module av
!**********************************************************************!
!
!  Purpose:
!    The artificial viscosity (AV) method of the equation sheet, one
!    place at a time: the face update (Step 1, velocity and position),
!    the cell update (Step 1 density, Step 2 energy), and the cell
!    state (pressure and sound speed from the EOS, the artificial
!    viscosity q, and the cell's CFL time step).
!
!    Each routine sees one place and its neighbors, a CHUNK of the
!    database passed straight in, read-only:
!
!       call face_step ( database(:,i-1:i+1), dth, dt, u_new, x_new )
!       call cell_step ( database(:,i-2:i+2), dt, rho_new, e_new )
!       call cell_state( database(:,i-2:i+2), BL, BQ, p, c, q, dtk, &
!                        d, tensile, spalled, pbreak, void, ierr )
!
!    and returns only the new values; the loop in maincode section 7
!    writes them back (the WRITE-BACK RULE in shock_mod). A routine
!    here never writes the database, which the compiler enforces
!    (intent(in)), so the physics can not reach past its chunk.
!
!    Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa,
!    e in (km/s)^2, masses in g/cm^3*mm (per unit area).
!
!  References:
!    Equation sheet, Hydrocode_Eqns_rev-0: Step 1, Step 2, Artificial
!    Viscosity, Time Step (CFL), Boundary Conditions, One Cycle.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/15/26    D. E. Kittell        Original code
!                (with Claude)
!    10/16/26    D. E. Kittell        Spall: intact cells hold tension
!                (with Claude)        to -spall_strength, then break
!                                     for good (damage slot D)
!    10/16/26    D. E. Kittell        Kinetic energy term factored,
!                (with Claude)        (a-b)(a+b) (round-off review)
!
!**********************************************************************!
!
!  READING A CHUNK
!  ===============
!  A chunk keeps the database's own layout, centered on the place
!  being updated (index 0). For a FACE, the cells on either side are
!  -1 and +1. For a CELL, its faces are -1 and +1 and the neighbor
!  cells are -2 and +2:
!
!     face chunk f(:,-1:1)            cell chunk c(:,-2:2)
!
!        -1     0     +1               -2    -1     0    +1    +2
!       cell  face   cell             cell  face  cell  face  cell
!       k     k+1/2  k+1              k-1  k-1/2   k   k+1/2  k+1
!
!  so, e.g., c(jp,+2) is the pressure in cell k+1 and f(ju,0) is the
!  velocity of the face itself.
!
!  At the two ends a neighbor is a ghost cell with M = P = q = 0
!  (equation sheet, Boundary Conditions). The formulas below need no
!  special case for it: the end face gets half a real cell's mass and
!  zero stress from the void, which is a free surface.
!
!**********************************************************************!
use bits,  only: dp, int32, zero, half, one
use shock, only: nvar, jx, ju, ju_old, jmf, jm, jrho, je, &
   jp, jq, jrho_old, jr0, jc0, js1, js2, jg0, jdam, jsp
use eos,   only: mg_pressure, mg_soundspeed, eos_ok, eos_bad_soundspeed
implicit none
private

public :: face_step, cell_step, cell_state, cell_dt

contains

   !******************************************************************!
   ! Step 1, one face: the velocity from n-1/2 to n+1/2, then the     !
   ! position from n to n+1 (the mesh moves with the material).       !
   !                                                                  !
   !    u(n+1/2) = u(n-1/2) + dth/mf * [ (P_k - P_k+1) + (q_k - q_k+1) ]
   !    x(n+1)   = x(n)     + u(n+1/2) * dt                           !
   !                                                                  !
   ! mf = (M_k + M_k+1)/2 is the face (node) mass, so dth/mf is the   !
   ! sheet's 2*dt/(M_k + M_k+1). dth is the time between the two      !
   ! half steps, (dt(n-1) + dt(n))/2: time-centered when dt changes   !
   ! from cycle to cycle, and exactly dt when it does not.            !
   ! Units: us * GPa / (g/cm^3*mm) = km/s.                            !
   !******************************************************************!
   pure subroutine face_step( f, dth, dt, u_new, x_new )
   implicit none
   real(kind=dp), intent(in)  :: f(nvar,-1:1)   ! cell, FACE, cell
   real(kind=dp), intent(in)  :: dth            ! us, half step to half step
   real(kind=dp), intent(in)  :: dt             ! us, this cycle's step
   real(kind=dp), intent(out) :: u_new          ! km/s, u at n+1/2
   real(kind=dp), intent(out) :: x_new          ! mm,   x at n+1

   u_new = f(ju,0) + (dth/f(jmf,0))*( (f(jp,-1) - f(jp,1)) + &
                                      (f(jq,-1) - f(jq,1)) )
   x_new = f(jx,0) + u_new*dt
   end subroutine face_step

   !******************************************************************!
   ! Step 1 (density) and Step 2 (energy), one cell. Run AFTER every  !
   ! face has its new x and u, and BEFORE any cell's P or q changes:  !
   ! the energy of cell k uses P and q at time n in cells k-1, k, k+1.!
   !                                                                  !
   !    rho(n+1) = M_k / ( x(k+1/2) - x(k-1/2) )        at n+1        !
   !                                                                  !
   !    e(n+1) = e(n) + dt/M_k * [ sig(k-1/2)*u(k-1/2)                !
   !                             - sig(k+1/2)*u(k+1/2) ]  u at n+1/2  !
   !           + 1/8 * [ (u(k+1/2)+u(k-1/2))**2 at n-1/2              !
   !                   - (u(k+1/2)+u(k-1/2))**2 at n+1/2 ]            !
   !                                                                  !
   ! where sig is the stress pushing on a face, as the cell sees it:  !
   ! the mass-weighted pressure of the two cells plus their averaged  !
   ! q. The first bracket is the work done by the face stresses, the  !
   ! second the change in the cell's kinetic energy (1/2)*ubar**2.    !
   ! (Equation sheet: "easiest place for mistakes".)                  !
   !******************************************************************!
   pure subroutine cell_step( c, dt, rho_new, e_new )
   implicit none
   real(kind=dp), intent(in)  :: c(nvar,-2:2)   ! cell,face,CELL,face,cell
   real(kind=dp), intent(in)  :: dt             ! us, this cycle's step
   real(kind=dp), intent(out) :: rho_new        ! g/cm^3, at n+1
   real(kind=dp), intent(out) :: e_new          ! (km/s)^2, at n+1
   real(kind=dp) :: mk, ml, mr                  ! cell masses k, k-1, k+1
   real(kind=dp) :: sigl, sigr                  ! face stresses, GPa
   real(kind=dp) :: work, dke                   ! the two brackets
   real(kind=dp) :: ua, ub                      ! face-velocity sums

   !*** Density from the new face positions.
   rho_new = c(jm,0)/( c(jx,1) - c(jx,-1) )

   !*** Face stresses (a ghost has M = P = q = 0, so the stress the
   !*** void puts on an end face is zero, apart from half of q).
   mk = c(jm, 0)
   ml = c(jm,-2)
   mr = c(jm, 2)
   sigl = ( mk*c(jp,-2) + ml*c(jp,0) )/( mk + ml ) + half*( c(jq,0) + c(jq,-2) )
   sigr = ( mr*c(jp,0) + mk*c(jp,2) )/( mk + mr ) + half*( c(jq,0) + c(jq, 2) )

   !*** Work by the faces, and the change in kinetic energy.
   work = (dt/mk)*( sigl*c(ju,-1) - sigr*c(ju,1) )
   !*** The kinetic energy term, 1/8*(a**2 - b**2), written as
   !*** 1/8*(a - b)*(a + b): the same number, but it never squares two
   !*** nearly equal sums and then subtracts them (round-off review,
   !*** 10/16/26: measured 2x closer to a quad-precision run).
   ua   = c(ju_old,1) + c(ju_old,-1)            ! 2*ubar at n-1/2
   ub   = c(ju,    1) + c(ju,    -1)            ! 2*ubar at n+1/2
   dke  = 0.125_dp*( ua - ub )*( ua + ub )
   e_new = c(je,0) + work + dke
   end subroutine cell_step

   !******************************************************************!
   ! The new state of one cell, after cell_step, in the order of the  !
   ! equation sheet (One Cycle, d and e), with bitwhiz's spall rule:  !
   !                                                                  !
   !   1. P(n+1) from the EOS at rho(n+1), e(n+1). In expansion this  !
   !      may be negative: an intact cell holds tension.              !
   !   2. SPALL. Each cell is intact (D = 0) or broken (D = 1):       !
   !        intact, P >= -spall_strength : keep P, tension and all    !
   !        intact, P <  -spall_strength : it BREAKS now (spalled),   !
   !                                       D = 1 and P = 0            !
   !        broken                       : P = max(P, 0), forever;    !
   !                                       it can be squeezed and     !
   !                                       shocked, never pulled      !
   !      spall_strength = 0 gives the project's P >= 0 rule.         !
   !   3. c(n+1) from the EOS at the pressure kept (or a void, below) !
   !   4. q(n+1), only while the cell is being squeezed:              !
   !         du = u(k-1/2) - u(k+1/2)   (n+1/2; > 0 = compressing)    !
   !         q  = BL*rho*c*|du| + BQ*rho*du**2   if du > 0 and rho up !
   !   5. the cell's CFL time step, dt_k                              !
   !                                                                  !
   ! pbreak reports how hard a cell was pulled on the step it broke:  !
   ! the EOS pressure then, before the floor. A cell can overshoot    !
   ! its strength within one step (fast release waves), and the run  !
   ! summary reports the deepest such value.                          !
   !                                                                  !
   ! A round-off floor under the spall strength. A cell that only     !
   ! translates can come out a hair wider than it started, in the     !
   ! last digit, and the EOS then gives P of order -1e-13 GPa. So a   !
   ! cell breaks, or counts as "tensile" for the first-tension flag,  !
   ! only below -1e-9 of its bulk modulus R0*C0**2 (about -2e-7 GPa   !
   ! for Ta), even with spall_strength = 0. Round-off measured on the !
   ! class deck: -3e-12 GPa at worst, 5 orders of magnitude below.    !
   !                                                                  !
   ! VOID CELLS. A broken cell that keeps stretching (e.g. the last   !
   ! cell at a free surface after the release) has P = 0. For the     !
   ! class materials the expansion cubic keeps c**2 > 0 there at any  !
   ! size, but unusual materials can reach a point where c -> 0. Such !
   ! a cell is treated as VOID: P = q = c = 0, broken, and its time   !
   ! step comes from its speed alone, dx/|ubar|. It keeps its mass    !
   ! and momentum, and the EOS takes over again if it is squeezed.    !
   !                                                                  !
   ! If the EOS fails in any other way, ierr says why and the other   !
   ! results are not to be used (signaling NaN); the caller stops.    !
   !******************************************************************!
   pure subroutine cell_state( c, BL, BQ, p, cs, q, dtk, dnew, tensile, &
      spalled, pbreak, void, ierr )
   implicit none
   real(kind=dp), intent(in)  :: c(nvar,-2:2)   ! cell,face,CELL,face,cell
   real(kind=dp), intent(in)  :: BL, BQ         ! viscosity coefficients
   real(kind=dp), intent(out) :: p              ! GPa, >= -spall_strength
   real(kind=dp), intent(out) :: cs             ! km/s, sound speed
   real(kind=dp), intent(out) :: q              ! GPa, artificial viscosity
   real(kind=dp), intent(out) :: dtk            ! us, this cell's CFL limit
   real(kind=dp), intent(out) :: dnew           ! damage D after this step
   logical, intent(out)       :: tensile        ! P below the round-off floor
   logical, intent(out)       :: spalled        ! broke on THIS step
   real(kind=dp), intent(out) :: pbreak         ! GPa, the EOS pressure as
                                                ! it broke (before the
                                                ! floor), else zero
   logical, intent(out)       :: void           ! treated as void (above)
   integer(kind=int32), intent(out) :: ierr     ! from the EOS
   real(kind=dp), parameter :: ftens = 1.0e-9_dp ! round-off floor / K0
   real(kind=dp) :: rho, du, ubar, pfail
   logical :: broken

   tensile = .false.
   spalled = .false.
   pbreak  = zero
   void    = .false.
   rho     = c(jrho,0)
   broken  = ( c(jdam,0) > half )
   dnew    = c(jdam,0)

   !*** 1. Pressure.
   call mg_pressure( rho, c(je,0), c(jr0,0), c(jc0,0), c(js1,0), &
      c(js2,0), c(jg0,0), p, ierr )
   if ( ierr /= eos_ok ) then
      cs  = p                                   ! NaN, like p
      q   = p
      dtk = p
      return
   end if

   !*** 2. Spall: break an intact cell pulled past its strength, and
   !***    floor the pressure of any broken cell.
   pfail   = max( c(jsp,0), ftens*c(jr0,0)*c(jc0,0)**2 )
   tensile = ( p < -ftens*c(jr0,0)*c(jc0,0)**2 )
   if ( .not. broken .and. p < -pfail ) then
      broken  = .true.
      spalled = .true.
      pbreak  = p                               ! how far past its strength
      dnew    = one
   end if
   if ( broken ) p = max( p, zero )

   !*** 3. Sound speed at the pressure kept.
   call mg_soundspeed( rho, p, c(jr0,0), c(jc0,0), c(js1,0), c(js2,0), &
      c(jg0,0), cs, ierr )
   if ( ierr == eos_bad_soundspeed .and. .not. ( p > zero ) .and. &
        rho < c(jr0,0) ) then                   ! stretched past c = 0
      void = .true.
      if ( .not. broken ) spalled = .true.      ! it broke by stretching
      dnew = one
      ierr = eos_ok
      p    = zero
      cs   = zero
      q    = zero
      ubar = abs( half*( c(ju,-1) + c(ju,1) ) )
      if ( ubar > zero ) then
         dtk = ( c(jx,1) - c(jx,-1) )/ubar
      else
         dtk = huge(one)                        ! a void at rest: no limit
      end if
      return
   end if
   if ( ierr /= eos_ok ) then
      q   = cs                                  ! NaN, like cs
      dtk = cs
      return
   end if

   !*** 4. Artificial viscosity.
   du = c(ju,-1) - c(ju,1)
   if ( du > zero .and. rho - c(jrho_old,0) > zero ) then
      q = BL*rho*cs*abs(du) + BQ*rho*du*du
   else
      q = zero
   end if

   !*** 5. This cell's time step.
   dtk = cell_dt( c, cs )
   end subroutine cell_state

   !******************************************************************!
   ! One cell's CFL time step (equation sheet, Time Step):            !
   !                                                                  !
   !    dt_k = ( x(k+1/2) - x(k-1/2) ) / ( |ubar| + c )               !
   !                                                                  !
   ! with ubar the average of the two face velocities: the time for a !
   ! sound wave, carried along with the flow, to cross the cell. The  !
   ! time step is CFL * (the smallest dt_k), set by the caller.       !
   ! cs is passed in, so section 6 can use it at t = 0 (c = C0).      !
   !******************************************************************!
   pure function cell_dt( c, cs ) result(dtk)
   implicit none
   real(kind=dp), intent(in) :: c(nvar,-2:2)    ! cell,face,CELL,face,cell
   real(kind=dp), intent(in) :: cs              ! km/s, the cell's c
   real(kind=dp) :: dtk                         ! us
   dtk = ( c(jx,1) - c(jx,-1) )/( abs( half*( c(ju,-1) + c(ju,1) ) ) + cs )
   end function cell_dt

end module av

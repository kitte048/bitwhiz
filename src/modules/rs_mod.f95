module rs
!**********************************************************************!
!
!  Purpose:
!    Method RS: Godunov's method with the acoustic Riemann solver of
!    U7, one place at a time, as the RS equation sheet writes it
!    (Equation_Sheets/Hydrocode_RS_rev-0, v4). Every cell carries an
!    average state (rho, u, e, P, c); every face carries the Riemann
!    solution between its two cells (u*, P*), which moves the face and
!    is the flux into both of them.
!
!       call rs_face_states( database(:,i-2:i+2), dt, order, &
!                            ul, ur, pl, pr )
!       call riemann_face ( database(:,i-1:i+1), ustar, pstar )
!       call rs_cell_step ( database(:,i-2:i+2), dt, rho_new, u_new, e_new )
!       call rs_state     ( database(:,i-2:i+2), p, cs, dtk, d, &
!                           tensile, spalled, pbreak, void, ierr )
!
!    As in module av, each routine sees only its chunk, read-only, and
!    returns the new values; the loops in maincode section 7 write
!    them back (the WRITE-BACK RULE in shock_mod).
!
!    Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa,
!    e in (km/s)^2, masses in g/cm^3*mm (per unit area). An impedance
!    Z = rho*c is in g/cm^3*km/s, so Z*u is in GPa.
!
!  References:
!    RS equation sheet, Steps 1-4, Time Step, Boundary Conditions.
!    U7 (Acoustic Solution); S. K. Godunov, Mat. Sb. 47 (1959);
!    D. E. Kittell et al., Propellants Explos. Pyrotech. 45 (2020)
!    295-315 (star values stored at the faces; p. 297, a reaction's
!    source held over a step, here per cell and per step).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/19/26    D. E. Kittell        Original code
!                (with Claude)
!    10/20/26    D. E. Kittell        Second order (order = 2, the
!                (with Claude)        default): MUSCL-Hancock face
!                                     states with a Van Leer limiter
!
!    11/04/26    D. E. Kittell        A burn: the reaction's source in
!                (with Claude)        the order-2 predictor (optional
!                                     src), and a burning cell's state
!                                     from the HVRB closure (optional
!                                     brn, through cell_pressure)
!
!**********************************************************************!
use bits,  only: dp, int32, zero, half, one
use shock, only: nvar, jx, jm, jrho, je, jp, jc, juc, ju_star, jp_star, &
   ju_lf, ju_rf, jp_lf, jp_rf
use eos,   only: eos_ok
use av,    only: cell_pressure
use hvrb,  only: burn_cell_t
implicit none
private

public :: rs_face_states, riemann_face, rs_cell_step, rs_state, rs_cell_dt

contains

   !******************************************************************!
   ! Step 1, one cell: the u and P it offers the Riemann              !
   ! problems on its LEFT face (ul, pl) and its RIGHT face (ur, pr).  !
   !                                                                  !
   ! order = 1: the cell's own u and P on both faces (first-order     !
   ! Godunov; the copies are exact, so the results are the same bits).!
   !                                                                  !
   ! order = 2, MUSCL-Hancock (van Leer 1979):                        !
   !  a. a slope per unit mass for u and for P, from the differences  !
   !     to the two neighbors (mass distances, so a mesh that changes !
   !     zone size at an interface is handled):                       !
   !        a = (W(k) - W(k-1)) / ((M(k-1) + M(k))/2)                 !
   !        b = (W(k+1) - W(k)) / ((M(k) + M(k+1))/2)                 !
   !     limited by Van Leer's harmonic mean:                         !
   !        s = 2*a*b/(a + b)  if a*b > 0,   else s = 0               !
   !     so a peak or a trough gets no slope (no new extremum, no     !
   !     ringing). A cell beside a ghost gets s = 0 (the free         !
   !     surfaces stay first order).                                  !
   !  b. the values at the two faces, W -/+ M*s/2, each advanced by   !
   !     half a step with the cell's own acoustic equations,          !
   !        du/dt = -dP/dh,   dP/dt = -Z**2 du/dh,   Z = rho*c,       !
   !     so the face states are centered at n+1/2.                    !
   ! Only u and P are needed: the acoustic Riemann solver takes Z     !
   ! from the cell averages. Both are continuous across a material    !
   ! interface, so the slopes may span one (V, which jumps there, is  !
   ! never reconstructed).                                            !
   !******************************************************************!
   pure subroutine rs_face_states( c, dt, order, ul, ur, pl, pr, src )
   implicit none
   real(kind=dp), intent(in)  :: c(nvar,-2:2)   ! cell,face,CELL,face,cell
   real(kind=dp), intent(in)  :: dt             ! us, this cycle's step
   integer(kind=int32), intent(in) :: order     ! 1 or 2
   real(kind=dp), intent(out) :: ul, ur         ! km/s, u on left/right face
   real(kind=dp), intent(out) :: pl, pr         ! GPa,  P on left/right face
   real(kind=dp), intent(in), optional :: src   ! GPa/us, the reaction's
                                                ! source in dP/dt (a cell
                                                ! that burns this step)
   real(kind=dp) :: mk, su, sp, du, dp_, z2

   if ( order < 2 ) then
      ul = c(juc,0)
      ur = c(juc,0)
      pl = c(jp,0)
      pr = c(jp,0)
      return
   end if

   mk = c(jm,0)
   if ( .not. ( c(jm,-2) > zero ) .or. .not. ( c(jm,2) > zero ) ) then
      su = zero                                 ! beside a ghost
      sp = zero
   else
      su = vanleer( ( c(juc,0) - c(juc,-2) )/( half*( c(jm,-2) + mk ) ), &
                    ( c(juc,2) - c(juc, 0) )/( half*( mk + c(jm,2) ) ) )
      sp = vanleer( ( c(jp,0)  - c(jp,-2)  )/( half*( c(jm,-2) + mk ) ), &
                    ( c(jp,2)  - c(jp, 0)  )/( half*( mk + c(jm,2) ) ) )
   end if

   !*** Half a step of the cell's own acoustic equations.
   z2  = ( c(jrho,0)*c(jc,0) )**2
   du  = -half*dt*sp
   dp_ = -half*dt*z2*su
   !*** A cell that burns this step: the reaction's source too, dP/dt =
   !*** -Z**2 du/dh + rho c**2 sigma r, held over the step as Z is
   !*** (module burn, ONE CYCLE, METHOD RS). Absent for any other cell,
   !*** whose face states are the same bits as without a burn.
   if ( present( src ) ) dp_ = dp_ + half*dt*src
   ul  = c(juc,0) - half*mk*su + du
   ur  = c(juc,0) + half*mk*su + du
   pl  = c(jp,0)  - half*mk*sp + dp_
   pr  = c(jp,0)  + half*mk*sp + dp_
   end subroutine rs_face_states

   !*** Van Leer's limiter: the harmonic mean of two one-sided slopes
   !*** when they agree in sign, else zero.
   pure function vanleer( a, b ) result(s)
   implicit none
   real(kind=dp), intent(in) :: a, b
   real(kind=dp) :: s
   if ( a*b > zero ) then
      s = 2.0_dp*a*b/( a + b )
   else
      s = zero
   end if
   end function vanleer

   !******************************************************************!
   ! Step 2, one face: the acoustic Riemann problem between the cell  !
   ! on its left (L) and the cell on its right (R), with each side's  !
   ! impedance Z = rho*c at time n held fixed for the step, and the u !
   ! and P each side offers this face (rs_face_states: the cell       !
   ! values for order 1, MUSCL-Hancock for order 2):                  !
   !                                                                  !
   !    u* = ( ZL*uL + ZR*uR + PL - PR ) / ( ZL + ZR )                !
   !    P* = ( ZR*PL + ZL*PR + ZL*ZR*(uL - uR) ) / ( ZL + ZR )        !
   !                                                                  !
   ! A GHOST cell (M = 0) is void: P = Z = 0 and u = 0. Its rho, c    !
   ! and u are never read (they are signaling NaN). With ZL = 0 the   !
   ! same two lines give the free surface, u* = uR - PR/ZR, P* = 0.   !
   !                                                                  !
   ! ZERO IMPEDANCE. A void cell (c = 0) has Z = 0 too, so a void     !
   ! cell beside a ghost or another void cell makes ZL + ZR = 0. Then !
   ! P* = 0 and u* = (uL + uR)/2, a ghost taking its neighbor's u     !
   ! (RS sheet, Boundary Conditions). The class materials never get   !
   ! there.                                                           !
   !******************************************************************!
   pure subroutine riemann_face( f, ustar, pstar )
   implicit none
   real(kind=dp), intent(in)  :: f(nvar,-1:1)   ! cell, FACE, cell
   real(kind=dp), intent(out) :: ustar          ! km/s, u* (n+1/2)
   real(kind=dp), intent(out) :: pstar          ! GPa,  P* (n+1/2)
   real(kind=dp) :: zl, zr, pl, pr, ul, ur, zs
   logical :: ghostl, ghostr

   ghostl = .not. ( f(jm,-1) > zero )
   ghostr = .not. ( f(jm, 1) > zero )
   zl = zero
   pl = zero
   ul = zero
   zr = zero
   pr = zero
   ur = zero
   if ( .not. ghostl ) then                     ! the left cell's RIGHT face
      zl = f(jrho,-1)*f(jc,-1)
      pl = f(jp_rf,-1)
      ul = f(ju_rf,-1)
   end if
   if ( .not. ghostr ) then                     ! the right cell's LEFT face
      zr = f(jrho,1)*f(jc,1)
      pr = f(jp_lf,1)
      ur = f(ju_lf,1)
   end if

   zs = zl + zr
   if ( zs > zero ) then
      ustar = ( zl*ul + zr*ur + pl - pr )/zs
      pstar = ( zr*pl + zl*pr + zl*zr*( ul - ur ) )/zs
   else                                         ! zero impedance (above)
      if ( ghostl ) ul = ur
      if ( ghostr ) ur = ul
      ustar = half*( ul + ur )
      pstar = zero
   end if
   end subroutine riemann_face

   !******************************************************************!
   ! Steps 3 and 4, one cell, AFTER every face has its u*, P* and new !
   ! x (loop 1). The faces' fluxes in, the cell's average state out:  !
   !                                                                  !
   !    rho(n+1) = M / ( x(k+1/2) - x(k-1/2) )          at n+1        !
   !    u(n+1)   = u(n) - dt/M * ( P*(k+1/2) - P*(k-1/2) )            !
   !    E(n+1)   = E(n) - dt/M * ( (P*u*)(k+1/2) - (P*u*)(k-1/2) )    !
   !    e(n+1)   = E(n+1) - u(n+1)**2/2,      E = e + u**2/2          !
   !                                                                  !
   ! Each face's flux leaves one cell and enters the next, so mass,   !
   ! momentum and total energy are conserved to round-off (P* = 0 at  !
   ! both free surfaces).                                             !
   !******************************************************************!
   pure subroutine rs_cell_step( c, dt, rho_new, u_new, e_new )
   implicit none
   real(kind=dp), intent(in)  :: c(nvar,-2:2)   ! cell,face,CELL,face,cell
   real(kind=dp), intent(in)  :: dt             ! us, this cycle's step
   real(kind=dp), intent(out) :: rho_new        ! g/cm^3, at n+1
   real(kind=dp), intent(out) :: u_new          ! km/s,   at n+1
   real(kind=dp), intent(out) :: e_new          ! (km/s)^2, at n+1
   real(kind=dp) :: dtm, et

   dtm     = dt/c(jm,0)
   rho_new = c(jm,0)/( c(jx,1) - c(jx,-1) )
   et      = c(je,0) + half*c(juc,0)*c(juc,0)
   u_new   = c(juc,0) - dtm*( c(jp_star,1) - c(jp_star,-1) )
   et      = et - dtm*( c(jp_star, 1)*c(ju_star, 1) - &
                        c(jp_star,-1)*c(ju_star,-1) )
   e_new   = et - half*u_new*u_new
   end subroutine rs_cell_step

   !******************************************************************!
   ! The new state of one cell, after rs_cell_step has been written   !
   ! back: P (with bitwhiz's spall rule), c and D from cell_pressure  !
   ! (module av; the same rules as method AV), and the cell's time    !
   ! step. There is no q.                                             !
   !******************************************************************!
   pure subroutine rs_state( c, p, cs, dtk, dnew, tensile, spalled, &
      pbreak, void, ierr, brn, cflag )
   implicit none
   real(kind=dp), intent(in)  :: c(nvar,-2:2)   ! cell,face,CELL,face,cell
   real(kind=dp), intent(out) :: p              ! GPa, >= -spall_strength
   real(kind=dp), intent(out) :: cs             ! km/s, sound speed
   real(kind=dp), intent(out) :: dtk            ! us, this cell's limit
   real(kind=dp), intent(out) :: dnew           ! damage D after this step
   logical, intent(out)       :: tensile        ! P below the round-off floor
   logical, intent(out)       :: spalled        ! broke on THIS step
   real(kind=dp), intent(out) :: pbreak         ! GPa, EOS pressure as it
                                                ! broke, else zero
   logical, intent(out)       :: void           ! treated as void
   integer(kind=int32), intent(out) :: ierr     ! from the EOS
   type(burn_cell_t), intent(in), optional :: brn  ! a burning cell's
                                                ! burn (module av)
   integer(kind=int32), intent(out), optional :: cflag ! its c's rule

   call cell_pressure( c(:,0), p, cs, dnew, tensile, spalled, pbreak, &
      void, ierr, brn, cflag )
   if ( ierr /= eos_ok ) then
      dtk = cs                                  ! NaN, like cs
      return
   end if
   dtk = rs_cell_dt( c, cs )
   end subroutine rs_state

   !******************************************************************!
   ! One cell's time step limit (RS sheet, Time Step):                !
   !                                                                  !
   !    dt_k = ( x(k+1/2) - x(k-1/2) ) / c   ( = M/Z )                !
   !                                                                  !
   ! In the mass coordinate h the waves leave a face at -Z and +Z; the!
   ! mesh moves with the material, so |u| does not enter. A void cell !
   ! (c = 0) uses dx/|u|, as in method AV, and has no limit at rest.  !
   ! The time step is CFL * (the smallest dt_k), set by the caller.   !
   !******************************************************************!
   pure function rs_cell_dt( c, cs ) result(dtk)
   implicit none
   real(kind=dp), intent(in) :: c(nvar,-2:2)    ! cell,face,CELL,face,cell
   real(kind=dp), intent(in) :: cs              ! km/s, the cell's c
   real(kind=dp) :: dtk                         ! us
   if ( cs > zero ) then
      dtk = ( c(jx,1) - c(jx,-1) )/cs
   else if ( abs( c(juc,0) ) > zero ) then
      dtk = ( c(jx,1) - c(jx,-1) )/abs( c(juc,0) )
   else
      dtk = huge(one)
   end if
   end function rs_cell_dt

end module rs

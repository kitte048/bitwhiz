module temperature
!**********************************************************************!
!
!  Purpose:
!    Temperature, for the materials whose model carries it (deck: eos =
!    mie_gruneisen_t, with CV and T0). Each such cell carries its own
!    cold energy e_c, from step to step, and its temperature T:
!
!       T = T0*exp(G0*eta) + ( e - e_c(eta) )/C_V,   eta = 1 - R0*V
!
!    P and c do not depend on T in this model (they are Mie-Gruneisen's,
!    module eos, the same code and the same bits), so T is a diagnostic
!    for now: the tracer file's TK columns, the history file's TK and the
!    run's T range. HVRB will make it an input.
!
!       call alloc_temperature( kerr )        once, after the t = 0 state
!       call temp_update( use_team, time, ncycle, kbad )   every cycle
!       tk(k)                                 cell k's T, K (0: no T)
!
!    A deck without mie_gruneisen_t allocates nothing here and runs
!    exactly as before, bit for bit.
!
!  Units, as everywhere in bitwhiz: e and e_c in (km/s)^2 = kJ/g, so
!  C_V is in kJ/(g K) here (the deck's CV, J/(g K), over 1000; module
!  deck, resolve_deck); T and T0 in K.
!
!  References:
!    doc/design/materials.md (approved 11/03/26): the cold curve, the
!    temperature, and the per-cell method ("plan C"). The temperature
!    calculation is D. E. Kittell's; the formulas were checked
!    symbolically (sympy: the isentropes, the Maxwell relation,
!    (dP/dT)_V = rho*Gamma*C_V) and against the G1 gold-standard data
!    before any code (PMMA to 0.006 K).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/03/26    D. E. Kittell        Original code
!                (with Claude)
!    11/04/26    D. E. Kittell        For the burn (module burn): one
!                (with Claude)        cell's cold curve moved on its
!                                     own (temp_cold_cell), before the
!                                     pressure that needs it; T of a
!                                     burning cell, vartheta/C_V
!                                     (temp_update's lam and q)
!    11/05/26    D. E. Kittell        cold_step: snan_dp (module bits),
!                (with Claude)        not ieee_value, for gfortran 8
!    11/05/26    D. E. Kittell        temp_update: a burning cell's
!                (with Claude)        solid where it is held (optional
!                                     rhold, eshold; module burn)
!
!**********************************************************************!
!
!  THE COLD CURVE, AND HOW A CELL CARRIES IT
!  =========================================
!  Mie-Gruneisen with rho*Gamma = R0*G0 is P = R0*G0*e + Pi(V), where Pi
!  is the part that depends on volume alone (module eos calls it phi:
!  P_H - R0*G0*e_H in compression, the cubic in rho - R0 in tension).
!  The cold curve is the isentrope through (V0, e = 0); as an ODE in
!  eta (de = -P dV along an isentrope, and d eta = -R0 dV),
!
!     de_c/d eta = G0*e_c + Pi(eta)/R0,      e_c(0) = 0
!
!  It is linear, so from eta_1 to eta_2 its solution is exact:
!
!     e_c(eta_2) = exp(G0*(eta_2 - eta_1))*e_c(eta_1)
!                + integral from eta_1 to eta_2 of
!                     exp(G0*(eta_2 - s))*Pi(s)/R0 ds
!
!  Only the integral is approximated: 3-point Gauss-Legendre, exact for
!  polynomials of degree 5, on pieces no longer than deta_max (below).
!  Each cell keeps e_c and the eta it belongs to, etac, and moves both
!  to its new eta once per step. e_c is a function of eta alone, so
!  however a cell moves (shocked, rung, released into tension and back)
!  the e_c it carries must stay on the curve; the unit test drives one
!  cell through such a path, 2,000 steps, and finds it on the curve to
!  1e-13 (tests/test_temp.f95 against tests/temp_reference.py).
!
!  Pi comes from module eos itself: mg_pressure at e = 0 returns
!  R0*G0*0 + phi = phi, bit for bit. So the temperature uses the tested
!  pressure code (the same Hugoniot, the same cubic in tension, the
!  same guards), and there is no second copy of it to drift apart.
!
!***NOTE: why carry e_c at all (and not a table, or the integral from
! V0 every time)? The integral from V0 is too slow, every cell every
! step; a table per material breaks once constants are graded cell by
! cell (TODO.md, section 7). A cell that carries its own e_c, as it
! carries its own e, needs neither. The design note has the numbers.
!
!***NOTE: why etac, and not the cell's old density? The update needs
! the eta where the carried e_c holds. Keeping it here, with e_c,
! makes this module independent of how each method stores its old
! state (AV's rho_old, RS's ...): whatever the hydro did between two
! calls, e_c goes from where it was to where the cell is now.
!
!***NOTE: a cell that crosses eta = 0 in one step is integrated in two
! pieces, to 0 and from 0. Pi's 4th derivative jumps there (the cubic
! in tension matches the Hugoniot form through the 3rd, module eos), so
! no Gauss piece straddles it. A cell deep in tension (eta << 0, a
! broken cell stretched far) takes pieces in proportion to 1 - eta:
! there Pi changes on that scale, and a few pieces still do.
!
!***NOTE: a cell coming back from far tension starts again from V0.
! The propagator's growth factor, exp(G0*(eta_2 - eta_1)), is above 1
! whenever a cell is compressed: an error in the carried e_c (round-off
! at least) grows by it. Within the class problem's range that is a
! factor of 2 or 3 at most, but a broken cell stretched to 21 V0 (eta =
! -20) and squeezed back would multiply its round-off by exp(G0*20),
! about 1e17 for Al, and its T would be noise. This is the physics of
! the isentropes (their spread shrinks as exp(G0*eta) on the way out,
! so the carried value forgets where it came from), not a fault of the
! quadrature. So a cell whose carried e_c lies beyond V = 2 V0 (eta <
! eta_far = -1) and is compressed takes e_c(0) = 0 and integrates from
! V0 instead: at most 1/deta_max = 200 pieces, |eta|/(1 - eta) < 1, and
! only for such cells. From there to anywhere the growth is at most
! exp(1.5*G0), 20 for Al. (Measured: out to eta = -20 and back to -0.2,
! 7e2 relative error carried, 1e-13 restarted.)
!
!**********************************************************************!
use bits,  only: dp, int32, zero, half, one
use shock, only: kmax, nlay, layer, database, icell, jx, jrho, je, jr0, &
   jc0, js1, js2, jg0, jdam, eos_mie_gruneisen_t
use eos,   only: mg_pressure, eos_ok
implicit none
private

public :: temp_in_run, alloc_temperature, dealloc_temperature, &
   temp_update, cold_step, temp_of, eta_of, temp_cold_cell
public :: tk, ec, etac, nt, kt, tmin_run, tmax_run, hot_k, hot_time, &
   hot_cycle, hot_x, cv, t0

!**********************************************************************!
! Data dictionary: the quadrature.
!
!  3-point Gauss-Legendre on [-1, 1]: nodes 0 and +-sqrt(3/5), weights
!  8/9 and 5/9. deta_max is the longest piece. The error of one piece
!  goes as its length**7, so of a whole step as length**6: measured on
!  the four class materials from eta = 0 to 0.1 in one step (float64
!  against 50 digits), 0.02 gives 3e-11, 0.01 gives 4e-13, 0.005 gives
!  6e-15 (round-off). In an explicit code a step's Delta eta is small
!  (below 0.005 almost always, a few hundredths in a shock front), so
!  most steps are one piece, three Pi evaluations.
!**********************************************************************!
real(kind=dp), parameter, dimension(3) :: xg = (/ &
   -0.77459666924148337704_dp, 0.0_dp, 0.77459666924148337704_dp /)
real(kind=dp), parameter, dimension(3) :: wg = (/ &
   5.0_dp/9.0_dp, 8.0_dp/9.0_dp, 5.0_dp/9.0_dp /)
real(kind=dp), parameter :: deta_max = 0.005_dp
real(kind=dp), parameter :: eta_far  = -1.0_dp  ! V = 2 V0: compressed
                                     ! from beyond it, start again at V0

!**********************************************************************!
! Data dictionary: each cell's temperature state, cell k at index k
! (1 to kmax; ghosts have none). Allocated only when some material
! carries T. A cell whose material does not keeps zeros: tk = 0 there,
! which the tracer and history files write as is (design note,
! decision 2). Written only by this module (temp_update), cell by cell,
! so the threads never share a value.
!**********************************************************************!
real(kind=dp), allocatable, protected :: tk(:)    ! T, K
real(kind=dp), allocatable, protected :: ec(:)    ! e_c, kJ/g, at etac
real(kind=dp), allocatable, protected :: etac(:)  ! the eta e_c holds at
real(kind=dp), allocatable, protected :: cv(:)    ! C_V, kJ/(g K)
real(kind=dp), allocatable, protected :: t0(:)    ! T0, K
integer(kind=int32), allocatable, protected :: kt(:)  ! the cells with
                                                  ! T, left to right
integer(kind=int32), protected :: nt = 0          ! how many

!*** The run's temperature range, over every INTACT cell with T and
!*** every cycle so far, and where and when it was hottest (the first
!*** cycle, and on it the lowest cell, that reached tmax_run).
!***
!***NOTE: why intact cells only. A broken cell (spall, D = 1; module av)
! has its pressure floored at 0, so the hydro does no work on it as it
! opens, while its cold energy still follows its volume up the cold
! curve (it is a function of V). Its T, computed as everywhere else and
! written as is to the tracer and history files (design note, Edges),
! then falls, below 0 K for a cell stretched far: in G1 at 2.00 km/s,
! the PMMA's free-surface cell reaches -4,693 K. That is not the
! temperature of anything, so it does not set the run's range.
real(kind=dp), protected       :: tmin_run  = zero  ! K
real(kind=dp), protected       :: tmax_run  = zero  ! K
integer(kind=int32), protected :: hot_k     = 0     ! cell
real(kind=dp), protected       :: hot_time  = zero  ! us
integer(kind=int32), protected :: hot_cycle = 0     ! cycle
real(kind=dp), protected       :: hot_x     = zero  ! mm, cell center

contains

   !******************************************************************!
   ! True if some layer's material carries T. The deck's tables are   !
   ! all it needs, so the output files can ask before the database    !
   ! exists.                                                          !
   !******************************************************************!
   logical function temp_in_run()
   implicit none
   temp_in_run = .false.
   if ( nlay > 0 ) temp_in_run = &
      any( layer(1:nlay)%eos == eos_mie_gruneisen_t )
   end function temp_in_run

   !******************************************************************!
   ! A cell's eta from its density, exactly as module eos computes it:!
   ! (rho - R0)/rho, which is exactly 0 at rho = R0 for every R0 (see !
   ! mg_ref's note; 1 - R0/rho is not).                               !
   !******************************************************************!
   elemental function eta_of( rho, R0 ) result( eta )
   implicit none
   real(kind=dp), intent(in) :: rho, R0
   real(kind=dp) :: eta
   eta = ( rho - R0 )/rho
   end function eta_of

   !******************************************************************!
   ! The temperature from the state and the carried cold energy,      !
   !    T = T0*exp(G0*eta) + ( e - e_c )/C_V                          !
   ! T0*exp(G0*eta) is the principal isentrope's temperature (for     !
   ! rho*Gamma constant, d ln T/d ln rho = Gamma); (e - e_c)/C_V is   !
   ! the heat above it. bitwhiz starts every cell at e = 0, so the    !
   ! energy at (V0, T0) is 0 and the formula needs no other term.     !
   !******************************************************************!
   elemental function temp_of( eta, e, ecold, G0, cvk, T0k ) result( t )
   implicit none
   real(kind=dp), intent(in) :: eta      ! 1 - R0*V
   real(kind=dp), intent(in) :: e        ! specific internal energy, kJ/g
   real(kind=dp), intent(in) :: ecold    ! e_c at eta, kJ/g
   real(kind=dp), intent(in) :: G0       ! reference Gruneisen coefficient
   real(kind=dp), intent(in) :: cvk      ! C_V, kJ/(g K)
   real(kind=dp), intent(in) :: T0k      ! T at R0 and e = 0, K
   real(kind=dp) :: t                    ! K
   t = T0k*exp( G0*eta ) + ( e - ecold )/cvk
   end function temp_of

   !******************************************************************!
   ! Move a cold energy from eta1 to eta2: ec2 = e_c(eta2), given     !
   ! ec1 = e_c(eta1). Elemental, so the unit test can drive one cell, !
   ! or many, through any path. On any status but eos_ok (Pi could    !
   ! not be evaluated at a Gauss point, which a state the hydro       !
   ! accepted can not reach), ec2 is a signaling NaN, as module eos   !
   ! does it, so a caller that ignores ierr stops at the next use.    !
   !******************************************************************!
   elemental subroutine cold_step( eta1, eta2, ec1, R0, C0, S1, S2, G0, &
      ec2, ierr )
   use bits, only: snan_dp                     ! (not ieee_value: bit_mod)
   implicit none
   real(kind=dp), intent(in)  :: eta1    ! where ec1 holds
   real(kind=dp), intent(in)  :: eta2    ! where the cell is now
   real(kind=dp), intent(in)  :: ec1     ! e_c(eta1), kJ/g
   real(kind=dp), intent(in)  :: R0, C0, S1, S2, G0  ! as mg_eos
   real(kind=dp), intent(out) :: ec2     ! e_c(eta2), kJ/g
   integer(kind=int32), intent(out) :: ierr ! eos_ok, or why not

   ec2 = ec1
   if ( eta1 < eta_far .and. eta2 > eta1 ) then         ! back from far
      ec2 = zero                                         ! tension: from
      call piece( zero, eta2, ec2, R0, C0, S1, S2, G0, ierr ) ! V0 (NOTE)
   else if ( ( eta1 < zero .and. eta2 > zero ) .or. &
        ( eta1 > zero .and. eta2 < zero ) ) then
      call piece( eta1, zero, ec2, R0, C0, S1, S2, G0, ierr )  ! to V0,
      if ( ierr == eos_ok ) &
         call piece( zero, eta2, ec2, R0, C0, S1, S2, G0, ierr ) ! on
   else
      call piece( eta1, eta2, ec2, R0, C0, S1, S2, G0, ierr )
   end if
   if ( ierr /= eos_ok ) ec2 = snan_dp
   end subroutine cold_step

   !******************************************************************!
   ! The exact propagator from a to b (same side of eta = 0), on n    !
   ! equal pieces, each no longer than deta_max*(1 - min(a, b, 0)),   !
   ! with the integral by 3-point Gauss-Legendre on each piece.       !
   !******************************************************************!
   elemental subroutine piece( a, b, ecold, R0, C0, S1, S2, G0, ierr )
   implicit none
   real(kind=dp), intent(in)    :: a, b             ! eta, from and to
   real(kind=dp), intent(inout) :: ecold            ! e_c(a) in, e_c(b) out
   real(kind=dp), intent(in)    :: R0, C0, S1, S2, G0
   integer(kind=int32), intent(out) :: ierr
   integer(kind=int32) :: n, j, m        ! pieces, piece, Gauss point
   real(kind=dp) :: sa, sb               ! a piece's ends
   real(kind=dp) :: sm, h                ! its midpoint and half length
   real(kind=dp) :: s                    ! a Gauss point
   real(kind=dp) :: pis                  ! Pi(s), GPa
   real(kind=dp) :: q                    ! the weighted sum

   ierr = eos_ok
   n = max( 1_int32, ceiling( abs( b - a )/ &
       ( deta_max*( one - min( a, b, zero ) ) ), kind=int32 ) )
   sb = a
   do j = 1, n
      sa = sb
      if ( j == n ) then
         sb = b                          ! the last piece ends exactly at b
      else
         sb = a + ( b - a )*( real(j,dp)/real(n,dp) )
      end if
      sm = half*( sa + sb )
      h  = half*( sb - sa )
      q  = zero
      do m = 1, 3
         s = sm + h*xg(m)
         call mg_pressure( R0/( one - s ), zero, R0, C0, S1, S2, G0, pis, &
            ierr )                       ! P at e = 0 is Pi, bit for bit
         if ( ierr /= eos_ok ) return
         q = q + wg(m)*exp( G0*( sb - s ) )*pis
      end do
      ecold = exp( G0*( sb - sa ) )*ecold + h*q/R0
   end do
   end subroutine piece

   !******************************************************************!
   ! Allocate the temperature state, if some material carries T, and  !
   ! set it from the t = 0 state (call after maincode section 5b has  !
   ! filled the cells). Every cell starts at rho = R0 and e = 0, so   !
   ! eta = 0, e_c = 0 and T = T0 exactly; maincode's setup audit      !
   ! checks that it does. Increments kerr on failure.                 !
   !******************************************************************!
   subroutine alloc_temperature( kerr )
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status, l, k, i

   if ( allocated(tk) .or. .not. temp_in_run() ) return
   nt = 0
   do l = 1, nlay
      if ( layer(l)%eos == eos_mie_gruneisen_t ) &
         nt = nt + layer(l)%klast - layer(l)%kfirst + 1
   end do
   allocate( tk(kmax), ec(kmax), etac(kmax), cv(kmax), t0(kmax), kt(nt), &
      stat=status )
   if ( status /= 0 ) then
      kerr = kerr + 1
      nt   = 0
      return
   end if
   tk   = zero
   ec   = zero
   etac = zero
   cv   = zero
   t0   = zero
   nt   = 0
   do l = 1, nlay
      if ( layer(l)%eos /= eos_mie_gruneisen_t ) cycle
      do k = layer(l)%kfirst, layer(l)%klast
         i = icell( k )
         nt = nt + 1
         kt(nt)  = k
         cv(k)   = layer(l)%cv
         t0(k)   = layer(l)%T0
         etac(k) = eta_of( database(jrho,i), database(jr0,i) )
         tk(k)   = temp_of( etac(k), database(je,i), ec(k), &
            database(jg0,i), cv(k), t0(k) )
      end do
   end do
   call track( zero, 0_int32, .true. )
   end subroutine alloc_temperature

   !******************************************************************!
   ! Deallocate it (safe to call when nothing was allocated).         !
   !******************************************************************!
   subroutine dealloc_temperature( kerr )
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status
   if ( .not. allocated(tk) ) return
   deallocate( tk, ec, etac, cv, t0, kt, stat=status )
   if ( status /= 0 ) kerr = kerr + 1
   nt = 0
   end subroutine dealloc_temperature

   !******************************************************************!
   ! One cycle: every cell with T moves its e_c to its new eta and    !
   ! takes its new T. Call it once per cycle, after the hydro step    !
   ! (either method), with the new time and cycle; then the run's T   !
   ! range is brought up to date. kbad is the first cell whose cold   !
   ! energy could not be moved (huge(kbad) if none): the caller stops !
   ! the run there, as for an EOS failure.                            !
   !                                                                  !
   ! Every cell is independent (it reads its own database column and  !
   ! writes only its own k), so the loop gives the same bits on any   !
   ! number of threads. It runs on the time loop's team when that is  !
   ! one (use_team; maincode, section 7).                             !
   !******************************************************************!
   subroutine temp_update( use_team, time, ncycle, kbad, lam, q, rhold, &
      eshold )
   implicit none
   logical, intent(in) :: use_team               ! kmax >= omp_min_zones
   real(kind=dp), intent(in) :: time             ! us, after the step
   integer(kind=int32), intent(in) :: ncycle     ! cycle, after the step
   integer(kind=int32), intent(out) :: kbad      ! first failure, or huge
   real(kind=dp), intent(in), optional :: lam(:) ! by cell: a burn's lam
   real(kind=dp), intent(in), optional :: q(:)   ! ... and Q, kJ/g (both
                                                 ! or neither; NOTE below)
   real(kind=dp), intent(in), optional :: rhold(:)  ! by cell: where the
   real(kind=dp), intent(in), optional :: eshold(:) ! solid is held, and
                                                 ! its e_S (both or
                                                 ! neither; module burn)
   integer(kind=int32) :: n, k, i, ierr
   real(kind=dp) :: eta, ec2, etah
   logical :: burns, holds

   kbad = huge(kbad)
   if ( nt == 0 ) return
   burns = present( lam ) .and. present( q )
   holds = burns .and. present( rhold ) .and. present( eshold )
   !$OMP PARALLEL DO IF( use_team ) DEFAULT(NONE) &
   !$OMP    SHARED( nt, kt, database, tk, ec, etac, cv, t0, burns, lam, q, &
   !$OMP            holds, rhold, eshold ) &
   !$OMP    PRIVATE( n, k, i, eta, ec2, ierr, etah ) REDUCTION(min: kbad)
   do n = 1, nt
      k   = kt(n)
      i   = icell( k )
      eta = eta_of( database(jrho,i), database(jr0,i) )
      call cold_step( etac(k), eta, ec(k), database(jr0,i), &
         database(jc0,i), database(js1,i), database(js2,i), &
         database(jg0,i), ec2, ierr )
      if ( ierr /= eos_ok ) then
         kbad = min( kbad, k )
         cycle
      end if
      ec(k)   = ec2
      etac(k) = eta
      tk(k)   = temp_of( eta, database(je,i), ec2, database(jg0,i), &
         cv(k), t0(k) )
      !***NOTE: a burning cell (lam > 0, module burn) is at vartheta/C_V,
      ! vartheta = e - (1 - lam)(e_c - C_V T_S) + lam Q (module hvrb):
      ! the inert T above plus lam (e_c - C_V T_S + Q)/C_V. At lam = 0
      ! nothing is added, so an unburnt cell's T is the inert model's,
      ! bit for bit.
      !***NOTE: held (module burn: the solid held where it first pulled,
      ! rho < rhold), the solid's e_c is at rhold, with e_S = eshold
      ! there: T = vartheta/C_V with that e_c, as module hvrb's closure.
      if ( burns ) then
         if ( lam(k) > zero ) then
            if ( holds ) then
               if ( database(jrho,i) < rhold(k) ) then
                  etah  = eta_of( rhold(k), database(jr0,i) )
                  tk(k) = ( database(je,i) - ( one - lam(k) )*( eshold(k) - &
                     cv(k)*t0(k)*exp( database(jg0,i)*etah ) ) + &
                     lam(k)*q(k) )/cv(k)
                  cycle
               end if
            end if
            tk(k) = tk(k) + lam(k)*( ec2 - &
               cv(k)*t0(k)*exp( database(jg0,i)*eta ) + q(k) )/cv(k)
         end if
      end if
   end do
   !$OMP END PARALLEL DO
   if ( kbad == huge(kbad) ) call track( time, ncycle, .false. )
   end subroutine temp_update

   !******************************************************************!
   ! One cell's cold energy, moved to its eta now, for a caller that  !
   ! needs it before temp_update (module burn: the HVRB closure needs !
   ! e_c at the new volume before the pressure). temp_update then     !
   ! finds the cell where it left it: a step of zero length, which    !
   ! leaves e_c bit for bit (exp(0) = 1, an integral over nothing),   !
   ! so the order changes no number. Cell k only: any number of       !
   ! threads may call it, each for its own cells. ierr as cold_step.  !
   !******************************************************************!
   subroutine temp_cold_cell( k, ierr )
   implicit none
   integer(kind=int32), intent(in)  :: k         ! cell, 1 to kmax
   integer(kind=int32), intent(out) :: ierr      ! eos_ok, or why not
   integer(kind=int32) :: i
   real(kind=dp) :: eta, ec2
   i   = icell( k )
   eta = eta_of( database(jrho,i), database(jr0,i) )
   call cold_step( etac(k), eta, ec(k), database(jr0,i), database(jc0,i), &
      database(js1,i), database(js2,i), database(jg0,i), ec2, ierr )
   if ( ierr /= eos_ok ) return
   ec(k)   = ec2
   etac(k) = eta
   end subroutine temp_cold_cell

   !******************************************************************!
   ! Bring the run's T range up to date with this cycle (first = the  !
   ! t = 0 state, which starts it). Serial, after the loop, so the    !
   ! hottest cell is the same on any number of threads: a strictly    !
   ! higher T moves it, so a tie keeps the earlier cycle and, on one  !
   ! cycle, the lower cell.                                           !
   !******************************************************************!
   subroutine track( time, ncycle, first )
   implicit none
   real(kind=dp), intent(in) :: time
   integer(kind=int32), intent(in) :: ncycle
   logical, intent(in) :: first
   integer(kind=int32) :: n, k, i

   if ( nt == 0 ) return
   if ( first ) then
      tmin_run = tk(kt(1))
      tmax_run = tk(kt(1))
      hot_k    = 0
   end if
   do n = 1, nt
      k = kt(n)
      i = icell( k )
      if ( database(jdam,i) > zero ) cycle    ! broken: see the NOTE
      tmin_run = min( tmin_run, tk(k) )
      if ( tk(k) > tmax_run .or. hot_k == 0 ) then
         tmax_run  = tk(k)
         hot_k     = k
         hot_time  = time
         hot_cycle = ncycle
         hot_x     = half*( database(jx,i-1) + database(jx,i+1) )
      end if
   end do
   end subroutine track

end module temperature

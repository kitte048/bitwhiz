program test_lshk
!**********************************************************************!
!
!  Purpose:
!    Unit test for the lead-shock detector (module leadshock). Run by
!    "make test"; the exit status is 0 if every check passes, 1 if any
!    check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    1. The residual h, along the Rayleigh line of a steady shock in
!       aluminum (Mie-Gruneisen, module eos; the class deck's values):
!       there e = (1/2) sigma (V_0 - V), sigma = R0**2 Us**2 (V_0 - V)
!       the total stress, so h = (1/2)(sigma - P)(V_0 - V) exactly (the
!       q of a smeared shock is sigma - P). Algebra, not a fit: the
!       check is to round-off.
!    2-9. The steps, on paths built so that h takes chosen values: at
!       each step e = h + (1/2)(V_0 - V) P for a chosen rho and P, so
!       the expected mark (the step, P_s, t_s) follows from the rules
!       in module leadshock's header by hand, written next to each.
!    10. The stall: a fall that slows below ls_knee of its largest step.
!    11. The hydro's own paths, replayed (tests/verification/
!       study_leadshock.py) are the study, not this test.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/06/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one, quit
use eos, only: mg_pressure, eos_ok
use leadshock, only: ls_h, ls_step, ls_marked, ls_nst, ls_hlast, &
   ls_hmax, ls_flag, ls_ps, ls_ts, ls_quiet, ls_rising, ls_falling, &
   ls_floor, ls_knee
implicit none

!*** Aluminum, as the class deck (and tests/verification/av_study).
real(kind=dp), parameter :: R0 = 2.78_dp, C0 = 5.30_dp, S1 = 1.34_dp, &
   S2 = zero, G0 = 2.0_dp
real(kind=dp), parameter :: V0 = one/R0
integer(kind=int32) :: ncheck, nfail, i, ierr
real(kind=dp) :: st(ls_nst), up, us, eta, v, sigma, e, p, h, href, err
logical :: ok

ncheck = 0
nfail  = 0
write(*,'(a)') ' test_lshk: the lead-shock detector (module leadshock)'

!*** 1. h along the Rayleigh line, u_p = 1 km/s (Us = 6.64 km/s).
up  = one
us  = C0 + S1*up
ok  = .true.
err = zero
do i = 1, 20
   eta   = real(i, dp)/20.0_dp*( up/us )     ! 0 < eta <= up/Us
   v     = V0*( one - eta )
   sigma = R0*R0*us*us*( V0 - v )
   e     = half*sigma*( V0 - v )
   call mg_pressure( one/v, e, R0, C0, S1, S2, G0, p, ierr )
   if ( ierr /= eos_ok ) ok = .false.
   h     = ls_h( one/v, e, p, R0 )
   href  = half*( sigma - p )*( V0 - v )
   err   = max( err, abs( h - href )/( half*sigma*( V0 - v ) ) )
end do
ok = ok .and. err < 1.0e-14_dp
call check( ok, '1. h = (1/2) q (V0 - V) on the Rayleigh line (rel. '// &
   rtoa(err)//')' )
!     and h = 0 on the Hugoniot (the end of the line: q = 0 there).
eta = up/us
v   = V0*( one - eta )
e   = half*up*up
call mg_pressure( one/v, e, R0, C0, S1, S2, G0, p, ierr )
ok  = ierr == eos_ok .and. abs( p - R0*us*up ) < 1.0e-12_dp*p .and. &
   abs( ls_h( one/v, e, p, R0 ) ) < 1.0e-14_dp*e
call check( ok, '1. h = 0 at the Hugoniot state (P = R0 Us up)' )

!*** 2. At rest, and below the floor, and in expansion: never armed.
st = zero
do i = 1, 5
   call put( st, R0, zero, zero, real(i, dp), one )
end do
ok = nint( st(ls_flag) ) == ls_quiet
st = zero
call put( st, 1.01_dp*R0, half*ls_floor*C0*C0, one, one, one )
ok = ok .and. nint( st(ls_flag) ) == ls_quiet
call put( st, 1.01_dp*R0, 2.0_dp*ls_floor*C0*C0, one, 2.0_dp, one )
ok = ok .and. nint( st(ls_flag) ) == ls_rising
st = zero
call put( st, 0.99_dp*R0, 1.0e-3_dp, one, one, one )   ! V > V0
ok = ok .and. nint( st(ls_flag) ) == ls_quiet
call check( ok, '2. quiet at rest, below the floor, and in expansion; '// &
   'armed just above the floor' )

!*** 3. A zero crossing. h = 1, 3, 2, 1, -1 (x 1e-3) at t = 1 to 5,
!***    P = 10, 20, 30, 40, 50: marked at t = 5, t_s = 4 + 1/(1+1) =
!***    4.5 (h from 1 to -1), P_s = 50.
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, 2.0_dp, 1.0_dp, -1.0_dp /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp /) )
ok = ls_marked( st ) .and. same( st(ls_ps), 50.0_dp ) .and. &
   abs( st(ls_ts) - 4.5_dp ) < 1.0e-10_dp
call check( ok, '3. a zero crossing: P_s at the step, t_s between' )

!*** 4. A local minimum. h = 1, 3, 2, 1.5, 1.6: the minimum at t = 4,
!***    seen at t = 5: P_s = P(5) = 50, t_s = 4.
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, 2.0_dp, 1.5_dp, 1.6_dp /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp /) )
ok = ls_marked( st ) .and. same( st(ls_ps), 50.0_dp ) .and. &
   same( st(ls_ts), 4.0_dp )
call check( ok, '4. a local minimum, however shallow (no hysteresis)' )

!*** 5. Rising again before the mark: h = 1, 3, 2, 4, 1, -1: the
!***    peak moves to 4; no mark at the dip to 2 then up to 4 (4 > the
!***    peak: rising, not a minimum); marked at t = 6, t_s = 5.5.
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, 2.0_dp, 4.0_dp, 1.0_dp, -1.0_dp /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp, 60.0_dp /) )
ok = ls_marked( st ) .and. same( st(ls_ps), 60.0_dp ) .and. &
   abs( st(ls_ts) - 5.5_dp ) < 1.0e-10_dp .and. &
   abs( st(ls_hmax) - 4.0e-3_dp ) < 1.0e-12_dp
call check( ok, '5. a rise past the peak: rising again, the peak moves' )

!*** 6. A fall straight through zero on the first fall: h = 1, 3, -1:
!***    marked at t = 3, t_s = 2 + 3/4.
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, -1.0_dp /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp /) )
ok = ls_marked( st ) .and. same( st(ls_ps), 30.0_dp ) .and. &
   abs( st(ls_ts) - 2.75_dp ) < 1.0e-10_dp
call check( ok, '6. the first fall crossing zero at once' )

!*** 7. Isentropic compression: h < 0 from the start (the chord over
!***    a convex P(V) is above it), so never armed.
st = zero
call path( st, (/ -1.0_dp, -2.0_dp, -3.0_dp, -2.0_dp, -4.0_dp /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp /) )
ok = .not. ls_marked( st ) .and. nint( st(ls_flag) ) == ls_quiet
call check( ok, '7. h <= 0 throughout: never armed, never marked' )

!*** 8. Frozen once marked: the case 3 path, then a reshock (h up to
!***    10, P to 100) and a release: P_s and t_s as they were.
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, 2.0_dp, 1.0_dp, -1.0_dp, 10.0_dp, &
   2.0_dp, -5.0_dp /), (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp, &
   100.0_dp, 60.0_dp, 5.0_dp /) )
ok = ls_marked( st ) .and. same( st(ls_ps), 50.0_dp ) .and. &
   abs( st(ls_ts) - 4.5_dp ) < 1.0e-10_dp
call check( ok, '8. frozen once marked: a reshock changes nothing' )

!*** 9. Still rising, or falling without a minimum yet: not marked.
st = zero
call path( st, (/ 1.0_dp, 2.0_dp, 3.0_dp /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp /) )
ok = .not. ls_marked( st ) .and. nint( st(ls_flag) ) == ls_rising
call path( st, (/ 2.0_dp, 1.0_dp /), (/ 40.0_dp, 50.0_dp /), 4 )
ok = ok .and. .not. ls_marked( st ) .and. &
   nint( st(ls_flag) ) == ls_falling .and. &
   abs( st(ls_hlast) - 1.0e-3_dp ) < 1.0e-12_dp
call check( ok, '9. rising, then falling: not marked yet' )

!*** 10. A stall. h = 1, 3, 2, 1.5, then 1.5 - knee/2 (a fall of half
!***     ls_knee times the largest, 1): marked at t = 5, t_s = 5,
!***     P_s = P(5) = 50. And a fall just above it is not: h = 1, 3, 2,
!***     1.5, 1.5 - 2 knee.
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, 2.0_dp, 1.5_dp, 1.5_dp - half*ls_knee /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp /) )
ok = ls_marked( st ) .and. same( st(ls_ps), 50.0_dp ) .and. &
   same( st(ls_ts), 5.0_dp )
st = zero
call path( st, (/ 1.0_dp, 3.0_dp, 2.0_dp, 1.5_dp, 1.5_dp - 2*ls_knee /), &
   (/ 10.0_dp, 20.0_dp, 30.0_dp, 40.0_dp, 50.0_dp /) )
ok = ok .and. .not. ls_marked( st ) .and. &
   abs( st(ls_ps) - 1.0e-3_dp ) < 1.0e-12_dp      ! the largest fall, so far
call check( ok, '10. a stalled fall (below ls_knee of the largest): '// &
   'marked; just above: not' )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_lshk: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_lshk: all ', ncheck, ' checks passed'

contains

   !*** One step at (rho, h, P), time t: e set so that ls_h gives h.
   subroutine put( s, rho, hh, pp, t, dt )
   implicit none
   real(kind=dp), intent(inout) :: s(ls_nst)
   real(kind=dp), intent(in) :: rho, hh, pp, t, dt
   real(kind=dp) :: ee
   ee = hh + half*( V0 - one/rho )*pp
   call ls_step( s, rho, ee, pp, R0, C0, t, dt )
   end subroutine put

   !*** Steps at t = t0+1, t0+2, ... (dt = 1), h in units of 1e-3 kJ/g
   !*** (far above the floor), compressed to rho = 1.1 R0.
   subroutine path( s, hs, ps, t0 )
   implicit none
   real(kind=dp), intent(inout) :: s(ls_nst)
   real(kind=dp), intent(in) :: hs(:), ps(:)
   integer, intent(in), optional :: t0
   integer :: j, j0
   j0 = 0
   if ( present( t0 ) ) j0 = t0 - 1
   do j = 1, size( hs )
      call put( s, 1.1_dp*R0, 1.0e-3_dp*hs(j), ps(j), real(j0 + j, dp), one )
   end do
   end subroutine path

   subroutine check( okk, what )
   implicit none
   logical, intent(in) :: okk
   character(len=*), intent(in) :: what
   ncheck = ncheck + 1
   if ( okk ) then
      write(*,'(a)') '   pass  '//what
   else
      write(*,'(a)') '   FAIL  '//what
      nfail = nfail + 1
   end if
   end subroutine check

   !*** The same value to within a few ulps (P_s is P itself; t_s at a
   !*** minimum is t - dt, exact for these whole numbers).
   logical function same( a, b )
   implicit none
   real(kind=dp), intent(in) :: a, b
   same = abs( a - b ) <= 4.0_dp*epsilon( one )*max( abs(a), abs(b) )
   end function same

   function rtoa( r ) result(s)
   implicit none
   real(kind=dp), intent(in) :: r
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(es8.1)' ) r
   s = trim(adjustl(buf))
   end function rtoa

end program test_lshk

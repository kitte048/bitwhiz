program test_tcas
!**********************************************************************!
!
!  Purpose:
!    Unit test for ThermalCascade (module thermalcascade): its rate,
!    1 - exp(-x), its exact step, and the cascade at constant volume.
!    Run by "make test"; the exit status is 0 if every check passes, 1
!    if any check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from module thermalcascade. The tables were computed in Python
!    with 50-digit arithmetic (mpmath) from the model's definition in
!    doc/design/burn_models.md (tests/tcas_reference.py): the rate (0
!    at or below TC, for every GT), 1 - exp(-x) by mpmath's expm1, the
!    exact step at a fixed rate, and the time for a cell at constant
!    volume to burn to lam = 0.5 and 0.99 by quadrature (the closure's
!    T linear in lam there, T = Ta + b lam). The other checks are by
!    construction: n steps at a fixed rate are one step n dt long (the
!    step is exact), and the cascade's time converges at first order
!    (the module takes T at the start of each step).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/07/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one, quit
use thermalcascade, only: tc_rate, tc_step, tc_om
implicit none

!*** The 50-digit tables (tests/tcas_reference.py).
type :: rate_t
   real(kind=dp) :: T, Ps, HT, TC, GT, NS, PR, r
end type rate_t
type :: om_t
   real(kind=dp) :: x, om
end type om_t
type :: step_t
   real(kind=dp) :: lam1, x, lam2
end type step_t
type :: casc_t
   real(kind=dp) :: Ta, b, HT, TC, GT, S, t50, t99
end type casc_t

type(rate_t), parameter, dimension(11) :: rates = (/ &
   rate_t( 7.4000000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.5000000000000000000_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.0953199141281574845_dp ), &
   rate_t( 7.4000000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 9.2571428571428571429e-2_dp ), &
   rate_t( 7.4000000000000000000e2_dp, 0.0_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.5000000000000000000_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.6565023392678924919e-1_dp ), &
   rate_t( 7.4000000000000000000e2_dp, -3.0000000000000000000_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.5000000000000000000_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.6565023392678924919e-1_dp ), &
   rate_t( 3.5000000000000000000e3_dp, 2.5000000000000000000e1_dp, &
      2.0000000000000000000e-6_dp, 6.0000000000000000000e2_dp, &
      2.2500000000000000000_dp, 5.0000000000000000000e-1_dp, &
      7.0000000000000000000_dp, 2.6390733438468973616e2_dp ), &
   rate_t( 6.0100000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.5000000000000000000_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 6.6122448979591836735e-4_dp ), &
   rate_t( 6.0000000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.5000000000000000000_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 0.0_dp ), &
   rate_t( 5.9900000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, 0.0_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, 0.0_dp ), &
   rate_t( 6.0100000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      2.5000000000000000000e-1_dp, 6.0000000000000000000e2_dp, 0.0_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, &
      1.6530612244897959184_dp ), &
   rate_t( 9.0000000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      1.0000000000000000000e-4_dp, 0.0_dp, 1.0000000000000000000_dp, &
      0.0_dp, 7.0000000000000000000_dp, 9.0000000000000000000e-2_dp ), &
   rate_t( 9.0000000000000000000e2_dp, 1.1000000000000000000e1_dp, &
      0.0_dp, 6.0000000000000000000e2_dp, 1.0000000000000000000_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, 0.0_dp ) /)
type(om_t), parameter, dimension(11) :: oms = (/ &
   om_t( 1.0000000000000000000e-16_dp, 9.9999999999999995000e-17_dp ), &
   om_t( 1.0000000000000000000e-12_dp, 9.9999999999950000000e-13_dp ), &
   om_t( 1.0000000000000000000e-8_dp, 9.9999999500000001667e-9_dp ), &
   om_t( 1.0000000000000000000e-4_dp, 9.9995000166662500083e-5_dp ), &
   om_t( 1.0000000000000000000e-2_dp, 9.9501662508319464261e-3_dp ), &
   om_t( 5.0000000000000000000e-2_dp, 4.8770575499285990909e-2_dp ), &
   om_t( 4.9990000000000000000e-1_dp, 3.9340868418864092352e-1_dp ), &
   om_t( 5.0000000000000000000e-1_dp, 3.9346934028736657640e-1_dp ), &
   om_t( 1.0000000000000000000_dp, 6.3212055882855767840e-1_dp ), &
   om_t( 1.0000000000000000000e1_dp, 9.9995460007023751515e-1_dp ), &
   om_t( 5.0000000000000000000e1_dp, 1.0000000000000000000_dp ) /)
type(step_t), parameter, dimension(7) :: steps = (/ &
   step_t( 0.0_dp, 1.0000000000000000000e-12_dp, &
      9.9999999999950000000e-13_dp ), &
   step_t( 0.0_dp, 3.0000000000000000000e-2_dp, &
      2.9554466451491823067e-2_dp ), &
   step_t( 0.0_dp, 2.0000000000000000000_dp, &
      8.6466471676338730811e-1_dp ), &
   step_t( 1.0000000000000000000e-9_dp, 1.0000000000000000000e-6_dp, &
      1.0009994990001671666e-6_dp ), &
   step_t( 5.0000000000000000000e-1_dp, 7.0000000000000000000e-1_dp, &
      7.5170734810429524265e-1_dp ), &
   step_t( 9.9900000000000000000e-1_dp, 3.0000000000000000000_dp, &
      9.9995021293163213606e-1_dp ), &
   step_t( 2.5000000000000000000e-1_dp, 0.0_dp, &
      2.5000000000000000000e-1_dp ) /)
type(casc_t), parameter, dimension(2) :: cascs = (/ &
   casc_t( 7.4000000000000000000e2_dp, 4.2000000000000000000e3_dp, &
      1.0000000000000000000e-3_dp, 6.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 6.6122448979591836735_dp, &
      1.2076937136398887808e-1_dp, 2.7979903367218588144e-1_dp ), &
   casc_t( 7.4000000000000000000e2_dp, 4.2000000000000000000e3_dp, &
      1.0000000000000000000e-4_dp, 6.0000000000000000000e2_dp, &
      1.5000000000000000000_dp, 6.6122448979591836735_dp, &
      5.1822753288268128590e-2_dp, 7.8189875635423058955e-2_dp ) /)

integer(kind=int32) :: ncheck, nfail, i, j, n
real(kind=dp) :: worst, x, lam, r, t, err(3), dt
real(kind=dp) :: t50(3), t99(3)
logical :: ok

ncheck = 0
nfail  = 0
write(*,'(a)') ' test_tcas: ThermalCascade (module thermalcascade)'

!*** 1. The rate, against 50 digits (0 exactly where it must be).
ok    = .true.
worst = zero
do i = 1, size(rates)
   r = tc_rate( rates(i)%T, rates(i)%Ps, rates(i)%HT, rates(i)%TC, &
      rates(i)%GT, rates(i)%NS, rates(i)%PR )
   if ( rates(i)%r > zero ) then
      worst = max( worst, abs( r - rates(i)%r )/rates(i)%r )
   else if ( abs( r ) > zero ) then
      ok = .false.
   end if
end do
ok = ok .and. worst < 1.0e-14_dp
call check( ok, '1. the rate (11 states: T at, below, above TC; GT = 0; '// &
   'P_s < 0) to '//rtoa(worst) )

!*** 2. 1 - exp(-x), from 1e-16 to 50, to its relative precision.
worst = zero
do i = 1, size(oms)
   worst = max( worst, abs( tc_om( oms(i)%x ) - oms(i)%om )/oms(i)%om )
end do
call check( worst < 4.0e-16_dp, '2. 1 - exp(-x), x from 1e-16 to 50 (the series below 0.5), '// &
   'to '//rtoa(worst) )

!*** 3. The exact step at a fixed rate.
worst = zero
do i = 1, size(steps)
   lam   = tc_step( steps(i)%lam1, steps(i)%x, one )
   worst = max( worst, abs( lam - steps(i)%lam2 ) )
end do
call check( worst < 4.0e-16_dp, '3. the step, 1 - lam2 = (1 - lam1) '// &
   'exp(-r dt), to '//rtoa(worst) )

!*** 4. Exact: 1000 steps of dt at a fixed rate are one step 1000 dt.
lam = zero
do i = 1, 1000
   lam = tc_step( lam, 2.5_dp, 1.0e-3_dp )
end do
x = tc_step( zero, 2.5_dp, one )
call check( abs( lam - x ) < 1.0e-13_dp, '4. 1000 steps = one step '// &
   '(exact at a fixed rate), to '//rtoa( abs( lam - x ) ) )

!*** 5. The cascade at constant volume: lam to 0.5 and 0.99, with T at
!***    the start of each step (as module burn steps a cell), against
!***    the 50-digit quadrature, at dt, dt/2, dt/4: first order.
ok = .true.
do j = 1, size(cascs)
   do n = 1, 3
      dt  = 1.0e-4_dp*cascs(j)%t50/real( 2**(n-1), dp )
      lam = zero
      t   = zero
      t50(n) = -one
      t99(n) = -one
      do while ( t99(n) < zero )
         x = lam
         r = cascs(j)%S*tc_rate( cascs(j)%Ta + cascs(j)%b*lam, zero, &
            cascs(j)%HT, cascs(j)%TC, cascs(j)%GT, zero, one ) ! T^n; S
                                                 ! the shock's factor
         lam = tc_step( lam, r, dt )
         t = t + dt
         if ( t50(n) < zero .and. lam >= half ) &
            t50(n) = t - dt*( lam - half )/( lam - x )
         if ( lam >= 0.99_dp ) t99(n) = t - dt*( lam - 0.99_dp )/( lam - x )
      end do
   end do
   err = abs( t99 - cascs(j)%t99 )/cascs(j)%t99
   ok  = ok .and. err(3) < 2.0e-4_dp .and. &
      err(1)/err(2) > 1.8_dp .and. err(1)/err(2) < 2.2_dp .and. &
      err(2)/err(3) > 1.8_dp .and. err(2)/err(3) < 2.2_dp .and. &
      abs( t50(3) - cascs(j)%t50 )/cascs(j)%t50 < 2.0e-4_dp
   write(*,'(a,f4.1,a,3es9.2)') '         GT = ', cascs(j)%GT, &
      ': t(0.99) error at dt, dt/2, dt/4:', err
end do
call check( ok, '5. the cascade at constant volume: first order in dt, '// &
   'to 2e-4 at the finest' )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_tcas: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_tcas: all ', ncheck, ' checks passed'

contains

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

   function rtoa( r ) result(s)
   implicit none
   real(kind=dp), intent(in) :: r
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(es8.1)' ) r
   s = trim(adjustl(buf))
   end function rtoa

end program test_tcas

program test_ffire
!**********************************************************************!
!
!  Purpose:
!    Unit test for FlashFire (module flashfire): its rate, its seed,
!    its sub-cycled RK4 step at a fixed temperature and at a constant
!    rate, and the cascade at constant volume.
!    Run by "make test"; the exit status is 0 if every check passes, 1
!    if any check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from module flashfire. The tables were computed in Python with
!    50-digit arithmetic (mpmath) from the model's definition in
!    doc/design/burn_models.md (tests/ffire_reference.py): the rate (0
!    unless 0 < lam < 1 and T > 0); lam(t) at a fixed T with BFF = 0,
!    in closed form; and the times for a cell at constant volume to burn
!    from the seed to lam = 0.5 and 0.99 by quadrature (the closure's T
!    linear in lam there, T = Ta + b lam). The other checks are by
!    construction: the seed, burn-out, and a constant rate (RK4 is exact
!    for it, so lam2 = lam1 + r dt); and b, T's slope in lam, against
!    module mixture's own vartheta at two lam (it is linear there), the
!    held solid too.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/12/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one, quit
use flashfire, only: ff_rate, ff_step, ff_tslope
use mixture, only: mix_state
use temperature, only: eta_of
implicit none
!*** The 50-digit tables (tests/ffire_reference.py).
type :: rate_t
   real(kind=dp) :: lam, T, Ps, KFF, AFF, BFF, TA, NS, PR, r
end type rate_t
type :: fix_t
   real(kind=dp) :: lam0, c, AFF, t, lam
end type fix_t
type :: casc_t
   real(kind=dp) :: T1, b, Ps, KFF, AFF, BFF, TA, NS, PR, LAM0, t50, t99
end type casc_t
type(rate_t), parameter, dimension(11) :: rates = (/ &
   rate_t( 3.0000000000000000000e-1_dp, 9.0000000000000000000e2_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.0000000000000000000e3_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.2905387308668860863_dp ), &
   rate_t( 1.0000000000000000000e-4_dp, 7.4000000000000000000e2_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.0000000000000000000e3_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 7.9626729774532751940e-3_dp ), &
   rate_t( 3.0000000000000000000e-1_dp, 9.0000000000000000000e2_dp, &
      0.0_dp, 4.0000000000000000000e2_dp, 1.0000000000000000000_dp, &
      5.0000000000000000000e-1_dp, 6.0000000000000000000e3_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, &
      1.9517406732246116737e-1_dp ), &
   rate_t( 3.0000000000000000000e-1_dp, 9.0000000000000000000e2_dp, &
      -3.0000000000000000000_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.0000000000000000000e3_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.9517406732246116737e-1_dp ), &
   rate_t( 9.9900000000000000000e-1_dp, 3.5000000000000000000e3_dp, &
      2.5000000000000000000e1_dp, 2.0000000000000000000e5_dp, &
      2.0000000000000000000_dp, 0.0_dp, 1.2000000000000000000e4_dp, &
      5.0000000000000000000e-1_dp, 7.0000000000000000000_dp, &
      1.3869037185260608327e-2_dp ), &
   rate_t( 5.0000000000000000000e-1_dp, 9.0000000000000000000e2_dp, &
      1.1000000000000000000e1_dp, 3.0000000000000000000_dp, 0.0_dp, &
      2.5000000000000000000_dp, 0.0_dp, 1.0000000000000000000_dp, &
      1.0000000000000000000_dp, 6.3639610306789277196_dp ), &
   rate_t( 1.0000000000000000000_dp, 9.0000000000000000000e2_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, 0.0_dp, &
      5.0000000000000000000e-1_dp, 6.0000000000000000000e3_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, 0.0_dp ), &
   rate_t( 0.0_dp, 9.0000000000000000000e2_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 0.0_dp, 6.0000000000000000000e3_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, 0.0_dp ), &
   rate_t( 3.0000000000000000000e-1_dp, 0.0_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.0000000000000000000e3_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 0.0_dp ), &
   rate_t( 3.0000000000000000000e-1_dp, -5.0000000000000000000_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.0000000000000000000e3_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 0.0_dp ), &
   rate_t( 3.0000000000000000000e-1_dp, 9.0000000000000000000e2_dp, &
      1.1000000000000000000e1_dp, 0.0_dp, 1.0000000000000000000_dp, &
      5.0000000000000000000e-1_dp, 6.0000000000000000000e3_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, 0.0_dp ) /)
type(fix_t), parameter, dimension(5) :: fixes = (/ &
   fix_t( 1.0000000000000000000e-4_dp, 2.0000000000000000000_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.3215734677267482264e-1_dp ), &
   fix_t( 1.0000000000000000000e-4_dp, 2.0000000000000000000_dp, &
      5.0000000000000000000e-1_dp, 3.0000000000000000000e-1_dp, &
      5.1006999924996249766e-1_dp ), &
   fix_t( 1.0000000000000000000e-4_dp, 2.0000000000000000000_dp, &
      2.0000000000000000000_dp, 1.5000000000000000000_dp, &
      7.5000625046878515889e-1_dp ), &
   fix_t( 2.0000000000000000000e-1_dp, 5.0000000000000000000_dp, &
      1.5000000000000000000_dp, 1.0000000000000000000e-1_dp, &
      4.6567410127420094341e-1_dp ), &
   fix_t( 1.0000000000000000000e-4_dp, 2.0000000000000000000_dp, &
      5.0000000000000000000e-1_dp, 2.0000000000000000000_dp, &
      1.0000000000000000000_dp ) /)
type(casc_t), parameter, dimension(3) :: cascs = (/ &
   casc_t( 7.4000000000000000000e2_dp, 4.2000000000000000000e3_dp, &
      1.1000000000000000000e1_dp, 4.0000000000000000000e2_dp, &
      1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      6.0000000000000000000e3_dp, 2.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.0000000000000000000e-4_dp, &
      3.5239828397948315167e-1_dp, 3.5905712559557645487e-1_dp ), &
   casc_t( 7.4000000000000000000e2_dp, 4.2000000000000000000e3_dp, &
      1.1000000000000000000e1_dp, 2.0000000000000000000e5_dp, &
      2.0000000000000000000_dp, 0.0_dp, 1.2000000000000000000e4_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, &
      1.0000000000000000000e-4_dp, 1.0723388791819328447e-1_dp, &
      1.0817634431038694135e-1_dp ), &
   casc_t( 8.0000000000000000000e2_dp, 4.0000000000000000000e3_dp, &
      5.0000000000000000000_dp, 5.0000000000000000000e1_dp, &
      5.0000000000000000000e-1_dp, 1.0000000000000000000_dp, &
      3.0000000000000000000e3_dp, 1.0000000000000000000_dp, &
      7.0000000000000000000_dp, 1.0000000000000000000e-3_dp, &
      1.8829627138987069360_dp, 1.9233456535819212163_dp ) /)
integer(kind=int32) :: ncheck = 0, nfail = 0, i, j, k, n, m
real(kind=dp) :: r, worst, lam, dt, T, x, err(2,2), th(2), p, c, dpdl, b
integer(kind=int32) :: ifb, ierr
!*** Material X (the class problem's), for check 6.
real(kind=dp), parameter :: R0 = 1.60_dp, C0 = 2.50_dp, S1 = 1.80_dp, &
   S2 = -0.10_dp, G0 = 1.20_dp, CVX = 1.1633418e-3_dp, T0X = 298.0_dp, &
   GAMX = 2.60_dp, QX = 4.8828_dp
logical :: ok

write(*,'(a)') ' test_ffire: FlashFire (module flashfire)'

!*** 1. The rate, against 50 digits (0 exactly where it must be).
ok    = .true.
worst = zero
do i = 1, size(rates)
   r = ff_rate( rates(i)%lam, rates(i)%T, rates(i)%Ps, rates(i)%KFF, &
      rates(i)%AFF, rates(i)%BFF, rates(i)%TA, rates(i)%NS, rates(i)%PR )
   if ( rates(i)%r > zero ) then
      worst = max( worst, abs( r - rates(i)%r )/rates(i)%r )
   else if ( abs( r ) > zero ) then
      ok = .false.
   end if
end do
ok = ok .and. worst < 1.0e-14_dp
call check( ok, '1. the rate (11 states: lam at the seed, 0 and 1; T <= 0; '// &
   'AFF, BFF, TA, KFF = 0; P_s < 0) to '//rtoa(worst) )

!*** 2. The seed, alone where nothing burns (T = 0, so the rate is 0):
!***    lam = max(lam1, LAM0), exactly; and KFF = 0, the inert limit,
!***    leaves lam1 as it is, with no seed.
ok = abs( ff_step( zero, zero, zero, 11.0_dp, 400.0_dp, one, half, &
        6000.0_dp, 2.0_dp, 7.0_dp, 1.0e-4_dp, 1.0e-3_dp ) - 1.0e-4_dp ) <= zero &
   .and. abs( ff_step( 0.3_dp, zero, zero, 11.0_dp, 400.0_dp, one, half, &
        6000.0_dp, 2.0_dp, 7.0_dp, 1.0e-4_dp, 1.0e-3_dp ) - 0.3_dp ) <= zero &
   .and. abs( ff_step( zero, 900.0_dp, 4200.0_dp, 11.0_dp, zero, one, half, &
        6000.0_dp, 2.0_dp, 7.0_dp, 1.0e-4_dp, 1.0e-3_dp ) ) <= zero
call check( ok, '2. the seed: lam = max(lam1, LAM0), exactly; KFF = 0: '// &
   'no seed, no burn' )

!*** 3. A constant rate (AFF = BFF = TA = 0): RK4 is exact for it, so
!***    lam2 = LAM0 + KFF S dt, however many sub-steps it takes.
lam   = ff_step( zero, 900.0_dp, 4200.0_dp, 11.0_dp, 2.5_dp, zero, zero, &
   zero, one, one, 1.0e-4_dp, 0.03_dp )
worst = abs( lam - ( 1.0e-4_dp + 2.5_dp*12.0_dp*0.03_dp ) )/lam
call check( worst < 1.0e-14_dp, '3. a constant rate: lam2 = LAM0 + r dt '// &
   '(exact), to '//rtoa(worst) )

!*** 4. A fixed T (b = 0) and BFF = 0, against the closed forms
!***    (AFF = 1, 0.5, 2, 1.5), one step of the whole time; and burn-out:
!***    AFF = 0.5 reaches lam = 1 in a finite time, and lam is then 1.
worst = zero
do i = 1, size(fixes) - 1
   lam = ff_step( zero, one, zero, zero, fixes(i)%c, fixes(i)%AFF, zero, &
      zero, zero, one, fixes(i)%lam0, fixes(i)%t )
   worst = max( worst, abs( lam - fixes(i)%lam )/( one - fixes(i)%lam ) )
end do
i   = size(fixes)
lam = ff_step( zero, one, zero, zero, fixes(i)%c, fixes(i)%AFF, zero, &
   zero, zero, one, fixes(i)%lam0, fixes(i)%t )
call check( worst < 1.0e-5_dp .and. abs( lam - one ) <= zero .and. &
   abs( fixes(i)%lam - one ) <= zero, &
   '4. a fixed T, BFF = 0: the closed forms, 1 - lam to '//rtoa(worst)// &
   '; burnt out at lam = 1 exactly' )

!*** 5. The cascade at constant volume, as module burn steps a cell: T at
!***    each step's start the closure's, Ta + b lam^n, and b; N steps of
!***    t50/N (t99/N) must end at lam = 0.5 (0.99), the seed at the
!***    first. T follows lam within each step, so the result is the
!***    integration's alone. Measured as the error in time it means,
!***    |lam - lam*|/(r(lam*) t*), the design note's measure.
ok = .true.
do j = 1, size(cascs)
   do m = 1, 2
      n = merge( 1000, 100, m == 1 )
      do i = 1, 2
         dt  = merge( cascs(j)%t50, cascs(j)%t99, i == 1 )/real( n, dp )
         lam = zero
         do k = 1, n
            T   = cascs(j)%T1 + cascs(j)%b*lam
            lam = ff_step( lam, T, cascs(j)%b, cascs(j)%Ps, cascs(j)%KFF, &
               cascs(j)%AFF, cascs(j)%BFF, cascs(j)%TA, cascs(j)%NS, &
               cascs(j)%PR, cascs(j)%LAM0, dt )
         end do
         x   = merge( half, 0.99_dp, i == 1 )
         r   = ff_rate( x, cascs(j)%T1 + cascs(j)%b*x, cascs(j)%Ps, &
            cascs(j)%KFF, cascs(j)%AFF, cascs(j)%BFF, cascs(j)%TA, &
            cascs(j)%NS, cascs(j)%PR )
         err(i,m) = abs( lam - x )/( r*dt*real( n, dp ) )
      end do
   end do
   ok = ok .and. maxval( err(:,1) ) < 1.0e-6_dp .and. &
      maxval( err(:,2) ) < 2.0e-6_dp
   write(*,'(a,i0,a,4es9.2)') '         case ', j, &
      ': time error at lam = 0.5, 0.99 (N = 1000, then 100):', err(:,1), &
      err(:,2)
end do
call check( ok, '5. the cascade at constant volume: the times to lam = '// &
   '0.5 and 0.99 to 1e-6 (N = 1000), 2e-6 (N = 100)' )

!*** 6. b, T's slope in lam at fixed rho and e, against the closure
!***    itself: module mixture's vartheta at lam = 0.2 and 0.6 (linear
!***    in lam), for a compressed cell, and for one stretched past its
!***    hold (the held solid's e_S and eta).
ok = .true.
do i = 1, 2
   call mix_state( 2.2_dp, 1.0_dp, 0.2_dp*real( 2*i - 1, dp ), 0.4_dp, R0, &
      C0, S1, S2, G0, CVX, T0X, GAMX, QX, p, c, th(i), dpdl, ifb, ierr )
   ok = ok .and. ierr == 0
end do
b     = ff_tslope( 0.4_dp, eta_of( 2.2_dp, R0 ), CVX, T0X, G0, QX )
worst = abs( ( th(2) - th(1) )/( 0.4_dp*CVX ) - b )/b
do i = 1, 2
   call mix_state( 1.5_dp, 0.3_dp, 0.2_dp*real( 2*i - 1, dp ), 0.01_dp, R0, &
      C0, S1, S2, G0, CVX, T0X, GAMX, QX, p, c, th(i), dpdl, ifb, ierr, &
      rhold=1.7_dp, eshold=0.05_dp )
end do
b     = ff_tslope( 0.05_dp, eta_of( 1.7_dp, R0 ), CVX, T0X, G0, QX )
worst = max( worst, abs( ( th(2) - th(1) )/( 0.4_dp*CVX ) - b )/b )
call check( ok .and. worst < 1.0e-12_dp, '6. b = (e_c + Q)/C_V, the '// &
   'closure''s slope of T in lam (held too), to '//rtoa(worst) )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_ffire: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_ffire: all ', ncheck, ' checks passed'

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

end program test_ffire

program test_sign
!**********************************************************************!
!
!  Purpose:
!    Unit test for StochasticIgnite (module stochignite): AS241, the
!    counter-based generator, each bin's starting Z, the Ornstein-
!    Uhlenbeck step, and the burn.
!    Run by "make test"; the exit status is 0 if every check passes, 1
!    if any check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from module stochignite. tests/sign_reference.py computes, at
!    50 digits (mpmath): the exact normal deviates; the generator's u
!    from Python's own integers (so the 16-bit pieces are checked bit
!    for bit); each bin's starting Z from the table; and the floored
!    mean rate, mu Phi(mu/sigma) + sigma phi(mu/sigma). The statistical
!    checks (the OU step's mean, variance and correlation) compare with
!    the process's exact values, within their sampling error (4
!    standard errors). The rest are by construction: SIGMA = 0 is a
!    clock, so lam = 1 - exp(-(MU S t)**AVRAMI); TAUZ = 1e30 freezes Z.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/12/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, int64, zero, one, quit
use stochignite, only: si_step, si_z0, si_uniform, si_normal, si_nsub
implicit none
type :: dev_t
   real(kind=dp) :: u, z
end type dev_t
type :: gen_t
   integer(kind=int64) :: seed, j, n, s
   real(kind=dp) :: u
end type gen_t
type :: z0_t
   integer(kind=int64) :: seed, j
   real(kind=dp) :: z
end type z0_t
type :: flr_t
   real(kind=dp) :: mu, sigma, r
end type flr_t
type(dev_t), parameter, dimension(18) :: devs = (/ &
   dev_t( 5.5511151231257827021e-17_dp, -8.2923610758135955382_dp ), &
   dev_t( 9.9999999999999994515e-21_dp, -9.2623400897984075796_dp ), &
   dev_t( 1.0000000000000000364e-10_dp, -6.3613409024040561991_dp ), &
   dev_t( 1.0000000000000000818e-5_dp, -4.2648907939228246102_dp ), &
   dev_t( 1.0000000000000000208e-3_dp, -3.0902323061678135354_dp ), &
   dev_t( 2.4250000000000000722e-2_dp, -1.9729610513118848376_dp ), &
   dev_t( 7.4899999999999994360e-2_dp, -1.4402382675279636631_dp ), &
   dev_t( 7.4999999999999997224e-2_dp, -1.4395314709384559349_dp ), &
   dev_t( 2.0000000000000001110e-1_dp, -8.4162123357291416552e-1_dp ), &
   dev_t( 4.9990000000000001101e-1_dp, -2.5066283008800749239e-4_dp ), &
   dev_t( 5.0000000000000000000e-1_dp, 0.0_dp ), &
   dev_t( 5.0009999999999998899e-1_dp, 2.5066283008800749239e-4_dp ), &
   dev_t( 8.0000000000000004441e-1_dp, 8.4162123357291436380e-1_dp ), &
   dev_t( 9.2500000000000004441e-1_dp, 1.4395314709384562291_dp ), &
   dev_t( 9.2510000000000003340e-1_dp, 1.4402382675279638594_dp ), &
   dev_t( 9.8999999999999999112e-1_dp, 2.3263478740408407676_dp ), &
   dev_t( 9.9999000000000004551e-1_dp, 4.2648907939238407699_dp ), &
   dev_t( 9.9999999999999988898e-1_dp, 8.2095361516013868556_dp ) /)
type(gen_t), parameter, dimension(8) :: gens = (/ &
   gen_t( 0_int64, 0_int64, 0_int64, 0_int64, &
      1.2964561829974752261e-1_dp ), &
   gen_t( 12345_int64, 0_int64, 1_int64, 1_int64, &
      4.5750064074326357577e-2_dp ), &
   gen_t( 12345_int64, 7_int64, 1_int64, 1_int64, &
      1.7140116187588849694e-1_dp ), &
   gen_t( 12345_int64, -7_int64, 1_int64, 1_int64, &
      8.0095374576584721371e-1_dp ), &
   gen_t( 19999_int64, -123456789_int64, 987654_int64, 3_int64, &
      5.9393483410719072335e-1_dp ), &
   gen_t( 1_int64, 1099511627781_int64, 1000000000_int64, 999_int64, &
      9.2545557643397724501e-1_dp ), &
   gen_t( 777_int64, 3_int64, 2_int64, 1_int64, &
      3.7494230996122823729e-1_dp ), &
   gen_t( 777_int64, 3_int64, 2_int64, 2_int64, &
      3.6525881665464121628e-1_dp ) /)
type(z0_t), parameter, dimension(7) :: z0s = (/ &
   z0_t( 0_int64, 0_int64, 1.8555270484536220685_dp ), &
   z0_t( 12345_int64, 3_int64, -6.0125784083832347835e-2_dp ), &
   z0_t( 12345_int64, -3_int64, -1.6235033411347525447_dp ), &
   z0_t( 19999_int64, 250000_int64, -3.0751439286904316055e-1_dp ), &
   z0_t( 42_int64, -1_int64, 3.7873003203963330484e-1_dp ), &
   z0_t( 19999_int64, 4611686018427387903_int64, &
      1.5551304214741957386_dp ), &
   z0_t( 5_int64, -4611686018427387904_int64, &
      3.2773351998408777833e-1_dp ) /)
type(flr_t), parameter, dimension(4) :: flrs = (/ &
   flr_t( 2.0000000000000000000_dp, 1.0000000000000000000_dp, &
      2.0084907026168296375_dp ), &
   flr_t( 2.0000000000000000000_dp, 2.0000000000000000000_dp, &
      2.1666309411753725968_dp ), &
   flr_t( 2.0000000000000000000_dp, 6.0000000000000000000_dp, &
      3.5254166857944317076_dp ), &
   flr_t( 1.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      1.0042453513084148188_dp ) /)
integer(kind=int32) :: ncheck = 0, nfail = 0, i, k, m
integer(kind=int64) :: n, j
real(kind=dp) :: worst, z, z1, phi, phi1, lam, dt, tau, mean, var, c1, &
   zprev, rho, se, t, rate
logical :: ok
integer(kind=int64), parameter :: seed = 4321_int64
integer(kind=int32), parameter :: nz = 200000

write(*,'(a)') ' test_sign: StochasticIgnite (module stochignite)'

!*** 1. AS241 against the exact deviate, 50 digits.
worst = zero
do i = 1, size(devs)
   z = si_normal( devs(i)%u )
   if ( abs( devs(i)%z ) > 1.0e-3_dp ) then
      worst = max( worst, abs( z/devs(i)%z - one ) )
   else
      worst = max( worst, abs( z - devs(i)%z ) )
   end if
end do
call check( worst < 1.0e-15_dp, '1. AS241 against 50 digits, u from '// &
   '2**-54 to 1 - 2**-53, to '//rtoa(worst) )

!*** 2. The generator, bit for bit with Python's integers.
ok = .true.
do i = 1, size(gens)
   if ( abs( si_uniform( gens(i)%seed, gens(i)%j, gens(i)%n, gens(i)%s ) &
      - gens(i)%u ) > zero ) ok = .false.
end do
call check( ok, '2. the generator: u exactly Python''s, 8 cases (negative'// &
   ' and large bins, cycles and sub-steps)' )

!*** 3. Each bin's starting Z: the table through AS241.
worst = zero
do i = 1, size(z0s)
   worst = max( worst, abs( si_z0( z0s(i)%seed, z0s(i)%j ) - z0s(i)%z ) )
end do
call check( worst < 4.0e-15_dp, '3. a bin''s starting Z from the '// &
   'atmospheric table, 7 bins to +-2**62, to '//rtoa(worst) )

!*** 4. The OU step: one bin's Z over nz cycles, dt = TAUZ/20 (one sub-
!***    step) and dt = 2 TAUZ (20 sub-steps): mean 0, variance 1, lag-1
!***    correlation exp(-dt/TAUZ), each within 4 of its standard errors.
ok = .true.
tau = 0.1_dp
do m = 1, 2
   dt = merge( tau/20.0_dp, 2.0_dp*tau, m == 1 )
   rho = exp( -dt/tau )
   z = zero
   mean = zero; var = zero; c1 = zero; zprev = zero
   do k = 1, nz
      n = int( k, int64 )
      call si_step( zero, z, .false., k == 1, seed, 17_int64, n, dt, one, &
         one, one, zero, zero, one, tau, phi, z1, lam )
      if ( k > 1 ) c1 = c1 + zprev*z1
      mean = mean + z1
      var  = var + z1*z1
      zprev = z1
      z = z1
   end do
   mean = mean/real( nz, dp )
   var  = var/real( nz, dp ) - mean**2
   c1   = ( c1/real( nz - 1, dp ) - mean**2 )/var     ! the correlation
   !*** An AR(1) series' standard errors, n = nz: the mean's,
   !*** sqrt((1+rho)/(1-rho)/n); the variance's, sqrt(2(1+rho**2)/
   !*** (1-rho**2)/n); the lag-1 correlation's, sqrt((1-rho**2)/n).
   se   = sqrt( ( one + rho )/( one - rho )/real( nz, dp ) )
   ok = ok .and. abs( mean ) < 4.0_dp*se
   se   = sqrt( 2.0_dp*( one + rho**2 )/( one - rho**2 )/real( nz, dp ) )
   ok = ok .and. abs( var - one ) < 4.0_dp*se
   se   = sqrt( ( one - rho**2 )/real( nz, dp ) )
   ok = ok .and. abs( c1 - rho ) < 4.0_dp*se
   write(*,'(a,f5.2,a,4f9.5)') '         dt/TAUZ = ', dt/tau, &
      ': mean, variance, lag-1 correlation (exact) ', mean, var, c1, rho
end do
call check( ok, '4. the OU step: mean 0, variance 1, lag-1 correlation '// &
   'exp(-dt/TAUZ), one and 20 sub-steps a cycle, 2e5 cycles' )

!*** 5. SIGMA = 0, a clock: phi = MU S t and lam = 1 - exp(-(MU S
!***    t)**AVRAMI), to round-off (S = (1 + 11/7)**2), 1000 steps. MU is
!***    small enough that phi ends near 0.33 and lam near 0.035, where lam
!***    is sensitive to phi (at phi of 3 or more, lam rounds to 1).
phi = zero; z = zero
dt = 1.0e-3_dp
do k = 1, 1000
   call si_step( phi, z, .true., k == 1, seed, 3_int64, int( k, int64 ), &
      dt, 0.05_dp, zero, 3.0_dp, 11.0_dp, 2.0_dp, 7.0_dp, 0.05_dp, phi1, z1, &
      lam )
   phi = phi1; z = z1
end do
t     = 1000.0_dp*dt
rate  = 0.05_dp*( one + 11.0_dp/7.0_dp )**2
worst = max( abs( phi/( rate*t ) - one ), &
   abs( lam/( one - exp( -( rate*t )**3 ) ) - one ) )
write(*,'(a,2f12.8)') '         phi, lam = ', phi, lam
call check( worst < 1.0e-12_dp, '5. SIGMA = 0: the clock, phi = MU S t '// &
   'and lam = 1 - exp(-(MU S t)**AVRAMI), 1000 steps, to '//rtoa(worst) )

!*** 6. TAUZ = 1e30: Z frozen, bit for bit, from its starting value.
z = zero
ok = .true.
do k = 1, 5000
   call si_step( zero, z, .false., k == 1, seed, -42_int64, &
      int( k, int64 ), 1.0e-3_dp, one, one, one, zero, zero, one, 1.0e30_dp, &
      phi, z1, lam )
   z = z1
   if ( abs( z - si_z0( seed, -42_int64 ) ) > zero ) ok = .false.
end do
ok = ok .and. si_nsub( 1.0e-3_dp, 1.0e30_dp ) == 1
call check( ok, '6. TAUZ = 1e30: Z frozen at the table''s value, bit for '// &
   'bit, 5000 steps' )

!*** 7. The floored mean rate: TAUZ = 0.01 us, many bins over 2 us
!***    (200 times TAUZ), phi/(S t) against mu Phi + sigma phi, within
!***    4 standard errors of the ensemble, plus 1e-3 of the rate (the
!***    left-point quadrature's share; about 0.4 standard errors here).
ok = .true.
do i = 1, size(flrs)
   mean = zero; var = zero
   do m = 1, 400
      j = int( m, int64 )
      phi = zero; z = zero
      do k = 1, 200
         call si_step( phi, z, .true., k == 1, seed, j, int( k, int64 ), &
            0.01_dp, flrs(i)%mu, flrs(i)%sigma, one, zero, zero, one, &
            0.01_dp, phi1, z1, lam )
         phi = phi1; z = z1
      end do
      mean = mean + phi/2.0_dp
      var  = var + ( phi/2.0_dp )**2
   end do
   mean = mean/400.0_dp
   var  = var/400.0_dp - mean**2
   se   = sqrt( var/400.0_dp )
   ok = ok .and. abs( mean - flrs(i)%r ) < 4.0_dp*se + 1.0e-3_dp*flrs(i)%r
   write(*,'(a,2f5.1,a,3f9.5)') '         mu, sigma = ', flrs(i)%mu, &
      flrs(i)%sigma, ': mean rate, exact, standard error ', mean, &
      flrs(i)%r, se
end do
call check( ok, '7. the floored mean rate, mu Phi(mu/sigma) + sigma '// &
   'phi(mu/sigma), 4 cases, 400 bins' )

!*** 8. The same SEED, the same bits; another SEED, another draw.
ok = abs( si_uniform( 7_int64, 1_int64, 2_int64, 3_int64 ) - &
   si_uniform( 7_int64, 1_int64, 2_int64, 3_int64 ) ) <= zero .and. &
   abs( si_uniform( 7_int64, 1_int64, 2_int64, 3_int64 ) - &
   si_uniform( 8_int64, 1_int64, 2_int64, 3_int64 ) ) > zero
call check( ok, '8. the same SEED, the same bits; another SEED, another' )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_sign: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_sign: all ', ncheck, ' checks passed'

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

end program test_sign

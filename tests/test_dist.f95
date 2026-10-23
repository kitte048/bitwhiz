program test_dist
!**********************************************************************!
!
!  Purpose:
!    Unit test for module distributions (src/modules/dist_mod.f95).
!    Run by "make test"; the exit status is 0 if every check passes,
!    1 if any check fails. Like the module, it uses nothing from
!    bitwhiz, so the two files can be copied into another code
!    together.
!
!  What it checks:
!    1. Reference values: f, F and S = 1 - F at 42 points of the seven
!       distributions, and the mean of f over [0, 1] for five
!       distributions, three of them in far tails. The expected values
!       are NOT from this module: tests/dist_reference.py computed them
!       from the textbook definitions with 50-digit arithmetic
!       (mpmath; its betainc for the incomplete beta function).
!    2. Identities that need no reference: F + S = 1; F never
!       decreases; the mean from F equals a numerical integral of f;
!       beta(1,1) is uniform; I_(1/2)(a,a) = 1/2; split normal with
!       equal spreads, and sinh-arcsinh with eps = 0 and delta = 1,
!       are the normal; sinh-arcsinh mirrors when eps changes sign;
!       Cauchy's F is 3/4 one scale past its center.
!    3. The kinetic-energy factor, the integral of f^2 over [0, 1],
!       against its closed form (linear 1 + s^2/3; beta
!       B(2a-1,2b-1)/B(a,b)^2).
!    4. The beta density at its ends (infinite, 1/B or 0).
!    5. dist_set: names case-blind; unknown names, wrong parameter
!       counts and out-of-range parameters are refused, with the
!       right error code and a message that says why.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/22/26    D. E. Kittell        Original code
!                (with Claude)
!    10/23/26    D. E. Kittell        Tolerances follow each value's
!                (with Claude)        condition number (row_tol), not
!                                     one number: the sinh-arcsinh
!                                     mirror check, deep in a tail,
!                                     failed on macOS by round-off;
!                                     its grid is now exact in binary
!
!**********************************************************************!
use, intrinsic :: iso_fortran_env, only: real64, int32
use distributions, only: dist_t, dist_set, dist_nparam, dist_pdf, &
   dist_cdf, dist_sf, dist_mean, dist_support
implicit none

integer, parameter :: wp = real64

!**********************************************************************!
! Data dictionary: reference points and means (tests/dist_reference.py).
!**********************************************************************!
type :: ref_t
   character(len=16)   :: name          ! distribution
   integer(kind=int32) :: np            ! its number of parameters
   real(kind=wp)       :: p(4)          ! the parameters (unused: 0)
   real(kind=wp)       :: x             ! where
   real(kind=wp)       :: f             ! f(x), expected
   real(kind=wp)       :: cdf           ! F(x), expected
   real(kind=wp)       :: sf            ! S(x) = 1 - F(x), expected
end type ref_t

type :: mref_t
   character(len=16)   :: name
   integer(kind=int32) :: np
   real(kind=wp)       :: p(4)
   real(kind=wp)       :: mean          ! the mean of f over [0, 1]
end type mref_t

type(ref_t), parameter, dimension(42) :: ref = (/ &
! 42 rows (tests/dist_reference.py): name, number of parameters,
! parameters, x, f(x), F(x), S(x)
   ref_t( 'uniform', 0, (/ 0.0_wp, 0.0_wp, 0.0_wp, 0.0_wp /), -0.1_wp, &
      0.0_wp, 0.0_wp, 1.0_wp ), &
   ref_t( 'uniform', 0, (/ 0.0_wp, 0.0_wp, 0.0_wp, 0.0_wp /), 0.3_wp, &
      1.0_wp, 2.999999999999999889E-1_wp, 7.000000000000000111E-1_wp ), &
   ref_t( 'uniform', 0, (/ 0.0_wp, 0.0_wp, 0.0_wp, 0.0_wp /), 1.5_wp, &
      0.0_wp, 1.0_wp, 0.0_wp ), &
   ref_t( 'linear', 1, (/ 0.5_wp, 0.0_wp, 0.0_wp, 0.0_wp /), 0.25_wp, &
      7.5E-1_wp, 1.5625E-1_wp, 8.4375E-1_wp ), &
   ref_t( 'linear', 1, (/ 0.5_wp, 0.0_wp, 0.0_wp, 0.0_wp /), 0.9_wp, &
      1.4000000000000000222_wp, 8.5500000000000003109E-1_wp, 1.4499999999999996891E-1_wp ), &
   ref_t( 'linear', 1, (/ -1.0_wp, 0.0_wp, 0.0_wp, 0.0_wp /), 0.2_wp, &
      1.5999999999999999778_wp, 3.6000000000000001776E-1_wp, 6.3999999999999998224E-1_wp ), &
   ref_t( 'linear', 1, (/ 1.0_wp, 0.0_wp, 0.0_wp, 0.0_wp /), 0.999_wp, &
      1.9979999999999999982_wp, 9.9800099999999999823E-1_wp, 1.9990000000000017746E-3_wp ), &
   ref_t( 'beta', 2, (/ 2.0_wp, 5.0_wp, 0.0_wp, 0.0_wp /), 0.1_wp, &
      1.9683000000000000607_wp, 1.1426500000000001093E-1_wp, 8.8573499999999998907E-1_wp ), &
   ref_t( 'beta', 2, (/ 2.0_wp, 5.0_wp, 0.0_wp, 0.0_wp /), 0.3_wp, &
      2.1609000000000000571_wp, 5.7982499999999997601E-1_wp, 4.2017500000000002399E-1_wp ), &
   ref_t( 'beta', 2, (/ 2.0_wp, 5.0_wp, 0.0_wp, 0.0_wp /), 0.8_wp, &
      3.8399999999999968026E-2_wp, 9.9840000000000000171E-1_wp, 1.5999999999999982947E-3_wp ), &
   ref_t( 'beta', 2, (/ 0.5_wp, 0.5_wp, 0.0_wp, 0.0_wp /), 0.01_wp, &
      3.1991347258556542789_wp, 6.3768560858519848583E-2_wp, 9.3623143914148015142E-1_wp ), &
   ref_t( 'beta', 2, (/ 0.5_wp, 0.5_wp, 0.0_wp, 0.0_wp /), 0.5_wp, &
      6.3661977236758134308E-1_wp, 5.0E-1_wp, 5.0E-1_wp ), &
   ref_t( 'beta', 2, (/ 0.5_wp, 0.5_wp, 0.0_wp, 0.0_wp /), 0.999_wp, &
      1.0070879119947089694E+1_wp, 9.7986495836662250008E-1_wp, 2.0135041633377499917E-2_wp ), &
   ref_t( 'beta', 2, (/ 0.3_wp, 2.0_wp, 0.0_wp, 0.0_wp /), 1E-06_wp, &
      6.1810772695148881159E+3_wp, 2.0603606747314900629E-2_wp, 9.7939639325268509937E-1_wp ), &
   ref_t( 'beta', 2, (/ 0.3_wp, 2.0_wp, 0.0_wp, 0.0_wp /), 0.4_wp, &
      4.4439980886543864467E-1_wp, 8.9639619566020118608E-1_wp, 1.0360380433979881392E-1_wp ), &
   ref_t( 'beta', 2, (/ 50.0_wp, 60.0_wp, 0.0_wp, 0.0_wp /), 0.3_wp, &
      2.972503226352446383E-2_wp, 3.4341151876628865457E-4_wp, 9.9965658848123371135E-1_wp ), &
   ref_t( 'beta', 2, (/ 50.0_wp, 60.0_wp, 0.0_wp, 0.0_wp /), 0.45_wp, &
      8.360039852227419138_wp, 4.6423529143060362867E-1_wp, 5.3576470856939637133E-1_wp ), &
   ref_t( 'beta', 2, (/ 50.0_wp, 60.0_wp, 0.0_wp, 0.0_wp /), 0.6_wp, &
      7.6620900133327905715E-2_wp, 9.9894322877191006598E-1_wp, 1.0567712280899340152E-3_wp ), &
   ref_t( 'beta', 2, (/ 500.0_wp, 3.0_wp, 0.0_wp, 0.0_wp /), 0.99_wp, &
      4.1729536013468700704E+1_wp, 1.2171819836073070433E-1_wp, 8.7828180163926929567E-1_wp ), &
   ref_t( 'beta', 2, (/ 2.0_wp, 1.0_wp, 0.0_wp, 0.0_wp /), 0.6_wp, &
      1.1999999999999999556_wp, 3.5999999999999997335E-1_wp, 6.4000000000000002665E-1_wp ), &
   ref_t( 'normal', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 0.5_wp, &
      3.9894228040143265579_wp, 5.0E-1_wp, 5.0E-1_wp ), &
   ref_t( 'normal', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 0.6_wp, &
      2.4197072451914340353_wp, 8.4134474606854288142E-1_wp, 1.5865525393145711858E-1_wp ), &
   ref_t( 'normal', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 0.1_wp, &
      1.3383022576488549293E-3_wp, 3.1671241833119958399E-5_wp, 9.9996832875816688004E-1_wp ), &
   ref_t( 'normal', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 1.5_wp, &
      7.6945986267064616328E-22_wp, 1.0_wp, 7.6198530241605687796E-24_wp ), &
   ref_t( 'normal', 2, (/ -8.0_wp, 1.0_wp, 0.0_wp, 0.0_wp /), 0.0_wp, &
      5.052271083536892288E-15_wp, 9.999999999999993779E-1_wp, 6.2209605742717841235E-16_wp ), &
   ref_t( 'normal', 2, (/ -8.0_wp, 1.0_wp, 0.0_wp, 0.0_wp /), 1.0_wp, &
      1.0279773571668914795E-18_wp, 9.9999999999999999989E-1_wp, 1.1285884059538406477E-19_wp ), &
   ref_t( 'split_normal', 3, (/ 0.3_wp, 0.05_wp, 0.2_wp, 0.0_wp /), 0.1_wp, &
      1.0706418061190851915E-3_wp, 1.2668496733247998921E-5_wp, 9.99987331503266752E-1_wp ), &
   ref_t( 'split_normal', 3, (/ 0.3_wp, 0.05_wp, 0.2_wp, 0.0_wp /), 0.3_wp, &
      3.1915382432114614235_wp, 1.9999999999999995559E-1_wp, 8.0000000000000004441E-1_wp ), &
   ref_t( 'split_normal', 3, (/ 0.3_wp, 0.05_wp, 0.2_wp, 0.0_wp /), 0.5_wp, &
      1.9357657961531467984_wp, 7.4615159370966870364E-1_wp, 2.5384840629033129636E-1_wp ), &
   ref_t( 'split_normal', 3, (/ 0.3_wp, 0.05_wp, 0.2_wp, 0.0_wp /), 1.0_wp, &
      6.9814615603660839159E-3_wp, 9.9962779347354315973E-1_wp, 3.722065264568402726E-4_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, -0.8_wp, 1.0_wp /), 0.0_wp, &
      6.5005326380043392729E-1_wp, 1.7047526167858779678E-1_wp, 8.2952473832141220322E-1_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, -0.8_wp, 1.0_wp /), 0.3_wp, &
      1.4104584978837649167_wp, 4.6753670679988677622E-1_wp, 5.3246329320011322378E-1_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, -0.8_wp, 1.0_wp /), 0.5_wp, &
      1.7983810108699427493_wp, 8.1275812746118017728E-1_wp, 1.8724187253881982272E-1_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, -0.8_wp, 1.0_wp /), 0.9_wp, &
      8.1592820093852001342E-5_wp, 9.9999842459092106417E-1_wp, 1.575409078935830803E-6_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, -0.8_wp, 1.0_wp /), 1.0_wp, &
      3.1117339896070808317E-7_wp, 9.9999999512109952164E-1_wp, 4.8789004783550328487E-9_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, 0.0_wp, 0.5_wp /), 0.9_wp, &
      4.1653789405345822963E-1_wp, 7.841105962175493529E-1_wp, 2.158894037824506471E-1_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, 1.5_wp, 2.0_wp /), 0.2_wp, &
      1.2469421189122683753E-128_wp, 3.7559851817336441989E-132_wp, 1.0_wp ), &
   ref_t( 'sinh_arcsinh', 4, (/ 0.5_wp, 0.2_wp, 1.5_wp, 2.0_wp /), 0.7_wp, &
      2.8175882497986551013_wp, 6.0479598414419384153E-1_wp, 3.9520401585580615847E-1_wp ), &
   ref_t( 'cauchy', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 0.6_wp, &
      1.5915494309189537111_wp, 7.4999999999999995583E-1_wp, 2.5000000000000004417E-1_wp ), &
   ref_t( 'cauchy', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), -100.0_wp, &
      3.151501903750900365E-6_wp, 3.1672615038177674419E-4_wp, 9.9968327384961822326E-1_wp ), &
   ref_t( 'cauchy', 2, (/ 0.5_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 0.2_wp, &
      3.1830988618379070688E-1_wp, 1.0241638234956673466E-1_wp, 8.9758361765043326534E-1_wp ), &
   ref_t( 'cauchy', 2, (/ 0.5_wp, 1E-06_wp, 0.0_wp, 0.0_wp /), 1.0_wp, &
      1.2732395447300696704E-6_wp, 9.9999936338022763327E-1_wp, 6.366197723667324879E-7_wp ) /)

! 5 rows: name, number of parameters, parameters, mean of f on [0, 1]
type(mref_t), parameter, dimension(5) :: mref = (/ &
   mref_t( 'normal', 2, (/ -8.0_wp, 1.0_wp, 0.0_wp, 0.0_wp /), 6.2198319858658302829E-16_wp ), &
   mref_t( 'normal', 2, (/ 9.0_wp, 1.0_wp, 0.0_wp, 0.0_wp /), 6.2198319858658302829E-16_wp ), &
   mref_t( 'cauchy', 2, (/ 50.0_wp, 0.1_wp, 0.0_wp, 0.0_wp /), 1.2992187215849198936E-5_wp ), &
   mref_t( 'sinh_arcsinh', 4, (/ -2.0_wp, 0.25_wp, 0.3_wp, 1.2_wp /), 2.2557833540027109261E-25_wp ), &
   mref_t( 'beta', 2, (/ 2.0_wp, 5.0_wp, 0.0_wp, 0.0_wp /), 1.0_wp ) /)

!**********************************************************************!
! Data dictionary: everything else.
!**********************************************************************!
!*** Tolerances, relative. tol_closed for values that are a few
!*** operations from their inputs. Values far in a tail, or built from
!*** large logarithms, are ill-conditioned: one unit in the last place
!*** of an intermediate result becomes many in the answer, and how
!*** many depends on the machine's math library (macOS and Linux
!*** differ). row_tol scales the tolerance by each reference value's
!*** condition number (see there), so the check is as tight as the
!*** arithmetic allows, on any machine, and no tighter.
real(kind=wp), parameter :: tol_closed = 1.0e-13_wp
real(kind=wp), parameter :: tol_beta   = 1.0e-12_wp
real(kind=wp), parameter :: tol_quad   = 1.0e-9_wp    ! Simpson, n = 4000
real(kind=wp), parameter :: zero = 0.0_wp, half = 0.5_wp, one = 1.0_wp
integer(kind=int32) :: ncheck = 0, nfail = 0
integer(kind=int32) :: j, k, ierr
real(kind=wp) :: tol, got, a, b, x, y, lnb, worst
real(kind=wp) :: lo, hi
logical :: ok
type(dist_t) :: d, d2
character(len=200) :: msg
real(kind=wp), parameter, dimension(4) :: ahalf = &
   (/ 0.3_wp, 2.5_wp, 80.0_wp, 3000.0_wp /)

!*** The sample distributions for the identity checks.
integer(kind=int32), parameter :: ns = 9
character(len=16), parameter, dimension(ns) :: sname = (/ &
   'uniform         ', 'linear          ', 'beta            ', &
   'beta            ', 'normal          ', 'split_normal    ', &
   'sinh_arcsinh    ', 'sinh_arcsinh    ', 'cauchy          ' /)
integer(kind=int32), parameter, dimension(ns) :: snp = &
   (/ 0, 1, 2, 2, 2, 3, 4, 4, 2 /)
real(kind=wp), parameter, dimension(4,ns) :: spar = reshape( (/ &
   0.0_wp,  0.0_wp,  0.0_wp, 0.0_wp, &
  -0.7_wp,  0.0_wp,  0.0_wp, 0.0_wp, &
   2.0_wp,  5.0_wp,  0.0_wp, 0.0_wp, &
   0.5_wp,  0.8_wp,  0.0_wp, 0.0_wp, &
   0.4_wp,  0.15_wp, 0.0_wp, 0.0_wp, &
   0.3_wp,  0.05_wp, 0.2_wp, 0.0_wp, &
   0.5_wp,  0.2_wp, -0.8_wp, 1.0_wp, &
   0.6_wp,  0.1_wp,  1.5_wp, 0.6_wp, &
   0.5_wp,  0.1_wp,  0.0_wp, 0.0_wp /), (/ 4, ns /) )

!=====================================================================!
! 1. Reference values.
!=====================================================================!
do j = 1, size( ref )
   call dist_set( d, ref(j)%name, ref(j)%p(1:ref(j)%np), ierr, msg )
   if ( ierr /= 0 ) then
      call check( .false., 'reference '//itoa(j)//': '//trim(msg) )
      cycle
   end if
   tol = row_tol( ref(j) )
   ok = near_rel( dist_pdf( d, ref(j)%x ), ref(j)%f, tol ) .and. &
        near_rel( dist_cdf( d, ref(j)%x ), ref(j)%cdf, tol ) .and. &
        near_rel( dist_sf( d, ref(j)%x ), ref(j)%sf, tol )
   call check( ok, trim(ref(j)%name)//' at x = '//num(ref(j)%x)// &
      ': f, F and S match the 50-digit values' )
   if ( .not. ok ) then
      write(*,'(9x,a,3es24.16)') 'got     ', dist_pdf( d, ref(j)%x ), &
         dist_cdf( d, ref(j)%x ), dist_sf( d, ref(j)%x )
      write(*,'(9x,a,3es24.16)') 'expected', ref(j)%f, ref(j)%cdf, ref(j)%sf
   end if
end do
do j = 1, size( mref )
   call dist_set( d, mref(j)%name, mref(j)%p(1:mref(j)%np), ierr, msg )
   got = dist_mean( d, zero, one )
   call check( ierr == 0 .and. near_rel( got, mref(j)%mean, tol_beta ), &
      trim(mref(j)%name)//': mean of f on [0, 1] = '//num(mref(j)%mean)// &
      ' (from the accurate tail)' )
end do

!=====================================================================!
! 2. Identities.
!=====================================================================!
do k = 1, ns
   call dist_set( d, sname(k), spar(1:snp(k),k), ierr, msg )
   if ( ierr /= 0 ) then
      call check( .false., 'sample '//trim(sname(k))//': '//trim(msg) )
      cycle
   end if
   ! F + S = 1, and F never decreases, on a grid from -0.5 to 1.5.
   worst = zero
   ok = .true.
   do j = 0, 2000
      x = -half + real( j, wp )/1000.0_wp
      worst = max( worst, abs( dist_cdf( d, x ) + dist_sf( d, x ) - one ) )
      if ( j > 0 ) then
         if ( dist_cdf( d, x ) < dist_cdf( d, x - 0.001_wp ) ) ok = .false.
      end if
   end do
   call check( worst <= 4.0_wp*epsilon( one ), trim(sname(k))//': F + S = 1 '// &
      'to round-off (worst '//num(worst)//')' )
   call check( ok, trim(sname(k))//': F never decreases' )
   ! The mean from F against Simpson's rule on f, where f is finite.
   a = 0.2_wp
   b = 0.7_wp
   got = dist_mean( d, a, b )*( b - a )
   y = simpson( d, a, b, 4000 )
   call check( near_rel( got, y, tol_quad ), trim(sname(k))// &
      ': F(0.7) - F(0.2) equals the integral of f' )
end do

call dist_set( d, 'beta', (/ one, one /), ierr, msg )
call dist_set( d2, 'uniform', (/ real(kind=wp) :: /), ierr, msg )
ok = .true.
do j = 0, 10
   x = real( j, wp )/10.0_wp
   if ( .not. near_rel( dist_cdf( d, x ), dist_cdf( d2, x ), tol_beta ) ) ok = .false.
end do
call check( ok, 'beta(1, 1) is uniform' )

call dist_set( d, 'beta', (/ 2.0_wp, one /), ierr, msg )
call check( near_rel( dist_cdf( d, 0.37_wp ), 0.37_wp**2, tol_beta ), &
   'beta(2, 1): F = x^2' )

worst = zero
do j = 1, 4
   a = ahalf(j)
   call dist_set( d, 'beta', (/ a, a /), ierr, msg )
   worst = max( worst, abs( dist_cdf( d, half ) - half ) )
end do
call check( worst <= 1.0e-13_wp, 'I_(1/2)(a, a) = 1/2 for a = 0.3, 2.5, 80, 3000' )

call dist_set( d, 'split_normal', (/ 0.4_wp, 0.15_wp, 0.15_wp /), ierr, msg )
call dist_set( d2, 'normal', (/ 0.4_wp, 0.15_wp /), ierr, msg )
call check( same_on_grid( d, d2, tol_closed ), &
   'split_normal with equal spreads is normal' )
call dist_set( d, 'split_normal', (/ 0.3_wp, 0.05_wp, 0.2_wp /), ierr, msg )
call check( near_rel( dist_cdf( d, 0.3_wp ), 0.05_wp/0.25_wp, tol_closed ), &
   'split_normal: F(m) = sigma_left/(sigma_left + sigma_right)' )

call dist_set( d, 'sinh_arcsinh', (/ 0.4_wp, 0.15_wp, zero, one /), ierr, msg )
call check( same_on_grid( d, d2, tol_closed ), &
   'sinh_arcsinh with eps = 0, delta = 1 is normal' )
call dist_set( d, 'sinh_arcsinh', (/ 0.5_wp, 0.2_wp, 0.9_wp, 1.7_wp /), ierr, msg )
call dist_set( d2, 'sinh_arcsinh', (/ 0.5_wp, 0.2_wp, -0.9_wp, 1.7_wp /), ierr, msg )
! On y = -1/2, -7/16, ..., 1/2: 1/2 + y and 1/2 - y are exact in
! binary, so the two sides see exactly opposite arguments, and must
! agree to round-off even far in the tails (F down to 1e-91 here,
! where any difference in the argument is amplified by z^2 ~ 400).
ok = .true.
do j = 0, 16
   y = -half + real( j, wp )/16.0_wp
   if ( .not. near_rel( dist_cdf( d, 0.5_wp + y ), dist_sf( d2, 0.5_wp - y ), &
        tol_closed ) ) ok = .false.
end do
call check( ok, 'sinh_arcsinh mirrors: F(loc + y; eps) = 1 - F(loc - y; -eps)' )
call dist_set( d, 'sinh_arcsinh', (/ 0.5_wp, 0.2_wp, zero, 0.4_wp /), ierr, msg )
call check( near_rel( dist_cdf( d, 0.5_wp ), half, tol_closed ), &
   'sinh_arcsinh with eps = 0: F(loc) = 1/2 for any delta' )

call dist_set( d, 'cauchy', (/ 0.5_wp, 0.1_wp /), ierr, msg )
call check( near_rel( dist_cdf( d, 0.6_wp ), 0.75_wp, tol_closed ) .and. &
   near_rel( dist_cdf( d, 0.5_wp ), half, tol_closed ), &
   'cauchy: F(x0) = 1/2, F(x0 + gamma) = 3/4' )

call dist_set( d, 'linear', (/ -0.6_wp /), ierr, msg )
call check( near_rel( dist_pdf( d, half ), one, tol_closed ), 'linear: f(1/2) = 1' )

call dist_set( d, 'normal', (/ 0.5_wp, 0.1_wp /), ierr, msg )
call check( near_rel( dist_cdf( d, 0.6_wp ), 0.84134474606854293_wp, tol_closed ), &
   'normal: F(mu + sigma) = Phi(1) = 0.8413447460685429' )

!=====================================================================!
! 3. The kinetic-energy factor, the integral of f^2 on [0, 1].
!=====================================================================!
call dist_set( d, 'linear', (/ 0.6_wp /), ierr, msg )
call check( near_rel( simpson2( d, zero, one, 4000 ), one + 0.36_wp/3.0_wp, &
   tol_quad ), 'linear: integral of f^2 = 1 + s^2/3' )
a = 2.0_wp
b = 5.0_wp
lnb = log_gamma( 2.0_wp*a - one ) + log_gamma( 2.0_wp*b - one ) - &
   log_gamma( 2.0_wp*a + 2.0_wp*b - 2.0_wp ) - 2.0_wp*( log_gamma( a ) + &
   log_gamma( b ) - log_gamma( a + b ) )
call dist_set( d, 'beta', (/ a, b /), ierr, msg )
call check( near_rel( simpson2( d, zero, one, 4000 ), exp( lnb ), tol_quad ), &
   'beta(2, 5): integral of f^2 = B(3, 9)/B(2, 5)^2' )

!=====================================================================!
! 4. The beta density at its ends.
!=====================================================================!
call dist_set( d, 'beta', (/ 0.5_wp, 2.0_wp /), ierr, msg )
call check( dist_pdf( d, zero ) >= huge( one ), 'beta(0.5, 2): f(0) is infinite (huge)' )
call dist_set( d, 'beta', (/ 2.0_wp, 0.5_wp /), ierr, msg )
call check( dist_pdf( d, one ) >= huge( one ), 'beta(2, 0.5): f(1) is infinite (huge)' )
call dist_set( d, 'beta', (/ one, 3.0_wp /), ierr, msg )
call check( near_rel( dist_pdf( d, zero ), 3.0_wp, tol_beta ), 'beta(1, 3): f(0) = 1/B(1,3) = 3' )
call dist_set( d, 'beta', (/ 3.0_wp, 2.0_wp /), ierr, msg )
call check( dist_pdf( d, zero ) <= zero .and. dist_pdf( d, one ) <= zero, &
   'beta(3, 2): f = 0 at both ends' )

!=====================================================================!
! 5. dist_set and dist_nparam.
!=====================================================================!
call dist_set( d, 'Beta', (/ 2.0_wp, 3.0_wp /), ierr, msg )
call check( ierr == 0, 'names are case-blind ("Beta")' )
call dist_support( d, lo, hi )
call check( lo <= zero .and. lo >= zero .and. hi <= one .and. hi >= one, &
   'beta lives on [0, 1]' )
call dist_set( d, 'normal', (/ zero, one /), ierr, msg )
call dist_support( d, lo, hi )
call check( lo <= -huge( one ) .and. hi >= huge( one ), 'normal lives on the whole line' )
call check( dist_nparam( 'uniform' ) == 0 .and. dist_nparam( 'linear' ) == 1 &
   .and. dist_nparam( 'beta' ) == 2 .and. dist_nparam( 'normal' ) == 2 .and. &
   dist_nparam( 'split_normal' ) == 3 .and. dist_nparam( 'sinh_arcsinh' ) == 4 &
   .and. dist_nparam( 'cauchy' ) == 2 .and. dist_nparam( 'gauss' ) == -1, &
   'dist_nparam: 0, 1, 2, 2, 3, 4, 2, and -1 for no such name' )
call refused( 'gauss', (/ zero, one /), 1, 'is not a distribution' )
call refused( 'beta', (/ 2.0_wp /), 2, 'beta takes 2 parameters (a b), not 1' )
call refused( 'uniform', (/ one /), 2, 'uniform takes 0 parameters' )
call refused( 'sinh_arcsinh', (/ zero, one, zero /), 2, 'takes 4 parameters' )
call refused( 'linear', (/ 1.5_wp /), 3, 's must be from -1 to 1' )
call refused( 'beta', (/ zero, one /), 3, 'a must be from 1e-6 to 1e6' )
call refused( 'beta', (/ one, 2.0e6_wp /), 3, 'b must be from 1e-6 to 1e6' )
call refused( 'normal', (/ 0.5_wp, -0.1_wp /), 3, 'sigma must be from 1e-6 to 1e6' )
call refused( 'normal', (/ 2.0e6_wp, 0.1_wp /), 3, 'mu must be from -1e6 to 1e6' )
call refused( 'split_normal', (/ 0.5_wp, 0.1_wp, zero /), 3, 'sigma_right must be' )
call refused( 'sinh_arcsinh', (/ 0.5_wp, 0.1_wp, zero, zero /), 3, 'delta must be' )
call refused( 'cauchy', (/ 0.5_wp, zero /), 3, 'gamma must be' )

!=====================================================================!
! Summary. Exit status 1 on any failure, so 'make test' stops.
!=====================================================================!
if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_dist: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   stop 1, quiet=.true.
end if
write(*,'(a,i0,a)') ' test_dist: all ', ncheck, ' checks passed'

contains

   !*** Count one check, and print it.
   subroutine check( ok, what )
   logical, intent(in) :: ok
   character(len=*), intent(in) :: what
   ncheck = ncheck + 1
   if ( ok ) then
      write(*,'(a)') '   pass  '//what
   else
      write(*,'(a)') '   FAIL  '//what
      nfail = nfail + 1
   end if
   end subroutine check

   !*** got within tol (relative) of want; both 0 counts as near.
   logical function near_rel( got, want, tol )
   real(kind=wp), intent(in) :: got, want, tol
   near_rel = abs( got - want ) <= tol*abs( want ) .or. &
      ( abs( want ) < tiny( one ) .and. abs( got ) < tiny( one ) )
   end function near_rel

   !*** F and f of a distribution d1 and a normal d2 agree on a grid
   !*** from -0.5 to 1.5, to tol times 1 + z^2, z = (x - mu)/sigma (the
   !*** two compute z by different routes, and a tail value's relative
   !*** error is about z^2 times z's).
   logical function same_on_grid( d1, d2, tol )
   type(dist_t), intent(in) :: d1, d2
   real(kind=wp), intent(in) :: tol
   integer(kind=int32) :: i
   real(kind=wp) :: xx, t
   same_on_grid = .true.
   do i = 0, 40
      xx = -half + real( i, wp )/20.0_wp
      t  = tol*( one + ( ( xx - d2%p(1) )/d2%p(2) )**2 )
      if ( .not. ( near_rel( dist_cdf( d1, xx ), dist_cdf( d2, xx ), t ) .and. &
           near_rel( dist_sf( d1, xx ), dist_sf( d2, xx ), t ) .and. &
           near_rel( dist_pdf( d1, xx ), dist_pdf( d2, xx ), t ) ) ) &
         same_on_grid = .false.
   end do
   end function same_on_grid

   !******************************************************************!
   ! The tolerance for one reference row, from its condition number:  !
   !  - normal family (normal, split_normal): a tail value's relative !
   !    error is about z^2 times z's, z = (x - center)/spread;        !
   !  - sinh_arcsinh: z = sinh(w), w = delta asinh(y) - eps, and w's  !
   !    error grows with |w|: z^2 (1 + |w|);                          !
   !  - beta: f and F are exp( a ln x + b ln(1-x) - ln B(a,b) ); each !
   !    term's rounding is about its size times epsilon, so the sum   !
   !    of their sizes (ln B from three log_gamma) sets the error;    !
   !    1e-14 per unit, never below tol_closed;                       !
   !  - the rest (uniform, linear, cauchy): tol_closed.               !
   !******************************************************************!
   real(kind=wp) function row_tol( r )
   type(ref_t), intent(in) :: r
   real(kind=wp) :: z, w, yy, terms
   select case ( trim( r%name ) )
   case ( 'normal' )
      z = ( r%x - r%p(1) )/r%p(2)
      row_tol = tol_closed*( one + z*z )
   case ( 'split_normal' )
      if ( r%x < r%p(1) ) then
         z = ( r%x - r%p(1) )/r%p(2)
      else
         z = ( r%x - r%p(1) )/r%p(3)
      end if
      row_tol = tol_closed*( one + z*z )
   case ( 'sinh_arcsinh' )
      yy = ( r%x - r%p(1) )/r%p(2)
      w  = min( abs( r%p(4)*asinh( yy ) - r%p(3) ), 30.0_wp )
      z  = sinh( w )
      row_tol = tol_closed*( one + z*z*( one + w ) )
   case ( 'beta' )
      terms = abs( log_gamma( r%p(1) ) ) + abs( log_gamma( r%p(2) ) ) + &
         abs( log_gamma( r%p(1) + r%p(2) ) )
      if ( r%x > zero .and. r%x < one ) terms = terms + &
         abs( r%p(1)*log( r%x ) ) + abs( r%p(2)*log( one - r%x ) )
      row_tol = max( tol_closed, 1.0e-14_wp*terms )
   case default
      row_tol = tol_closed
   end select
   end function row_tol

   !*** Simpson's rule for the integral of f over [a, b], n even.
   real(kind=wp) function simpson( d, a, b, n )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(in) :: a, b
   integer(kind=int32), intent(in) :: n
   integer(kind=int32) :: i
   real(kind=wp) :: h, s
   h = ( b - a )/real( n, wp )
   s = dist_pdf( d, a ) + dist_pdf( d, b )
   do i = 1, n - 1
      s = s + real( 2*( 1 + mod( i, 2 ) ), wp )*dist_pdf( d, a + real( i, wp )*h )
   end do
   simpson = s*h/3.0_wp
   end function simpson

   !*** The same for f^2.
   real(kind=wp) function simpson2( d, a, b, n )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(in) :: a, b
   integer(kind=int32), intent(in) :: n
   integer(kind=int32) :: i
   real(kind=wp) :: h, s
   h = ( b - a )/real( n, wp )
   s = dist_pdf( d, a )**2 + dist_pdf( d, b )**2
   do i = 1, n - 1
      s = s + real( 2*( 1 + mod( i, 2 ) ), wp )*dist_pdf( d, a + real( i, wp )*h )**2
   end do
   simpson2 = s*h/3.0_wp
   end function simpson2

   !*** dist_set must refuse name/p with error code want, and a message
   !*** containing text.
   subroutine refused( name, p, want, text )
   character(len=*), intent(in) :: name, text
   real(kind=wp), intent(in) :: p(:)
   integer(kind=int32), intent(in) :: want
   type(dist_t) :: dd
   integer(kind=int32) :: ie
   character(len=200) :: m
   call dist_set( dd, name, p, ie, m )
   call check( ie == want .and. index( m, text ) > 0, 'refused: '//trim(m) )
   end subroutine refused

   function itoa( n ) result( s )
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim( buf )
   end function itoa

   function num( v ) result( s )
   real(kind=wp), intent(in) :: v
   character(len=:), allocatable :: s
   character(len=24) :: buf
   write( buf, '(g12.5)' ) v
   s = trim( adjustl( buf ) )
   end function num

end program test_dist

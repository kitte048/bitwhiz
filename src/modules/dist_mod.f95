module distributions
!**********************************************************************!
!
!  Purpose:
!    Probability distributions: densities, cumulative distributions
!    and interval means, by name. Self-contained ON PURPOSE: it uses
!    nothing from bitwhiz (its kinds come from iso_fortran_env), so
!    this file and its unit test, tests/test_dist.f95, can be copied
!    into another code unchanged. bitwhiz uses it for velocity
!    profiles across a layer (xvel_profile; input/README.md).
!
!       dist_set      a distribution from a name and its parameters,
!                     checked; ierr = 0 if all is well, else msg says
!                     what is wrong
!       dist_nparam   how many parameters a name takes (-1: no such
!                     name)
!       dist_pdf      the density, f(x)
!       dist_cdf      the cumulative distribution, F(x)
!       dist_sf       the survival function, 1 - F(x), computed
!                     directly so that it stays accurate where F is
!                     close to 1
!       dist_mean     the average of f over [a, b], (F(b) - F(a))/(b - a),
!                     from whichever of F and 1 - F is the more accurate
!       dist_support  where f lives: [0, 1], or (-huge, huge)
!
!    The routines that evaluate a distribution are pure or elemental
!    (no saved state), so they are safe in OpenMP loops and work on
!    whole arrays. (dist_set, called once per distribution, is not.)
!
!  The catalogue (parameters in deck order):
!
!     uniform                      f = 1 on [0, 1]
!     linear s                     f = 1 + s(2x - 1) on [0, 1], |s| <= 1
!     beta a b                     f = x^(a-1) (1-x)^(b-1) / B(a,b)
!     normal mu sigma              the Gaussian
!     split_normal m sl sr         a normal on each side of its peak m,
!                                  spread sl on the left, sr on the right
!     sinh_arcsinh loc scale eps delta
!                                  Jones and Pewsey (Biometrika 96, 2009):
!                                  eps the skewness (0 symmetric, either
!                                  sign), delta the tail weight (1 normal,
!                                  below 1 heavier, above 1 lighter)
!     cauchy x0 gamma              location x0, scale gamma
!
!    Every F is a closed form or a standard expansion, never a numerical
!    integral of f: Phi(z) = erfc(-z/sqrt 2)/2 for the normal family;
!    the regularized incomplete beta function I_x(a,b) for beta, by its
!    continued fraction (Abramowitz and Stegun 26.5.8), evaluated with
!    the modified Lentz method. A beta density is infinite at an end
!    when a < 1 or b < 1, but its F is finite, so means over intervals
!    from F are exact.
!
!    Parameter ranges: positive parameters (spreads, scales, shapes)
!    from 1e-6 to 1e6, others from -1e6 to 1e6, and |s| <= 1. Within
!    them no intermediate result overflows, so the routines are safe
!    with floating-point traps on.
!
!    A new distribution is a new id, a new case in each routine, and
!    a line in dist_nparam.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/22/26    D. E. Kittell        Original code (doc/design/
!                (with Claude)        distributions.md): uniform,
!                                     linear, beta, normal, split
!                                     normal, sinh-arcsinh, Cauchy
!
!**********************************************************************!
use, intrinsic :: iso_fortran_env, only: real64, int32
implicit none
private

integer, parameter :: wp = real64

public :: dist_t, dist_set, dist_nparam, dist_pdf, dist_cdf, dist_sf, &
   dist_mean, dist_support, dist_names

!*** The names, as a list for messages.
character(len=*), parameter :: dist_names = 'uniform, linear, beta, '// &
   'normal, split_normal, sinh_arcsinh, cauchy'

!*** Distribution ids.
integer(kind=int32), parameter :: d_none = 0, d_uniform = 1, d_linear = 2, &
   d_beta = 3, d_normal = 4, d_split = 5, d_sas = 6, d_cauchy = 7

!*** A distribution: its id, name, parameters (deck order) and, for
!*** beta, ln B(a,b), computed once.
type :: dist_t
   integer(kind=int32) :: id = d_none
   character(len=16)   :: name = ' '
   real(kind=wp)       :: p(4) = 0.0_wp
   real(kind=wp)       :: lnb  = 0.0_wp
end type dist_t

real(kind=wp), parameter :: zero = 0.0_wp, half = 0.5_wp, one = 1.0_wp
real(kind=wp), parameter :: pi = 3.141592653589793238_wp
real(kind=wp), parameter :: rsqrt2 = 0.7071067811865475244_wp  ! 1/sqrt(2)
real(kind=wp), parameter :: rsqrt2pi = 0.3989422804014326779_wp ! 1/sqrt(2pi)
real(kind=wp), parameter :: pmin = 1.0e-6_wp, pmax = 1.0e6_wp
real(kind=wp), parameter :: wcap = 50.0_wp   ! sinh-arcsinh: |w| beyond
                                             ! this, F is 0 or 1 exactly

contains

   !******************************************************************!
   ! How many parameters a name takes; -1 if it is not a name here.   !
   !******************************************************************!
   pure integer(kind=int32) function dist_nparam( name )
   character(len=*), intent(in) :: name
   select case ( lower( name ) )
   case ( 'uniform' );      dist_nparam = 0
   case ( 'linear' );       dist_nparam = 1
   case ( 'beta' );         dist_nparam = 2
   case ( 'normal' );       dist_nparam = 2
   case ( 'split_normal' ); dist_nparam = 3
   case ( 'sinh_arcsinh' ); dist_nparam = 4
   case ( 'cauchy' );       dist_nparam = 2
   case default;            dist_nparam = -1
   end select
   end function dist_nparam

   !******************************************************************!
   ! A distribution from its name and parameters p (deck order).      !
   ! ierr: 0 all is well; 1 no such name; 2 wrong number of           !
   ! parameters; 3 a parameter out of range. msg says which.          !
   !******************************************************************!
   subroutine dist_set( d, name, p, ierr, msg )
   type(dist_t), intent(out) :: d
   character(len=*), intent(in) :: name
   real(kind=wp), intent(in) :: p(:)
   integer(kind=int32), intent(out) :: ierr
   character(len=*), intent(out) :: msg
   character(len=16) :: nm
   integer(kind=int32) :: np

   ierr = 0
   msg  = ' '
   nm   = lower( name )
   np   = dist_nparam( nm )
   if ( np < 0 ) then
      ierr = 1
      msg  = '"'//trim(name)//'" is not a distribution (one of: '// &
         dist_names//')'
      return
   end if
   if ( size( p ) /= np ) then
      ierr = 2
      msg  = trim(nm)//' takes '//itoa( np )//' parameter'// &
         plural( np )//' ('//trim( pnames( nm ) )//'), not '// &
         itoa( int( size( p ), int32 ) )
      return
   end if
   d%name = nm
   d%p(1:np) = p
   select case ( nm )
   case ( 'uniform' )
      d%id = d_uniform
   case ( 'linear' )
      d%id = d_linear
      if ( abs( p(1) ) > one ) call bad( 's must be from -1 to 1 '// &
         '(so f is never negative)' )
   case ( 'beta' )
      d%id = d_beta
      call positive( p(1), 'a' )
      call positive( p(2), 'b' )
      if ( ierr == 0 ) d%lnb = log_gamma( p(1) ) + log_gamma( p(2) ) - &
         log_gamma( p(1) + p(2) )
   case ( 'normal' )
      d%id = d_normal
      call bounded( p(1), 'mu' )
      call positive( p(2), 'sigma' )
   case ( 'split_normal' )
      d%id = d_split
      call bounded( p(1), 'm' )
      call positive( p(2), 'sigma_left' )
      call positive( p(3), 'sigma_right' )
   case ( 'sinh_arcsinh' )
      d%id = d_sas
      call bounded( p(1), 'loc' )
      call positive( p(2), 'scale' )
      call bounded( p(3), 'eps' )
      call positive( p(4), 'delta' )
   case ( 'cauchy' )
      d%id = d_cauchy
      call bounded( p(1), 'x0' )
      call positive( p(2), 'gamma' )
   end select
   if ( ierr /= 0 ) d%id = d_none

   contains

      subroutine bad( text )
      character(len=*), intent(in) :: text
      if ( ierr /= 0 ) return               ! report the first only
      ierr = 3
      msg  = trim(nm)//': '//text
      end subroutine bad

      subroutine positive( x, what )
      real(kind=wp), intent(in) :: x
      character(len=*), intent(in) :: what
      if ( x < pmin .or. x > pmax ) call bad( what// &
         ' must be from 1e-6 to 1e6' )
      end subroutine positive

      subroutine bounded( x, what )
      real(kind=wp), intent(in) :: x
      character(len=*), intent(in) :: what
      if ( abs( x ) > pmax ) call bad( what//' must be from -1e6 to 1e6' )
      end subroutine bounded

   end subroutine dist_set

   !******************************************************************!
   ! Where f lives: [0, 1] for uniform, linear and beta; the whole    !
   ! line, (-huge, huge), for the others.                             !
   !******************************************************************!
   pure subroutine dist_support( d, lo, hi )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(out) :: lo, hi
   select case ( d%id )
   case ( d_uniform, d_linear, d_beta )
      lo = zero
      hi = one
   case default
      lo = -huge( one )
      hi =  huge( one )
   end select
   end subroutine dist_support

   !******************************************************************!
   ! The density f(x). Zero outside the support. A beta density that  !
   ! is infinite at an end (a < 1 at 0, b < 1 at 1) returns huge.     !
   !******************************************************************!
   elemental real(kind=wp) function dist_pdf( d, x )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(in) :: x
   real(kind=wp) :: y, z, w, a, b, s

   dist_pdf = zero
   select case ( d%id )
   case ( d_uniform )
      if ( x >= zero .and. x <= one ) dist_pdf = one
   case ( d_linear )
      if ( x >= zero .and. x <= one ) dist_pdf = one + d%p(1)*( 2.0_wp*x - one )
   case ( d_beta )
      a = d%p(1)
      b = d%p(2)
      if ( x < zero .or. x > one ) then
         dist_pdf = zero
      else if ( .not. ( x > zero ) ) then      ! x = 0
         dist_pdf = end_value( a )
      else if ( .not. ( x < one ) ) then       ! x = 1
         dist_pdf = end_value( b )
      else
         s = ( a - one )*log( x ) + ( b - one )*log( one - x ) - d%lnb
         if ( s > 700.0_wp ) then
            dist_pdf = huge( one )
         else
            dist_pdf = exp( s )
         end if
      end if
   case ( d_normal )
      z = ( x - d%p(1) )/d%p(2)
      dist_pdf = phi( z )/d%p(2)
   case ( d_split )
      if ( x < d%p(1) ) then
         z = ( x - d%p(1) )/d%p(2)
      else
         z = ( x - d%p(1) )/d%p(3)
      end if
      dist_pdf = 2.0_wp*phi( z )/( d%p(2) + d%p(3) )
   case ( d_sas )
      y = ( x - d%p(1) )/d%p(2)
      w = d%p(4)*asinh( y ) - d%p(3)
      if ( abs( w ) < wcap ) then
         z = sinh( w )
         dist_pdf = d%p(4)*cosh( w )*phi( z )/( d%p(2)*sqrt( one + y*y ) )
      end if
   case ( d_cauchy )
      y = ( x - d%p(1) )/d%p(2)
      dist_pdf = one/( pi*d%p(2)*( one + y*y ) )
   end select

   contains

      !*** The beta density at an end where the power is p - 1
      !*** (p = a at x = 0, p = b at x = 1): infinite, 1/B or 0.
      pure real(kind=wp) function end_value( p )
      real(kind=wp), intent(in) :: p
      if ( p < one ) then
         end_value = huge( one )
      else if ( p > one ) then
         end_value = zero
      else
         end_value = exp( -d%lnb )      ! p = 1: the other factor is 1
      end if
      end function end_value

   end function dist_pdf

   !******************************************************************!
   ! The cumulative distribution F(x) = P(X <= x).                    !
   !******************************************************************!
   elemental real(kind=wp) function dist_cdf( d, x )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(in) :: x
   real(kind=wp) :: y, w, sl, sr

   select case ( d%id )
   case ( d_uniform )
      dist_cdf = min( max( x, zero ), one )
   case ( d_linear )
      if ( x <= zero ) then
         dist_cdf = zero
      else if ( x >= one ) then
         dist_cdf = one
      else
         dist_cdf = x*( one - d%p(1)*( one - x ) )   ! x + s(x^2 - x)
      end if
   case ( d_beta )
      if ( x <= zero ) then
         dist_cdf = zero
      else if ( x >= one ) then
         dist_cdf = one
      else
         dist_cdf = ibeta( d%p(1), d%p(2), d%lnb, x )
      end if
   case ( d_normal )
      dist_cdf = phic( -( x - d%p(1) )/d%p(2) )
   case ( d_split )
      sl = d%p(2)
      sr = d%p(3)
      if ( x < d%p(1) ) then
         dist_cdf = 2.0_wp*sl*phic( -( x - d%p(1) )/sl )/( sl + sr )
      else
         dist_cdf = one - 2.0_wp*sr*phic( ( x - d%p(1) )/sr )/( sl + sr )
      end if
   case ( d_sas )
      y = ( x - d%p(1) )/d%p(2)
      w = d%p(4)*asinh( y ) - d%p(3)
      if ( w >= wcap ) then
         dist_cdf = one
      else if ( w <= -wcap ) then
         dist_cdf = zero
      else
         dist_cdf = phic( -sinh( w ) )
      end if
   case ( d_cauchy )
      y = ( x - d%p(1) )/d%p(2)
      if ( y < zero ) then
         dist_cdf = atan( -one/y )/pi              ! the left tail, exact
      else
         dist_cdf = half + atan( y )/pi
      end if
   case default
      dist_cdf = zero
   end select
   end function dist_cdf

   !******************************************************************!
   ! The survival function S(x) = 1 - F(x) = P(X > x), computed       !
   ! directly: accurate where F is close to 1.                        !
   !******************************************************************!
   elemental real(kind=wp) function dist_sf( d, x )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(in) :: x
   real(kind=wp) :: y, w, sl, sr

   select case ( d%id )
   case ( d_uniform )
      dist_sf = min( max( one - x, zero ), one )
   case ( d_linear )
      if ( x <= zero ) then
         dist_sf = one
      else if ( x >= one ) then
         dist_sf = zero
      else
         dist_sf = ( one - x )*( one + d%p(1)*x )   ! 1 - x - s(x^2 - x)
      end if
   case ( d_beta )
      if ( x <= zero ) then
         dist_sf = one
      else if ( x >= one ) then
         dist_sf = zero
      else
         dist_sf = ibeta( d%p(2), d%p(1), d%lnb, one - x )
      end if
   case ( d_normal )
      dist_sf = phic( ( x - d%p(1) )/d%p(2) )
   case ( d_split )
      sl = d%p(2)
      sr = d%p(3)
      if ( x < d%p(1) ) then
         dist_sf = one - 2.0_wp*sl*phic( -( x - d%p(1) )/sl )/( sl + sr )
      else
         dist_sf = 2.0_wp*sr*phic( ( x - d%p(1) )/sr )/( sl + sr )
      end if
   case ( d_sas )
      y = ( x - d%p(1) )/d%p(2)
      w = d%p(4)*asinh( y ) - d%p(3)
      if ( w >= wcap ) then
         dist_sf = zero
      else if ( w <= -wcap ) then
         dist_sf = one
      else
         dist_sf = phic( sinh( w ) )
      end if
   case ( d_cauchy )
      y = ( x - d%p(1) )/d%p(2)
      if ( y > zero ) then
         dist_sf = atan( one/y )/pi                ! the right tail, exact
      else
         dist_sf = half - atan( y )/pi
      end if
   case default
      dist_sf = one
   end select
   end function dist_sf

   !******************************************************************!
   ! The average of f over [a, b], (F(b) - F(a))/(b - a): from F      !
   ! where F(a) < 1/2, from S(a) - S(b) where it is not, so the       !
   ! difference never comes from two numbers close to 1. b <= a gives !
   ! f(a).                                                            !
   !******************************************************************!
   elemental real(kind=wp) function dist_mean( d, a, b )
   type(dist_t), intent(in) :: d
   real(kind=wp), intent(in) :: a, b
   real(kind=wp) :: fa

   if ( b <= a ) then
      dist_mean = dist_pdf( d, a )
      return
   end if
   fa = dist_cdf( d, a )
   if ( fa < half ) then
      dist_mean = ( dist_cdf( d, b ) - fa )/( b - a )
   else
      dist_mean = ( dist_sf( d, a ) - dist_sf( d, b ) )/( b - a )
   end if
   end function dist_mean

!======================================================================!
!  Helpers.                                                            !
!======================================================================!

   !*** The standard normal density.
   elemental real(kind=wp) function phi( z )
   real(kind=wp), intent(in) :: z
   if ( abs( z ) > 40.0_wp ) then
      phi = zero                       ! below 1e-347: zero in real64
   else
      phi = rsqrt2pi*exp( -half*z*z )
   end if
   end function phi

   !*** The standard normal upper tail, 1 - Phi(z) = erfc(z/sqrt 2)/2,
   !*** accurate for large z (so Phi(z) = phic(-z) is accurate for
   !*** large negative z).
   elemental real(kind=wp) function phic( z )
   real(kind=wp), intent(in) :: z
   phic = half*erfc( z*rsqrt2 )
   end function phic

   !******************************************************************!
   ! The regularized incomplete beta function I_x(a, b), 0 < x < 1:   !
   !                                                                  !
   !    I_x(a,b) = x^a (1-x)^b / ( a B(a,b) ) * 1/K                   !
   !                                                                  !
   ! where K is the continued fraction of A&S 26.5.8. It converges    !
   ! fast for x < (a+1)/(a+b+2); above that, the symmetry             !
   ! I_x(a,b) = 1 - I_(1-x)(b,a) is used instead.                     !
   !******************************************************************!
   elemental real(kind=wp) function ibeta( a, b, lnb, x )
   real(kind=wp), intent(in) :: a, b, lnb, x
   real(kind=wp) :: front
   front = exp( a*log( x ) + b*log( one - x ) - lnb )
   if ( x < ( a + one )/( a + b + 2.0_wp ) ) then
      ibeta = front/( a*betacf( a, b, x ) )
   else
      ibeta = one - front/( b*betacf( b, a, one - x ) )
   end if
   end function ibeta

   !******************************************************************!
   ! K, the continued fraction for I_x(a,b) (A&S 26.5.8),             !
   !                                                                  !
   !    K = 1 + d1/(1 + d2/(1 + d3/(1 + ...)))                        !
   !    d(2m+1) = -(a+m)(a+b+m) x / ( (a+2m)(a+2m+1) )                !
   !    d(2m)   =  m(b-m) x       / ( (a+2m-1)(a+2m) )                !
   !                                                                  !
   ! by the modified Lentz method (Lentz, Appl. Opt. 15, 1976):       !
   ! K = product of C_j*D_j, C_j = 1 + d_j/C_(j-1),                   !
   ! D_j = 1/(1 + d_j D_(j-1)), stopped when C_j*D_j is 1 to within   !
   ! eps. tiny keeps a zero denominator from stopping it.             !
   !******************************************************************!
   elemental real(kind=wp) function betacf( a, b, x )
   real(kind=wp), intent(in) :: a, b, x
   integer(kind=int32), parameter :: maxit = 20000
   real(kind=wp), parameter :: tiny_cf = 1.0e-200_wp
   real(kind=wp), parameter :: eps_cf = 1.0e-15_wp
   real(kind=wp) :: c, dd, dj, fk, del, rm
   integer(kind=int32) :: m, j

   c  = one
   dd = zero
   fk = one
   do j = 1, 2*maxit
      m  = j/2
      rm = real( m, wp )
      if ( mod( j, 2 ) == 1 ) then
         dj = -( a + rm )*( a + b + rm )*x/( ( a + 2.0_wp*rm )* &
            ( a + 2.0_wp*rm + one ) )
      else
         dj = rm*( b - rm )*x/( ( a + 2.0_wp*rm - one )*( a + 2.0_wp*rm ) )
      end if
      dd = one + dj*dd
      if ( abs( dd ) < tiny_cf ) dd = tiny_cf
      c  = one + dj/c
      if ( abs( c ) < tiny_cf ) c = tiny_cf
      dd  = one/dd
      del = c*dd
      fk  = fk*del
      if ( abs( del - one ) < eps_cf ) exit
   end do
   betacf = fk
   end function betacf

   !*** Lower case (names are compared case-blind).
   pure function lower( text ) result( s )
   character(len=*), intent(in) :: text
   character(len=len_trim(adjustl(text))) :: s
   integer :: i, ic
   s = trim( adjustl( text ) )
   do i = 1, len( s )
      ic = iachar( s(i:i) )
      if ( ic >= iachar('A') .and. ic <= iachar('Z') ) s(i:i) = achar( ic + 32 )
   end do
   end function lower

   pure function itoa( n ) result( s )
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim( buf )
   end function itoa

   pure function plural( n ) result( s )
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   s = 's'
   if ( n == 1 ) s = ''
   end function plural

   !*** The parameters a name takes, for messages.
   pure function pnames( nm ) result( s )
   character(len=*), intent(in) :: nm
   character(len=:), allocatable :: s
   select case ( nm )
   case ( 'uniform' );      s = 'none'
   case ( 'linear' );       s = 's'
   case ( 'beta' );         s = 'a b'
   case ( 'normal' );       s = 'mu sigma'
   case ( 'split_normal' ); s = 'm sigma_left sigma_right'
   case ( 'sinh_arcsinh' ); s = 'loc scale eps delta'
   case ( 'cauchy' );       s = 'x0 gamma'
   case default;            s = ''
   end select
   end function pnames

end module distributions

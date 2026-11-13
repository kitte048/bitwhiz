module stochignite
!**********************************************************************!
!
!  Purpose:
!    StochasticIgnite, a burn model with a random rate (deck: burn =
!    stochasticignite, with eos = mie_gruneisen_t and products =
!    ideal_gas): its random field Z, its generator, and its step.
!    Proposed by ChatGPT 4o-mini in SAND2025-09228 (§5.2.2), repaired
!    where it is not defined, and extended in how Z behaves (doc/design/
!    burn_models.md, "StochasticIgnite" and "Step 7").
!
!       call si_step( phi1, z1, marked, first, seed, j, n, dt, MU, &
!                     SIGMA, AVRAMI, Ps, NS, PR, TAUZ, phi2, z2, lam2 )
!       z  = si_z0( seed, j )                  bin j's Z at t = 0
!       u  = si_uniform( seed, j, n, s )       the generator, (0, 1)
!       x  = si_normal( u )                    AS241: N(0, 1)
!
!    Pure and elemental where it can be; it holds no state. Module burn
!    gives it the cell's phi and Z, the lead shock's P_s and whether it
!    is marked (module leadshock), the cycle n and the cell's bin j.
!
!  The model (as proposed, repaired and extended; the design note's
!  three-layer table):
!       dlam/dt = g(lam) (mu + sigma Z) (1 + P_s/P_ref)^m     (proposed)
!    bitwhiz:
!       lam = 1 - exp(-phi**AVRAMI)                  (KJMA, a potential)
!       dphi/dt = max(MU + SIGMA Z, 0) (1 + max(P_s, 0)/PR)**NS
!    once the lead shock is marked (the gate), and Z an Ornstein-
!    Uhlenbeck process in time, correlation time TAUZ, one per bin of
!    width LC of the material's initial position (DK, 11/12/26):
!       dZ = -(Z/TAUZ) dt + sqrt(2/TAUZ) dW
!    TAUZ = 1e30 is a frozen field (exactly: THE STEP).
!
!  THE STEP
!  ========
!  The hydro's dt in ns sub-steps h = dt/ns, ns the least with h <=
!  TAUZ/10 (ns_max at most, below). In each, phi by the rate at the
!  sub-step's start (left point; only once the lead shock is marked),
!  then Z by the OU process's exact step,
!       Z <- a Z + sqrt(1 - a**2) xi,   a = exp(-h/TAUZ),   xi ~ N(0, 1)
!  exact in distribution for any h. sqrt(1 - a**2) is formed as written,
!  not by an accurate 1 - exp(-2x): so TAUZ = 1e30, where a rounds to
!  1, gives 0 there and a Z frozen bit for bit, with no special case;
!  for h/TAUZ >= 1e-8 the cancellation costs at most 5e-9 of the noise's
!  amplitude. Then lam = 1 - exp(-phi**AVRAMI), by module thermalcascade's
!  accurate 1 - exp(-x) (tc_om). The prototype (design note, "Step 7"):
!  with h <= TAUZ/10 the variance of phi is within Monte Carlo noise of
!  its closed form; a longer h misses the fluctuation within it.
!
!  THE RANDOM NUMBERS
!  ==================
!  Z at t = 0: bin j reads the atmospheric table (module random, 20,000
!  values), entry modulo(SEED + 7919 j, 20000) + 1, through AS241 (7919,
!  prime, shares no factor with 20,000 = 2**5 5**4). Every later draw:
!  a counter-based generator, a pure function of (SEED, j, n, s) for bin
!  j, cycle n, sub-step s: SplitMix64 chained over the four, x =
!  m(m(m(m(SEED) xor j) xor n) xor s), and u = ((x >> 12) + 1/2) 2**-52:
!  52 bits, so k + 1/2 is exact in double precision and u is strictly
!  inside (0, 1), from 2**-53 to 1 - 2**-53 (53 bits would make k + 1/2
!  round, to 2**53 at the top, and u = 1 once in 2**53 draws). Every
!  cell of a bin gets the same draws, and any number of threads the same
!  bits.
!
!***NOTE: 64-bit unsigned arithmetic, in Fortran. Fortran's integers are
! signed and an overflow is not defined, so a 64-bit value is kept as
! two 32-bit halves, each in an int64 (0 to 2**32 - 1), and products
! are formed from 16-bit pieces: no intermediate reaches 2**35. Shifts
! and xor are bit operations on the halves. tests/test_sign.f95 checks
! the bits against tests/sign_reference.py's Python integers.
!
!***NOTE: AS241 (Wichura 1988, PPND16): the normal deviate of u to about
! 1e-16 relative (4.4e-16, 2 ulp, or better against 50 digits, u from
! 2**-54 to 1 - 2**-53: tests/test_sign.f95).
!
!***NOTE: ns_max. TAUZ far below the hydro's dt would ask for many
! sub-steps per cell per cycle; ns is held to ns_max = 1000. Below
! TAUZ = dt/100 the sub-steps are then longer than TAUZ/10 and the
! variance of phi is not resolved; but there the noise averages away
! within a step anyway (the design note: the model tends to a burn at
! the floored mean rate).
!
!  Units, as everywhere in bitwhiz: MU and SIGMA in 1/us; TAUZ, dt, h in
!  us; P_s and PR in GPa; phi, lam, Z, AVRAMI and NS dimensionless.
!
!  References:
!    D. E. Kittell et al., "A Short Survey of Current Reactive Burn
!    Model Capabilities as of Mid-Year 2025", SAND2025-09228, Sandia
!    National Laboratories (2025), doi:10.2172/2585504, §5.2.2.
!    M. J. Wichura, "Algorithm AS 241: The percentage points of the
!    normal distribution", Applied Statistics 37, 477-484 (1988).
!    G. L. Steele, D. Lea and C. H. Flood, "Fast splittable pseudorandom
!    number generators", OOPSLA 2014 (SplitMix64).
!    J. K. Salmon et al., "Parallel random numbers: as easy as 1, 2, 3",
!    SC11 (2011) (counter-based generators).
!    G. E. Uhlenbeck and L. S. Ornstein, Phys. Rev. 36, 823 (1930); D. T.
!    Gillespie, Phys. Rev. E 54, 2084 (1996) (the OU step, exact).
!    doc/design/burn_models.md, "StochasticIgnite" (approved 11/06/26)
!    and "Step 7, StochasticIgnite: the plan" (approved 11/12/26).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/12/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, int64, zero, half, one
use thermalcascade, only: tc_om
use random, only: randlist, nbig
implicit none
private

public :: si_step, si_z0, si_uniform, si_normal, si_nsub, si_ns_max, &
   si_stride

!*** The step's algorithm constants (THE STEP, the NOTE on ns_max).
real(kind=dp), parameter :: si_h_tau = 0.1_dp       ! h <= si_h_tau TAUZ
integer(kind=int32), parameter :: si_ns_max = 1000
!*** The table's stride (THE RANDOM NUMBERS).
integer(kind=int64), parameter :: si_stride = 7919_int64

!*** SplitMix64's constants, as 32-bit halves (hi, lo).
integer(kind=int64), parameter :: m32 = 4294967295_int64     ! 2**32 - 1
integer(kind=int64), parameter :: m16 = 65535_int64          ! 2**16 - 1
integer(kind=int64), parameter :: gold_hi = 2654435769_int64, &
   gold_lo = 2135587861_int64
integer(kind=int64), parameter :: c1_hi = 3210233709_int64, &
   c1_lo = 484763065_int64
integer(kind=int64), parameter :: c2_hi = 2496678331_int64, &
   c2_lo = 321982955_int64

!*** AS241's coefficients (PPND16).
real(kind=dp), parameter :: a(0:7) = (/ 3.3871328727963666080e0_dp, &
   1.3314166789178437745e+2_dp, 1.9715909503065514427e+3_dp, &
   1.3731693765509461125e+4_dp, 4.5921953931549871457e+4_dp, &
   6.7265770927008700853e+4_dp, 3.3430575583588128105e+4_dp, &
   2.5090809287301226727e+3_dp /)
real(kind=dp), parameter :: b(0:7) = (/ 1.0_dp, &
   4.2313330701600911252e+1_dp, 6.8718700749205790830e+2_dp, &
   5.3941960214247511077e+3_dp, 2.1213794301586595867e+4_dp, &
   3.9307895800092710610e+4_dp, 2.8729085735721942674e+4_dp, &
   5.2264952788528545610e+3_dp /)
real(kind=dp), parameter :: c(0:7) = (/ 1.42343711074968357734e0_dp, &
   4.63033784615654529590e0_dp, 5.76949722146069140550e0_dp, &
   3.64784832476320460504e0_dp, 1.27045825245236838258e0_dp, &
   2.41780725177450611770e-1_dp, 2.27238449892691845833e-2_dp, &
   7.74545014278341407640e-4_dp /)
real(kind=dp), parameter :: d(0:7) = (/ 1.0_dp, &
   2.05319162663775882187e0_dp, 1.67638483018380384940e0_dp, &
   6.89767334985100004550e-1_dp, 1.48103976427480074590e-1_dp, &
   1.51986665636164571966e-2_dp, 5.47593808499534494600e-4_dp, &
   1.05075007164441684324e-9_dp /)
real(kind=dp), parameter :: e(0:7) = (/ 6.65790464350110377720e0_dp, &
   5.46378491116411436990e0_dp, 1.78482653991729133580e0_dp, &
   2.96560571828504891230e-1_dp, 2.65321895265761230930e-2_dp, &
   1.24266094738807843860e-3_dp, 2.71155556874348757815e-5_dp, &
   2.01033439929228813265e-7_dp /)
real(kind=dp), parameter :: f(0:7) = (/ 1.0_dp, &
   5.99832206555887937690e-1_dp, 1.36929880922735805310e-1_dp, &
   1.48753612908506148525e-2_dp, 7.86869131145613259100e-4_dp, &
   1.84631831751005468180e-5_dp, 1.42151175831644588870e-7_dp, &
   2.04426310338993978564e-15_dp /)

contains

   !******************************************************************!
   ! One step (THE STEP): phi and Z over dt, and lam. marked: the     !
   ! lead shock is (phi moves only then); first: the run's first      !
   ! cycle, when Z starts from the table (si_z0), not from z1.        !
   !******************************************************************!
   pure subroutine si_step( phi1, z1, marked, first, seed, j, n, dt, MU, &
      SIGMA, AVRAMI, Ps, NS, PR, TAUZ, phi2, z2, lam2 )
   implicit none
   real(kind=dp), intent(in)  :: phi1, z1        ! at the step's start
   logical, intent(in)        :: marked, first
   integer(kind=int64), intent(in) :: seed, j, n ! SEED, bin, cycle
   real(kind=dp), intent(in)  :: dt              ! us
   real(kind=dp), intent(in)  :: MU, SIGMA, AVRAMI, Ps, NS, PR, TAUZ
   real(kind=dp), intent(out) :: phi2, z2, lam2
   real(kind=dp) :: h, s_fac, aa, bb, xi
   integer(kind=int32) :: nsub, isub
   z2   = z1
   if ( first ) z2 = si_z0( seed, j )
   phi2 = phi1
   nsub = si_nsub( dt, TAUZ )
   h    = dt/real( nsub, dp )
   aa   = exp( -h/TAUZ )
   bb   = sqrt( one - aa*aa )                    ! as written (THE STEP)
   s_fac = ( one + max( Ps, zero )/PR )**NS
   do isub = 1, nsub
      if ( marked ) phi2 = phi2 + max( MU + SIGMA*z2, zero )*s_fac*h
      xi = si_normal( si_uniform( seed, j, n, int( isub, int64 ) ) )
      z2 = aa*z2 + bb*xi
   end do
   lam2 = zero
   if ( phi2 > zero ) lam2 = tc_om( phi2**AVRAMI )
   end subroutine si_step

   !******************************************************************!
   ! The sub-steps in dt: the least ns with dt/ns <= TAUZ/10, 1 to    !
   ! si_ns_max (the NOTE).                                            !
   !******************************************************************!
   elemental function si_nsub( dt, TAUZ ) result( ns )
   implicit none
   real(kind=dp), intent(in) :: dt, TAUZ
   integer(kind=int32) :: ns
   real(kind=dp) :: x
   x  = dt/( si_h_tau*TAUZ )
   ns = 1
   if ( x > one ) ns = int( min( real( si_ns_max, dp ), &
      real( ceiling( min( x, 1.0e6_dp ) ), dp ) ), int32 )
   end function si_nsub

   !******************************************************************!
   ! Bin j's Z at t = 0: the atmospheric table, through AS241. j is   !
   ! reduced modulo nbig first, so 7919 j can not overflow for any j  !
   ! (the entry is the same: modulo(SEED + 7919 j, nbig) + 1).         !
   !******************************************************************!
   elemental function si_z0( seed, j ) result( z )
   implicit none
   integer(kind=int64), intent(in) :: seed, j
   real(kind=dp) :: z
   integer(kind=int64) :: nb
   nb = int( nbig, int64 )
   z = si_normal( randlist( int( modulo( seed + si_stride*modulo( j, nb ), &
      nb ), int32 ) + 1 ) )
   end function si_z0

   !******************************************************************!
   ! The generator (THE RANDOM NUMBERS): u in (0, 1) from (seed, j,   !
   ! n, s), SplitMix64 chained over the four.                         !
   !******************************************************************!
   elemental function si_uniform( seed, j, n, s ) result( u )
   implicit none
   integer(kind=int64), intent(in) :: seed, j, n, s
   real(kind=dp) :: u
   integer(kind=int64) :: hi, lo
   call halves( seed, hi, lo )
   call mix( hi, lo )
   call xor_in( j, hi, lo )
   call mix( hi, lo )
   call xor_in( n, hi, lo )
   call mix( hi, lo )
   call xor_in( s, hi, lo )
   call mix( hi, lo )
   !*** x >> 12, 52 bits: hi's 32 then lo's top 20 (THE RANDOM NUMBERS).
   u = ( real( hi, dp )*1048576.0_dp + real( ishft( lo, -12 ), dp ) + &
      half )*2.0_dp**(-52)
   end function si_uniform

   !******************************************************************!
   ! AS241 (Wichura 1988): the standard normal deviate of u, 0<u<1.   !
   !******************************************************************!
   elemental function si_normal( u ) result( x )
   implicit none
   real(kind=dp), intent(in) :: u
   real(kind=dp) :: x, q, r
   q = u - half
   if ( abs( q ) <= 0.425_dp ) then
      r = 0.180625_dp - q*q
      x = q*poly( a, r )/poly( b, r )
      return
   end if
   r = u
   if ( q > zero ) r = one - u
   r = sqrt( -log( r ) )
   if ( r <= 5.0_dp ) then
      r = r - 1.6_dp
      x = poly( c, r )/poly( d, r )
   else
      r = r - 5.0_dp
      x = poly( e, r )/poly( f, r )
   end if
   if ( q < zero ) x = -x
   end function si_normal

   !*** A polynomial, Horner's rule, coefficients 0 to 7.
   pure function poly( cf, r ) result( p )
   real(kind=dp), intent(in) :: cf(0:7), r
   real(kind=dp) :: p
   integer(kind=int32) :: i
   p = cf(7)
   do i = 6, 0, -1
      p = p*r + cf(i)
   end do
   end function poly

   !*** A signed 64-bit integer's bits, as two 32-bit halves.
   pure subroutine halves( v, hi, lo )
   integer(kind=int64), intent(in)  :: v
   integer(kind=int64), intent(out) :: hi, lo
   hi = iand( ishft( v, -32 ), m32 )               ! logical shift
   lo = iand( v, m32 )
   end subroutine halves

   !*** x <- x xor v (v's 64 bits).
   pure subroutine xor_in( v, hi, lo )
   integer(kind=int64), intent(in)    :: v
   integer(kind=int64), intent(inout) :: hi, lo
   integer(kind=int64) :: vh, vl
   call halves( v, vh, vl )
   hi = ieor( hi, vh )
   lo = ieor( lo, vl )
   end subroutine xor_in

   !*** SplitMix64's output function, from the state x (its increment
   !*** first): z = x + golden; z = (z xor z>>30) c1; z = (z xor z>>27)
   !*** c2; z xor z>>31.
   pure subroutine mix( hi, lo )
   integer(kind=int64), intent(inout) :: hi, lo
   call add( hi, lo, gold_hi, gold_lo )
   call xshr( hi, lo, 30 )
   call mul( hi, lo, c1_hi, c1_lo )
   call xshr( hi, lo, 27 )
   call mul( hi, lo, c2_hi, c2_lo )
   call xshr( hi, lo, 31 )
   end subroutine mix

   !*** x <- x + y, mod 2**64.
   pure subroutine add( hi, lo, yh, yl )
   integer(kind=int64), intent(inout) :: hi, lo
   integer(kind=int64), intent(in)    :: yh, yl
   integer(kind=int64) :: t
   t  = lo + yl                                    ! < 2**33
   lo = iand( t, m32 )
   hi = iand( hi + yh + ishft( t, -32 ), m32 )
   end subroutine add

   !*** x <- x xor (x >> k), 0 < k < 32.
   pure subroutine xshr( hi, lo, k )
   integer(kind=int64), intent(inout) :: hi, lo
   integer, intent(in) :: k
   integer(kind=int64) :: sh, sl
   sh = ishft( hi, -k )
   sl = ior( ishft( lo, -k ), iand( ishft( hi, 32 - k ), m32 ) )
   hi = ieor( hi, sh )
   lo = ieor( lo, sl )
   end subroutine xshr

   !*** x <- x y, mod 2**64 (the NOTE: 16-bit pieces).
   pure subroutine mul( hi, lo, yh, yl )
   integer(kind=int64), intent(inout) :: hi, lo
   integer(kind=int64), intent(in)    :: yh, yl
   integer(kind=int64) :: ph, pl
   call mulfull( lo, yl, ph, pl )                  ! lo yl, all 64 bits
   ph = iand( ph + mullo( hi, yl ) + mullo( lo, yh ), m32 )
   hi = ph
   lo = pl
   end subroutine mul

   !*** The full 64-bit product of two 32-bit values, as halves.
   pure subroutine mulfull( x, y, ph, pl )
   integer(kind=int64), intent(in)  :: x, y
   integer(kind=int64), intent(out) :: ph, pl
   integer(kind=int64) :: x0, x1, y0, y1, p00, mid, t
   x0 = iand( x, m16 );  x1 = ishft( x, -16 )
   y0 = iand( y, m16 );  y1 = ishft( y, -16 )
   p00 = x0*y0                                     ! < 2**32
   mid = x0*y1 + x1*y0                             ! < 2**33
   t   = p00 + ishft( iand( mid, m16 ), 16 )       ! < 2**33
   pl  = iand( t, m32 )
   ph  = x1*y1 + ishft( mid, -16 ) + ishft( t, -32 )
   end subroutine mulfull

   !*** The low 32 bits of the product of two 32-bit values.
   pure function mullo( x, y ) result( p )
   integer(kind=int64), intent(in) :: x, y
   integer(kind=int64) :: p, x0, x1, y0, y1
   x0 = iand( x, m16 );  x1 = ishft( x, -16 )
   y0 = iand( y, m16 );  y1 = ishft( y, -16 )
   p  = iand( x0*y0 + ishft( iand( x0*y1 + x1*y0, m16 ), 16 ), m32 )
   end function mullo

end module stochignite

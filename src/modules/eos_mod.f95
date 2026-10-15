module eos
!**********************************************************************!
!
!  Purpose:
!    The equation of state: Mie-Gruneisen referenced to the principal
!    Hugoniot, with the house convention rho*Gamma = R0*G0. Given a
!    cell's density and specific internal energy (and its material
!    constants), return the pressure and the isentropic sound speed.
!
!       call mg_eos( rho, e, R0, C0, S1, S2, G0, p, c, ierr )
!
!    Units, as everywhere in bitwhiz:
!       rho, R0   g/cm^3        e       (km/s)^2 = kJ/g = MJ/kg
!       C0, c     km/s          p       GPa
!       S1, S2, G0  dimensionless
!
!  References:
!    Equation sheet, Hydrocode_Eqns_rev-0 (Equations of State, and
!    Isentropic Sound Speed); project rev-0, Eq. 4; code contract (b)
!    sections 5.2-5.5. The derivative forms below (dUs/deta, dP_H/dV,
!    and the phi construction for the sound speed) are D. E. Kittell's,
!    checked symbolically and numerically on 10/14/26 (sympy and 50-digit
!    mpmath, all four class materials, eta = -0.5 to 0.99 of the limit;
!    float64 agrees to 2e-14).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/14/26    D. E. Kittell        Original code
!                (with Claude)
!    10/15/26    D. E. Kittell        mg_pressure and mg_soundspeed, so
!                (with Claude)        c can follow the P >= 0 floor
!    10/16/26    D. E. Kittell        Expansion branch: a cubic in
!                (with Claude)        rho - R0 that continues the
!                                     Hugoniot form through 3rd order
!
!**********************************************************************!
!
!  THE EQUATIONS, IN THE ORDER THE CODE EVALUATES THEM
!  ===================================================
!  Compression, and the Hugoniot shock speed (the root of
!  Us = C0 + S1*up + (S2/C0)*up**2 with up = eta*Us, rationalized):
!
!     eta  = 1 - R0/rho                     (V = 1/rho, V0 = 1/R0)
!     a    = 1 - S1*eta
!     xi1  = sqrt( a**2 - 4*S2*eta**2 )
!     D    = a + xi1
!     Us   = 2*C0 / D
!     Us'  = dUs/deta = 2*C0*( S1 + (S1 - S1**2*eta + 4*S2*eta)/xi1 ) / D**2
!
!  The Hugoniot reference curve. The sheet writes P_H = up**2/(V0 - V),
!  which is 0/0 at the initial state (and would trip -ffpe-trap on the
!  first cycle). With up = eta*Us and V0 - V = eta*V0 the eta cancels:
!
!     P_H  = R0*eta*Us**2
!     e_H  = (eta*Us)**2 / 2
!
!  Pressure. Write P(V,e) = R0*G0*e + phi(V), where phi = P_H - R0*G0*e_H
!  is the part that depends on volume alone. (Possible only because
!  (dP/de)_V = R0*G0 is a constant: that is the rho*Gamma = R0*G0
!  convention. phi is a construction for the code, not for the sheet.)
!
!     phi  = P_H - R0*G0*e_H
!     P    = R0*G0*e + phi
!
!  Sound speed. Along an isentrope de = -P dV, so
!     (dP/dV)_S = phi' - R0*G0*P,   with phi' = (dP/dV)_e,
!  and c**2 = -V**2 (dP/dV)_S. The Hugoniot slopes it needs:
!
!     dP_H/dV = -R0**2*( Us**2 + 2*eta*Us*Us' )
!     de_H/dV = ( eta*V0*dP_H/dV - P_H ) / 2       (sheet identity)
!     phi'    = dP_H/dV - R0*G0*de_H/dV
!     c**2    = V**2*( R0*G0*P - phi' )
!
!  which is the sheet's c = (1/rho)*sqrt( R0*G0*(P + de_H/dV) - dP_H/dV )
!  rearranged.
!
!  EXPANSION, V > V0 (eta < 0). U_S-u_p data exist only in compression,
!  so for expansion bitwhiz uses its own rule (D. E. Kittell's cubic,
!  10/16/26; not from the literature): phi is a cubic in the density
!  change x = rho - R0 = 1/V - 1/V0 (negative in expansion),
!
!     phi  = a1*x + a2*x**2/2 + a3*x**3/6
!
!  with the coefficients chosen so that phi and its first three
!  derivatives match the compression form at V0. Then P, c, and the
!  first two derivatives of c are all continuous at the initial state:
!
!     a1 = C0**2                                     (c continuous)
!     a2 = (C0**2/R0)*( 4*S1 - 2 - G0 )              (dc continuous)
!     a3 = (6*C0**2/R0**2)*( 3*S1**2 - 4*S1 - G0*S1 + G0 + 2*S2 + 1 )
!
!  (4*S1 - 1, inside a2, is the K0' of a linear Us-up fit.) This is the
!  Taylor series of the compression form, carried into expansion: it
!  agrees with simply evaluating the Hugoniot form at eta < 0 to 3-4
!  digits out to V = 1.1*V0, but it is a polynomial, so it can be
!  evaluated at ANY expansion (no square root, no division), for any
!  material that is valid in compression. Its slope, in V:
!
!     phi' = dphi/dV = -rho**2 * ( a1 + a2*x + a3*x**2/2 )
!
!  and P and c**2 then follow from the same two lines as compression.
!  For the four class materials c**2 > 0 at P = 0 all the way to
!  rho -> 0. (Unusual parameters can give a cubic whose slope reaches
!  zero, a point where c -> 0; see eos_bad_soundspeed below.)
!  How much tension a material can actually hold is NOT the EOS's
!  business: that is the spall strength, applied in the time loop.
!
!***NOTE: dP_H/dV (the slope ALONG the Hugoniot) is not (dP/dV)_e (the
! slope of the EOS surface at fixed e); they differ by R0*G0*de_H/dV.
! Using one for the other gives a sound speed 5% high at eta = 0.1 and
! 11% high at the 1.5 km/s first shock in MatX, with no warning, and
! the reference state can not tell them apart (both give c = C0). The
! unit test (tests/test_eos.f95) checks compressed states for this.
!
!***NOTE: the "up" inside an EOS is the HUGONIOT particle velocity at
! the cell's current volume, never the cell's own velocity. mg_eos has
! no velocity argument, so the two can not be mixed up.
!
!**********************************************************************!
!
!  WHAT CAN GO WRONG, AND WHAT mg_eos DOES ABOUT IT
!  ================================================
!  mg_eos never stops the run and never prints (it is elemental, so it
!  can not). It returns a status code; the caller knows the cell, the
!  layer and the time, and reports them. On any status but eos_ok,
!  p and c are set to a SIGNALING NaN, so a caller that forgets to
!  look at ierr stops at the very next arithmetic on them.
!
!   eos_bad_density     rho <= 0 (a tangled mesh: a cell turned inside
!                       out). Checked first, before dividing by rho.
!   eos_too_compressed  past the Hugoniot's reach (compression only).
!                       For S2 = 0 (Ta, Al, PMMA) Us blows up as
!                       eta -> 1/S1 (0.833, 0.746, 0.649) and D -> 0.
!                       We stop short of that, when Us would pass
!                       100*C0 (D < 0.02); the class problem never gets
!                       past eta = 0.28. For S2 > 0 the square root can
!                       go negative first. For S2 < 0 (MatX) neither
!                       happens at any eta.
!   eos_bad_soundspeed  c**2 <= 0. Compressed or at P >= 0 this does
!                       not happen for the class materials. It can in
!                       expansion for unusual parameters, where the
!                       cubic's slope reaches zero (in a sweep of 2754
!                       plausible materials, 11% have such a point,
!                       the earliest at rho = 0.63*R0), or in deep
!                       tension at a negative P. The time loop treats
!                       a cell there as broken (void).
!
!  Spall (the tension a material can hold, then failure) and the
!  "first cell to go tensile" flag are NOT here: the EOS reports a
!  negative pressure honestly, and the time loop decides what to do
!  with it. For that the EOS comes in three calls:
!
!     mg_eos        ( rho, e, ..., p, c, ierr )   both, c at that p
!     mg_pressure   ( rho, e, ..., p, ierr )      P alone
!     mg_soundspeed ( rho, p, ..., c, ierr )      c at a GIVEN p
!
!  so the loop can do what it needs: P, then (for a broken cell) the
!  P >= 0 floor, then c at the pressure it kept. All three share one
!  private routine (mg_ref) for the volume-only part, so they agree to
!  the last bit.
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one, two
implicit none
private

public :: mg_eos, mg_pressure, mg_soundspeed, eos_message
public :: eos_ok, eos_bad_density, eos_too_compressed, eos_bad_soundspeed

!*** Status codes returned in ierr.
integer(kind=int32), parameter :: eos_ok             = 0
integer(kind=int32), parameter :: eos_bad_density    = 1
integer(kind=int32), parameter :: eos_too_compressed = 2
integer(kind=int32), parameter :: eos_bad_soundspeed = 3

!*** Smallest allowed D = a + xi1. Us = 2*C0/D, so D < 0.02 means
!*** Us > 100*C0: far past any real shock, and well before D = 0.
real(kind=dp), parameter :: dmin = 0.02_dp

contains

   !******************************************************************!
   ! Mie-Gruneisen pressure and sound speed for one cell, together:   !
   ! c is the sound speed at the pressure p returned. Elemental: call !
   ! it with scalars for one cell, or with conforming arrays (e.g.    !
   ! strided rows of the database) for many cells at once.            !
   !******************************************************************!
   elemental subroutine mg_eos( rho, e, R0, C0, S1, S2, G0, p, c, ierr )
   implicit none
   real(kind=dp), intent(in)  :: rho     ! density, g/cm^3
   real(kind=dp), intent(in)  :: e       ! specific internal energy, (km/s)^2
   real(kind=dp), intent(in)  :: R0      ! reference density, g/cm^3
   real(kind=dp), intent(in)  :: C0      ! Us-up intercept, km/s
   real(kind=dp), intent(in)  :: S1      ! Us-up slope
   real(kind=dp), intent(in)  :: S2      ! Us-up curvature
   real(kind=dp), intent(in)  :: G0      ! reference Gruneisen coefficient
   real(kind=dp), intent(out) :: p       ! pressure, GPa
   real(kind=dp), intent(out) :: c       ! isentropic sound speed, km/s
   integer(kind=int32), intent(out) :: ierr ! eos_ok, or why not
   real(kind=dp) :: v, phi, phip

   call mg_ref( rho, R0, C0, S1, S2, G0, v, phi, phip, ierr )
   if ( ierr == eos_ok ) then
      p = R0*G0*e + phi
      call sound( v, p, R0*G0, phip, c, ierr )
   end if
   if ( ierr /= eos_ok ) call unusable( p, c )
   end subroutine mg_eos

   !******************************************************************!
   ! The pressure alone, P(rho, e) = R0*G0*e + phi(V). The time loop  !
   ! uses this, then applies the P >= 0 floor, then asks for c at the !
   ! floored pressure (equation sheet, Step 2 and One Cycle, d).      !
   !******************************************************************!
   elemental subroutine mg_pressure( rho, e, R0, C0, S1, S2, G0, p, ierr )
   implicit none
   real(kind=dp), intent(in)  :: rho, e, R0, C0, S1, S2, G0  ! as mg_eos
   real(kind=dp), intent(out) :: p       ! pressure, GPa
   integer(kind=int32), intent(out) :: ierr ! eos_ok, or why not
   real(kind=dp) :: v, phi, phip, unused

   call mg_ref( rho, R0, C0, S1, S2, G0, v, phi, phip, ierr )
   if ( ierr == eos_ok ) then
      p = R0*G0*e + phi
   else
      call unusable( p, unused )
   end if
   end subroutine mg_pressure

   !******************************************************************!
   ! The sound speed at density rho and a GIVEN pressure p,           !
   !    c**2 = V**2*( R0*G0*p - phi'(V) ),                            !
   ! which holds for any p because (dP/de)_V = R0*G0 is a constant.   !
   ! The time loop calls it with the floored pressure (p = 0 for a    !
   ! cell the floor reset), as the equation sheet orders it: "P (keep !
   ! them >= 0), then sound speeds c".                                !
   !******************************************************************!
   elemental subroutine mg_soundspeed( rho, p, R0, C0, S1, S2, G0, c, ierr )
   implicit none
   real(kind=dp), intent(in)  :: rho     ! density, g/cm^3
   real(kind=dp), intent(in)  :: p       ! pressure to use, GPa
   real(kind=dp), intent(in)  :: R0, C0, S1, S2, G0  ! as mg_eos
   real(kind=dp), intent(out) :: c       ! isentropic sound speed, km/s
   integer(kind=int32), intent(out) :: ierr ! eos_ok, or why not
   real(kind=dp) :: v, phi, phip, unused

   call mg_ref( rho, R0, C0, S1, S2, G0, v, phi, phip, ierr )
   if ( ierr == eos_ok ) call sound( v, p, R0*G0, phip, c, ierr )
   if ( ierr /= eos_ok ) call unusable( c, unused )
   end subroutine mg_soundspeed

   !******************************************************************!
   ! The volume-only part of the EOS: V, phi(V) and phi'(V), from the !
   ! Hugoniot reference curve, with the guards (see the header).      !
   !******************************************************************!
   elemental subroutine mg_ref( rho, R0, C0, S1, S2, G0, v, phi, phip, ierr )
   implicit none

   !*******************************************************************!
   ! Data dictionary: Subroutine I/O.
   !*******************************************************************!
   real(kind=dp), intent(in)  :: rho     ! density, g/cm^3
   real(kind=dp), intent(in)  :: R0      ! reference density, g/cm^3
   real(kind=dp), intent(in)  :: C0      ! Us-up intercept, km/s
   real(kind=dp), intent(in)  :: S1      ! Us-up slope
   real(kind=dp), intent(in)  :: S2      ! Us-up curvature
   real(kind=dp), intent(in)  :: G0      ! reference Gruneisen coefficient
   real(kind=dp), intent(out) :: v       ! specific volume, cm^3/g
   real(kind=dp), intent(out) :: phi     ! P_H - R0*G0*e_H, GPa
   real(kind=dp), intent(out) :: phip    ! phi' = (dP/dV)_e
   integer(kind=int32), intent(out) :: ierr ! eos_ok, or why not

   !*******************************************************************!
   ! Data dictionary: Subroutine Internal Variables.
   !*******************************************************************!
   real(kind=dp) :: eta                  ! compression, 1 - V/V0
   real(kind=dp) :: a, disc, xi1, d      ! pieces of the Us root
   real(kind=dp) :: us, dus              ! Us and dUs/deta, km/s
   real(kind=dp) :: ph, eh               ! Hugoniot P_H (GPa), e_H
   real(kind=dp) :: dph_dv, deh_dv       ! Hugoniot slopes in V
   real(kind=dp) :: rg                   ! R0*G0 = (dP/de)_V
   real(kind=dp) :: x                    ! expansion: rho - R0, g/cm^3
   real(kind=dp) :: a1, a2, a3           ! expansion: the cubic's coef.

   ierr = eos_ok
   v    = zero
   phi  = zero
   phip = zero

   !*** A bad density first: everything below divides by rho.
   if ( .not. ( rho > zero ) ) then
      ierr = eos_bad_density
      return
   end if

   v   = one/rho
   eta = one - R0*v
   rg  = R0*G0

   !*** Expansion: the cubic in x = rho - R0 (see the header). No
   !*** square root and no division, so it is good at any expansion.
   if ( eta < zero ) then
      x     = rho - R0
      a1    = C0*C0
      a2    = (C0*C0/R0)*( 4.0_dp*S1 - two - G0 )
      a3    = (6.0_dp*C0*C0/(R0*R0))*( 3.0_dp*S1*S1 - 4.0_dp*S1 - G0*S1 &
              + G0 + two*S2 + one )
      phi   = x*( a1 + x*( half*a2 + x*a3/6.0_dp ) )
      phip  = -rho*rho*( a1 + x*( a2 + half*a3*x ) )
      return
   end if

   !*** Compression (and the reference state itself, eta = 0).
   !*** The Hugoniot shock speed, guarded BEFORE any division by xi1
   !*** or D (at the limit both go to zero together).
   a    = one - S1*eta
   disc = a*a - 4.0_dp*S2*eta*eta
   if ( disc <= zero ) then
      ierr = eos_too_compressed
      return
   end if
   xi1 = sqrt( disc )
   d   = a + xi1
   if ( d < dmin ) then
      ierr = eos_too_compressed
      return
   end if
   us  = two*C0/d
   dus = two*C0*( S1 + (S1 - S1*S1*eta + 4.0_dp*S2*eta)/xi1 )/( d*d )

   !*** The Hugoniot reference curve (cancelled form, no 0/0), and phi.
   ph  = R0*eta*us*us
   eh  = half*(eta*us)**2
   phi = ph - rg*eh

   !*** Its slope, from the Hugoniot slopes. (V0 - V) = eta*V0 = eta/R0.
   dph_dv = -R0*R0*( us*us + two*eta*us*dus )
   deh_dv = half*( (eta/R0)*dph_dv - ph )
   phip   = dph_dv - rg*deh_dv
   end subroutine mg_ref

   !******************************************************************!
   ! c from c**2 = V**2*( R0*G0*p - phi' ), guarded.                  !
   !******************************************************************!
   elemental subroutine sound( v, p, rg, phip, c, ierr )
   implicit none
   real(kind=dp), intent(in)  :: v, p, rg, phip
   real(kind=dp), intent(out) :: c
   integer(kind=int32), intent(out) :: ierr
   real(kind=dp) :: c2
   c2 = v*v*( rg*p - phip )
   if ( c2 > zero ) then
      c    = sqrt( c2 )
      ierr = eos_ok
   else
      c    = zero
      ierr = eos_bad_soundspeed
   end if
   end subroutine sound

   !******************************************************************!
   ! Make two results unusable: a signaling NaN, so a caller that     !
   ! ignores ierr stops at the very next arithmetic on them.          !
   !******************************************************************!
   elemental subroutine unusable( a, b )
   use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_signaling_nan
   implicit none
   real(kind=dp), intent(out) :: a, b
   a = ieee_value( a, ieee_signaling_nan )
   b = ieee_value( b, ieee_signaling_nan )
   end subroutine unusable

   !******************************************************************!
   ! A status code as words, for the caller's error message.          !
   !******************************************************************!
   pure function eos_message( ierr ) result(msg)
   implicit none
   integer(kind=int32), intent(in) :: ierr
   character(len=:), allocatable :: msg
   select case ( ierr )
   case ( eos_ok )
      msg = 'ok'
   case ( eos_bad_density )
      msg = 'density is zero or negative (a tangled mesh?)'
   case ( eos_too_compressed )
      msg = 'compressed past the reach of the Hugoniot (Us > 100*C0)'
   case ( eos_bad_soundspeed )
      msg = 'sound speed squared is zero or negative (stretched past '// &
            'where the material holds together)'
   case default
      msg = 'unknown EOS status'
   end select
   end function eos_message

end module eos

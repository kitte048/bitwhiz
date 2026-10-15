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
!   eos_too_compressed  past the Hugoniot's reach. For S2 = 0 (Ta, Al,
!                       PMMA) Us blows up as eta -> 1/S1 (0.833, 0.746,
!                       0.649) and D -> 0. We stop short of that, when
!                       Us would pass 100*C0 (D < 0.02); the class
!                       problem never gets past eta = 0.28. For S2 > 0
!                       the square root can go negative first. For
!                       S2 < 0 (MatX) neither happens at any eta.
!   eos_bad_soundspeed  c**2 <= 0. With e = 0 this needs deep tension,
!                       eta below -0.32 (Al) to -0.42 (PMMA), at -16
!                       to -45 GPa: far past anything the P >= 0 floor
!                       allows. A backstop only.
!
!  The P >= 0 floor and the "first cell to go tensile" flag are NOT
!  here (equation sheet, Step 2): the EOS reports a negative pressure
!  honestly, and the time loop decides what to do with it.
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one, two
implicit none
private

public :: mg_eos, eos_message
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
   ! Mie-Gruneisen pressure and sound speed for one cell. Elemental:  !
   ! call it with scalars for one cell, or with conforming arrays     !
   ! (e.g. strided rows of the database) for many cells at once.      !
   !******************************************************************!
   elemental subroutine mg_eos( rho, e, R0, C0, S1, S2, G0, p, c, ierr )
   use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_signaling_nan
   implicit none

   !*******************************************************************!
   ! Data dictionary: Subroutine I/O.
   !*******************************************************************!
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

   !*******************************************************************!
   ! Data dictionary: Subroutine Internal Variables.
   !*******************************************************************!
   real(kind=dp) :: v                    ! specific volume, cm^3/g
   real(kind=dp) :: eta                  ! compression, 1 - V/V0
   real(kind=dp) :: a, disc, xi1, d      ! pieces of the Us root
   real(kind=dp) :: us, dus              ! Us and dUs/deta, km/s
   real(kind=dp) :: ph, eh               ! Hugoniot P_H (GPa), e_H
   real(kind=dp) :: dph_dv, deh_dv       ! Hugoniot slopes in V
   real(kind=dp) :: rg                   ! R0*G0 = (dP/de)_V
   real(kind=dp) :: phi, phip            ! phi(V) and phi' = (dP/dV)_e
   real(kind=dp) :: c2                   ! c**2

   !*** Every check below that fails sets ierr and EXITs this block,
   !*** landing at the bottom, where p and c are made unusable. A good
   !*** state returns from inside the block.
   ierr = eos_ok
   eos_body: block

      !*** A bad density first: everything below divides by rho.
      if ( .not. ( rho > zero ) ) then
         ierr = eos_bad_density
         exit eos_body
      end if

      v   = one/rho
      eta = one - R0*v
      rg  = R0*G0

      !*** The Hugoniot shock speed, guarded BEFORE any division by xi1
      !*** or D (at the limit both go to zero together).
      a    = one - S1*eta
      disc = a*a - 4.0_dp*S2*eta*eta
      if ( disc <= zero ) then
         ierr = eos_too_compressed
         exit eos_body
      end if
      xi1 = sqrt( disc )
      d   = a + xi1
      if ( d < dmin ) then
         ierr = eos_too_compressed
         exit eos_body
      end if
      us  = two*C0/d
      dus = two*C0*( S1 + (S1 - S1*S1*eta + 4.0_dp*S2*eta)/xi1 )/( d*d )

      !*** The Hugoniot reference curve (cancelled form, no 0/0).
      ph = R0*eta*us*us
      eh = half*(eta*us)**2

      !*** Pressure: thermal part plus the volume-only part phi.
      phi = ph - rg*eh
      p   = rg*e + phi

      !*** Sound speed from the Hugoniot slopes. (V0 - V) = eta*V0 = eta/R0.
      dph_dv = -R0*R0*( us*us + two*eta*us*dus )
      deh_dv = half*( (eta/R0)*dph_dv - ph )
      phip   = dph_dv - rg*deh_dv
      c2     = v*v*( rg*p - phip )
      if ( c2 <= zero ) then
         ierr = eos_bad_soundspeed
         exit eos_body
      end if
      c = sqrt( c2 )
      return                                  ! a good state ends here

   end block eos_body

   !*** Only a failed check gets here: make p and c unusable.
   p = ieee_value( p, ieee_signaling_nan )
   c = ieee_value( c, ieee_signaling_nan )

   end subroutine mg_eos

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
      msg = 'sound speed squared is zero or negative (deep tension?)'
   case default
      msg = 'unknown EOS status'
   end select
   end function eos_message

end module eos

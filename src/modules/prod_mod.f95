module products
!**********************************************************************!
!
!  Purpose:
!    The detonation products' equation of state, for a material that
!    burns (deck: products = ideal_gas, with GAMMA and Q). The burn
!    (module hvrb) mixes the products with the unreacted solid at one
!    density and one temperature; this module gives the gas phase's
!    part, as functions of the density and vartheta = C_V T:
!
!       call idg_state( rho, theta, gamma, p, c2 )
!
!    Today there is one products model, the ideal gas of the HVRB
!    equation sheet (doc/HVRB_Eqns_v8, "Detonation Products"):
!
!       P_gas = (gamma - 1) rho C_V T = (gamma - 1) rho vartheta
!       e_gas = C_V T - Q                 (energy zero at T = 0 K)
!       c_gas**2 = gamma (gamma - 1) vartheta
!
!    with the same C_V as the solid, so the mixture's closure is linear
!    in T (module hvrb). HVRB is usually paired with a JWL or a tabular
!    products EOS; the ideal gas is the first, not the only one. Another
!    (JWL, Davis, a table) is another set of routines here, giving P and
!    e from (rho, T); with its own C_V the closure becomes a one-variable
!    solve for T in module hvrb, in the same place (doc/design/
!    materials.md, phase 3).
!
!  Units, as everywhere in bitwhiz: rho in g/cm^3, vartheta and e in
!  (km/s)^2 = kJ/g, so rho*vartheta is in kJ/cm^3 = GPa; c in km/s.
!
!  References:
!    doc/HVRB_Eqns_v8 (frozen 11/04/26); doc/design/materials.md,
!    phase 3 (approved 11/04/26).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/04/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, zero, one
implicit none
private

public :: idg_state

contains

   !******************************************************************!
   ! The ideal gas: pressure and sound speed squared at density rho   !
   ! and vartheta = C_V T. A vartheta at or below 0 (no temperature,  !
   ! which a cell the hydro has cooled through 0 K could carry) is a  !
   ! gas with no pressure: p = 0 and c2 = 0, never negative. The      !
   ! caller (module hvrb) decides what a cell with c2 = 0 does.       !
   !******************************************************************!
   elemental subroutine idg_state( rho, theta, gamma, p, c2 )
   implicit none
   real(kind=dp), intent(in)  :: rho     ! density, g/cm^3
   real(kind=dp), intent(in)  :: theta   ! vartheta = C_V T, kJ/g
   real(kind=dp), intent(in)  :: gamma   ! ratio of specific heats, > 1
   real(kind=dp), intent(out) :: p       ! P_gas, GPa
   real(kind=dp), intent(out) :: c2      ! c_gas**2, (km/s)^2
   if ( theta > zero ) then
      p  = ( gamma - one )*rho*theta
      c2 = gamma*( gamma - one )*theta
   else
      p  = zero
      c2 = zero
   end if
   end subroutine idg_state

end module products

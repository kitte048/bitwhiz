module halo
!**********************************************************************!
!
!  Purpose:
!    HALO (Hot-spot Activation, Loss and Overlap), a burn model with
!    shock memory and no switches (deck: burn = halo, with eos =
!    mie_gruneisen_t and products = ideal_gas): its activation measure,
!    its hot spots and its burn, each one step.
!
!       call ha_ed_step( ed1, vmin1, de, v, dv, ed2, vmin2 )  the measure
!       a    = ha_act( ed, ED0, BETAH )               Erf((E_D/E_D0)**BETAH)
!       eta2 = ha_eta_step( eta1, lam1, ed1, ed2, dt, ED0, BETAH, TAUD, &
!                           DELTA )                   the hot spots
!       s2   = ha_s_step( s1, eta, P, dt, KB, DFRAC, NH, PR )  the burn
!       lam  = ha_lam( s, DFRAC )                     1 - exp(-s**DFRAC)
!       call ha_step( ... )                           all three, in order
!
!    Elemental and pure; it holds no state. Module burn gives it the
!    cell's E_D, eta, s and smallest volume so far (its history,
!    bst(1:4)), its lam, its P^n, its v = 1/rho and the change of its e
!    and v over the latest step (THE ACTIVATION MEASURE, below). HALO is not gated by the lead shock: a
!    cell's hot spots come from its own compression.
!
!  The model (doc/design/burn_models.md, "HALO" and "Step 8"):
!    hot spots are activated by compression, as a function of a measure
!    E_D of the compression work done on the cell, and dissipated, never
!    reactivated; the reactant burns from them with a fractal topology.
!    Per step, in this order (DK):
!       E_D <- E_D + sqrt( max(De, 0) max(v_min - v, 0) ),
!       v_min <- min(v_min, v)
!       eta <- eta exp(-(1 - lam)**DELTA dt/TAUD)
!              + Erf((E_D2/ED0)**BETAH) - Erf((E_D1/ED0)**BETAH)
!       s   <- s + KB eta**(1/DFRAC) (max(P, 0)/PR)**NH dt
!       lam  = 1 - exp(-s**DFRAC)
!    The concepts are the literature's: hot-spot activation by the work
!    of compression and its loss by dissipation, as in CREST and SURF,
!    and the burn topology of statistical hot spots (SHS) and of Hill and
!    Zimmermann, with the dimension d a free fractal dimension between 2
!    (cylinders) and 3 (spheres). The rest is bitwhiz's own.
!
!  THE ACTIVATION MEASURE: NEW COMPRESSION ONLY (DK, 11/13/26)
!  ===========================================================
!  Each step adds sqrt(De |Dv|) while the cell is compressed past the
!  smallest volume it has had, v_min, and its energy rises; = sqrt(sigma)
!  |Dv|, sigma = De/|Dv| the step's mean stress doing the work, so the sum
!  converges to the integral of sqrt(sigma) |dv| over the compression,
!  independent of the mesh. Compression above v_min adds nothing: the
!  ringing behind a captured shock (AV's especially) oscillates about a
!  volume the cell has already passed, and the plan's first form, which
!  counted every compressive step, took it in (AV's E_D 14 to 18 % above
!  the Rayleigh line's integral, RS's 3 to 6 %; with v_min both 2 to 5 %,
!  AV's within 0.2 % of RS's: doc/design/burn_models.md, "As built: step
!  8"). A second shock
!  drives the cell to a new v_min and counts in full. For a monotone
!  compression the two forms are the same. A step that crosses v_min
!  counts only the part below it (its De whole). v_min = 0 (bst starts
!  at 0) is not yet set: the cell's v before the step, v - Dv, stands in.
!  A shock crossed in one step earns up to 3/(2 sqrt 2) = 1.061 of the
!  integral (sqrt of a mean, not a mean of sqrt). A smooth
!  ramp is compression work too, and activates (71 to 85 % of a shock's
!  E_D to the same volume, for Material X). Units: kJ/g = GPa cm^3/g, so
!  E_D is in GPa**(1/2) cm^3/g. De and Dv come from module burn: the
!  database's old and new rho and e (the latest completed step; under
!  method RS one step behind AV, DK).
!
!  THE STEPS, EXACT WHERE THEY CAN BE
!  ==================================
!  eta: the decay first (exact for constant lam), then the step's new
!  activation, so eta <= Erf((E_D/ED0)**BETAH) <= 1 always: a hot spot
!  once dissipated is never re-activated. s: a potential, exact for eta
!  and P constant over the step (lam = 1 - exp(-(K t)**d), KJMA); in lam,
!  by the chain rule, the hot-spot topology d (-ln(1 - lam))**((d-1)/d)
!  (1 - lam) (Hill, Zimmermann and Nichols), and positive from lam = 0 in
!  s, so no starting term. lam by module thermalcascade's accurate 1 - exp(-x)
!  (tc_om). TAUD = 1e30: exp(...) = 1 exactly, no dissipation. KB = 0:
!  s stays 0 and lam = 0 exactly, the inert limit.
!
!***NOTE: the tests, not max(...)**: (max(P, 0)/PR)**NH is 1 at NH = 0
! whatever P, and 0 for P <= 0 otherwise; (1 - lam)**DELTA is 1 at DELTA
! = 0 (never 0**0).
!
!***NOTE: no overflow. Erf(x**BETAH) is 1 in double once x**BETAH >= 6,
! and 1 - exp(-s**DFRAC) once s**DFRAC >= 40: both are set to 1 there
! from the logarithms, before the power is taken, so no BETAH or DFRAC
! can overflow it (the same results; found by the review).
!
!  Units, as everywhere in bitwhiz: e in kJ/g, v in cm^3/g, E_D and ED0
!  in GPa**(1/2) cm^3/g, P and PR in GPa, dt and TAUD in us, KB in 1/us;
!  eta, s, lam, BETAH, DELTA, DFRAC, NH dimensionless.
!
!  References:
!    doc/design/burn_models.md, "HALO" (approved 11/06/26) and "Step 8,
!    HALO: the plan" (approved 11/13/26); doc/manual, chapter 7, HALO;
!    checked against 50-digit values (tests/test_halo.f95, tests/
!    halo_reference.py).
!    L. G. Hill, B. Zimmermann and A. L. Nichols III, "On the burn
!    topology of hot-spot-initiated reactions", AIP Conf. Proc. 1195, 432
!    (2009), doi:10.1063/1.3295166 (the KJMA form; d = 2 and 3).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/13/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, zero, one
use thermalcascade, only: tc_om
implicit none
private

public :: ha_ed_step, ha_act, ha_eta_step, ha_s_step, ha_lam, ha_step

contains

   !******************************************************************!
   ! The activation measure over one step, new compression only (THE  !
   ! ACTIVATION MEASURE).                                             !
   !******************************************************************!
   elemental subroutine ha_ed_step( ed1, vmin1, de, v, dv, ed2, vmin2 )
   implicit none
   real(kind=dp), intent(in)  :: ed1      ! E_D at the start
   real(kind=dp), intent(in)  :: vmin1    ! smallest v so far (0: not set)
   real(kind=dp), intent(in)  :: de       ! e's change over the step, kJ/g
   real(kind=dp), intent(in)  :: v        ! v at the step's end, cm^3/g
   real(kind=dp), intent(in)  :: dv       ! v's change over the step
   real(kind=dp), intent(out) :: ed2, vmin2
   real(kind=dp) :: vref
   vref = vmin1
   if ( .not. ( vref > zero ) ) vref = v - dv     ! not set: v before
   ed2   = ed1 + sqrt( max( de, zero )*max( vref - v, zero ) )
   vmin2 = min( vref, v )
   end subroutine ha_ed_step

   !******************************************************************!
   ! The activated fraction, Erf((E_D/ED0)**BETAH), 0 to 1.           !
   !******************************************************************!
   elemental function ha_act( ed, ED0, BETAH ) result( a )
   implicit none
   real(kind=dp), intent(in) :: ed, ED0, BETAH
   real(kind=dp) :: a
   real(kind=dp) :: x
   a = zero
   if ( .not. ( ed > zero ) ) return
   x = ed/ED0
   if ( x > one ) then
      if ( BETAH*log( x ) >= log( 6.0_dp ) ) then  ! erf = 1 (the NOTE)
         a = one
         return
      end if
   end if
   a = erf( x**BETAH )
   end function ha_act

   !******************************************************************!
   ! The hot spots over one step: decay at lam1, then the activation  !
   ! from ed1 to ed2 (THE STEPS).                                     !
   !******************************************************************!
   elemental function ha_eta_step( eta1, lam1, ed1, ed2, dt, ED0, BETAH, &
      TAUD, DELTA ) result( eta2 )
   implicit none
   real(kind=dp), intent(in) :: eta1, lam1, ed1, ed2, dt
   real(kind=dp), intent(in) :: ED0, BETAH, TAUD, DELTA
   real(kind=dp) :: eta2, f
   f = one                                        ! (1 - lam)**DELTA (NOTE)
   if ( DELTA > zero ) f = max( one - lam1, zero )**DELTA
   eta2 = eta1*exp( -f*dt/TAUD ) &
      + ( ha_act( ed2, ED0, BETAH ) - ha_act( ed1, ED0, BETAH ) )
   eta2 = min( max( eta2, zero ), one )
   end function ha_eta_step

   !******************************************************************!
   ! The burn's potential over one step: s + K dt, K = KB eta**(1/d)  !
   ! (max(P, 0)/PR)**NH (THE STEPS; the NOTE).                        !
   !******************************************************************!
   elemental function ha_s_step( s1, eta, P, dt, KB, DFRAC, NH, PR ) &
      result( s2 )
   implicit none
   real(kind=dp), intent(in) :: s1, eta, P, dt
   real(kind=dp), intent(in) :: KB, DFRAC, NH, PR
   real(kind=dp) :: s2, fp
   s2 = s1
   if ( .not. ( KB > zero .and. eta > zero ) ) return
   if ( NH > zero ) then
      if ( .not. ( P > zero ) ) return
      fp = ( P/PR )**NH
   else
      fp = one
   end if
   s2 = s1 + KB*eta**( one/DFRAC )*fp*dt
   end function ha_s_step

   !******************************************************************!
   ! lam from the potential: 1 - exp(-s**DFRAC), 0 at s = 0.          !
   !******************************************************************!
   elemental function ha_lam( s, DFRAC ) result( lam )
   implicit none
   real(kind=dp), intent(in) :: s, DFRAC
   real(kind=dp) :: lam
   lam = zero
   if ( .not. ( s > zero ) ) return
   if ( s > one ) then
      if ( DFRAC*log( s ) >= log( 40.0_dp ) ) then ! 1 - e**-40 = 1 (NOTE)
         lam = one
         return
      end if
   end if
   lam = tc_om( s**DFRAC )
   end function ha_lam

   !******************************************************************!
   ! One step of all three, in DK's order: E_D (and v_min), then eta  !
   ! (at lam1),                                                       !
   ! then s (at the new eta and P^n), then lam.                       !
   !******************************************************************!
   elemental subroutine ha_step( ed1, eta1, s1, vmin1, lam1, de, v, dv, P, &
      dt, ED0, BETAH, TAUD, DELTA, DFRAC, NH, KB, PR, ed2, eta2, s2, vmin2, &
      lam2 )
   implicit none
   real(kind=dp), intent(in)  :: ed1, eta1, s1, vmin1, lam1   ! the start
   real(kind=dp), intent(in)  :: de, v, dv             ! the compression
   real(kind=dp), intent(in)  :: P                     ! P^n, GPa
   real(kind=dp), intent(in)  :: dt                    ! us
   real(kind=dp), intent(in)  :: ED0, BETAH, TAUD, DELTA, DFRAC, NH, KB, PR
   real(kind=dp), intent(out) :: ed2, eta2, s2, vmin2, lam2
   call ha_ed_step( ed1, vmin1, de, v, dv, ed2, vmin2 )
   eta2 = ha_eta_step( eta1, lam1, ed1, ed2, dt, ED0, BETAH, TAUD, DELTA )
   s2   = ha_s_step( s1, eta2, P, dt, KB, DFRAC, NH, PR )
   lam2 = ha_lam( s2, DFRAC )
   end subroutine ha_step

end module halo

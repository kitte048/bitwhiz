module thermalcascade
!**********************************************************************!
!
!  Purpose:
!    ThermalCascade, a burn model gated by the lead shock (deck: burn =
!    thermalcascade, with eos = mie_gruneisen_t and products =
!    ideal_gas): its rate and its exact step. Proposed by ChatGPT
!    4o-mini in SAND2025-09228 (§5.2.3), repaired where it can not run
!    as written (doc/design/burn_models.md, "ThermalCascade").
!
!       r    = tc_rate( T, Ps, HT, TC, GT, NS, PR )     1/us
!       lam2 = tc_step( lam1, r, dt )
!
!    Elemental, as module hvrb is; it holds no state. Module burn gives
!    it the cell's T at the start of the step (module temperature: the
!    closure's one temperature, vartheta/C_V, solid and products alike),
!    the lead shock's P_s (module leadshock), and its lam; it burns only
!    once the lead shock is marked (module burn, cell_burn: the gate).
!
!  The model (as proposed, then repaired):
!       dlam/dt = HT (1 - lam) max(T - TC, 0)**GT (1 + P_s/PR)**NS
!    Repairs (the design note): (T - TC)**GT -> max(T - TC, 0)**GT, no
!    burn at or below TC and GT need not be an integer; gated by the
!    lead shock, P_s frozen there (Menikoff and Shaw 2010).
!    The cascade: burning raises T (each lam adds (e_c + Q)/C_V to it),
!    which raises the rate.
!
!  THE STEP, exact for the rate at the start of the step
!  =====================================================
!  The rate is first order in (1 - lam), so over dt at r fixed
!       1 - lam2 = (1 - lam1) exp(-r dt):
!  lam stays in [0, 1) by construction, with no stiffness however large
!  r dt (the cascade's runaway is where an explicit step would fail).
!  Written lam2 = lam1 + (1 - lam1)(1 - exp(-x)), x = r dt, so a small
!  lam keeps its digits; and 1 - exp(-x) by its series below x = 0.5
!  (16 terms: the next, 0.5**17/17!, is below 1e-19 of the sum), since
!  Fortran 2018 has no expm1. (Below 0.05 only, 1 - exp(-x) just above
!  it lost a digit to the subtraction: 5.8e-16 at x = 0.05, measured.) The only error is r's: T and P_s at the
!  start of the step, first order in dt (the design note, "Steps that
!  stay exact").
!
!***NOTE: the temperature test, not max(T - TC, 0)**GT: at GT = 0 that
! would be 0**0, which Fortran leaves to the processor (gfortran gives
! 1), and a cell at or below TC would burn. With the test, a cell at or
! below TC never burns, for every GT; at GT = 0 the rate above TC is
! HT (1 + P_s/PR)**NS, a clock once the lead shock is marked.
!
!  Units, as everywhere in bitwhiz: T and TC in K; P_s and PR in GPa;
!  HT in 1/(us K**GT); r in 1/us; dt in us; GT and NS dimensionless.
!
!  References:
!    D. E. Kittell et al., "A Short Survey of Current Reactive Burn
!    Model Capabilities as of Mid-Year 2025", SAND2025-09228, Sandia
!    National Laboratories (2025), doi:10.2172/2585504, §5.2.3.
!    R. Menikoff and M. S. Shaw, EPJ Web Conf. 10, 00003 (2010), §4.
!    doc/design/burn_models.md (approved 11/06/26), "ThermalCascade",
!    and "As built: step 5"; checked against 50-digit values (tests/
!    test_tcas.f95, tests/tcas_reference.py).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/07/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, one
implicit none
private

public :: tc_rate, tc_step, tc_om

!*** 1 - exp(-x) for small x: below xsmall its series, nseries terms.
real(kind=dp), parameter :: xsmall = 0.5_dp
integer(kind=int32), parameter :: nseries = 16

contains

   !******************************************************************!
   ! The rate, 1/us: HT (T - TC)**GT (1 + P_s/PR)**NS above TC, else  !
   ! 0 (the NOTE). P_s below 0 counts as 0.                           !
   !******************************************************************!
   elemental function tc_rate( T, Ps, HT, TC, GT, NS, PR ) result( r )
   implicit none
   real(kind=dp), intent(in) :: T        ! the cell's temperature, K
   real(kind=dp), intent(in) :: Ps       ! the lead shock's pressure, GPa
   real(kind=dp), intent(in) :: HT       ! rate coefficient, >= 0
   real(kind=dp), intent(in) :: TC       ! critical temperature, K, >= 0
   real(kind=dp), intent(in) :: GT       ! temperature exponent, >= 0
   real(kind=dp), intent(in) :: NS       ! exponent on 1 + P_s/PR, >= 0
   real(kind=dp), intent(in) :: PR       ! reference pressure, GPa, > 0
   real(kind=dp) :: r
   if ( .not. ( T > TC ) ) then
      r = zero
   else if ( GT > zero ) then
      r = HT*( T - TC )**GT*( one + max( Ps, zero )/PR )**NS
   else
      r = HT*( one + max( Ps, zero )/PR )**NS     ! GT = 0 (the NOTE)
   end if
   end function tc_rate

   !******************************************************************!
   ! One exact step (THE STEP): lam2 from lam1 at the rate r over dt. !
   !******************************************************************!
   elemental function tc_step( lam1, r, dt ) result( lam2 )
   implicit none
   real(kind=dp), intent(in) :: lam1     ! lam at the start, 0 to 1
   real(kind=dp), intent(in) :: r        ! the rate, 1/us, >= 0
   real(kind=dp), intent(in) :: dt       ! the step, us
   real(kind=dp) :: lam2
   lam2 = lam1 + ( one - lam1 )*tc_om( r*dt )
   end function tc_step

   !******************************************************************!
   ! 1 - exp(-x), x >= 0, to its relative precision however small x   !
   ! (THE STEP).                                                      !
   !******************************************************************!
   elemental function tc_om( x ) result( om )
   implicit none
   real(kind=dp), intent(in) :: x
   real(kind=dp) :: om, term
   integer(kind=int32) :: k
   if ( x < xsmall ) then
      term = x                           ! x**k/k!, signs alternating
      om   = x
      do k = 2, nseries
         term = -term*x/real(k, dp)
         om   = om + term
      end do
   else
      om = one - exp( -x )
   end if
   end function tc_om

end module thermalcascade

module flashfire
!**********************************************************************!
!
!  Purpose:
!    FlashFire, an Arrhenius burn model gated by the lead shock (deck:
!    burn = flashfire, with eos = mie_gruneisen_t and products =
!    ideal_gas): its rate and its sub-cycled step. Proposed by ChatGPT
!    4o-mini in SAND2025-09228 (§5.2.1), repaired where it can not run
!    as written (doc/design/burn_models.md, "FlashFire" and "Step 6").
!
!       r    = ff_rate( lam, T, Ps, KFF, AFF, BFF, TA, NS, PR )   1/us
!       lam2 = ff_step( lam1, T1, b, Ps, KFF, AFF, BFF, TA, NS, PR, &
!                       LAM0, dt )
!       b    = ff_tslope( es, eta, cv, T0, G0, Q )            K
!
!    Elemental, as module thermalcascade is; it holds no state. Module
!    burn gives it the cell's lam, T and b at the start of the step
!    (THE TEMPERATURE, below), and the lead shock's P_s (module
!    leadshock); it burns only once the lead shock is marked (module
!    burn, cell_burn: the gate).
!
!  The model (as proposed, then repaired):
!       dlam/dt = KFF (1 - lam)**AFF lam**BFF exp(-TA/T) (1 + P_s/PR)**NS
!    Repairs (the design note): lam**BFF is 0 at lam = 0, so the burn
!    would never start: lam is seeded to LAM0 at the lead shock; E_a/R
!    is one activation temperature, TA; gated by the lead shock, P_s
!    frozen there (Menikoff and Shaw 2010). P_s below 0 counts as 0.
!
!  THE TEMPERATURE: T FOLLOWS LAM WITHIN THE STEP (DK, 11/12/26)
!  =============================================================
!  At fixed rho and e the closure's vartheta = C_V T is linear in lam
!  (module mixture: vartheta = e - (1 - lam) e_c + lam Q), so over the
!  step
!       T(lam) = T1 + (lam - lam1) b,      b = (e_c + Q)/C_V,
!  with T1, lam1 and b from the cell's state at the step's start
!  (ff_tslope, from the carried e_S and its eta, or the held solid's:
!  module burn, ff_slope). Each stage of each sub-step uses its own
!  T(lam): the cascade's feedback (burning heats the cell, which burns
!  faster) is resolved within the step, for a few flops and no EOS
!  call.
!
!  THE STEP: RK4 SUB-STEPS, DELTA LAM RELATIVE (DK, 11/12/26)
!  ==========================================================
!  The topology (1 - lam)**AFF lam**BFF has no closed form, so the step
!  is sub-cycled: first the seed, lam = max(lam1, LAM0); then, while
!  time is left, a sub-step of
!       h = min( time left, eps min(lam, 1 - lam)/r )
!  by the classical fourth-order Runge-Kutta method, T(lam) at each
!  stage, lam kept in [LAM0, 1]; once 1 - lam < lam_done (1e-12) the
!  cell is burnt out, lam = 1. eps = 0.1, an algorithm constant (not a
!  deck key, DK). Measured against a 30-digit quadrature of the
!  constant-volume cascade (design note, "Step 6"): about 1e-5 in the
!  time to lam = 0.99 (1.4e-5 at the worst case tried), at a cost of
!  about one sub-step per hydro step over a whole burn (they pile up,
!  to about 60, only in the runaway). The cap is set from k1 alone, so
!  a sub-step moves lam by about, not at most, eps min(lam, 1 - lam). An absolute cap on Delta lam does not converge (the slow
!  induction from LAM0 then runs at the hydro's dt); the relative cap
!  does. What remains is the rate's frozen inputs (P_s, T1, b), first
!  order in dt, as for every model.
!
!***NOTE: the tests, not max(...)**: the rate is 0 unless 0 < lam < 1
! and T > 0, so (1 - lam)**AFF is never 0**0 (AFF = 0, lam = 1), and
! exp(-TA/T) never divides by 0. TA = 0 is no Arrhenius factor.
!
!***NOTE: KFF = 0 is the inert limit: no burn, and no seed either (the
! step returns lam1), so a FlashFire material at KFF = 0 runs the
! lead-shock detector and is otherwise the inert material, bit for bit,
! as ThermalCascade at HT = 0. Any KFF > 0 seeds at the mark.
!
!***NOTE: the sub-steps are bounded. Each one moves lam by about eps
! times min(lam, 1 - lam), from LAM0 up and toward 1 - lam_done, so a
! cell's whole burn takes about (ln(1/LAM0) + ln(1/lam_done))/eps
! sub-steps beyond one per hydro step: under 400 with LAM0 = 1e-4. A
! hard limit, nsub_max per call, guards against a fault; reaching it
! ends the step where lam is, silently (it is not reached in the tests
! or studies: each sub-step either uses all the time left or moves lam
! by a share of lam or 1 - lam, so the loop ends).
!
!  Units, as everywhere in bitwhiz: T, T1 and TA in K; b in K; P_s and
!  PR in GPa; KFF in 1/us; r in 1/us; dt in us; AFF, BFF, NS and LAM0
!  dimensionless.
!
!  References:
!    D. E. Kittell et al., "A Short Survey of Current Reactive Burn
!    Model Capabilities as of Mid-Year 2025", SAND2025-09228, Sandia
!    National Laboratories (2025), doi:10.2172/2585504, §5.2.1.
!    R. Menikoff and M. S. Shaw, EPJ Web Conf. 10, 00003 (2010), §4.
!    doc/design/burn_models.md (approved 11/06/26), "FlashFire", and
!    "Step 6, FlashFire: the plan" (approved 11/12/26); doc/manual,
!    chapter 7, FlashFire; checked against 50-digit values (tests/
!    test_ffire.f95, tests/ffire_reference.py).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/12/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one
implicit none
private

public :: ff_rate, ff_step, ff_tslope, ff_eps, ff_lam_done, ff_nsub_max

!*** The step's algorithm constants (THE STEP, and the NOTEs).
real(kind=dp), parameter :: ff_eps      = 0.1_dp     ! Delta lam, relative
real(kind=dp), parameter :: ff_lam_done = 1.0e-12_dp ! 1 - lam: burnt out
integer(kind=int32), parameter :: ff_nsub_max = 100000

contains

   !******************************************************************!
   ! The rate, 1/us: KFF (1-lam)**AFF lam**BFF exp(-TA/T)             !
   ! (1 + P_s/PR)**NS for 0 < lam < 1 and T > 0, else 0 (the NOTE).   !
   ! P_s below 0 counts as 0.                                         !
   !******************************************************************!
   elemental function ff_rate( lam, T, Ps, KFF, AFF, BFF, TA, NS, PR ) &
      result( r )
   implicit none
   real(kind=dp), intent(in) :: lam      ! extent of reaction
   real(kind=dp), intent(in) :: T        ! the cell's temperature, K
   real(kind=dp), intent(in) :: Ps       ! the lead shock's pressure, GPa
   real(kind=dp), intent(in) :: KFF      ! rate constant, 1/us, >= 0
   real(kind=dp), intent(in) :: AFF      ! exponent on 1 - lam, >= 0
   real(kind=dp), intent(in) :: BFF      ! exponent on lam, >= 0
   real(kind=dp), intent(in) :: TA       ! activation temperature, K, >= 0
   real(kind=dp), intent(in) :: NS       ! exponent on 1 + P_s/PR, >= 0
   real(kind=dp), intent(in) :: PR       ! reference pressure, GPa, > 0
   real(kind=dp) :: r
   if ( .not. ( lam > zero .and. lam < one .and. T > zero ) ) then
      r = zero
   else
      r = KFF*( one - lam )**AFF*lam**BFF*exp( -TA/T ) &
         *( one + max( Ps, zero )/PR )**NS
   end if
   end function ff_rate

   !******************************************************************!
   ! One step (THE STEP): lam2 from lam1 over dt, seeded to LAM0 and  !
   ! sub-cycled by RK4, T following lam as T1 + (lam - lam1) b.       !
   !******************************************************************!
   elemental function ff_step( lam1, T1, b, Ps, KFF, AFF, BFF, TA, NS, &
      PR, LAM0, dt ) result( lam2 )
   implicit none
   real(kind=dp), intent(in) :: lam1     ! lam at the start, 0 to 1
   real(kind=dp), intent(in) :: T1       ! T at the start, K
   real(kind=dp), intent(in) :: b        ! dT/dlam at fixed rho, e: K
   real(kind=dp), intent(in) :: Ps       ! the lead shock's pressure, GPa
   real(kind=dp), intent(in) :: KFF, AFF, BFF, TA, NS, PR  ! the rate's
   real(kind=dp), intent(in) :: LAM0     ! the seed, 0 < LAM0 < 1
   real(kind=dp), intent(in) :: dt       ! the step, us
   real(kind=dp) :: lam2
   real(kind=dp) :: lam, rem, h, k1, k2, k3, k4
   integer(kind=int32) :: n
   if ( .not. ( KFF > zero ) ) then               ! the inert limit (NOTE)
      lam2 = lam1
      return
   end if
   lam = max( lam1, LAM0 )                        ! the seed
   rem = dt
   do n = 1, ff_nsub_max
      if ( .not. ( rem > zero .and. lam < one ) ) exit
      k1 = f( lam )
      if ( .not. ( k1 > zero ) ) exit             ! nothing burns here
      h   = min( rem, ff_eps*min( lam, one - lam )/k1 )
      k2  = f( lam + half*h*k1 )
      k3  = f( lam + half*h*k2 )
      k4  = f( lam + h*k3 )
      lam = min( lam + h*( k1 + 2.0_dp*( k2 + k3 ) + k4 )/6.0_dp, one )
      if ( one - lam < ff_lam_done ) lam = one     ! burnt out
      rem = rem - h
   end do
   lam2 = lam
   contains
      !*** The rate at x (kept in [LAM0, 1]), T following lam.
      pure function f( x ) result( rx )
      real(kind=dp), intent(in) :: x
      real(kind=dp) :: rx, xc
      xc = min( max( x, LAM0 ), one )
      rx = ff_rate( xc, T1 + ( xc - lam1 )*b, Ps, KFF, AFF, BFF, TA, NS, PR )
      end function f
   end function ff_step

   !******************************************************************!
   ! b = dT/dlam at fixed rho and e, K (THE TEMPERATURE): (e_c + Q)/  !
   ! C_V, e_c = e_S - C_V T0 exp(G0 eta), the closure's (module       !
   ! mixture). es and eta: the carried e_S and the eta it holds at,   !
   ! or the held solid's e_S and eta (module burn, ff_slope).         !
   !******************************************************************!
   elemental function ff_tslope( es, eta, cv, T0, G0, Q ) result( b )
   implicit none
   real(kind=dp), intent(in) :: es       ! e_S, kJ/g
   real(kind=dp), intent(in) :: eta      ! the compression it holds at
   real(kind=dp), intent(in) :: cv       ! C_V, kJ/(g K)
   real(kind=dp), intent(in) :: T0       ! K
   real(kind=dp), intent(in) :: G0       ! Gruneisen coefficient at rest
   real(kind=dp), intent(in) :: Q        ! heat of reaction, kJ/g
   real(kind=dp) :: b
   b = ( es - cv*T0*exp( G0*eta ) + Q )/cv
   end function ff_tslope

end module flashfire

module hvrb
!**********************************************************************!
!
!  Purpose:
!    The History Variable Reactive Burn (HVRB), for a material that
!    burns (deck: eos = mie_gruneisen_t, burn = hvrb, products = ...):
!    its rate law, and the closure that mixes the unreacted solid and
!    the products in a cell that is partly burnt.
!
!       call hvrb_step ( phi1, p, dt, PR, ZR, MR, XR, PI, TAU0, phi2, lam2 )
!       call hvrb_state( rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, &
!                        gamma, Q, p, c, theta, dpdlam, ifb, ierr )
!
!    Elemental, as module eos and module temperature are: one cell, or
!    many at once. This module holds no state; the cells' phi and lam,
!    and their constants, are kept by the time loop's caller.
!
!  The model is doc/HVRB_Eqns_v8 (the frozen equation sheet), with the
!  choices of doc/design/materials.md, phase 3 (approved 11/04/26):
!
!    Rate law (separable, history variable):
!       Phi = (1/TAU0) ((P - PI)/PR)**ZR   if P > PI,   else 0
!       phi = integral of Phi dt,          lam = 1 - (1 - phi**MR/XR)**XR
!       up to phi_end = XR**(1/MR), where lam = 1
!    Closure (density-temperature equilibrium, one C_V; the sheet's
!    T-free form), with vartheta = C_V T:
!       vartheta = e - (1 - lam)(e_S - C_V T_S) + lam Q,  T_S = T0 exp(G0 eta)
!       P = (1 - lam) P_sol(rho, e_S - C_V T_S + vartheta) + lam P_gas
!    e_S is the isentrope from rest: module temperature's carried cold
!    energy, e_c there (the sheet's e_c is e_S - C_V T_S; this module
!    calls that ecs).
!
!  Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa; e, e_S,
!  Q and vartheta in (km/s)^2 = kJ/g; C_V in kJ/(g K); T in K; PR and
!  PI in GPa; TAU0 and dt in us; phi dimensionless.
!
!  References:
!    doc/HVRB_Eqns_v8 (frozen 11/04/26): the rate law, the topology,
!    the reactant and products, the closure, the sound speed.
!    doc/design/materials.md, phase 3: the solid dropped while it would
!    pull, the threshold, ZR = 0, the exact sound speed and its guards,
!    dP/dlam for method RS. The closed forms below were checked with
!    sympy (11/04/26), and the module against 50-digit values
!    (tests/test_hvrb.f95, tests/hvrb_reference.py).
!    J. Starkenberg, Proc. 12th Int. Detonation Symp. (2002) 1001-1007,
!    and the sheet's other references, for HVRB itself.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/04/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
!
!  THE RATE LAW
!  ============
!  The stiff part, g(lam) = dlam/dphi, is integrated exactly: phi is
!  summed (phi = phi + Phi*dt, the sheet's first-order quadrature of
!  Phi, its only error) and lam is the topology's closed form of phi.
!  So lam stays in [0, 1] by construction and reaches 1 exactly, at
!  phi_end, where phi stops.
!
!***NOTE: the threshold is a test, not max(P - PI, 0)**ZR. At ZR = 0
! that would be 0**0, which Fortran leaves to the processor (gfortran
! gives 1): a cell at rest would burn. With the test, a cell at or
! below PI never burns, for every ZR, even with PI = 0 (at rest, P = 0
! is not > 0). In tension P < 0 <= PI, so a cell in tension does not
! burn either: HVRB never runs backward, and it stops there.
!
!***NOTE: ZR = 0 is a burn on a clock (design note): above PI, Phi =
! 1/TAU0, so phi is the time spent above threshold over TAU0, PR has no
! effect, and the topology shapes lam(t). With MR = 1 it is a d^n law
! exactly, XR = 3/n and burn-out at XR*TAU0 (the D^2 law: XR = 1.5).
! The unit test integrates one step by step against its closed form.
!
!***NOTE: lam for a small phi. 1 - (1 - x)**XR, x = phi**MR/XR, loses
! digits as x -> 0 (1 - x rounds): at x = 1e-8, half of them. Below
! x = 0.05 the binomial series is summed instead, 16 terms (the next is
! below 0.05**17 = 8e-23 of the first, times binomial coefficients that
! stay of order one for the exponents a burn uses), so lam keeps its
! relative precision however small it is. Fortran 2018 has no log1p.
!
!  THE CLOSURE, AND THE SOLID THAT WOULD PULL
!  ==========================================
!  A cell that has started to burn holds no tension (design note,
!  phase 3): the gas fills the cracks of a reacting solid, so the solid
!  is not mixed in while its pressure is negative,
!     P = (1 - lam) max(P_sol, 0) + lam P_gas.
!  Only its pressure is dropped; vartheta, T and the energy are as
!  written. A cell at lam = 0 is the inert material exactly: mg_eos at
!  (rho, e), the same call and the same bits as eos = mie_gruneisen_t,
!  so tension and spall there are what they always were. A cell at
!  lam = 1 never evaluates the solid (its weight is 0), so it never
!  reaches the solid's Hugoniot limit (eos_too_compressed); a cell with
!  0 < lam < 1 past it stops the run, as an inert cell does.
!
!  THE SOUND SPEED (fixed lam), exact
!  ==================================
!  c**2 = (dP/drho)_e + (P/rho**2)(dP/de)_rho of the pressure actually
!  used. With the solid in (the sheet's exact rule):
!     c**2 = (1-lam) c_sol**2 + lam c_gas**2
!            - lam (1-lam) (R0 G0/rho - gamma + 1)**2 vartheta
!  c_sol at (rho, e_sol), the inert Mie-Gruneisen sound speed at P_sol.
!  With the solid dropped (P = lam P_gas; d ecs/drho = P_c/rho**2 along
!  the isentrope, P_c = P_sol - R0 G0 vartheta the sheet's cold
!  pressure):
!     c**2 = lam (gamma-1) [ vartheta (1 + lam (gamma-1)) - (1-lam) P_c/rho ]
!  Guards, in order, if c**2 <= 0 (or vartheta <= 0, where the gas has
!  no pressure and the exact rule does not hold): the mass-weighted
!  (1-lam) c_sol**2 + lam c_gas**2 (c_sol at max(P_sol, 0)), flag 1;
!  then the gas's alone, flag 2; then eos_bad_soundspeed, as module eos
!  reports a cell with no sound speed (the time loop treats it as it
!  treats that).
!
!  dP/dlam at fixed rho and e (for method RS's source term, rho c**2
!  sigma; design note, phase 3):
!     solid in:      -P_sol + P_gas + [(1-lam) R0 G0 + lam (gamma-1) rho](ecs + Q)
!     solid dropped:          P_gas + lam (gamma-1) rho (ecs + Q)
!  with (gamma - 1) taken as 0 where vartheta <= 0 (P_gas = 0 there).
!  At lam = 0 it is the slope of the burn's first step: the dropped
!  form if P_sol < 0 (P itself jumps there, from P_sol to >= 0, as the
!  cell starts to burn). At lam = 1 the solid is not evaluated: the
!  dropped form (the burn is over, so nothing multiplies it).
!
!**********************************************************************!
use bits,     only: dp, int32, zero, one
use eos,      only: mg_eos, mg_pressure, mg_soundspeed, eos_ok, &
   eos_bad_soundspeed
use products, only: idg_state
implicit none
private

public :: hvrb_phi_end, hvrb_lambda, hvrb_rate, hvrb_step, hvrb_state
public :: hvrb_c_exact, hvrb_c_mass, hvrb_c_gas

!*** The sound speed's flag (ifb): which rule gave c (THE SOUND SPEED).
integer(kind=int32), parameter :: hvrb_c_exact = 0
integer(kind=int32), parameter :: hvrb_c_mass  = 1
integer(kind=int32), parameter :: hvrb_c_gas   = 2

!*** lam for small phi: below xsmall the binomial series, nseries terms.
real(kind=dp), parameter :: xsmall = 0.05_dp
integer(kind=int32), parameter :: nseries = 16

contains

   !******************************************************************!
   ! Where the burn ends: phi_end = XR**(1/MR), lam(phi_end) = 1.     !
   !******************************************************************!
   elemental function hvrb_phi_end( MR, XR ) result( pend )
   implicit none
   real(kind=dp), intent(in) :: MR, XR   ! delay and completion exponents
   real(kind=dp) :: pend
   pend = XR**( one/MR )
   end function hvrb_phi_end

   !******************************************************************!
   ! The topology: lam = 1 - (1 - phi**MR/XR)**XR, 0 for phi <= 0,    !
   ! exactly 1 from phi_end on (see the NOTE on small phi).           !
   !******************************************************************!
   elemental function hvrb_lambda( phi, MR, XR ) result( lam )
   implicit none
   real(kind=dp), intent(in) :: phi      ! history variable
   real(kind=dp), intent(in) :: MR, XR   ! delay and completion exponents
   real(kind=dp) :: lam                  ! extent of reaction, 0 to 1
   real(kind=dp) :: x, b, xk, sgn
   integer(kind=int32) :: k

   if ( phi <= zero ) then
      lam = zero
   else if ( phi >= hvrb_phi_end( MR, XR ) ) then
      lam = one
   else
      x = phi**MR/XR
      if ( x < xsmall ) then          ! 1 - (1 - x)**XR, term by term
         b   = XR
         xk  = x
         sgn = one
         lam = b*xk
         do k = 2, nseries
            b   = b*( XR - real(k - 1, dp) )/real(k, dp)
            xk  = xk*x
            sgn = -sgn
            lam = lam + sgn*b*xk
         end do
      else
         lam = one - ( one - x )**XR
      end if
   end if
   end function hvrb_lambda

   !******************************************************************!
   ! The reaction potential, Phi, 1/us (see the NOTEs: the threshold  !
   ! is a test; ZR = 0 is a clock).                                   !
   !******************************************************************!
   elemental function hvrb_rate( p, PR, ZR, PI, TAU0 ) result( rate )
   implicit none
   real(kind=dp), intent(in) :: p        ! the cell's pressure, GPa
   real(kind=dp), intent(in) :: PR       ! reference pressure, GPa, > 0
   real(kind=dp), intent(in) :: ZR       ! pressure exponent, >= 0
   real(kind=dp), intent(in) :: PI       ! threshold pressure, GPa, >= 0
   real(kind=dp), intent(in) :: TAU0     ! time constant, us, > 0
   real(kind=dp) :: rate
   if ( .not. ( p > PI ) ) then
      rate = zero
   else if ( ZR > zero ) then
      rate = ( ( p - PI )/PR )**ZR/TAU0
   else
      rate = one/TAU0                    ! ZR = 0: a clock (NOTE)
   end if
   end function hvrb_rate

   !******************************************************************!
   ! One step of the burn: phi from phi1 by Phi(p)*dt, at most to     !
   ! phi_end, and its lam. p is the cell's pressure at the start of   !
   ! the step (the sheet: P^n).                                       !
   !******************************************************************!
   elemental subroutine hvrb_step( phi1, p, dt, PR, ZR, MR, XR, PI, TAU0, &
      phi2, lam2 )
   implicit none
   real(kind=dp), intent(in)  :: phi1    ! phi at the start of the step
   real(kind=dp), intent(in)  :: p       ! P at the start of the step, GPa
   real(kind=dp), intent(in)  :: dt      ! the step, us
   real(kind=dp), intent(in)  :: PR, ZR, MR, XR, PI, TAU0   ! the burn's
   real(kind=dp), intent(out) :: phi2    ! phi at the end
   real(kind=dp), intent(out) :: lam2    ! lam at the end
   phi2 = min( phi1 + hvrb_rate( p, PR, ZR, PI, TAU0 )*dt, &
      hvrb_phi_end( MR, XR ) )
   lam2 = hvrb_lambda( phi2, MR, XR )
   end subroutine hvrb_step

   !******************************************************************!
   ! The closure: P, c, vartheta and dP/dlam of a cell at (rho, e,    !
   ! lam), given e_S, its isentrope from rest at rho (module          !
   ! temperature's carried cold energy). ifb says which rule gave c   !
   ! (hvrb_c_exact, _mass, _gas). On any status but eos_ok, p, c and  !
   ! dpdlam are signaling NaNs, as module eos does it, so a caller    !
   ! that ignores ierr stops at the next use; theta is always set.    !
   !******************************************************************!
   elemental subroutine hvrb_state( rho, e, lam, es, R0, C0, S1, S2, G0, &
      cvk, T0k, gamma, Q, p, c, theta, dpdlam, ifb, ierr )
   implicit none
   real(kind=dp), intent(in)  :: rho     ! density, g/cm^3
   real(kind=dp), intent(in)  :: e       ! specific internal energy, kJ/g
   real(kind=dp), intent(in)  :: lam     ! extent of reaction, 0 to 1
   real(kind=dp), intent(in)  :: es      ! e_S at rho, kJ/g
   real(kind=dp), intent(in)  :: R0, C0, S1, S2, G0  ! the solid, as mg_eos
   real(kind=dp), intent(in)  :: cvk     ! C_V, kJ/(g K), both phases
   real(kind=dp), intent(in)  :: T0k     ! T at R0 and e = 0, K
   real(kind=dp), intent(in)  :: gamma   ! the products' gamma
   real(kind=dp), intent(in)  :: Q       ! heat of reaction, kJ/g
   real(kind=dp), intent(out) :: p       ! P, GPa
   real(kind=dp), intent(out) :: c       ! c at fixed lam, km/s
   real(kind=dp), intent(out) :: theta   ! vartheta = C_V T, kJ/g
   real(kind=dp), intent(out) :: dpdlam  ! (dP/dlam) at rho, e; GPa
   integer(kind=int32), intent(out) :: ifb   ! which rule gave c
   integer(kind=int32), intent(out) :: ierr  ! eos_ok, or why not
   real(kind=dp) :: eta, ecs, psol, pg, c2g, g1, c2, cs, pc
   integer(kind=int32) :: ierrc
   logical :: dropped

   ifb   = hvrb_c_exact
   eta   = ( rho - R0 )/rho              ! as module eos computes it
   ecs   = es - cvk*T0k*exp( G0*eta )    ! the sheet's e_c
   theta = e - ( one - lam )*ecs + lam*Q
   call idg_state( rho, theta, gamma, pg, c2g )
   g1 = zero                             ! d P_gas/d(rho vartheta)
   if ( theta > zero ) g1 = gamma - one

   !*** Unburnt: the inert material, bit for bit.
   if ( .not. ( lam > zero ) ) then
      call mg_eos( rho, e, R0, C0, S1, S2, G0, p, c, ierr )
      if ( ierr /= eos_ok ) then
         call unusable( p, c, dpdlam )
      else if ( p < zero ) then          ! the first step drops the solid
         dpdlam = pg
      else
         dpdlam = -p + pg + R0*G0*( ecs + Q )
      end if
      return
   end if

   !*** Burnt: the gas alone; the solid is not evaluated.
   if ( .not. ( lam < one ) ) then
      p      = pg
      dpdlam = pg + g1*rho*( ecs + Q )
      ierr   = eos_ok
      if ( c2g > zero ) then
         c = sqrt( c2g )
      else
         ierr = eos_bad_soundspeed
         call unusable( p, c, dpdlam )
      end if
      return
   end if

   !*** Partly burnt.
   call mg_pressure( rho, ecs + theta, R0, C0, S1, S2, G0, psol, ierr )
   if ( ierr /= eos_ok ) then
      call unusable( p, c, dpdlam )
      return
   end if
   dropped = psol < zero
   if ( dropped ) then                   ! the solid would pull
      p      = lam*pg
      dpdlam = pg + lam*g1*rho*( ecs + Q )
      pc     = psol - R0*G0*theta
      c2     = lam*g1*( theta*( one + lam*g1 ) - ( one - lam )*pc/rho )
   else
      p      = ( one - lam )*psol + lam*pg
      dpdlam = -psol + pg + ( ( one - lam )*R0*G0 + lam*g1*rho )*( ecs + Q )
      c2     = zero
      if ( theta > zero ) then
         call mg_soundspeed( rho, psol, R0, C0, S1, S2, G0, cs, ierrc )
         if ( ierrc == eos_ok ) c2 = ( one - lam )*cs*cs + lam*c2g &
            - lam*( one - lam )*( R0*G0/rho - gamma + one )**2*theta
      end if
   end if

   !*** The guards (THE SOUND SPEED).
   if ( .not. ( c2 > zero ) ) then
      ifb = hvrb_c_mass
      call mg_soundspeed( rho, max( psol, zero ), R0, C0, S1, S2, G0, cs, &
         ierrc )
      c2 = lam*c2g
      if ( ierrc == eos_ok ) c2 = c2 + ( one - lam )*cs*cs
      if ( ierrc /= eos_ok .or. .not. ( c2 > zero ) ) then
         ifb = hvrb_c_gas
         c2  = c2g
      end if
   end if
   if ( c2 > zero ) then
      c = sqrt( c2 )
   else
      ierr = eos_bad_soundspeed
      call unusable( p, c, dpdlam )
   end if
   end subroutine hvrb_state

   !******************************************************************!
   ! Signaling NaNs for results that must not be used (module eos's   !
   ! convention).                                                     !
   !******************************************************************!
   elemental subroutine unusable( a, b, d )
   use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_signaling_nan
   implicit none
   real(kind=dp), intent(out) :: a, b, d
   a = ieee_value( a, ieee_signaling_nan )
   b = ieee_value( b, ieee_signaling_nan )
   d = ieee_value( d, ieee_signaling_nan )
   end subroutine unusable

end module hvrb

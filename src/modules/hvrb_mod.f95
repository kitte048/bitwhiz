module hvrb
!**********************************************************************!
!
!  Purpose:
!    The History Variable Reactive Burn (HVRB), for a material that
!    burns (deck: eos = mie_gruneisen_t, burn = hvrb, products = ...):
!    its rate law. The closure that mixes the unreacted solid and the
!    products in a cell that is partly burnt is module mixture's.
!
!       call hvrb_step ( phi1, p, dt, PR, ZR, MR, XR, PI, TAU0, phi2, lam2 )
!       hvrb_lambda( phi, MR, XR ),  hvrb_rate( p, PR, ZR, PI, TAU0 ),
!       hvrb_phi_end( MR, XR )
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
!    Closure: module mixture.
!
!  Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa; PR and
!  PI in GPa; TAU0 and dt in us; phi dimensionless.
!
!  References:
!    doc/HVRB_Eqns_v8 (frozen 11/04/26): the rate law, the topology.
!    doc/design/materials.md, phase 3: the threshold, ZR = 0. The
!    closed forms below were checked with sympy (11/04/26), and the
!    module against 50-digit values (tests/test_hvrb.f95,
!    tests/hvrb_reference.py).
!    J. Starkenberg, Proc. 12th Int. Detonation Symp. (2002) 1001-1007,
!    and the sheet's other references, for HVRB itself.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/04/26    D. E. Kittell        Original code
!                (with Claude)
!    11/04/26    D. E. Kittell        burn_cell_t, what the hydro's
!                (with Claude)        cell routines need of a burning
!                                     cell (module burn fills it)
!    11/05/26    D. E. Kittell        unusable: snan_dp (module bits),
!                (with Claude)        not ieee_value, for gfortran 8
!    11/05/26    D. E. Kittell        The solid held where it first
!                (with Claude)        pulled (optional rhold, eshold;
!                                     hvrb_pulls): a partly burnt cell
!                                     in tension keeps a vartheta > 0
!
!    11/06/26    D. E. Kittell        The closure (hvrb_state,
!                (with Claude)        hvrb_pulls, burn_cell_t) moved
!                                     to module mixture, for every
!                                     burn model; the rate law
!                                     unchanged
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
!**********************************************************************!
use bits, only: dp, int32, zero, one
implicit none
private

public :: hvrb_phi_end, hvrb_lambda, hvrb_rate, hvrb_step

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

end module hvrb

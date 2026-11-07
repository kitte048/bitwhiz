module mixture
!**********************************************************************!
!
!  Purpose:
!    The closure of a cell that is partly burnt: the unreacted solid
!    (Mie-Gruneisen, eos = mie_gruneisen_t) and its products (an ideal
!    gas, products = ideal_gas, with the solid's C_V) mixed at one
!    density and one temperature, for every burn model (deck: burn =
!    ...). The model's rate law, which says how lam moves, is its own
!    module's (module hvrb); this one says what a cell at lam is.
!
!       call mix_state( rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, &
!                       gamma, Q, p, c, theta, dpdlam, ifb, ierr &
!                       [, rhold, eshold] )
!       mix_pulls( rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, Q )
!       burn_cell_t                    what the hydro's cell routines
!                                      need of a burning cell
!
!    Elemental, as module eos and module temperature are: one cell, or
!    many at once. This module holds no state; the cells' lam, rhold
!    and eshold are module burn's.
!
!  The closure is doc/HVRB_Eqns_v8's (the frozen equation sheet), with
!  the choices of doc/design/materials.md, phase 3 (approved 11/04/26),
!  model-independent once the products are an ideal gas with the
!  solid's C_V (doc/design/burn_models.md, "The closure, factored out
!  first"). Density-temperature equilibrium, one C_V, the sheet's T-free
!  form, with vartheta = C_V T:
!       vartheta = e - (1 - lam)(e_S - C_V T_S) + lam Q,  T_S = T0 exp(G0 eta)
!       P = (1 - lam) P_sol(rho, e_S - C_V T_S + vartheta) + lam P_gas
!    e_S is the isentrope from rest: module temperature's carried cold
!    energy, e_c there (the sheet's e_c is e_S - C_V T_S; this module
!    calls that ecs).
!
!  Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa; e, e_S,
!  Q and vartheta in (km/s)^2 = kJ/g; C_V in kJ/(g K); T in K.
!
!  References:
!    doc/HVRB_Eqns_v8 (frozen 11/04/26): the reactant and products, the
!    closure, the sound speed.
!    doc/design/materials.md, phase 3: the solid dropped while it would
!    pull, the exact sound speed and its guards, dP/dlam for method RS.
!    The closed forms below were checked with sympy (11/04/26), and the
!    module against 50-digit values (tests/test_hvrb.f95,
!    tests/hvrb_reference.py).
!    doc/design/burn_models.md, step 2: this module.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/04/26    D. E. Kittell        Original code, in module hvrb
!                (with Claude)        (hvrb_state; burn_cell_t)
!    11/05/26    D. E. Kittell        unusable: snan_dp (module bits),
!                (with Claude)        not ieee_value, for gfortran 8
!    11/05/26    D. E. Kittell        The solid held where it first
!                (with Claude)        pulled (optional rhold, eshold;
!                                     hvrb_pulls): a partly burnt cell
!                                     in tension keeps a vartheta > 0
!    11/06/26    D. E. Kittell        Moved here from module hvrb, for
!                (with Claude)        every burn model: hvrb_state,
!                                     hvrb_pulls and hvrb_c_* renamed
!                                     mix_state, mix_pulls, mix_c_*;
!                                     the code otherwise unchanged
!
!**********************************************************************!
!
!  THE CLOSURE, AND THE SOLID THAT WOULD PULL
!  ==========================================
!  A cell that has started to burn holds no tension (design note,
!  phase 3): the gas fills the cracks of a reacting solid, so the solid
!  is not mixed in while its pressure is negative,
!     P = (1 - lam) max(P_sol, 0) + lam P_gas.
!  Only its pressure is dropped; vartheta, T and the energy are as
!  written (but see THE SOLID HELD, below). A cell at lam = 0 is the
!  inert material exactly: mg_eos at
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
!  THE SOLID HELD WHERE IT FIRST PULLED (11/05/26)
!  ===============================================
!  A dropped solid does no work (it adds nothing to P), yet its cold
!  energy ecs(rho) went on growing as the cell stretched: energy taken
!  from vartheta by no force, so vartheta, and T, went negative (to
!  -4300 K, Material X at 1 km/s, AV). So the solid stops where it
!  first pulled: at rho_hold, with e_S there, eshold, while the cell is
!  stretched past it (rho < rhold). It cavitates; the gas fills the
!  rest. Module burn keeps rhold and eshold, by cell (burn_hold: set
!  where the solid first pulls, kept while rho < rhold, cleared when
!  the cell is squeezed back to rhold and the solid pushes again).
!  Held, every term of the solid is at (rhold, eshold), the gas's at
!  the cell's rho:
!     ecs = eshold - C_V T0 exp(G0 eta(rhold)),   d ecs/drho = 0
!     vartheta, P, dP/dlam as above, with that ecs and P_sol(rhold, .)
!     c**2 = lam (gamma-1) vartheta
!            + (P/rho**2) [ s (1-lam) R0 G0 + lam (gamma-1) rho ]
!  (s = 1 if the held solid pushes, 0 dropped; P_sol at a fixed density
!  depends on e alone, d P_sol/de = R0 G0). Dropped, that is
!  lam (gamma-1) vartheta (1 + lam (gamma-1)) > 0 wherever vartheta > 0,
!  so the guards are not needed; and an expansion then cools vartheta
!  as rho**(lam (gamma-1)): never below 0, nor below the gas alone
!  expanded the same way. At rho = rhold the held and the unheld
!  closures agree (eshold is e_S there), so P is continuous; a cell
!  that is never held (every cell of every deck before this) gets the
!  same bits as before.
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

public :: mix_state, mix_pulls
public :: mix_c_exact, mix_c_mass, mix_c_gas
public :: burn_cell_t

!*** What a burning cell's pressure needs beyond its database slots (its
!*** rho, e and Mie-Gruneisen constants): handed to the hydro's cell
!*** routines (module av, cell_pressure) by module burn, which keeps the
!*** cells' burn state. A value, not state: this module still keeps none.
type :: burn_cell_t
   real(kind=dp) :: lam   = zero   ! extent of reaction, 0 to 1
   real(kind=dp) :: es    = zero   ! e_S at the cell's rho, kJ/g
   real(kind=dp) :: cv    = zero   ! C_V, kJ/(g K)
   real(kind=dp) :: T0    = zero   ! K
   real(kind=dp) :: gamma = zero   ! the products'
   real(kind=dp) :: Q     = zero   ! kJ/g
   real(kind=dp) :: rhold  = zero  ! where the solid is held, g/cm^3
                                   ! (0: not held; THE SOLID HELD)
   real(kind=dp) :: eshold = zero  ! e_S there, kJ/g
end type burn_cell_t

!*** The sound speed's flag (ifb): which rule gave c (THE SOUND SPEED).
integer(kind=int32), parameter :: mix_c_exact = 0
integer(kind=int32), parameter :: mix_c_mass  = 1
integer(kind=int32), parameter :: mix_c_gas   = 2

contains

   !******************************************************************!
   ! The closure: P, c, vartheta and dP/dlam of a cell at (rho, e,    !
   ! lam), given e_S, its isentrope from rest at rho (module          !
   ! temperature's carried cold energy). ifb says which rule gave c   !
   ! (mix_c_exact, _mass, _gas). On any status but eos_ok, p, c and  !
   ! dpdlam are signaling NaNs, as module eos does it, so a caller    !
   ! that ignores ierr stops at the next use; theta is always set.    !
   ! rhold and eshold (both or neither): the solid held, used for     !
   ! 0 < lam and rho < rhold (THE SOLID HELD); otherwise ignored.     !
   !******************************************************************!
   elemental subroutine mix_state( rho, e, lam, es, R0, C0, S1, S2, G0, &
      cvk, T0k, gamma, Q, p, c, theta, dpdlam, ifb, ierr, rhold, eshold )
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
   real(kind=dp), intent(in), optional :: rhold  ! solid held at, g/cm^3
   real(kind=dp), intent(in), optional :: eshold ! e_S there, kJ/g
   real(kind=dp) :: eta, ecs, psol, pg, c2g, g1, c2, cs, pc, rs
   integer(kind=int32) :: ierrc
   logical :: dropped, held

   !*** The solid's density: the cell's, or where it is held.
   held = .false.
   if ( present( rhold ) .and. present( eshold ) ) &
      held = lam > zero .and. rho < rhold
   rs = rho
   if ( held ) rs = rhold

   ifb   = mix_c_exact
   eta   = ( rs - R0 )/rs                ! as module eos computes it
   if ( held ) then
      ecs = eshold - cvk*T0k*exp( G0*eta )
   else
      ecs = es - cvk*T0k*exp( G0*eta )   ! the sheet's e_c
   end if
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

   !*** Partly burnt (the solid at rs: the cell's rho, or held).
   call mg_pressure( rs, ecs + theta, R0, C0, S1, S2, G0, psol, ierr )
   if ( ierr /= eos_ok ) then
      call unusable( p, c, dpdlam )
      return
   end if
   dropped = psol < zero
   if ( dropped ) then                   ! the solid would pull
      p      = lam*pg
      dpdlam = pg + lam*g1*rho*( ecs + Q )
      if ( held ) then                   ! d ecs/drho = 0
         c2  = lam*g1*theta*( one + lam*g1 )
      else
         pc  = psol - R0*G0*theta
         c2  = lam*g1*( theta*( one + lam*g1 ) - ( one - lam )*pc/rho )
      end if
   else
      p      = ( one - lam )*psol + lam*pg
      dpdlam = -psol + pg + ( ( one - lam )*R0*G0 + lam*g1*rho )*( ecs + Q )
      c2     = zero
      if ( held ) then                   ! P_sol(rhold, .) depends on e only
         c2  = lam*g1*theta + ( p/rho**2 )*( ( one - lam )*R0*G0 + &
            lam*g1*rho )
      else if ( theta > zero ) then
         call mg_soundspeed( rho, psol, R0, C0, S1, S2, G0, cs, ierrc )
         if ( ierrc == eos_ok ) c2 = ( one - lam )*cs*cs + lam*c2g &
            - lam*( one - lam )*( R0*G0/rho - gamma + one )**2*theta
      end if
   end if

   !*** The guards (THE SOUND SPEED).
   if ( .not. ( c2 > zero ) ) then
      ifb = mix_c_mass
      call mg_soundspeed( rs, max( psol, zero ), R0, C0, S1, S2, G0, cs, &
         ierrc )
      c2 = lam*c2g
      if ( ierrc == eos_ok ) c2 = c2 + ( one - lam )*cs*cs
      if ( ierrc /= eos_ok .or. .not. ( c2 > zero ) ) then
         ifb = mix_c_gas
         c2  = c2g
      end if
   end if
   if ( c2 > zero ) then
      c = sqrt( c2 )
   else
      ierr = eos_bad_soundspeed
      call unusable( p, c, dpdlam )
   end if
   end subroutine mix_state

   !******************************************************************!
   ! True if the solid of a partly burnt cell (0 < lam < 1) at its    !
   ! own rho would pull, P_sol < 0: where module burn holds it (THE   !
   ! SOLID HELD). False otherwise, and where the EOS can not say.     !
   !******************************************************************!
   elemental logical function mix_pulls( rho, e, lam, es, R0, C0, S1, &
      S2, G0, cvk, T0k, Q ) result( pulls )
   implicit none
   real(kind=dp), intent(in) :: rho, e, lam, es     ! as mix_state's
   real(kind=dp), intent(in) :: R0, C0, S1, S2, G0  ! the solid
   real(kind=dp), intent(in) :: cvk, T0k, Q         ! C_V, T0, Q
   real(kind=dp) :: eta, ecs, theta, psol
   integer(kind=int32) :: ierr
   pulls = .false.
   if ( .not. ( lam > zero .and. lam < one ) ) return
   eta   = ( rho - R0 )/rho
   ecs   = es - cvk*T0k*exp( G0*eta )
   theta = e - ( one - lam )*ecs + lam*Q
   call mg_pressure( rho, ecs + theta, R0, C0, S1, S2, G0, psol, ierr )
   pulls = ierr == eos_ok .and. psol < zero
   end function mix_pulls

   !******************************************************************!
   ! Signaling NaNs for results that must not be used (module eos's   !
   ! convention).                                                     !
   !******************************************************************!
   elemental subroutine unusable( a, b, d )
   use bits, only: snan_dp                     ! (not ieee_value: bit_mod)
   implicit none
   real(kind=dp), intent(out) :: a, b, d
   a = snan_dp
   b = snan_dp
   d = snan_dp
   end subroutine unusable

end module mixture

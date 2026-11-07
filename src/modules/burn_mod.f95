module burn
!**********************************************************************!
!
!  Purpose:
!    The cells' burn state, for the materials that burn (deck: burn =
!    hvrb, with eos = mie_gruneisen_t and a products EOS): each such
!    cell's model, constants, history variables and extent of reaction
!    lam, by cell, and the burn's step in the time loop. The
!    physics is module hvrb's (the rate law) and module mixture's (the
!    closure), both stateless; this module keeps the state and hands
!    each cell to them.
!
!       call alloc_burn( kerr )                 once, after the t = 0 state
!       call burn_step( dt, kbad )              every cycle, inside the
!                                               time loop's parallel region,
!                                               after the energy update and
!                                               before the pressures
!       burn_cell( k )                          what cell k's pressure
!                                               needs (module av)
!       call burn_track( time, ncycle )         every cycle, after it
!       call burn_audit( nchg )                 at the run's end: the
!                                               cells whose constants
!                                               changed (THE CELLS'
!                                               CONSTANTS, below)
!       lam(k), qk(k)                           cell k's lam and Q (0: none)
!       bmod(k), bpar(:,k), bst(:,k)            its model, constants and
!                                               history variables
!       rhold(k), eshold(k)                     where its solid is held
!                                               (0: not held; THE SOLID
!                                               HELD, below)
!
!    Method RS splits burn_step in two (ONE CYCLE, RS, below):
!       call burn_rate_rs( dt )                 at the cycle's start
!       src(k)                                  cell k's reaction source
!       call temp_cold_cell( k, ierr )          in its cell loop, per cell
!                                               (module temperature)
!       call burn_hold( k )                     then, per cell
!
!    A deck without a burn allocates nothing here and runs exactly as
!    before, bit for bit.
!
!    Why a module of its own, and not module hvrb's arrays: hvrb is the
!    model, pure math; this is the state of whichever burn a cell has.
!    A second burn model (doc/design/burn_models.md) is a row in module
!    burn_table and a case in cell_burn, with nothing else in the code
!    needing to know which model a cell burns with. And every constant
!    is kept by cell, filled from its layer at setup, so constants
!    graded through a layer (TODO.md, section 7) change how these
!    arrays are filled, not the physics.
!
!  Units, as everywhere in bitwhiz: us, GPa, kJ/g; phi and lam are
!  dimensionless.
!
!  References:
!    doc/design/materials.md, phase 3 (approved 11/04/26), the order
!    within a cycle; doc/HVRB_Eqns_v8, "Adding Burn to One Cycle".
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/04/26    D. E. Kittell        Original code
!                (with Claude)
!    11/04/26    D. E. Kittell        Method RS: burn_rate_rs, phi and
!                (with Claude)        lam at the cycle's start, and each
!                                     cell's reaction source for the
!                                     order-2 predictor (src, module rs)
!    11/05/26    D. E. Kittell        rhold, eshold and burn_hold: the
!                (with Claude)        solid held where it first pulled
!                                     (module hvrb, THE SOLID HELD)
!    11/06/26    D. E. Kittell        The cells' burn by model (doc/
!                (with Claude)        design/burn_models.md, step 3):
!                                     bmod, bpar and bst (module
!                                     burn_table's slots) for phi and
!                                     HVRB's six constants; cell_burn,
!                                     one case per model; burn_audit,
!                                     the constants checked at the
!                                     run's end
!    11/06/26    D. E. Kittell        The closure from module mixture
!                (with Claude)        (mix_state, mix_pulls), the rate
!                                     law from module hvrb
!
!**********************************************************************!
!
!  ONE CYCLE, FOR A CELL THAT CAN BURN (the sheet's "Adding Burn to One
!  Cycle"; method AV, maincode section 7)
!  ====================================================================
!    a, b, c. momentum, positions, volumes and energies, as for any cell
!    d0. burn_step: the cold energy e_S to the new volume (module
!        temperature, temp_cold_cell: the closure needs it), then phi by
!        Phi(P^n) dt and lam^(n+1) = lam(phi) (module hvrb, hvrb_step).
!        P^n is the cell's pressure from the last cycle, still in the
!        database at this point.
!    d.  the pressure: a cell with lam > 0 from the closure at (rho,
!        e, lam)^(n+1) (module av, cell_pressure, given burn_cell(k));
!        a cell at lam = 0 exactly as an inert cell.
!        Then burn_hold: where the cell's solid is held (below).
!    after the step: temp_update, then burn_track.
!  Burning changes lam at fixed rho and e, so total energy is the hydro's
!  own (e carries the chemical energy through + lam Q); the heartbeat's
!  energy error is the check.
!
!  ONE CYCLE, METHOD RS (maincode, rs_region)
!  ==========================================
!  RS moves P within the step, in its order-2 predictor (module rs,
!  rs_face_states: half a step of dP/dt = -Z**2 du/dh), which runs
!  before the cells are updated. There the reaction is a source,
!     dP/dt = -Z**2 du/dh + rho c**2 sigma r
!  (Fickett and Davis's thermicity sigma, r = dlam/dt; D. E. Kittell et
!  al., Propellants Explos. Pyrotech. 45 (2020) 295-315, p. 297; doc/
!  design/materials.md, phase 3). So for RS the burn's step is split:
!    0'. burn_rate_rs, at the cycle's start: phi and lam over dt from
!        P^n (nothing else needed), and the source src = rho c**2 sigma r
!        with r = (lam^(n+1) - lam^n)/dt, the step's own rate (not
!        g(lam) Phi: g is infinite at lam = 0 when MR < 1), and rho c**2
!        sigma = (dP/dlam) at fixed rho and e, from the closure at the
!        cell's state n (module mixture), held over the step as Z is.
!    0.  the predictor, given src for a cell that burns this step
!    2.  the cell loop: rho, u, e, then e_S to the new volume
!        (temp_cold_cell), burn_hold, then the state (the closure if
!        lam > 0)
!  Order 1 has no predictor, so no source: its P comes from the closure.
!  The source shapes only the face pressures the Riemann problem is
!  given; the conservative update, and so energy, are untouched.
!
!  THE SOLID HELD (module mixture has the physics)
!  ===============================================
!  A partly burnt cell's solid is held at rhold, with e_S there, eshold,
!  once it pulls: burn_hold, per cell, once a step, after e_S is at the
!  cell's new volume and lam is lam^(n+1), and before the cell's P:
!     rho < rhold (held)                 : kept as it is
!     otherwise, the solid pulls at rho  : rhold = rho, eshold = e_S
!     otherwise                          : not held (rhold = 0)
!  and never held at lam = 0 or 1. So it is set where the solid first
!  pulls, kept while the cell is stretched past that, and cleared once
!  the cell is squeezed back to it and the solid pushes. The same rhold
!  and eshold reach every user of the closure in the step: the cell's
!  P (module av, cell_pressure, through burn_cell, for both methods),
!  RS's source (burn_rate_rs, the next cycle, at the same state n) and
!  T (module temperature, temp_update).
!
!  THE CELLS' CONSTANTS, AND WHAT GUARDS THEM
!  ==========================================
!  Three arrays, three lifetimes (module burn_table):
!    bmod(k)      cell k's model (burn_none, burn_hvrb, ...)
!    bpar(s,k)    its constants, in the model's slot order: written
!                 once, here in alloc_burn, from the cell's layer, and
!                 never again (graded constants, later, vary in space,
!                 never in time)
!    bst(s,k)     its history variables (HVRB: phi): written every
!                 cycle, by cell k only, so any number of threads gives
!                 the same bits
!  What keeps bpar (and bmod, qk, gamk) constant: they are protected,
!  so no other module can assign to them (it does not compile); in
!  this module only alloc_burn does; and the step hands them to a
!  model's routines as intent(in), elemental or pure, which can not
!  write them either. burn_audit checks it at the run's end anyway: it
!  fills every cell's constants again from its layer, as alloc_burn
!  did, and counts the cells whose bits differ (maincode stops with
!  an error if any do). One pass over the cells, no copy kept.
!
!***NOTE: rs_reaction_source turns the source off, for checking its
! effect (design note: G2, on and off); a development switch, not a
! deck key.
!
!**********************************************************************!
use bits,        only: dp, int32, int64, zero, half, one
use shock,       only: kmax, nlay, layer, database, icell, jx, jp, jrho, &
   je, jr0, jc0, js1, js2, jg0, products_ideal_gas
use burn_table,  only: npar_max, nst_max, burn_none, burn_hvrb, hv_PR, &
   hv_ZR, hv_MR, hv_XR, hv_PI, hv_TAU0, hv_phi
use eos,         only: eos_ok
use hvrb,        only: hvrb_step
use mixture,     only: mix_state, mix_pulls, burn_cell_t
use temperature, only: temp_cold_cell, ec, cv, t0
implicit none
private

public :: burn_in_run, alloc_burn, dealloc_burn, burn_step, burn_cell, &
   burn_track, burn_rate_rs, burn_hold, burn_audit
public :: lam, qk, bmod, bpar, bst, nb, kb, first_k, first_time, &
   first_cycle, first_x, lam_max, burnable, src, rhold, eshold

!**********************************************************************!
! Data dictionary: each cell's burn, cell k at index k (1 to kmax).
! Allocated only when some material burns; a cell that does not keeps
! zeros (lam = 0: the tracer and history files write it so). Written
! only by this module, cell by cell (burn_step), so the threads never
! share a value.
!**********************************************************************!
integer(kind=int32), allocatable, protected :: bmod(:) ! the model
real(kind=dp), allocatable, protected :: bpar(:,:)! (1:npar_max, k): its
                                                  ! constants, by slot
real(kind=dp), allocatable, protected :: bst(:,:) ! (1:nst_max, k): its
                                                  ! history variables
real(kind=dp), allocatable, protected :: lam(:)   ! extent of reaction
real(kind=dp), allocatable, protected :: qk(:)    ! Q, kJ/g (products)
real(kind=dp), allocatable, protected :: rhold(:) ! the solid held at,
                                                  ! g/cm^3 (0: not held)
real(kind=dp), allocatable, protected :: eshold(:)! e_S there, kJ/g
real(kind=dp), allocatable, protected :: gamk(:) ! the products' gamma
integer(kind=int32), allocatable, protected :: kb(:)  ! the cells that
                                                  ! can burn, left to right
integer(kind=int32), protected :: nb = 0          ! how many
logical, allocatable, protected :: burnable(:)    ! by cell: can burn
real(kind=dp), allocatable, protected :: src(:)   ! by cell: RS's reaction
                                                  ! source, GPa/us (0: none)
logical, parameter :: rs_reaction_source = .true. ! (NOTE above)

!*** The run's burn, so far: the first cell to react (lam > 0: the first
!*** cycle, and on it the lowest cell) and the largest lam anywhere.
integer(kind=int32), protected :: first_k     = 0     ! cell, 0 = none yet
real(kind=dp), protected       :: first_time  = zero  ! us
integer(kind=int32), protected :: first_cycle = 0
real(kind=dp), protected       :: first_x     = zero  ! mm, cell center
real(kind=dp), protected       :: lam_max     = zero

contains

   !******************************************************************!
   ! True if some layer's material burns (the deck's tables are all   !
   ! it needs, so the output files can ask before the database        !
   ! exists).                                                         !
   !******************************************************************!
   logical function burn_in_run()
   implicit none
   burn_in_run = .false.
   if ( nlay > 0 ) burn_in_run = any( layer(1:nlay)%burn /= burn_none )
   end function burn_in_run

   !******************************************************************!
   ! Allocate the burn state, if some material burns, and set it at  !
   ! t = 0: phi = lam = 0 in every cell (maincode's setup audit       !
   ! checks it). Call after alloc_temperature (a burning material     !
   ! carries T: the deck requires eos = mie_gruneisen_t). Increments  !
   ! kerr on failure.                                                 !
   !******************************************************************!
   subroutine alloc_burn( kerr )
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status, l, k

   if ( allocated(lam) .or. .not. burn_in_run() ) return
   nb = 0
   do l = 1, nlay
      if ( layer(l)%burn /= burn_none ) &
         nb = nb + layer(l)%klast - layer(l)%kfirst + 1
   end do
   allocate( bmod(kmax), bpar(npar_max,kmax), bst(nst_max,kmax), &
      lam(kmax), qk(kmax), gamk(kmax), kb(nb), burnable(kmax), src(kmax), &
      rhold(kmax), eshold(kmax), stat=status )
   if ( status /= 0 ) then
      kerr = kerr + 1
      nb   = 0
      return
   end if
   bst = zero
   lam = zero
   call fill_constants( bmod, bpar, qk, gamk )

   src  = zero
   rhold  = zero
   eshold = zero
   burnable = .false.
   nb  = 0
   do l = 1, nlay
      if ( layer(l)%burn == burn_none ) cycle
      do k = layer(l)%kfirst, layer(l)%klast
         nb = nb + 1
         kb(nb)  = k
         burnable(k) = .true.
      end do
   end do
   first_k = 0
   lam_max = zero
   end subroutine alloc_burn

   !******************************************************************!
   ! Deallocate it (safe to call when nothing was allocated).         !
   !******************************************************************!
   subroutine dealloc_burn( kerr )
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status
   if ( .not. allocated(lam) ) return
   deallocate( bmod, bpar, bst, lam, qk, gamk, kb, burnable, src, rhold, &
      eshold, stat=status )
   if ( status /= 0 ) kerr = kerr + 1
   nb = 0
   end subroutine dealloc_burn

   !******************************************************************!
   ! The burn's step, d0 (ONE CYCLE, above), for every cell that can  !
   ! burn: e_S to the cell's new volume, then phi and lam over dt     !
   ! from the cell's pressure P^n. Call it inside the time loop's     !
   ! parallel region (or outside any): the loop is an orphaned OMP DO !
   ! that binds to the caller's team, so kbad must be shared there.   !
   ! kbad: the first cell whose cold energy could not be moved (the   !
   ! caller stops the run, as for an EOS failure); left as it is if   !
   ! none. Every cell writes only its own k: any number of threads    !
   ! gives the same bits.                                             !
   !******************************************************************!
   subroutine burn_step( dt, kbad )
   implicit none
   real(kind=dp), intent(in) :: dt               ! the step, us
   integer(kind=int32), intent(inout) :: kbad    ! first failure, or huge
   integer(kind=int32) :: n, k, ierr
   real(kind=dp) :: st2(nst_max), lam2

   !$OMP DO REDUCTION(min: kbad)
   do n = 1, nb
      k = kb(n)
      call temp_cold_cell( k, ierr )
      if ( ierr /= eos_ok ) then
         kbad = min( kbad, k )
         cycle
      end if
      call cell_burn( bmod(k), bpar(:,k), bst(:,k), &
         database(jp,icell(k)), dt, st2, lam2 )
      bst(:,k) = st2
      lam(k)   = lam2
      call burn_hold( k )
   end do
   !$OMP END DO
   end subroutine burn_step

   !******************************************************************!
   ! Method RS, step 0' (ONE CYCLE, METHOD RS): phi and lam over dt   !
   ! from P^n, and the reaction source src for the order-2 predictor. !
   ! Call it inside the time loop's parallel region, before the       !
   ! predictor (an orphaned OMP DO, as burn_step). Every cell writes  !
   ! only its own k. A cell whose closure can not be evaluated at its !
   ! state n gets no source (its state at n+1 is evaluated anyway,    !
   ! and stops the run if it fails).                                  !
   !******************************************************************!
   subroutine burn_rate_rs( dt )
   implicit none
   real(kind=dp), intent(in) :: dt               ! the step, us
   integer(kind=int32) :: n, k, i, ifb, ierr
   real(kind=dp) :: st2(nst_max), lam2, p, c, theta, dpdlam

   !$OMP DO
   do n = 1, nb
      k = kb(n)
      i = icell( k )
      call cell_burn( bmod(k), bpar(:,k), bst(:,k), database(jp,i), dt, &
         st2, lam2 )
      src(k) = zero
      if ( rs_reaction_source .and. lam2 > lam(k) ) then
         call mix_state( database(jrho,i), database(je,i), lam(k), ec(k), &
            database(jr0,i), database(jc0,i), database(js1,i), &
            database(js2,i), database(jg0,i), cv(k), t0(k), gamk(k), &
            qk(k), p, c, theta, dpdlam, ifb, ierr, rhold(k), eshold(k) )
         if ( ierr == eos_ok ) src(k) = dpdlam*( lam2 - lam(k) )/dt
      end if
      bst(:,k) = st2
      lam(k)   = lam2
   end do
   !$OMP END DO
   end subroutine burn_rate_rs

   !******************************************************************!
   ! One cell's burn over dt, by its model (module burn_table): its   !
   ! history variables st2 and lam2 at the step's end, from its       !
   ! constants and history variables at the start and its pressure    !
   ! P^n. Writes nothing of the module's: the caller stores st2 and   !
   ! lam2. Its constants are intent(in), here and in the model's      !
   ! routines (THE CELLS' CONSTANTS).                                 !
   !******************************************************************!
   pure subroutine cell_burn( ib, par, st1, p, dt, st2, lam2 )
   implicit none
   integer(kind=int32), intent(in) :: ib            ! the model
   real(kind=dp), intent(in)  :: par(npar_max)      ! its constants
   real(kind=dp), intent(in)  :: st1(nst_max)       ! history, start
   real(kind=dp), intent(in)  :: p                  ! P^n, GPa
   real(kind=dp), intent(in)  :: dt                 ! the step, us
   real(kind=dp), intent(out) :: st2(nst_max)       ! history, end
   real(kind=dp), intent(out) :: lam2               ! lam, end
   st2  = st1
   lam2 = zero
   select case ( ib )
   case ( burn_hvrb )
      call hvrb_step( st1(hv_phi), p, dt, par(hv_PR), par(hv_ZR), &
         par(hv_MR), par(hv_XR), par(hv_PI), par(hv_TAU0), st2(hv_phi), &
         lam2 )
   end select
   end subroutine cell_burn

   !******************************************************************!
   ! Every cell's model and constants, from its layer (THE CELLS'     !
   ! CONSTANTS): alloc_burn's fill, and burn_audit's check of it.     !
   ! Cells that do not burn get burn_none and zeros.                  !
   !******************************************************************!
   subroutine fill_constants( md, par, q, gam )
   implicit none
   integer(kind=int32), intent(out) :: md(:)        ! (kmax)
   real(kind=dp), intent(out) :: par(:,:)           ! (npar_max, kmax)
   real(kind=dp), intent(out) :: q(:), gam(:)       ! (kmax)
   integer(kind=int32) :: l, k
   md  = burn_none
   par = zero
   q   = zero
   gam = zero
   do l = 1, nlay
      if ( layer(l)%burn == burn_none ) cycle
      do k = layer(l)%kfirst, layer(l)%klast
         md(k)    = layer(l)%burn
         par(:,k) = layer(l)%bpar
         if ( layer(l)%products == products_ideal_gas ) then
            gam(k) = layer(l)%GAMMA
            q(k)   = layer(l)%Q
         end if
      end do
   end do
   end subroutine fill_constants

   !******************************************************************!
   ! At the run's end: nchg, the cells whose model or constants (bmod,!
   ! bpar, qk, gamk) differ by any bit from their layer's, filled     !
   ! again as alloc_burn filled them. 0 when nothing burns. Serial,   !
   ! one pass; the arrays it fills are its own, freed on return.      !
   !******************************************************************!
   subroutine burn_audit( nchg )
   implicit none
   integer(kind=int32), intent(out) :: nchg
   integer(kind=int32), allocatable :: md(:)
   real(kind=dp), allocatable :: par(:,:), q(:), gam(:)
   integer(kind=int32) :: k
   nchg = 0
   if ( .not. allocated(lam) ) return
   allocate( md(kmax), par(npar_max,kmax), q(kmax), gam(kmax) )
   call fill_constants( md, par, q, gam )
   do k = 1, kmax
      if ( md(k) /= bmod(k) .or. differ( par(:,k), bpar(:,k) ) .or. &
         differ( (/ q(k), gam(k) /), (/ qk(k), gamk(k) /) ) ) &
         nchg = nchg + 1
   end do
   deallocate( md, par, q, gam )
   contains
      pure logical function differ( a, b )       ! any bit, not just ==
      real(kind=dp), intent(in) :: a(:), b(:)
      differ = any( transfer( a, 1_int64, size(a) ) /= &
         transfer( b, 1_int64, size(b) ) )
      end function differ
   end subroutine burn_audit

   !******************************************************************!
   ! What cell k's pressure needs of its burn (module av, given it    !
   ! when lam(k) > 0): lam, e_S (module temperature's carried cold    !
   ! energy, moved to the cell's volume by burn_step), C_V, T0, the   !
   ! products' gamma and Q, and where its solid is held.              !
   !******************************************************************!
   pure function burn_cell( k ) result( b )
   implicit none
   integer(kind=int32), intent(in) :: k
   type(burn_cell_t) :: b
   b%lam   = lam(k)
   b%es    = ec(k)
   b%cv    = cv(k)
   b%T0    = t0(k)
   b%gamma = gamk(k)
   b%Q     = qk(k)
   b%rhold  = rhold(k)
   b%eshold = eshold(k)
   end function burn_cell

   !******************************************************************!
   ! Where cell k's solid is held (THE SOLID HELD): call once a step, !
   ! after e_S is at the cell's new volume and lam(k) is lam^(n+1),   !
   ! before the cell's P. Cell k only: any number of threads may call !
   ! it, each for its own cells.                                      !
   !******************************************************************!
   subroutine burn_hold( k )
   implicit none
   integer(kind=int32), intent(in) :: k          ! cell, 1 to kmax
   integer(kind=int32) :: i
   real(kind=dp) :: rho
   i   = icell( k )
   rho = database(jrho,i)
   if ( rho < rhold(k) .and. lam(k) > zero .and. lam(k) < one ) return
   if ( mix_pulls( rho, database(je,i), lam(k), ec(k), database(jr0,i), &
      database(jc0,i), database(js1,i), database(js2,i), database(jg0,i), &
      cv(k), t0(k), qk(k) ) ) then
      rhold(k)  = rho                            ! held from here
      eshold(k) = ec(k)
   else
      rhold(k)  = zero                           ! not held
      eshold(k) = zero
   end if
   end subroutine burn_hold

   !******************************************************************!
   ! Bring the run's burn record up to date with this cycle: the      !
   ! first cell to react and the largest lam. Serial, after the       !
   ! cycle, so it is the same on any number of threads (the lowest    !
   ! cell wins, on the first cycle any cell reacts).                  !
   !******************************************************************!
   subroutine burn_track( time, ncycle )
   implicit none
   real(kind=dp), intent(in) :: time              ! us, after the step
   integer(kind=int32), intent(in) :: ncycle      ! cycle, after the step
   integer(kind=int32) :: n, k, i
   do n = 1, nb
      k = kb(n)
      lam_max = max( lam_max, lam(k) )
      if ( first_k == 0 .and. lam(k) > zero ) then
         first_k     = k
         first_time  = time
         first_cycle = ncycle
         i           = icell( k )
         first_x     = half*( database(jx,i-1) + database(jx,i+1) )
      end if
   end do
   end subroutine burn_track

end module burn

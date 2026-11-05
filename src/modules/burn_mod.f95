module burn
!**********************************************************************!
!
!  Purpose:
!    The cells' burn state, for the materials that burn (deck: burn =
!    hvrb, with eos = mie_gruneisen_t and a products EOS): each such
!    cell's history variable phi and extent of reaction lam, and its
!    constants, by cell, and the burn's step in the time loop. The
!    physics is module hvrb's (the rate law and the closure, stateless);
!    this module keeps the state and hands each cell to it.
!
!       call alloc_burn( kerr )                 once, after the t = 0 state
!       call burn_step( dt, kbad )              every cycle, inside the
!                                               time loop's parallel region,
!                                               after the energy update and
!                                               before the pressures
!       burn_cell( k )                          what cell k's pressure
!                                               needs (module av)
!       call burn_track( time, ncycle )         every cycle, after it
!       lam(k), qk(k)                           cell k's lam and Q (0: none)
!
!    A deck without a burn allocates nothing here and runs exactly as
!    before, bit for bit.
!
!    Why a module of its own, and not module hvrb's arrays: hvrb is the
!    model, pure math; this is the state of whichever burn a cell has.
!    A second burn model (the 2025 survey's, TODO.md section 6) is a
!    second branch in burn_step and burn_cell, with nothing else in the
!    code needing to know which model a cell burns with. And every
!    constant is kept by cell, filled from its layer at setup, so
!    constants graded through a layer (TODO.md, section 7) change how
!    these arrays are filled, not the physics.
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
!    after the step: temp_update, then burn_track.
!  Burning changes lam at fixed rho and e, so total energy is the hydro's
!  own (e carries the chemical energy through + lam Q); the heartbeat's
!  energy error is the check.
!
!**********************************************************************!
use bits,        only: dp, int32, zero, half
use shock,       only: kmax, nlay, layer, database, icell, jx, jp, &
   burn_none, burn_hvrb, products_ideal_gas
use eos,         only: eos_ok
use hvrb,        only: hvrb_step, burn_cell_t
use temperature, only: temp_cold_cell, ec, cv, t0
implicit none
private

public :: burn_in_run, alloc_burn, dealloc_burn, burn_step, burn_cell, &
   burn_track
public :: lam, qk, phi, nb, kb, first_k, first_time, first_cycle, first_x, &
   lam_max

!**********************************************************************!
! Data dictionary: each cell's burn, cell k at index k (1 to kmax).
! Allocated only when some material burns; a cell that does not keeps
! zeros (lam = 0: the tracer and history files write it so). Written
! only by this module, cell by cell (burn_step), so the threads never
! share a value.
!**********************************************************************!
real(kind=dp), allocatable, protected :: phi(:)   ! history variable
real(kind=dp), allocatable, protected :: lam(:)   ! extent of reaction
real(kind=dp), allocatable, protected :: qk(:)    ! Q, kJ/g (products)
real(kind=dp), allocatable :: prk(:), zrk(:), mrk(:), xrk(:), pik(:), &
   tauk(:)                                        ! HVRB's, as layer_t's
real(kind=dp), allocatable :: gamk(:)             ! the products' gamma
integer(kind=int32), allocatable, protected :: kb(:)  ! the cells that
                                                  ! can burn, left to right
integer(kind=int32), protected :: nb = 0          ! how many

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
   allocate( phi(kmax), lam(kmax), qk(kmax), prk(kmax), zrk(kmax), &
      mrk(kmax), xrk(kmax), pik(kmax), tauk(kmax), gamk(kmax), kb(nb), &
      stat=status )
   if ( status /= 0 ) then
      kerr = kerr + 1
      nb   = 0
      return
   end if
   phi = zero
   lam = zero
   qk  = zero
   prk = zero
   zrk = zero
   mrk = zero
   xrk = zero
   pik = zero
   tauk = zero
   gamk = zero
   nb  = 0
   do l = 1, nlay
      if ( layer(l)%burn /= burn_hvrb ) cycle
      do k = layer(l)%kfirst, layer(l)%klast
         nb = nb + 1
         kb(nb)  = k
         prk(k)  = layer(l)%PR
         zrk(k)  = layer(l)%ZR
         mrk(k)  = layer(l)%MR
         xrk(k)  = layer(l)%XR
         pik(k)  = layer(l)%PI
         tauk(k) = layer(l)%TAU0
         if ( layer(l)%products == products_ideal_gas ) then
            gamk(k) = layer(l)%GAMMA
            qk(k)   = layer(l)%Q
         end if
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
   deallocate( phi, lam, qk, prk, zrk, mrk, xrk, pik, tauk, gamk, kb, &
      stat=status )
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
   real(kind=dp) :: phi2, lam2

   !$OMP DO REDUCTION(min: kbad)
   do n = 1, nb
      k = kb(n)
      call temp_cold_cell( k, ierr )
      if ( ierr /= eos_ok ) then
         kbad = min( kbad, k )
         cycle
      end if
      call hvrb_step( phi(k), database(jp,icell(k)), dt, prk(k), zrk(k), &
         mrk(k), xrk(k), pik(k), tauk(k), phi2, lam2 )
      phi(k) = phi2
      lam(k) = lam2
   end do
   !$OMP END DO
   end subroutine burn_step

   !******************************************************************!
   ! What cell k's pressure needs of its burn (module av, given it    !
   ! when lam(k) > 0): lam, e_S (module temperature's carried cold    !
   ! energy, moved to the cell's volume by burn_step), C_V, T0, and   !
   ! the products' gamma and Q.                                       !
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
   end function burn_cell

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

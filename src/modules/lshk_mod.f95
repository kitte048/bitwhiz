module leadshock
!**********************************************************************!
!
!  Purpose:
!    The lead-shock detector of Menikoff and Shaw's SURF (2010, §4),
!    for the burn models that need the lead shock's pressure, P_s (doc/
!    design/burn_models.md, "The lead shock, P_S and t_s", and step 4):
!    one cell's detector, five numbers, stepped once a cycle from the
!    cell's state at the step's end.
!
!       h = ls_h( rho, e, p, R0 )        the energy jump condition's
!                                        residual, kJ/g
!       call ls_step( st, rho, e, p, R0, C0, t, dt )
!                                        one step of the detector
!       ls_marked( st )                  true once the lead shock is
!                                        marked; then st(ls_ps) is P_s,
!                                        GPa, and st(ls_ts) is t_s, us
!
!    Pure, and it holds no state: the five numbers are the caller's
!    (module burn keeps them in the cell's bst, slots 1 to ls_nst).
!
!  THE RESIDUAL
!  ============
!     h = e - e_0 - (1/2)(V_0 - V)(P + P_0),
!  the Hugoniot's energy jump condition, with the state ahead of the
!  lead shock the cell's own at t = 0: at rest at R0, e_0 = 0, P_0 = 0
!  (every bitwhiz cell starts there; Menikoff and Shaw print P - P_0, an
!  erratum, moot here). On the Hugoniot h = 0. Inside a steady smeared
!  shock, along its Rayleigh line, h = (1/2) q (V_0 - V) exactly (AV's
!  q; RS's dissipation plays its part); as the cell reaches the shocked
!  state, h falls back.
!
!  THE STEPS (flag in st(ls_flag))
!  ===============================
!    quiet    (ls_quiet):   armed, rising, once V < V_0 and h > the
!                           floor
!    rising   (ls_rising):  h_max follows h up; on the first fall,
!    falling  (ls_falling): marked at the first step where
!                             h <= 0 (a zero crossing: compression
!                                    follows the shock), t_s between the
!                                    two steps where h changes sign, or
!                             h > h_last (a local minimum: expansion
!                                    follows), t_s the minimum's step, or
!                             h_last - h < ls_knee times the largest
!                                    one-step fall since the peak (the
!                                    fall has stalled: a weak shock's
!                                    tail; NOTE below), t_s this step;
!                           P_s = P at the step that marks it. A rise
!                           past h_max before any: rising again. Until
!                           the mark, slot ls_ps holds that largest
!                           fall (P_s is not yet known, so no sixth
!                           number is needed).
!    shocked  (ls_shocked): frozen; P_s and t_s never change again.
!
!***NOTE: the floor. A wave's first cells see an exponentially small
! precursor (P of 1e-233 GPa, measured) long before the shock, whose
! round-off wiggles would read as a local minimum (a false mark at
! P = 0, measured with no floor). So the detector arms only once
! h > ls_floor*C0**2: the material's own energy scale, C0**2 in
! (km/s)**2 = kJ/g, times an algorithm constant (not a deck key).
! Measured (doc/design/burn_models.md, "As built: step 4"): every
! floor from 1e-14 to 1e-7 marks every shock tried, 0.75 to 78 GPa, AV
! and RS, 25 to 200 zones/mm, and none at P = 0; 1e-6 misses the
! weakest. 1e-10, three decades from either edge.
!
!***NOTE: no hysteresis. A weak shock's h does not come back down (AV,
! 0.75 GPa: from 3.1e-5 to a plateau at 3.0e-5 kJ/g, the shocked state
! a little off the Hugoniot), so the first local minimum must count,
! however shallow; a test such as "below half of h_max" misses every
! weak shock (measured).
!
!***NOTE: the stall. After a weak shock in AV, P is on its plateau
! within a few ns, but h creeps down toward its own for 100 ns more, by
! less and less each step (0.75 GPa in aluminum: from 6.98e-6 to
! 6.884e-6 kJ/g), so its first local minimum, where round-off ends
! the creep, came 117 ns after the shock at 200 zones/mm, and later on
! finer meshes: not converging. Marked instead once a step's fall is
! below ls_knee of the largest: the lag then shrinks with the mesh (36,
! 21, 14 ns at 25, 100, 200 zones/mm) for every value tried from 0.003
! up. A larger one marks sooner, but moves P_s where P falls right
! behind the front (a decaying shock: up to 1.3 % at 0.003, 2.7 % at
! 0.03 and 0.1, 5 % at 0.3, against 0.01; on square shocks at most
! 0.6 % from 0.003 to 0.1, every P_s within 1.1 % of exact at 0.01).
! 0.01, the middle of the range that converges.
!
!***NOTE: a smooth ramp. Its foot is a compression front too: h rises
! a little there (AV's q, RS's dissipation) and comes back as the ramp
! goes on, so the foot is marked, at a P_s that falls as the mesh
! refines (ramp_linear, 0.05 mm into the window: AV 0.67, 0.44, 0.30,
! 0.20 GPa at 25, 50, 100, 200 zones/mm). A ramp that steepens into a
! shock before the cell sees it is marked at the shock (8.4 GPa there,
! every mesh). See the design note.
!
!  Units, as everywhere in bitwhiz: g/cm^3, kJ/g, GPa, us, km/s.
!
!  References:
!    R. Menikoff and M. S. Shaw, "Reactive burn models and ignition &
!    growth concept", EPJ Web Conf. 10, 00003 (2010), §4, eq. (10).
!    doc/design/burn_models.md (approved 11/06/26), "The lead shock",
!    step 4, and "As built: step 4" (the measurements above).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/06/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one
implicit none
private

public :: ls_h, ls_step, ls_marked
public :: ls_nst, ls_hlast, ls_hmax, ls_flag, ls_ps, ls_ts
public :: ls_quiet, ls_rising, ls_falling, ls_shocked, ls_floor, ls_knee

!*** The detector's five numbers, in this order in its caller's array.
integer(kind=int32), parameter :: ls_nst   = 5
integer(kind=int32), parameter :: ls_hlast = 1   ! h at the last step
integer(kind=int32), parameter :: ls_hmax  = 2   ! its largest, since armed
integer(kind=int32), parameter :: ls_flag  = 3   ! the step it is in
integer(kind=int32), parameter :: ls_ps    = 4   ! P_s, GPa (once marked;
                                                 ! before, the largest
                                                 ! one-step fall of h)
integer(kind=int32), parameter :: ls_ts    = 5   ! t_s, us (once marked)

!*** The flag's values (kept as a real in its slot, compared by nint).
integer(kind=int32), parameter :: ls_quiet   = 0
integer(kind=int32), parameter :: ls_rising  = 1
integer(kind=int32), parameter :: ls_falling = 2
integer(kind=int32), parameter :: ls_shocked = 3

!*** The floor, in units of C0**2, and the stall (the NOTEs above).
real(kind=dp), parameter :: ls_floor = 1.0e-10_dp
real(kind=dp), parameter :: ls_knee  = 0.01_dp

contains

   !******************************************************************!
   ! h, the residual of the energy jump condition from the cell's     !
   ! state at t = 0 (rest at R0, e_0 = P_0 = 0), kJ/g.                !
   !******************************************************************!
   elemental function ls_h( rho, e, p, R0 ) result( h )
   implicit none
   real(kind=dp), intent(in) :: rho      ! density, g/cm^3
   real(kind=dp), intent(in) :: e        ! specific internal energy, kJ/g
   real(kind=dp), intent(in) :: p        ! pressure, GPa
   real(kind=dp), intent(in) :: R0       ! reference density, g/cm^3
   real(kind=dp) :: h
   h = e - half*( one/R0 - one/rho )*p
   end function ls_h

   !******************************************************************!
   ! One step of the detector (THE STEPS), from the cell's state at   !
   ! the step's end, t, and the step's length, dt. st is the cell's   !
   ! five numbers, all 0 at t = 0.                                    !
   !******************************************************************!
   pure subroutine ls_step( st, rho, e, p, R0, C0, t, dt )
   implicit none
   real(kind=dp), intent(inout) :: st(ls_nst)  ! the detector's numbers
   real(kind=dp), intent(in) :: rho, e, p      ! the state at t
   real(kind=dp), intent(in) :: R0, C0         ! the material's
   real(kind=dp), intent(in) :: t, dt          ! us
   real(kind=dp) :: h, hl, d
   integer(kind=int32) :: flag

   flag = nint( st(ls_flag), int32 )
   if ( flag == ls_shocked ) return
   h  = ls_h( rho, e, p, R0 )
   hl = st(ls_hlast)
   st(ls_hlast) = h

   select case ( flag )
   case ( ls_quiet )
      if ( rho > R0 .and. h > ls_floor*C0*C0 ) then
         st(ls_hmax) = h
         st(ls_ps)   = zero
         st(ls_flag) = real( ls_rising, dp )
      end if
   case default                                ! rising or falling
      if ( h > st(ls_hmax) ) then
         st(ls_hmax) = h                       ! (rising again)
         st(ls_ps)   = zero
         st(ls_flag) = real( ls_rising, dp )
      else if ( flag == ls_rising .and. h < hl ) then
         st(ls_flag) = real( ls_falling, dp )  ! the first fall, which
         st(ls_ps)   = hl - h                  ! (the largest so far)
         if ( .not. ( h > zero ) ) then        ! may cross zero at once
            st(ls_ps)   = p
            st(ls_ts)   = t - dt*h/( h - hl )
            st(ls_flag) = real( ls_shocked, dp )
         end if
      else if ( flag == ls_falling ) then
         if ( .not. ( h > zero ) ) then        ! a zero crossing
            st(ls_ps)   = p
            st(ls_ts)   = t - dt*h/( h - hl )  ! hl > 0 >= h: h - hl < 0
            st(ls_flag) = real( ls_shocked, dp )
         else if ( h > hl ) then               ! a local minimum, at t - dt
            st(ls_ps)   = p
            st(ls_ts)   = t - dt
            st(ls_flag) = real( ls_shocked, dp )
         else                                  ! still falling: stalled?
            d = hl - h
            if ( d < ls_knee*st(ls_ps) ) then
               st(ls_ps)   = p
               st(ls_ts)   = t
               st(ls_flag) = real( ls_shocked, dp )
            else
               st(ls_ps) = max( st(ls_ps), d )
            end if
         end if
      end if
   end select
   end subroutine ls_step

   !******************************************************************!
   ! True once the lead shock is marked.                              !
   !******************************************************************!
   pure logical function ls_marked( st )
   implicit none
   real(kind=dp), intent(in) :: st(ls_nst)
   ls_marked = nint( st(ls_flag), int32 ) == ls_shocked
   end function ls_marked

end module leadshock

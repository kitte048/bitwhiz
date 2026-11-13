module burn_table
!**********************************************************************!
!
!  Purpose:
!    The burn models' table: which models there are, which deck keys
!    each takes and in what order, and how many history variables each
!    keeps per cell. Constants only, fixed when the code is compiled;
!    the deck reader (module deck) and the cells' burn (module burn)
!    are driven by it, so a new model is a row here and its own module
!    (doc/design/burn_models.md, step 3).
!
!       burn_none, burn_hvrb, ...     the model codes (deck: burn = ...)
!       burn_names(ib), burn_long(ib) its deck name and full name
!       npar_max, nst_max             the most constants and history
!                                     variables any model has, per cell
!       nbkey, bkey_name(j), bkey_check(j), bkey_note(j)
!       bkey_max(j)                   a key's largest value (huge: none)
!                                     every burn key, each listed once
!       burn_npar(ib), burn_key(s,ib) model ib's keys, slot s = 1 to
!                                     burn_npar(ib), as indices j into
!                                     the keys (0 past the last)
!       burn_nst(ib)                  its history variables
!       burn_uses_ls(ib)              does it need the lead shock
!                                     (module leadshock: its five
!                                     numbers are then bst(1:5))
!       bkey_index( key )             j of a key, 0 if not a burn key
!       burn_takes( ib, j )           does model ib take key j
!       hv_PR ... hv_TAU0, hv_phi     HVRB's slots, in bpar and bst
!       tc_HT ... tc_PR               ThermalCascade's, in bpar
!       ff_KFF ... ff_LAM0            FlashFire's, in bpar
!
!  Three arrays, three lifetimes (module burn keeps the last two):
!    this table   what a model is: compiled in, never written;
!    bpar(s,k)    cell k's constants, in model slot order: written once,
!                 at setup, from its layer (and, once graded, varying
!                 in space but never in time);
!    bst(s,k)     cell k's history variables: written every cycle, by
!                 cell k only.
!
!  The keys' rules (doc/design/burn_models.md, "Deck keys", approved
!  11/06/26), checked on this table by tests/test_btab.f95:
!    1. One key, one meaning, in every model: each key is listed once,
!       with one check and one note, and models share it by index.
!    2. A model takes only its own keys (module deck: any other burn
!       key is a deck error).
!    3. No burn key has the name of another Material key (R0, C0, S1,
!       S2, G0, CV, T0, GAMMA, Q, eos, burn, products, spall_strength).
!  A model with more keys than npar_max does not compile: burn_key's
!  constructor would not fit its declared shape.
!
!  Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa, kJ/g, K.
!
!  References:
!    doc/design/burn_models.md (approved 11/06/26): "Per-cell
!    parameters and state, ready for grading" (the slot table), "Deck
!    keys", and step 3.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/06/26    D. E. Kittell        Original code: HVRB's row (its
!                (with Claude)        keys and checks as module deck
!                                     had them), and burn_none,
!                                     burn_hvrb and burn_names from
!                                     module shock
!    11/06/26    D. E. Kittell        burn_uses_ls: the models that
!                (with Claude)        need the lead shock (step 4)
!    11/07/26    D. E. Kittell        ThermalCascade's row (step 5):
!                (with Claude)        burn_tcas; keys HT, TC, GT, NS
!                                     (PR shared); its slots tc_*
!    11/12/26    D. E. Kittell        FlashFire's row (step 6):
!                (with Claude)        burn_ffire; keys KFF, AFF, BFF,
!                                     TA, LAM0 (NS, PR shared); a
!                                     new check, chk_open01 (LAM0);
!                                     its slots ff_*
!    11/12/26    D. E. Kittell        bkey_max, a key's largest value:
!                (with Claude)        XR at most 25, where hvrb_lambda's
!                                     series still keeps lam to
!                                     round-off (the v1.4.0 review,
!                                     F-03)
!
!**********************************************************************!
use bits, only: int32, dp
implicit none
private

public :: npar_max, nst_max, nburn, burn_none, burn_hvrb, burn_names, &
   burn_long, nbkey, bkey_name, bkey_check, bkey_note, bkey_max, chk_any, &
   chk_positive, chk_nonneg, burn_npar, burn_key, burn_nst, burn_uses_ls, &
   bkey_index, burn_takes
public :: hv_PR, hv_ZR, hv_MR, hv_XR, hv_PI, hv_TAU0, hv_phi
public :: burn_tcas, tc_HT, tc_TC, tc_GT, tc_NS, tc_PR
public :: burn_ffire, ff_KFF, ff_AFF, ff_BFF, ff_TA, ff_NS, ff_PR, ff_LAM0
public :: chk_open01

!*** Per cell, at most (the slot table: StochasticIgnite and HALO take 8
!*** constants, StochasticIgnite keeps 6 numbers).
integer(kind=int32), parameter :: npar_max = 8
integer(kind=int32), parameter :: nst_max  = 6

!*** The models (deck: burn = <name>). burn_none is the default.
integer(kind=int32), parameter :: nburn      = 3
integer(kind=int32), parameter :: burn_none  = 0
integer(kind=int32), parameter :: burn_hvrb  = 1
integer(kind=int32), parameter :: burn_tcas  = 2
integer(kind=int32), parameter :: burn_ffire = 3
character(len=16), parameter, dimension(nburn) :: burn_names = (/ &
   'hvrb            ', 'thermalcascade  ', 'flashfire       ' /)
character(len=40), parameter, dimension(nburn) :: burn_long = (/ &
   'History Variable Reactive Burn          ', &
   'ThermalCascade, SAND2025-09228, repaired', &
   'FlashFire, SAND2025-09228, repaired     ' /)

!*** Every burn key, each once (rule 1): its name as the resolved deck
!*** writes it, the check its value must pass, and the resolved deck's
!*** note beside it.
integer(kind=int32), parameter :: chk_any      = 0   ! any real
integer(kind=int32), parameter :: chk_positive = 1   ! > 0
integer(kind=int32), parameter :: chk_nonneg   = 2   ! >= 0
integer(kind=int32), parameter :: chk_open01   = 3   ! > 0 and < 1
integer(kind=int32), parameter :: nbkey = 15
character(len=8), parameter, dimension(nbkey) :: bkey_name = (/ &
   'PR      ', 'ZR      ', 'MR      ', 'XR      ', 'PI      ', &
   'TAU0    ', 'HT      ', 'TC      ', 'GT      ', 'NS      ', &
   'KFF     ', 'AFF     ', 'BFF     ', 'TA      ', 'LAM0    ' /)
integer(kind=int32), parameter, dimension(nbkey) :: bkey_check = (/ &
   chk_positive, chk_nonneg, chk_positive, chk_positive, chk_nonneg, &
   chk_positive, chk_nonneg, chk_nonneg, chk_nonneg, chk_nonneg, &
   chk_nonneg, chk_nonneg, chk_nonneg, chk_nonneg, chk_open01 /)
character(len=32), parameter, dimension(nbkey) :: bkey_note = (/ &
   'GPa, reference pressure         ', 'pressure exponent               ', &
   'delay exponent                  ', 'completion exponent             ', &
   'GPa, threshold                  ', 'us, time constant               ', &
   '1/(us K**GT), rate coefficient  ', 'K, critical temperature         ', &
   'temperature exponent            ', 'exponent on 1 + P_s/PR          ', &
   '1/us, rate constant             ', 'exponent on 1 - lam             ', &
   'exponent on lam                 ', 'K, activation temperature       ', &
   'ignition fraction at the shock  ' /)
!*** And its largest value (huge(1.0_dp): none). XR above 25 is refused:
!*** hvrb_lambda's series for small phi loses digits there (1e-14 at 30,
!*** 7e-6 at 80, against 50 digits; input/README.md, the v1.4.0 review's
!*** F-03), and burns use XR of a few.
real(kind=dp), parameter, dimension(nbkey) :: bkey_max = (/ &
   huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), 25.0_dp, huge(1.0_dp), &
   huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), &
   huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp), huge(1.0_dp) /)

!*** The models' rows: their keys in slot order (indices into the keys
!*** above, 0 past the last) and their history variables.
integer(kind=int32), parameter, dimension(nburn) :: burn_npar = (/ 6, 5, 7 /)
integer(kind=int32), parameter, dimension(npar_max,nburn) :: burn_key = &
   reshape( (/ 1, 2, 3, 4, 5, 6, 0, 0, &          ! hvrb
               7, 8, 9, 10, 1, 0, 0, 0, &         ! thermalcascade
               11, 12, 13, 14, 10, 1, 15, 0 /), & ! flashfire
            (/ npar_max, nburn /) )
integer(kind=int32), parameter, dimension(nburn) :: burn_nst = (/ 1, 5, 5 /)
!*** Which models need the lead shock's pressure, P_s (doc/design/
!*** burn_models.md, "The lead shock"): their history variables start
!*** with the detector's five (module leadshock, ls_nst), their own
!*** after them. HVRB does not.
logical, parameter, dimension(nburn) :: burn_uses_ls = &
   (/ .false., .true., .true. /)

!*** HVRB's slots: its constants in bpar, its phi in bst.
integer(kind=int32), parameter :: hv_PR = 1, hv_ZR = 2, hv_MR = 3, &
   hv_XR = 4, hv_PI = 5, hv_TAU0 = 6
integer(kind=int32), parameter :: hv_phi = 1

!*** ThermalCascade's slots: its constants in bpar (HT, TC, GT, NS, PR,
!*** the design note's order); its bst is the detector's five, and lam
!*** is the model's own variable (module burn's lam).
integer(kind=int32), parameter :: tc_HT = 1, tc_TC = 2, tc_GT = 3, &
   tc_NS = 4, tc_PR = 5

!*** FlashFire's slots: its constants in bpar (KFF, AFF, BFF, TA, NS, PR,
!*** LAM0, the design note's order); its bst is the detector's five, and
!*** lam is the model's own variable, as ThermalCascade's.
integer(kind=int32), parameter :: ff_KFF = 1, ff_AFF = 2, ff_BFF = 3, &
   ff_TA = 4, ff_NS = 5, ff_PR = 6, ff_LAM0 = 7

contains

   !******************************************************************!
   ! The index j of a burn key, by name in any case; 0 if it is not   !
   ! one.                                                             !
   !******************************************************************!
   pure function bkey_index( key ) result( j )
   implicit none
   character(len=*), intent(in) :: key
   integer(kind=int32) :: j
   do j = 1, nbkey
      if ( upper( trim(key) ) == trim(bkey_name(j)) ) return
   end do
   j = 0
   return
   contains
      pure function upper( text ) result( s )
      character(len=*), intent(in) :: text
      character(len=len(text)) :: s
      integer(kind=int32) :: i
      s = text
      do i = 1, len(s)
         if ( s(i:i) >= 'a' .and. s(i:i) <= 'z' ) &
            s(i:i) = achar( iachar(s(i:i)) - 32 )
      end do
      end function upper
   end function bkey_index

   !******************************************************************!
   ! True if model ib (1 to nburn) takes key j (1 to nbkey).          !
   !******************************************************************!
   pure logical function burn_takes( ib, j ) result( takes )
   implicit none
   integer(kind=int32), intent(in) :: ib, j
   takes = .false.
   if ( ib < 1 .or. ib > nburn .or. j < 1 ) return
   takes = any( burn_key(1:burn_npar(ib),ib) == j )
   end function burn_takes

end module burn_table

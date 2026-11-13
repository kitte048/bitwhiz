program test_btab
!**********************************************************************!
!
!  Purpose:
!    Unit test for the burn models' table (module burn_table): that it
!    keeps the deck-key rules of doc/design/burn_models.md ("Deck
!    keys", approved 11/06/26) and fits the per-cell arrays. Run by
!    "make test"; the exit status is 0 if every check passes, 1 if any
!    check fails, so make (and any script) can tell.
!
!  What it checks, on the table alone (no deck, no hydro):
!    1. Names: every burn key and every model name is unique, in any
!       case (rule 1: one key, one meaning).
!    2. No burn key has the name of another Material key (rule 3): R0,
!       C0, S1, S2, G0, CV, T0, GAMMA, Q, eos, burn, products,
!       spall_strength, name.
!    3. Each model's row: npar between 1 and npar_max, its slots
!       1 to npar each a key (1 to nbkey), none twice, and 0 past the
!       last; nst between 1 and nst_max.
!    4. Every key is taken by some model (none left over), and has a
!       known check.
!    5. bkey_index finds every key in either case, and nothing else;
!       burn_takes agrees with the rows.
!    6. HVRB's row is the slot table's: PR, ZR, MR, XR, PI, TAU0 in
!       slots hv_PR to hv_TAU0, phi in bst(hv_phi), one history
!       variable.
!    7. A model that uses the lead shock (burn_uses_ls) has room for
!       the detector's ls_nst numbers first (module leadshock); HVRB
!       does not use it.
!    8. ThermalCascade's row is the slot table's: HT, TC, GT, NS, PR in
!       slots tc_HT to tc_PR, PR shared with HVRB (one key, one
!       meaning), the detector's five numbers its history, and its
!       checks (HT, TC, GT, NS >= 0, so HT = 0 is the inert limit).
!    9. FlashFire's row is the slot table's: KFF, AFF, BFF, TA, NS, PR,
!       LAM0 in slots ff_KFF to ff_LAM0, NS shared with ThermalCascade
!       and PR with both, the detector's five numbers its history, and
!       its checks (KFF, AFF, BFF, TA >= 0; LAM0 strictly between 0 and
!       1, the one key with chk_open01).
!   10. Each key's largest value (bkey_max): XR's 25 (the v1.4.0
!       review, F-03), every other key's none (huge).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/06/26    D. E. Kittell        Original code
!                (with Claude)
!    11/06/26    D. E. Kittell        7: burn_uses_ls (step 4)
!                (with Claude)
!    11/07/26    D. E. Kittell        8: ThermalCascade's row (step 5)
!                (with Claude)
!    11/12/26    D. E. Kittell        9: FlashFire's row (step 6); 4
!                (with Claude)        knows chk_open01
!    11/12/26    D. E. Kittell        10: bkey_max (F-03)
!                (with Claude)
!
!**********************************************************************!
use bits, only: int32, dp, quit
use burn_table, only: npar_max, nst_max, nburn, burn_none, burn_hvrb, &
   burn_names, burn_long, nbkey, bkey_name, bkey_check, bkey_note, bkey_max, &
   chk_any, chk_positive, chk_nonneg, chk_open01, burn_npar, burn_key, burn_nst, &
   bkey_index, burn_takes, hv_PR, hv_ZR, hv_MR, hv_XR, hv_PI, hv_TAU0, &
   hv_phi, burn_uses_ls, burn_tcas, tc_HT, tc_TC, tc_GT, tc_NS, tc_PR, &
   burn_ffire, ff_KFF, ff_AFF, ff_BFF, ff_TA, ff_NS, ff_PR, ff_LAM0
use leadshock, only: ls_nst
implicit none

!*** The Material block's other keys (module deck, key_material).
integer(kind=int32), parameter :: nother = 14
character(len=16), parameter, dimension(nother) :: other_keys = (/ &
   'R0              ', 'C0              ', 'S1              ', &
   'S2              ', 'G0              ', 'CV              ', &
   'T0              ', 'GAMMA           ', 'Q               ', &
   'EOS             ', 'BURN            ', 'PRODUCTS        ', &
   'SPALL_STRENGTH  ', 'NAME            ' /)
character(len=8), parameter, dimension(6) :: hvrb_keys = (/ &
   'PR      ', 'ZR      ', 'MR      ', 'XR      ', 'PI      ', &
   'TAU0    ' /)
character(len=8), parameter, dimension(5) :: tcas_keys = (/ &
   'HT      ', 'TC      ', 'GT      ', 'NS      ', 'PR      ' /)
character(len=8), parameter, dimension(7) :: ffire_keys = (/ &
   'KFF     ', 'AFF     ', 'BFF     ', 'TA      ', 'NS      ', &
   'PR      ', 'LAM0    ' /)
integer(kind=int32) :: ncheck, nfail, i, j, ib, s, n
logical :: ok

ncheck = 0
nfail  = 0
write(*,'(a)') ' test_btab: the burn models'' table (module burn_table)'

!*** 1. Unique names, in any case.
ok = .true.
do i = 1, nbkey
   if ( len_trim(bkey_name(i)) == 0 ) ok = .false.
   do j = i + 1, nbkey
      if ( upper(bkey_name(i)) == upper(bkey_name(j)) ) ok = .false.
   end do
end do
call check( ok, '1. every burn key''s name is unique' )
ok = burn_none == 0
do i = 1, nburn
   if ( len_trim(burn_names(i)) == 0 .or. len_trim(burn_long(i)) == 0 ) &
      ok = .false.
   do j = i + 1, nburn
      if ( upper(burn_names(i)) == upper(burn_names(j)) ) ok = .false.
   end do
end do
call check( ok, '1. every model''s name is unique (burn_none = 0)' )

!*** 2. No collisions with the Material block's other keys.
ok = .true.
do i = 1, nbkey
   do j = 1, nother
      if ( upper(bkey_name(i)) == trim(other_keys(j)) ) then
         ok = .false.
         write(*,'(a)') '         '//trim(bkey_name(i))// &
            ' is another Material key'
      end if
   end do
end do
call check( ok, '2. no burn key is another Material key (rule 3)' )

!*** 3. Each model's row fits the per-cell arrays.
ok = .true.
do ib = 1, nburn
   n = burn_npar(ib)
   if ( n < 1 .or. n > npar_max ) ok = .false.
   if ( burn_nst(ib) < 1 .or. burn_nst(ib) > nst_max ) ok = .false.
   do s = 1, npar_max
      j = burn_key(s,ib)
      if ( s <= n ) then
         if ( j < 1 .or. j > nbkey ) ok = .false.
         if ( j >= 1 ) then
            if ( count( burn_key(1:n,ib) == j ) /= 1 ) ok = .false.
         end if
      else if ( j /= 0 ) then
         ok = .false.
      end if
   end do
end do
call check( ok, '3. each row: keys in slots 1 to npar <= npar_max, '// &
   'none twice, nst <= nst_max' )

!*** 4. Every key has a model and a known check.
ok = .true.
do j = 1, nbkey
   if ( .not. any( (/ ( burn_takes( ib, j ), ib = 1, nburn ) /) ) ) &
      ok = .false.
   if ( bkey_check(j) /= chk_any .and. bkey_check(j) /= chk_positive &
      .and. bkey_check(j) /= chk_nonneg .and. bkey_check(j) /= chk_open01 ) &
      ok = .false.
   if ( len_trim(bkey_note(j)) == 0 ) ok = .false.
end do
call check( ok, '4. every key is some model''s, with a check and a note' )

!*** 5. The lookups.
ok = bkey_index('R0') == 0 .and. bkey_index('') == 0 .and. &
   bkey_index('P') == 0 .and. bkey_index('PRX') == 0
do j = 1, nbkey
   if ( bkey_index( trim(bkey_name(j)) ) /= j ) ok = .false.
   if ( bkey_index( lower(bkey_name(j)) ) /= j ) ok = .false.
end do
do ib = 1, nburn
   do j = 1, nbkey
      if ( burn_takes( ib, j ) .neqv. &
         any( burn_key(1:burn_npar(ib),ib) == j ) ) ok = .false.
   end do
end do
ok = ok .and. .not. burn_takes( burn_none, 1 ) .and. &
   .not. burn_takes( nburn + 1, 1 ) .and. .not. burn_takes( 1, 0 )
call check( ok, '5. bkey_index (either case) and burn_takes' )

!*** 6. HVRB, as the slot table has it.
ok = trim(burn_names(burn_hvrb)) == 'hvrb' .and. burn_npar(burn_hvrb) == 6 &
   .and. burn_nst(burn_hvrb) == 1 .and. hv_phi == 1
do s = 1, 6
   if ( trim(bkey_name( burn_key(s,burn_hvrb) )) /= trim(hvrb_keys(s)) ) &
      ok = .false.
end do
ok = ok .and. hv_PR == 1 .and. hv_ZR == 2 .and. hv_MR == 3 .and. &
   hv_XR == 4 .and. hv_PI == 5 .and. hv_TAU0 == 6
ok = ok .and. bkey_check( burn_key(hv_PR,burn_hvrb) ) == chk_positive &
   .and. bkey_check( burn_key(hv_ZR,burn_hvrb) ) == chk_nonneg &
   .and. bkey_check( burn_key(hv_MR,burn_hvrb) ) == chk_positive &
   .and. bkey_check( burn_key(hv_XR,burn_hvrb) ) == chk_positive &
   .and. bkey_check( burn_key(hv_PI,burn_hvrb) ) == chk_nonneg &
   .and. bkey_check( burn_key(hv_TAU0,burn_hvrb) ) == chk_positive
call check( ok, '6. HVRB: PR ZR MR XR PI TAU0 in slots 1-6, phi in '// &
   'bst(1), its checks' )

!*** 7. The lead shock's room.
ok = .not. burn_uses_ls(burn_hvrb) .and. ls_nst <= nst_max
do ib = 1, nburn
   if ( burn_uses_ls(ib) .and. burn_nst(ib) < ls_nst ) ok = .false.
end do
call check( ok, '7. a model using the lead shock has its ls_nst slots '// &
   'first; HVRB does not use it' )

!*** 8. ThermalCascade, as the slot table has it.
ok = trim(burn_names(burn_tcas)) == 'thermalcascade' .and. &
   burn_npar(burn_tcas) == 5 .and. burn_nst(burn_tcas) == ls_nst .and. &
   burn_uses_ls(burn_tcas)
do s = 1, 5
   if ( trim(bkey_name( burn_key(s,burn_tcas) )) /= trim(tcas_keys(s)) ) &
      ok = .false.
end do
ok = ok .and. tc_HT == 1 .and. tc_TC == 2 .and. tc_GT == 3 .and. &
   tc_NS == 4 .and. tc_PR == 5 .and. &
   burn_key(tc_PR,burn_tcas) == burn_key(hv_PR,burn_hvrb)
do s = 1, 4
   if ( bkey_check( burn_key(s,burn_tcas) ) /= chk_nonneg ) ok = .false.
end do
ok = ok .and. bkey_check( burn_key(tc_PR,burn_tcas) ) == chk_positive
call check( ok, '8. ThermalCascade: HT TC GT NS PR in slots 1-5 (PR '// &
   'HVRB''s), the detector its history, its checks' )

!*** 9. FlashFire, as the slot table has it.
ok = trim(burn_names(burn_ffire)) == 'flashfire' .and. &
   burn_npar(burn_ffire) == 7 .and. burn_nst(burn_ffire) == ls_nst .and. &
   burn_uses_ls(burn_ffire)
do s = 1, 7
   if ( trim(bkey_name( burn_key(s,burn_ffire) )) /= trim(ffire_keys(s)) ) &
      ok = .false.
end do
ok = ok .and. ff_KFF == 1 .and. ff_AFF == 2 .and. ff_BFF == 3 .and. &
   ff_TA == 4 .and. ff_NS == 5 .and. ff_PR == 6 .and. ff_LAM0 == 7 .and. &
   burn_key(ff_NS,burn_ffire) == burn_key(tc_NS,burn_tcas) .and. &
   burn_key(ff_PR,burn_ffire) == burn_key(hv_PR,burn_hvrb)
do s = 1, 4
   if ( bkey_check( burn_key(s,burn_ffire) ) /= chk_nonneg ) ok = .false.
end do
ok = ok .and. bkey_check( burn_key(ff_PR,burn_ffire) ) == chk_positive .and. &
   bkey_check( burn_key(ff_LAM0,burn_ffire) ) == chk_open01 .and. &
   count( bkey_check == chk_open01 ) == 1
call check( ok, '9. FlashFire: KFF AFF BFF TA NS PR LAM0 in slots 1-7 '// &
   '(NS and PR shared), the detector its history, its checks' )

!*** 10. The largest values: XR 25, the rest none.
ok = .true.
do j = 1, nbkey
   if ( trim(bkey_name(j)) == 'XR' ) then
      ok = ok .and. abs( bkey_max(j) - 25.0_dp ) <= 0.0_dp
   else
      ok = ok .and. bkey_max(j) >= huge(1.0_dp)
   end if
end do
call check( ok, '10. the largest values: XR at most 25 (F-03), no other '// &
   'key bounded above' )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_btab: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_btab: all ', ncheck, ' checks passed'

contains

   subroutine check( okk, what )
   implicit none
   logical, intent(in) :: okk
   character(len=*), intent(in) :: what
   ncheck = ncheck + 1
   if ( okk ) then
      write(*,'(a)') '   pass  '//what
   else
      write(*,'(a)') '   FAIL  '//what
      nfail = nfail + 1
   end if
   end subroutine check

   !*** Upper and lower case, trimmed (ASCII).
   function upper( text ) result( s )
   implicit none
   character(len=*), intent(in) :: text
   character(len=:), allocatable :: s
   integer(kind=int32) :: k
   s = trim(text)
   do k = 1, len(s)
      if ( s(k:k) >= 'a' .and. s(k:k) <= 'z' ) &
         s(k:k) = achar( iachar(s(k:k)) - 32 )
   end do
   end function upper

   function lower( text ) result( s )
   implicit none
   character(len=*), intent(in) :: text
   character(len=:), allocatable :: s
   integer(kind=int32) :: k
   s = trim(text)
   do k = 1, len(s)
      if ( s(k:k) >= 'A' .and. s(k:k) <= 'Z' ) &
         s(k:k) = achar( iachar(s(k:k)) + 32 )
   end do
   end function lower

end program test_btab

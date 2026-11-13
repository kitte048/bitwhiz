program test_halo
!**********************************************************************!
!
!  Purpose:
!    Unit test for HALO (module halo): its activation measure, its hot
!    spots and its burn. Run by "make test"; the exit status is 0 if
!    every check passes, 1 if any check fails, so make (and any script)
!    can tell.
!
!  Where the expected values come from:
!    NOT from module halo. tests/halo_reference.py computes them at 50
!    digits (mpmath) from the model's definition (doc/design/
!    burn_models.md, "HALO" and "Step 8"): the measure's integral along a
!    Rayleigh line and the scheme's sum over N steps; Erf((E_D/ED0)^BETAH);
!    dissipation alone, an exponential; the burn at fixed eta and P,
!    lam = 1 - exp(-(K t)^d) (KJMA). The rest is by construction: no
!    compression, no measure; no new compression (ringing about a volume
!    already passed), no measure; TAUD = 1e30, no decay; KB = 0, no burn;
!    eta never above Erf.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/13/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one, quit
use halo, only: ha_ed_step, ha_act, ha_eta_step, ha_s_step, ha_lam, ha_step
implicit none
type :: ed_t
   real(kind=dp) :: va, Pa, vb, Pb
   integer(kind=int32) :: n
   real(kind=dp) :: total, integral
end type ed_t
type :: act_t
   real(kind=dp) :: ed, ED0, BETAH, a
end type act_t
type :: dis_t
   real(kind=dp) :: eta0, lam, DELTA, TAUD, t, eta
end type dis_t
type :: brn_t
   real(kind=dp) :: eta, P, KB, DFRAC, NH, PR, t, lam
end type brn_t
type(ed_t), parameter, dimension(5) :: eds = (/ &
   ed_t( 6.2500000000000000000e-1_dp, 0.0_dp, &
      4.6360000000000000000e-1_dp, 1.1000000000000000000e1_dp, 1, &
      3.7851655181775076505e-1_dp, 3.5686882744224102376e-1_dp ), &
   ed_t( 6.2500000000000000000e-1_dp, 0.0_dp, &
      4.6360000000000000000e-1_dp, 1.1000000000000000000e1_dp, 10, &
      3.5778803650692084101e-1_dp, 3.5686882744224102376e-1_dp ), &
   ed_t( 6.2500000000000000000e-1_dp, 0.0_dp, &
      4.6360000000000000000e-1_dp, 1.1000000000000000000e1_dp, 1000, &
      3.5686984699632425240e-1_dp, 3.5686882744224102376e-1_dp ), &
   ed_t( 5.5000000000000000000e-1_dp, 4.0000000000000000000_dp, &
      4.7000000000000000000e-1_dp, 1.1000000000000000000e1_dp, 1, &
      2.1908902300206644538e-1_dp, 2.1701236338216684450e-1_dp ), &
   ed_t( 5.5000000000000000000e-1_dp, 4.0000000000000000000_dp, &
      4.7000000000000000000e-1_dp, 1.1000000000000000000e1_dp, 50, &
      2.1701328960503597529e-1_dp, 2.1701236338216684450e-1_dp ) /)
type(act_t), parameter, dimension(6) :: acts = (/ &
   act_t( 3.9000000000000000000e-1_dp, 4.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 7.9875327850624909304e-1_dp ), &
   act_t( 3.3000000000000000000e-1_dp, 4.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 4.8761915106990918546e-1_dp ), &
   act_t( 1.0000000000000000000e-1_dp, 4.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 4.4077087026896622133e-3_dp ), &
   act_t( 8.0000000000000000000e-1_dp, 4.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 1.0000000000000000000_dp ), &
   act_t( 2.5000000000000000000e-1_dp, 3.0000000000000000000e-1_dp, &
      1.0000000000000000000_dp, 7.6140717068356453810e-1_dp ), &
   act_t( 2.5000000000000000000e-1_dp, 3.0000000000000000000e-1_dp, &
      2.5000000000000000000_dp, 6.3002699061990634247e-1_dp ) /)
type(dis_t), parameter, dimension(4) :: diss = (/ &
   dis_t( 8.0000000000000000000e-1_dp, 0.0_dp, &
      2.0000000000000000000_dp, 2.5000000000000000000e-1_dp, &
      1.0000000000000000000_dp, 1.4652511110987344235e-2_dp ), &
   dis_t( 8.0000000000000000000e-1_dp, 3.0000000000000000000e-1_dp, &
      2.0000000000000000000_dp, 2.5000000000000000000e-1_dp, &
      1.0000000000000000000_dp, 1.1268673673683599692e-1_dp ), &
   dis_t( 5.0000000000000000000e-1_dp, 6.0000000000000000000e-1_dp, &
      0.0_dp, 1.0000000000000000000e-1_dp, 3.0000000000000000000e-1_dp, &
      2.4893534183931971490e-2_dp ), &
   dis_t( 1.0000000000000000000_dp, 9.0000000000000000000e-1_dp, &
      5.0000000000000000000e-1_dp, 2.0000000000000000000_dp, &
      3.0000000000000000000_dp, 6.2229460989828039468e-1_dp ) /)
type(brn_t), parameter, dimension(5) :: brns = (/ &
   brn_t( 8.4000000000000000000e-1_dp, 1.1000000000000000000e1_dp, &
      5.0000000000000000000e-1_dp, 3.0000000000000000000_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, &
      4.0000000000000000000e-1_dp, 9.6238602897370192266e-2_dp ), &
   brn_t( 8.4000000000000000000e-1_dp, 1.1000000000000000000e1_dp, &
      5.0000000000000000000e-1_dp, 2.3000000000000000000_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, &
      4.0000000000000000000e-1_dp, 1.5279052311799019534e-1_dp ), &
   brn_t( 3.0000000000000000000e-1_dp, 1.1000000000000000000e1_dp, &
      2.0000000000000000000_dp, 2.0000000000000000000_dp, &
      1.0000000000000000000_dp, 7.0000000000000000000_dp, &
      2.5000000000000000000e-1_dp, 1.6906531196074401608e-1_dp ), &
   brn_t( 1.0000000000000000000_dp, -2.0000000000000000000_dp, &
      1.0000000000000000000_dp, 2.0000000000000000000_dp, 0.0_dp, &
      7.0000000000000000000_dp, 5.0000000000000000000e-1_dp, &
      2.2119921692859513175e-1_dp ), &
   brn_t( 5.0000000000000000000e-1_dp, 5.0000000000000000000_dp, &
      1.0000000000000000000_dp, 3.0000000000000000000_dp, &
      2.0000000000000000000_dp, 7.0000000000000000000_dp, &
      5.0000000000000000000e-2_dp, 8.3006098391167359186e-6_dp ) /)
integer(kind=int32) :: ncheck = 0, nfail = 0, i, k
real(kind=dp) :: worst, ed, ed2, eta, eta2, s, s2, lam, lam2, v1, v2, &
   de, dv, dt, x, a, vm, vm2, v, ed3
logical :: ok

write(*,'(a)') ' test_halo: HALO (module halo)'

!*** 1. The measure along a Rayleigh line, in N steps: the scheme's sum,
!***    against 50 digits; and its approach to the integral (one step
!***    from rest: 3/(2 sqrt 2) of it).
worst = zero
do i = 1, size(eds)
   ed = zero; vm = zero
   do k = 0, eds(i)%n - 1
      v1 = eds(i)%va + ( eds(i)%vb - eds(i)%va )*real( k, dp )/ &
         real( eds(i)%n, dp )
      v2 = eds(i)%va + ( eds(i)%vb - eds(i)%va )*real( k + 1, dp )/ &
         real( eds(i)%n, dp )
      de = half*( pr( i, v1 ) + pr( i, v2 ) )*( v1 - v2 )
      call ha_ed_step( ed, vm, de, v2, v2 - v1, ed2, vm2 )
      ed = ed2; vm = vm2
   end do
   worst = max( worst, abs( ed/eds(i)%total - one ) )
   write(*,'(a,i5,a,f10.7)') '         N = ', eds(i)%n, &
      ': the sum over the integral ', ed/eds(i)%integral
end do
call check( worst < 1.0e-13_dp, '1. the measure along a Rayleigh line, '// &
   '1 to 1000 steps, against 50 digits, to '//rtoa(worst) )

!*** 2. No compression, no measure: expansion, or energy falling.
call ha_ed_step( 0.3_dp, 0.5_dp, 0.1_dp, 0.51_dp, 0.01_dp, ed, vm )
ok = same( ed, 0.3_dp ) .and. same( vm, 0.5_dp )
call ha_ed_step( 0.3_dp, 0.5_dp, -0.1_dp, 0.49_dp, -0.01_dp, ed, vm )
ok = ok .and. same( ed, 0.3_dp ) .and. same( vm, 0.49_dp )
call ha_ed_step( 0.3_dp, 0.5_dp, zero, 0.49_dp, -0.01_dp, ed, vm )
ok = ok .and. same( ed, 0.3_dp )
call ha_ed_step( zero, zero, zero, 0.625_dp, zero, ed, vm )   ! cycle 1
ok = ok .and. same( ed, zero ) .and. same( vm, 0.625_dp ) .and. &
   same( ha_act( zero, 0.4_dp, 4.0_dp ), zero )
call check( ok, '2. no compression, no measure: v rising or e falling '// &
   'adds nothing; v_min not yet set (0) starts at v; Erf(0) = 0' )

!*** 3. New compression only (DK, 11/13/26): a shock to v = 0.46, then
!***    ringing about it (v between 0.455 and 0.465, e rising and
!***    falling) adds only the part below 0.46 once; a second compression
!***    to 0.43 counts in full, as the same path counted step by step.
ed = zero; vm = zero
v1 = 0.625_dp
do k = 1, 40                                  ! the first shock, 40 steps
   v2 = v1 - ( 0.625_dp - 0.46_dp )/40.0_dp
   call ha_ed_step( ed, vm, 8.0e-3_dp, v2, v2 - v1, ed2, vm2 )
   ed = ed2; vm = vm2; v1 = v2
end do
ed3 = ed
do k = 1, 400                                 ! ringing, 400 steps
   v2 = 0.46_dp + 5.0e-3_dp*sin( 0.7_dp*real( k, dp ) )
   call ha_ed_step( ed, vm, 2.0e-3_dp*cos( 0.7_dp*real( k, dp ) ), v2, &
      v2 - v1, ed2, vm2 )
   ed = ed2; vm = vm2; v1 = v2
end do
x  = ed - ed3                                 ! what the ringing added
ok = vm >= 0.455_dp - 1.0e-15_dp .and. x < 0.01_dp*ed3
ed3 = ed
v = vm
do k = 1, 20                                  ! a second compression
   v2 = v - ( v - 0.43_dp )*real( k, dp )/20.0_dp
   v1 = v - ( v - 0.43_dp )*real( k - 1, dp )/20.0_dp
   call ha_ed_step( ed, vm, 5.0e-3_dp, v2, v2 - v1, ed2, vm2 )
   ed = ed2; vm = vm2
end do
a = 20.0_dp*sqrt( 5.0e-3_dp*( v - 0.43_dp )/20.0_dp )   ! counted in full
ok = ok .and. abs( ( ed - ed3 )/a - one ) < 1.0e-13_dp
write(*,'(a,3f10.6)') '         first shock, ringing''s share, second: ', &
   ed3 - x, x, ed - ed3
call check( ok, '3. new compression only: 400 steps of ringing add '// &
   'under 1 % (its first dip below v_min); a second compression counts '// &
   'in full, to 1e-13' )

!*** 4. The activated fraction, Erf((E_D/ED0)**BETAH).
worst = zero
do i = 1, size(acts)
   worst = max( worst, abs( ha_act( acts(i)%ed, acts(i)%ED0, acts(i)%BETAH ) &
      - acts(i)%a ) )
end do
!*** ... and no overflow (the NOTE): Erf 1 and lam 1 where they are 1 in
!*** double, whatever BETAH or DFRAC.
ok = same( ha_act( 11.0_dp, one, 400.0_dp ), one ) .and. &
   same( ha_act( one, 1.0e-200_dp, 4.0_dp ), one ) .and. &
   same( ha_lam( 1.0e200_dp, 2.3_dp ), one ) .and. &
   same( ha_act( 6.0_dp**0.25_dp*0.999_dp, one, 4.0_dp ), &
   erf( ( 6.0_dp**0.25_dp*0.999_dp )**4 ) )
call check( worst < 4.0e-16_dp .and. ok, '4. Erf((E_D/ED0)**BETAH), 6 '// &
   'points, to '//rtoa(worst)//'; 1 where it is 1, with no overflow' )

!*** 5. Dissipation alone, at a fixed lam, 1000 steps: the exponential.
worst = zero
do i = 1, size(diss)
   eta = diss(i)%eta0
   dt  = diss(i)%t/1000.0_dp
   do k = 1, 1000
      eta = ha_eta_step( eta, diss(i)%lam, 0.2_dp, 0.2_dp, dt, 0.4_dp, &
         4.0_dp, diss(i)%TAUD, diss(i)%DELTA )
   end do
   worst = max( worst, abs( eta/diss(i)%eta - one ) )
end do
!*** ... and at lam = 1: no decay with DELTA > 0, (1 - lam)**0 = 1 with
!*** DELTA = 0 (never 0**0).
ok = same( ha_eta_step( 0.5_dp, one, 0.2_dp, 0.2_dp, 0.1_dp, 0.4_dp, &
   4.0_dp, 0.25_dp, 2.0_dp ), 0.5_dp ) .and. &
   abs( ha_eta_step( 0.5_dp, one, 0.2_dp, 0.2_dp, 0.1_dp, 0.4_dp, 4.0_dp, &
   0.25_dp, zero )/( 0.5_dp*exp( -0.4_dp ) ) - one ) < 1.0e-15_dp
call check( worst < 1.0e-12_dp .and. ok, '5. dissipation alone: eta0 '// &
   'exp(-(1-lam)**DELTA t/TAUD), DELTA 0 to 2, 1000 steps, to '// &
   rtoa(worst)//'; at lam = 1, DELTA 2 and 0' )

!*** 6. Activation alone (TAUD = 1e30): eta = Erf((E_D/ED0)**BETAH) at the
!***    end, whatever the path (the increments telescope); and no decay
!***    at all, bit for bit, once the compression stops.
ed = zero; eta = zero; vm = zero; v = 0.625_dp
do k = 1, 500
   x   = real( k, dp )
   dv  = -2.0e-4_dp*( one + 0.3_dp*cos( 3.0_dp*x ) )
   v   = v + dv
   call ha_ed_step( ed, vm, 1.0e-3_dp*( one + 0.5_dp*sin( x ) ), v, dv, &
      ed2, vm2 )
   vm  = vm2
   eta = ha_eta_step( eta, 0.1_dp, ed, ed2, 1.0e-3_dp, 0.4_dp, 4.0_dp, &
      1.0e30_dp, 2.0_dp )
   ed  = ed2
end do
worst = abs( eta - ha_act( ed, 0.4_dp, 4.0_dp ) )
eta2 = eta
ok = .true.
do k = 1, 10000
   eta2 = ha_eta_step( eta2, 0.1_dp, ed, ed, 1.0e-3_dp, 0.4_dp, 4.0_dp, &
      1.0e30_dp, 2.0_dp )
   if ( .not. same( eta2, eta ) ) ok = .false.
end do
call check( worst < 4.0e-15_dp .and. ok, '6. activation alone: eta = '// &
   'Erf((E_D/ED0)**BETAH), 500 steps, to '//rtoa(worst)//'; TAUD = 1e30 '// &
   'then holds eta bit for bit, 10000 steps' )

!*** 7. eta never above Erf((E_D/ED0)**BETAH): a shock, a long dissipation,
!***    a second shock; eta stays in [0, Erf] at every step.
ed = zero; eta = zero; lam = zero; ok = .true.; vm = zero; v = 0.625_dp
do k = 1, 3000
   de = zero; dv = zero
   if ( k <= 20 .or. ( k > 1500 .and. k <= 1530 ) ) then
      de = 2.0e-2_dp; dv = -4.0e-3_dp
   end if
   v = v + dv
   call ha_ed_step( ed, vm, de, v, dv, ed2, vm2 )
   vm = vm2
   eta = ha_eta_step( eta, lam, ed, ed2, 1.0e-3_dp, 0.4_dp, 4.0_dp, &
      0.25_dp, 2.0_dp )
   ed  = ed2
   if ( eta < zero .or. eta > ha_act( ed, 0.4_dp, 4.0_dp ) + 1.0e-15_dp ) &
      ok = .false.
end do
write(*,'(a,2f10.6)') '         E_D and eta after two shocks: ', ed, eta
call check( ok, '7. 0 <= eta <= Erf((E_D/ED0)**BETAH) through two shocks '// &
   'and a dissipation, 3000 steps' )

!*** 8. The burn at fixed eta and P, 1000 steps: lam = 1 - exp(-(K t)**d).
worst = zero
do i = 1, size(brns)
   s  = zero
   dt = brns(i)%t/1000.0_dp
   do k = 1, 1000
      s = ha_s_step( s, brns(i)%eta, brns(i)%P, dt, brns(i)%KB, &
         brns(i)%DFRAC, brns(i)%NH, brns(i)%PR )
   end do
   lam = ha_lam( s, brns(i)%DFRAC )
   worst = max( worst, abs( lam/brns(i)%lam - one ) )
end do
call check( worst < 1.0e-12_dp, '8. the burn at fixed eta and P: KJMA, '// &
   'd = 2, 2.3 and 3, NH = 0 at P < 0, to '//rtoa(worst) )

!*** 9. The inert limit and the pressure's floor: KB = 0, lam exactly 0
!***    through a shock; P <= 0 with NH > 0, no burn.
ed = zero; eta = zero; s = zero; lam = zero; ok = .true.; vm = zero
v = 0.625_dp
do k = 1, 200
   v = v - 4.0e-4_dp
   call ha_step( ed, eta, s, vm, lam, 2.0e-2_dp, v, -4.0e-4_dp, 11.0_dp, &
      1.0e-3_dp, 0.4_dp, 4.0_dp, 0.25_dp, 2.0_dp, 2.3_dp, 2.0_dp, zero, &
      7.0_dp, ed2, eta2, s2, vm2, lam2 )
   ed = ed2; eta = eta2; s = s2; lam = lam2; vm = vm2
   if ( .not. ( same( lam, zero ) .and. same( s, zero ) ) ) ok = .false.
end do
ok = ok .and. eta > zero .and. &
   ha_s_step( zero, 0.9_dp, -1.0_dp, 1.0e-3_dp, one, 2.3_dp, 2.0_dp, &
   7.0_dp ) <= zero .and. &
   ha_s_step( zero, 0.9_dp, zero, 1.0e-3_dp, one, 2.3_dp, 2.0_dp, &
   7.0_dp ) <= zero
call check( ok, '9. KB = 0: hot spots but lam = 0 exactly, 200 steps; '// &
   'P <= 0 with NH > 0 does not burn' )

!*** 10. The order (DK): one ha_step is E_D, then eta at lam1, then s at
!***    the new eta and P^n, then lam: the same bits as the four calls.
ed = 0.31_dp; eta = 0.2_dp; s = 0.4_dp; lam = ha_lam( s, 2.3_dp )
call ha_step( ed, eta, s, 0.5_dp, lam, 1.5e-2_dp, 0.497_dp, -3.0e-3_dp, &
   9.0_dp, 2.0e-3_dp, 0.4_dp, 4.0_dp, 0.25_dp, 2.0_dp, 2.3_dp, 2.0_dp, &
   1.3_dp, 7.0_dp, ed2, eta2, s2, vm2, lam2 )
call ha_ed_step( ed, 0.5_dp, 1.5e-2_dp, 0.497_dp, -3.0e-3_dp, x, vm )
a = ha_eta_step( eta, lam, ed, x, 2.0e-3_dp, 0.4_dp, 4.0_dp, 0.25_dp, 2.0_dp )
v1 = ha_s_step( s, a, 9.0_dp, 2.0e-3_dp, 1.3_dp, 2.3_dp, 2.0_dp, 7.0_dp )
ok = same( ed2, x ) .and. same( vm2, vm ) .and. same( eta2, a ) .and. &
   same( s2, v1 ) .and. same( lam2, ha_lam( v1, 2.3_dp ) ) .and. &
   lam2 > lam .and. .not. same( eta2, eta ) .and. ed2 > ed
call check( ok, '10. one step in DK''s order: E_D and v_min, then eta, '// &
   'then s, then lam, bit for bit' )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_halo: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_halo: all ', ncheck, ' checks passed'

contains

   !*** P on path i's Rayleigh line at v (linear in v).
   pure function pr( i, v ) result( p )
   integer(kind=int32), intent(in) :: i
   real(kind=dp), intent(in) :: v
   real(kind=dp) :: p
   p = eds(i)%Pa + ( eds(i)%Pb - eds(i)%Pa )*( eds(i)%va - v )/ &
      ( eds(i)%va - eds(i)%vb )
   end function pr

   !*** Equal to the last bit (no -Wcompare-reals warning).
   pure logical function same( p, q )
   real(kind=dp), intent(in) :: p, q
   same = abs( p - q ) <= zero
   end function same

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

   function rtoa( r ) result(s)
   implicit none
   real(kind=dp), intent(in) :: r
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(es8.1)' ) r
   s = trim(adjustl(buf))
   end function rtoa

end program test_halo

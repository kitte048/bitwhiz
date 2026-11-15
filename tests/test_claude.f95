program test_claude
!**********************************************************************!
!
!  Purpose:
!    Unit test for CLAUDE (module claude): its entropy, its lighting,
!    its moments with births through the step and the quench, and lam.
!    Run by "make test"; the exit status is 0 if every check passes, 1
!    if any check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from module claude. tests/claude_reference.py computes them at
!    50 digits (mpmath) from the model's definition (doc/design/
!    burn_models.md, "CLAUDE" and "Step 9"): Avrami's extended volume by
!    direct quadrature over a history of lighting, growth and quenching;
!    every center lit at once against Hill and Zimmermann's closed form;
!    the entropy by integrating de/T at fixed volume; n(w2) - n(w1); J_k.
!    The rest is by construction: TQ = 1e30, the unquenched step bit for
!    bit; D0 = 0, lam = 0 exactly; the running maximum.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/14/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, one, quit
use claude, only: cl_entropy, cl_dn, cl_moments, cl_lam, cl_growth, cl_jk, &
   cl_step
implicit none
type :: his_t
   real(kind=dp) :: q, lam
end type his_t
type :: all_t
   real(kind=dp) :: n, g, t, lam
end type all_t
type :: ent_t
   real(kind=dp) :: e, ec, eta, cv, T0, G0, s
end type ent_t
type :: dn_t
   real(kind=dp) :: w1, w2, NMAX, W0, KW, dn
end type dn_t
type :: jk_t
   real(kind=dp) :: dt, q, j0, j1, j2, j3, j4
end type jk_t
type(his_t), parameter, dimension(2) :: hiss = (/ &
   his_t( 0.0_dp, 5.0206691548706007224e-1_dp ), &
   his_t( 4.0000000000000000000_dp, 2.2772082767537770578e-1_dp ) /)
type(all_t), parameter, dimension(3) :: alls = (/ &
   all_t( 1.0000000000000000000e3_dp, 3.0000000000000000000e-1_dp, &
      4.0000000000000000000e-2_dp, 7.2120965808851082427e-3_dp ), &
   all_t( 1.2500000000000000000e2_dp, 5.0000000000000000000e-1_dp, &
      3.0000000000000000000e-1_dp, 8.2918016384707000305e-1_dp ), &
   all_t( 8.0000000000000000000_dp, 1.0000000000000000000_dp, &
      1.0000000000000000000_dp, 9.9999999999999720326e-1_dp ) /)
type(ent_t), parameter, dimension(4) :: ents = (/ &
   ent_t( 9.7000000000000000000e-1_dp, 3.3000000000000000000e-1_dp, &
      2.5930000000000000000e-1_dp, 1.1633418000000000000e-3_dp, &
      2.9800000000000000000e2_dp, 1.2000000000000000000_dp, &
      9.9518941476528168944e-1_dp ), &
   ent_t( 2.5000000000000000000e-1_dp, 5.0000000000000000000e-2_dp, &
      1.0000000000000000000e-1_dp, 1.1633418000000000000e-3_dp, &
      2.9800000000000000000e2_dp, 1.2000000000000000000_dp, &
      4.8071128500532577200e-1_dp ), &
   ent_t( 5.0000000000000000000e-2_dp, 0.0_dp, 0.0_dp, &
      9.0000000000000000000e-4_dp, 3.0000000000000000000e2_dp, &
      2.0000000000000000000_dp, 1.5290913311585772561e-1_dp ), &
   ent_t( 1.5000000000000000000_dp, 8.0000000000000000000e-1_dp, &
      3.2000000000000000000e-1_dp, 1.1633418000000000000e-3_dp, &
      2.9800000000000000000e2_dp, 1.2000000000000000000_dp, &
      1.0064468970637449821_dp ) /)
type(dn_t), parameter, dimension(6) :: dns = (/ &
   dn_t( 0.0_dp, 6.6000000000000000000e-1_dp, &
      1.0000000000000000000e3_dp, 6.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 7.6871394471567147203e2_dp ), &
   dn_t( 3.0000000000000000000e-1_dp, 3.1000000000000000000e-1_dp, &
      1.0000000000000000000e3_dp, 6.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 8.1927013579209340319_dp ), &
   dn_t( 6.0000000000000000000e-1_dp, 6.0000010000000000000e-1_dp, &
      1.0000000000000000000e3_dp, 6.0000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 2.4525294048639405899e-4_dp ), &
   dn_t( 1.0000000000000000000e-1_dp, 2.0000000000000000000_dp, &
      5.0000000000000000000e1_dp, 5.0000000000000000000e-1_dp, &
      1.0000000000000000000_dp, 4.0020755709462383464e1_dp ), &
   dn_t( 1.0000000000000000000e-16_dp, 6.6000000000000000000e-1_dp, &
      1.0000000000000000000e3_dp, 6.6000000000000000000e-1_dp, &
      3.0000000000000000000e1_dp, 6.3212055882855767840e2_dp ), &
   dn_t( 2.0000000000000000000e-16_dp, 6.6000000000000000000e-1_dp, &
      1.0000000000000000000e3_dp, 6.6000000000000000000e-1_dp, &
      4.0000000000000000000_dp, 6.3212055882855767840e2_dp ) /)
type(jk_t), parameter, dimension(8) :: jks = (/ &
   jk_t( 5.0000000000000000000e-2_dp, 4.0000000000000000000_dp, &
      4.5317311730504535333e-2_dp, 1.0951935191513605998e-3_dp, &
      3.5890038901941638209e-5_dp, 1.3321931427692955731e-6_dp, &
      5.2926341084948918924e-8_dp ), &
   jk_t( 5.0000000000000000000e-2_dp, 1.0000000000000000000e-6_dp, &
      4.9999998750000020833e-2_dp, 1.2499999583333341146e-3_dp, &
      4.1666665104166697917e-5_dp, 1.5624999375000013021e-6_dp, &
      6.2499997395833389137e-8_dp ), &
   jk_t( 3.0000000000000000000e-1_dp, 4.0000000000000000000e1_dp, &
      2.4999846394691166795e-2_dp, 6.2495007827462920830e-4_dp, &
      3.1233679435936471943e-5_dp, 2.3383786143567388541e-6_dp, &
      2.3259365843412492294e-7_dp ), &
   jk_t( 2.0000000000000000000_dp, 6.0000000000000000000e-1_dp, &
      1.1646763134796631723_dp, 9.3714648275876496495e-1_dp, &
      1.1158601964478692389_dp, 1.5633781567433182390_dp, &
      2.3906753939633990163_dp ), &
   jk_t( 1.0000000000000000000_dp, 1.0000000000000000000_dp, &
      6.3212055882855767840e-1_dp, 2.6424111765711535681e-1_dp, &
      1.6060279414278839202e-1_dp, 1.1392894125692285447e-1_dp, &
      8.7836323856249096291e-2_dp ), &
   jk_t( 1.0000000000000000000_dp, 1.9990000000000000000_dp, &
      4.3248089734364560104e-1_dp, 1.4857939526442879315e-1_dp, &
      8.0884494406605874322e-2_dp, 5.3618207608686933184e-2_dp, &
      3.9520832528611950579e-2_dp ), &
   jk_t( 1.0000000000000000000_dp, 2.0010000000000000000_dp, &
      4.3218390025064095212e-1_dp, 1.4841773345935707012e-1_dp, &
      8.0777336991627528948e-2_dp, 5.3539228074170480776e-2_dp, &
      3.9458718989612427932e-2_dp ), &
   jk_t( 5.0000000000000000000e-1_dp, 6.0000000000000000000_dp, &
      1.5836882193868934284e-1_dp, 2.2245881292459561891e-2_dp, &
      5.3408325821588563396e-3_dp, 1.6331857000822626911e-3_dp, &
      5.7017517122292572134e-4_dp ) /)
!*** The history of claude_reference.py, section 1: 8 steps of 0.05 us.
real(kind=dp), parameter :: dt_h = 0.05_dp
real(kind=dp), parameter, dimension(8) :: dn_h = (/ 20.0_dp, zero, &
   50.0_dp, 10.0_dp, zero, zero, 30.0_dp, 5.0_dp /)
real(kind=dp), parameter, dimension(8) :: g_h = (/ 0.1_dp, 0.3_dp, 0.2_dp, &
   zero, 0.5_dp, 0.4_dp, 0.4_dp, one /)
integer(kind=int32) :: ncheck = 0, nfail = 0, i, k
real(kind=dp) :: worst, m(0:3), m2(0:3), vq, vq2, lam, w, w2, x, jk(0:4), &
   ma(0:3), vqa, mb(0:3), vqb, t
logical :: ok

write(*,'(a)') ' test_claude: CLAUDE (module claude)'

!*** 1. A history of lighting and growth, 8 steps, against Avrami's
!***    extended volume by quadrature: no quench (TQ = 1e30), and TQ =
!***    0.25 us.
worst = zero
do i = 1, size(hiss)
   m = zero; vq = zero
   t = 1.0e30_dp                            ! TQ: none at q = 0
   if ( hiss(i)%q > zero ) t = one/hiss(i)%q
   do k = 1, 8
      call cl_moments( m, vq, dn_h(k), g_h(k)*dt_h, dt_h, t, m2, vq2 )
      m = m2; vq = vq2
   end do
   lam = cl_lam( m(3), vq )
   worst = max( worst, abs( lam/hiss(i)%lam - one ) )
   write(*,'(a,f6.2,a,f14.10,a,f14.10)') '         q = ', hiss(i)%q, &
      ': lam ', lam, ', extended volume ', hiss(i)%lam
end do
call check( worst < 1.0e-13_dp, '1. a history of lighting, growth and '// &
   'quench, 8 steps, against the extended volume by quadrature, to '// &
   rtoa(worst) )

!*** 2. Every center lit at once, G constant, 100 steps: Hill and
!***    Zimmermann's 1 - exp(-(pi/6) that**3).
worst = zero
do i = 1, size(alls)
   m = (/ alls(i)%n, zero, zero, zero /); vq = zero
   do k = 1, 100
      call cl_moments( m, vq, zero, alls(i)%g*alls(i)%t/100.0_dp, &
         alls(i)%t/100.0_dp, 1.0e30_dp, m2, vq2 )
      m = m2; vq = vq2
   end do
   worst = max( worst, abs( cl_lam( m(3), vq )/alls(i)%lam - one ) )
end do
call check( worst < 1.0e-13_dp, '2. every center lit at once: 1 - '// &
   'exp(-(pi/6) that**3), 100 steps, to '//rtoa(worst) )

!*** 3. TQ = 1e30 is the unquenched step bit for bit; and a quench as
!***    TQ grows tends to it.
m = (/ 30.0_dp, 2.0_dp, 0.3_dp, 0.05_dp /)
call cl_moments( m, zero, 12.0_dp, 0.02_dp, 0.05_dp, 1.0e30_dp, ma, vqa )
ok = all( abs( ma - (/ m(0) + 12.0_dp, m(1) + 0.02_dp*m(0) + 6.0_dp*0.02_dp, &
   m(2) + 0.04_dp*m(1) + 4.0e-4_dp*m(0) + 4.0_dp*4.0e-4_dp, &
   m(3) + 0.06_dp*m(2) + 1.2e-3_dp*m(1) + 8.0e-6_dp*m(0) + &
   3.0_dp*8.0e-6_dp /) ) <= 1.0e-15_dp*abs( ma ) ) .and. vqa <= zero
call cl_moments( m, zero, 12.0_dp, 0.02_dp, 0.05_dp, 1.0e8_dp, mb, vqb )
ok = ok .and. all( abs( mb/ma - one ) < 1.0e-8_dp ) .and. vqb < 1.0e-8_dp
call check( ok, '3. TQ = 1e30: no quench, new centers adding dn '// &
   'DR**j/(j+1); TQ = 1e8 within 1e-8 of it' )

!*** 4. J_k, by the series (q dt < 1) and the recursion, to 50 digits.
worst = zero
do i = 1, size(jks)
   jk = cl_jk( jks(i)%dt, jks(i)%q )
   worst = max( worst, maxval( abs( jk/(/ jks(i)%j0, jks(i)%j1, &
      jks(i)%j2, jks(i)%j3, jks(i)%j4 /) - one ) ) )
end do
call check( worst < 2.0e-15_dp, '4. J_0 to J_4, q dt from 5e-8 to 12, '// &
   'about the switch at 2 too, to '//rtoa(worst) )

!*** 5. The entropy, against de/T integrated at fixed volume.
worst = zero
do i = 1, size(ents)
   x = cl_entropy( ents(i)%e, ents(i)%ec, ents(i)%eta, ents(i)%cv, &
      ents(i)%T0, ents(i)%G0 )
   worst = max( worst, abs( x/ents(i)%s - one ) )
end do
ok = cl_entropy( 0.3_dp, 0.3_dp, 0.2_dp, 1.0e-3_dp, 298.0_dp, 1.2_dp ) <= &
   zero .and. cl_entropy( -2.0_dp, 0.3_dp, 0.2_dp, 1.0e-3_dp, 298.0_dp, &
   1.2_dp ) <= zero
call check( worst < 1.0e-14_dp .and. ok, '5. the entropy against de/T at '// &
   'fixed volume, 4 states, to '//rtoa(worst)//'; 0 on the isentrope, 0 '// &
   'where T would not be positive' )

!*** 6. Centers lit, n(w2) - n(w1), to 50 digits; none unless w rises.
worst = zero
do i = 1, size(dns)
   x = cl_dn( dns(i)%w1, dns(i)%w2, dns(i)%NMAX, dns(i)%W0, dns(i)%KW )
   worst = max( worst, abs( x/dns(i)%dn - one ) )
end do
ok = cl_dn( 0.5_dp, 0.5_dp, 1000.0_dp, 0.6_dp, 4.0_dp ) <= zero .and. &
   cl_dn( 0.5_dp, 0.4_dp, 1000.0_dp, 0.6_dp, 4.0_dp ) <= zero
call check( worst < 1.0e-13_dp .and. ok, '6. centers lit, n(w2) - n(w1), '// &
   'a rise of 1e-7, and from 1e-16 at KW = 30 (no overflow), to '// &
   rtoa(worst)//'; none unless w rises' )

!*** 7. One step's order (w, then dn, then the moments at P^n and rho,
!***    then lam), bit for bit; w a running maximum.
m = (/ 5.0_dp, 0.1_dp, 0.02_dp, 0.004_dp /); vq = 1.0e-3_dp; w = 0.4_dp
call cl_step( w, m, vq, 0.5_dp, 9.0_dp, 2.1_dp, 2.0e-3_dp, 1.6_dp, &
   1000.0_dp, 0.6_dp, 4.0_dp, 0.3_dp, 1.0_dp, 7.0_dp, 0.25_dp, w2, m2, &
   vq2, lam )
x = cl_dn( 0.4_dp, 0.5_dp, 1000.0_dp, 0.6_dp, 4.0_dp )
call cl_moments( m, vq, x, cl_growth( 9.0_dp, 2.1_dp, 1.6_dp, 0.3_dp, &
   1.0_dp, 7.0_dp )*2.0e-3_dp, 2.0e-3_dp, 0.25_dp, ma, vqa )
ok = abs( w2 - 0.5_dp ) <= zero .and. all( abs( m2 - ma ) <= zero ) .and. &
   abs( vq2 - vqa ) <= zero .and. abs( lam - cl_lam( ma(3), vqa ) ) <= zero
call cl_step( w2, m2, vq2, 0.45_dp, 9.0_dp, 2.1_dp, 2.0e-3_dp, 1.6_dp, &
   1000.0_dp, 0.6_dp, 4.0_dp, 0.3_dp, 1.0_dp, 7.0_dp, 0.25_dp, w, ma, vqa, &
   x )
ok = ok .and. abs( w - 0.5_dp ) <= zero .and. &
   abs( ma(0)/( m2(0)*exp( -2.0e-3_dp/0.25_dp ) ) - one ) < 1.0e-15_dp
call check( ok, '7. one step in order: w, the centers lit, the moments, '// &
   'lam, bit for bit; w a running maximum (no lighting as s falls)' )

!*** 8. The inert limit and the pressure's floor: D0 = 0, centers lit
!***    but lam = 0 exactly; P <= 0 with NG > 0, no growth; NG = 0, P
!***    does not matter; G in reference lengths, (rho/R0)**(1/3).
m = zero; vq = zero; w = zero; ok = .true.
do k = 1, 200
   call cl_step( w, m, vq, 0.004_dp*real( k, dp ), 11.0_dp, 2.0_dp, &
      1.0e-3_dp, 1.6_dp, 1000.0_dp, 0.6_dp, 4.0_dp, zero, 1.0_dp, 7.0_dp, &
      0.25_dp, w2, m2, vq2, lam )
   w = w2; m = m2; vq = vq2
   if ( lam > zero .or. any( m(1:3) > zero ) .or. vq > zero ) ok = .false.
end do
t = 1.6_dp/1.6_dp
ok = ok .and. m(0) > zero .and. &
   cl_growth( -1.0_dp, 2.0_dp, 1.6_dp, 0.3_dp, 1.0_dp, 7.0_dp ) <= zero .and. &
   abs( cl_growth( -1.0_dp, 1.6_dp, 1.6_dp, 0.3_dp, zero, 7.0_dp ) - &
   0.3_dp ) <= zero .and. &
   abs( cl_growth( 7.0_dp, 2.0_dp, 1.6_dp, 0.3_dp, 2.0_dp, 7.0_dp )/ &
   ( 0.3_dp*1.25_dp**( one/3.0_dp ) ) - t ) < 1.0e-15_dp
call check( ok, '8. D0 = 0: centers lit, lam = 0 exactly, 200 steps; '// &
   'P <= 0 with NG > 0 no growth; NG = 0; G times (rho/R0)**(1/3)' )

if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_claude: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_claude: all ', ncheck, ' checks passed'

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

   function rtoa( r ) result(s)
   implicit none
   real(kind=dp), intent(in) :: r
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(es8.1)' ) r
   s = trim(adjustl(buf))
   end function rtoa

end program test_claude

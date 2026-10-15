program test_eos
!**********************************************************************!
!
!  Purpose:
!    Unit test for the equation of state (module eos, mg_eos). Run by
!    "make test"; the exit status is 0 if every check passes, 1 if any
!    check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from mg_eos. They were computed in Python with 50-digit
!    arithmetic (mpmath): the pressure straight from the closed-form Us,
!    and the sound speed from its thermodynamic definition,
!       c**2 = V**2 * [ P*(dP/de)_V - (dP/dV)_e ],
!    with mpmath's own numerical derivatives. So this test checks the
!    analytic derivatives in mg_eos (dUs/deta, dP_H/dV, phi') against an
!    independent route to the same numbers (code contract (a) 11.2).
!    Generator: My_Codes/bitwhiz/tests/eos_reference.py. In expansion
!    the expected values come from the cubic, with its coefficients
!    taken by the generator from the compression form's own numerical
!    derivatives, not from the formulas in eos_mod.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/14/26    D. E. Kittell        Original code
!                (with Claude)
!    10/16/26    D. E. Kittell        Expansion cubic: new reference
!                (with Claude)        states, broken cells at P = 0,
!                                     smoothness through V0
!
!**********************************************************************!
use bits, only: dp, int32, zero, one, two
use shock, only: not_finite
use eos, only: mg_eos, mg_soundspeed, eos_message, eos_ok, &
   eos_bad_density, eos_too_compressed, eos_bad_soundspeed
implicit none

!**********************************************************************!
! Data dictionary: the four class materials (input deck values).
!**********************************************************************!
integer(kind=int32), parameter :: nmat = 4
character(len=4), parameter, dimension(nmat) :: mname = &
   (/ 'Ta  ', 'Al  ', 'MatX', 'PMMA' /)
!                                                R0      C0     S1     S2     G0
real(kind=dp), parameter, dimension(5,nmat) :: mat = reshape( (/ &
                                              16.65_dp, 3.40_dp, 1.20_dp,  0.00_dp, 1.60_dp, &
                                               2.78_dp, 5.30_dp, 1.34_dp,  0.00_dp, 2.00_dp, &
                                               1.60_dp, 2.50_dp, 1.80_dp, -0.10_dp, 1.20_dp, &
                                               1.187_dp,2.55_dp, 1.54_dp,  0.00_dp, 0.90_dp /), &
                                              (/ 5, nmat /) )

!**********************************************************************!
! Data dictionary: reference states (rho, e) and the expected (P, c).
!**********************************************************************!
type :: state_t
   integer(kind=int32) :: m              ! material, index into mat
   real(kind=dp) :: rho                  ! g/cm^3
   real(kind=dp) :: e                    ! (km/s)^2
   real(kind=dp) :: p                    ! GPa, expected
   real(kind=dp) :: c                    ! km/s, expected
end type state_t

! 53 states: material, rho (g/cm^3), e ((km/s)^2), P (GPa), c (km/s)
type(state_t), parameter, dimension(53) :: ref = (/ &
   state_t( 1, 17.526315789473684211_dp, &
      0.0_dp, &
      10.455808057944771390_dp, &
      3.6354505331347595257_dp ), & ! Ta, eta = 0.05, cold
   state_t( 1, 17.526315789473684211_dp, &
      0.016353553644182888185_dp, &
      10.891466727025803531_dp, &
      3.6406433262830523279_dp ), & ! Ta, eta = 0.05, on Hugoniot
   state_t( 1, 17.526315789473684211_dp, &
      0.31635355364418288818_dp, &
      18.883466727025803531_dp, &
      3.7346223141315545100_dp ), & ! Ta, eta = 0.05, hot
   state_t( 1, 19.588235294117647059_dp, &
      0.0_dp, &
      37.784901844140392623_dp, &
      4.1063932931861821895_dp ), & ! Ta, eta = 0.15, cold
   state_t( 1, 19.588235294117647059_dp, &
      0.19341165972635336109_dp, &
      42.937388459250446163_dp, &
      4.1497228924537023373_dp ), & ! Ta, eta = 0.15, on Hugoniot
   state_t( 1, 19.588235294117647059_dp, &
      0.49341165972635336109_dp, &
      50.929388459250446163_dp, &
      4.2160502943103420258_dp ), & ! Ta, eta = 0.15, hot
   state_t( 1, 22.200000000000000000_dp, &
      0.0_dp, &
      78.560816326530612245_dp, &
      4.6161113466872283907_dp ), & ! Ta, eta = 0.25, cold
   state_t( 1, 22.200000000000000000_dp, &
      0.73724489795918367347_dp, &
      98.201020408163265306_dp, &
      4.7297057644293055695_dp ), & ! Ta, eta = 0.25, on Hugoniot
   state_t( 1, 22.200000000000000000_dp, &
      1.0372448979591836735_dp, &
      106.19302040816326531_dp, &
      4.7751561878200174479_dp ), & ! Ta, eta = 0.25, hot
   state_t( 1, 15.857142857142857143_dp, &
      0.0_dp, &
      -8.9077158406219630709_dp, &
      3.1577555449452785438_dp ), & ! Ta, eta = -0.05, cold
   state_t( 1, 15.857142857142857143_dp, &
      0.31286044855820576718_dp, &
      -0.57311349103136143335_dp, &
      3.2946073228297379322_dp ), & ! Ta, eta = -0.05, hot
   state_t( 1, 13.875000000000000000_dp, &
      0.0_dp, &
      -29.049316666666666667_dp, &
      2.3282760431987727115_dp ), & ! Ta, eta = -0.2, cold
   state_t( 1, 13.875000000000000000_dp, &
      0.45036420395421436004_dp, &
      -17.051614273326396115_dp, &
      2.6610321183311841323_dp ), & ! Ta, eta = -0.2, hot
   state_t( 2, 2.9263157894736842105_dp, &
      0.0_dp, &
      4.2611503419342461536_dp, &
      5.7402908752071775028_dp ), & ! Al, eta = 0.05, cold
   state_t( 2, 2.9263157894736842105_dp, &
      0.040336523494265866657_dp, &
      4.4854214125623643722_dp, &
      5.7529604710793106284_dp ), & ! Al, eta = 0.05, on Hugoniot
   state_t( 2, 2.9263157894736842105_dp, &
      0.34033652349426586666_dp, &
      6.1534214125623643722_dp, &
      5.8463282649711933244_dp ), & ! Al, eta = 0.05, hot
   state_t( 2, 3.2705882352941176471_dp, &
      0.0_dp, &
      15.595997656645274678_dp, &
      6.6298797079634001748_dp ), & ! Al, eta = 0.15, cold
   state_t( 2, 3.2705882352941176471_dp, &
      0.49500627348641371176_dp, &
      18.348232537229734916_dp, &
      6.7369038194441069231_dp ), & ! Al, eta = 0.15, on Hugoniot
   state_t( 2, 3.2705882352941176471_dp, &
      0.79500627348641371176_dp, &
      20.016232537229734916_dp, &
      6.8009464835742235103_dp ), & ! Al, eta = 0.15, hot
   state_t( 2, 3.7066666666666666667_dp, &
      0.0_dp, &
      33.109644411781333032_dp, &
      7.6329850763999006835_dp ), & ! Al, eta = 0.25, cold
   state_t( 2, 3.7066666666666666667_dp, &
      1.9849906721691446662_dp, &
      44.146192549041777376_dp, &
      7.9201445813144202458_dp ), & ! Al, eta = 0.25, on Hugoniot
   state_t( 2, 3.7066666666666666667_dp, &
      2.2849906721691446662_dp, &
      45.814192549041777376_dp, &
      7.9626434171651924584_dp ), & ! Al, eta = 0.25, hot
   state_t( 2, 2.6476190476190476190_dp, &
      0.0_dp, &
      -3.6010940314609653385_dp, &
      4.8457036778157699179_dp ), & ! Al, eta = -0.05, cold
   state_t( 2, 2.6476190476190476190_dp, &
      0.33084131686823500271_dp, &
      -1.7616163096735787235_dp, &
      4.9939818122001801373_dp ), & ! Al, eta = -0.05, hot
   state_t( 2, 2.3166666666666666667_dp, &
      0.0_dp, &
      -11.665374376666666667_dp, &
      3.2326060962222621740_dp ), & ! Al, eta = -0.2, cold
   state_t( 2, 2.3166666666666666667_dp, &
      0.64941635402879917205_dp, &
      -8.0546194482665432701_dp, &
      3.7670121280053262611_dp ), & ! Al, eta = -0.2, hot
   state_t( 3, 1.6842105263157894737_dp, &
      0.0_dp, &
      0.58532469726059500798_dp, &
      2.8447381455996191623_dp ), & ! MatX, eta = 0.05, cold
   state_t( 3, 1.6842105263157894737_dp, &
      0.0094285550460791721646_dp, &
      0.60342752294906701853_dp, &
      2.8468910177889571831_dp ), & ! MatX, eta = 0.05, on Hugoniot
   state_t( 3, 1.6842105263157894737_dp, &
      0.30942855504607917216_dp, &
      1.1794275229490670185_dp, &
      2.9145614536611583555_dp ), & ! MatX, eta = 0.05, hot
   state_t( 3, 1.8823529411764705882_dp, &
      0.0_dp, &
      2.5400519698855965106_dp, &
      3.7078902754586196952_dp ), & ! MatX, eta = 0.15, cold
   state_t( 3, 1.8823529411764705882_dp, &
      0.13084058910811795213_dp, &
      2.7912659009731829787_dp, &
      3.7262013960263452939_dp ), & ! MatX, eta = 0.15, on Hugoniot
   state_t( 3, 1.8823529411764705882_dp, &
      0.43084058910811795213_dp, &
      3.3672659009731829787_dp, &
      3.7678504274650665275_dp ), & ! MatX, eta = 0.15, hot
   state_t( 3, 2.1333333333333333333_dp, &
      0.0_dp, &
      6.7486895898214147955_dp, &
      4.9848774052809819947_dp ), & ! MatX, eta = 0.25, cold
   state_t( 3, 2.1333333333333333333_dp, &
      0.62028396965270356576_dp, &
      7.9396348115546056418_dp, &
      5.0350206316458670005_dp ), & ! MatX, eta = 0.25, on Hugoniot
   state_t( 3, 2.1333333333333333333_dp, &
      0.92028396965270356576_dp, &
      8.5156348115546056418_dp, &
      5.0590940652551169486_dp ), & ! MatX, eta = 0.25, hot
   state_t( 3, 1.5238095238095238095_dp, &
      0.0_dp, &
      -0.43338732318324155059_dp, &
      2.1912340821375265464_dp ), & ! MatX, eta = -0.05, cold
   state_t( 3, 1.5238095238095238095_dp, &
      0.30657285911628791494_dp, &
      0.15523256632003124610_dp, &
      2.2996134183497249565_dp ), & ! MatX, eta = -0.05, hot
   state_t( 3, 1.3333333333333333333_dp, &
      0.0_dp, &
      -1.2203703703703703704_dp, &
      1.4122676800097069417_dp ), & ! MatX, eta = -0.2, cold
   state_t( 3, 1.3333333333333333333_dp, &
      0.36729144035403582572_dp, &
      -0.51517080489062158499_dp, &
      1.6601552730748195555_dp ), & ! MatX, eta = -0.2, hot
   state_t( 4, 1.2494736842105263158_dp, &
      0.0_dp, &
      0.44280696990300834929_dp, &
      2.8293079776379679845_dp ), & ! PMMA, eta = 0.05, cold
   state_t( 4, 1.2494736842105263158_dp, &
      0.0095408478875587050095_dp, &
      0.45299945770128731385_dp, &
      2.8305402718655763628_dp ), & ! PMMA, eta = 0.05, on Hugoniot
   state_t( 4, 1.2494736842105263158_dp, &
      0.30954084788755870501_dp, &
      0.77348945770128731385_dp, &
      2.8690182520599012298_dp ), & ! PMMA, eta = 0.05, hot
   state_t( 4, 1.3964705882352941176_dp, &
      0.0_dp, &
      1.8256541123991944007_dp, &
      3.5103851989079916815_dp ), & ! PMMA, eta = 0.15, cold
   state_t( 4, 1.3964705882352941176_dp, &
      0.12370299191187785464_dp, &
      1.9578060186586535128_dp, &
      3.5206815147289209238_dp ), & ! PMMA, eta = 0.15, on Hugoniot
   state_t( 4, 1.3964705882352941176_dp, &
      0.42370299191187785464_dp, &
      2.2782960186586535128_dp, &
      3.5455275810736445376_dp ), & ! PMMA, eta = 0.15, hot
   state_t( 4, 1.5826666666666666667_dp, &
      0.0_dp, &
      4.5278206796549672814_dp, &
      4.4912741788990506662_dp ), & ! PMMA, eta = 0.25, cold
   state_t( 4, 1.5826666666666666667_dp, &
      0.53725461035098155860_dp, &
      5.1017697798929208804_dp, &
      4.5184433582691404300_dp ), & ! PMMA, eta = 0.25, on Hugoniot
   state_t( 4, 1.5826666666666666667_dp, &
      0.83725461035098155860_dp, &
      5.4222597798929208804_dp, &
      4.5335436340556498211_dp ), & ! PMMA, eta = 0.25, hot
   state_t( 4, 1.1304761904761904762_dp, &
      0.0_dp, &
      -0.34024164885422740525_dp, &
      2.2964358667546862147_dp ), & ! PMMA, eta = -0.05, cold
   state_t( 4, 1.1304761904761904762_dp, &
      0.30700743321358462458_dp, &
      -0.012265607952154950813_dp, &
      2.3553732195053310379_dp ), & ! PMMA, eta = -0.05, hot
   state_t( 4, 0.98916666666666666667_dp, &
      0.0_dp, &
      -0.98942177275000000000_dp, &
      1.6386282275122688732_dp ), & ! PMMA, eta = -0.2, cold
   state_t( 4, 0.98916666666666666667_dp, &
      0.37601422439188620486_dp, &
      -0.58772577683214796734_dp, &
      1.7673951056090135245_dp ), & ! PMMA, eta = -0.2, hot
   state_t( 3, 2.1108447540380316065_dp, &
      0.55439625545141542951_dp, &
      7.3305679236761677658_dp, &
      4.9072575218937171734_dp ) /) !  MatX, 1.5 km/s first shock, up = 1.053, contract V2: 7.331 GPa

! 12 broken-cell states: material, rho (g/cm^3), c at P = 0 (km/s)
!*** (p and e are not used here: the call is mg_soundspeed at P = 0.)
type(state_t), parameter, dimension(12) :: zerop = (/ &
   state_t( 1, 9.9900000000000000000_dp, 0.0_dp, 0.0_dp, &
      2.6685126943674073517_dp ), & ! Ta, rho = 0.6*R0, P = 0
   state_t( 1, 1.6650000000000000000_dp, 0.0_dp, 0.0_dp, &
      2.1664163958020627942_dp ), & ! Ta, rho = 0.1*R0, P = 0
   state_t( 1, 0.33300000000000000000_dp, 0.0_dp, 0.0_dp, &
      2.1509938168204947213_dp ), & ! Ta, rho = 0.02*R0, P = 0
   state_t( 2, 1.6680000000000000000_dp, 0.0_dp, 0.0_dp, &
      4.1815085507505541869_dp ), & ! Al, rho = 0.6*R0, P = 0
   state_t( 2, 0.27800000000000000000_dp, 0.0_dp, 0.0_dp, &
      4.1689275791263153100_dp ), & ! Al, rho = 0.1*R0, P = 0
   state_t( 2, 0.055600000000000000000_dp, 0.0_dp, 0.0_dp, &
      4.3265668253708967762_dp ), & ! Al, rho = 0.02*R0, P = 0
   state_t( 3, 0.96000000000000000000_dp, 0.0_dp, 0.0_dp, &
      1.8248287590894659067_dp ), & ! MatX, rho = 0.6*R0, P = 0
   state_t( 3, 0.16000000000000000000_dp, 0.0_dp, 0.0_dp, &
      4.4263416045307664437_dp ), & ! MatX, rho = 0.1*R0, P = 0
   state_t( 3, 0.032000000000000000000_dp, 0.0_dp, 0.0_dp, &
      4.9241953657425087991_dp ), & ! MatX, rho = 0.02*R0, P = 0
   state_t( 4, 0.71220000000000000000_dp, 0.0_dp, 0.0_dp, &
      1.6148246220565253692_dp ), & ! PMMA, rho = 0.6*R0, P = 0
   state_t( 4, 0.11870000000000000000_dp, 0.0_dp, 0.0_dp, &
      3.2607949889559141065_dp ), & ! PMMA, rho = 0.1*R0, P = 0
   state_t( 4, 0.023740000000000000000_dp, 0.0_dp, 0.0_dp, &
      3.6395446702025790633_dp ) /) !  PMMA, rho = 0.02*R0, P = 0

!*** Tolerances. float64 carries about 16 digits; the arithmetic in
!*** mg_eos loses at most a few of them (2e-14 measured), so 1e-12 is
!*** tight enough to catch any wrong term and loose enough to pass on
!*** any IEEE machine and any optimization level.
real(kind=dp), parameter :: rtol = 1.0e-12_dp

!**********************************************************************!
! Data dictionary: work variables.
!**********************************************************************!
integer(kind=int32) :: i, m, ierr, nfail, ncheck
integer(kind=int32), dimension(size(ref)) :: ierrs
real(kind=dp) :: p, c, eta, err_p, err_c, worst_p, worst_c
real(kind=dp), dimension(size(ref)) :: pa, ca

nfail  = 0
ncheck = 0
write(*,'(a)') ' test_eos: Mie-Gruneisen pressure and sound speed'

!=====================================================================!
! 1. The reference state, rho = R0 and e = 0: P = 0 exactly (eta is
!    exactly 0, and every term of P carries eta or e) and c = C0 (to a
!    few units in the last place).
!=====================================================================!
do m = 1, nmat
   call mg_eos( mat(1,m), zero, mat(1,m), mat(2,m), mat(3,m), mat(4,m), &
      mat(5,m), p, c, ierr )
   call check( ierr == eos_ok .and. .not. ( abs(p) > zero ) .and. &
      abs(c - mat(2,m)) <= 4.0_dp*epsilon(one)*mat(2,m), &
      'reference state, '//trim(mname(m))//': P = 0, c = C0' )
end do

!=====================================================================!
! 2. The reference states: compressed, on and off the Hugoniot, and
!    in expansion (V = 1.05 and 1.25 V0, the cubic branch), for all
!    four materials, plus the 1.5 km/s first shock in MatX. A wrong
!    derivative (e.g. dP_H/dV used where phi' belongs) misses c by
!    5-11% here; a wrong cubic coefficient misses in expansion.
!=====================================================================!
worst_p = zero
worst_c = zero
do i = 1, size(ref)
   m = ref(i)%m
   call mg_eos( ref(i)%rho, ref(i)%e, mat(1,m), mat(2,m), mat(3,m), &
      mat(4,m), mat(5,m), p, c, ierr )
   if ( ierr /= eos_ok ) then
      call check( .false., 'state '//itoa(i)//' ('//trim(mname(m))// &
         '): '//eos_message(ierr) )
      cycle
   end if
   err_p = abs(p - ref(i)%p)/max( abs(ref(i)%p), one )   ! GPa scale near P = 0
   err_c = abs(c - ref(i)%c)/ref(i)%c
   worst_p = max( worst_p, err_p )
   worst_c = max( worst_c, err_c )
   if ( err_p > rtol .or. err_c > rtol ) then
      call check( .false., 'state '//itoa(i)//' ('//trim(mname(m))// &
         '): P or c off the reference' )
   end if
end do
call check( worst_p <= rtol .and. worst_c <= rtol, &
   itoa(size(ref))//' reference states, P and c to 1e-12' )
write(*,'(a,es8.1,a,es8.1)') '         worst relative error: P ', &
   worst_p, ', c ', worst_c

!=====================================================================!
! 3. The elemental call on whole arrays gives exactly the same answers
!    as one call per state (it is the same code, looped by Fortran).
!=====================================================================!
call mg_eos( ref%rho, ref%e, mat(1,ref%m), mat(2,ref%m), mat(3,ref%m), &
   mat(4,ref%m), mat(5,ref%m), pa, ca, ierrs )
same_answers: block
   logical :: same
   same = all( ierrs == eos_ok )
   do i = 1, size(ref)
      m = ref(i)%m
      call mg_eos( ref(i)%rho, ref(i)%e, mat(1,m), mat(2,m), mat(3,m), &
         mat(4,m), mat(5,m), p, c, ierr )
      if ( abs(pa(i) - p) > zero .or. abs(ca(i) - c) > zero ) same = .false.
   end do
   call check( same, 'array (elemental) call == one call per state' )
end block same_answers

!=====================================================================!
! 4. Broken cells: the sound speed at P = 0 (what the time loop uses
!    once a cell has failed), out to rho = 0.02*R0. The cubic keeps
!    c**2 > 0 at P = 0 at any expansion for all four materials.
!=====================================================================!
worst_c = zero
do i = 1, size(zerop)
   m = zerop(i)%m
   call mg_soundspeed( zerop(i)%rho, zero, mat(1,m), mat(2,m), mat(3,m), &
      mat(4,m), mat(5,m), c, ierr )
   if ( ierr /= eos_ok ) then
      worst_c = huge(one)
   else
      worst_c = max( worst_c, abs(c - zerop(i)%c)/zerop(i)%c )
   end if
end do
call check( worst_c <= rtol, itoa(size(zerop))//' broken-cell states '// &
   '(c at P = 0, down to 0.02*R0) to 1e-12' )

!=====================================================================!
! 5. Smooth through V0, where compression meets the expansion cubic:
!    P, c, dc/drho and d2c/drho2 continuous (the cubic matches phi and
!    its first three derivatives). Checked with one-sided differences
!    on each side of rho = R0, cold, for all four materials: a jump in
!    a slope shows up as an O(1) mismatch, smooth agreement as O(h).
!=====================================================================!
do m = 1, nmat
   call smooth_at_v0( m )
end do

!=====================================================================!
! 6. Status codes, and NO floating-point trap on the way. On any status
!    but eos_ok, p and c must come back as NaN (so they can not be used
!    by mistake). Linear Al (S2 = 0) has its limit at eta = 1/S1.
!=====================================================================!
m = 2                                                     ! Al
eta = 0.98_dp/mat(3,m)                                    ! Us = 50*C0
call status_case( mat(1,m)/(one - eta), zero, m, eos_ok, &
   'Al at 0.98 of the limit: still ok' )
eta = 0.995_dp/mat(3,m)                                   ! Us = 200*C0
call status_case( mat(1,m)/(one - eta), zero, m, eos_too_compressed, &
   'Al at 0.995 of the limit: too compressed' )
eta = one/mat(3,m)                                        ! exactly at it
call status_case( mat(1,m)/(one - eta), zero, m, eos_too_compressed, &
   'Al exactly at eta = 1/S1: too compressed, no trap' )
eta = 1.2_dp/mat(3,m)                                     ! past it
call status_case( mat(1,m)/(one - eta), zero, m, eos_too_compressed, &
   'Al past the limit: too compressed, no trap' )
m = 3                                                     ! MatX, S2 < 0
eta = 0.9_dp
call status_case( mat(1,m)/(one - eta), zero, m, eos_ok, &
   'MatX at eta = 0.9 (S2 < 0, no limit): ok' )
m = 2
call status_case( zero, zero, m, eos_bad_density, 'rho = 0: bad density' )
call status_case( -one, zero, m, eos_bad_density, 'rho < 0: bad density' )
m = 1                                                     ! Ta, cold,
call status_case( 0.1_dp*mat(1,m), zero, m, eos_bad_soundspeed, &   ! P = -44 GPa
   'Ta cold at rho = 0.1*R0 (P = -44 GPa): c**2 <= 0' )

!*** A made-up material (R0 = C0 = 1, S1 = 1.3, S2 = -0.3, G0 = 0.3)
!*** whose cubic's slope reaches zero at rho = 0.63*R0: there c -> 0
!*** even at P = 0, and beyond it c**2 < 0.
call mg_soundspeed( 0.5_dp, zero, one, one, 1.3_dp, -0.3_dp, 0.3_dp, &
   c, ierr )
call check( ierr == eos_bad_soundspeed .and. not_finite(c), &
   'made-up material past its cubic''s c = 0 point: c**2 <= 0' )
call mg_soundspeed( 0.7_dp, zero, one, one, 1.3_dp, -0.3_dp, 0.3_dp, &
   c, ierr )
call check( ierr == eos_ok, '... and before it (rho = 0.7*R0): ok' )

!*** A made-up material with S2 > 0, where the square root goes
!*** negative before D reaches zero.
call mg_eos( 2.78_dp/(one - 0.6_dp), zero, 2.78_dp, 5.30_dp, 1.34_dp, &
   0.5_dp, 2.00_dp, p, c, ierr )
call check( ierr == eos_too_compressed .and. not_finite(p) .and. &
   not_finite(c), 'S2 > 0, negative square root: too compressed' )

!=====================================================================!
! Summary. Exit status 1 on any failure, so 'make test' stops.
!=====================================================================!
if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_eos: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   stop 1, quiet=.true.
end if
write(*,'(a,i0,a)') ' test_eos: all ', ncheck, ' checks passed'

contains

   !*** Count one check, and print it.
   subroutine check( ok, what )
   implicit none
   logical, intent(in) :: ok
   character(len=*), intent(in) :: what
   ncheck = ncheck + 1
   if ( ok ) then
      write(*,'(a)') '   pass  '//what
   else
      write(*,'(a)') '   FAIL  '//what
      nfail = nfail + 1
   end if
   end subroutine check

   !*** One status case: the code must match, and p, c must be NaN
   !*** unless the status is eos_ok.
   subroutine status_case( rho_in, e_in, mm, want, what )
   implicit none
   real(kind=dp), intent(in) :: rho_in, e_in
   integer(kind=int32), intent(in) :: mm, want
   character(len=*), intent(in) :: what
   real(kind=dp) :: pp, cc
   integer(kind=int32) :: ie
   logical :: nan_ok
   call mg_eos( rho_in, e_in, mat(1,mm), mat(2,mm), mat(3,mm), mat(4,mm), &
      mat(5,mm), pp, cc, ie )
   if ( want == eos_ok ) then
      nan_ok = .not. ( not_finite(pp) .or. not_finite(cc) )
   else
      nan_ok = not_finite(pp) .and. not_finite(cc)
   end if
   call check( ie == want .and. nan_ok, what )
   end subroutine status_case

   !*** Continuity of P, c, dc/drho and d2c/drho2 through rho = R0.
   !*** One-sided differences on each side of R0, with step h: the two
   !*** sides never agree exactly (finite differences are not exact),
   !*** but if the curve is smooth they disagree by O(h), so HALVING h
   !*** halves the mismatch. A kink (a derivative that jumps at R0)
   !*** leaves a mismatch that does not shrink. So: mismatch(h/2) must
   !*** be at most 0.6 of mismatch(h), for the slope of P, the slope
   !*** of c and the curvature of c. (Measured ratios: 0.50 to 0.53.)
   subroutine smooth_at_v0( mm )
   implicit none
   integer(kind=int32), intent(in) :: mm
   real(kind=dp) :: mis(3,2), h
   integer(kind=int32) :: n
   logical :: ok
   ok = .true.
   do n = 1, 2
      h = 1.0e-3_dp*mat(1,mm)/real(n,dp)          ! h, then h/2
      call mismatch( mm, h, mis(:,n), ok )
   end do
   if ( ok ) ok = all( mis(:,2) <= 0.6_dp*mis(:,1) )
   call check( ok, 'smooth through V0, '//trim(mname(mm))// &
      ': P, c, dc and d2c continuous' )
   end subroutine smooth_at_v0

   !*** The three left/right mismatches at step h, relative.
   subroutine mismatch( mm, h, mis, ok )
   implicit none
   integer(kind=int32), intent(in) :: mm
   real(kind=dp), intent(in) :: h
   real(kind=dp), intent(out) :: mis(3)
   logical, intent(inout) :: ok
   real(kind=dp) :: cc(-2:2), pp(-2:2), a, b
   integer(kind=int32) :: j, ie
   mis = zero
   do j = -2, 2
      call mg_eos( mat(1,mm) + real(j,dp)*h, zero, mat(1,mm), mat(2,mm), &
         mat(3,mm), mat(4,mm), mat(5,mm), pp(j), cc(j), ie )
      if ( ie /= eos_ok ) ok = .false.
   end do
   if ( .not. ok ) return
   a = pp(1) - pp(0)                              ! slope of P, right
   b = pp(0) - pp(-1)                             ! ... and left
   mis(1) = abs(a - b)/abs(a)
   a = cc(1) - cc(0)                              ! slope of c
   b = cc(0) - cc(-1)
   mis(2) = abs(a - b)/abs(a)
   a = cc(2) - two*cc(1) + cc(0)                  ! curvature of c
   b = cc(0) - two*cc(-1) + cc(-2)
   mis(3) = abs(a - b)/max( abs(a), abs(b) )
   end subroutine mismatch

   !*** An integer as text, without padding.
   function itoa( n ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim(buf)
   end function itoa

end program test_eos

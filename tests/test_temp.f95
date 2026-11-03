program test_temp
!**********************************************************************!
!
!  Purpose:
!    Unit test for the temperature (module temperature: cold_step,
!    temp_of). Run by "make test"; the exit status is 0 if every check
!    passes, 1 if any check fails, so make (and any script) can tell.
!
!  Where the expected values come from:
!    NOT from module temperature. They were computed in Python with
!    50-digit arithmetic (mpmath): the cold energy as the integral
!    itself, from V0 to the state, by mpmath's own quadrature, with Pi
!    built from the closed-form Us (compression) and the cubic's
!    coefficients taken from the compression form's own numerical
!    derivatives (tension); T from the formula of doc/design/
!    materials.md at e = e_H. So this test checks the per-step method
!    (the exact propagator, the 3-point Gauss pieces, the split at
!    eta = 0) against an independent route to the same numbers.
!    Generator: tests/temp_reference.py.
!
!    The one risk of carrying e_c cell by cell ("plan C") is drift:
!    small errors piling up over thousands of steps. Section 6 drives
!    one cell through a shock, 2,000 steps of ringing, a release into
!    tension and back, and section 7 a broken cell stretched to 21
!    times its volume and back; e_c must still be on the curve.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/03/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, one, quit
use shock, only: nlay, layer, eos_mie_gruneisen, eos_mie_gruneisen_t
use deck, only: read_deck
use eos, only: eos_ok
use temperature, only: cold_step, temp_of
implicit none

!**********************************************************************!
! Data dictionary: the four class materials (input deck values), and
! the gold-standard runs' C_V and T0 (doc/design/materials.md).
!**********************************************************************!
integer(kind=int32), parameter :: nmat = 4   ! Ta, Al, MatX, PMMA
!                                                R0      C0     S1     S2     G0
real(kind=dp), parameter, dimension(5,nmat) :: mat = reshape( (/ &
                                              16.65_dp, 3.40_dp, 1.20_dp,  0.00_dp, 1.60_dp, &
                                               2.78_dp, 5.30_dp, 1.34_dp,  0.00_dp, 2.00_dp, &
                                               1.60_dp, 2.50_dp, 1.80_dp, -0.10_dp, 1.20_dp, &
                                               1.187_dp,2.55_dp, 1.54_dp,  0.00_dp, 0.90_dp /), &
                                              (/ 5, nmat /) )
real(kind=dp), parameter :: cv_g1 = 1.1633418_dp/1000.0_dp  ! kJ/(g K)
real(kind=dp), parameter :: t0_g1 = 298.0_dp                ! K

!**********************************************************************!
! Data dictionary: the reference cold energies and Hugoniot states.
!**********************************************************************!
type :: cold_t
   integer(kind=int32) :: m              ! material, index into mat
   real(kind=dp) :: eta                  ! 1 - R0*V
   real(kind=dp) :: ec                   ! e_c(eta), kJ/g, expected
end type cold_t

type :: hug_t
   integer(kind=int32) :: m              ! material
   real(kind=dp) :: eta                  ! 1 - R0*V
   real(kind=dp) :: e                    ! e_H, kJ/g
   real(kind=dp) :: t                    ! T on the Hugoniot, K, expected
end type hug_t

! 24 cold energies: material, eta, e_c (kJ/g)
type(cold_t), parameter, dimension(24) :: ref = (/ &
   cold_t( 1, -0.2_dp, &
      0.17125419471726932230_dp ), & ! Ta
   cold_t( 1, -0.05_dp, &
      0.013357126033442483853_dp ), & ! Ta
   cold_t( 1, 0.05_dp, &
      0.015676235028184915703_dp ), & ! Ta
   cold_t( 1, 0.1_dp, &
      0.068239371484163409084_dp ), & ! Ta
   cold_t( 1, 0.15_dp, &
      0.16768047666152956576_dp ), & ! Ta
   cold_t( 1, 0.25_dp, &
      0.56261642198776283957_dp ), & ! Ta
   cold_t( 2, -0.2_dp, &
      0.40221193139450443418_dp ), & ! Al
   cold_t( 2, -0.05_dp, &
      0.032162474148941959308_dp ), & ! Al
   cold_t( 2, 0.05_dp, &
      0.038458529675380763039_dp ), & ! Al
   cold_t( 2, 0.1_dp, &
      0.16911200254314975884_dp ), & ! Al
   cold_t( 2, 0.15_dp, &
      0.42003814425340277747_dp ), & ! Al
   cold_t( 2, 0.25_dp, &
      1.4437109046374710397_dp ), & ! Al
   cold_t( 3, -0.2_dp, &
      0.081755450005121964307_dp ), & ! MatX
   cold_t( 3, -0.05_dp, &
      0.0069548221827798990292_dp ), & ! MatX
   cold_t( 3, 0.05_dp, &
      0.0088439501730987018782_dp ), & ! MatX
   cold_t( 3, 0.1_dp, &
      0.040406644119296199658_dp ), & ! MatX
   cold_t( 3, 0.15_dp, &
      0.10495603588097223499_dp ), & ! MatX
   cold_t( 3, 0.25_dp, &
      0.40489211036290169319_dp ), & ! MatX
   cold_t( 4, -0.2_dp, &
      0.090063704786293224853_dp ), & ! PMMA
   cold_t( 4, -0.05_dp, &
      0.0073567324225940510281_dp ), & ! PMMA
   cold_t( 4, 0.05_dp, &
      0.0090358883176984555520_dp ), & ! PMMA
   cold_t( 4, 0.1_dp, &
      0.040468296365143355500_dp ), & ! PMMA
   cold_t( 4, 0.15_dp, &
      0.10281695882933745606_dp ), & ! PMMA
   cold_t( 4, 0.25_dp, &
      0.37641941441394890060_dp ) /) ! PMMA

! 12 Hugoniot states: material, eta, e_H (kJ/g), T (K)
type(hug_t), parameter, dimension(12) :: hug = (/ &
   hug_t( 1, 0.05_dp, &
      0.016353553644182888185_dp, &
      323.40176423580669600_dp ), & ! Ta
   hug_t( 1, 0.15_dp, &
      0.19341165972635336109_dp, &
      400.95058129112965945_dp ), & ! Ta
   hug_t( 1, 0.25_dp, &
      0.73724489795918367347_dp, &
      594.67310520852881012_dp ), & ! Ta
   hug_t( 2, 0.05_dp, &
      0.040336523494265866657_dp, &
      330.95524317198478034_dp ), & ! Al
   hug_t( 2, 0.15_dp, &
      0.49500627348641371176_dp, &
      466.69997361781775438_dp ), & ! Al
   hug_t( 2, 0.25_dp, &
      1.9849906721691446662_dp, &
      956.59902018180450434_dp ), & ! Al
   hug_t( 3, 0.05_dp, &
      0.0094285550460791721646_dp, &
      316.92981289197334676_dp ), & ! MatX
   hug_t( 3, 0.15_dp, &
      0.13084058910811795213_dp, &
      379.02094456190694220_dp ), & ! MatX
   hug_t( 3, 0.25_dp, &
      0.62028396965270356576_dp, &
      587.40717253114738655_dp ), & ! MatX
   hug_t( 4, 0.05_dp, &
      0.0095408478875587050095_dp, &
      312.15036176124155549_dp ), & ! PMMA
   hug_t( 4, 0.15_dp, &
      0.12370299191187785464_dp, &
      359.02544117200505222_dp ), & ! PMMA
   hug_t( 4, 0.25_dp, &
      0.53725461035098155860_dp, &
      511.44491331956040477_dp ) /) ! PMMA

!*** Tolerance. The method's quadrature error is below 1e-14 (pieces of
!*** at most 0.005 in eta, module temperature), and float64 round-off
!*** over a 2,000-step path stays near 1e-13 (measured), so 1e-12 is
!*** tight enough to catch a wrong term, a wrong weight or a lost
!*** factor, and loose enough for any IEEE machine and optimization.
real(kind=dp), parameter :: rtol = 1.0e-12_dp

!**********************************************************************!
! Data dictionary: work variables.
!**********************************************************************!
integer(kind=int32) :: i, j, m, ierr, nfail, ncheck, nbad
real(kind=dp) :: ec1, ec2, ecw, eta1, eta2, t, worst, err
real(kind=dp), dimension(size(ref)) :: eca
integer(kind=int32), dimension(size(ref)) :: ierrs
logical :: ok

nfail  = 0
ncheck = 0
write(*,'(a)') ' test_temp: the cold curve and the temperature'

!=====================================================================!
! 1. The reference state, eta = 0 and e = 0: a step of zero length
!    leaves e_c = 0 exactly, and T = T0 exactly (exp(0) = 1), for all
!    four materials. Every cell at rest stays at T0 to the last bit.
!=====================================================================!
ok = .true.
do m = 1, nmat
   call step( m, zero, zero, zero, ec2, ierr )
   t = temp_of( zero, zero, ec2, mat(5,m), cv_g1, t0_g1 )
   if ( ierr /= eos_ok .or. abs(ec2) > zero .or. abs(t - t0_g1) > zero ) &
      ok = .false.
end do
call check( ok, 'reference state: e_c = 0 and T = T0 exactly' )

!=====================================================================!
! 2. A cell that does not move: 1,000 steps of zero length at eta =
!    0.1 leave its e_c bit for bit (the growth factor is exp(0) = 1
!    and the integral is 0).
!=====================================================================!
ok = .true.
do m = 1, nmat
   call step( m, zero, 0.1_dp, zero, ec1, ierr )
   ec2 = ec1
   do i = 1, 1000
      ecw = ec2
      call step( m, 0.1_dp, 0.1_dp, ecw, ec2, ierr )
   end do
   if ( ierr /= eos_ok .or. abs(ec2 - ec1) > zero ) ok = .false.
end do
call check( ok, 'zero-length steps leave e_c bit for bit' )

!=====================================================================!
! 3. The cold energy in ONE step from V0, in tension (the cubic) and
!    in compression (the Hugoniot form), for all four materials. The
!    longer steps are cut into pieces of 0.005; this checks the
!    propagator, the Gauss points and weights, and the pieces.
!=====================================================================!
worst = zero
nbad  = 0
do i = 1, size(ref)
   m = ref(i)%m
   call step( m, zero, ref(i)%eta, zero, ec2, ierr )
   call score( ierr, ec2, ref(i)%ec, worst, nbad )
end do
call check( nbad == 0, itoa(size(ref))//' cold energies, one step '// &
   'from V0, to 1e-12' )
write(*,'(a,es8.1)') '         worst relative error: ', worst

!=====================================================================!
! 4. The same, in 997 small steps (each a single piece, as almost every
!    step of a run is): the same e_c, so the step size does not matter.
!=====================================================================!
worst = zero
nbad  = 0
do i = 1, size(ref)
   m = ref(i)%m
   ec2  = zero
   eta2 = zero
   do j = 1, 997
      eta1 = eta2
      eta2 = ref(i)%eta*( real(j,dp)/997.0_dp )
      ec1 = ec2
      call step( m, eta1, eta2, ec1, ec2, ierr )
      if ( ierr /= eos_ok ) exit
   end do
   call score( ierr, ec2, ref(i)%ec, worst, nbad )
end do
call check( nbad == 0, itoa(size(ref))//' cold energies, 997 steps '// &
   'from V0, to 1e-12' )
write(*,'(a,es8.1)') '         worst relative error: ', worst

!=====================================================================!
! 5. The elemental call on whole arrays gives exactly the same answers
!    as one call per state (it is the same code, looped by Fortran).
!=====================================================================!
call cold_step( spread(zero, 1, size(ref)), ref%eta, &
   spread(zero, 1, size(ref)), mat(1,ref%m), mat(2,ref%m), mat(3,ref%m), &
   mat(4,ref%m), mat(5,ref%m), eca, ierrs )
ok = all( ierrs == eos_ok )
do i = 1, size(ref)
   call step( ref(i)%m, zero, ref(i)%eta, zero, ec2, ierr )
   if ( abs(eca(i) - ec2) > zero ) ok = .false.
end do
call check( ok, 'array (elemental) call == one call per state' )

!=====================================================================!
! 6. The hard path, for all four materials: a shock from V0 to eta =
!    0.25 in 4 steps (each cut into 13 pieces), 2,000 steps of ringing
!    between about 0.15 and 0.30, a release in 50 steps to eta = -0.2
!    (into tension, crossing V0 on the way), then 7 steps back to 0.1.
!    e_c is a function of V alone, so at -0.2 and at 0.1 the carried
!    value must be the curve's, to near round-off, however it got
!    there. This is the test of plan C's one risk, drift.
!=====================================================================!
worst = zero
nbad  = 0
do m = 1, nmat
   ec2  = zero
   eta2 = zero
   do j = 1, 2061
      eta1 = eta2
      eta2 = hard_path( j )
      ec1 = ec2
      call step( m, eta1, eta2, ec1, ec2, ierr )
      if ( ierr /= eos_ok ) exit
      if ( j == 2054 ) call score( ierr, ec2, ref_ec( m, -0.2_dp ), worst, &
         nbad )                          ! the end of the release
   end do
   call score( ierr, ec2, ref_ec( m, 0.1_dp ), worst, nbad )
end do
call check( nbad == 0, 'hard path (shock, 2,000 steps of ringing, '// &
   'release into tension, back): e_c on the curve to 1e-12' )
write(*,'(a,es8.1)') '         worst relative error: ', worst

!=====================================================================!
! 7. A broken cell stretched far: from eta = -0.2 out to -20 (21 times
!    its volume) in 50 steps and back. Out there a step's Delta eta is
!    about 0.4; its pieces scale with 1 - eta, so a few per step do,
!    and the cell comes back on the curve.
!=====================================================================!
worst = zero
nbad  = 0
do m = 1, nmat
   call step( m, zero, -0.2_dp, zero, ec2, ierr )
   eta2 = -0.2_dp
   do j = 1, 100
      eta1 = eta2
      if ( j < 50 ) then
         eta2 = -0.2_dp - 19.8_dp*( real(j,dp)/50.0_dp )
      else if ( j < 100 ) then
         eta2 = -20.0_dp + 19.8_dp*( real(j-50,dp)/50.0_dp )
      else
         eta2 = -0.2_dp
      end if
      ec1 = ec2
      call step( m, eta1, eta2, ec1, ec2, ierr )
      if ( ierr /= eos_ok ) exit
   end do
   call score( ierr, ec2, ref_ec( m, -0.2_dp ), worst, nbad )
end do
call check( nbad == 0, 'deep tension (out to 21 V0 and back): e_c on '// &
   'the curve to 1e-12' )
write(*,'(a,es8.1)') '         worst relative error: ', worst

!=====================================================================!
! 8. T on the Hugoniot, with the gold-standard runs' C_V and T0, for
!    all four materials, from 314 K to 957 K: e_c by one step from V0,
!    then the formula.
!=====================================================================!
worst = zero
do i = 1, size(hug)
   m = hug(i)%m
   call step( m, zero, hug(i)%eta, zero, ec2, ierr )
   t = temp_of( hug(i)%eta, hug(i)%e, ec2, mat(5,m), cv_g1, t0_g1 )
   if ( ierr /= eos_ok ) then
      worst = huge(one)
   else
      worst = max( worst, abs(t - hug(i)%t)/hug(i)%t )
   end if
end do
call check( worst <= rtol, itoa(size(hug))//' Hugoniot temperatures to '// &
   '1e-12' )
write(*,'(a,es8.1)') '         worst relative error: ', worst

!=====================================================================!
! 9. Units, end to end: the deck's CV in J/(g K) becomes kJ/(g K) in
!    the layer table (module deck), and then at V0 an energy of
!    0.11633418 kJ/g = 116.33418 J/g over CV = 1.1633418 J/(g K) is
!    100 K above T0: T = 398 K, by hand. The deck is the test deck
!    tests/decks/ok_temperature.deck (MatX and PMMA carry T, Al not).
!=====================================================================!
call read_deck( 'tests/decks/ok_temperature.deck', ierr )
ok = ( ierr == 0 .and. nlay == 3 )
if ( ok ) then
   ok = layer(1)%eos == eos_mie_gruneisen .and. &
        .not. ( abs(layer(1)%cv) > zero ) .and. &
        layer(2)%eos == eos_mie_gruneisen_t .and. &
        layer(3)%eos == eos_mie_gruneisen_t
end if
call check( ok, 'units: the deck reads, and its models are Al '// &
   'mie_gruneisen, MatX and PMMA mie_gruneisen_t' )
if ( ok ) then
   t = temp_of( zero, 0.11633418_dp, zero, layer(2)%G0, layer(2)%cv, &
      layer(2)%T0 )
   ok = abs(layer(2)%cv - 1.1633418e-3_dp) <= 4.0_dp*epsilon(one)* &
      1.1633418e-3_dp .and. abs(t - 398.0_dp) <= 1.0e-10_dp
end if
call check( ok, 'units: CV = 1.1633418 J/(g K) is 1.1633418e-3 kJ/(g K) '// &
   'inside, and 0.11633418 kJ/g at V0 is T0 + 100 K' )

!=====================================================================!
! Summary. Exit status 1 on any failure, so 'make test' stops.
!=====================================================================!
if ( nfail > 0 ) then
   write(*,'(a,i0,a,i0,a)') ' test_temp: ', nfail, ' of ', ncheck, &
      ' checks FAILED'
   call quit( 1 )
end if
write(*,'(a,i0,a)') ' test_temp: all ', ncheck, ' checks passed'

contains

   !*** One cold step for material mm, from eta1 to eta2.
   subroutine step( mm, e1, e2, ec_in, ec_out, ie )
   implicit none
   integer(kind=int32), intent(in) :: mm
   real(kind=dp), intent(in) :: e1, e2, ec_in
   real(kind=dp), intent(out) :: ec_out
   integer(kind=int32), intent(out) :: ie
   call cold_step( e1, e2, ec_in, mat(1,mm), mat(2,mm), mat(3,mm), &
      mat(4,mm), mat(5,mm), ec_out, ie )
   end subroutine step

      !*** The hard path's j-th eta (section 6).
   real(kind=dp) function hard_path( jj )
   implicit none
   integer(kind=int32), intent(in) :: jj
   real(kind=dp), save :: top            ! where the ringing ended
   if ( jj <= 4 ) then                   ! the shock
      hard_path = 0.25_dp*( real(jj,dp)/4.0_dp )
   else if ( jj <= 2004 ) then           ! the ringing
      hard_path = 0.225_dp + 0.075_dp*sin( 0.37_dp*real(jj-4,dp) )* &
         cos( 0.011_dp*real(jj-4,dp) )
      top = hard_path
   else if ( jj < 2054 ) then            ! the release
      hard_path = top + ( -0.2_dp - top )*( real(jj-2004,dp)/50.0_dp )
   else if ( jj == 2054 ) then
      hard_path = -0.2_dp                ! exactly, to compare
   else if ( jj < 2061 ) then            ! back
      hard_path = -0.2_dp + 0.3_dp*( real(jj-2054,dp)/7.0_dp )
   else
      hard_path = 0.1_dp                 ! exactly, to compare
   end if
   end function hard_path

   !*** The reference e_c of material mm at eta (from the ref table).
   real(kind=dp) function ref_ec( mm, eta )
   implicit none
   integer(kind=int32), intent(in) :: mm
   real(kind=dp), intent(in) :: eta
   integer(kind=int32) :: n
   ref_ec = huge(one)
   do n = 1, size(ref)
      if ( ref(n)%m == mm .and. .not. ( abs(ref(n)%eta - eta) > zero ) ) &
         ref_ec = ref(n)%ec
   end do
   end function ref_ec

   !*** Score one result against its reference: the worst relative
   !*** error so far, and a count of misses (a failed step is a miss).
   subroutine score( ie, got, want, wst, nb )
   implicit none
   integer(kind=int32), intent(in) :: ie
   real(kind=dp), intent(in) :: got, want
   real(kind=dp), intent(inout) :: wst
   integer(kind=int32), intent(inout) :: nb
   if ( ie /= eos_ok ) then
      nb = nb + 1
      return
   end if
   err = abs(got - want)/abs(want)
   wst = max( wst, err )
   if ( err > rtol ) nb = nb + 1
   end subroutine score

   !*** Count one check, and print it.
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

   !*** An integer as text, without padding.
   function itoa( n ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim(buf)
   end function itoa

end program test_temp

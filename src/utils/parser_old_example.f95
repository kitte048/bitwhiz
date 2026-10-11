subroutine parser(fname,ui,kerr,echo)
!**********************************************************************!
!
!  Purpose:
!    Initialize the user input "ui" array from file.
!
use shared_data
implicit none
integer(kind=long) :: i,j,k,l,m,n      ! save for index counting
integer(kind=long) :: ierror           ! file I/O error counter
integer(kind=long), intent(inout) :: kerr ! integer error counter
character(len=32), intent(in) :: fname  ! file name
character(len=80) :: fline              ! one line from a file
character(len=80) :: cc                 ! left-justified file line
real(kind=dp), dimension(100), &
   intent(inout) :: ui(100)   ! user input array
real(kind=dp) :: val
integer(kind=short) :: ng,ii
integer(kind=short), intent(in) :: echo ! enable verbose output
 
!                                         0         1         2
! KEWARGS (string values)                 012345678901234567890
character(len=2),  parameter :: png     = 'ng'
character(len=5),  parameter :: pelem   = 'nelem'
character(len=6),  parameter :: psimdt  = 'sim_dt'
character(len=6),  parameter :: psimm0  = 'sim_m0'
character(len=8),  parameter :: propr   = 'prop_rho'
character(len=6),  parameter :: propn   = 'prop_n'
character(len=6),  parameter :: propa   = 'prop_a'
character(len=6),  parameter :: propb   = 'prop_b'
character(len=6),  parameter :: propc   = 'prop_c'
character(len=6),  parameter :: propk   = 'prop_k'
character(len=8),  parameter :: propisp = 'prop_isp'
character(len=7),  parameter :: propcf  = 'prop_cf'
character(len=8),  parameter :: propgam = 'prop_gam'
character(len=10), parameter :: pgap1   = 'grain_gap1'
character(len=10), parameter :: pgap2   = 'grain_gap2'
character(len=10), parameter :: pgap3   = 'grain_gap3'
character(len=10), parameter :: pgap4   = 'grain_gap4'
character(len=10), parameter :: pgap5   = 'grain_gap5'
character(len=10), parameter :: pgap6   = 'grain_gap6'
character(len=10), parameter :: pgap7   = 'grain_gap7'
character(len=10), parameter :: pgap8   = 'grain_gap8'
character(len=10), parameter :: pgap9   = 'grain_gap9'
character(len=11), parameter :: pgap10  = 'grain_gap10'
character(len=10), parameter :: plen1   = 'grain_len1'
character(len=10), parameter :: plen2   = 'grain_len2'
character(len=10), parameter :: plen3   = 'grain_len3'
character(len=10), parameter :: plen4   = 'grain_len4'
character(len=10), parameter :: plen5   = 'grain_len5'
character(len=10), parameter :: plen6   = 'grain_len6'
character(len=10), parameter :: plen7   = 'grain_len7'
character(len=10), parameter :: plen8   = 'grain_len8'
character(len=10), parameter :: plen9   = 'grain_len9'
character(len=11), parameter :: plen10  = 'grain_len10'
character(len=10), parameter :: prad1   = 'grain_rad1'
character(len=10), parameter :: prad2   = 'grain_rad2'
character(len=10), parameter :: prad3   = 'grain_rad3'
character(len=10), parameter :: prad4   = 'grain_rad4'
character(len=10), parameter :: prad5   = 'grain_rad5'
character(len=10), parameter :: prad6   = 'grain_rad6'
character(len=10), parameter :: prad7   = 'grain_rad7'
character(len=10), parameter :: prad8   = 'grain_rad8'
character(len=10), parameter :: prad9   = 'grain_rad9'
character(len=11), parameter :: prad10  = 'grain_rad10'
character(len=6),  parameter :: psrmlc  = 'srm_lc'
character(len=6),  parameter :: psrmr0  = 'srm_r0'
character(len=9),  parameter :: ptwall  = 'srm_twall'
character(len=9),  parameter :: ptheta  = 'srm_theta'
character(len=6),  parameter :: psrmrt  = 'srm_rt'
character(len=6),  parameter :: psrmtt  = 'srm_tt'
character(len=8),  parameter :: pldnz   = 'srm_ldnz'
character(len=8),  parameter :: paeac   = 'srm_aeac'

! KEWARGS (string length)
integer(kind=long), parameter :: nng      = 2
integer(kind=long), parameter :: nelem    = 5
integer(kind=long), parameter :: nsimdt   = 6
integer(kind=long), parameter :: nsimm0   = 6
integer(kind=long), parameter :: npropr   = 8
integer(kind=long), parameter :: npropn   = 6
integer(kind=long), parameter :: npropa   = 6
integer(kind=long), parameter :: npropb   = 6
integer(kind=long), parameter :: npropc   = 6
integer(kind=long), parameter :: npropk   = 6
integer(kind=long), parameter :: npropisp = 8
integer(kind=long), parameter :: npropcf  = 7
integer(kind=long), parameter :: npropgam = 8
integer(kind=long), parameter :: ngap1    = 10
integer(kind=long), parameter :: ngap2    = 10
integer(kind=long), parameter :: ngap3    = 10
integer(kind=long), parameter :: ngap4    = 10
integer(kind=long), parameter :: ngap5    = 10
integer(kind=long), parameter :: ngap6    = 10
integer(kind=long), parameter :: ngap7    = 10
integer(kind=long), parameter :: ngap8    = 10
integer(kind=long), parameter :: ngap9    = 10
integer(kind=long), parameter :: ngap10   = 11
integer(kind=long), parameter :: nlen1    = 10
integer(kind=long), parameter :: nlen2    = 10
integer(kind=long), parameter :: nlen3    = 10
integer(kind=long), parameter :: nlen4    = 10
integer(kind=long), parameter :: nlen5    = 10
integer(kind=long), parameter :: nlen6    = 10
integer(kind=long), parameter :: nlen7    = 10
integer(kind=long), parameter :: nlen8    = 10
integer(kind=long), parameter :: nlen9    = 10
integer(kind=long), parameter :: nlen10   = 11
integer(kind=long), parameter :: nrad1    = 10
integer(kind=long), parameter :: nrad2    = 10
integer(kind=long), parameter :: nrad3    = 10
integer(kind=long), parameter :: nrad4    = 10
integer(kind=long), parameter :: nrad5    = 10
integer(kind=long), parameter :: nrad6    = 10
integer(kind=long), parameter :: nrad7    = 10
integer(kind=long), parameter :: nrad8    = 10
integer(kind=long), parameter :: nrad9    = 10
integer(kind=long), parameter :: nrad10   = 11
integer(kind=long), parameter :: nsrmlc   = 6
integer(kind=long), parameter :: nsrmr0   = 6
integer(kind=long), parameter :: ntwall   = 9
integer(kind=long), parameter :: ntheta   = 9
integer(kind=long), parameter :: nsrmrt   = 6
integer(kind=long), parameter :: nsrmtt   = 6
integer(kind=long), parameter :: nldnz    = 8
integer(kind=long), parameter :: naeac    = 8

! Formatted I/O statements.
100  format(1(' '))
101  format(1(a55))
102  format(1(a22),1(a32))
103  format(1(a60))
104  format(1(a18),1(1es12.5),1(a23))
105  format(1(a18),1(i1))
106  format(1(a22),1(1es12.5),1(a6))
107  format('[BEC] found input file: ',1(a32))
108  format('[BEC] ERROR reading file: ',1(a32))

! Zero the user input "ui" array.
do i=1,100,1
   ui(i)=zero
end do

! Double-check if the input deck exists.
open(unit=55,file=fname,status='old',action='read',iostat=ierror)
if (ierror==0) then

   do while (ierror==0)
      read(unit=55,fmt='(1(a80))',iostat=ierror) fline
      write(kpt6,'(1(a80))') fline

      ! Read in KEWARG values here.
      cc=adjustl(fline)

      ! No. 1-9 are simulation settings.
      if (cc(1:nng)==png) then
         call getval(cc,val,echo)
         ui(1)=val
      else if (cc(1:nelem)==pelem) then
         call getval(cc,val,echo)
         ui(2)=val
      else if (cc(1:nsimdt)==psimdt) then
         call getval(cc,val,echo)
         ui(3)=val
      else if (cc(1:nsimm0)==psimm0) then
         call getval(cc,val,echo)
         ui(4)=val

      ! No. 10-19 are for the grain gaps.
      else if (cc(1:ngap1)==pgap1.and.&
               cc(1:ngap10).ne.pgap10) then
         call getval(cc,val,echo)
         ui(10)=val
      else if (cc(1:ngap2)==pgap2) then
         call getval(cc,val,echo)
         ui(11)=val
      else if (cc(1:ngap3)==pgap3) then
         call getval(cc,val,echo)
         ui(12)=val
      else if (cc(1:ngap4)==pgap4) then
         call getval(cc,val,echo)
         ui(13)=val
      else if (cc(1:ngap5)==pgap5) then
         call getval(cc,val,echo)
         ui(14)=val
      else if (cc(1:ngap6)==pgap6) then
         call getval(cc,val,echo)
         ui(15)=val
      else if (cc(1:ngap7)==pgap7) then
         call getval(cc,val,echo)
         ui(16)=val
      else if (cc(1:ngap8)==pgap8) then
         call getval(cc,val,echo)
         ui(17)=val
      else if (cc(1:ngap9)==pgap9) then
         call getval(cc,val,echo)
         ui(18)=val
      else if (cc(1:ngap10)==pgap10) then
         call getval(cc,val,echo)
         ui(19)=val

      ! No. 20-29 are for the grain lengths. 
      else if (cc(1:nlen1)==plen1.and.&
               cc(1:nlen10).ne.plen10) then
         call getval(cc,val,echo)
         ui(20)=val
      else if (cc(1:nlen2)==plen2) then
         call getval(cc,val,echo)
         ui(21)=val
      else if (cc(1:nlen3)==plen3) then
         call getval(cc,val,echo)
         ui(22)=val
      else if (cc(1:nlen4)==plen4) then
         call getval(cc,val,echo)
         ui(23)=val
      else if (cc(1:nlen5)==plen5) then
         call getval(cc,val,echo)
         ui(24)=val
      else if (cc(1:nlen6)==plen6) then
         call getval(cc,val,echo)
         ui(25)=val
      else if (cc(1:nlen7)==plen7) then
         call getval(cc,val,echo)
         ui(26)=val
      else if (cc(1:nlen8)==plen8) then
         call getval(cc,val,echo)
         ui(27)=val
      else if (cc(1:nlen9)==plen9) then
         call getval(cc,val,echo)
         ui(28)=val
      else if (cc(1:nlen10)==plen10) then
         call getval(cc,val,echo)
         ui(29)=val

      ! No. 30-39 are for the grain inner radii.
      else if (cc(1:nrad1)==prad1.and.&
               cc(1:nrad10).ne.prad10) then
         call getval(cc,val,echo)
         ui(30)=val
      else if (cc(1:nrad2)==prad2) then
         call getval(cc,val,echo)
         ui(31)=val
      else if (cc(1:nrad3)==prad3) then
         call getval(cc,val,echo)
         ui(32)=val
      else if (cc(1:nrad4)==prad4) then
         call getval(cc,val,echo)
         ui(33)=val
      else if (cc(1:nrad5)==prad5) then
         call getval(cc,val,echo)
         ui(34)=val
      else if (cc(1:nrad6)==prad6) then
         call getval(cc,val,echo)
         ui(35)=val
      else if (cc(1:nrad7)==prad7) then
         call getval(cc,val,echo)
         ui(36)=val
      else if (cc(1:nrad8)==prad8) then
         call getval(cc,val,echo)
         ui(37)=val
      else if (cc(1:nrad9)==prad9) then
         call getval(cc,val,echo)
         ui(38)=val
      else if (cc(1:nrad10)==prad10) then
         call getval(cc,val,echo)
         ui(39)=val

      ! No. 40-50 are for the motor design.
      else if (cc(1:nsrmlc)==psrmlc) then
         call getval(cc,val,echo)
         ui(40)=val
      else if (cc(1:nsrmr0)==psrmr0) then
         call getval(cc,val,echo)
         ui(41)=val
      else if (cc(1:ntwall)==ptwall) then
         call getval(cc,val,echo)
         ui(42)=val
      else if (cc(1:ntheta)==ptheta) then
         call getval(cc,val,echo)
         ui(43)=val
      else if (cc(1:nsrmrt)==psrmrt) then
         call getval(cc,val,echo)
         ui(44)=val
      else if (cc(1:nsrmtt)==psrmtt) then
         call getval(cc,val,echo)
         ui(45)=val
      else if (cc(1:nldnz)==pldnz) then
         call getval(cc,val,echo)
         ui(46)=val
      else if (cc(1:naeac)==paeac) then
         call getval(cc,val,echo)
         ui(47)=val

      ! No. 60-70 are for the propellant data.
      else if (cc(1:npropr)==propr) then
         call getval(cc,val,echo)
         ui(60)=val
      else if (cc(1:npropn)==propn) then
         call getval(cc,val,echo)
         ui(61)=val
      else if (cc(1:npropa)==propa) then
         call getval(cc,val,echo)
         ui(62)=val
      else if (cc(1:npropk)==propk) then
         call getval(cc,val,echo)
         ui(63)=val
      else if (cc(1:npropisp)==propisp) then
         call getval(cc,val,echo)
         ui(64)=val
      else if (cc(1:npropcf)==propcf) then
         call getval(cc,val,echo)
         ui(65)=val
      else if (cc(1:npropgam)==propgam) then
         call getval(cc,val,echo)
         ui(66)=val
      else if (cc(1:npropb)==propb) then
         call getval(cc,val,echo)
         ui(67)=val
      else if (cc(1:npropc)==propc) then
         call getval(cc,val,echo)
         ui(68)=val
      end if
   end do

   ! Calculate the derived parameters.
   ng = nint(ui(1))
   ui(48) = ui(40) + two*ui(41)*ui(46)  ! srm_ltot=<...>
   ui(49) = pi*ui(43)/(two*nin*ten)     ! srm_thetar=<...>
   ui(50) = (ui(41)-ui(44))*tan(ui(49)) ! srm_lnz=<...>
   ui(5)  = ui(48)/(one*nint(ui(2)))    ! sim_dx=<...>

   ! Echo user input to the terminal.
   if (echo==1) then
      write(*,103) "ECHO Propellant Information:                          "
      write(*,104) "     rho  = ",ui(60)         ," [lbm/in^3]            "
      write(*,104) "     n    = ",ui(61)         ,"                       "
      write(*,104) "     a    = ",ui(62)         ," [in/sec/psia^n]       "
      write(*,104) "     k    = ",ui(63)         ,"                       "
      write(*,104) "     Isp  = ",ui(64)         ," [sec]                 "
      write(*,104) "     Cf   = ",ui(65)         ,"                       "
      write(*,104) "     gam  = ",ui(66)         ,"                       "
      write(*,104) "     b    = ",ui(67)         ,"                       "
      write(*,104) "     c    = ",ui(68)         ,"                       "
      write(*,103) "                                                      "
      write(*,103) "ECHO Motor Design Parameters:                         "
      write(*,104) "     lc   = ",ui(40)         ," [in]                  "
      write(*,104) "     r0   = ",ui(41)         ," [in]                  "
      write(*,104) "     twall= ",ui(42)         ," [in]                  "
      write(*,104) "     theta= ",ui(43)         ," [deg]                 "
      write(*,104) "     rt   = ",ui(44)         ," [in]                  "
      write(*,104) "     tt   = ",ui(45)         ," [in]                  "
      write(*,104) "     lnz  = ",ui(50)         ," [in]                  "
      write(*,104) "     LDnz = ",ui(46)         ,"                       "
      write(*,104) "     AeAc = ",ui(47)         ,"                       "
      write(*,103) "                                                      "
      write(*,103) "ECHO Bates Grain Dimensions:                          "
      do ii=1,ng,1
         write(*,105) "    Grain #",ii
         write(*,106) "         gap = ",ui( 9+ii)," [in] "
         write(*,106) "         len = ",ui(19+ii)," [in] "
         write(*,106) "         ri  = ",ui(29+ii)," [in] "
      end do
      write(*,103) "                                                      "
      write(*,103) "ECHO Simulation Controls:                             "
      write(*,104) "     dx   = ",ui(5)          ," [in]                  "
      write(*,104) "     dt   = ",ui(3)          ," [sec]                 "
      write(*,104) "     M0   = ",ui(4)          ,"                       "
      write(*,103) "                                                      "
   end if
else
   kerr=kerr+1
   write(kpt6,108) fname
end if
close(55)

end subroutine parser

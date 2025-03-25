program bitwhiz
use bits, only: int32,dp,kpt6,nline
implicit none
integer(kind=int32) :: idx,n,nx,ny
real(kind=dp) :: cpu1,cpu2
character(len=nline) :: aname,f
character(len=80) :: cmap
cmap = ' ' ! default

201 format("CPU Elapsed Time = ",1(1f15.3)," seconds")
202 format(1(1es15.5))

! Command Line Execution.
n = command_argument_count()

! Loop over the execution line parameters.
found_params: if (n>0) then

 call timestamp( cpu1 ) !~ save for reference.

 loop_params: do idx=1,n,1

  call get_command_argument(idx,aname)

  select_params: select case(adjustl(aname))

   ! ...
   case("-grayscale")
    cmap = "grayscale"
   case("-plasma")
    cmap = "plasma"
   case("-viridis")
    cmap = "viridis"
   case("-inferno")
    cmap = "inferno"
   case("-blackbody")
    nx = 1
   case("-kindlmann")
    nx = 1
   case("-ekindlmann")
    nx = 1
   case("-smoothcw")
    nx = 1
   case("-bentcw")
    ny = 1

  end select select_params
 end do loop_params

 call timestamp( cpu2 ) !~ save for reference

 write( kpt6, 201 ) cpu2-cpu1 !~ save for reference

! No command line arguments were found.
else
 ! 1234567890123456789012345678901234567890123456789012345
 write(kpt6,'(1(a55))') &
  "usage: bitwhiz [-colormap] [-RGB_flip]                 "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "  [-colormap]  is a named color map, lowercase:        "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "    -bentcw       BLUE-WHITE-RED, BENT COOLWARM        "
 write(kpt6,'(1(a55))') &
  "    -blackbody    BLACK-RED-ORANGE-YELLOW-WHITE        "
 write(kpt6,'(1(a55))') &
  "    -ekindlmann   BLACK-BLUE-GREEN-YELLOW-PEACH-PINK-W "
 write(kpt6,'(1(a55))') &
  "    -grayscale    BLACK-WHITE, MATHEMATICALLY LINEAR   "
 write(kpt6,'(1(a55))') &
  "    -inferno      BLACK-PURPLE-PINK-ORANGE-YELLOW      "
 write(kpt6,'(1(a55))') &
  "    -kindlmann    BLACK-BLUE-GREEN-YELLOW-PALE         "
 write(kpt6,'(1(a55))') &
  "    -plasma       BLUE-PURPLE-PEACH-ORANGE-YELLOW      "
 write(kpt6,'(1(a55))') &
  "    -smoothcw     BLUE-WHITE-RED, SMOOTH COOLWARM      "
 write(kpt6,'(1(a55))') &
  "    -viridis      PURPLE-BLUE-GREEN-YELLOW             "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "  [-RGB_flip]  allows you to do a permutation on RGB   "
 write(kpt6,'(1(a55))') &
  "               vals in a color map to see what happens:"
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "    -123          DEFAULT if none specified; i.e., RGB "
 write(kpt6,'(1(a55))') &
  "    -132            permutation that takes RGB --> GRB "
 write(kpt6,'(1(a55))') &
  "    -213            permutation that takes RGB --> RBG "
 write(kpt6,'(1(a55))') &
  "    -231            permutation that takes RGB --> BRG "
 write(kpt6,'(1(a55))') &
  "    -312            permutation that takes RGB --> GBR "
 write(kpt6,'(1(a55))') &
  "    -321            permutation that takes RGB --> BGR "

end if found_params
write(*,*) cmap
end program bitwhiz

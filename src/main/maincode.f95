program bitwhiz
use bits, only: int16,int32,dp,kpt6,nline
implicit none
integer(kind=int32) :: idx,n,nx,ny
integer(kind=int16) :: npr=1                           ! permutation
real(kind=dp) :: cpu1,cpu2
character(len=nline) :: aname,f
character(len=80) :: cmap
cmap = ' ' ! default

201 format("CPU Elapsed Time = ",1(1f15.3)," seconds")
202 format(1(1es15.5))

! Command Line Execution.
n = command_argument_count()

!==========================================!
! Loop over the execution line parameters. !
!==========================================!
found_params: if (n>0) then

 call timestamp( cpu1 ) !~ save for reference.

 loop_params: do idx=1,n,1

  call get_command_argument(idx,aname)

  !======================================================!
  ! Loop over cases that are INDEPENDENT of other cases. !
  !======================================================!
  select_params: select case(adjustl(aname))

   ! ... Under Construction ...
   case("-bentcw")
      cmap(1:17)='bentcoolwarm1,2,3'
   case("-blackbody")
      cmap(1:14)='blackbody1,2,3'
   case("-ekindlmann")
      cmap(1:22)='extendedkindlmann1,2,3'
   case("-grayscale")
      cmap(1:9)='grayscale'
   case("-inferno")
      cmap(1:12)='inferno1,2,3'
   case("-kindlmann")
      cmap(1:14)='kindlmann1,2,3'
   case("-plasma")
      cmap(1:11)='plasma1,2,3'
   case("-smoothcw")
      cmap(1:19)='smoothcoolwarm1,2,3'
   case("-viridis")
      cmap(1:12)='viridis1,2,3'
   case("-123")
      npr=1
   case("-132")
      npr=2
   case("-213")
      npr=3
   case("-231")
      npr=4
   case("-312")
      npr=5
   case("-321")
      npr=6

   ! Draw color maps.
   case("-allmaps")
    call draw_colormaps()

  end select select_params
 end do loop_params

!=======================================!
! No command line arguments were found. !
!=======================================!
!
! Put the help menu here.
else
 ! 1234567890123456789012345678901234567890123456789012345
 write(kpt6,'(1(a55))') &
  "usage: bitwhiz [-colormap] [-RGB_flip] [-allmaps]      "
 write(kpt6,'(1(a55))') &
  "          [-showmap]                                   "
 write(kpt6,'(1(a55))') &
  "                                                       "
!=========================================!
! Help menu for the different color maps. !
!=========================================!
 write(kpt6,'(1(a55))') &
  "  [-colormap]  is a named color map, lowercase:        "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "   -bentcw       BLUE-WHITE-RED, BENT*                 "
 write(kpt6,'(1(a55))') &
  "   -blackbody    BLACK-RED-ORANGE-YELLOW-WHITE*        "
 write(kpt6,'(1(a55))') &
  "   -ekindlmann   BLACK-BLUE-GREEN-YELLOW-PEACH-PINK-W* "
 write(kpt6,'(1(a55))') &
  "   -grayscale    BLACK-WHITE, LINEAR^^                 "
 write(kpt6,'(1(a55))') &
  "   -inferno      BLACK-PURPLE-PINK-ORANGE-YELLOW*      "
 write(kpt6,'(1(a55))') &
  "   -kindlmann    BLACK-BLUE-GREEN-YELLOW-PALE*         "
 write(kpt6,'(1(a55))') &
  "   -plasma       BLUE-PURPLE-PEACH-ORANGE-YELLOW*      "
 write(kpt6,'(1(a55))') &
  "   -smoothcw     BLUE-WHITE-RED, SMOOTH*               "
 write(kpt6,'(1(a55))') &
  "   -viridis      PURPLE-BLUE-GREEN-YELLOW*             "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "     key:                                              "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "      * RGB Values are 64-bit (8 byte), 1024 colors    "
 write(kpt6,'(1(a55))') &
  "      ^^ RGB Values are integers (R=G=B), 256 colors   "
 write(kpt6,'(1(a55))') &
  "                                                       "
!=====================================!
! Help menu for the RGB permutations. !
!=====================================!
 write(kpt6,'(1(a55))') &
  "  [-RGB_flip]  allows you to do a permutation on RGB   "
 write(kpt6,'(1(a55))') &
  "               in a color map to see what happens:     "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "   -123          DEFAULT if none specified; i.e., RGB  "
 write(kpt6,'(1(a55))') &
  "   -132          permutation....................(GR)B  "
 write(kpt6,'(1(a55))') &
  "   -213          permutation....................(RB)G  "
 write(kpt6,'(1(a55))') &
  "   -231          permutation....................(BR)G  "
 write(kpt6,'(1(a55))') &
  "   -312          permutation....................(GB)R  "
 write(kpt6,'(1(a55))') &
  "   -321          permutation....................(BG)R  "
 write(kpt6,'(1(a55))') &
  "                                                       "
! ...
 write(kpt6,'(1(a55))') &
  "  [-allmaps]   draws every available color map in the  "
 write(kpt6,'(1(a55))') &
  "               bitwhiz code, including permutations    "
 write(kpt6,'(1(a55))') &
  "                                                       "
 write(kpt6,'(1(a55))') &
  "  [-showmap]   draws current color map, if specified   "
 write(kpt6,'(1(a55))') &
  "                                                       "

end if found_params

!====================================!
! Run a program based on user input. !
!====================================!
run_program: if (n>0) then

   ! Apply color map permutations.
   if (npr>1.and.cmap(1:9).ne.'grayscale') then
      do idx=1,70,1
         if (cmap(idx:idx+4).eq.'1,2,3') then
            if (npr.eq.2) then
               cmap(idx:idx+4)='1,3,2'
            else if (npr.eq.3) then
               cmap(idx:idx+4)='2,1,3'
            else if (npr.eq.4) then
               cmap(idx:idx+4)='2,3,1'
            else if (npr.eq.5) then
               cmap(idx:idx+4)='3,1,2'
            else if (npr.eq.6) then
               cmap(idx:idx+4)='3,2,1'
            end if
         end if
      end do
   end if

   loop_params_2: do idx=1,n,1

    call get_command_argument(idx,aname)

    !=============================================!
    ! Loop over cases that DEPEND on other cases. !
    !=============================================!
    select_params_2: select case(adjustl(aname))

     ! Draw current color map.
     case("-showmap")
      call draw_singlemap(cmap)

     ! Draw the blobs demo code.
     case("-draw_blobs")
      call draw_blobs(cmap)

     ! Draws the potential flow around a cylinder (Under Construction).
     case("-draw_cylflow")
      call draw_cylflow(cmap)

     ! Recolor Image (Under Construction).
     case("-recolor")
       call recolor(cmap)

    end select select_params_2

   end do loop_params_2

   !=======================================!
   ! Compute CPU time and write to screen. !
   !=======================================!
   call timestamp( cpu2 )

   write( kpt6, 201 ) cpu2-cpu1

end if run_program


end program bitwhiz

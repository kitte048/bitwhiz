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
 write(kpt6,'(1(a49))') &
  "usage: bitwhiz [-grayscale] [-plasma] [-viridis]"
 write(kpt6,'(1(a52))') &
  "  [-inferno] [-blackbody] [-kindlmann] [-ekindlmann]"
 write(kpt6,'(1(a51))') &
  "  [-smoothcw] [-bentcw] [-123] [-132] [-213] [-231]"
 write(kpt6,'(1(a49))') &
  "  [-312] [-321]                                  "

end if found_params
write(*,*) cmap
end program bitwhiz

program bitwhiz
use bits, only: dp,kpt6
implicit none
real(kind=dp) :: cpu1,cpu2
character(len=80) :: cmap
cmap = ' ' ! default

201 format("CPU Elapsed Time = ",1(1f15.3)," seconds")

call timestamp( cpu1 ) !~ save for reference.

!==================!
! Draw color maps. !
!==================!
call draw_colormaps()

!=======================================!
! Compute CPU time and write to screen. !
!=======================================!
call timestamp( cpu2 )

write( kpt6, 201 ) cpu2-cpu1

end program bitwhiz

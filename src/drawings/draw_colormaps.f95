subroutine draw_colormaps()
!**********************************************************************!
!  About:                                                              !
!    Single routine to draw all pre-programmed color maps.             !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    11/25/23    D. E. Kittell      Original code                      !
!    10/06/26    Claude (for DEK)   F2018 clean: character(len=),      !
!                                   allocatable fcn/RGB, drop int64    !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6,one
implicit none

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32) :: i,j,k
integer(kind=int32) :: istat            ! allocation status
integer(kind=int32), parameter :: nx=768
integer(kind=int32), parameter :: ny=96
real(kind=dp), dimension(:,:), allocatable :: fcn       ! real vals [0,1]
character(len=1), dimension(:,:,:), allocatable :: RGB  ! RGB (optional)
character(len=80) :: bout
character(len=80) :: cmap
character(len=5), dimension(6), parameter :: idx = &
(/ '1,2,3' , '1,3,2' , '2,1,3' , '2,3,1' , '3,1,2' , '3,2,1' /)

!*** Allocate the image arrays (too large for the stack).
allocate( fcn(nx,ny), RGB(nx,ny,3), stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_colormaps could not allocate the image.'
   return
end if

!*** Make the image and write to file.
do i=1,nx,1
   do j=1,ny,1
      fcn( i, j ) = ( i - one ) / ( nx - one )
   end do
end do

!*** Grayscale Color Bar.

write(kpt6,*) " - - - - - -"
bout = 'Grayscale'
cmap = 'grayscale'
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
write(kpt6,*) " - - - - - -"

!*** All other color bars may be permuted.
do k=1,6,1
   bout = 'Smoothcoolwarm' // idx(k)
   cmap = 'smoothcoolwarm' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Bentcoolwarm' // idx(k)
   cmap = 'bentcoolwarm' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Viridis' // idx(k)
   cmap = 'viridis' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Plasma' // idx(k)
   cmap = 'plasma' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Blackbody' // idx(k)
   cmap = 'blackbody' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Inferno' // idx(k)
   cmap = 'inferno' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Kindlmann' // idx(k)
   cmap = 'kindlmann' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Extendedkindlmann' // idx(k)
   cmap = 'extendedkindlmann' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
end do

deallocate( fcn, RGB )

return
end subroutine

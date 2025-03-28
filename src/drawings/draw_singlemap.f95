subroutine draw_singlemap(cmap)
!**********************************************************************!
!  About:                                                              !
!    Single routine to draw the current color maps.                    !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    03/27/25    D. E. Kittell      Original code                      !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6,one
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
character(len=80), intent(inout) :: cmap           ! string params

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32) :: i,j
integer(kind=int32), parameter :: nx=768
integer(kind=int32), parameter :: ny=96
real(kind=dp), dimension(nx,ny) :: fcn     ! real vals [0,1]
character*1, dimension(nx,ny,3) :: RGB     ! RGB (optional)
character*80 :: bout

!*** Make the image and write to file.
do i=1,nx,1
   do j=1,ny,1
      fcn( i, j ) = ( i - one ) / ( nx - one )
   end do
end do

!*** Make the file name to be the same as draw_colormaps.
bout = 'DEFAULT'
name_check: if (cmap(1:4).eq."bent") then
   bout(1:17) = cmap(1:17)
   bout(1:1) = 'B'
else if (cmap(1:4).eq."blac") then
   bout(1:14) = cmap(1:14)
   bout(1:1) = 'B'
else if (cmap(1:4).eq."exte") then
   bout(1:22) = cmap(1:22)
   bout(1:1) = 'E'
else if (cmap(1:4).eq."gray") then
   bout(1:9) = cmap(1:9)
   bout(1:1) = 'G'
else if (cmap(1:4).eq."infe") then
   bout(1:12) = cmap(1:12)
   bout(1:1) = 'I'
else if (cmap(1:4).eq."kind") then
   bout(1:14) = cmap(1:14)
   bout(1:1) = 'K'
else if (cmap(1:4).eq."plas") then
   bout(1:11) = cmap(1:11)
   bout(1:1) = 'P'
else if (cmap(1:4).eq."smoo") then
   bout(1:19) = cmap(1:19)
   bout(1:1) = 'S'
else if (cmap(1:4).eq."viri") then
   bout(1:12) = cmap(1:12)
   bout(1:1) = 'V'
else
   cmap(1:9) = 'grayscale'
end if name_check


write(kpt6,*) " - - - - - -"
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
write(kpt6,*) " - - - - - -"

return
end subroutine

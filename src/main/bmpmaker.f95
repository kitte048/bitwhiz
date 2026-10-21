subroutine bmpmaker(nx,ny,fcn,RGB,bout,cmap)
!**********************************************************************!
!  About:                                                              !
!    BMPMAKER is the executive routine that makes ".bmp" files.        !
!                                                                      !
!  Purpose:                                                            !
!    To convert a real-valued function (via colormaps), or             !
!    RGB values into a properly formatted ".bmp" file.                 !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    11/19/23    D. E. Kittell      Started over from bitart project.  !
!    10/06/26    Claude (for DEK)   F2018 clean: character(len=1),     !
!                                   explicit int16 for ilast, set the  !
!                                   row padding bytes to zero          !
!    10/13/26    Claude (for DEK)   Loop indices and istat are local   !
!                                   (were shared in module bits); the  !
!                                   channel order npr is int16, as the !
!                                   colormap routines expect           !
!    10/20/26    Claude (for DEK)   The colormap choice moved, as it   !
!                                   was, into apply_colormap (below),  !
!                                   so a caller can color an image,    !
!                                   then change pixels (draw_xt), and  !
!                                   pass RGB with no colormap ('rgb')  !
!                                                                      !
!**********************************************************************!
use bits, only: dp,int8,int16,int32,one,thr,for,eig,ten, &
                bfType,bfSize,bfReserved1,bfReserved2,bfOffBits, &
                biSize,biWidth,biHeight,biPlanes,biBitCount, &
                biCompression,biSizeImage,biXPelsPerMeter, &
                biYPelsPerMeter,biClrUsed,biClrImportant, kpt6
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
character(len=80), intent(in) :: bout,cmap             ! string params
integer(kind=int32), intent(in) :: nx,ny               ! dimensions
real(kind=dp), dimension(nx,ny), intent(in) :: fcn     ! values [0,1]
character(len=1), dimension(nx,ny,3), intent(inout) :: RGB  ! (optional)

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.
!**********************************************************************!
character(len=80) :: bfile                             ! name w/ ".bmp"
integer(kind=int16), parameter :: uu=77                ! file ID
integer(kind=int16), parameter :: ibeg=1               ! string parse
integer(kind=int16), parameter :: iend=80              ! string parse
integer(kind=int16) :: ilast                           ! string parse
integer(kind=int32) :: BitsPerPixel, &
   RowSize1,RowSize2,nzp                               ! integers
integer(kind=int8), dimension(:), allocatable :: zpad  ! zero pad
integer(kind=int32) :: i,j                             ! loop indices
integer(kind=int32) :: istat                           ! open() status

! Set image dimensions.
biWidth=nx
biHeight=ny
BitsPerPixel=biBitCount
RowSize1=ceiling((BitsPerPixel*nx)/(for*eig))*4
RowSize2=floor((BitsPerPixel*nx+thr*ten+one)/(for*eig))*4

! Bitmap integer calculations.
error_if: if (RowSize1 /= RowSize2) then
   write(kpt6,*) "ERROR bitmap row size calculator failed."
else
   nzp = RowSize1 - (nx*BitsPerPixel/8)
   biSizeImage = RowSize1 * ny
   bfSize = bfOffBits + biSizeImage

   ! Make file name with ".bmp" extension.
   ilast=-99
   do i=ibeg,iend,1
      if ( ((bout(i:i).eq.' ') .or. (bout(i:i).eq.'')) .and. &
             ilast .lt. 0 ) then
         ilast = int( i - 1, int16 )
      end if
   end do
   bfile = trim(adjustl(bout(1:ilast)))//".bmp"
   write(kpt6,*) "MAKING File: ",bfile(1:54)

   ! Write to file.
   open ( unit=uu, file=bfile, status='replace', &
          access='stream', action='write', form='unformatted', &
          position='rewind', iostat=istat )
   open_if: if (istat /= 0) then
      write(kpt6,*) 'ERROR file I/O was not created.'
   else

      ! Write BMP Header.
      write ( uu ) bfType,bfSize,bfReserved1,bfReserved2,bfOffBits

      ! Write DIB Header.
      write ( uu ) biSize,biWidth,biHeight,biPlanes,biBitCount, &
                   biCompression,biSizeImage,biXPelsPerMeter, &
                   biYPelsPerMeter,biClrUsed,biClrImportant

      !********************************!
      ! Apply the color map (if used)  !
      !********************************!
      call apply_colormap( nx, ny, fcn, RGB, cmap )

      ! Write Bit Values, if row padding.
      rowpad_if: if (nzp > 0) then
         write(kpt6,*) &
            "   Zero padding is required to make bitmap image."
         write(kpt6,*) "    bytes = ",nzp
         allocate(zpad(nzp))
         zpad = 0_int8

         ! Lines (bottom to top).
         do j=ny,1,-1
            do i=1,nx
               write ( uu ) RGB(i,j,1:3)
            end do
            write ( uu ) zpad(1:nzp)
         end do
         deallocate(zpad)

      ! Write Bit Values, if NOT row padding.
      else
         write(kpt6,*) &
            "   No zero padding required to make bitmap image."

         ! Lines (bottom to top).
         do j=ny,1,-1
            do i=1,nx
               write ( uu ) RGB(i,j,1:3)
            end do
         end do
      end if rowpad_if

   end if open_if

end if error_if

close ( unit=uu )

return
end subroutine bmpmaker

subroutine apply_colormap(nx,ny,fcn,RGB,cmap)
!**********************************************************************!
!  About:                                                              !
!    APPLY_COLORMAP turns a real-valued image, fcn in [0,1], into RGB  !
!    with the named colormap (e.g. "viridis", or "viridis2,1,3" for a  !
!    channel order). A name that is none of the colormaps leaves RGB  !
!    as it is: that is how a caller passes ready-made RGB to bmpmaker  !
!    (cmap = 'rgb').                                                   !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    10/20/26    Claude (for DEK)   Moved, as it was, out of bmpmaker  !
!                                                                      !
!**********************************************************************!
use bits, only: dp,int16,int32
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
integer(kind=int32), intent(in) :: nx,ny               ! dimensions
real(kind=dp), dimension(nx,ny), intent(in) :: fcn     ! values [0,1]
character(len=1), dimension(nx,ny,3), intent(inout) :: RGB  ! colors
character(len=80), intent(in) :: cmap                  ! colormap name

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.
!**********************************************************************!
integer(kind=int16) :: npr                             ! channel order

   !********************************!
   ! Apply the color map (if used)  !
   !********************************!

   ! Straight linear interpolation grayscale.
   colormap_if: if (cmap(1:9)=='grayscale') then
      call cmap_grayscale( nx, ny, fcn, RGB )

   ! Smooth Cool-Warm Color Maps.
   else if (cmap(1:14)=='smoothcoolwarm') then
      npr=1
      if (cmap(15:19)=='1,2,3') npr=1
      if (cmap(15:19)=='1,3,2') npr=2
      if (cmap(15:19)=='2,1,3') npr=3
      if (cmap(15:19)=='2,3,1') npr=4
      if (cmap(15:19)=='3,1,2') npr=5
      if (cmap(15:19)=='3,2,1') npr=6
      call cmap_smoothcoolwarm( nx, ny, fcn, RGB, npr )

   ! Bent Cool-Warm Color Maps.
   else if (cmap(1:12)=='bentcoolwarm') then
      npr=1
      if (cmap(13:17)=='1,2,3') npr=1
      if (cmap(13:17)=='1,3,2') npr=2
      if (cmap(13:17)=='2,1,3') npr=3
      if (cmap(13:17)=='2,3,1') npr=4
      if (cmap(13:17)=='3,1,2') npr=5
      if (cmap(13:17)=='3,2,1') npr=6
      call cmap_bentcoolwarm( nx, ny, fcn, RGB, npr )

   ! Viridis Color Maps.
   else if (cmap(1:7)=='viridis') then
      npr=1
      if (cmap(8:12)=='1,2,3') npr=1
      if (cmap(8:12)=='1,3,2') npr=2
      if (cmap(8:12)=='2,1,3') npr=3
      if (cmap(8:12)=='2,3,1') npr=4
      if (cmap(8:12)=='3,1,2') npr=5
      if (cmap(8:12)=='3,2,1') npr=6
      call cmap_viridis( nx, ny, fcn, RGB, npr )

   ! Plasma Color Maps.
   else if (cmap(1:6)=='plasma') then
      npr=1
      if (cmap(7:11)=='1,2,3') npr=1
      if (cmap(7:11)=='1,3,2') npr=2
      if (cmap(7:11)=='2,1,3') npr=3
      if (cmap(7:11)=='2,3,1') npr=4
      if (cmap(7:11)=='3,1,2') npr=5
      if (cmap(7:11)=='3,2,1') npr=6
      call cmap_plasma( nx, ny, fcn, RGB, npr )

   ! Black Body Color Maps.
   else if (cmap(1:9)=='blackbody') then
      npr=1
      if (cmap(10:14)=='1,2,3') npr=1
      if (cmap(10:14)=='1,3,2') npr=2
      if (cmap(10:14)=='2,1,3') npr=3
      if (cmap(10:14)=='2,3,1') npr=4
      if (cmap(10:14)=='3,1,2') npr=5
      if (cmap(10:14)=='3,2,1') npr=6
      call cmap_blackbody( nx, ny, fcn, RGB, npr )

   ! Inferno Color Maps.
   else if (cmap(1:7)=='inferno') then
      npr=1
      if (cmap(8:12)=='1,2,3') npr=1
      if (cmap(8:12)=='1,3,2') npr=2
      if (cmap(8:12)=='2,1,3') npr=3
      if (cmap(8:12)=='2,3,1') npr=4
      if (cmap(8:12)=='3,1,2') npr=5
      if (cmap(8:12)=='3,2,1') npr=6
      call cmap_inferno( nx, ny, fcn, RGB, npr )

   ! Kindlmann Color Maps.
   else if (cmap(1:9)=='kindlmann') then
      npr=1
      if (cmap(10:14)=='1,2,3') npr=1
      if (cmap(10:14)=='1,3,2') npr=2
      if (cmap(10:14)=='2,1,3') npr=3
      if (cmap(10:14)=='2,3,1') npr=4
      if (cmap(10:14)=='3,1,2') npr=5
      if (cmap(10:14)=='3,2,1') npr=6
      call cmap_kindlmann( nx, ny, fcn, RGB, npr )

   ! Extended Kindlmann Color Maps.
   else if (cmap(1:17)=='extendedkindlmann') then
      npr=1
      if (cmap(18:22)=='1,2,3') npr=1
      if (cmap(18:22)=='1,3,2') npr=2
      if (cmap(18:22)=='2,1,3') npr=3
      if (cmap(18:22)=='2,3,1') npr=4
      if (cmap(18:22)=='3,1,2') npr=5
      if (cmap(18:22)=='3,2,1') npr=6
      call cmap_extendedkindlmann( nx, ny, fcn, RGB, npr )

   end if colormap_if

return
end subroutine apply_colormap

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
!                                                                      !
!**********************************************************************!
use bits, only: dp,int8,int16,int32,j,i,k,istat,one,thr,for,eig,ten, &
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
character*1, dimension(nx,ny,3), intent(inout) :: RGB  ! (optional)

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
         ilast = i - 1
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

      ! Straight linear interpolation grayscale.
      colormap_if: if (cmap(1:9)=='grayscale') then
         call cmap_grayscale( nx, ny, fcn, RGB )

      ! Smooth Cool-Warm Color Maps.
      else if (cmap(1:14)=='smoothcoolwarm') then
         k=1
         if (cmap(15:19)=='1,2,3') k=1
         if (cmap(15:19)=='1,3,2') k=2
         if (cmap(15:19)=='2,1,3') k=3
         if (cmap(15:19)=='2,3,1') k=4
         if (cmap(15:19)=='3,1,2') k=5
         if (cmap(15:19)=='3,2,1') k=6
         call cmap_smoothcoolwarm( nx, ny, fcn, RGB, k )

      ! Bent Cool-Warm Color Maps.
      else if (cmap(1:12)=='bentcoolwarm') then
         k=1
         if (cmap(13:17)=='1,2,3') k=1
         if (cmap(13:17)=='1,3,2') k=2
         if (cmap(13:17)=='2,1,3') k=3
         if (cmap(13:17)=='2,3,1') k=4
         if (cmap(13:17)=='3,1,2') k=5
         if (cmap(13:17)=='3,2,1') k=6
         call cmap_bentcoolwarm( nx, ny, fcn, RGB, k )

      ! Viridis Color Maps.
      else if (cmap(1:7)=='viridis') then
         k=1
         if (cmap(8:12)=='1,2,3') k=1
         if (cmap(8:12)=='1,3,2') k=2
         if (cmap(8:12)=='2,1,3') k=3
         if (cmap(8:12)=='2,3,1') k=4
         if (cmap(8:12)=='3,1,2') k=5
         if (cmap(8:12)=='3,2,1') k=6
         call cmap_viridis( nx, ny, fcn, RGB, k )

      ! Plasma Color Maps.
      else if (cmap(1:6)=='plasma') then
         k=1
         if (cmap(7:11)=='1,2,3') k=1
         if (cmap(7:11)=='1,3,2') k=2
         if (cmap(7:11)=='2,1,3') k=3
         if (cmap(7:11)=='2,3,1') k=4
         if (cmap(7:11)=='3,1,2') k=5
         if (cmap(7:11)=='3,2,1') k=6
         call cmap_plasma( nx, ny, fcn, RGB, k )

      ! Black Body Color Maps.
      else if (cmap(1:9)=='blackbody') then
         k=1
         if (cmap(10:14)=='1,2,3') k=1
         if (cmap(10:14)=='1,3,2') k=2
         if (cmap(10:14)=='2,1,3') k=3
         if (cmap(10:14)=='2,3,1') k=4
         if (cmap(10:14)=='3,1,2') k=5
         if (cmap(10:14)=='3,2,1') k=6
         call cmap_blackbody( nx, ny, fcn, RGB, k )

      ! Inferno Color Maps.
      else if (cmap(1:7)=='inferno') then
         k=1
         if (cmap(8:12)=='1,2,3') k=1
         if (cmap(8:12)=='1,3,2') k=2
         if (cmap(8:12)=='2,1,3') k=3
         if (cmap(8:12)=='2,3,1') k=4
         if (cmap(8:12)=='3,1,2') k=5
         if (cmap(8:12)=='3,2,1') k=6
         call cmap_inferno( nx, ny, fcn, RGB, k )

      ! Kindlmann Color Maps.
      else if (cmap(1:9)=='kindlmann') then
         k=1
         if (cmap(10:14)=='1,2,3') k=1
         if (cmap(10:14)=='1,3,2') k=2
         if (cmap(10:14)=='2,1,3') k=3
         if (cmap(10:14)=='2,3,1') k=4
         if (cmap(10:14)=='3,1,2') k=5
         if (cmap(10:14)=='3,2,1') k=6
         call cmap_kindlmann( nx, ny, fcn, RGB, k )

      ! Extended Kindlmann Color Maps.
      else if (cmap(1:17)=='extendedkindlmann') then
         k=1
         if (cmap(18:22)=='1,2,3') k=1
         if (cmap(18:22)=='1,3,2') k=2
         if (cmap(18:22)=='2,1,3') k=3
         if (cmap(18:22)=='2,3,1') k=4
         if (cmap(18:22)=='3,1,2') k=5
         if (cmap(18:22)=='3,2,1') k=6
         call cmap_extendedkindlmann( nx, ny, fcn, RGB, k )

      end if colormap_if

      ! Write Bit Values, if row padding.
      rowpad_if: if (nzp > 0) then
         write(kpt6,*) &
            "   Zero padding is required to make bitmap image."
         write(kpt6,*) "    bytes = ",nzp
         allocate(zpad(nzp))

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

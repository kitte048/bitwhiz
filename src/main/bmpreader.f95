subroutine bmpreader(fname,nx,ny)
!**********************************************************************!
!  About:                                                              !
!    BMPREADER is the executive routine that reads ".bmp" files.       !
!                                                                      !
!  Purpose:                                                            !
!    To open a ".bmp" file and extract the image data pixel array.     !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    12/04/23    D. E. Kittell      Original program.               .  !
!                                                                      !
!**********************************************************************!
use bits, only: int8,int16,int32,dp,nline,istat,kpt6,i,ii,j,k, &
                alloc_rgbdata,dealloc_rgbdata,RGBdata, &
                alloc_CIELAB,dealloc_CIELAB,Lstar,astar,bstar, &
                zero,one,thr,for,eig,ten
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
character(len=nline), intent(in) :: fname         ! file name for BMP
integer(kind=int32), intent(out) :: nx,ny         ! dimensions

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.
!**********************************************************************!
integer(kind=int16), parameter :: uu=88        ! file ID
integer(kind=int8), dimension(10) :: bytes     ! 1 byte signed ints
character(len=2) :: bfHeader="  "              ! ="0","BM","BA", etc.
character(len=1024) :: str                     ! string to write numbers
character(len=1024) :: KindOS="  "             ! string for which OS used
character(len=8) :: onebyte                    ! store 1 byte as a string
integer(kind=int16) :: bfType                  ! always'BM' (.bmp)
integer(kind=int32) :: bfSize                  ! file size in bytes
integer(kind=int16) :: bfReserved1             ! always 0
integer(kind=int16) :: bfReserved2             ! always 0
integer(kind=int32) :: bfOffBits               ! 54 bytes (14+40) ?
integer(kind=int32) :: biSize                  ! size of header
integer(kind=int32) :: biWidth                 ! width in pixels
integer(kind=int32) :: biHeight                ! height in pixels
integer(kind=int16) :: biPlanes                ! must be set to 1
integer(kind=int16) :: biBitCount              ! color depth (RGB) 
integer(kind=int32) :: biCompression           ! no compression
integer(kind=int32) :: biSizeImage             ! size of data, bytes
integer(kind=int32) :: biXPelsPerMeter         ! usually set to zero
integer(kind=int32) :: biYPelsPerMeter         ! usually set to zero
integer(kind=int32) :: biClrUsed               ! default 0 for 2^n
integer(kind=int32) :: biClrImportant          ! all colors
integer(kind=int32) :: kerr=0                  ! error if no free memory
integer(kind=int32) :: iOS=0                   ! integer for OS type
logical :: readable=.false.                    ! true if file is readable
logical :: supported=.false.                   ! true if type supported 
integer(kind=int32) :: BitsPerPixel, &
   RowSize1,RowSize2,nzp=0                               ! integers
integer(kind=int8), dimension(:), allocatable :: zpad  ! zero pad
character(len=80) :: bout,cmap                 ! string params
real(kind=dp) :: R,G,B,X,Y,Z,X0,Y0,Z0          ! image processing tests
integer(kind=int8), dimension(8) :: b07        ! 8-bit color bits

150 format(/,'Opening file: ',1(a54))
160 format(/,'ERROR opening file: ',1(a54))
161 format(/,'ERROR first 2 bytes of file are not valid BMP format.')
170 format(' Attempting to auto-detect the OS format type...',&
           /,' header matches ',1(a54))
180 format(/,'ERROR insufficient memory to load bitmap.')
190 format('[ (',1(i3),',',1(i3),',',1(i3),'), (', &
                 1(i3),',',1(i3),',',1(i3),'), (', &
                 1(i3),',',1(i3),',',1(i3),'),')
191 format('  (',1(i3),',',1(i3),',',1(i3),'), (', &
                 1(i3),',',1(i3),',',1(i3),'), (', &
                 1(i3),',',1(i3),',',1(i3),'),')
192 format('  (',1(i3),',',1(i3),',',1(i3),'), (', &
                 1(i3),',',1(i3),',',1(i3),'), (', &
                 1(i3),',',1(i3),',',1(i3),') ]')

!********************************************************!
! First open to see whether file exists and can be read. !
!********************************************************!
open ( unit=uu, file=trim(adjustl(fname)), status='old', &
       form='unformatted', action='read', iostat=istat , &
       access ='stream' )

! Read first two bytes.
open_if: if (istat /= 0) then
   write(kpt6,160) fname
else
   write(kpt6,150) fname
   read ( uu, POS=1 ) bytes(1),bytes(2)
   bfHeader(1:1) = achar(bytes(1))
   bfHeader(2:2) = achar(bytes(2))

   ! Check the File Header.
   readable_if: if (bfHeader(1:2)=="BM") then
      readable = .true.

   ! Other possibilities (not currently supported). 
   else if (bfHeader(1:2)=="BA") then
      write(kpt6,*) "Type BA (OS/2 struct bitmap array) NOT supported."

   else if (bfHeader(1:2)=="CI") then
      write(kpt6,*) "Type CI (OS/2 struct color icon) NOT supported."

   else if (bfHeader(1:2)=="CP") then
      write(kpt6,*) "Type CP (OS/2 const color pointer) NOT supported."

   else if (bfHeader(1:2)=="IC") then
      write(kpt6,*) "Type IC (OS/2 struct icon) NOT supported."

   else if (bfHeader(1:2)=="PT") then
      write(kpt6,*) "Type PT (OS/2 pointer) NOT supported."

   ! Not a valid BMP format.
   else
      write(kpt6,161)

   end if readable_if
end if open_if
close ( unit=uu )

!*******************!
! Echo File Details !
!*******************!
echo_if: if (readable) then
   open ( unit=uu, file=trim(adjustl(fname)), status='old', &
          form='unformatted', action='read', iostat=istat , &
          access ='stream' )

   !*****************!
   ! Read BMP Header ! 
   !*****************!
   read ( uu, POS=1 ) bfType,bfSize,bfReserved1,bfReserved2,bfOffBits

   !*****************!
   ! Read DIB Header !
   !*****************!
   read ( uu ) biSize

   !
   ! Detect Windows and OS/2 variants from the information header.
   ! Use iOS = -1 if not supported, otherwise choose an integer.
   !
   how_made_if: if (biSize.eq.12) then
      KindOS = 'Windows 2.x BMP -or- OS/2 1.x BMP'
      iOS = 1

   else if (biSize.eq.64) then
      KindOS = 'OS/2 2.x BMP'
      iOS = 2

   else if (biSize.eq.16) then
      KindOS = 'OS/2 2.x BMP'
      iOS = 3

   else if (biSize.eq.40) then
      KindOS = 'Windows 3.x BMP -or- Windows NT BMP'
      iOS = 4
      supported = .true.

   else if (biSize.eq.52) then
      KindOS = 'Undocumented - adds RGB bit masks'
      iOS = 5

   else if (biSize.eq.56) then
      KindOS = 'Undocumented - adds alpha channel'
      iOS = 6

   else if (biSize.eq.108) then
      KindOS = 'Windows NT -or- Windows 4.x -or- Windows 95'
      iOS = 7

   else if (biSize.eq.124) then
      KindOS = 'Windows NT -or- Windows 5.x -or- Windows 98'
      iOS = 8

   else
      KindOS = 'TYPE UNKNOWN'
      iOS = -1

   end if how_made_if

   write(kpt6,170) KindOS
   write(kpt6,*) '.-----------------------------------------------.'
   write(kpt6,*) '|                  BMP Header                   |'
   write(kpt6,*) "'-----------------------------------------------'"
   write(kpt6,*) '                Type = ',bfHeader
   write(str,'(1(i16))') bfSize
   write(kpt6,*) '           File Size = ',trim(adjustl(str)), &
                 ' bytes'
   write(str,'(1(i16))') bfReserved1
   write(kpt6,*) '          Reserved 1 = ',trim(adjustl(str))
   write(str,'(1(i16))') bfReserved2
   write(kpt6,*) '          Reserved 2 = ',trim(adjustl(str))
   write(str,'(1(i16))') bfOffBits
   write(kpt6,*) '   Starting Position = ',trim(adjustl(str)), &
                 ' bytes'
   write(kpt6,*) '.-----------------------------------------------.'
   write(kpt6,*) '|                  DIB Header                   |'
   write(kpt6,*) "'-----------------------------------------------'"

   !=====================================!
   ! Windows 3.x BMP -or- Windows NT BMP !
   !=====================================!
   if (iOS==4) then
    read ( uu ) biWidth,biHeight,biPlanes,biBitCount, &
                biCompression,biSizeImage,biXPelsPerMeter, &
                biYPelsPerMeter,biClrUsed,biClrImportant
    write(str,'(1(i16))') biSize
    write(kpt6,*) '     DIB Header Size = ',trim(adjustl(str)), &
                  ' bytes'
    write(str,'(1(i16))') biWidth
    write(kpt6,*) '         Image Width = ',trim(adjustl(str)), &
                  ' pixels'
    write(str,'(1(i16))') biHeight
    write(kpt6,*) '        Image Height = ',trim(adjustl(str)), &
                  ' pixels'
    write(str,'(1(i16))') biPlanes
    write(kpt6,*) '        Color Planes = ',trim(adjustl(str))
    write(str,'(1(i16))') biBitCount
    write(kpt6,*) '      Bits Per Pixel = ',trim(adjustl(str))
    write(str,'(1(i16))') biCompression
    write(kpt6,*) '  Compression Method = ',trim(adjustl(str))
    write(str,'(1(i16))') biSizeImage
    write(kpt6,*) '      Size of Bitmap = ',trim(adjustl(str)), &
                  ' bytes'
    write(str,'(1(i16))') biXPelsPerMeter
    write(kpt6,*) '      Horizontal Rez = ',trim(adjustl(str)), &
                  ' pixels per meter'
    write(str,'(1(i16))') biYPelsPerMeter
    write(kpt6,*) '        Vertical Rez = ',trim(adjustl(str)), &
                  ' pixels per meter'
    write(str,'(1(i16))') biClrUsed
    write(kpt6,*) '         Colors Used = ',trim(adjustl(str))
    write(str,'(1(i16))') biClrImportant
    write(kpt6,*) '    Important Colors = ',trim(adjustl(str))
   end if

   close ( unit=uu )
end if echo_if

!**************!
! Extract Data !
!**************!
supported_if: if (supported .and. iOS .gt. 0) then

   write(kpt6,*) '.-----------------------------------------------.'
   write(kpt6,*) '|                 Bitmap Data                   |'
   write(kpt6,*) "'-----------------------------------------------'"

   ! Set image dimensions and allocate memory.
   nx = biWidth
   ny = biHeight
   BitsPerPixel=biBitCount
   RowSize1=ceiling((BitsPerPixel*nx)/(for*eig))*4
   RowSize2=floor((BitsPerPixel*nx+thr*ten+one)/(for*eig))*4
   nzp = RowSize1 - (nx*BitsPerPixel/8)

   call alloc_rgbdata(nx,ny,kerr)

   open ( unit=uu, file=trim(adjustl(fname)), status='old', &
          form='unformatted', action='read', iostat=istat , &
          access ='stream' )

   mem_fail: if ( kerr > 0 ) then

      ! Error message.
      write(kpt6,180)

   else

      ! Position the file.
      k = bfOffBits+1

      ! Lines (bottom to top).
      do j=ny,1,-1
         do i=1,nx,1

            !=========================================!
            ! Choose the correct bits per pixel here. !
            !=========================================!

            ! 24-bit color.
            if (biBitCount.eq.24) then
             read ( uu, POS = k ) bytes(1),bytes(2),bytes(3)
             k = k+3
             RGBdata(i,j,1) = achar(bytes(1))
             RGBdata(i,j,2) = achar(bytes(2))
             RGBdata(i,j,3) = achar(bytes(3))

             ! Read the zero pad, if applicable.
             if ( (i.eq.nx) .and. (nzp.gt.0) ) then
              read ( uu, POS = k ) bytes(1:nzp)
              k = k+nzp
             end if

            ! 8-bit color.
            else if (biBitCount.eq.8) then
             read ( uu, POS = k ) bytes(1)
             write( onebyte , '(B8.8)' ) bytes(1)
!             do ii=1,8,1
!              if (onebyte(ii:ii).eq.'0') then
!               b07(ii) = 0
!              else
!               b07(ii) = 1
!              end if
!             end do
             k = k+1
!             RGBdata(i,j,1) = achar( 4*b07(1) + 2*b07(2) + 1*b07(3) )
!             RGBdata(i,j,2) = achar( 4*b07(4) + 2*b07(5) + 1*b07(6) )
!             RGBdata(i,j,3) = achar(            2*b07(7) + 1*b07(8) )
            end if

 
         end do
      end do

      ! Formatted RGB data (pixels 1 thru 3).
      write(kpt6,190) ichar(RGBdata(ny,1,1)), &
                      ichar(RGBdata(ny,1,2)), &
                      ichar(RGBdata(ny,1,3)), &
                      ichar(RGBdata(ny,2,1)), &
                      ichar(RGBdata(ny,2,2)), &
                      ichar(RGBdata(ny,2,3)), &
                      ichar(RGBdata(ny,3,1)), &
                      ichar(RGBdata(ny,3,2)), &
                      ichar(RGBdata(ny,3,3))

      ! Formatted RGB data (pixels 4 thru 6).
      write(kpt6,191) ichar(RGBdata(ny,4,1)), &
                      ichar(RGBdata(ny,4,2)), &
                      ichar(RGBdata(ny,4,3)), &
                      ichar(RGBdata(ny,5,1)), &
                      ichar(RGBdata(ny,5,2)), &
                      ichar(RGBdata(ny,5,3)), &
                      ichar(RGBdata(ny,6,1)), &
                      ichar(RGBdata(ny,6,2)), &
                      ichar(RGBdata(ny,6,3))

      write(kpt6,*) '    :       :      :       :      :       :'
      write(kpt6,*) '    :       :      :       :      :       :'
      write(kpt6,*) '    :       :      :       :      :       :'

      ! Formatted RGB data (pixels N-5 thru N-3).
      write(kpt6,191) ichar(RGBdata(1,nx-5,1)), &
                      ichar(RGBdata(1,nx-5,2)), &
                      ichar(RGBdata(1,nx-5,3)), &
                      ichar(RGBdata(1,nx-4,1)), &
                      ichar(RGBdata(1,nx-4,2)), &
                      ichar(RGBdata(1,nx-4,3)), &
                      ichar(RGBdata(1,nx-3,1)), &
                      ichar(RGBdata(1,nx-3,2)), &
                      ichar(RGBdata(1,nx-3,3))

      ! Formatted RGB data (pixels N-2 thru N).
      write(kpt6,192) ichar(RGBdata(1,nx-2,1)), &
                      ichar(RGBdata(1,nx-2,2)), &
                      ichar(RGBdata(1,nx-2,3)), &
                      ichar(RGBdata(1,nx-1,1)), &
                      ichar(RGBdata(1,nx-1,2)), &
                      ichar(RGBdata(1,nx-1,3)), &
                      ichar(RGBdata(1,nx-0,1)), &
                      ichar(RGBdata(1,nx-0,2)), &
                      ichar(RGBdata(1,nx-0,3))

   end if mem_fail
   close ( unit=uu )
end if supported_if

write(kpt6,*) ' '

!################################################!
! Testing, testing, 1,2,3...
!################################################!
kerr = 0
call alloc_CIELAB(nx,ny,kerr)
do j=ny,1,-1
   do i=1,nx

      ! RGB Signals.
      R = one*ichar(RGBdata(i,j,1))
      G = one*ichar(RGBdata(i,j,2))
      B = one*ichar(RGBdata(i,j,3))

      ! Conversion to CIE tristimulus values.
      X = 0.4303_dp * R + 0.3416_dp * G + 0.1784_dp * B
      Y = 0.2219_dp * R + 0.7068_dp * G + 0.0713_dp * B
      Z = 0.0202_dp * R + 0.1296_dp * G + 0.9393_dp * B

      ! Tristimulus values of the illuminant; e.g., D65.
      X0 = 95.047_dp
      Y0 = 100.0_dp
      Z0 = 108.883_dp

   end do
end do
bout = 'Testing'
cmap = 'None'
call bmpmaker(nx,ny,Lstar,RGBdata,bout,cmap)
!################################################!
! END.
!################################################!

return
end subroutine bmpreader

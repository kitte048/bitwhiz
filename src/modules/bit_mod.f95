module bits
!**********************************************************************!
!
!  Purpose:
!    Module contains variables and data arrays used to draw bitmap art.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    04/04/20    D. E. Kittell        Original code
!
!**********************************************************************!
implicit none
save

! Declare all items to be public
public

!**********************************************************************!
! Data dictionary: declare system-independent reals and integers.
!**********************************************************************!
integer, parameter :: sp = selected_real_kind(6, 37)    !  32-bit (4 byte)
integer, parameter :: dp = selected_real_kind(15, 307)  !  64-bit (8 byte)
integer, parameter :: qp = selected_real_kind(33, 4931) ! 128-bit (16 byte)

integer, parameter :: int8 = selected_int_kind(1)       ! 1 byte signed int
integer, parameter :: int16 = selected_int_kind(3)      ! 2 byte signed int
integer, parameter :: int32 = selected_int_kind(9)      ! 4 byte signed int
integer, parameter :: int64 = selected_int_kind(18)     ! 8 byte signed int

integer(kind=int16), parameter :: kpt5=5,kpt6=6         ! File I/O

!**********************************************************************!
! Data dictionary: declare variables for mathematical function eval.
!**********************************************************************!
integer(kind=int32) :: i,j,k,ii,jj,kk,istat
real(kind=dp), parameter :: zero=0.0_dp,half=0.5_dp,one=1.0_dp, &
   two=2.0_dp,thr=3.0_dp,for=4.0_dp,fiv=5.0_dp,six=6.0_dp, &
   sev=7.0_dp, eig=8.0_dp, nin=9.0_dp, ten=10.0_dp

! 65 digits of PI
real(kind=qp), parameter :: pi=&
 3.14159265358979323846264338327950288419716939937510582097494459230_qp

integer(kind=int32), parameter :: nline=200  ! size of a character line

!**********************************************************************!
! Data dictionary: BMP Header (BYTES 14, FIELDS 5)
!**********************************************************************!
!  Using 'BM' for Windows 3.1x, 95, NT, ... etc.
integer(kind=int16), parameter :: bfType=19778    ! always'BM' (.bmp)
integer(kind=int32)            :: bfSize          ! file size in bytes
integer(kind=int16), parameter :: bfReserved1=0   ! always 0
integer(kind=int16), parameter :: bfReserved2=0   ! always 0
integer(kind=int32), parameter :: bfOffBits=54    ! 54 bytes (14+40)

!**********************************************************************!
! Data dictionary: DIB Header (BYTES 40, FIELDS 11)
!**********************************************************************!
integer(kind=int32), parameter :: biSize=40         ! size of header
integer(kind=int32)            :: biWidth           ! width in pixels
integer(kind=int32)            :: biHeight          ! height in pixels
integer(kind=int16), parameter :: biPlanes=1        ! must be set to 1
integer(kind=int16), parameter :: biBitCount=24     ! color depth (RGB) 
integer(kind=int32), parameter :: biCompression=0   ! no compression
integer(kind=int32)            :: biSizeImage       ! size of data, bytes
integer(kind=int32), parameter :: biXPelsPerMeter=0 ! usually set to zero
integer(kind=int32), parameter :: biYPelsPerMeter=0 ! usually set to zero
integer(kind=int32), parameter :: biClrUsed=0       ! default 0 for 2^n
integer(kind=int32), parameter :: biClrImportant=0  ! all colors

!**********************************************************************!
! Data dictionary: Named RGB Color Values.
!**********************************************************************!
! see https://www.imgonline.com.ua/eng/color-palette.php
integer(kind=int32), parameter :: ncls=137
character*1, parameter, dimension(3) :: &
!*** Colors 1-10
   Maroon               = (/achar(128),achar(  0),achar(  0)/), &
   DarkRed              = (/achar(139),achar(  0),achar(  0)/), &
   FireBrick            = (/achar(178),achar( 34),achar( 34)/), &
   Red                  = (/achar(255),achar(  0),achar(  0)/), &
   Salmon               = (/achar(250),achar(128),achar(114)/), &
   Tomato               = (/achar(255),achar( 99),achar( 71)/), &
   Coral                = (/achar(255),achar(127),achar( 80)/), &
   OrangeRed            = (/achar(255),achar( 69),achar(  0)/), &
   Chocolate            = (/achar(210),achar(105),achar( 30)/), &
   SandyBrown           = (/achar(244),achar(164),achar( 96)/), &
!*** Colors 11-20
   DarkOrange           = (/achar(255),achar(140),achar(  0)/), &
   Orange               = (/achar(255),achar(165),achar(  0)/), &
   DarkGoldenrod        = (/achar(184),achar(134),achar( 11)/), &
   Goldenrod            = (/achar(218),achar(165),achar( 32)/), &
   Gold                 = (/achar(255),achar(215),achar(  0)/), &
   Olive                = (/achar(128),achar(128),achar(  0)/), &
   Yellow               = (/achar(255),achar(255),achar(  0)/), &
   YellowGreen          = (/achar(154),achar(205),achar( 50)/), &
   GreenYellow          = (/achar(173),achar(255),achar( 47)/), &
   Chartreuse           = (/achar(127),achar(255),achar(  0)/), &
!*** Colors 21-30
   LawnGreen            = (/achar(124),achar(252),achar(  0)/), &
   Green                = (/achar(  0),achar(128),achar(  0)/), &
   Lime                 = (/achar(  0),achar(255),achar(  0)/), &
   LimeGreen            = (/achar( 50),achar(205),achar( 50)/), &
   SpringGreen          = (/achar(  0),achar(255),achar(127)/), &
   MediumSpringGreen    = (/achar(  0),achar(250),achar(154)/), &
   Turquoise            = (/achar( 64),achar(224),achar(208)/), &
   LightSeaGreen        = (/achar( 32),achar(178),achar(170)/), &
   MediumTurquoise      = (/achar( 72),achar(209),achar(204)/), &
   DarkCyan             = (/achar(  0),achar(139),achar(139)/), &
!*** Colors 31-40
   Aqua                 = (/achar(  0),achar(255),achar(255)/), &
   DarkTurquoise        = (/achar(  0),achar(206),achar(209)/), &
   DeepSkyBlue          = (/achar(  0),achar(191),achar(255)/), &
   DodgerBlue           = (/achar( 30),achar(144),achar(255)/), &
   RoyalBlue            = (/achar( 65),achar(105),achar(225)/), &
   Navy                 = (/achar(  0),achar(  0),achar(128)/), &
   DarkBlue             = (/achar(  0),achar(  0),achar(139)/), &
   MediumBlue           = (/achar(  0),achar(  0),achar(205)/), &
   Blue                 = (/achar(  0),achar(  0),achar(255)/), &
   BlueViolet           = (/achar(138),achar( 43),achar(226)/), &
!*** Colors 41-50
   DarkOrchid           = (/achar(153),achar( 50),achar(204)/), &
   DarkViolet           = (/achar(148),achar(  0),achar(211)/), &
   Purple               = (/achar(128),achar(  0),achar(128)/), &
   DarkMagenta          = (/achar(139),achar(  0),achar(139)/), &
   Magenta              = (/achar(255),achar(  0),achar(255)/), &
   MediumVioletRed      = (/achar(199),achar( 21),achar(133)/), &
   DeepPink             = (/achar(255),achar( 20),achar(147)/), &
   HotPink              = (/achar(255),achar(105),achar(180)/), &
   Crimson              = (/achar(220),achar( 20),achar( 60)/), &
   Brown                = (/achar(165),achar( 42),achar( 42)/), &
!*** Colors 51-60
   IndianRed            = (/achar(205),achar( 92),achar( 92)/), &
   RosyBrown            = (/achar(188),achar(143),achar(143)/), &
   LightCoral           = (/achar(240),achar(128),achar(128)/), &
   Snow                 = (/achar(255),achar(250),achar(250)/), &
   MistyRose            = (/achar(255),achar(228),achar(225)/), &
   DarkSalmon           = (/achar(233),achar(150),achar(122)/), &
   LightSalmon          = (/achar(255),achar(160),achar(122)/), &
   Sienna               = (/achar(160),achar( 82),achar( 45)/), &
   SeaShell             = (/achar(255),achar(245),achar(238)/), &
   SaddleBrown          = (/achar(139),achar( 69),achar( 19)/), &
!*** Colors 61-70
   Peachpuff            = (/achar(255),achar(218),achar(185)/), &
   Peru                 = (/achar(205),achar(133),achar( 63)/), &
   Linen                = (/achar(250),achar(240),achar(230)/), &
   Bisque               = (/achar(255),achar(228),achar(196)/), &
   Burlywood            = (/achar(222),achar(184),achar(135)/), &
   Tancolor             = (/achar(210),achar(180),achar(140)/), &
   AntiqueWhite         = (/achar(255),achar(235),achar(215)/), &
   NavajoWhite          = (/achar(255),achar(222),achar(173)/), &
   BlanchedAlmond       = (/achar(255),achar(235),achar(205)/), &
   PapayaWhip           = (/achar(255),achar(239),achar(213)/), &
!*** Colors 71-80
   Moccasin             = (/achar(255),achar(228),achar(181)/), &
   Wheat                = (/achar(245),achar(222),achar(179)/), &
   Oldlace              = (/achar(253),achar(245),achar(230)/), &
   FloralWhite          = (/achar(255),achar(250),achar(240)/), &
   CornSilk             = (/achar(255),achar(248),achar(220)/), &
   Khaki                = (/achar(240),achar(230),achar(140)/), &
   LemonChiffon         = (/achar(255),achar(250),achar(205)/), &
   PaleGoldenrod        = (/achar(238),achar(232),achar(170)/), &
   DarkKhaki            = (/achar(189),achar(183),achar(107)/), &
   Beige                = (/achar(245),achar(245),achar(220)/), &
!*** Colors 81-90
   LightGoldenrodYellow = (/achar(250),achar(250),achar(210)/), &
   LightYellow          = (/achar(255),achar(255),achar(224)/), &
   Ivory                = (/achar(255),achar(255),achar(240)/), &
   OliveDrab            = (/achar(107),achar(142),achar( 35)/), &
   DarkOliveGreen       = (/achar( 85),achar(107),achar( 47)/), &
   DarkSeaGreen         = (/achar(143),achar(188),achar(143)/), &
   DarkGreen            = (/achar(  0),achar(100),achar(  0)/), &
   ForestGreen          = (/achar( 34),achar(139),achar( 34)/), &
   LightGreen           = (/achar(144),achar(238),achar(144)/), &
   PaleGreen            = (/achar(152),achar(251),achar(152)/), &
!*** Colors 91-100
   Honeydew             = (/achar(240),achar(255),achar(240)/), &
   SeaGreen             = (/achar( 46),achar(139),achar( 87)/), &
   MediumSeaGreen       = (/achar( 60),achar(179),achar(113)/), &
   MintCream            = (/achar(245),achar(255),achar(250)/), &
   MediumAquamarine     = (/achar(102),achar(205),achar(170)/), &
   Aquamarine           = (/achar(127),achar(255),achar(212)/), &
   DarkSlateGray        = (/achar( 47),achar( 79),achar( 79)/), &
   PaleTurquoise        = (/achar(179),achar(238),achar(238)/), &
   LightCyan            = (/achar(224),achar(255),achar(255)/), &
   Azure                = (/achar(245),achar(255),achar(255)/), &
!*** Colors 101-110
   CadetBlue            = (/achar( 95),achar(158),achar(160)/), &
   PowderBlue           = (/achar(176),achar(224),achar(230)/), &
   LightBlue            = (/achar(173),achar(216),achar(230)/), &
   SkyBlue              = (/achar(135),achar(206),achar(235)/), &
   LightskyBlue         = (/achar(135),achar(206),achar(250)/), &
   SteelBlue            = (/achar( 70),achar(130),achar(180)/), &
   AliceBlue            = (/achar(240),achar(248),achar(255)/), &
   SlateGray            = (/achar(112),achar(128),achar(144)/), &
   LightSlateGray       = (/achar(119),achar(136),achar(153)/), &
   LightSteelBlue       = (/achar(176),achar(196),achar(222)/), &
!*** Colors 111-120
   CornflowerBlue       = (/achar(100),achar(149),achar(237)/), &
   Lavender             = (/achar(230),achar(230),achar(250)/), &
   GhostWhite           = (/achar(248),achar(248),achar(255)/), &
   MidnightBlue         = (/achar( 25),achar( 25),achar(112)/), &
   SlateBlue            = (/achar(106),achar( 90),achar(205)/), &
   DarkSlateBlue        = (/achar( 72),achar( 61),achar(139)/), &
   MediumSlateBlue      = (/achar(123),achar(104),achar(238)/), &
   MediumPurple         = (/achar(147),achar(112),achar(219)/), &
   Indigo               = (/achar( 75),achar(  0),achar(130)/), &
   MediumOrchid         = (/achar(186),achar( 85),achar(211)/), &
!*** Colors 121-130
   Plum                 = (/achar(221),achar(160),achar(221)/), &
   Violet               = (/achar(238),achar(130),achar(238)/), &
   Thistle              = (/achar(216),achar(191),achar(216)/), &
   Orchid               = (/achar(218),achar(112),achar(214)/), &
   LavenderBlush        = (/achar(255),achar(240),achar(245)/), &
   PaleVioletRed        = (/achar(219),achar(112),achar(147)/), &
   Pink                 = (/achar(255),achar(192),achar(203)/), &
   LightPink            = (/achar(255),achar(182),achar(193)/), &
   Black                = (/achar(  0),achar(  0),achar(  0)/), &
   DimGray              = (/achar(105),achar(105),achar(105)/), &
!*** Colors 131-137
   Gray                 = (/achar(128),achar(128),achar(128)/), &
   DarkGray             = (/achar(169),achar(169),achar(169)/), &
   Silver               = (/achar(192),achar(192),achar(192)/), &
   LightGray            = (/achar(211),achar(211),achar(211)/), &
   Gainsboro            = (/achar(220),achar(220),achar(220)/), &
   WhiteSmoke           = (/achar(245),achar(245),achar(245)/), &
   White                = (/achar(255),achar(255),achar(255)/)

!**********************************************************************!
! Data dictionary: Functions to allocate RGB, RGBAX arrays.
!**********************************************************************!
character*1, dimension(:,:,:), allocatable :: RGBdata   ! data from file
character*1, dimension(:,:,:), allocatable :: RGBAXdata ! data from file
real(kind=dp), dimension(:,:), allocatable :: Lstar, &
   astar,bstar                                          ! CIELAB colors

!***NOTE: for every subroutine that allocates memory, there should be
! a corresponding subroutine to deallocate that memory.
contains

   !**************************!
   ! Allocate RGB Data Array. !
   !**************************!
   subroutine alloc_rgbdata(nx,ny,kerr)
   implicit none
   integer(kind=int32), intent(in) :: nx,ny   ! pixel array dimensions
   integer(kind=int32), intent(inout) :: kerr ! increment if no free memory
   integer(kind=int32) :: status
   character*1, dimension(:,:,:), allocatable :: mtest ! test only

   if (allocated(RGBdata)) then
      return
   else

      ! Memory size check (conservative).
      allocate(mtest(nx+10,ny+10,3),stat=status)
      mem_fail: if (status>0) then
         kerr = kerr+1
      else
         deallocate(mtest)
         allocate( RGBdata( nx, ny, 3 ) )
      end if mem_fail
   end if

   return
   end subroutine alloc_rgbdata

   !****************************!
   ! Deallocate RGB Data Array. !
   !****************************!
   subroutine dealloc_rgbdata(kerr)
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status

   if (allocated(RGBdata)) then
      deallocate(RGBdata,stat=status)
      mem_fail: if (status>0) then
         kerr = kerr+1
      end if mem_fail
   else
      return
   end if

   return
   end subroutine dealloc_rgbdata

   !*******************************!
   ! Allocate CIELAB Color Arrays. !
   !*******************************!
   subroutine alloc_CIELAB(nx,ny,kerr)
   implicit none
   integer(kind=int32), intent(in) :: nx,ny   ! pixel array dimensions
   integer(kind=int32), intent(inout) :: kerr ! increment if no free memory
   integer(kind=int32) :: status
   character*1, dimension(:,:), allocatable :: mtest ! test only

   if (allocated(Lstar)) then
      return
   else

      ! Memory size check (conservative).
      allocate(mtest(nx+10,ny+10),stat=status)
      mem_fail: if (status>0) then
         kerr = kerr+1
      else
         deallocate(mtest)
         allocate( Lstar(nx,ny), astar(nx,ny), bstar(nx,ny) )
      end if mem_fail
   end if

   return
   end subroutine alloc_CIELAB

   !*********************************!
   ! Deallocate CIELAB Color Arrays. !
   !*********************************!
   subroutine dealloc_CIELAB(kerr)
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status

   if (allocated(Lstar)) then
      deallocate(Lstar,astar,bstar,stat=status)
      mem_fail: if (status>0) then
         kerr = kerr+1
      end if mem_fail
   else
      return
   end if

   return
   end subroutine dealloc_CIELAB

end module bits

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
character(len=1), parameter, dimension(3) :: &
!*** Colors 1-10
   Maroon               = (/char(128),char(  0),char(  0)/), &
   DarkRed              = (/char(139),char(  0),char(  0)/), &
   FireBrick            = (/char(178),char( 34),char( 34)/), &
   Red                  = (/char(255),char(  0),char(  0)/), &
   Salmon               = (/char(250),char(128),char(114)/), &
   Tomato               = (/char(255),char( 99),char( 71)/), &
   Coral                = (/char(255),char(127),char( 80)/), &
   OrangeRed            = (/char(255),char( 69),char(  0)/), &
   Chocolate            = (/char(210),char(105),char( 30)/), &
   SandyBrown           = (/char(244),char(164),char( 96)/), &
!*** Colors 11-20
   DarkOrange           = (/char(255),char(140),char(  0)/), &
   Orange               = (/char(255),char(165),char(  0)/), &
   DarkGoldenrod        = (/char(184),char(134),char( 11)/), &
   Goldenrod            = (/char(218),char(165),char( 32)/), &
   Gold                 = (/char(255),char(215),char(  0)/), &
   Olive                = (/char(128),char(128),char(  0)/), &
   Yellow               = (/char(255),char(255),char(  0)/), &
   YellowGreen          = (/char(154),char(205),char( 50)/), &
   GreenYellow          = (/char(173),char(255),char( 47)/), &
   Chartreuse           = (/char(127),char(255),char(  0)/), &
!*** Colors 21-30
   LawnGreen            = (/char(124),char(252),char(  0)/), &
   Green                = (/char(  0),char(128),char(  0)/), &
   Lime                 = (/char(  0),char(255),char(  0)/), &
   LimeGreen            = (/char( 50),char(205),char( 50)/), &
   SpringGreen          = (/char(  0),char(255),char(127)/), &
   MediumSpringGreen    = (/char(  0),char(250),char(154)/), &
   Turquoise            = (/char( 64),char(224),char(208)/), &
   LightSeaGreen        = (/char( 32),char(178),char(170)/), &
   MediumTurquoise      = (/char( 72),char(209),char(204)/), &
   DarkCyan             = (/char(  0),char(139),char(139)/), &
!*** Colors 31-40
   Aqua                 = (/char(  0),char(255),char(255)/), &
   DarkTurquoise        = (/char(  0),char(206),char(209)/), &
   DeepSkyBlue          = (/char(  0),char(191),char(255)/), &
   DodgerBlue           = (/char( 30),char(144),char(255)/), &
   RoyalBlue            = (/char( 65),char(105),char(225)/), &
   Navy                 = (/char(  0),char(  0),char(128)/), &
   DarkBlue             = (/char(  0),char(  0),char(139)/), &
   MediumBlue           = (/char(  0),char(  0),char(205)/), &
   Blue                 = (/char(  0),char(  0),char(255)/), &
   BlueViolet           = (/char(138),char( 43),char(226)/), &
!*** Colors 41-50
   DarkOrchid           = (/char(153),char( 50),char(204)/), &
   DarkViolet           = (/char(148),char(  0),char(211)/), &
   Purple               = (/char(128),char(  0),char(128)/), &
   DarkMagenta          = (/char(139),char(  0),char(139)/), &
   Magenta              = (/char(255),char(  0),char(255)/), &
   MediumVioletRed      = (/char(199),char( 21),char(133)/), &
   DeepPink             = (/char(255),char( 20),char(147)/), &
   HotPink              = (/char(255),char(105),char(180)/), &
   Crimson              = (/char(220),char( 20),char( 60)/), &
   Brown                = (/char(165),char( 42),char( 42)/), &
!*** Colors 51-60
   IndianRed            = (/char(205),char( 92),char( 92)/), &
   RosyBrown            = (/char(188),char(143),char(143)/), &
   LightCoral           = (/char(240),char(128),char(128)/), &
   Snow                 = (/char(255),char(250),char(250)/), &
   MistyRose            = (/char(255),char(228),char(225)/), &
   DarkSalmon           = (/char(233),char(150),char(122)/), &
   LightSalmon          = (/char(255),char(160),char(122)/), &
   Sienna               = (/char(160),char( 82),char( 45)/), &
   SeaShell             = (/char(255),char(245),char(238)/), &
   SaddleBrown          = (/char(139),char( 69),char( 19)/), &
!*** Colors 61-70
   Peachpuff            = (/char(255),char(218),char(185)/), &
   Peru                 = (/char(205),char(133),char( 63)/), &
   Linen                = (/char(250),char(240),char(230)/), &
   Bisque               = (/char(255),char(228),char(196)/), &
   Burlywood            = (/char(222),char(184),char(135)/), &
   Tancolor             = (/char(210),char(180),char(140)/), &
   AntiqueWhite         = (/char(255),char(235),char(215)/), &
   NavajoWhite          = (/char(255),char(222),char(173)/), &
   BlanchedAlmond       = (/char(255),char(235),char(205)/), &
   PapayaWhip           = (/char(255),char(239),char(213)/), &
!*** Colors 71-80
   Moccasin             = (/char(255),char(228),char(181)/), &
   Wheat                = (/char(245),char(222),char(179)/), &
   Oldlace              = (/char(253),char(245),char(230)/), &
   FloralWhite          = (/char(255),char(250),char(240)/), &
   CornSilk             = (/char(255),char(248),char(220)/), &
   Khaki                = (/char(240),char(230),char(140)/), &
   LemonChiffon         = (/char(255),char(250),char(205)/), &
   PaleGoldenrod        = (/char(238),char(232),char(170)/), &
   DarkKhaki            = (/char(189),char(183),char(107)/), &
   Beige                = (/char(245),char(245),char(220)/), &
!*** Colors 81-90
   LightGoldenrodYellow = (/char(250),char(250),char(210)/), &
   LightYellow          = (/char(255),char(255),char(224)/), &
   Ivory                = (/char(255),char(255),char(240)/), &
   OliveDrab            = (/char(107),char(142),char( 35)/), &
   DarkOliveGreen       = (/char( 85),char(107),char( 47)/), &
   DarkSeaGreen         = (/char(143),char(188),char(143)/), &
   DarkGreen            = (/char(  0),char(100),char(  0)/), &
   ForestGreen          = (/char( 34),char(139),char( 34)/), &
   LightGreen           = (/char(144),char(238),char(144)/), &
   PaleGreen            = (/char(152),char(251),char(152)/), &
!*** Colors 91-100
   Honeydew             = (/char(240),char(255),char(240)/), &
   SeaGreen             = (/char( 46),char(139),char( 87)/), &
   MediumSeaGreen       = (/char( 60),char(179),char(113)/), &
   MintCream            = (/char(245),char(255),char(250)/), &
   MediumAquamarine     = (/char(102),char(205),char(170)/), &
   Aquamarine           = (/char(127),char(255),char(212)/), &
   DarkSlateGray        = (/char( 47),char( 79),char( 79)/), &
   PaleTurquoise        = (/char(179),char(238),char(238)/), &
   LightCyan            = (/char(224),char(255),char(255)/), &
   Azure                = (/char(245),char(255),char(255)/), &
!*** Colors 101-110
   CadetBlue            = (/char( 95),char(158),char(160)/), &
   PowderBlue           = (/char(176),char(224),char(230)/), &
   LightBlue            = (/char(173),char(216),char(230)/), &
   SkyBlue              = (/char(135),char(206),char(235)/), &
   LightskyBlue         = (/char(135),char(206),char(250)/), &
   SteelBlue            = (/char( 70),char(130),char(180)/), &
   AliceBlue            = (/char(240),char(248),char(255)/), &
   SlateGray            = (/char(112),char(128),char(144)/), &
   LightSlateGray       = (/char(119),char(136),char(153)/), &
   LightSteelBlue       = (/char(176),char(196),char(222)/), &
!*** Colors 111-120
   CornflowerBlue       = (/char(100),char(149),char(237)/), &
   Lavender             = (/char(230),char(230),char(250)/), &
   GhostWhite           = (/char(248),char(248),char(255)/), &
   MidnightBlue         = (/char( 25),char( 25),char(112)/), &
   SlateBlue            = (/char(106),char( 90),char(205)/), &
   DarkSlateBlue        = (/char( 72),char( 61),char(139)/), &
   MediumSlateBlue      = (/char(123),char(104),char(238)/), &
   MediumPurple         = (/char(147),char(112),char(219)/), &
   Indigo               = (/char( 75),char(  0),char(130)/), &
   MediumOrchid         = (/char(186),char( 85),char(211)/), &
!*** Colors 121-130
   Plum                 = (/char(221),char(160),char(221)/), &
   Violet               = (/char(238),char(130),char(238)/), &
   Thistle              = (/char(216),char(191),char(216)/), &
   Orchid               = (/char(218),char(112),char(214)/), &
   LavenderBlush        = (/char(255),char(240),char(245)/), &
   PaleVioletRed        = (/char(219),char(112),char(147)/), &
   Pink                 = (/char(255),char(192),char(203)/), &
   LightPink            = (/char(255),char(182),char(193)/), &
   Black                = (/char(  0),char(  0),char(  0)/), &
   DimGray              = (/char(105),char(105),char(105)/), &
!*** Colors 131-137
   Gray                 = (/char(128),char(128),char(128)/), &
   DarkGray             = (/char(169),char(169),char(169)/), &
   Silver               = (/char(192),char(192),char(192)/), &
   LightGray            = (/char(211),char(211),char(211)/), &
   Gainsboro            = (/char(220),char(220),char(220)/), &
   WhiteSmoke           = (/char(245),char(245),char(245)/), &
   White                = (/char(255),char(255),char(255)/)

!**********************************************************************!
! Data dictionary: Functions to allocate RGB, RGBAX arrays.
!**********************************************************************!
character(len=1), allocatable :: RGBdata(:,:,:)         ! data from file
character(len=1), allocatable :: RGBAXdata(:,:,:)       ! data from file
real(kind=dp), allocatable :: Lstar(:,:), &
   astar(:,:),bstar(:,:)                                ! CIELAB colors

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
   character(len=1), allocatable :: mtest(:,:,:) ! test only

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
   character(len=1), allocatable :: mtest(:,:) ! test only

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

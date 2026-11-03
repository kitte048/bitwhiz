subroutine draw_profile( bout, n, x, y, xlo, xhi, ylo, yhi, title_text )
!**********************************************************************!
!  About:                                                              !
!    DRAW_PROFILE makes one line plot, y against x, as a fixed-size    !
!    bitmap, nx by ny pixels, and hands it to bmpmaker: the drawing    !
!    under the tracer plots (draw_trace: velocity against time) and    !
!    the pressure movie's frames (module pics: P against x at one      !
!    time). It was draw_trace's own until the movie needed it with an  !
!    x range and a title of its own (11/02/26); a tracer plot is the   !
!    same, byte for byte.                                              !
!                                                                      !
!    The picture: a white page, and inside it the plot area, framed by !
!    a box with rounded outside corners (the spines) and tick marks at !
!    tenths of each axis, pointing in; in it, a line through the n     !
!    points, x across from xlo (the left edge of the plot area) to xhi !
!    (the right edge), y up from ylo (the bottom edge) to yhi (the top !
!    edge). A point beyond the y axis is drawn at the box's edge, as a !
!    t-x diagram's colors saturate. The box sits nmt pixels below the  !
!    top (the title's margin, as it always was), nml from the left,    !
!    nmr from the right and nmb from the bottom, so there is room for  !
!    the text: title_text, engraved above the box, and the four axis   !
!    ends, in smaller figures: xlo and xhi centered under the box's    !
!    bottom corners, ylo and yhi right-aligned left of its left side,  !
!    level with the plot area's bottom and top. They are written by    !
!    axis_text (module strokes) with the decimals of the axis's step,  !
!    so a caller gives clean ends (nice_ends) and the text is exact.   !
!    No units and no axis names: the screen says what each axis is.    !
!                                                                      !
!    THE TITLE is drawn with strokes, like the curve: each letter is a !
!    few straight lines and elliptical arcs in a cell one cap height   !
!    tall, from bitwhiz's own small stroke font (module strokes, which !
!    also draws the frame, so draw_tx's pictures share this look), set !
!    at th pixels with strokes tsw wide, in slate, centered on the     !
!    page (where the box was centered before its sides moved in for    !
!    the numbers) and in the top margin's height. A stroke font keeps  !
!    the letters anti-aliased the same way as everything else, with no !
!    font file. Letters the font does not have are left blank.         !
!                                                                      !
!    Colors, from the equation sheets' figures (the Okabe-Ito palette, !
!    which colorblind readers can tell apart, beside a dark ink): the  !
!    frame slate #2C3E50 (the sheets' ink), the curve vermilion        !
!    #D55E00. The curve is 3.0 pixels wide, a little wider than the    !
!    2.5-pixel spines; where they meet, the frame is on top.           !
!                                                                      !
!    ANTI-ALIASING. Everything is drawn at ns x ns samples per pixel,  !
!    each sample frame ink, curve ink or paper, and each pixel takes   !
!    the fraction of its samples of each, its coverages cf and cc:     !
!       color = cf*slate + cc*vermilion + (1 - cf - cc)*white.         !
!    A sample is frame ink if it is on a spine or a tick, and curve    !
!    ink (if not frame) if it is within half the curve's width of the  !
!    line through the points: the union of the segments, each with     !
!    round ends, so the joins are round too. This is neighborhood      !
!    averaging of a supersampled image (Russ and Neal, The Image       !
!    Processing Handbook, ch. 4): an edge that cuts a pixel gets the   !
!    shade of how much of the pixel it covers, so curves and rounded   !
!    corners are smooth instead of stair-stepped, and a line does not  !
!    jump from ink to white within one pixel. (A median filter, from   !
!    the same chapter, preserves edges instead: on a drawing that is   !
!    only ink or paper it keeps every edge hard, and a window wider    !
!    than about twice a line's width removes the line.) Straight       !
!    spines start on a pixel boundary, so their outer edge is crisp    !
!    and their inner edge takes the half pixel of the 2.5-pixel width. !
!                                                                      !
!    Colors are set here, pixel by pixel, so no colormap is used       !
!    (bmpmaker writes RGB as given when cmap names none of its         !
!    colormaps). RGB( i, j, 1:3 ) is BLUE, GREEN, RED, the order of a  !
!    bitmap file, as the colormap routines fill it.                    !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer          Description of change            !
!      ====       ==========          =====================            !
!    10/20/26    D. E. Kittell        Original code, as draw_trace:    !
!                (with Claude)        the frame; then (10/21/26) the   !
!                                     curve, the title, anti-aliasing, !
!                                     module strokes (draw_trace's     !
!                                     record)                          !
!    11/02/26    D. E. Kittell        Split from draw_trace as         !
!                (with Claude)        draw_profile: the x range and    !
!                                     the title are arguments, and a   !
!                                     point beyond the y axis is drawn !
!                                     at the box's edge (for the       !
!                                     movie); draw_trace calls it      !
!    11/03/26    D. E. Kittell        The axis ends as numbers: the    !
!                (with Claude)        box's left, right and bottom     !
!                                     sides moved in (nml 100, nmr 60, !
!                                     nmb 70; the top and the title    !
!                                     as before), xlo and xhi under    !
!                                     it, ylo and yhi left of it       !
!                                                                      !
!**********************************************************************!
use bits, only: int8,int32,dp,kpt6,zero,half,one
use strokes, only: frame_t,frame_set,frame_ink,frame_near,stamp,engrave, &
   slate_rgb,nice_ends,axis_text
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
character(len=80), intent(in) :: bout      ! file name, without ".bmp"
integer(kind=int32), intent(in) :: n       ! points
real(kind=dp), intent(in) :: x(n)          ! across (a tracer plot: t, us)
real(kind=dp), intent(in) :: y(n)          ! up (a tracer plot: u, km/s)
real(kind=dp), intent(in) :: xlo, xhi      ! the plot's x axis
real(kind=dp), intent(in) :: ylo, yhi      ! the plot's y axis
character(len=*), intent(in) :: title_text ! engraved above the box

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32), parameter :: nx=800      ! pixels across (x)
integer(kind=int32), parameter :: ny=600      ! pixels up (y)
!*** The box's distance from each side of the page, pixels: the top's
!*** is the title's (as it was when all four were 40); the others make
!*** room for the axis ends' numbers.
integer(kind=int32), parameter :: nmt=40      ! top: the title
integer(kind=int32), parameter :: nml=100     ! left: ylo and yhi
integer(kind=int32), parameter :: nmr=60      ! right: half of xhi
integer(kind=int32), parameter :: nmb=70      ! bottom: xlo and xhi
integer(kind=int32), parameter :: ns=4        ! samples per pixel, each way
real(kind=dp), parameter :: cw=3.0_dp         ! curve width, pixels
!*** The title: its cap height and stroke width (pixels).
real(kind=dp), parameter :: th=16.0_dp        ! cap height, pixels
real(kind=dp), parameter :: tsw=2.2_dp        ! stroke width, pixels
!*** The axis ends' numbers: cap height, stroke width, and their gap
!*** from the box (pixels).
real(kind=dp), parameter :: nh=12.0_dp        ! cap height, pixels
real(kind=dp), parameter :: nsw=1.7_dp        ! stroke width, pixels
real(kind=dp), parameter :: ngap=10.0_dp      ! gap to the box, pixels
!*** The curve's ink, as red, green, blue (0 to 255): Okabe-Ito
!*** vermilion, #D55E00. (The frame's and the title's, slate #2C3E50,
!*** is module strokes' slate_rgb.)
real(kind=dp), parameter, dimension(3) :: crv_rgb = &
   (/ 213.0_dp, 94.0_dp, 0.0_dp /)
integer(kind=int32) :: i,j,k,ii,jj,m          ! loop indices
integer(kind=int32) :: nf,nc                  ! frame, curve samples in a
                                              ! pixel
integer(kind=int32) :: istat                  ! allocation status
real(kind=dp) :: sx,sy                        ! a sample, pixels from the
                                              ! top-left corner
type(frame_t) :: f                            ! the box, plot area, ticks
real(kind=dp) :: cf,cc                        ! a pixel's coverages, 0 to 1
real(kind=dp) :: hs                           ! one sample, in pixels
real(kind=dp), dimension(:), allocatable :: px,py       ! the points, px
real(kind=dp), dimension(:,:), allocatable :: fcn       ! (not used)
character(len=1), dimension(:,:,:), allocatable :: RGB  ! the colors
integer(kind=int8), dimension(:,:), allocatable :: crv  ! samples: 1
                                              ! curve, 2 title, 0 neither
character(len=80) :: cmap                     ! 'rgb': no colormap
real(kind=dp) :: a,b,stx,sty                  ! nice_ends: the ends (as
                                              ! given) and each axis's step

!*** Allocate the image arrays (too large for the stack). bmpmaker
!*** takes fcn too, but with no colormap it never reads it.
allocate( fcn(nx,ny), RGB(nx,ny,3), crv(nx*ns,ny*ns), px(n), py(n), &
   stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_profile could not allocate the image.'
   return
end if
fcn  = zero
cmap = 'rgb'
hs   = one/real( ns, dp )

!*** The geometry, in pixels from the image's top-left corner (pixel
!*** (i, j) covers x from i-1 to i and y from j-1 to j; bmpmaker writes
!*** row j = ny first, the bottom of the image). The box's outside
!*** edges, the margins in from the image's; frame_set puts the plot
!*** area inside the spines (f%xa..f%xb across, x; f%ya..f%yb down, y)
!*** and the ticks at its tenths.
call frame_set( f, real( nml, dp ), real( nx - nmr, dp ), real( nmt, dp ), &
   real( ny - nmb, dp ) )

!*** The points in pixels: xlo at the plot area's left edge, xhi at
!*** its right; ylo at its bottom edge, yhi at its top. A point beyond
!*** the y axis goes to the box's edge (a tracer plot's axis holds all
!*** of its points, so for it this changes nothing).
do k=1,n,1
   if ( xhi > xlo ) then
      px(k) = f%xa + ( x(k) - xlo )/( xhi - xlo )*( f%xb - f%xa )
   else
      px(k) = half*( f%xa + f%xb )
   end if
   if ( yhi > ylo ) then
      py(k) = f%yb - ( y(k) - ylo )/( yhi - ylo )*( f%yb - f%ya )
      py(k) = min( max( py(k), f%ya ), f%yb )
   else
      py(k) = half*( f%ya + f%yb )
   end if
end do

!*** The curve's samples: every sample within half the curve's width
!*** of a segment (or of the one point, for n = 1). Sample (ii, jj) is
!*** at x = (ii - 1/2)/ns, y = (jj - 1/2)/ns.
crv = 0_int8
do k=1,max( n - 1, 1 ),1
   m = min( k + 1, n )
   call stamp( crv, ns, px(k), py(k), px(m), py(m), cw, 1_int8 )
end do

!*** The title's samples (marked 2): centered on the page, its cap
!*** height centered in the top margin.
call engrave( crv, ns, title_text, half*real( nx, dp ), half*f%bt, th, &
   tsw, 2_int8 )

!*** The axis ends (marked 2, slate like the title), with each axis's
!*** decimals (nice_ends' step; the ends given are already clean): xlo
!*** and xhi centered under the plot area's left and right edges, ylo
!*** and yhi ending ngap left of the box, level with the plot area's
!*** bottom and top.
call nice_ends( xlo, xhi, a, b, stx )
call nice_ends( ylo, yhi, a, b, sty )
call engrave( crv, ns, axis_text( xlo, stx ), f%xa, f%bb + ngap + half*nh, &
   nh, nsw, 2_int8 )
call engrave( crv, ns, axis_text( xhi, stx ), f%xb, f%bb + ngap + half*nh, &
   nh, nsw, 2_int8 )
call engrave( crv, ns, axis_text( ylo, sty ), f%bl - ngap, f%yb, nh, nsw, &
   2_int8, 'r' )
call engrave( crv, ns, axis_text( yhi, sty ), f%bl - ngap, f%ya, nh, nsw, &
   2_int8, 'r' )

!*** The page: white. Then each pixel that has ink: its coverages from
!*** its ns x ns samples, the frame first. The title is slate, so its
!*** samples count with the frame's.
RGB = char(255)
do j=1,ny,1
   do i=1,nx,1
      nc = int( sum( crv( (i-1)*ns+1:i*ns, (j-1)*ns+1:j*ns ) ), int32 )
      if ( nc == 0 .and. .not. frame_near( f, real( i, dp ) - half, &
           real( j, dp ) - half ) ) cycle
      nf = 0
      nc = 0
      do jj=1,ns,1
         do ii=1,ns,1
            sx = real( i - 1, dp ) + ( real( ii, dp ) - half )*hs
            sy = real( j - 1, dp ) + ( real( jj, dp ) - half )*hs
            if ( frame_ink( f, sx, sy ) ) then
               nf = nf + 1
            else if ( crv( (i-1)*ns+ii, (j-1)*ns+jj ) == 1_int8 ) then
               nc = nc + 1
            else if ( crv( (i-1)*ns+ii, (j-1)*ns+jj ) == 2_int8 ) then
               nf = nf + 1
            end if
         end do
      end do
      if ( nf + nc == 0 ) cycle
      cf = real( nf, dp )/real( ns*ns, dp )
      cc = real( nc, dp )/real( ns*ns, dp )
      do k=1,3,1
         ! k = 1, 2, 3 is blue, green, red: the ink's 3, 2, 1.
         RGB( i, j, k ) = char( nint( 255.0_dp*( one - cf - cc ) + &
            cf*slate_rgb(4-k) + cc*crv_rgb(4-k) ) )
      end do
   end do
end do

!*** The file.
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )

deallocate( fcn, RGB, crv, px, py )

return

end subroutine draw_profile

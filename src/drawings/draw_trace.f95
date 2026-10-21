subroutine draw_trace( bout, n, t, u, ylo, yhi )
!**********************************************************************!
!  About:                                                              !
!    DRAW_TRACE makes one tracer plot (velocity against time) as a     !
!    fixed-size bitmap, nx by ny pixels, and hands it to bmpmaker.     !
!    Called by module pics (maincode section 9), once per tracer,      !
!    after a run and in a plots_only run.                              !
!                                                                      !
!    The picture: a white page, a margin of nm pixels, and inside it   !
!    the plot area, framed by a box with rounded outside corners (the  !
!    spines) and tick marks at tenths of each axis, pointing in; in    !
!    it, the tracer's velocity against time, a line through its n      !
!    points. Time runs across, from the first point (the left edge of  !
!    the plot area) to the last (the right edge); velocity up, from    !
!    ylo (the bottom edge) to yhi (the top edge). The only text is a   !
!    title engraved in the margin above the box, BITWHIZ SCOPE VIEW;   !
!    the screen gives the ranges.                                      !
!                                                                      !
!    THE TITLE is drawn with strokes, like the curve: each letter is a !
!    few straight lines and elliptical arcs in a cell one cap height   !
!    tall, from bitwhiz's own small stroke font (module strokes, which !
!    also draws the frame, so draw_tx's pictures share this look), set !
!    at th pixels with strokes tsw wide, in slate, centered over the   !
!    box and in the margin's height. A stroke font keeps the letters   !
!    anti-aliased the same way as everything else, with no font file.  !
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
!    10/20/26    D. E. Kittell        Original code: the frame         !
!                (with Claude)                                         !
!    10/21/26    D. E. Kittell        The frame restyled: 2.5-pixel    !
!                (with Claude)        navy spines, rounded outside     !
!                                     corners, anti-aliased (4 x 4     !
!                                     samples per pixel, averaged)     !
!    10/21/26    D. E. Kittell        The curve: the tracer's velocity !
!                (with Claude)        against time, 3.0 pixels wide,   !
!                                     vermilion, anti-aliased the same !
!                                     way; the frame slate #2C3E50     !
!                                     (was navy #1F497D), the sheets'  !
!                                     ink                              !
!    10/21/26    D. E. Kittell        The title BITWHIZ SCOPE VIEW,    !
!                (with Claude)        engraved above the box (a stroke !
!                                     font of its 12 letters)          !
!    10/21/26    D. E. Kittell        The frame, stamp and the font    !
!                (with Claude)        moved to module strokes, shared  !
!                                     with draw_tx; the picture is the !
!                                     same, byte for byte              !
!                                                                      !
!**********************************************************************!
use bits, only: int8,int32,dp,kpt6,zero,half,one
use strokes, only: frame_t,frame_set,frame_ink,frame_near,stamp,engrave, &
   slate_rgb
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
character(len=80), intent(in) :: bout      ! file name, without ".bmp"
integer(kind=int32), intent(in) :: n       ! points
real(kind=dp), intent(in) :: t(n)          ! us, increasing
real(kind=dp), intent(in) :: u(n)          ! km/s
real(kind=dp), intent(in) :: ylo, yhi      ! km/s, the plot's y axis

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32), parameter :: nx=800      ! pixels across (t)
integer(kind=int32), parameter :: ny=600      ! pixels up (u)
integer(kind=int32), parameter :: nm=40       ! margin, pixels
integer(kind=int32), parameter :: ns=4        ! samples per pixel, each way
real(kind=dp), parameter :: cw=3.0_dp         ! curve width, pixels
!*** The title: its text, cap height and stroke width (pixels).
character(len=*), parameter :: title_text='BITWHIZ SCOPE VIEW'
real(kind=dp), parameter :: th=16.0_dp        ! cap height, pixels
real(kind=dp), parameter :: tsw=2.2_dp        ! stroke width, pixels
!*** The curve's ink, as red, green, blue (0 to 255): Okabe-Ito
!*** vermilion, #D55E00. (The frame's and the title's, slate #2C3E50,
!*** is module strokes' slate_rgb.)
real(kind=dp), parameter, dimension(3) :: crv_rgb = &
   (/ 213.0_dp, 94.0_dp, 0.0_dp /)
integer(kind=int32) :: i,j,k,ii,jj,m          ! loop indices
integer(kind=int32) :: nf,nc                  ! frame, curve samples in a
                                              ! pixel
integer(kind=int32) :: istat                  ! allocation status
real(kind=dp) :: x,y                          ! a sample, pixels from the
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

!*** Allocate the image arrays (too large for the stack). bmpmaker
!*** takes fcn too, but with no colormap it never reads it.
allocate( fcn(nx,ny), RGB(nx,ny,3), crv(nx*ns,ny*ns), px(n), py(n), &
   stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_trace could not allocate the image.'
   return
end if
fcn  = zero
cmap = 'rgb'
hs   = one/real( ns, dp )

!*** The geometry, in pixels from the image's top-left corner (pixel
!*** (i, j) covers x from i-1 to i and y from j-1 to j; bmpmaker writes
!*** row j = ny first, the bottom of the image). The box's outside
!*** edges, a margin in from the image's; frame_set puts the plot area
!*** inside the spines (f%xa..f%xb across, time; f%ya..f%yb down,
!*** velocity) and the ticks at its tenths.
call frame_set( f, real( nm, dp ), real( nx - nm, dp ), real( nm, dp ), &
   real( ny - nm, dp ) )

!*** The points in pixels: t(1) at the plot area's left edge, t(n) at
!*** its right; ylo at its bottom edge, yhi at its top.
do k=1,n,1
   if ( t(n) > t(1) ) then
      px(k) = f%xa + ( t(k) - t(1) )/( t(n) - t(1) )*( f%xb - f%xa )
   else
      px(k) = half*( f%xa + f%xb )
   end if
   if ( yhi > ylo ) then
      py(k) = f%yb - ( u(k) - ylo )/( yhi - ylo )*( f%yb - f%ya )
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

!*** The title's samples (marked 2): centered over the box, its cap
!*** height centered in the margin.
call engrave( crv, ns, title_text, half*( f%bl + f%br ), half*f%bt, th, &
   tsw, 2_int8 )

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
            x = real( i - 1, dp ) + ( real( ii, dp ) - half )*hs
            y = real( j - 1, dp ) + ( real( jj, dp ) - half )*hs
            if ( frame_ink( f, x, y ) ) then
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

end subroutine draw_trace

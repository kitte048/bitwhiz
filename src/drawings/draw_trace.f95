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
!    ylo (the bottom edge) to yhi (the top edge). No text: the screen  !
!    gives the ranges.                                                 !
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
!                                                                      !
!**********************************************************************!
use bits, only: int8,int32,dp,kpt6,zero,half,one
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
real(kind=dp), parameter :: lw=2.5_dp         ! spine width, pixels
real(kind=dp), parameter :: rc=12.0_dp        ! outside corner radius, px
real(kind=dp), parameter :: tl=10.0_dp        ! tick length, pixels
real(kind=dp), parameter :: tw=2.0_dp         ! tick width, pixels
real(kind=dp), parameter :: cw=3.0_dp         ! curve width, pixels
!*** The inks, as red, green, blue (0 to 255): the frame slate, #2C3E50,
!*** the equation sheets' ink; the curve Okabe-Ito vermilion, #D55E00.
real(kind=dp), parameter, dimension(3) :: ink_rgb = &
   (/ 44.0_dp, 62.0_dp, 80.0_dp /)
real(kind=dp), parameter, dimension(3) :: crv_rgb = &
   (/ 213.0_dp, 94.0_dp, 0.0_dp /)
integer(kind=int32) :: i,j,k,ii,jj,m          ! loop indices
integer(kind=int32) :: nf,nc                  ! frame, curve samples in a
                                              ! pixel
integer(kind=int32) :: is1,is2,js1,js2        ! samples a segment may reach
integer(kind=int32) :: istat                  ! allocation status
real(kind=dp) :: x,y                          ! a sample, pixels from the
                                              ! top-left corner
real(kind=dp) :: bl,br,bt,bb                  ! the box's outside edges
real(kind=dp) :: xa,xb,ya,yb                  ! the plot area (inside)
real(kind=dp) :: cf,cc                        ! a pixel's coverages, 0 to 1
real(kind=dp) :: hs                           ! one sample, in pixels
real(kind=dp), dimension(9) :: xt,yt          ! tick positions
real(kind=dp), dimension(:), allocatable :: px,py       ! the points, px
real(kind=dp), dimension(:,:), allocatable :: fcn       ! (not used)
character(len=1), dimension(:,:,:), allocatable :: RGB  ! the colors
integer(kind=int8), dimension(:,:), allocatable :: crv  ! curve samples
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
!*** edges, and inside the spines the plot area, whose tenths get ticks
!*** (time across, velocity up).
bl = real( nm, dp )
br = real( nx - nm, dp )
bt = real( nm, dp )
bb = real( ny - nm, dp )
xa = bl + lw
xb = br - lw
ya = bt + lw
yb = bb - lw
do k=1,9,1
   xt(k) = xa + real( k, dp )*( xb - xa )/10.0_dp
   yt(k) = yb - real( k, dp )*( yb - ya )/10.0_dp
end do

!*** The points in pixels: t(1) at the plot area's left edge, t(n) at
!*** its right; ylo at its bottom edge, yhi at its top.
do k=1,n,1
   if ( t(n) > t(1) ) then
      px(k) = xa + ( t(k) - t(1) )/( t(n) - t(1) )*( xb - xa )
   else
      px(k) = half*( xa + xb )
   end if
   if ( yhi > ylo ) then
      py(k) = yb - ( u(k) - ylo )/( yhi - ylo )*( yb - ya )
   else
      py(k) = half*( ya + yb )
   end if
end do

!*** The curve's samples: every sample within half the curve's width
!*** of a segment (or of the one point, for n = 1). Sample (ii, jj) is
!*** at x = (ii - 1/2)/ns, y = (jj - 1/2)/ns.
crv = 0_int8
do k=1,max( n - 1, 1 ),1
   m  = min( k + 1, n )
   is1 = max( 1,     floor( ( min( px(k), px(m) ) - half*cw )*ns ) )
   is2 = min( nx*ns, ceiling( ( max( px(k), px(m) ) + half*cw )*ns ) )
   js1 = max( 1,     floor( ( min( py(k), py(m) ) - half*cw )*ns ) )
   js2 = min( ny*ns, ceiling( ( max( py(k), py(m) ) + half*cw )*ns ) )
   do jj=js1,js2,1
      y = ( real( jj, dp ) - half )*hs
      do ii=is1,is2,1
         x = ( real( ii, dp ) - half )*hs
         if ( seg_dist2( x, y, px(k), py(k), px(m), py(m) ) <= &
              ( half*cw )**2 ) crv( ii, jj ) = 1_int8
      end do
   end do
end do

!*** The page: white. Then each pixel that has ink: its coverages from
!*** its ns x ns samples, the frame first.
RGB = char(255)
do j=1,ny,1
   do i=1,nx,1
      nc = int( sum( crv( (i-1)*ns+1:i*ns, (j-1)*ns+1:j*ns ) ), int32 )
      if ( nc == 0 .and. .not. near( real( i, dp ) - half, &
           real( j, dp ) - half ) ) cycle
      nf = 0
      nc = 0
      do jj=1,ns,1
         do ii=1,ns,1
            x = real( i - 1, dp ) + ( real( ii, dp ) - half )*hs
            y = real( j - 1, dp ) + ( real( jj, dp ) - half )*hs
            if ( inked( x, y ) ) then
               nf = nf + 1
            else if ( crv( (i-1)*ns+ii, (j-1)*ns+jj ) == 1_int8 ) then
               nc = nc + 1
            end if
         end do
      end do
      if ( nf + nc == 0 ) cycle
      cf = real( nf, dp )/real( ns*ns, dp )
      cc = real( nc, dp )/real( ns*ns, dp )
      do k=1,3,1
         ! k = 1, 2, 3 is blue, green, red: the ink's 3, 2, 1.
         RGB( i, j, k ) = char( nint( 255.0_dp*( one - cf - cc ) + &
            cf*ink_rgb(4-k) + cc*crv_rgb(4-k) ) )
      end do
   end do
end do

!*** The file.
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )

deallocate( fcn, RGB, crv, px, py )

return

contains

   !*** Is the point (x, y) frame ink: on a spine or on a tick?
   logical function inked( x, y )
   real(kind=dp), intent(in) :: x, y
   integer(kind=int32) :: mm
   inked = in_rounded( x, y, bl, br, bt, bb, rc ) .and. .not. &
           in_rounded( x, y, xa, xb, ya, yb, max( rc - lw, zero ) )
   if ( inked ) return
   do mm=1,9,1
      ! Time ticks, up from the bottom spine and down from the top.
      if ( abs( x - xt(mm) ) <= half*tw .and. &
           ( ( y >= yb - tl .and. y <= yb ) .or. &
             ( y >= ya .and. y <= ya + tl ) ) ) inked = .true.
      ! Velocity ticks, right from the left spine and left from the right.
      if ( abs( y - yt(mm) ) <= half*tw .and. &
           ( ( x >= xa .and. x <= xa + tl ) .or. &
             ( x >= xb - tl .and. x <= xb ) ) ) inked = .true.
      if ( inked ) return
   end do
   end function inked

   !*** Is (x, y) inside the rectangle l..r by t..b with corners rounded
   !*** to radius rad? (Outside the straight edges: no. In a corner
   !*** square: within rad of the corner circle's center.)
   logical function in_rounded( x, y, l, r, t, b, rad )
   real(kind=dp), intent(in) :: x, y, l, r, t, b, rad
   real(kind=dp) :: ax, ay, dx, dy
   ax = abs( x - half*( l + r ) )
   ay = abs( y - half*( t + b ) )
   dx = max( ax - ( half*( r - l ) - rad ), zero )
   dy = max( ay - ( half*( b - t ) - rad ), zero )
   in_rounded = ( ax <= half*( r - l ) .and. ay <= half*( b - t ) .and. &
                  dx*dx + dy*dy <= rad*rad )
   end function in_rounded

   !*** Could a pixel centered at (x, y) hold frame ink? Only near the
   !*** box: within a pixel of its outside edges, and no deeper inside
   !*** than the ticks reach. (Saves sampling the empty plot area.)
   logical function near( x, y )
   real(kind=dp), intent(in) :: x, y
   near = ( x > bl - one .and. x < br + one .and. &
            y > bt - one .and. y < bb + one ) .and. .not. &
          ( x > xa + tl + one .and. x < xb - tl - one .and. &
            y > ya + tl + one .and. y < yb - tl - one )
   end function near

   !*** The squared distance from (x, y) to the segment from (x1, y1) to
   !*** (x2, y2): to its nearest point, an end if the foot of the
   !*** perpendicular falls outside it.
   real(kind=dp) function seg_dist2( x, y, x1, y1, x2, y2 )
   real(kind=dp), intent(in) :: x, y, x1, y1, x2, y2
   real(kind=dp) :: dx, dy, l2, s
   dx = x2 - x1
   dy = y2 - y1
   l2 = dx*dx + dy*dy
   s  = zero
   if ( l2 > zero ) s = min( max( ( ( x - x1 )*dx + ( y - y1 )*dy )/l2, &
      zero ), one )
   seg_dist2 = ( x - x1 - s*dx )**2 + ( y - y1 - s*dy )**2
   end function seg_dist2

end subroutine draw_trace

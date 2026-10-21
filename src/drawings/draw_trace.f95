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
!    few straight lines and elliptical arcs (as nar segments) in a     !
!    cell one cap height tall, from bitwhiz's own small table (glyph,  !
!    below; only the letters of the title), set at th pixels with      !
!    strokes tsw wide, in slate, centered over the box and in the      !
!    margin's height. A stroke font keeps the letters anti-aliased the !
!    same way as everything else, with no font file.                  !
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
!*** The title: its text, cap height and stroke width (pixels), the
!*** space between letters and a word space (in cap heights), and the
!*** segments per arc.
character(len=*), parameter :: title_text='BITWHIZ SCOPE VIEW'
real(kind=dp), parameter :: th=16.0_dp        ! cap height, pixels
real(kind=dp), parameter :: tsw=2.2_dp        ! stroke width, pixels
real(kind=dp), parameter :: tgap=0.34_dp      ! between letters
real(kind=dp), parameter :: tspace=0.46_dp    ! a word space
integer(kind=int32), parameter :: nar=16      ! segments per arc
real(kind=dp), parameter :: degrad=3.141592653589793_dp/180.0_dp
!*** The inks, as red, green, blue (0 to 255): the frame slate, #2C3E50,
!*** the equation sheets' ink; the curve Okabe-Ito vermilion, #D55E00.
real(kind=dp), parameter, dimension(3) :: ink_rgb = &
   (/ 44.0_dp, 62.0_dp, 80.0_dp /)
real(kind=dp), parameter, dimension(3) :: crv_rgb = &
   (/ 213.0_dp, 94.0_dp, 0.0_dp /)
integer(kind=int32) :: i,j,k,ii,jj,m          ! loop indices
integer(kind=int32) :: nf,nc                  ! frame, curve samples in a
                                              ! pixel
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
integer(kind=int8), dimension(:,:), allocatable :: crv  ! samples: 1
                                              ! curve, 2 title, 0 neither
real(kind=dp) :: gx,gy                        ! a letter's cell, top left
real(kind=dp) :: wt                           ! the title's width, pixels
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
   m = min( k + 1, n )
   call stamp( px(k), py(k), px(m), py(m), cw, 1_int8 )
end do

!*** The title's samples (marked 2): letter by letter, left to right,
!*** centered over the box, the cap height centered in the margin.
wt = zero
do k=1,len( title_text ),1
   wt = wt + advance( title_text(k:k) ) + tgap
end do
wt = wt - tgap
gx = half*( bl + br ) - wt*th/2.0_dp
gy = half*bt - half*th
do k=1,len( title_text ),1
   call glyph( title_text(k:k) )
   gx = gx + ( advance( title_text(k:k) ) + tgap )*th
end do

!*** The page: white. Then each pixel that has ink: its coverages from
!*** its ns x ns samples, the frame first. The title is slate, so its
!*** samples count with the frame's.
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

   !*** Mark (as val) every sample within half of width w of the segment
   !*** from (x1, y1) to (x2, y2). Sample (ii, jj) is at
   !*** x = (ii - 1/2)/ns, y = (jj - 1/2)/ns.
   subroutine stamp( x1, y1, x2, y2, w, val )
   real(kind=dp), intent(in) :: x1, y1, x2, y2, w
   integer(kind=int8), intent(in) :: val
   integer(kind=int32) :: i1, i2, j1, j2, a, b
   real(kind=dp) :: xs, ys
   i1 = max( 1,     floor( ( min( x1, x2 ) - half*w )*ns ) )
   i2 = min( nx*ns, ceiling( ( max( x1, x2 ) + half*w )*ns ) )
   j1 = max( 1,     floor( ( min( y1, y2 ) - half*w )*ns ) )
   j2 = min( ny*ns, ceiling( ( max( y1, y2 ) + half*w )*ns ) )
   do b=j1,j2,1
      ys = ( real( b, dp ) - half )*hs
      do a=i1,i2,1
         xs = ( real( a, dp ) - half )*hs
         if ( seg_dist2( xs, ys, x1, y1, x2, y2 ) <= ( half*w )**2 ) &
            crv( a, b ) = val
      end do
   end do
   end subroutine stamp

   !******************************************************************!
   ! THE TITLE'S LETTERS. Each in a cell one cap height tall: x from  !
   ! 0 (its left) to its advance width, y from 0 (cap top) to 1       !
   ! (baseline); placed at (gx, gy) and scaled by th. gl draws a      !
   ! straight stroke; ga an elliptical arc, center (cx, cy), radii    !
   ! (rx, ry), from angle a0 to a1 in degrees, measured as on paper   !
   ! (0 to the right, 90 up), in nar segments.                        !
   !******************************************************************!
   real(kind=dp) function advance( c )
   character(len=1), intent(in) :: c
   select case ( c )
   case ( 'B' ); advance = 0.72_dp
   case ( 'I' ); advance = 0.00_dp
   case ( 'T' ); advance = 0.70_dp
   case ( 'W' ); advance = 1.00_dp
   case ( 'H' ); advance = 0.70_dp
   case ( 'Z' ); advance = 0.70_dp
   case ( 'S' ); advance = 0.66_dp
   case ( 'C' ); advance = 0.78_dp
   case ( 'O' ); advance = 0.86_dp
   case ( 'P' ); advance = 0.66_dp
   case ( 'E' ); advance = 0.62_dp
   case ( 'V' ); advance = 0.80_dp
   case default; advance = tspace         ! a space (or a letter not
   end select                             ! in the table: left blank)
   end function advance

   subroutine glyph( c )
   character(len=1), intent(in) :: c
   select case ( c )
   case ( 'B' )
      call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
      call gl( 0.00_dp, 0.0_dp, 0.42_dp, 0.0_dp )
      call ga( 0.42_dp, 0.25_dp, 0.25_dp, 0.25_dp, 90.0_dp, -90.0_dp )
      call gl( 0.42_dp, 0.5_dp, 0.00_dp, 0.5_dp )
      call gl( 0.00_dp, 0.5_dp, 0.47_dp, 0.5_dp )
      call ga( 0.47_dp, 0.75_dp, 0.25_dp, 0.25_dp, 90.0_dp, -90.0_dp )
      call gl( 0.47_dp, 1.0_dp, 0.00_dp, 1.0_dp )
   case ( 'I' )
      call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
   case ( 'T' )
      call gl( 0.00_dp, 0.0_dp, 0.70_dp, 0.0_dp )
      call gl( 0.35_dp, 0.0_dp, 0.35_dp, 1.0_dp )
   case ( 'W' )
      call gl( 0.00_dp, 0.0_dp, 0.22_dp, 1.0_dp )
      call gl( 0.22_dp, 1.0_dp, 0.50_dp, 0.3_dp )
      call gl( 0.50_dp, 0.3_dp, 0.78_dp, 1.0_dp )
      call gl( 0.78_dp, 1.0_dp, 1.00_dp, 0.0_dp )
   case ( 'H' )
      call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
      call gl( 0.70_dp, 0.0_dp, 0.70_dp, 1.0_dp )
      call gl( 0.00_dp, 0.5_dp, 0.70_dp, 0.5_dp )
   case ( 'Z' )
      call gl( 0.00_dp, 0.0_dp, 0.70_dp, 0.0_dp )
      call gl( 0.70_dp, 0.0_dp, 0.00_dp, 1.0_dp )
      call gl( 0.00_dp, 1.0_dp, 0.70_dp, 1.0_dp )
   case ( 'S' )
      call ga( 0.33_dp, 0.25_dp, 0.31_dp, 0.25_dp, 25.0_dp, 270.0_dp )
      call ga( 0.33_dp, 0.75_dp, 0.33_dp, 0.25_dp, 90.0_dp, -155.0_dp )
   case ( 'C' )
      call ga( 0.44_dp, 0.5_dp, 0.44_dp, 0.5_dp, 48.0_dp, 312.0_dp )
   case ( 'O' )
      call ga( 0.43_dp, 0.5_dp, 0.43_dp, 0.5_dp, 0.0_dp, 360.0_dp )
   case ( 'P' )
      call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
      call gl( 0.00_dp, 0.0_dp, 0.40_dp, 0.0_dp )
      call ga( 0.40_dp, 0.25_dp, 0.26_dp, 0.25_dp, 90.0_dp, -90.0_dp )
      call gl( 0.40_dp, 0.5_dp, 0.00_dp, 0.5_dp )
   case ( 'E' )
      call gl( 0.62_dp, 0.0_dp, 0.00_dp, 0.0_dp )
      call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
      call gl( 0.00_dp, 1.0_dp, 0.62_dp, 1.0_dp )
      call gl( 0.00_dp, 0.5_dp, 0.52_dp, 0.5_dp )
   case ( 'V' )
      call gl( 0.00_dp, 0.0_dp, 0.40_dp, 1.0_dp )
      call gl( 0.40_dp, 1.0_dp, 0.80_dp, 0.0_dp )
   end select
   end subroutine glyph

   !*** A straight stroke of the current letter, cell coordinates.
   subroutine gl( xa1, ya1, xa2, ya2 )
   real(kind=dp), intent(in) :: xa1, ya1, xa2, ya2
   call stamp( gx + xa1*th, gy + ya1*th, gx + xa2*th, gy + ya2*th, tsw, &
      2_int8 )
   end subroutine gl

   !*** An elliptical arc of the current letter, as nar strokes.
   subroutine ga( cx, cy, rx, ry, a0, a1 )
   real(kind=dp), intent(in) :: cx, cy, rx, ry, a0, a1
   integer(kind=int32) :: q
   real(kind=dp) :: p, q1x, q1y, q2x, q2y
   p   = ( a0 + ( a1 - a0 )*0.0_dp/real( nar, dp ) )*degrad
   q1x = cx + rx*cos( p )
   q1y = cy - ry*sin( p )
   do q=1,nar,1
      p   = ( a0 + ( a1 - a0 )*real( q, dp )/real( nar, dp ) )*degrad
      q2x = cx + rx*cos( p )
      q2y = cy - ry*sin( p )
      call gl( q1x, q1y, q2x, q2y )
      q1x = q2x
      q1y = q2y
   end do
   end subroutine ga

end subroutine draw_trace

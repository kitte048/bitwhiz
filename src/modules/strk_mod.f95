module strokes
!**********************************************************************!
!
!  Purpose:
!    The pieces every bitwhiz picture is drawn with (src/drawings:
!    draw_trace, draw_tx), so all of them share one look:
!
!       frame_t, frame_set, frame_ink, frame_near
!           the box around a plot: slate spines 2.5 pixels wide,
!           outside corners rounded to 12 pixels, ticks at tenths of
!           each axis pointing in
!       stamp
!           mark the samples within half a width of a segment (a
!           stroke with round ends), for curves and letters
!       engrave
!           a title in bitwhiz's own stroke font: each letter a few
!           straight strokes and elliptical arcs in a cell one cap
!           height tall (only the letters bitwhiz's titles use, the
!           ten digits, and . = + - for the movies' times)
!       in_rounded, seg_dist2
!           the geometry under them
!
!    Coordinates are in pixels from the image's top-left corner: pixel
!    (i, j) covers x from i-1 to i and y from j-1 to j. Pictures are
!    drawn at ns x ns samples per pixel and averaged (anti-aliasing;
!    draw_trace explains it); a sample mask has ns times the image's
!    pixels each way, sample (a, b) at x = (a - 1/2)/ns,
!    y = (b - 1/2)/ns.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/21/26    D. E. Kittell        Original code, from draw_trace
!                (with Claude)        (frame, stamp, the font), shared
!                                     with draw_tx; letters R, U, L, Y
!                                     and the digits 0, 1 added
!    11/02/26    D. E. Kittell        For the movies' titles (PRESSURE
!                (with Claude)        AT TIME = +1.234 US): letters A,
!                                     D, M, N, the digits 2 to 9, and
!                                     . = + -
!
!**********************************************************************!
use bits, only: int8, int32, dp, zero, half, one
implicit none
private

public :: frame_t, frame_set, frame_ink, frame_near, stamp, engrave, &
   in_rounded, seg_dist2, slate_rgb

!*** The ink of every frame and title: slate, #2C3E50, the equation
!*** sheets' ink, as red, green, blue (0 to 255).
real(kind=dp), parameter, dimension(3) :: slate_rgb = &
   (/ 44.0_dp, 62.0_dp, 80.0_dp /)

!*** The frame's style, in pixels.
real(kind=dp), parameter :: lw = 2.5_dp       ! spine width
real(kind=dp), parameter :: rc = 12.0_dp      ! outside corner radius
real(kind=dp), parameter :: tl = 10.0_dp      ! tick length
real(kind=dp), parameter :: tw = 2.0_dp       ! tick width

!*** The font: the space between letters and a word space, in cap
!*** heights; segments per arc.
real(kind=dp), parameter :: tgap = 0.34_dp
real(kind=dp), parameter :: tspace = 0.46_dp
integer(kind=int32), parameter :: nar = 16
real(kind=dp), parameter :: degrad = 3.141592653589793_dp/180.0_dp

!*** A frame: the box's outside edges, the plot area inside the spines
!*** (xa..xb across, ya..yb down), and the ticks at its tenths.
type :: frame_t
   real(kind=dp) :: bl, br, bt, bb
   real(kind=dp) :: xa, xb, ya, yb
   real(kind=dp), dimension(9) :: xt, yt
end type frame_t

contains

   !******************************************************************!
   ! A frame whose box has outside edges bl, br (left, right) and     !
   ! bt, bb (top, bottom).                                            !
   !******************************************************************!
   subroutine frame_set( f, bl, br, bt, bb )
   type(frame_t), intent(out) :: f
   real(kind=dp), intent(in) :: bl, br, bt, bb
   integer(kind=int32) :: k
   f%bl = bl
   f%br = br
   f%bt = bt
   f%bb = bb
   f%xa = bl + lw
   f%xb = br - lw
   f%ya = bt + lw
   f%yb = bb - lw
   do k=1,9,1
      f%xt(k) = f%xa + real( k, dp )*( f%xb - f%xa )/10.0_dp
      f%yt(k) = f%yb - real( k, dp )*( f%yb - f%ya )/10.0_dp
   end do
   end subroutine frame_set

   !*** Is the point (x, y) frame ink: on a spine or on a tick?
   logical function frame_ink( f, x, y )
   type(frame_t), intent(in) :: f
   real(kind=dp), intent(in) :: x, y
   integer(kind=int32) :: m
   frame_ink = in_rounded( x, y, f%bl, f%br, f%bt, f%bb, rc ) .and. &
      .not. in_rounded( x, y, f%xa, f%xb, f%ya, f%yb, max( rc - lw, zero ) )
   if ( frame_ink ) return
   do m=1,9,1
      ! Ticks across, up from the bottom spine and down from the top.
      if ( abs( x - f%xt(m) ) <= half*tw .and. &
           ( ( y >= f%yb - tl .and. y <= f%yb ) .or. &
             ( y >= f%ya .and. y <= f%ya + tl ) ) ) frame_ink = .true.
      ! Ticks up, right from the left spine and left from the right.
      if ( abs( y - f%yt(m) ) <= half*tw .and. &
           ( ( x >= f%xa .and. x <= f%xa + tl ) .or. &
             ( x >= f%xb - tl .and. x <= f%xb ) ) ) frame_ink = .true.
      if ( frame_ink ) return
   end do
   end function frame_ink

   !*** Could a pixel centered at (x, y) hold frame ink? Only near the
   !*** box: within a pixel of its outside edges, and no deeper inside
   !*** than the ticks reach. (Saves sampling the empty plot area.)
   logical function frame_near( f, x, y )
   type(frame_t), intent(in) :: f
   real(kind=dp), intent(in) :: x, y
   frame_near = ( x > f%bl - one .and. x < f%br + one .and. &
                  y > f%bt - one .and. y < f%bb + one ) .and. .not. &
                ( x > f%xa + tl + one .and. x < f%xb - tl - one .and. &
                  y > f%ya + tl + one .and. y < f%yb - tl - one )
   end function frame_near

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

   !******************************************************************!
   ! Mark (as val) every sample of mask within half of width w of the !
   ! segment from (x1, y1) to (x2, y2); ns samples per pixel each way.!
   !******************************************************************!
   subroutine stamp( mask, ns, x1, y1, x2, y2, w, val )
   integer(kind=int8), dimension(:,:), intent(inout) :: mask
   integer(kind=int32), intent(in) :: ns
   real(kind=dp), intent(in) :: x1, y1, x2, y2, w
   integer(kind=int8), intent(in) :: val
   integer(kind=int32) :: i1, i2, j1, j2, a, b
   real(kind=dp) :: xs, ys, hs
   hs = one/real( ns, dp )
   i1 = max( 1,              floor( ( min( x1, x2 ) - half*w )*ns ) )
   i2 = min( size( mask, 1 ), ceiling( ( max( x1, x2 ) + half*w )*ns ) )
   j1 = max( 1,              floor( ( min( y1, y2 ) - half*w )*ns ) )
   j2 = min( size( mask, 2 ), ceiling( ( max( y1, y2 ) + half*w )*ns ) )
   do b=j1,j2,1
      ys = ( real( b, dp ) - half )*hs
      do a=i1,i2,1
         xs = ( real( a, dp ) - half )*hs
         if ( seg_dist2( xs, ys, x1, y1, x2, y2 ) <= ( half*w )**2 ) &
            mask( a, b ) = val
      end do
   end do
   end subroutine stamp

   !******************************************************************!
   ! A title, text, in capitals th pixels tall with strokes tsw wide, !
   ! centered across on xc with its cap height centered on yc, marked !
   ! (as val) in mask. A character not in the font is left blank.     !
   !                                                                  !
   ! THE FONT. Each letter in a cell one cap height tall: x from 0    !
   ! (its left) to its advance width, y from 0 (cap top) to 1         !
   ! (baseline); placed at (gx, gy) and scaled by th. gl draws a      !
   ! straight stroke; ga an elliptical arc, center (cx, cy), radii    !
   ! (rx, ry), from angle a0 to a1 in degrees, measured as on paper   !
   ! (0 to the right, 90 up), in nar segments. A new letter is a case !
   ! in advance and in glyph.                                         !
   !******************************************************************!
   subroutine engrave( mask, ns, text, xc, yc, th, tsw, val )
   integer(kind=int8), dimension(:,:), intent(inout) :: mask
   integer(kind=int32), intent(in) :: ns
   character(len=*), intent(in) :: text
   real(kind=dp), intent(in) :: xc, yc, th, tsw
   integer(kind=int8), intent(in) :: val
   real(kind=dp) :: gx, gy, wt
   integer(kind=int32) :: k

   wt = zero
   do k=1,len( text ),1
      wt = wt + advance( text(k:k) ) + tgap
   end do
   wt = wt - tgap
   gx = xc - wt*th/2.0_dp
   gy = yc - half*th
   do k=1,len( text ),1
      call glyph( text(k:k) )
      gx = gx + ( advance( text(k:k) ) + tgap )*th
   end do

   contains

      real(kind=dp) function advance( c )
      character(len=1), intent(in) :: c
      select case ( c )
      case ( '0' ); advance = 0.60_dp
      case ( '1' ); advance = 0.30_dp
      case ( '2' ); advance = 0.60_dp
      case ( '3' ); advance = 0.60_dp
      case ( '4' ); advance = 0.64_dp
      case ( '5' ); advance = 0.60_dp
      case ( '6' ); advance = 0.60_dp
      case ( '7' ); advance = 0.60_dp
      case ( '8' ); advance = 0.60_dp
      case ( '9' ); advance = 0.60_dp
      case ( '.' ); advance = 0.12_dp
      case ( '=' ); advance = 0.56_dp
      case ( '+' ); advance = 0.56_dp
      case ( '-' ); advance = 0.40_dp
      case ( 'A' ); advance = 0.76_dp
      case ( 'B' ); advance = 0.72_dp
      case ( 'C' ); advance = 0.78_dp
      case ( 'D' ); advance = 0.70_dp
      case ( 'E' ); advance = 0.62_dp
      case ( 'H' ); advance = 0.70_dp
      case ( 'I' ); advance = 0.00_dp
      case ( 'L' ); advance = 0.58_dp
      case ( 'M' ); advance = 0.84_dp
      case ( 'N' ); advance = 0.70_dp
      case ( 'O' ); advance = 0.86_dp
      case ( 'P' ); advance = 0.66_dp
      case ( 'R' ); advance = 0.68_dp
      case ( 'S' ); advance = 0.66_dp
      case ( 'T' ); advance = 0.70_dp
      case ( 'U' ); advance = 0.70_dp
      case ( 'V' ); advance = 0.80_dp
      case ( 'W' ); advance = 1.00_dp
      case ( 'Y' ); advance = 0.76_dp
      case ( 'Z' ); advance = 0.70_dp
      case default; advance = tspace      ! a space (or a letter not in
      end select                          ! the font: left blank)
      end function advance

      subroutine glyph( c )
      character(len=1), intent(in) :: c
      select case ( c )
      case ( '0' )
         call ga( 0.30_dp, 0.5_dp, 0.30_dp, 0.5_dp, 0.0_dp, 360.0_dp )
      case ( '1' )
         call gl( 0.04_dp, 0.22_dp, 0.30_dp, 0.0_dp )
         call gl( 0.30_dp, 0.0_dp, 0.30_dp, 1.0_dp )
      case ( '2' )                        ! a hook, a diagonal, a base
         call ga( 0.30_dp, 0.28_dp, 0.29_dp, 0.28_dp, 160.0_dp, -38.0_dp )
         call gl( 0.53_dp, 0.45_dp, 0.00_dp, 1.0_dp )
         call gl( 0.00_dp, 1.0_dp, 0.60_dp, 1.0_dp )
      case ( '3' )                        ! two bowls, open to the left
         call ga( 0.29_dp, 0.25_dp, 0.27_dp, 0.25_dp, 155.0_dp, -90.0_dp )
         call ga( 0.29_dp, 0.74_dp, 0.31_dp, 0.26_dp, 90.0_dp, -155.0_dp )
      case ( '4' )
         call gl( 0.48_dp, 1.0_dp, 0.48_dp, 0.0_dp )
         call gl( 0.48_dp, 0.0_dp, 0.00_dp, 0.68_dp )
         call gl( 0.00_dp, 0.68_dp, 0.64_dp, 0.68_dp )
      case ( '5' )                        ! a flag, a stem, a bowl
         call gl( 0.56_dp, 0.0_dp, 0.06_dp, 0.0_dp )
         call gl( 0.06_dp, 0.0_dp, 0.05_dp, 0.47_dp )
         call ga( 0.29_dp, 0.68_dp, 0.30_dp, 0.31_dp, 135.0_dp, -150.0_dp )
      case ( '6' )                        ! a bowl below, a stroke into it
         call ga( 0.30_dp, 0.69_dp, 0.30_dp, 0.31_dp, 0.0_dp, 360.0_dp )
         call ga( 0.42_dp, 0.62_dp, 0.42_dp, 0.62_dp, 72.0_dp, 180.0_dp )
         call gl( 0.00_dp, 0.62_dp, 0.00_dp, 0.69_dp )
      case ( '7' )
         call gl( 0.00_dp, 0.0_dp, 0.60_dp, 0.0_dp )
         call gl( 0.60_dp, 0.0_dp, 0.20_dp, 1.0_dp )
      case ( '8' )                        ! two rings, the lower wider
         call ga( 0.30_dp, 0.25_dp, 0.25_dp, 0.25_dp, 0.0_dp, 360.0_dp )
         call ga( 0.30_dp, 0.74_dp, 0.30_dp, 0.26_dp, 0.0_dp, 360.0_dp )
      case ( '9' )                        ! the 6 turned over
         call ga( 0.30_dp, 0.31_dp, 0.30_dp, 0.31_dp, 0.0_dp, 360.0_dp )
         call ga( 0.18_dp, 0.38_dp, 0.42_dp, 0.62_dp, 0.0_dp, -108.0_dp )
         call gl( 0.60_dp, 0.31_dp, 0.60_dp, 0.38_dp )
      case ( '.' )                        ! a ring the stroke fills: a dot
         call ga( 0.06_dp, 0.93_dp, 0.05_dp, 0.05_dp, 0.0_dp, 360.0_dp )
      case ( '=' )
         call gl( 0.00_dp, 0.36_dp, 0.56_dp, 0.36_dp )
         call gl( 0.00_dp, 0.64_dp, 0.56_dp, 0.64_dp )
      case ( '+' )
         call gl( 0.28_dp, 0.22_dp, 0.28_dp, 0.78_dp )
         call gl( 0.00_dp, 0.5_dp, 0.56_dp, 0.5_dp )
      case ( '-' )
         call gl( 0.00_dp, 0.5_dp, 0.40_dp, 0.5_dp )
      case ( 'A' )
         call gl( 0.00_dp, 1.0_dp, 0.38_dp, 0.0_dp )
         call gl( 0.38_dp, 0.0_dp, 0.76_dp, 1.0_dp )
         call gl( 0.14_dp, 0.64_dp, 0.62_dp, 0.64_dp )
      case ( 'B' )
         call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.42_dp, 0.0_dp )
         call ga( 0.42_dp, 0.25_dp, 0.25_dp, 0.25_dp, 90.0_dp, -90.0_dp )
         call gl( 0.42_dp, 0.5_dp, 0.00_dp, 0.5_dp )
         call gl( 0.00_dp, 0.5_dp, 0.47_dp, 0.5_dp )
         call ga( 0.47_dp, 0.75_dp, 0.25_dp, 0.25_dp, 90.0_dp, -90.0_dp )
         call gl( 0.47_dp, 1.0_dp, 0.00_dp, 1.0_dp )
      case ( 'C' )
         call ga( 0.44_dp, 0.5_dp, 0.44_dp, 0.5_dp, 48.0_dp, 312.0_dp )
      case ( 'D' )
         call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.25_dp, 0.0_dp )
         call ga( 0.25_dp, 0.5_dp, 0.45_dp, 0.5_dp, 90.0_dp, -90.0_dp )
         call gl( 0.25_dp, 1.0_dp, 0.00_dp, 1.0_dp )
      case ( 'E' )
         call gl( 0.62_dp, 0.0_dp, 0.00_dp, 0.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
         call gl( 0.00_dp, 1.0_dp, 0.62_dp, 1.0_dp )
         call gl( 0.00_dp, 0.5_dp, 0.52_dp, 0.5_dp )
      case ( 'H' )
         call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
         call gl( 0.70_dp, 0.0_dp, 0.70_dp, 1.0_dp )
         call gl( 0.00_dp, 0.5_dp, 0.70_dp, 0.5_dp )
      case ( 'I' )
         call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
      case ( 'L' )
         call gl( 0.00_dp, 0.0_dp, 0.00_dp, 1.0_dp )
         call gl( 0.00_dp, 1.0_dp, 0.58_dp, 1.0_dp )
      case ( 'M' )
         call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.42_dp, 0.72_dp )
         call gl( 0.42_dp, 0.72_dp, 0.84_dp, 0.0_dp )
         call gl( 0.84_dp, 0.0_dp, 0.84_dp, 1.0_dp )
      case ( 'N' )
         call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.70_dp, 1.0_dp )
         call gl( 0.70_dp, 1.0_dp, 0.70_dp, 0.0_dp )
      case ( 'O' )
         call ga( 0.43_dp, 0.5_dp, 0.43_dp, 0.5_dp, 0.0_dp, 360.0_dp )
      case ( 'P' )
         call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.40_dp, 0.0_dp )
         call ga( 0.40_dp, 0.25_dp, 0.26_dp, 0.25_dp, 90.0_dp, -90.0_dp )
         call gl( 0.40_dp, 0.5_dp, 0.00_dp, 0.5_dp )
      case ( 'R' )
         call gl( 0.00_dp, 1.0_dp, 0.00_dp, 0.0_dp )
         call gl( 0.00_dp, 0.0_dp, 0.40_dp, 0.0_dp )
         call ga( 0.40_dp, 0.25_dp, 0.26_dp, 0.25_dp, 90.0_dp, -90.0_dp )
         call gl( 0.40_dp, 0.5_dp, 0.00_dp, 0.5_dp )
         call gl( 0.34_dp, 0.5_dp, 0.68_dp, 1.0_dp )
      case ( 'S' )
         call ga( 0.33_dp, 0.25_dp, 0.31_dp, 0.25_dp, 25.0_dp, 270.0_dp )
         call ga( 0.33_dp, 0.75_dp, 0.33_dp, 0.25_dp, 90.0_dp, -155.0_dp )
      case ( 'T' )
         call gl( 0.00_dp, 0.0_dp, 0.70_dp, 0.0_dp )
         call gl( 0.35_dp, 0.0_dp, 0.35_dp, 1.0_dp )
      case ( 'U' )
         call gl( 0.00_dp, 0.0_dp, 0.00_dp, 0.65_dp )
         call ga( 0.35_dp, 0.65_dp, 0.35_dp, 0.35_dp, 180.0_dp, 360.0_dp )
         call gl( 0.70_dp, 0.65_dp, 0.70_dp, 0.0_dp )
      case ( 'V' )
         call gl( 0.00_dp, 0.0_dp, 0.40_dp, 1.0_dp )
         call gl( 0.40_dp, 1.0_dp, 0.80_dp, 0.0_dp )
      case ( 'W' )
         call gl( 0.00_dp, 0.0_dp, 0.22_dp, 1.0_dp )
         call gl( 0.22_dp, 1.0_dp, 0.50_dp, 0.3_dp )
         call gl( 0.50_dp, 0.3_dp, 0.78_dp, 1.0_dp )
         call gl( 0.78_dp, 1.0_dp, 1.00_dp, 0.0_dp )
      case ( 'Y' )
         call gl( 0.00_dp, 0.0_dp, 0.38_dp, 0.52_dp )
         call gl( 0.76_dp, 0.0_dp, 0.38_dp, 0.52_dp )
         call gl( 0.38_dp, 0.52_dp, 0.38_dp, 1.0_dp )
      case ( 'Z' )
         call gl( 0.00_dp, 0.0_dp, 0.70_dp, 0.0_dp )
         call gl( 0.70_dp, 0.0_dp, 0.00_dp, 1.0_dp )
         call gl( 0.00_dp, 1.0_dp, 0.70_dp, 1.0_dp )
      end select
      end subroutine glyph

      !*** A straight stroke of the current letter, cell coordinates.
      subroutine gl( xa1, ya1, xa2, ya2 )
      real(kind=dp), intent(in) :: xa1, ya1, xa2, ya2
      call stamp( mask, ns, gx + xa1*th, gy + ya1*th, gx + xa2*th, &
         gy + ya2*th, tsw, val )
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

   end subroutine engrave

end module strokes

subroutine draw_trace( bout )
!**********************************************************************!
!  About:                                                              !
!    DRAW_TRACE makes one tracer plot (velocity against time) as a     !
!    fixed-size bitmap, nx by ny pixels, and hands it to bmpmaker.     !
!    Called by module pics (maincode section 9), once per tracer,      !
!    after a run and in a plots_only run.                              !
!                                                                      !
!    The picture: a white page, a margin of nm pixels, and inside it   !
!    the plot area, framed by a box with rounded outside corners (the  !
!    spines) and tick marks at tenths of each axis, pointing in. Time  !
!    runs across, from the first to the last row of the tracer file;   !
!    velocity up. No text: the screen gives the ranges.                !
!                                                                      !
!    ANTI-ALIASING. The frame is drawn at ns x ns samples per pixel    !
!    (each sample in or out of the ink), and each pixel takes the      !
!    fraction of its samples that are ink, its coverage c (0 to 1):    !
!       color = c*ink + (1 - c)*white.                                 !
!    That is neighborhood averaging of a supersampled image (Russ and  !
!    Neal, The Image Processing Handbook, ch. 4): an edge that cuts a  !
!    pixel gets the shade of how much of the pixel it covers, so a     !
!    rounded corner is smooth instead of a staircase, and a spine does !
!    not jump from solid to white within one pixel. (A median filter,  !
!    from the same chapter, preserves edges instead: on a drawing that !
!    is only ink or paper it keeps every edge hard, and a window wider !
!    than about twice a line's width removes the line.) Straight       !
!    spines start on a pixel boundary, so their outer edge is crisp    !
!    and their inner edge takes the half pixel of the 2.5-pixel width. !
!                                                                      !
!    Colors are set here, pixel by pixel, so no colormap is used       !
!    (bmpmaker writes RGB as given when cmap names none of its         !
!    colormaps). RGB( i, j, 1:3 ) is BLUE, GREEN, RED, the order of a  !
!    bitmap file, as the colormap routines fill it.                    !
!                                                                      !
!    THIS VERSION DRAWS THE FRAME ONLY (spines and ticks). The curve   !
!    comes next.                                                       !
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
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6,zero,half,one
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
character(len=80), intent(in) :: bout      ! file name, without ".bmp"

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
!*** The ink: a muted navy, #1F497D, as red, green, blue (0 to 255).
real(kind=dp), parameter, dimension(3) :: ink_rgb = &
   (/ 31.0_dp, 73.0_dp, 125.0_dp /)
integer(kind=int32) :: i,j,k,ii,jj            ! loop indices
integer(kind=int32) :: nin                    ! ink samples in a pixel
integer(kind=int32) :: istat                  ! allocation status
real(kind=dp) :: x,y                          ! a sample, pixels from the
                                              ! top-left corner
real(kind=dp) :: bl,br,bt,bb                  ! the box's outside edges
real(kind=dp) :: xa,xb,ya,yb                  ! the plot area (inside)
real(kind=dp) :: c                            ! a pixel's coverage, 0 to 1
real(kind=dp), dimension(9) :: xt,yt          ! tick positions
real(kind=dp), dimension(:,:), allocatable :: fcn       ! (not used)
character(len=1), dimension(:,:,:), allocatable :: RGB  ! the colors
character(len=80) :: cmap                     ! 'rgb': no colormap

!*** Allocate the image arrays (too large for the stack). bmpmaker
!*** takes fcn too, but with no colormap it never reads it.
allocate( fcn(nx,ny), RGB(nx,ny,3), stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_trace could not allocate the image.'
   return
end if
fcn = zero
cmap = 'rgb'

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

!*** The page: white. Then every pixel near the frame (the rest has
!*** no ink): its coverage from ns x ns samples at their centers.
RGB = char(255)
do j=1,ny,1
   do i=1,nx,1
      if ( .not. near( real( i, dp ) - half, real( j, dp ) - half ) ) cycle
      nin = 0
      do jj=1,ns,1
         do ii=1,ns,1
            x = real( i - 1, dp ) + ( real( ii, dp ) - half )/real( ns, dp )
            y = real( j - 1, dp ) + ( real( jj, dp ) - half )/real( ns, dp )
            if ( inked( x, y ) ) nin = nin + 1
         end do
      end do
      if ( nin == 0 ) cycle
      c = real( nin, dp )/real( ns*ns, dp )
      RGB( i, j, 1 ) = char( nint( 255.0_dp*( one - c ) + c*ink_rgb(3) ) )
      RGB( i, j, 2 ) = char( nint( 255.0_dp*( one - c ) + c*ink_rgb(2) ) )
      RGB( i, j, 3 ) = char( nint( 255.0_dp*( one - c ) + c*ink_rgb(1) ) )
   end do
end do

!*** The file.
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )

deallocate( fcn, RGB )

return

contains

   !*** Is the point (x, y) ink: on a spine or on a tick?
   logical function inked( x, y )
   real(kind=dp), intent(in) :: x, y
   integer(kind=int32) :: m
   inked = in_rounded( x, y, bl, br, bt, bb, rc ) .and. .not. &
           in_rounded( x, y, xa, xb, ya, yb, max( rc - lw, zero ) )
   if ( inked ) return
   do m=1,9,1
      ! Time ticks, up from the bottom spine and down from the top.
      if ( abs( x - xt(m) ) <= half*tw .and. &
           ( ( y >= yb - tl .and. y <= yb ) .or. &
             ( y >= ya .and. y <= ya + tl ) ) ) inked = .true.
      ! Velocity ticks, right from the left spine and left from the right.
      if ( abs( y - yt(m) ) <= half*tw .and. &
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

   !*** Could a pixel centered at (x, y) hold any ink? Only near the box:
   !*** within a pixel of its outside edges, and no deeper inside than
   !*** the ticks reach. (Saves sampling the empty plot area.)
   logical function near( x, y )
   real(kind=dp), intent(in) :: x, y
   near = ( x > bl - one .and. x < br + one .and. &
            y > bt - one .and. y < bb + one ) .and. .not. &
          ( x > xa + tl + one .and. x < xb - tl - one .and. &
            y > ya + tl + one .and. y < yb - tl - one )
   end function near

end subroutine draw_trace

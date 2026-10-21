subroutine draw_tx( var, bout, cmap, clo, chi )
!**********************************************************************!
!  About:                                                              !
!    DRAW_TX makes one t-x diagram (u or P) as a fixed-size bitmap,    !
!    nx by ny pixels, and hands it to bmpmaker. Called by module pics  !
!    (maincode section 9), after a run and in a plots_only run, once   !
!    the history file has been read (module hist, the hr_ arrays).     !
!                                                                      !
!    The picture, in the style of the tracer plots (draw_trace; the    !
!    frame, the font and the slate ink are module strokes'): a white   !
!    page; a box with rounded outside corners and ticks at tenths of   !
!    each axis, pointing in; the title engraved above it, BITWHIZ      !
!    PRESSURE VIEW or BITWHIZ VELOCITY VIEW; and below it a color bar, !
!    the colormap from 0 (the window's low end, left) to 1 (its high   !
!    end, right), outlined in slate and labeled 0 and 1. The screen    !
!    gives the ranges.                                                 !
!                                                                      !
!    Inside the box, the plot area, in the LAB frame: x across, from   !
!    the smallest face position of the whole run (left edge) to the    !
!    largest (right edge); t up, from 0 (bottom edge) to the last      !
!    frame (top edge). Every cell is drawn between its two faces where !
!    they are at that time, so a material line (a face) is a curve of  !
!    slope dx/dt = u, and a shock front's slope is the shock velocity. !
!                                                                      !
!    Pressure: the deck's colormap over the color window clo to chi    !
!    (values beyond it take its end colors), and WHITE                 !
!      - where there is no material (beyond the free surfaces),        !
!      - in material no wave has reached yet: a cell is white until    !
!        its |P| first exceeds pzero (in any frame so far), and        !
!      - in open spall: a broken cell (D = 1) at P = 0 (|P| <= pzero). !
!        Squeezed shut again it carries pressure and is colored.       !
!    Material that a release has brought back to about zero pressure   !
!    stays colored: it has been shocked. pzero is 1e-6 of the run's    !
!    largest |P|, not 0: in the lab frame a moving, unshocked flyer's  !
!    faces move every step, so its cell widths, and its densities,     !
!    pick up round-off, and its P is ~1e-14 GPa, not exactly 0.        !
!                                                                      !
!    Velocity: the deck's colormap over its window, and WHITE only     !
!    where there is no material and in open spall (as above). The u of !
!    the history file is at the FACES (AV's u, RS's u*), so within a   !
!    cell u runs linearly from its left face to its right face.        !
!    Untouched material is colored: a moving flyer has a velocity, and !
!    material at rest has u = 0.                                       !
!                                                                      !
!    HOW THE PLOT AREA IS FILLED: like the mixed cells of an Eulerian  !
!    hydrocode. Each pixel row is ns sub-rows, each at its own time t; !
!    the faces at t are interpolated between the two frames around it, !
!    so material moves smoothly between frames, and each cell's state  !
!    is the nearer frame's. In a sub-row, each cell lays its length    !
!    over the pixels it covers: a pixel gets the cells' mean value     !
!    (length-weighted; for u, the mean of the line over the part of    !
!    the cell it covers, its value at that part's midpoint) and its    !
!    COVERAGE, the fraction of its width that colored cells fill.      !
!    White cells add nothing: what they cover is paper. The sub-row's  !
!    color is                                                          !
!       coverage*colormap(mean) + (1 - coverage)*white,                !
!    and the pixel the average of its sub-rows. So a free surface, a   !
!    spall plane or the edge of a wave that cuts a pixel gives the     !
!    pixel the shade of how much of it is colored, and a line in t-x   !
!    (a surface moving at any speed) is smooth instead of stair-       !
!    stepped. It is anti-aliasing by area coverage, horizontally       !
!    exact and vertically by ns samples. Cells smaller than a pixel    !
!    (a compressed metal) are averaged, never skipped.                 !
!                                                                      !
!    The frame, title, color bar outline and labels are slate, drawn   !
!    at ns x ns samples per pixel (draw_trace explains it); a pixel    !
!    with frame coverage cf is cf*slate + (1 - cf)*(what is under it). !
!                                                                      !
!    Pixel (i, j) covers x from i-1 to i and y from j-1 to j, from the !
!    image's top-left corner. bmpmaker writes row j = ny first, which  !
!    is the BOTTOM of the image. RGB( i, j, 1:3 ) is BLUE, GREEN, RED, !
!    the order of a bitmap file, as the colormap routines fill it.     !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer          Description of change            !
!      ====       ==========          =====================            !
!    10/20/26    D. E. Kittell        Original code: the fiducial      !
!                (with Claude)                                         !
!    10/20/26    D. E. Kittell        Pressure from the history file,  !
!                (with Claude)        lab frame, white rule; schemes 1 !
!                                     and 2 (ischeme)                  !
!    10/20/26    D. E. Kittell        White: not yet reached (|P| has  !
!                (with Claude)        never exceeded pzero), or open   !
!                                     spall (D = 1, P = 0)             !
!    10/20/26    D. E. Kittell        Renamed draw_tx (was draw_xt);   !
!                (with Claude)        the velocity from the history    !
!                                     file, linear across each cell    !
!    10/21/26    D. E. Kittell        The scope view's look: frame,    !
!                (with Claude)        engraved title, color bar (from  !
!                                     module strokes); the plot area   !
!                                     anti-aliased by coverage (ns     !
!                                     sub-rows per row); scheme 1 gone !
!                                                                      !
!**********************************************************************!
use bits, only: int8,int32,dp,kpt6,zero,half,one
use hist, only: hr_nframes,hr_kmax,hr_time,hr_x,hr_u,hr_p,hr_d
use strokes, only: frame_t,frame_set,frame_ink,frame_near,engrave, &
   in_rounded,slate_rgb
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
character(len=*), intent(in) :: var        ! 'u' or 'P'
character(len=80), intent(in) :: bout      ! file name, without ".bmp"
character(len=80), intent(in) :: cmap      ! the deck's colormap
real(kind=dp), intent(in) :: clo, chi      ! the color window (GPa, km/s)

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32), parameter :: nx=1200     ! pixels across (x)
integer(kind=int32), parameter :: ny=900      ! pixels down (t up)
integer(kind=int32), parameter :: ns=4        ! samples (and sub-rows) per
                                              ! pixel, each way
!*** The box's outside edges, pixels: a 40-pixel margin left, right and
!*** above (the title's), 80 below (the color bar's).
real(kind=dp), parameter :: bl=40.0_dp, br=1160.0_dp
real(kind=dp), parameter :: bt=40.0_dp, bb=820.0_dp
!*** The title: cap height and stroke width (pixels), as the scope's.
real(kind=dp), parameter :: th=16.0_dp
real(kind=dp), parameter :: tsw=2.2_dp
!*** The color bar: its outside edges, outline width and corner radius
!*** (pixels); its labels' cap height, stroke width and distance from
!*** the bar's ends to their centers.
real(kind=dp), parameter :: cbl=300.0_dp, cbr=900.0_dp
real(kind=dp), parameter :: cbt=842.0_dp, cbb=860.0_dp
real(kind=dp), parameter :: cbw=1.5_dp, cbrad=5.0_dp
real(kind=dp), parameter :: lth=12.0_dp, lsw=1.8_dp, lgap=16.0_dp
real(kind=dp), parameter :: zero_frac=1.0e-6_dp  ! pzero / largest |P|
integer(kind=int32) :: i,j,k,s,ii,jj          ! loop indices
integer(kind=int32) :: i1,i2                  ! pixels a cell covers
integer(kind=int32) :: ilo,ihi                ! pixels the plot area touches
integer(kind=int32) :: jf,jn                  ! frame at/before t, nearer
integer(kind=int32) :: jt                     ! frames seen by 'reached'
integer(kind=int32) :: nf,kmax                ! frames, cells
integer(kind=int32) :: nsub                   ! sub-rows in the plot area
integer(kind=int32) :: nfk,nbk                ! frame, bar samples in a pixel
integer(kind=int32) :: istat                  ! allocation status
type(frame_t) :: f                            ! the box, plot area, ticks
real(kind=dp) :: xmin,xmax,sc                 ! mm: the run's x; px per mm
real(kind=dp) :: tend,t,w,ys                  ! us: top edge, a sub-row's t;
                                              ! its y, pixels
real(kind=dp) :: a,b,lo,hi,ov                 ! px: a cell, a pixel, overlap
real(kind=dp) :: p,span                       ! a cell's P (GPa), the window
real(kind=dp) :: ua,ub                        ! km/s: u at a cell's faces
real(kind=dp) :: v                            ! the value drawn (P or u)
real(kind=dp) :: x,y,hs                       ! a sample, pixels; one sample
real(kind=dp) :: cf,cb                        ! frame, bar fill coverages
real(kind=dp) :: bxa,bxb,bya,byb              ! the bar's fill (inside its
                                              ! outline)
real(kind=dp), dimension(3) :: col            ! a pixel's red, green, blue
logical :: isu                                ! drawing u (not P)
logical :: blank                              ! this cell is white now
real(kind=dp) :: pzero                        ! GPa: |P| below this is 0
real(kind=dp), dimension(:,:), allocatable :: fcn       ! (not used)
character(len=1), dimension(:,:,:), allocatable :: RGB  ! the colors
real(kind=dp), dimension(:,:), allocatable :: f4,c4     ! a row's sub-rows:
                                              ! window value, coverage
character(len=1), dimension(:,:,:), allocatable :: rgb4 ! and their colors
real(kind=dp), dimension(:,:), allocatable :: dat       ! a row's plot-area
                                              ! colors, red, green, blue
real(kind=dp), dimension(:,:), allocatable :: fb        ! the bar's values
character(len=1), dimension(:,:,:), allocatable :: rgbb ! and colors
logical, dimension(:), allocatable :: reached           ! a wave has
                                              ! reached the cell (so far)
real(kind=dp), dimension(:), allocatable :: xf          ! faces at t, px
real(kind=dp), dimension(:), allocatable :: acc,clen    ! per pixel: sum
                                              ! of v*length, colored length
integer(kind=int8), dimension(:,:), allocatable :: txt  ! samples: 2 text
character(len=80) :: none                     ! 'rgb': no colormap
character(len=21) :: title_text               ! the title

!*** Allocate the image arrays (too large for the stack).
nf   = hr_nframes
kmax = hr_kmax
allocate( fcn(nx,ny), RGB(nx,ny,3), f4(nx,ns), c4(nx,ns), rgb4(nx,ns,3), &
   dat(nx,3), fb(nx,1), rgbb(nx,1,3), xf(kmax+1), acc(nx), clen(nx), &
   reached(kmax), txt(nx*ns,ny*ns), stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_tx could not allocate the image.'
   return
end if

isu = ( var == 'u' )
if ( isu ) then
   title_text = 'BITWHIZ VELOCITY VIEW'
else
   title_text = 'BITWHIZ PRESSURE VIEW'
end if
hs = one/real( ns, dp )

!*** The box, and inside its spines the plot area f%xa..f%xb across,
!*** f%ya..f%yb down (in pixels; not on pixel boundaries: a spine is
!*** 2.5 pixels wide). The pixels it touches, across: ilo to ihi.
call frame_set( f, bl, br, bt, bb )
ilo = floor( f%xa ) + 1
ihi = ceiling( f%xb )

!*** The run's x (mm) onto the plot area's width (pixels); t from 0 at
!*** its bottom edge to the last frame at its top.
xmin = real( minval( hr_x(:,1:nf) ), dp )
xmax = real( maxval( hr_x(:,1:nf) ), dp )
sc   = zero
if ( xmax > xmin ) sc = ( f%xb - f%xa )/( xmax - xmin )
tend = hr_time(nf)
span = chi - clo
pzero = zero_frac*real( maxval( abs( hr_p(:,1:nf) ) ), dp )

!*** The text's samples (marked 2): the title centered over the box in
!*** the top margin, as the scope's; 0 and 1 at the bar's ends.
txt = 0_int8
call engrave( txt, ns, trim( title_text ), half*( bl + br ), half*bt, th, &
   tsw, 2_int8 )
call engrave( txt, ns, '0', cbl - lgap, half*( cbt + cbb ), lth, lsw, &
   2_int8 )
call engrave( txt, ns, '1', cbr + lgap, half*( cbt + cbb ), lth, lsw, &
   2_int8 )

!*** The color bar's fill, inside its outline, and its colors: each
!*** pixel column the colormap at the column's center, 0 at the fill's
!*** left edge, 1 at its right.
bxa = cbl + cbw
bxb = cbr - cbw
bya = cbt + cbw
byb = cbb - cbw
do i=1,nx,1
   fb( i, 1 ) = min( max( ( real( i, dp ) - half - bxa )/( bxb - bxa ), &
      zero ), one )
end do
call apply_colormap( nx, 1, fb, rgbb, cmap )

!*** Row by row, from the bottom (t = 0) up, and in each row its
!*** sub-rows from the bottom up, so t only increases ('reached' and
!*** the frames only move forward).
fcn     = zero
RGB     = char(255)
reached = .false.
jf      = 1
jt      = 0
rows: do j=ny,1,-1

   ! The plot area's colors in this row (white where it has none).
   dat  = 255.0_dp
   nsub = 0
   f4   = zero
   c4   = zero
   if ( real( j, dp ) > f%ya .and. real( j - 1, dp ) < f%yb ) then
      subrows: do s=ns,1,-1
         ys = real( j - 1, dp ) + ( real( s, dp ) - half )*hs
         if ( ys < f%ya .or. ys > f%yb ) cycle subrows
         nsub = nsub + 1
         t = ( f%yb - ys )/( f%yb - f%ya )*tend

         ! The frames around t: jf at or before it, jf+1 after it.
         do while ( jf < nf - 1 )
            if ( hr_time(jf+1) > t ) exit
            jf = jf + 1
         end do

         ! The faces at t, in pixels, and the frame each cell's state
         ! comes from (jn).
         if ( nf == 1 ) then
            xf = f%xa + ( real( hr_x(:,1), dp ) - xmin )*sc
            jn = 1
         else
            w  = ( t - hr_time(jf) )/( hr_time(jf+1) - hr_time(jf) )
            w  = min( max( w, zero ), one )
            xf = f%xa + ( ( one - w )*real( hr_x(:,jf), dp ) + &
               w*real( hr_x(:,jf+1), dp ) - xmin )*sc
            jn = jf
            if ( w >= half ) jn = jf + 1
         end if

         ! Which cells a wave has reached, up to frame jn.
         do while ( jt < jn )
            jt = jt + 1
            reached = reached .or. ( abs( real( hr_p(:,jt), dp ) ) > pzero )
         end do

         ! Each cell onto the pixels it covers, by the length it covers.
         ! A white cell adds nothing: what is not colored is white.
         acc  = zero
         clen = zero
         cells: do k=1,kmax,1
            a = xf(k)
            b = xf(k+1)
            p = real( hr_p(k,jn), dp )
            ua = real( hr_u(k,jn), dp )
            ub = real( hr_u(k+1,jn), dp )
            ! White: open spall in both; in P also not reached yet.
            blank = ( hr_d(k,jn) == 1 .and. .not. ( abs(p) > pzero ) )
            if ( .not. isu ) blank = blank .or. ( .not. reached(k) )
            if ( blank ) cycle cells
            i1 = max( ilo, floor( a ) + 1 )
            i2 = min( ihi, floor( b ) + 1 )
            do i=i1,i2,1
               lo = max( real( i - 1, dp ), f%xa )
               hi = min( real( i, dp ), f%xb )
               ov = min( b, hi ) - max( a, lo )
               if ( ov > zero ) then
                  ! The mean over the overlap: the value at its midpoint
                  ! (P is the same across a cell, u linear in x).
                  v = value( half*( max( a, lo ) + min( b, hi ) ) )
                  acc(i)  = acc(i)  + ov*v
                  clen(i) = clen(i) + ov
               end if
            end do
         end do cells

         ! Each pixel's mean value (its place in the window) and
         ! coverage: the colored part of its width inside the plot area.
         do i=ilo,ihi,1
            lo = max( real( i - 1, dp ), f%xa )
            hi = min( real( i, dp ), f%xb )
            if ( clen(i) > zero .and. hi > lo ) then
               f4( i, s ) = window( acc(i)/clen(i) )
               c4( i, s ) = min( clen(i)/( hi - lo ), one )
            end if
         end do
      end do subrows

      ! The sub-rows' colors, and each pixel their average: each
      ! sub-row its color where covered, white where not. (k = 1, 2, 3
      ! is blue, green, red.)
      if ( nsub > 0 ) then
         call apply_colormap( nx, ns, f4, rgb4, cmap )
         dat = zero
         do s=1,ns,1
            ys = real( j - 1, dp ) + ( real( s, dp ) - half )*hs
            if ( ys < f%ya .or. ys > f%yb ) cycle
            do k=1,3,1
               dat( :, k ) = dat( :, k ) + c4( :, s )*real( ichar( &
                  rgb4( :, s, k ) ), dp ) + ( one - c4( :, s ) )*255.0_dp
            end do
         end do
         dat = dat/real( nsub, dp )
      end if
   end if

   ! Each pixel: the plot area's color, the bar's, or white, with the
   ! slate (frame, title, bar outline, labels) on top by its coverage.
   do i=1,nx,1
      x = real( i, dp ) - half
      y = real( j, dp ) - half
      do k=1,3,1
         col(k) = dat( i, 4-k )
      end do
      nfk = 0
      nbk = 0
      if ( frame_near( f, x, y ) .or. near_bar( x, y ) .or. &
           any( txt( (i-1)*ns+1:i*ns, (j-1)*ns+1:j*ns ) /= 0_int8 ) ) then
         do jj=1,ns,1
            do ii=1,ns,1
               x = real( i - 1, dp ) + ( real( ii, dp ) - half )*hs
               y = real( j - 1, dp ) + ( real( jj, dp ) - half )*hs
               if ( frame_ink( f, x, y ) .or. &
                    txt( (i-1)*ns+ii, (j-1)*ns+jj ) == 2_int8 ) then
                  nfk = nfk + 1
               else if ( in_rounded( x, y, bxa, bxb, bya, byb, &
                         max( cbrad - cbw, zero ) ) ) then
                  nbk = nbk + 1
               else if ( in_rounded( x, y, cbl, cbr, cbt, cbb, cbrad ) ) then
                  nfk = nfk + 1
               end if
            end do
         end do
      end if
      cf = real( nfk, dp )/real( ns*ns, dp )
      cb = real( nbk, dp )/real( ns*ns, dp )
      if ( nbk > 0 ) then
         ! The bar (no plot area here): what is under the slate is its
         ! fill and paper, cb*fill + (1 - cf - cb)*white, per 1 - cf.
         ! (nbk > 0, so cf < 1.)
         do k=1,3,1
            col(k) = ( cb*real( ichar( rgbb( i, 1, 4-k ) ), dp ) + &
               ( one - cb - cf )*255.0_dp )/( one - cf )
         end do
      end if
      do k=1,3,1
         ! k = 1, 2, 3 is blue, green, red: the colors' 3, 2, 1.
         RGB( i, j, k ) = char( nint( cf*slate_rgb(4-k) + &
            ( one - cf )*col(4-k) ) )
      end do
   end do
end do rows

!*** The file (bmpmaker with no colormap writes RGB as it is).
none = 'rgb'
call bmpmaker( nx, ny, fcn, RGB, bout, none )

deallocate( fcn, RGB, f4, c4, rgb4, dat, fb, rgbb, xf, acc, clen, &
   reached, txt )

return

contains

   !*** A value's place in the color window, from 0 to 1.
   real(kind=dp) function window( y )
   real(kind=dp), intent(in) :: y
   if ( span > zero ) then
      window = min( max( ( y - clo )/span, zero ), one )
   else
      window = half
   end if
   end function window

   !*** The value drawn at x inside the current cell [a, b]: its P, or
   !*** u from the left face's ua to the right face's ub, linearly.
   real(kind=dp) function value( x )
   real(kind=dp), intent(in) :: x
   if ( isu ) then
      value = ua + ( ub - ua )*( x - a )/( b - a )
   else
      value = p
   end if
   end function value

   !*** Could a pixel centered at (x, y) touch the color bar?
   logical function near_bar( x, y )
   real(kind=dp), intent(in) :: x, y
   near_bar = ( x > cbl - one .and. x < cbr + one .and. &
                y > cbt - one .and. y < cbb + one )
   end function near_bar

end subroutine draw_tx

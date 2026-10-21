subroutine draw_tx( var, bout, cmap, clo, chi )
!**********************************************************************!
!  About:                                                              !
!    DRAW_TX makes one t-x diagram (u or P) as a fixed-size bitmap,    !
!    nx by ny pixels, and hands it to bmpmaker. Called by module pics  !
!    (maincode section 9), after a run and in a plots_only run, once   !
!    the history file has been read (module hist, the hr_ arrays).     !
!                                                                      !
!    The image is the plot area and nothing else, in the LAB frame:    !
!    x across, from the smallest face position of the whole run       !
!    (left edge) to the largest (right edge); t up, from 0 (bottom     !
!    edge) to the last frame (top edge). Every cell is drawn between   !
!    its two faces where they are at that time, so a material line     !
!    (a face) is a curve of slope dx/dt = u, and a shock front's slope !
!    is the shock velocity. No text, no border: the screen gives the   !
!    ranges.                                                           !
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
!    Pixels. Pixel column i covers x from xmin + (i-1)*dx to           !
!    xmin + i*dx; pixel row r (from the bottom) is the time            !
!    t = (r - 1/2)*dt. bmpmaker writes row j = ny first, which is the  !
!    BOTTOM of the image, so image row j is r = ny - j + 1. Two ways   !
!    to fill a row (ischeme, below):                                   !
!      1  point samples: the latest frame at or before t, and in each  !
!         pixel the cell under its center.                             !
!      2  (the default) faces interpolated in time between the two     !
!         frames around t, so material moves smoothly between frames;  !
!         each cell's state from the nearer of the two; and each pixel !
!         the length-weighted mean of the cells over it, white if more !
!         than half of it is white. Cells smaller than a pixel (a      !
!         compressed metal) are averaged instead of skipped.           !
!                                                                      !
!    Velocity: the deck's colormap over its window, and WHITE only     !
!    where there is no material and in open spall (as above). The u of !
!    the history file is at the FACES (AV's u, RS's u*), so within a   !
!    cell u runs linearly from its left face to its right face; a      !
!    pixel takes the mean of that line over the part of the cell it    !
!    covers, which is its value at that part's midpoint. Untouched     !
!    material is colored: a moving flyer has a velocity, and material  !
!    at rest has u = 0.                                                !
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
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6,zero,half,one
use hist, only: hr_nframes,hr_kmax,hr_time,hr_x,hr_u,hr_p,hr_d
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
integer(kind=int32), parameter :: ny=900      ! pixels up (t)
integer(kind=int32), parameter :: ischeme=2   ! 1 = point samples
                                              ! 2 = interpolated, averaged
integer(kind=int32) :: i,j,k,r                ! loop indices
integer(kind=int32) :: i1,i2                  ! pixels a cell covers
integer(kind=int32) :: jf,jn                  ! frame at/before t, nearer
integer(kind=int32) :: jt                     ! frames seen by 'reached'
integer(kind=int32) :: nf,kmax                ! frames, cells
integer(kind=int32) :: istat                  ! allocation status
real(kind=dp) :: xmin,xmax,dx                 ! mm: image edges, a pixel
real(kind=dp) :: tend,dt,t,w                  ! us: top edge, a row, row t
real(kind=dp) :: a,b,lo,hi,ov                 ! mm: a cell, a pixel, overlap
real(kind=dp) :: p,span                       ! a cell's P (GPa), the window
real(kind=dp) :: ua,ub                        ! km/s: u at a cell's faces
real(kind=dp) :: v                            ! the value drawn (P or u)
logical :: isu                                ! drawing u (not P)
real(kind=dp) :: pzero                        ! GPa: |P| below this is 0
real(kind=dp), parameter :: zero_frac=1.0e-6_dp  ! pzero / largest |P|
real(kind=dp), dimension(:,:), allocatable :: fcn       ! values [0,1]
character(len=1), dimension(:,:,:), allocatable :: RGB  ! the colors
logical, dimension(:,:), allocatable :: white           ! white pixels
logical, dimension(:), allocatable :: reached           ! a wave has
                                              ! reached the cell (so far)
logical :: blank                              ! this cell is white now
real(kind=dp), dimension(:), allocatable :: xf          ! faces at t
real(kind=dp), dimension(:), allocatable :: acc,clen    ! per pixel: sum
                                              ! of v*length, colored length
character(len=80) :: none                     ! 'rgb': no colormap

!*** Allocate the image arrays (too large for the stack).
nf   = hr_nframes
kmax = hr_kmax
allocate( fcn(nx,ny), RGB(nx,ny,3), white(nx,ny), xf(kmax+1), &
   acc(nx), clen(nx), reached(kmax), stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_tx could not allocate the image.'
   return
end if

isu = ( var == 'u' )

!*** The image's edges: x over the whole run, t from 0 to the last frame.
xmin = real( minval( hr_x(:,1:nf) ), dp )
xmax = real( maxval( hr_x(:,1:nf) ), dp )
dx   = ( xmax - xmin ) / real( nx, dp )
tend = hr_time(nf)
dt   = tend / real( ny, dp )
span = chi - clo
pzero = zero_frac*real( maxval( abs( hr_p(:,1:nf) ) ), dp )

!*** Row by row, from the bottom (t = 0) up.
fcn     = zero
white   = .true.
reached = .false.
jf      = 1
jt      = 0
rows: do r=1,ny,1
   j = ny - r + 1
   t = ( real( r, dp ) - half ) * dt

   ! The frames around t: jf at or before it, jf+1 after it.
   do while ( jf < nf - 1 )
      if ( hr_time(jf+1) > t ) exit
      jf = jf + 1
   end do

   ! The faces at t, and the frame each cell's state comes from (jn).
   if ( nf == 1 .or. ischeme == 1 ) then
      xf = real( hr_x(:,jf), dp )
      jn = jf
   else
      w  = ( t - hr_time(jf) ) / ( hr_time(jf+1) - hr_time(jf) )
      w  = min( max( w, zero ), one )
      xf = ( one - w )*real( hr_x(:,jf), dp ) + w*real( hr_x(:,jf+1), dp )
      jn = jf
      if ( w >= half ) jn = jf + 1
   end if

   ! Which cells a wave has reached, up to frame jn.
   do while ( jt < jn )
      jt = jt + 1
      reached = reached .or. ( abs( real( hr_p(:,jt), dp ) ) > pzero )
   end do

   ! Each cell onto the pixels it covers.
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
      if ( ischeme == 1 ) then
         ! The pixels whose centers are in [a, b), each the value at
         ! its center.
         i1 = max( 1,  ceiling( ( a - xmin )/dx + half ) )
         i2 = min( nx, ceiling( ( b - xmin )/dx + half ) - 1 )
         do i=i1,i2,1
            if ( .not. blank ) then
               fcn( i, j )   = window( value( xmin + ( real( i, dp ) &
                  - half )*dx ) )
               white( i, j ) = .false.
            end if
         end do
      else
         ! Every pixel the cell overlaps, by the length it covers.
         ! A white cell adds nothing: what is not colored is white.
         if ( blank ) cycle cells
         i1 = max( 1,  floor( ( a - xmin )/dx ) + 1 )
         i2 = min( nx, floor( ( b - xmin )/dx ) + 1 )
         do i=i1,i2,1
            lo = xmin + real( i - 1, dp )*dx
            hi = lo + dx
            ov = min( b, hi ) - max( a, lo )
            if ( ov > zero ) then
               ! The mean over the overlap: the value at its midpoint
               ! (P is the same across a cell, u linear in x).
               v = value( half*( max( a, lo ) + min( b, hi ) ) )
               acc(i)  = acc(i)  + ov*v
               clen(i) = clen(i) + ov
            end if
         end do
      end if
   end do cells

   ! Scheme 2: a pixel more than half colored takes the mean value of
   ! its colored part; otherwise it stays white.
   if ( ischeme /= 1 ) then
      do i=1,nx,1
         if ( clen(i) > half*dx ) then
            fcn( i, j )   = window( acc(i)/clen(i) )
            white( i, j ) = .false.
         end if
      end do
   end if
end do rows

!*** Colors from the deck's colormap, then white on top, then the file
!*** (bmpmaker with no colormap writes RGB as it is).
call apply_colormap( nx, ny, fcn, RGB, cmap )
do k=1,3,1
   where ( white ) RGB( :, :, k ) = char(255)
end do
none = 'rgb'
call bmpmaker( nx, ny, fcn, RGB, bout, none )

deallocate( fcn, RGB, white, xf, acc, clen, reached )

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

end subroutine draw_tx

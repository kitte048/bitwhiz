subroutine draw_colormaps()
!**********************************************************************!
!  About:                                                              !
!    Single routine to draw all pre-programmed color maps.             !
!                                                                      !
!    Each map is drawn on a square image. The scalar runs 0 -> 1 from  !
!    the lower-left corner to the upper-right corner. With ipat=2 the  !
!    line y=x splits the image: the upper-left triangle shows the      !
!    straight ramp, and in the lower-right triangle a small sine       !
!    ripple rides on the same ramp, growing toward the lower-right     !
!    corner.                                                           !
!    Equal ripples should look equally visible all along the diagonal; !
!    where they fade, the color map is perceptually flat. After        !
!    P. Kovesi, "Good Colour Maps: How to Design Them",                !
!    arXiv:1509.03700 (2015).                                          !
!                                                                      !
!    With anoise > 0, a per-pixel grain of +/- anoise is added (only   !
!    in the lower-right triangle when ipat=2), drawn from the          !
!    atmospheric-noise list via r8_uniform_01 (utils).                 !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    11/25/23    D. E. Kittell      Original code                      !
!    10/06/26    Claude (for DEK)   F2018 clean: character(len=),      !
!                                   allocatable fcn/RGB, drop int64    !
!    10/06/26    Claude (for DEK)   Square image, diagonal ramp, and   !
!                                   Kovesi-style sine-ramp test (ipat) !
!    10/06/26    Claude (for DEK)   Atmospheric-noise grain (anoise)   !
!    10/08/26    Claude (for DEK)   ipat=2: plain ramp above y=x,      !
!                                   ripple + grain below it            !
!    10/23/26    Claude (for DEK)   Fixed seed by random_seed, not     !
!                                   random_init (gfortran 9+ only)     !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6,zero,half,one,two,pi
implicit none

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32) :: i,j,k
integer(kind=int32) :: istat            ! allocation status
integer :: nseed                         ! the generator's seed size
integer, allocatable :: seed(:)          ! ... and the seed
integer(kind=int32), parameter :: n=512       ! square image, n x n pixels
integer(kind=int32), parameter :: nx=n
integer(kind=int32), parameter :: ny=n
integer(kind=int32), parameter :: ipat=2      ! 1 = diagonal ramp
                                              ! 2 = ramp + sine ripple test
real(kind=dp), parameter :: amax=0.05_dp      ! max ripple amplitude
real(kind=dp), parameter :: ncyc=60.0_dp      ! ripple cycles along diagonal
real(kind=dp), parameter :: anoise=0.02_dp    ! grain amplitude (0 = off)
real(kind=dp) :: r                            ! atmospheric noise in [0,1)
real(kind=dp) :: x,y,t,u,amp                  ! image coordinates
logical :: textured                           ! ripple/grain at this pixel?
real(kind=dp), dimension(:,:), allocatable :: fcn       ! real vals [0,1]
character(len=1), dimension(:,:,:), allocatable :: RGB  ! RGB (optional)
character(len=80) :: bout
character(len=80) :: cmap
character(len=5), dimension(6), parameter :: idx = &
(/ '1,2,3' , '1,3,2' , '2,1,3' , '2,3,1' , '3,1,2' , '3,2,1' /)

!*** Allocate the image arrays (too large for the stack).
allocate( fcn(nx,ny), RGB(nx,ny,3), stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_colormaps could not allocate the image.'
   return
end if

!*** Same grain every run: a fixed seed (Fortran 95's random_seed;
!*** Fortran 2018's random_init needs gfortran 9 or later). For fresh
!*** grain every run, leave out the "put".
call random_seed( size=nseed )
allocate( seed(nseed) )
seed = 20231125 + 7919*(/ ( i, i = 1, nseed ) /)
call random_seed( put=seed )
deallocate( seed )

!*** Make the image and write to file.
!    bmpmaker writes row j=ny first, which is the BOTTOM of the image,
!    so x runs left -> right and y runs bottom -> top, both on [0,1].
!    t is the diagonal coordinate (0 lower-left, 1 upper-right) and
!    u the cross-diagonal one (0 upper-left, 1 lower-right).
!    With ipat=2 the line y=x splits the image: the upper-left triangle
!    (y > x) gets the straight ramp only, the lower-right triangle
!    (y <= x) gets the ripple and grain. Both use the same base ramp,
!    so the color is continuous across the diagonal.
do i=1,nx,1
   do j=1,ny,1
      x = ( i - one ) / ( nx - one )
      y = ( ny - j ) / ( ny - one )
      t = half * ( x + y )
      u = half * ( x - y + one )
      textured = ( ipat == 1 ) .or. ( y <= x )
      pattern_if: if (ipat == 1) then
         fcn( i, j ) = t
      else if (.not. textured) then
         ! Upper-left triangle: the straight ramp alone.
         fcn( i, j ) = amax + ( one - two * amax ) * t
      else
         ! Ramp scaled into [amax, 1-amax] so the ripple stays in [0,1].
         amp = amax * u**2
         fcn( i, j ) = amax + ( one - two * amax ) * t &
                     + amp * sin( two * real(pi, kind=dp) * ncyc * t )
      end if pattern_if
      if (textured .and. anoise > zero) then
         call r8_uniform_01( r )
         fcn( i, j ) = fcn( i, j ) + anoise * ( two * r - one )
      end if
      fcn( i, j ) = min( max( fcn( i, j ), zero ), one )
   end do
end do

!*** Grayscale Color Bar.

write(kpt6,*) " - - - - - -"
bout = 'Grayscale'
cmap = 'grayscale'
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
write(kpt6,*) " - - - - - -"

!*** All other color bars may be permuted.
do k=1,6,1
   bout = 'Smoothcoolwarm' // idx(k)
   cmap = 'smoothcoolwarm' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Bentcoolwarm' // idx(k)
   cmap = 'bentcoolwarm' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Viridis' // idx(k)
   cmap = 'viridis' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Plasma' // idx(k)
   cmap = 'plasma' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Blackbody' // idx(k)
   cmap = 'blackbody' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Inferno' // idx(k)
   cmap = 'inferno' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Kindlmann' // idx(k)
   cmap = 'kindlmann' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
   bout = 'Extendedkindlmann' // idx(k)
   cmap = 'extendedkindlmann' // idx(k)
   call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
   write(kpt6,*) " - - - - - -"
end do

deallocate( fcn, RGB )

return
end subroutine

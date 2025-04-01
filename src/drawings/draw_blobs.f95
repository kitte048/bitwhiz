subroutine draw_blobs(cmap)
!**********************************************************************!
!  About:                                                              !
!    Single routine to draw the current color maps.                    !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    03/27/25    D. E. Kittell      Original code                      !
!                                                                      !
!**********************************************************************!
use bits, only: int32,int64,dp,kpt6,pi,zero,half,one,two,thr,for,fiv, &
                six,sev,eig,nin,ten
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
character(len=80), intent(inout) :: cmap           ! string params

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32) :: i,j,k
integer(kind=int32), parameter :: kmax=500
integer(kind=int32), parameter :: nx=2400
integer(kind=int32), parameter :: ny=2400
real(kind=dp), dimension(nx,ny) :: fcn     ! real vals [0,1]
real(kind=dp), dimension(kmax) :: xc,yc, &
                 sigma_x,sigma_y           ! Gaussian PDF parameters
character*1, dimension(nx,ny,3) :: RGB     ! RGB (optional)
character*80 :: bout
real(kind=dp) :: sgn,fval,fnoise,arg, &
                 gmin,gmax,clip_l,clip_u

! Populate KMAX Gaussian PDFs.
do i=1,kmax,1

   ! Locate the center of the PDF.
   call r8_uniform_01( fnoise )
   xc(i) = one * nx *  fnoise

   call r8_uniform_01( fnoise )
   yc(i) = one * ny *  fnoise

   ! Adjust the spread.
   call r8_uniform_01( fnoise )
   sigma_x(i) = nx / (two*ten + two*ten * fnoise)

   call r8_uniform_01( fnoise )
   sigma_y(i) = ny / (two*ten + two*ten * fnoise)
end do

! Loop over pixels.
do i=1,nx,1
   do j=1,ny,1

      ! Initialize.
      fcn( i, j ) = zero
      sgn = one

      ! Loop over PDFs.
      do k=1,kmax,1

         ! Exponential term.
         arg = half*((one*i-xc(k))/sigma_x(k))**2 + &
               half*((one*j-yc(k))/sigma_y(k))**2

         fcn(i,j) = fcn(i,j) + sgn*exp(-arg)
         sgn = -one*sgn

      end do

      ! Global extrema.
      if (fcn(i,j)<gmin) gmin=fcn(i,j)
      if (fcn(i,j)>gmax) gmax=fcn(i,j)

   end do
end do

! Loop a second time to scale the color values.
clip_l = 0.65_dp 
clip_u = 0.65_dp

do i=1,nx,1
   do j=1,ny,1
      fval = (fcn(i,j)-gmin*clip_l) / &
             (gmax*clip_u-gmin*clip_l)
      call r8_uniform_01( fnoise )
      fnoise = fnoise / (fiv)
      fcn(i,j) = min( max( fval + fnoise, zero ), one )
   end do
end do


!*** Make the file name to be the same as draw_colormaps.
bout = 'DEFAULT'
name_check: if (cmap(1:4).eq."bent") then
   bout(1:17) = cmap(1:17)
   bout(1:1) = 'B'
else if (cmap(1:4).eq."blac") then
   bout(1:14) = cmap(1:14)
   bout(1:1) = 'B'
else if (cmap(1:4).eq."exte") then
   bout(1:22) = cmap(1:22)
   bout(1:1) = 'E'
else if (cmap(1:4).eq."gray") then
   bout(1:9) = cmap(1:9)
   bout(1:1) = 'G'
else if (cmap(1:4).eq."infe") then
   bout(1:12) = cmap(1:12)
   bout(1:1) = 'I'
else if (cmap(1:4).eq."kind") then
   bout(1:14) = cmap(1:14)
   bout(1:1) = 'K'
else if (cmap(1:4).eq."plas") then
   bout(1:11) = cmap(1:11)
   bout(1:1) = 'P'
else if (cmap(1:4).eq."smoo") then
   bout(1:19) = cmap(1:19)
   bout(1:1) = 'S'
else if (cmap(1:4).eq."viri") then
   bout(1:12) = cmap(1:12)
   bout(1:1) = 'V'
else
   cmap(1:9) = 'grayscale'
end if name_check
bout = 'Blobs_'//bout


write(kpt6,*) " - - - - - -"
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
write(kpt6,*) " - - - - - -"

return
end subroutine

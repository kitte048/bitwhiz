subroutine draw_cylflow(cmap)
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
                six,sev,eig,nin,ten,pi
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
character(len=80), intent(inout) :: cmap           ! string params

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32) :: i,j,k
integer(kind=int32), parameter :: nx=2400
integer(kind=int32), parameter :: ny=2400
integer(kind=int32), parameter :: nstream=64 ! number of streamlines
real(kind=dp), dimension(nx,ny) :: fcn     ! real vals [0,1]
real(kind=dp), dimension(nx,ny) :: psi     ! stream function
real(kind=dp), dimension(nx,ny) :: umag    ! velocity magnitude
real(kind=dp), dimension(nstream) :: &
                psilo, psihi          ! for calculating streamlines
character*1, dimension(nx,ny,3) :: RGB     ! RGB (optional)
character*80 :: bout
real(kind=dp) :: ur,utheta,u,gam,a,r,x,y, &
                 theta,gmin,gmax,val,err, &
                 fnoise,fval,hmin,hmax,dpsi

gam = one+half
a = half*half
u = one

gmin = 1.0e10_dp
gmax = -1.0e10_dp

hmin = 1.0e10_dp
hmax = -1.0e10_dp

! Loop over pixels (First Time).
do i=1,nx,1
   do j=1,ny,1

      ! Initialize.
      fcn(i,j) = zero
      psi(i,j) = zero
      umag(i,j) = zero

      ! Get (x,y) from pixels.
      x = two*(one*i-one)/(one*nx-one)-one
      y = two*(one-one*j)/(one*ny-one)+one

      ! Calculate the angle.
      theta = atan2( y, x )

      ! Calculate the magnitude.
      r = sqrt(x**2+y**2)

      ! Do not evaluate near the branch cut in the complex plane.
      outside_if: if ( (r.ge.a) .and. (abs(y).gt.zero) ) then

         ! Calculate the stream function.
         psi(i,j) = u*y*(one-a**2/(x**2+y**2)) + &
                    (gam/(two*pi))*log(r/a)
      
         ! Calculate the velocity magnitude.
         ur = u*(one-a**2/(x**2+y**2))*cos(theta)
         utheta = -u*(one+a**2/(x**2+y**2))*sin(theta) &
                  -(gam/(two*pi*sqrt(x**2+y**2)))
         umag(i,j) = sqrt(ur**2+utheta**2)

         fcn(i,j) = sqrt(ur**2+utheta**2)

         ! Global extrema.
         if (fcn(i,j)<gmin) gmin=fcn(i,j)
         if (fcn(i,j)>gmax) gmax=fcn(i,j)

      end if outside_if

      ! Do not evaluate near the branch cut in the complex plane.
      inside_if: if ( (r.lt.a) .and. (abs(y).gt.zero) ) then

         ! Calculate the stream function.
         psi(i,j) = u*y*(one-a**2/(x**2+y**2)) + &
                    (gam/(two*pi))*log(r/a)
      
         ! Calculate the velocity magnitude.
         ur = u*(one-a**2/(x**2+y**2))*cos(theta)
         utheta = -u*(one+a**2/(x**2+y**2))*sin(theta) &
                  -(gam/(two*pi*sqrt(x**2+y**2)))
         umag(i,j) = sqrt(ur**2+utheta**2)

         fcn(i,j) = half*log(sqrt(ur**2+utheta**2))

         ! Global extrema.
         if (fcn(i,j)<hmin) hmin=fcn(i,j)
         if (fcn(i,j)>hmax) hmax=fcn(i,j)

      end if inside_if

   end do
end do

write(*,*) gmin,gmax
write(*,*) hmin,hmax

!*********************!
!                     !
! STREAMLINE ANALYSIS !
!                     !
!*********************!

do k=1,nstream,1
   j = nint(one*ny*(one*k)/(one*nstream+1))
   psilo(k) = min(psi(1,j-3),psi(1,j+3))
   psihi(k) = max(psi(1,j-3),psi(1,j+3))
end do

dpsi = -( half*(psilo(nstream)+psihi(nstream)) - &
         half*(psilo(1)+psihi(1)) ) / (one*nstream-one)

! Loop over pixels (Second Time).
!gmin = 1.25_dp * gmin
!gmax = 0.75_dp * gmax

gmin = 0.25_dp
gmax = 2.15_dp

do i=1,nx,1
   do j=1,ny,1

      ! Get (x,y) from pixels.
      x = two*(one*i-one)/(one*nx-one)-one
      y = two*(one-one*j)/(one*ny-one)+one

      ! Calculate the angle.
      theta = atan2( y, x )

      ! Calculate the magnitude.
      r = sqrt(x**2+y**2)

      ! Scale the flow field, inside/outside.
      if ( (r.ge.a) .and. (abs(y).gt.zero) ) then
         fval = (fcn(i,j)-gmin) / (gmax-gmin)
      else if ( (r.lt.a) .and. (abs(y).gt.zero) ) then
         fval = (fcn(i,j)-hmin) / (hmax-hmin)
      else
         fval = zero
      end if

      call r8_uniform_01( fnoise )
      fnoise = fnoise / (ten)
      fcn(i,j) = min( max( fval + fnoise, zero ), one )

      ! Check if pixel is on a streamline.
      do k=1,nstream,1
         if (psi(i,j).ge.psilo(k).and.psi(i,j).le.psihi(k)) then
            fcn(i,j) = one-fcn(i,j)
            if ( (r.lt.a) .and. (abs(y).gt.zero) ) then
               fcn(i,j) = zero
            end if
         end if
      end do

      ! Add streamlines inside of the cylinder.
      if ( (r.lt.a) .and. (abs(y).gt.zero) ) then
         do k=1,25,1
            if ( psi(i,j).ge.psilo(k)-one*k*dpsi .and. &
                 psi(i,j).le.psihi(k)-one*k*dpsi ) then
               fcn(i,j) = zero
            else if ( psi(i,j).ge.psilo(k)+one*k*dpsi .and. &
                 psi(i,j).le.psihi(k)+one*k*dpsi ) then
               fcn(i,j) = zero
            end if
         end do
      end if

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
bout = 'CylFlow_'//bout


write(kpt6,*) " - - - - - -"
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )
write(kpt6,*) " - - - - - -"

return
end subroutine

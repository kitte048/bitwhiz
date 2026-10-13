subroutine cmap_grayscale(nx,ny,fcn,RGB)
!**********************************************************************!
!  About:                                                              !
!    CMAP_GRAYSCALE is one of the color map options for bmpmaker.      !
!                                                                      !
!  Purpose:                                                            !
!    To convert a real-valued function into a grayscale RGB triplet.   !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    11/19/23    D. E. Kittell      Started over from bitart project.  !
!    10/06/26    Claude (for DEK)   F2018 clean: character(len=), int32 !
!                                   locals, explicit int() truncation  !
!    10/06/26    Claude (for DEK)   Round to nearest, nint() (was int  !
!                                   truncation) for the 0-255 channels !
!    10/13/26    Claude (for DEK)   Loop indices are local variables   !
!                                   (were shared in module bits)       !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,zero,one
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
integer(kind=int32), intent(in) :: nx,ny               ! pixel size
real(kind=dp), dimension(nx,ny), intent(in) :: fcn     ! real vals [0,1]
character(len=1), dimension(nx,ny,3), intent(out) :: RGB    ! RGB values

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.
!**********************************************************************!
integer(kind=int32) :: i,j           ! pixel loop indices
integer(kind=int32) :: ch1           ! 0-255 channel value
real(kind=dp) :: val                 ! original values check if [0,1]

do i=1,nx,1
   do j=1,ny,1

      val = min(max(fcn(i,j),zero),one)
      ch1 = min(max(nint(one*val*255.0_dp),0),255)

      RGB(i,j,1) = achar(ch1)
      RGB(i,j,2) = achar(ch1)
      RGB(i,j,3) = achar(ch1)
   end do
end do

return
end subroutine cmap_grayscale

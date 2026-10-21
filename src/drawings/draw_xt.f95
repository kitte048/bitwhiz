subroutine draw_xt( var, bout, cmap )
!**********************************************************************!
!  About:                                                              !
!    DRAW_XT makes one t-x diagram (u or P) as a fixed-size bitmap,    !
!    nx by ny pixels, and hands it to bmpmaker. Called by module pics  !
!    (maincode section 9), after a run and in a plots_only run.        !
!                                                                      !
!    The image is the plot area and nothing else: x across (pixel      !
!    column i = 1 at the smallest x of the run), t up (bmpmaker writes !
!    row j = ny first, which is the BOTTOM of the image, so row ny is  !
!    t = 0), colored edge to edge, no text, no border.                 !
!                                                                      !
!    THIS VERSION DRAWS A FIDUCIAL, to check the plumbing (file names, !
!    sizes, the colormap, plots_only): a ramp from 0 to 1 through the  !
!    deck's colormap, left to right for u and bottom to top for P, so  !
!    the two files differ and the bottom-left corner is the color for  !
!    0. The data (module hist) and the white rules come next.          !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer          Description of change            !
!      ====       ==========          =====================            !
!    10/20/26    D. E. Kittell        Original code: the fiducial      !
!                (with Claude)                                         !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
character(len=*), intent(in) :: var        ! 'u' or 'P'
character(len=80), intent(in) :: bout      ! file name, without ".bmp"
character(len=80), intent(in) :: cmap      ! the deck's colormap

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
integer(kind=int32), parameter :: nx=1200     ! pixels across (x)
integer(kind=int32), parameter :: ny=900      ! pixels up (t)
integer(kind=int32) :: i,j                    ! loop indices
integer(kind=int32) :: istat                  ! allocation status
real(kind=dp), dimension(:,:), allocatable :: fcn       ! values [0,1]
character(len=1), dimension(:,:,:), allocatable :: RGB  ! the colors

!*** Allocate the image arrays (too large for the stack).
allocate( fcn(nx,ny), RGB(nx,ny,3), stat=istat )
if (istat /= 0) then
   write(kpt6,*) 'ERROR draw_xt could not allocate the image.'
   return
end if

!*** The fiducial: a ramp from 0 to 1, across for u, up for P.
!    Row j = ny is the bottom of the image (see About).
do j=1,ny,1
   do i=1,nx,1
      if (var == 'u') then
         fcn( i, j ) = real( i - 1, dp ) / real( nx - 1, dp )
      else
         fcn( i, j ) = real( ny - j, dp ) / real( ny - 1, dp )
      end if
   end do
end do

!*** Colors from the deck's colormap, then the file.
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )

deallocate( fcn, RGB )

return
end subroutine draw_xt

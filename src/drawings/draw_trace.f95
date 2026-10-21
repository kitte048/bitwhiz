subroutine draw_trace( bout )
!**********************************************************************!
!  About:                                                              !
!    DRAW_TRACE makes one tracer plot (velocity against time) as a     !
!    fixed-size bitmap, nx by ny pixels, and hands it to bmpmaker.     !
!    Called by module pics (maincode section 9), once per tracer,      !
!    after a run and in a plots_only run.                              !
!                                                                      !
!    The picture: a white page, a margin of nm pixels, and inside it   !
!    the plot area, framed by a 1-pixel black border with tick marks   !
!    at tenths of each axis (nt pixels long, pointing in). Time runs   !
!    across, from the first to the last row of the tracer file;        !
!    velocity up. No text: the screen gives the ranges. The colors are !
!    set here, pixel by pixel, so no colormap is used (bmpmaker writes !
!    RGB as given when cmap names none of its colormaps).              !
!                                                                      !
!    THIS VERSION DRAWS THE FRAME ONLY (border and ticks), to check    !
!    the plumbing: one file per tracer, by name, in a plots_only run   !
!    too. The curve comes next.                                        !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer          Description of change            !
!      ====       ==========          =====================            !
!    10/20/26    D. E. Kittell        Original code: the frame         !
!                (with Claude)                                         !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp,kpt6
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
integer(kind=int32), parameter :: nt=8        ! tick length, pixels
integer(kind=int32) :: i,j,k                  ! loop indices
integer(kind=int32) :: i0,i1,j0,j1            ! the border's columns, rows
integer(kind=int32) :: istat                  ! allocation status
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
fcn = 0.0_dp
cmap = 'rgb'

!*** The page: white.
RGB = char(255)

!*** The border: columns i0 and i1, rows j0 (top) and j1 (bottom).
!    Row j = ny is the bottom of the image (bmpmaker writes it first).
i0 = 1 + nm
i1 = nx - nm
j0 = 1 + nm
j1 = ny - nm
RGB( i0:i1, j0, : ) = char(0)
RGB( i0:i1, j1, : ) = char(0)
RGB( i0, j0:j1, : ) = char(0)
RGB( i1, j0:j1, : ) = char(0)

!*** Tick marks at tenths, pointing into the plot area: up from the
!    bottom edge and down from the top (time), right from the left
!    edge and left from the right (velocity).
do k=1,9,1
   i = i0 + nint( real( k*( i1 - i0 ), dp ) / 10.0_dp )
   j = j1 - nint( real( k*( j1 - j0 ), dp ) / 10.0_dp )
   RGB( i, j1-nt:j1, : ) = char(0)
   RGB( i, j0:j0+nt, : ) = char(0)
   RGB( i0:i0+nt, j, : ) = char(0)
   RGB( i1-nt:i1, j, : ) = char(0)
end do

!*** The file.
call bmpmaker( nx, ny, fcn, RGB, bout, cmap )

deallocate( fcn, RGB )

return
end subroutine draw_trace

module hist
!**********************************************************************!
!
!  Purpose:
!    The history file, <title>.hist: the whole mesh over time, one
!    frame per snapshot (deck: plot_every, plot_dt), for pictures.
!    The format is input/README.md, section 9; this module writes it
!    and nothing else. In short:
!
!       header   64 fixed bytes, then the variable table (32 bytes
!                each), the layer table (72 bytes each) and a text
!                block (2048 bytes), header_bytes in all
!       frames   time (real64), cycle, frame (int32), then x and u at
!                the k_max + 1 faces and P at the k_max cells (real32)
!
!    Little-endian stream access (plain bytes, no record markers),
!    flushed after every frame, so a crashed run still leaves whole
!    frames. nframes and status are filled in when the run ends
!    (close_history, from maincode's close_outputs).
!
!    Called from maincode only, outside the parallel region, so the
!    file is the same on any number of threads.
!
!  Units, as everywhere in bitwhiz: mm, us, km/s, GPa.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/20/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits,  only: sp, dp, int32, zero
use shock, only: jx, ju, jp, ju_star, database, iface, icell, layer, &
   nlay, method, rs_order, plot_every, plot_dt
implicit none
private

public :: open_history, history_frame, close_history, hst_open, &
   hst_file, hst_frames

!**********************************************************************!
!  The variables in each frame, in file order (the header's variable
!  table). Names and units are the tracer file's. To add one: an entry
!  here (its slot for AV, its slot for RS, name, unit, 0 = faces or
!  1 = cells), at the END, and bump nhv; the reader finds variables by
!  name, so old files and scripts keep working.
!**********************************************************************!
integer(kind=int32), parameter :: nhv = 3
integer(kind=int32), parameter, dimension(nhv) :: hv_av = (/ jx, ju,      jp /)
integer(kind=int32), parameter, dimension(nhv) :: hv_rs = (/ jx, ju_star, jp /)
character(len=8),  parameter, dimension(nhv) :: hv_name = (/ &
   'XPOS    ', 'KMPS    ', 'GPA     ' /)
character(len=16), parameter, dimension(nhv) :: hv_unit = (/ &
   'mm              ', 'km/s            ', 'GPa             ' /)
integer(kind=int32), parameter, dimension(nhv) :: hv_where = (/ 0, 0, 1 /)

!*** Format constants (input/README.md, section 9).
character(len=8),    parameter :: magic      = 'BWHIST  '
integer(kind=int32), parameter :: version    = 1
integer(kind=int32), parameter :: text_bytes = 2048

!*** The file. "Is it open?" is hst_open, never a test on the unit.
integer(kind=int32) :: khs        = 0          ! unit number
logical             :: hst_open   = .false.    ! the file is open
character(len=72)   :: hst_file   = ' '        ! <title>.hist
integer(kind=int32) :: hst_frames = 0          ! frames written so far
integer(kind=int32) :: kh         = 0          ! cells in the file
real(kind=dp)       :: tnext      = zero       ! us, next plot_dt time
integer(kind=int32) :: slot(nhv)               ! this run's slots

!*** One frame's values, single precision. Sized when the file opens.
real(kind=sp), allocatable :: buf(:)

contains

   !******************************************************************!
   ! Open <title>.hist and write its header. With no snapshot keys    !
   ! (plot_every = 0 and plot_dt = 0) there is nothing to write: no   !
   ! file, and ios = 0. ios /= 0 means the file could not be opened.  !
   ! info holds the text block's lines (deck, title, method, ...),    !
   ! written as given, each ending in a newline.                      !
   !                                                                  !
   ! Called once the deck is read, before the database exists, so the !
   ! cell count comes from the layer table: the last layer's last     !
   ! cell is k_max.                                                   !
   !******************************************************************!
   subroutine open_history( title, info, ios )
   implicit none
   character(len=*), intent(in) :: title
   character(len=*), dimension(:), intent(in) :: info
   integer(kind=int32), intent(out) :: ios
   integer(kind=int32) :: j, n, header_bytes, frame_bytes, order
   character(len=8) :: meth
   character(len=text_bytes) :: text

   ios = 0
   if ( plot_every <= 0 .and. .not. ( plot_dt > zero ) ) return
   hst_file = trim(title)//'.hist'
   open( newunit=khs, file=trim(hst_file), status='replace', &
         action='write', access='stream', form='unformatted', iostat=ios )
   if ( ios /= 0 ) return
   hst_open   = .true.
   hst_frames = 0
   tnext      = zero
   kh         = layer(nlay)%klast
   if ( method == 'RS' ) then
      slot  = hv_rs
      order = rs_order
   else
      slot  = hv_av
      order = 0
   end if
   meth = method

   !*** The sizes. A face variable has kh + 1 values, a cell one kh.
   n = 0
   do j = 1, nhv
      n = n + kh + 1 - hv_where(j)
   end do
   allocate( buf(n) )
   frame_bytes  = 16 + 4*n
   header_bytes = 64 + 32*nhv + 72*nlay + text_bytes

   !*** The text block: the lines, then spaces to the end.
   text = ' '
   n = 0
   do j = 1, size(info)
      if ( n + len_trim(info(j)) + 1 > text_bytes ) exit
      text(n+1:n+len_trim(info(j))+1) = trim(info(j))//new_line('a')
      n = n + len_trim(info(j)) + 1
   end do

   !*** 1. Fixed part, 64 bytes. nframes and status are 0 until
   !*** close_history fills them in.
   write( khs ) magic, version, header_bytes, frame_bytes, 0_int32, &
      0_int32, kh, nhv, nlay, meth, order, text_bytes, 0_int32, 0_int32
   !*** 2. Variables, 32 bytes each.
   do j = 1, nhv
      write( khs ) hv_name(j), hv_unit(j), hv_where(j), 0_int32
   end do
   !*** 3. Layers, 72 bytes each, left to right.
   do j = 1, nlay
      write( khs ) layer(j)%name, layer(j)%matname, layer(j)%kfirst, &
         layer(j)%klast
   end do
   !*** 4. Text.
   write( khs ) text
   flush( khs )
   end subroutine open_history

   !******************************************************************!
   ! One frame, if this cycle is a snapshot. Called once per cycle,   !
   ! right after the tracer row, with the same cycle and time.        !
   !                                                                  !
   ! A snapshot is cycle 0, every plot_every cycles, the first cycle  !
   ! at or after each multiple of plot_dt (at that cycle's own time;  !
   ! nothing is interpolated), and always the last cycle. The next    !
   ! plot_dt time is counted in whole multiples, so it never drifts   !
   ! (as the tracer file's tracer_dt).                                !
   !                                                                  !
   ! The frame holds x and P at TIME and u at the half step before    !
   ! it, the velocity the method carries: AV's u, RS's u* (as KMPS in !
   ! the tracer file). Faces 1 to kh+1 are iface(0) to iface(kh);     !
   ! cells 1 to kh are icell(1) to icell(kh); no ghosts.              !
   !******************************************************************!
   subroutine history_frame( ncycle, time, last )
   implicit none
   integer(kind=int32), intent(in) :: ncycle ! cycle number, n
   real(kind=dp), intent(in) :: time      ! us
   logical, intent(in) :: last            ! the run's last cycle
   logical :: snap
   integer(kind=int32) :: j, n, k

   if ( .not. hst_open ) return
   snap = ( ncycle == 0 .or. last )
   if ( plot_every > 0 ) snap = snap .or. ( mod(ncycle, plot_every) == 0 )
   if ( plot_dt > zero ) snap = snap .or. .not. ( time < tnext )
   if ( .not. snap ) return
   if ( plot_dt > zero ) tnext = ( aint( time/plot_dt ) + 1.0_dp )*plot_dt

   n = 0
   do j = 1, nhv
      if ( hv_where(j) == 0 ) then
         do k = 0, kh
            buf(n+k+1) = real( database( slot(j), iface(k) ), sp )
         end do
         n = n + kh + 1
      else
         do k = 1, kh
            buf(n+k) = real( database( slot(j), icell(k) ), sp )
         end do
         n = n + kh
      end if
   end do
   hst_frames = hst_frames + 1
   write( khs ) time, ncycle, hst_frames, buf
   flush( khs )
   end subroutine history_frame

   !******************************************************************!
   ! Fill in nframes and status (bytes 20 and 24 of the header), then !
   ! close. status: 1 reached t_end, 2 reached cycle_max, 3 stopped   !
   ! by an error; maincode says which. A file never closed here keeps !
   ! status 0 (the run crashed).                                      !
   !******************************************************************!
   subroutine close_history( status )
   implicit none
   integer(kind=int32), intent(in) :: status
   if ( .not. hst_open ) return
   write( khs, pos=21 ) hst_frames, status
   close( khs )
   hst_open = .false.
   if ( allocated(buf) ) deallocate( buf )
   end subroutine close_history

end module hist

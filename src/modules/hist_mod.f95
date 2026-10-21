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
!                the k_max + 1 faces and P at the k_max cells (real32),
!                and D at the cells (int8: 0 intact, 1 broken)
!
!    Little-endian stream access (plain bytes, no record markers),
!    flushed after every frame, so a crashed run still leaves whole
!    frames. nframes and status are filled in when the run ends
!    (close_history, from maincode's close_outputs).
!
!    It also READS the file back (read_history), for the pictures
!    (module pics): after a run, and in a plots_only run.
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
!    10/20/26    D. E. Kittell        DMG (int8) as a 4th variable; each
!                (with Claude)        variable has a type (0 real32,
!                                     1 int8); plot_dt and plot_every in
!                                     the text; read_history
!
!**********************************************************************!
use bits,  only: sp, dp, int8, int32, int64, zero
use shock, only: jx, ju, jp, jdam, ju_star, database, iface, icell, &
   layer, nlay, method, rs_order, plot_every, plot_dt
implicit none
private

public :: open_history, history_frame, close_history, hst_open, &
   hst_file, hst_frames, read_history, free_history

!**********************************************************************!
!  The variables in each frame, in file order (the header's variable
!  table). Names and units are the tracer file's. To add one: an entry
!  here (its slot for AV, its slot for RS, name, unit, 0 = faces or
!  1 = cells, 0 = real32 or 1 = int8), at the END, and bump nhv; the
!  reader finds variables by name, so old files and scripts keep
!  working. An int8 variable is stored as 0 or 1: 1 wherever the slot
!  is above 0 (damage: any D > 0 counts as broken).
!**********************************************************************!
integer(kind=int32), parameter :: nhv = 4
integer(kind=int32), parameter, dimension(nhv) :: hv_av = &
   (/ jx, ju,      jp, jdam /)
integer(kind=int32), parameter, dimension(nhv) :: hv_rs = &
   (/ jx, ju_star, jp, jdam /)
character(len=8),  parameter, dimension(nhv) :: hv_name = (/ &
   'XPOS    ', 'KMPS    ', 'GPA     ', 'DMG     ' /)
character(len=16), parameter, dimension(nhv) :: hv_unit = (/ &
   'mm              ', 'km/s            ', 'GPa             ', &
   '-               ' /)
integer(kind=int32), parameter, dimension(nhv) :: hv_where = (/ 0, 0, 1, 1 /)
integer(kind=int32), parameter, dimension(nhv) :: hv_type  = (/ 0, 0, 0, 1 /)

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

!*** One frame's values: the real32 variables, then the int8 ones.
!*** Sized when the file opens.
real(kind=sp),      allocatable :: buf(:)
integer(kind=int8), allocatable :: ibuf(:)

!**********************************************************************!
!  What read_history reads back (public, for module pics). Frames
!  are the second index: hr_x(k, j) is face k of frame j.
!**********************************************************************!
integer(kind=int32), public :: hr_nframes = 0      ! frames read
integer(kind=int32), public :: hr_status  = 0      ! how the run ended
integer(kind=int32), public :: hr_kmax    = 0      ! cells
integer(kind=int32), public :: hr_nlay    = 0      ! layers
character(len=8),    public :: hr_method  = ' '    ! AV or RS
integer(kind=int32), public :: hr_order   = 0      ! RS 1 or 2, AV 0
character(len=32),   public, allocatable :: hr_lname(:), hr_lmat(:)
integer(kind=int32), public, allocatable :: hr_kfirst(:), hr_klast(:)
character(len=:),    public, allocatable :: hr_text   ! the text block
real(kind=dp),       public, allocatable :: hr_time(:)
integer(kind=int32), public, allocatable :: hr_cycle(:)
real(kind=sp),       public, allocatable :: hr_x(:,:), hr_u(:,:), hr_p(:,:)
integer(kind=int8),  public, allocatable :: hr_d(:,:)

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
   integer(kind=int32) :: j, n, ni, header_bytes, frame_bytes, order
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

   !*** The sizes. A face variable has kh + 1 values, a cell one kh;
   !*** a real32 value is 4 bytes, an int8 one 1.
   n  = 0
   ni = 0
   do j = 1, nhv
      if ( hv_type(j) == 0 ) then
         n  = n  + kh + 1 - hv_where(j)
      else
         ni = ni + kh + 1 - hv_where(j)
      end if
   end do
   allocate( buf(n), ibuf(ni) )
   frame_bytes  = 16 + 4*n + ni
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
      write( khs ) hv_name(j), hv_unit(j), hv_where(j), hv_type(j)
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
   integer(kind=int32) :: j, n, ni, k, nv

   if ( .not. hst_open ) return
   snap = ( ncycle == 0 .or. last )
   if ( plot_every > 0 ) snap = snap .or. ( mod(ncycle, plot_every) == 0 )
   if ( plot_dt > zero ) snap = snap .or. .not. ( time < tnext )
   if ( .not. snap ) return
   if ( plot_dt > zero ) tnext = ( aint( time/plot_dt ) + 1.0_dp )*plot_dt

   hst_frames = hst_frames + 1
   write( khs ) time, ncycle, hst_frames
   n  = 0
   ni = 0
   do j = 1, nhv
      nv = kh + 1 - hv_where(j)
      if ( hv_type(j) == 0 ) then
         do k = 1, nv
            buf(n+k) = real( database( slot(j), place(j, k) ), sp )
         end do
         write( khs ) buf(n+1:n+nv)
         n = n + nv
      else
         do k = 1, nv
            ibuf(ni+k) = merge( 1_int8, 0_int8, &
               database( slot(j), place(j, k) ) > zero )
         end do
         write( khs ) ibuf(ni+1:ni+nv)
         ni = ni + nv
      end if
   end do
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
   if ( allocated(buf) )  deallocate( buf )
   if ( allocated(ibuf) ) deallocate( ibuf )
   end subroutine close_history

   !*** The database index of value k (from 1) of variable j: face k is
   !*** iface(k-1) (faces 1 to kh+1 from the left), cell k is icell(k).
   integer(kind=int32) function place( j, k )
   implicit none
   integer(kind=int32), intent(in) :: j, k
   if ( hv_where(j) == 0 ) then
      place = iface( k - 1 )
   else
      place = icell( k )
   end if
   end function place

   !******************************************************************!
   ! Read a history file back, whole, into the hr_ arrays above, for  !
   ! the pictures. msg is blank if it worked, and otherwise says why  !
   ! not (in words for the screen).                                   !
   !                                                                  !
   ! Read by the format (input/README.md, section 9), not by what     !
   ! this bitwhiz writes: variables are found by name and type, so a  !
   ! file without DMG (written before it was added) reads too, with D !
   ! = 0, and a variable this reader does not know is skipped. A file !
   ! whose run crashed (nframes = 0 in the header) gives its whole    !
   ! frames, counted from the file's size.                            !
   !******************************************************************!
   subroutine read_history( fname, msg )
   implicit none
   character(len=*), intent(in) :: fname
   character(len=:), allocatable, intent(out) :: msg
   character(len=8) :: mg, meth
   integer(kind=int32) :: ver, header_bytes, frame_bytes, nframes, &
      status, kmax, nvar, nl, order, tbytes, spare(2)
   character(len=8),  allocatable :: vname(:)
   character(len=16), allocatable :: vunit(:)
   integer(kind=int32), allocatable :: vwhere(:), vtype(:), nval(:)
   real(kind=sp),      allocatable :: rv(:)
   integer(kind=int8), allocatable :: iv(:)
   integer(kind=int32) :: lu, ios, j, jf, nbytes, nfr, cyc, frm
   integer(kind=int64) :: fsize
   real(kind=dp) :: t
   logical :: has(4)

   msg = ''
   call free_history()
   open( newunit=lu, file=fname, status='old', action='read', &
         access='stream', form='unformatted', iostat=ios )
   if ( ios /= 0 ) then
      msg = 'cannot open '//fname
      return
   end if
   inquire( unit=lu, size=fsize )

   !*** 1. Fixed part.
   read( lu, iostat=ios ) mg, ver, header_bytes, frame_bytes, nframes, &
      status, kmax, nvar, nl, meth, order, tbytes, spare
   if ( ios /= 0 .or. mg /= magic ) then
      msg = fname//' is not a bitwhiz history file'
      close( lu ); return
   end if
   if ( ver /= version ) then
      msg = fname//' is format version '//itoa(ver)// &
         '; this bitwhiz reads version '//itoa(version)
      close( lu ); return
   end if
   if ( kmax < 1 .or. nvar < 1 .or. nl < 1 .or. tbytes < 0 .or. &
        header_bytes /= 64 + 32*nvar + 72*nl + tbytes ) then
      msg = fname//' has a damaged header'
      close( lu ); return
   end if

   !*** 2. Variables: their sizes must add up to frame_bytes.
   allocate( vname(nvar), vunit(nvar), vwhere(nvar), vtype(nvar), &
      nval(nvar) )
   nbytes = 16
   do j = 1, nvar
      read( lu ) vname(j), vunit(j), vwhere(j), vtype(j)
      if ( vwhere(j) < 0 .or. vwhere(j) > 1 .or. vtype(j) < 0 .or. &
           vtype(j) > 1 ) then
         msg = fname//': variable '//trim(vname(j))//' has an unknown '// &
            'place or type'
         close( lu ); return
      end if
      nval(j) = kmax + 1 - vwhere(j)
      nbytes  = nbytes + nval(j)*merge( 4, 1, vtype(j) == 0 )
   end do
   if ( nbytes /= frame_bytes ) then
      msg = fname//' has a damaged header (frame size)'
      close( lu ); return
   end if
   !*** The four this reader uses, each where it must be.
   has = .false.
   do j = 1, nvar
      select case ( trim(vname(j)) )
      case ( 'XPOS' ); has(1) = ( vwhere(j) == 0 .and. vtype(j) == 0 )
      case ( 'KMPS' ); has(2) = ( vwhere(j) == 0 .and. vtype(j) == 0 )
      case ( 'GPA'  ); has(3) = ( vwhere(j) == 1 .and. vtype(j) == 0 )
      case ( 'DMG'  ); has(4) = ( vwhere(j) == 1 .and. vtype(j) == 1 )
      end select
   end do
   if ( .not. all( has(1:3) ) ) then
      msg = fname//' does not have XPOS and KMPS (faces) and GPA (cells)'
      close( lu ); return
   end if

   !*** 3. Layers, 4. text.
   allocate( hr_lname(nl), hr_lmat(nl), hr_kfirst(nl), hr_klast(nl) )
   do j = 1, nl
      read( lu ) hr_lname(j), hr_lmat(j), hr_kfirst(j), hr_klast(j)
   end do
   allocate( character(len=tbytes) :: hr_text )
   read( lu ) hr_text

   !*** Frames: the header's count, or (a run that crashed, nframes =
   !*** 0) every whole frame in the file.
   nfr = int( ( fsize - int(header_bytes,int64) )/int(frame_bytes,int64), &
      int32 )
   if ( nframes > 0 .and. nframes /= nfr ) then
      msg = fname//' holds '//itoa(nfr)//' frames, but its header says '// &
         itoa(nframes)
      close( lu ); return
   end if
   if ( nfr < 1 ) then
      msg = fname//' has no frames'
      close( lu ); return
   end if
   allocate( hr_time(nfr), hr_cycle(nfr), hr_x(kmax+1,nfr), &
      hr_u(kmax+1,nfr), hr_p(kmax,nfr), hr_d(kmax,nfr), rv(kmax+1), &
      iv(kmax+1) )
   hr_d = 0_int8
   do jf = 1, nfr
      read( lu, iostat=ios ) t, cyc, frm
      if ( ios /= 0 ) exit
      hr_time(jf)  = t
      hr_cycle(jf) = cyc
      do j = 1, nvar
         if ( vtype(j) == 0 ) then
            read( lu, iostat=ios ) rv(1:nval(j))
         else
            read( lu, iostat=ios ) iv(1:nval(j))
         end if
         if ( ios /= 0 ) exit
         select case ( trim(vname(j)) )
         case ( 'XPOS' ); hr_x(:,jf) = rv(1:kmax+1)
         case ( 'KMPS' ); hr_u(:,jf) = rv(1:kmax+1)
         case ( 'GPA'  ); hr_p(:,jf) = rv(1:kmax)
         case ( 'DMG'  ); if ( has(4) ) hr_d(:,jf) = iv(1:kmax)
         end select
      end do
      if ( ios /= 0 ) exit
   end do
   close( lu )
   if ( ios /= 0 ) then
      msg = 'cannot read frame '//itoa(jf)//' of '//fname
      call free_history()
      return
   end if
   hr_nframes = nfr
   hr_status  = status
   hr_kmax    = kmax
   hr_nlay    = nl
   hr_method  = meth
   hr_order   = order
   end subroutine read_history

   !*** Free what read_history read (safe to call any time).
   subroutine free_history()
   implicit none
   if ( allocated(hr_lname) )  deallocate( hr_lname, hr_lmat, hr_kfirst, &
      hr_klast )
   if ( allocated(hr_text) )   deallocate( hr_text )
   if ( allocated(hr_time) )   deallocate( hr_time, hr_cycle, hr_x, hr_u, &
      hr_p, hr_d )
   hr_nframes = 0
   end subroutine free_history

   !*** An integer as text, no padding.
   function itoa( i ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: i
   character(len=:), allocatable :: s
   character(len=16) :: b
   write( b, '(i0)' ) i
   s = trim(b)
   end function itoa

end module hist

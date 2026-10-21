module pics
!**********************************************************************!
!
!  Purpose:
!    The pictures a run leaves (maincode section 9): at the end of a
!    run, and the whole of a plots_only run, which re-draws them from
!    the files an earlier run of the same deck wrote, without running
!    (a new colormap or color window takes about a second).
!
!       <title>.tx_u.bmp     t-x diagram of the velocity u   } with
!       <title>.tx_p.bmp     t-x diagram of the pressure P   } snapshots
!       <title>.tr_<name>.bmp  velocity against time, one per tracer
!
!    Everything is read back from the files, never from the run's
!    memory, so a picture after a run and the same picture from a
!    plots_only run are made by the same code from the same numbers:
!
!       t-x diagrams   <title>.hist         (module hist, read_history)
!       tracer plots   <title>.tracers.csv  (read here)
!
!    The history file must have been made by this deck: its method,
!    order, cells and layers are checked against the deck's. Its
!    frames decide the picture, whatever the deck's plot_dt and
!    plot_every say now (they only say whether there is a file).
!
!  The drawing is done by two fixed-size routines in src/drawings,
!  each of which prepares its image and hands it to bmpmaker, as
!  draw_colormaps does:
!
!       draw_tx      t-x diagram, 1200 x 900 pixels, the deck's colormap
!       draw_trace   tracer plot,  800 x 600 pixels, on white
!
!  The pictures:
!    t-x diagrams, in the lab frame: x across, from the smallest to
!    the largest face position of the whole run, t up, from 0 to the
!    last frame, inside a frame like the tracer plots', titled
!    BITWHIZ PRESSURE VIEW or BITWHIZ VELOCITY VIEW, with a color bar
!    (0 to 1 of the window) below. Colors:
!    the deck's colormap over the color window, min + lo*(max - min)
!    to min + hi*(max - min) of the data (plot_u_lo, ...), values
!    beyond saturating. White: open spall (D = 1 and P = 0) and
!    outside the material, in both; in P also every cell no wave has
!    reached yet (its |P| has not yet exceeded 1e-6 of the run's
!    largest |P|). Each cell is drawn between its faces at that time
!    (u linear between them), pixels averaging the cells over them
!    and shaded by how much of them is colored (anti-aliasing,
!    draw_tx).
!    Tracer plots: velocity against time, x from the first to the
!    last time, y from min - 5% to max + 5% of the range, a border
!    and tick marks at tenths, and the title BITWHIZ SCOPE VIEW
!    above the box (no other text).
!    The screen gets every range, so a picture can be read without
!    text on it.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/20/26    D. E. Kittell        Original code: reading, checks,
!                (with Claude)        ranges and the calls; drawing next
!    10/20/26    D. E. Kittell        The calls go to draw_xt and
!                (with Claude)        draw_trace (src/drawings), which
!                                     draw fiducials for now; each file
!                                     is checked to exist afterwards
!    10/20/26    D. E. Kittell        draw_xt gets the color window;
!                (with Claude)        the P t-x diagram is drawn
!    10/20/26    D. E. Kittell        t-x, not x-t, in names: files
!                (with Claude)        <title>.tx_u.bmp, .tx_p.bmp and
!                                     draw_tx; the u t-x diagram is
!                                     drawn too
!    10/21/26    D. E. Kittell        Quieter: each group of pictures
!                (with Claude)        is announced once (bmpmaker no
!                                     longer prints per file)
!    10/21/26    D. E. Kittell        draw_trace gets each tracer's
!                (with Claude)        times, velocities and y axis
!    10/21/26    D. E. Kittell        Comments: the t-x diagrams get
!                (with Claude)        the scope view's frame, a title,
!                                     a color bar, anti-aliasing
!
!**********************************************************************!
use bits,  only: sp, dp, int32, zero, one, kpt6
use shock, only: title, layer, nlay, method, rs_order, plot_every, &
   plot_dt, plots_only, tracer, ntrc, colormap, plot_u_lo, plot_u_hi, &
   plot_p_lo, plot_p_hi
use hist,  only: read_history, free_history, hr_nframes, hr_status, &
   hr_kmax, hr_nlay, hr_method, hr_order, hr_lname, hr_lmat, hr_kfirst, &
   hr_klast, hr_text, hr_time, hr_x, hr_u, hr_p
use deck,  only: fmt_real, get_line
implicit none
private

public :: make_pictures

character(len=*), parameter :: fl = '(3x,a,t40,'': '',a)'   ! label : text

!*** The drawing routines (src/drawings; external, like bmpmaker).
!*** The interface lets the compiler check every call.
interface
   subroutine draw_tx( var, bout, cmap, clo, chi )
      import :: dp
      character(len=*), intent(in) :: var
      character(len=80), intent(in) :: bout, cmap
      real(kind=dp), intent(in) :: clo, chi
   end subroutine draw_tx
   subroutine draw_trace( bout, n, t, u, ylo, yhi )
      import :: dp, int32
      character(len=80), intent(in) :: bout
      integer(kind=int32), intent(in) :: n
      real(kind=dp), intent(in) :: t(n), u(n), ylo, yhi
   end subroutine draw_trace
end interface

contains

   !******************************************************************!
   ! All the pictures this deck asks for. nerr counts what went wrong !
   ! (a file missing, or not from this deck); each is reported on the !
   ! screen, and the caller stops with exit status 1.                 !
   !******************************************************************!
   subroutine make_pictures( nerr )
   implicit none
   integer(kind=int32), intent(out) :: nerr
   logical :: want_tx, want_tr

   nerr = 0
   want_tx = ( plot_every > 0 .or. plot_dt > zero )
   want_tr = ( ntrc > 0 )
   write( kpt6, '(1x,a)' ) repeat('=',56)
   write( kpt6, '(1x,a)' ) ' 9. Pictures'
   write( kpt6, '(1x,a)' ) repeat('-',56)
   if ( plots_only ) write( kpt6, fl ) 'plots_only', &
      'yes: no run; from the files of an earlier run'
   if ( .not. ( want_tx .or. want_tr ) ) then
      write( kpt6, fl ) 'Pictures', 'none (no plot_every, plot_dt or '// &
         'tracers in the deck)'
      if ( plots_only ) call error( 'plots_only: this deck has nothing '// &
         'to draw', nerr )
   else
      write( kpt6, fl ) 'Colormap', trim(colormap)
      if ( want_tx ) call tx_pictures( nerr )
      if ( want_tr ) call tracer_pictures( nerr )
   end if
   if ( plots_only .and. nerr > 0 ) write( kpt6, '(a)' ) ' bitwhiz: '// &
      'plots_only re-draws from the files a run of this deck wrote; '// &
      'run it once with plots_only = no first'
   write( kpt6, '(1x,a)' ) repeat('=',56)
   end subroutine make_pictures

   !******************************************************************!
   ! The two t-x diagrams, from <title>.hist.                         !
   !******************************************************************!
   subroutine tx_pictures( nerr )
   implicit none
   integer(kind=int32), intent(inout) :: nerr
   character(len=:), allocatable :: fname, msg, what
   real(kind=sp) :: umin, umax, pmin, pmax
   real(kind=dp) :: ulo, uhi, plo, phi
   integer(kind=int32) :: l, ord

   fname = trim(title)//'.hist'
   call read_history( fname, msg )
   if ( len(msg) > 0 ) then
      call error( msg, nerr )
      return
   end if

   !*** Made by this deck? Method, order, cells, then every layer.
   ord = 0
   if ( method == 'RS' ) ord = rs_order
   what = ''
   if ( hr_method /= method ) then
      what = 'method '//trim(hr_method)//', not '//trim(method)
   else if ( hr_order /= ord ) then
      what = 'order '//itoa(hr_order)//', not '//itoa(ord)
   else if ( hr_kmax /= layer(nlay)%klast ) then
      what = itoa(hr_kmax)//' cells, not '//itoa(layer(nlay)%klast)
   else if ( hr_nlay /= nlay ) then
      what = itoa(hr_nlay)//' layers, not '//itoa(nlay)
   else
      do l = 1, nlay
         if ( hr_lname(l) /= layer(l)%name .or. &
              hr_lmat(l)  /= layer(l)%matname .or. &
              hr_kfirst(l) /= layer(l)%kfirst .or. &
              hr_klast(l)  /= layer(l)%klast ) then
            what = 'layer '//itoa(l)//' is '//trim(hr_lname(l))//' ('// &
               trim(hr_lmat(l))//', cells '//itoa(hr_kfirst(l))//' to '// &
               itoa(hr_klast(l))//')'
            exit
         end if
      end do
   end if
   if ( len(what) > 0 ) then
      call error( fname//' was not made by this deck: '//what, nerr )
      call free_history()
      return
   end if

   !*** What the file holds.
   write( kpt6, fl ) 'History file', fname
   write( kpt6, fl ) 'Frames', itoa(hr_nframes)//', t = '// &
      fmt_real(hr_time(1))//' to '//fmt_real(hr_time(hr_nframes))//' us'
   if ( text_value('plot_dt') == '?' ) then
      write( kpt6, fl ) 'Written with', 'plot_dt, plot_every not '// &
         'recorded (an older file)'
   else
      write( kpt6, fl ) 'Written with', 'plot_dt = '// &
         text_value('plot_dt')//' us, plot_every = '//text_value('plot_every')
   end if
   if ( plots_only .and. ( text_value('plot_dt') /= fmt_real(plot_dt) &
        .or. text_value('plot_every') /= itoa(plot_every) ) ) &
      write( kpt6, fl ) 'This deck''s plot_dt, plot_every', &
         'not used: the frames in the file are'
   select case ( hr_status )
   case ( 1 )
   case ( 2 )
      write( kpt6, fl ) 'Run ended', 'at cycle_max, before t_end'
   case ( 3 )
      write( kpt6, fl ) 'Run ended', 'stopped by an error'
   case default
      write( kpt6, fl ) 'Run ended', 'not cleanly (crashed?); its '// &
         'whole frames are used'
   end select

   !*** Ranges and color windows (fractions of each range).
   umin = minval(hr_u); umax = maxval(hr_u)
   pmin = minval(hr_p); pmax = maxval(hr_p)
   ulo = real(umin,dp) + plot_u_lo*real(umax - umin,dp)
   uhi = real(umin,dp) + plot_u_hi*real(umax - umin,dp)
   plo = real(pmin,dp) + plot_p_lo*real(pmax - pmin,dp)
   phi = real(pmin,dp) + plot_p_hi*real(pmax - pmin,dp)
   write( kpt6, fl ) 'x across (mm)', num(minval(hr_x))//' to '// &
      num(maxval(hr_x))
   write( kpt6, fl ) 't up (us)', num(real(hr_time(1),sp))//' to '// &
      num(real(hr_time(hr_nframes),sp))
   write( kpt6, fl ) 'u in the run (km/s)', num(umin)//' to '//num(umax)
   write( kpt6, fl ) 'u colors (km/s)', num(real(ulo,sp))//' to '// &
      num(real(uhi,sp))//'  (window '//fmt_real(plot_u_lo)//' to '// &
      fmt_real(plot_u_hi)//')'
   write( kpt6, fl ) 'P in the run (GPa)', num(pmin)//' to '//num(pmax)
   write( kpt6, fl ) 'P colors (GPa)', num(real(plo,sp))//' to '// &
      num(real(phi,sp))//'  (window '//fmt_real(plot_p_lo)//' to '// &
      fmt_real(plot_p_hi)//')'
   write( kpt6, fl ) 'White', 'outside the material, open spall '// &
      '(D = 1, P = 0);'
   write( kpt6, fl ) '', 'in P also material no wave has reached'

   !*** The pictures, announced once.
   write( kpt6, fl ) 'Drawing t-x diagrams', trim(title)//'.tx_u.bmp, '// &
      trim(title)//'.tx_p.bmp'
   call tx_file( 'u', trim(title)//'.tx_u', ulo, uhi, nerr )
   call tx_file( 'P', trim(title)//'.tx_p', plo, phi, nerr )
   call free_history()
   end subroutine tx_pictures

   !******************************************************************!
   ! One plot per tracer, velocity against time, from the tracer      !
   ! file: its TIME column and the tracer's KMPS column.              !
   !******************************************************************!
   subroutine tracer_pictures( nerr )
   implicit none
   integer(kind=int32), intent(inout) :: nerr
   character(len=:), allocatable :: fname, line
   character(len=64), allocatable :: names(:)
   real(kind=dp), allocatable :: row(:), t(:), u(:,:)
   integer(kind=int32), allocatable :: col(:)
   integer(kind=int32) :: lu, ios, ncol, nrow, it, ktime, n
   logical :: eof, bad
   real(kind=dp) :: umin, umax, del

   fname = trim(title)//'.tracers.csv'
   open( newunit=lu, file=fname, status='old', action='read', iostat=ios )
   if ( ios /= 0 ) then
      call error( 'cannot open '//fname, nerr )
      return
   end if

   !*** Line 1: the column names. TIME, and each tracer's KMPS column.
   call get_line( lu, line, eof, bad )
   if ( eof .or. bad ) then
      call error( fname//' is empty or cannot be read', nerr )
      close( lu ); return
   end if
   call split_csv( line, names, ncol )
   ktime = find( names, ncol, 'TIME' )
   allocate( col(ntrc) )
   do it = 1, ntrc
      col(it) = find( names, ncol, 'KMPS.'//trim(tracer(it)%name) )
      if ( col(it) == 0 ) call error( 'tracer '//trim(tracer(it)%name)// &
         ' is not in '//fname//' (not in the deck that made it?)', nerr )
   end do
   if ( ktime == 0 ) call error( fname//' has no TIME column', nerr )
   if ( ktime == 0 .or. any( col == 0 ) ) then
      close( lu ); return
   end if

   !*** The rows: count them, then read them (line 2 is the long names;
   !*** the trailer starts with '#').
   nrow = 0
   call get_line( lu, line, eof, bad )
   do
      call get_line( lu, line, eof, bad )
      if ( eof .or. bad ) exit
      if ( line(1:min(1,len(line))) == '#' ) exit
      nrow = nrow + 1
   end do
   if ( nrow < 1 ) then
      call error( fname//' has no rows', nerr )
      close( lu ); return
   end if
   allocate( row(ncol), t(nrow), u(nrow,ntrc) )
   rewind( lu )
   call get_line( lu, line, eof, bad )
   call get_line( lu, line, eof, bad )
   do n = 1, nrow
      call get_line( lu, line, eof, bad )
      read( line, *, iostat=ios ) row
      if ( ios /= 0 ) then
         call error( fname//': cannot read row '//itoa(n), nerr )
         close( lu ); return
      end if
      t(n) = row(ktime)
      do it = 1, ntrc
         u(n,it) = row(col(it))
      end do
   end do
   close( lu )

   !*** One plot per tracer: x from the first to the last time, y from
   !*** min - 5% to max + 5% of the range (a flat line: +-5% of its
   !*** value, or +-0.05 km/s at 0).
   !*** The pictures announced once; then one line per tracer, its
   !*** velocity range and the plot's y axis (what a reader needs to
   !*** read a plot whose only text is its title).
   write( kpt6, fl ) 'Tracer file', fname
   write( kpt6, fl ) 'Rows', itoa(nrow)//', t = '//fmt_real(t(1))// &
      ' to '//fmt_real(t(nrow))//' us'
   write( kpt6, fl ) 'Drawing tracer plots', itoa(ntrc)//', '// &
      trim(title)//'.tr_<tracer>.bmp'
   do it = 1, ntrc
      umin = minval(u(:,it)); umax = maxval(u(:,it))
      del  = 0.05_dp*( umax - umin )
      if ( .not. ( del > zero ) ) del = 0.05_dp*max( abs(umax), one )
      write( kpt6, fl ) 'Tracer '//trim(tracer(it)%name)//' u (km/s)', &
         num(real(umin,sp))//' to '//num(real(umax,sp))//', y axis '// &
         num(real(umin - del,sp))//' to '//num(real(umax + del,sp))
      call trace_file( trim(title)//'.tr_'//trim(tracer(it)%name), t, &
         u(:,it), umin - del, umax + del, nerr )
   end do
   end subroutine tracer_pictures

   !******************************************************************!
   ! One t-x diagram (u or P) into <base>.bmp: draw it (draw_tx, from !
   ! the history file just read, colors from clo to chi) and check    !
   ! the file is there. (The caller announces the pictures.)          !
   !******************************************************************!
   subroutine tx_file( var, base, clo, chi, nerr )
   implicit none
   character(len=*), intent(in) :: var, base
   real(kind=dp), intent(in) :: clo, chi
   integer(kind=int32), intent(inout) :: nerr
   character(len=80) :: bout, cmap
   bout = base
   cmap = colormap
   call fresh( base//'.bmp' )
   call draw_tx( var, bout, cmap, clo, chi )
   call written( base//'.bmp', nerr )
   end subroutine tx_file

   !******************************************************************!
   ! One tracer plot into <base>.bmp: draw its velocity u against     !
   ! time t, y axis from ylo to yhi (draw_trace), and check the file  !
   ! is there. (The caller announces the pictures.)                   !
   !******************************************************************!
   subroutine trace_file( base, t, u, ylo, yhi, nerr )
   implicit none
   character(len=*), intent(in) :: base
   real(kind=dp), intent(in) :: t(:), u(:), ylo, yhi
   integer(kind=int32), intent(inout) :: nerr
   character(len=80) :: bout
   bout = base
   call fresh( base//'.bmp' )
   call draw_trace( bout, size(t), t, u, ylo, yhi )
   call written( base//'.bmp', nerr )
   end subroutine trace_file

   !*** Remove an old copy of a picture before drawing it, so that
   !*** "written" below can only find the new one. (bmpmaker reports
   !*** a file it cannot open on the screen, but does not return it.)
   subroutine fresh( file )
   implicit none
   character(len=*), intent(in) :: file
   integer(kind=int32) :: lu, ios
   logical :: there
   inquire( file=file, exist=there )
   if ( .not. there ) return
   open( newunit=lu, file=file, status='old', iostat=ios )
   if ( ios == 0 ) close( lu, status='delete' )
   end subroutine fresh

   !*** Was the picture written? If not, an error.
   subroutine written( file, nerr )
   implicit none
   character(len=*), intent(in) :: file
   integer(kind=int32), intent(inout) :: nerr
   logical :: there
   inquire( file=file, exist=there )
   if ( .not. there ) call error( 'could not write '//file, nerr )
   end subroutine written

   !******************************************************************!
   ! Small helpers.                                                   !
   !******************************************************************!

   !*** A problem, on the screen, counted.
   subroutine error( msg, nerr )
   implicit none
   character(len=*), intent(in) :: msg
   integer(kind=int32), intent(inout) :: nerr
   write( kpt6, '(a)' ) ' bitwhiz: '//msg
   nerr = nerr + 1
   end subroutine error

   !*** The value of a "key : value" line of the history file's text
   !*** ('?' if there is none, e.g. a file from before it was added).
   function text_value( key ) result(v)
   implicit none
   character(len=*), intent(in) :: key
   character(len=:), allocatable :: v
   integer(kind=int32) :: i, j, k
   v = '?'
   i = index( hr_text, new_line('a')//key//' ' )
   if ( i == 0 ) return
   j = i + index( hr_text(i+1:), ':' )
   k = index( hr_text(j+1:), new_line('a') )
   if ( k == 0 ) return
   v = trim(adjustl( hr_text(j+1:j+k-1) ))
   end function text_value

   !*** The comma-separated fields of a line, blanks trimmed.
   subroutine split_csv( line, names, n )
   implicit none
   character(len=*), intent(in) :: line
   character(len=64), allocatable, intent(out) :: names(:)
   integer(kind=int32), intent(out) :: n
   integer(kind=int32) :: i, j
   n = count( transfer( line, 'a', len(line) ) == ',' ) + 1
   allocate( names(n) )
   i = 1
   do j = 1, n
      if ( j < n ) then
         names(j) = adjustl( line(i:i-2+index(line(i:), ',')) )
         i = i + index( line(i:), ',' )
      else
         names(j) = adjustl( line(i:) )
      end if
   end do
   end subroutine split_csv

   !*** Which column has this name (ignoring case), 0 if none.
   integer(kind=int32) function find( names, n, want )
   implicit none
   character(len=64), intent(in) :: names(:)
   integer(kind=int32), intent(in) :: n
   character(len=*), intent(in) :: want
   integer(kind=int32) :: j
   find = 0
   do j = 1, n
      if ( lower(names(j)) == lower(want) ) then
         find = j
         return
      end if
   end do
   end function find

   function lower( s ) result(r)
   implicit none
   character(len=*), intent(in) :: s
   character(len=len(s)) :: r
   integer(kind=int32) :: i, c
   r = s
   do i = 1, len(s)
      c = iachar( s(i:i) )
      if ( c >= iachar('A') .and. c <= iachar('Z') ) r(i:i) = achar(c + 32)
   end do
   end function lower

   !*** A number for the screen, rounded to 5 significant digits and
   !*** written as plainly as fmt_real writes the resolved deck
   !*** (2.0917, -0.099603, 18.709, 0.0).
   function num( x ) result(s)
   implicit none
   real(kind=sp), intent(in) :: x
   character(len=:), allocatable :: s
   real(kind=dp) :: y, scale
   integer(kind=int32) :: e
   y = real( x, dp )
   if ( .not. ( abs(y) > zero ) ) then
      s = fmt_real( zero )
      return
   end if
   e = floor( log10( abs(y) ) )
   scale = 10.0_dp**( 4 - e )
   s = fmt_real( anint( y*scale )/scale )
   end function num

   function itoa( i ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: i
   character(len=:), allocatable :: s
   character(len=16) :: b
   write( b, '(i0)' ) i
   s = trim(b)
   end function itoa

end module pics

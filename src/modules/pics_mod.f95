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
!       <title>.mv_p_<cycle>.bmp  the pressure movie (movie_frames):
!                                 P against x, one frame per movie time
!
!    Everything is read back from the files, never from the run's
!    memory, so a picture after a run and the same picture from a
!    plots_only run are made by the same code from the same numbers:
!
!       t-x diagrams   <title>.hist         (module hist, read_history)
!       movie          <title>.hist
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
!       draw_profile movie frame,  800 x 600 pixels, on white (the line
!                    plot under draw_trace)
!
!  The pictures:
!    t-x diagrams, in the lab frame: x across, from the smallest to
!    the largest face position of the whole run, t up, from 0 to the
!    last frame, inside a frame like the tracer plots', titled
!    BITWHIZ PRESSURE VIEW or BITWHIZ VELOCITY VIEW, with a color bar
!    (0 to 1 of the window) below. Colors:
!    the deck's colormap over the color window, min + lo*(top - min)
!    to min + hi*(top - min) of the data (plot_u_lo, ...), values
!    beyond saturating. The top is the data's max with plot_range =
!    full; with robust (the default) it is the largest value the run
!    HELD: the highest level the mesh's largest value reaches for at
!    least nhold = 50 cycles in all (held_top), if the max is more
!    than 2% (spike) of the range above that; else the max. A start-up
!    spike, like the few tens of cycles of overshoot where two slabs
!    meet at an impact, then does not set the colors; a state that
!    lasts does, and a run without a spike keeps its full range. What
!    lies above the top is reported (how high, where, how many cycles)
!    and drawn in the top color. The min is always the data's own:
!    tension, the spall signal, is never trimmed.
!    White: open spall (D = 1 and P = 0) and outside the material, in both; in P also every cell no wave has
!    reached yet (its |P| has not yet exceeded 1e-3 of the run's
!    largest |P|). Each cell is drawn between its faces at that time
!    (u linear between them), pixels averaging the cells over them
!    and shaded by how much of them is colored (anti-aliasing,
!    draw_tx).
!    Tracer plots: velocity against time, x from the first to the
!    last time, y from min - 5% to max + 5% of the range, a border
!    and tick marks at tenths, and the title BITWHIZ SCOPE VIEW
!    above the box (no other text).
!    The pressure movie (movie_frames = N, 2 to 50, which needs
!    snapshots): N movie times spread evenly from 0 to the last
!    snapshot's, t_m = m*t_last/(N - 1), and for each the snapshot
!    nearest it (the earlier of two equally near; a snapshot two times
!    share is drawn once, so fewer snapshots than N give fewer frames).
!    Each frame is P against x, at the cells' centers, titled PRESSURE
!    AT TIME = +1.234 US and named by the snapshot's cycle in six
!    digits (rolling over past 999999), so they sort in time order. The
!    axes hold for the whole movie: x as the t-x diagrams' (the run's
!    smallest to largest face position, lab frame), y from min - 5% to
!    top + 5% of the run's P, the top found as the P t-x diagram's
!    (plot_range); a value above it is drawn at the box's edge. At
!    most 50 frames: a movie is a preview; figures come from the
!    history file (input/README.md, section 9).
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
!    10/24/26    D. E. Kittell        A tracer plot of a flat line,
!                (with Claude)        flat to round-off (an interface
!                                     at a steady u), gets the flat
!                                     line's axis, not one stretched
!                                     over its round-off; the white
!                                     rule's 1e-3 (draw_tx)
!    10/24/26    D. E. Kittell        plot_range: the t-x color ranges
!                (with Claude)        run to the top the run held for
!                                     50 cycles (robust, the default)
!                                     or to the max (full); what lies
!                                     above is reported
!    11/02/26    D. E. Kittell        The pressure movie
!                (with Claude)        (movie_frames): P against x from
!                                     the snapshots nearest N times
!                                     spread over the run, drawn by
!                                     draw_profile
!    11/03/26    D. E. Kittell        Section 9 opens with its rule and
!                (with Claude)        leaves the closing one to the run's
!                                     end (one rule between sections)
!    11/03/26    D. E. Kittell        The tracer plots' and the movie's
!                (with Claude)        axes rounded out to clean ends
!                                     (nice_ends, module strokes), which
!                                     the pictures now print
!
!**********************************************************************!
use bits,  only: sp, dp, int32, zero, one, kpt6
use shock, only: title, layer, nlay, method, rs_order, plot_every, &
   plot_dt, plots_only, tracer, ntrc, colormap, plot_range, plot_u_lo, &
   plot_u_hi, plot_p_lo, plot_p_hi, movie_frames
use hist,  only: read_history, free_history, hr_nframes, hr_status, &
   hr_kmax, hr_nlay, hr_method, hr_order, hr_lname, hr_lmat, hr_kfirst, &
   hr_klast, hr_text, hr_time, hr_cycle, hr_x, hr_u, hr_p
use deck,  only: fmt_real, get_line
use strokes, only: nice_ends
implicit none
private

public :: make_pictures

character(len=*), parameter :: fl = '(3x,a,t40,'': '',a)'   ! label : text
integer(kind=int32), parameter :: nhold = 50   ! cycles a robust top is held
real(kind=sp), parameter :: spike = 0.02_sp     ! a max this far (a fraction
                                                ! of the range) above it is
                                                ! a spike; less is kept

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
   subroutine draw_profile( bout, n, x, y, xlo, xhi, ylo, yhi, title_text )
      import :: dp, int32
      character(len=80), intent(in) :: bout
      integer(kind=int32), intent(in) :: n
      real(kind=dp), intent(in) :: x(n), y(n), xlo, xhi, ylo, yhi
      character(len=*), intent(in) :: title_text
   end subroutine draw_profile
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
   end subroutine make_pictures

   !******************************************************************!
   ! The two t-x diagrams, from <title>.hist.                         !
   !******************************************************************!
   subroutine tx_pictures( nerr )
   implicit none
   integer(kind=int32), intent(inout) :: nerr
   character(len=:), allocatable :: fname, msg, what
   real(kind=sp) :: umin, umax, pmin, pmax, utop, ptop
   real(kind=dp) :: ulo, uhi, plo, phi
   integer(kind=int32) :: l, ord, j

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

   !*** Ranges, their tops (plot_range) and the color windows
   !*** (fractions of min to top).
   umin = minval(hr_u); umax = maxval(hr_u)
   pmin = minval(hr_p); pmax = maxval(hr_p)
   utop = umax; ptop = pmax
   if ( plot_range == 'robust' ) then
      utop = held_top( [( maxval(hr_u(:,j)), j = 1, hr_nframes )] )
      ptop = held_top( [( maxval(hr_p(:,j)), j = 1, hr_nframes )] )
      ! Only a spike is left out: a max within 2% (spike) of the range
      ! above what was held is kept, so a run without one keeps its
      ! full range.
      if ( .not. ( umax - utop > spike*( utop - umin ) ) ) utop = umax
      if ( .not. ( pmax - ptop > spike*( ptop - pmin ) ) ) ptop = pmax
   end if
   ulo = real(umin,dp) + plot_u_lo*real(utop - umin,dp)
   uhi = real(umin,dp) + plot_u_hi*real(utop - umin,dp)
   plo = real(pmin,dp) + plot_p_lo*real(ptop - pmin,dp)
   phi = real(pmin,dp) + plot_p_hi*real(ptop - pmin,dp)
   write( kpt6, fl ) 'x across (mm)', num(minval(hr_x))//' to '// &
      num(maxval(hr_x))
   write( kpt6, fl ) 't up (us)', num(real(hr_time(1),sp))//' to '// &
      num(real(hr_time(hr_nframes),sp))
   if ( plot_range == 'robust' ) then
      write( kpt6, fl ) 'Color ranges', 'robust: min to the top held '// &
         'for '//itoa(nhold)//' cycles'
   else
      write( kpt6, fl ) 'Color ranges', 'full: min to max'
   end if
   write( kpt6, fl ) 'u in the run (km/s)', num(umin)//' to '//num(umax)
   if ( utop < umax ) call above( 'u above the range (km/s)', hr_u, &
      .true., utop )
   write( kpt6, fl ) 'u colors (km/s)', num(real(ulo,sp))//' to '// &
      num(real(uhi,sp))//'  (window '//fmt_real(plot_u_lo)//' to '// &
      fmt_real(plot_u_hi)//')'
   write( kpt6, fl ) 'P in the run (GPa)', num(pmin)//' to '//num(pmax)
   if ( ptop < pmax ) call above( 'P above the range (GPa)', hr_p, &
      .false., ptop )
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

   !*** The pressure movie, from the same file and the same P range.
   if ( movie_frames > 0 ) call movie_pictures( pmin, ptop, nerr )
   call free_history()
   end subroutine tx_pictures

   !******************************************************************!
   ! The pressure movie: P against x at the snapshots nearest         !
   ! movie_frames times spread from 0 to the last snapshot (module    !
   ! header). The history file is read; pmin and ptop are the P t-x   !
   ! diagram's (the top by plot_range).                               !
   !******************************************************************!
   subroutine movie_pictures( pmin, ptop, nerr )
   implicit none
   real(kind=sp), intent(in) :: pmin, ptop
   integer(kind=int32), intent(inout) :: nerr
   integer(kind=int32) :: pick(movie_frames)
   real(kind=dp), allocatable :: xc(:), v(:)
   real(kind=dp) :: xlo, xhi, plo, phi, del, tm, tlast
   real(kind=dp) :: step                    ! nice_ends' step (not used)
   integer(kind=int32) :: nf, kmax, nm, m, j, jn
   character(len=16) :: tstr
   character(len=6) :: cyc
   character(len=80) :: bout
   character(len=:), allocatable :: base

   nf = hr_nframes
   kmax = hr_kmax

   !*** The frames: for each movie time t_m = m*t_last/(N - 1), the
   !*** snapshot nearest it. The times only grow, so one pass; a
   !*** snapshot already taken (two movie times nearest the same one)
   !*** is not taken again.
   tlast = hr_time(nf)
   nm = 0
   jn = 1
   do m = 0, movie_frames - 1
      tm = tlast*real( m, dp )/real( movie_frames - 1, dp )
      do while ( jn < nf )
         if ( abs( hr_time(jn+1) - tm ) < abs( hr_time(jn) - tm ) ) then
            jn = jn + 1
         else
            exit
         end if
      end do
      if ( nm > 0 ) then
         if ( pick(nm) == jn ) cycle
      end if
      nm = nm + 1
      pick(nm) = jn
   end do

   !*** The axes, for the whole movie: x as the t-x diagrams', y from
   !*** min - 5% to top + 5% of P's range (a flat range: +-5% of its
   !*** value, at least +-0.05, as the tracer plots), then each rounded
   !*** out to clean ends.
   del = 0.05_dp*real( ptop - pmin, dp )
   if ( .not. ( real( ptop - pmin, dp ) > 1.0e-9_dp* &
        max( abs(real(pmin,dp)), abs(real(ptop,dp)), one ) ) ) &
      del = 0.05_dp*max( abs(real(ptop,dp)), one )
   call nice_ends( real( minval(hr_x), dp ), real( maxval(hr_x), dp ), &
      xlo, xhi, step )
   call nice_ends( real( pmin, dp ) - del, real( ptop, dp ) + del, plo, phi, &
      step )
   write( kpt6, fl ) 'Pressure movie', itoa(nm)//' frames (movie_frames '// &
      '= '//itoa(movie_frames)//') of the '//itoa(nf)//' snapshots'
   if ( nm < movie_frames ) write( kpt6, fl ) '', '(fewer: some movie '// &
      'times are nearest the same snapshot)'
   write( kpt6, fl ) 'Movie x axis (mm)', num(real(xlo,sp))//' to '// &
      num(real(xhi,sp))
   write( kpt6, fl ) 'Movie P axis (GPa)', num(real(plo,sp))//' to '// &
      num(real(phi,sp))
   write( kpt6, fl ) 'Drawing the movie', trim(title)//'.mv_p_<cycle>.bmp'

   !*** The frames: P at the cells' centers.
   allocate( xc(kmax), v(kmax) )
   do m = 1, nm
      j = pick(m)
      write( tstr, '(sp,f16.3)' ) hr_time(j)
      write( cyc, '(i6.6)' ) mod( hr_cycle(j), 1000000_int32 )
      xc = 0.5_dp*( real( hr_x(1:kmax,j), dp ) + real( hr_x(2:kmax+1,j), dp ) )
      v = real( hr_p(:,j), dp )
      base = trim(title)//'.mv_p_'//cyc
      bout = base
      call fresh( base//'.bmp' )
      call draw_profile( bout, kmax, xc, v, xlo, xhi, plo, phi, &
         'PRESSURE AT TIME = '//trim(adjustl(tstr))//' US' )
      call written( base//'.bmp', nerr )
   end do
   deallocate( xc, v )
   end subroutine movie_pictures

   !******************************************************************!
   ! plot_range = robust: the top of a color range, the largest value !
   ! the run HELD. fmax(j) is the largest value on the mesh in frame  !
   ! j, and each frame stands for the cycles around it (half of those !
   ! to each neighbor; frames need not be evenly spaced). The top is  !
   ! the highest level the frame maxima reach for at least nhold      !
   ! cycles in all: the largest L with                                !
   !    sum of the cycles of the frames with fmax >= L  >=  nhold,    !
   ! one of the fmax values, found by bisection (64 halvings, each a  !
   ! pass over the frames; no sort). A run of fewer than 2*nhold      !
   ! cycles keeps its max: too short to tell a spike from a state.    !
   !******************************************************************!
   function held_top( fmax ) result(top)
   implicit none
   real(kind=sp), intent(in) :: fmax(:)
   real(kind=sp) :: top
   real(kind=dp) :: w(size(fmax)), a, b, c
   integer(kind=int32) :: n, j, it

   n = size(fmax)
   top = maxval(fmax)
   if ( n < 2 ) return
   w(1) = half_gap( 1, 2 )
   w(n) = half_gap( n-1, n )
   do j = 2, n-1
      w(j) = half_gap( j-1, j ) + half_gap( j, j+1 )
   end do
   if ( sum(w) < real(2*nhold,dp) ) return
   ! held(a) >= nhold (a = the smallest frame max: every frame), and
   ! held(b) < nhold just above the largest; halve until they meet.
   a = real(minval(fmax),dp)
   b = real(top,dp)
   if ( held(b) >= real(nhold,dp) ) return     ! the max itself is held
   do it = 1, 64
      c = a + 0.5_dp*( b - a )
      if ( .not. ( c > a .and. c < b ) ) exit
      if ( held(c) >= real(nhold,dp) ) then
         a = c
      else
         b = c
      end if
   end do
   ! The frame max at or just above a: held for nhold cycles, and no
   ! frame max above it is.
   top = minval( fmax, mask = real(fmax,dp) >= a )

   contains

      real(kind=dp) function half_gap( j1, j2 )   ! half the cycles between
      integer(kind=int32), intent(in) :: j1, j2
      half_gap = 0.5_dp*real( hr_cycle(j2) - hr_cycle(j1), dp )
      end function half_gap

      real(kind=dp) function held( level )    ! cycles at or above level
      real(kind=dp), intent(in) :: level
      held = sum( w, mask = real(fmax,dp) >= level )
      end function held

   end function held_top

   !******************************************************************!
   ! What lies above a robust top: one screen line, how high (the     !
   ! run's max, where and when) and for how many cycles the mesh had  !
   ! something above the top. v is hr_u (at faces) or hr_p (cells).   !
   !******************************************************************!
   subroutine above( label, v, at_faces, top )
   implicit none
   character(len=*), intent(in) :: label
   real(kind=sp), intent(in) :: v(:,:), top
   logical, intent(in) :: at_faces
   integer(kind=int32) :: m(2), k, j, n
   real(kind=sp) :: x
   real(kind=dp) :: ncyc

   m = maxloc( v )
   k = m(1); j = m(2)
   if ( at_faces ) then
      x = hr_x(k,j)
   else
      x = 0.5_sp*( hr_x(k,j) + hr_x(k+1,j) )
   end if
   ! Cycles with something above the top: each frame above it stands
   ! for the cycles around it, as in held_top.
   n = hr_nframes
   ncyc = zero
   do j = 1, n
      if ( maxval(v(:,j)) > top ) then
         if ( j > 1 ) ncyc = ncyc + &
            0.5_dp*real( hr_cycle(j) - hr_cycle(j-1), dp )
         if ( j < n ) ncyc = ncyc + &
            0.5_dp*real( hr_cycle(j+1) - hr_cycle(j), dp )
      end if
   end do
   write( kpt6, fl ) label, 'up to '//num(v(m(1),m(2)))//' at t = '// &
      num(real(hr_time(m(2)),sp))//' us, x = '//num(x)//' mm; above for '// &
      'about '//itoa(nint(ncyc,int32))//' cycles; drawn in the top color'
   end subroutine above

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
   logical :: eof, bad, flat
   real(kind=dp) :: umin, umax, del
   real(kind=dp) :: ylo, yhi, step          ! the y axis (nice_ends)

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
   !*** min - 5% to max + 5% of the range, both rounded out to clean
   !*** ends (nice_ends, module strokes; draw_trace rounds the time
   !*** axis), which the plot prints at its corners. A flat line gets
   !*** +-5% of its value, at least +-0.05 km/s; flat means flat to
   !*** round-off (a range under 1e-9 of its values, as at an interface
   !*** whose u is steady, 0.5 km/s +- 1e-13), so the axis is never
   !*** stretched over round-off.
   !*** The pictures announced once; then one line per tracer, its
   !*** velocity range and the plot's y axis (the numbers at the plot's
   !*** left side; its own text names no axis or unit).
   write( kpt6, fl ) 'Tracer file', fname
   write( kpt6, fl ) 'Rows', itoa(nrow)//', t = '//fmt_real(t(1))// &
      ' to '//fmt_real(t(nrow))//' us'
   write( kpt6, fl ) 'Drawing tracer plots', itoa(ntrc)//', '// &
      trim(title)//'.tr_<tracer>.bmp'
   do it = 1, ntrc
      umin = minval(u(:,it)); umax = maxval(u(:,it))
      del  = 0.05_dp*( umax - umin )
      flat = .not. ( umax - umin > &
         1.0e-9_dp*max( abs(umin), abs(umax), one ) )
      if ( flat ) del = 0.05_dp*max( abs(umax), one )
      call nice_ends( umin - del, umax + del, ylo, yhi, step )
      write( kpt6, fl ) 'Tracer '//trim(tracer(it)%name)//' u (km/s)', &
         num(real(umin,sp))//' to '//num(real(umax,sp))//', y axis '// &
         num(real(ylo,sp))//' to '//num(real(yhi,sp))
      call trace_file( trim(title)//'.tr_'//trim(tracer(it)%name), t, &
         u(:,it), ylo, yhi, nerr )
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

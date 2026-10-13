program bitwhiz
!**********************************************************************!
!
!  Purpose:
!    bitwhiz, a one-dimensional Lagrangian hydrocode for the ME 697
!    class project. Usage:   bitwhiz <deck>
!
!    The run goes section by section, top to bottom:
!      0. Loading screen.            5. Initialization.
!      1. Read the command line.     6. Allocate the data arrays.
!      2. Read the input deck.       7. Begin the simulation.
!      3. Test OpenMP settings.      8. Close the heartbeat file.
!      4. Open the heartbeat file.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    03/24/25    D. E. Kittell        Original code; fork of bitmaths
!    10/13/26    D. E. Kittell        Colormap demo retired; the deck is
!                (with Claude)        read before OpenMP and heartbeat
!    10/13/26    D. E. Kittell        Banner shows version, build date,
!                (with Claude)        compiler and build type
!    10/13/26    D. E. Kittell        Hardening: deck path checked for
!                (with Claude)        length and blanks; time stamps
!                                     carry the time zone
!    10/13/26    D. E. Kittell        Run time from system_clock (wall)
!                (with Claude)        and cpu_time (all threads), shown
!                                     in a closing block; the old
!                                     timestamp lines are gone
!
!**********************************************************************!
use bits, only: dp,int32,int64,kpt6
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads, &
   thread_num,nalive,title,khb,hb_open,hb_file
use deck, only: read_deck,write_resolved_deck
use build, only: build_date,build_version       ! written by 'make'
use, intrinsic :: iso_fortran_env, only: compiler_version,compiler_options
!$ use omp_lib, only: omp_get_num_procs,omp_set_num_threads, &
!$    omp_get_num_threads,omp_get_thread_num
implicit none
integer(kind=int64) :: tick0,tick1     ! wall clock ticks, start and end
integer(kind=int64) :: rate             ! wall clock ticks per second
real(kind=dp) :: cpu0,cpu1              ! CPU seconds, start and end
integer(kind=int32) :: nargs            ! command line word count
integer(kind=int32) :: kerr             ! errors found in the deck
integer(kind=int32) :: ios              ! I/O status from open()
integer(kind=int32) :: nlen             ! full length of the deck path
character(len=256) :: deckname          ! the deck file, from the
                                        ! command line

202 format(1x,a)                        ! a plain line
203 format(3x,a,t40,': ',i6,2x,a)       ! label : integer  note
204 format(3x,a,t40,': ',a)             ! label : text
205 format(3x,a,t40,': ',i6)            ! label : integer
206 format(3x,a,t15,': ',a)             ! banner label : text
207 format(3x,a,t15,': ',f10.3,a)       ! banner label : seconds  note

!*** Start the clocks. Two different times are kept, because with
!*** OpenMP they tell different stories:
!***   wall clock - real time that passes, what you wait for. It comes
!***                from system_clock, a tick counter that does not
!***                care about midnight or the date.
!***   CPU time   - processor time spent, summed over ALL threads. With
!***                4 busy threads it grows about 4 times faster than
!***                the wall clock; CPU / (wall x threads) near 1 means
!***                the threads were kept busy.
call system_clock( tick0, rate )
call cpu_time( cpu0 )

! The colormap demo (draw_colormaps) is retired from the run. It stays
! in the build (src/drawings), and can still be called from here for a
! quick look at every colormap:   call draw_colormaps()

!====================!
! 0. Loading screen. !
!====================!
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) '       ---==>>    __    _ __           __    _'
write( kpt6, 202 ) '        --==>>   / /_  (_) /__      __/ /_  (_)___'
write( kpt6, 202 ) '         -==>>  / __ \/ / __/ | /| / / __ \/ /_  /'
write( kpt6, 202 ) '        --==>> / /_/ / / /_ | |/ |/ / / / / / / /_'
write( kpt6, 202 ) '       ---==>>/_.___/_/\__/ |__/|__/_/ /_/_/ /___/'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 202 ) '        a one-dimensional Lagrangian hydrocode'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 202 ) '   u |                         _______________________'
write( kpt6, 202 ) '     |                ________/    second shock'
write( kpt6, 202 ) '     |               /'
write( kpt6, 202 ) '     |   ___________/   first shock'
write( kpt6, 202 ) '     |__/____________________________________________ t'
write( kpt6, 202 ) repeat('-',56)
!*** Which code this is: the git version and build date come from
!*** src/modules/build_mod.f95, which 'make' writes on every build; the
!*** compiler and its options are recorded by the compiler itself.
write( kpt6, 206 ) 'version',   build_version()
write( kpt6, 206 ) 'built',     build_date()
write( kpt6, 206 ) 'compiler',  compiler_version()
write( kpt6, 206 ) 'build',     build_kind()
write( kpt6, 206 ) 'run start', clock()
write( kpt6, 202 ) repeat('=',56)

!=============================!
! 1. Read the command line.   !
!=============================!

! Usage:  bitwhiz <deck>
!
! The command line takes only the input deck's file name. Everything
! else about a run (threads, solver, materials, geometry, tracers,
! output) is in the deck, so the deck is the complete record of what
! was run (input/README.md).
nargs = command_argument_count()
if ( nargs == 0 ) call usage( 'no input deck given' )
call get_command_argument( 1, deckname, length=nlen )

! A path longer than deckname would be cut short without a word and
! could open the wrong file (or a folder), so it is refused instead.
if ( nlen > len(deckname) ) call usage( 'the deck path is longer '// &
   'than 256 characters; run from a folder closer to the deck' )
if ( len_trim(deckname) == 0 ) call usage( 'no input deck given' )
if ( deckname(1:1) == '-' ) then
   if ( trim(deckname) == '-np' ) then
      call usage( '-np is gone: set num_threads in the deck''s Run block' )
   else
      call usage( 'options like "'//trim(deckname)//'" are not used; '// &
         'give the deck file' )
   end if
end if
if ( nargs > 1 ) call usage( 'only one argument (the deck) is allowed' )

!=========================!
! 2. Read the input deck. !
!=========================!

! The deck reader (module deck, src/modules/deck_mod.f95) checks every
! line against input/README.md and fills the input tables in the shock
! module. It lists ALL the problems it finds before giving up, each
! with the deck's file name and line number, so one run shows every
! mistake. If the deck is clean, the "resolved deck" is printed: the
! same run with every default filled in and every define substituted.
! It is the record of what this run actually used, and reading it
! back in gives exactly the same run.
call read_deck( trim(deckname), kerr )
if ( kerr > 0 ) then
   write( kpt6, 202 ) repeat('-',56)
   write( kpt6, '(1x,i0,a)' ) kerr, ' error(s) in the input deck; stopping.'
   stop 1, quiet=.true.                 ! exit status 1, no "STOP 1" line
end if
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 2. Input deck: '//trim(deckname)
write( kpt6, 202 ) repeat('=',56)
call write_resolved_deck( int(kpt6) )

!===================================!
! 3. Test OpenMP settings, if used. !
!===================================!

! Every line that starts with !$ is compiled ONLY with -fopenmp. In a
! serial build they are comments, the shock module defaults describe
! one thread, and this section still prints a sensible report.

!*** Ask the system how many processors there are, and never ask for
!*** more threads than that (oversubscribing is very slow, see
!*** NOTES_bitwhiz_Performance_IO_v1.md section 2).
!$ omp_on    = .true.
!$ num_procs = omp_get_num_procs()
!*** num_threads = 0 in the deck means "use every processor".
if ( nproc == 0 ) then
   max_threads = num_procs
else
   max_threads = min( nproc, num_procs )
end if
!$ call omp_set_num_threads( max_threads )

!*** Open a real parallel region and count who shows up. Each thread
!*** adds 1 to its own copy of nalive, and REDUCTION(+) sums the
!*** copies at the end. SINGLE lets exactly one thread record what
!*** OpenMP says about the team. (OMP_get_num_threads() only reports
!*** the team size from INSIDE a parallel region; outside, it is 1.)
nalive = 0
!$OMP PARALLEL DEFAULT(SHARED) REDUCTION(+:nalive)
nalive = nalive + 1
!$OMP SINGLE
!$ num_threads = omp_get_num_threads()
!$ thread_num  = omp_get_thread_num()
!$OMP END SINGLE
!$OMP END PARALLEL

!*** Report.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 3. OpenMP settings'
write( kpt6, 202 ) repeat('-',56)
if ( omp_on ) then
   write( kpt6, 204 ) 'OpenMP compiled in', 'yes'
else
   write( kpt6, 204 ) 'OpenMP compiled in', 'no (serial build)'
end if
if ( nproc == 0 ) then
   write( kpt6, 204 ) 'Threads requested (deck)', '     0  (all processors)'
else
   write( kpt6, 205 ) 'Threads requested (deck)', nproc
end if
if ( omp_on ) then
   write( kpt6, 205 ) 'Processors available', num_procs
else
   write( kpt6, 204 ) 'Processors available', '(not asked: serial)'
end if
if ( nproc > num_procs .and. omp_on ) then
   write( kpt6, 203 ) 'Threads in the team', max_threads, &
      '(capped at processors)'
else if ( nproc /= 1 .and. .not. omp_on ) then
   write( kpt6, 203 ) 'Threads in the team', max_threads, &
      '(serial build: 1 thread)'
else
   write( kpt6, 205 ) 'Threads in the team', max_threads
end if
write( kpt6, 205 ) 'Team size seen inside region', num_threads
write( kpt6, 205 ) 'Threads that reported in', nalive
write( kpt6, 205 ) 'SINGLE block ran on thread', thread_num
if ( nalive /= max_threads ) then
   write( kpt6, 202 ) repeat('-',56)
   write( kpt6, 202 ) '  WARNING: fewer threads reported in than were'
   write( kpt6, 202 ) '  requested (check OMP_THREAD_LIMIT / OMP_DYNAMIC).'
end if
write( kpt6, 202 ) repeat('=',56)

!==============================!
! 4. Open the heartbeat file.  !
!==============================!

! The heartbeat gets one line per cycle from section 7, so a long run
! can be watched from another terminal with
!
!     tail -f <title>.heartbeat
!
! It is named after the deck's title (which defaults to the deck's
! file name), so runs with different titles in the same folder keep
! their own heartbeats. 'replace' starts a fresh file every run.
hb_file = trim(title)//'.heartbeat'
open( newunit=khb, file=trim(hb_file), status='replace', &
      action='write', iostat=ios )
if ( ios /= 0 ) then
   write( kpt6, 202 ) 'bitwhiz: cannot open the heartbeat file '// &
      trim(hb_file)
   stop 1, quiet=.true.
end if
hb_open = .true.

!*** Header: where the run came from, then one name per column. The
!*** cycle lines that section 7 writes line up under these names.
write( khb, '(a)' ) '# bitwhiz heartbeat'
write( khb, '(a)' ) '# deck    : '//trim(deckname)
write( khb, '(a)' ) '# title   : '//trim(title)
write( khb, '(a)' ) '# started : '//clock()
write( khb, '(a)' ) '# version : '//build_version()
write( khb, '(a)' ) '# built   : '//build_date()//', '//compiler_version()
write( khb, '(a)' ) '# flags   : '//compiler_options()
write( khb, '(a)' ) '# units   : us, GPa; errors are relative to t = 0'
write( khb, '(a)' ) '#   cycle      t (us)     dt (us)  dt cell'// &
   '   max P (GPa)    mass err  energy err   x-momentum   wall (s)'
flush( khb )                            ! so tail -f sees it now

write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 4. Heartbeat'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 204 ) 'Heartbeat file', trim(hb_file)
write( kpt6, 202 ) repeat('=',56)

!====================!
! 5. Initialization. !
!====================!

! TODO / includes time zero and cycle zero

!==============================!
! 6. Allocate the data arrays. !
!==============================!

! TODO / hints:
!*****************************************!
! FORTRAN ARRAY INDEX SUMMARY
! differs from numerical method idex, "k"
!
! i= 1   2   3   4   5      imax-1 imax
!  +---+---+---+---+---+-   -+---+---+
!  | G | F | C | F | C | ... | F | G |
!  +---+---+---+---+---+-   -+---+---+
!      even odd              even odd
!
!  G = Ghost Cell
!  F = Face
!  C = Center
!*****************************************!

!==========================!
! 7. Begin the simulation. !
!==========================!

! TODO / hints (equation sheet Steps 1-2; slots and rules: shock_mod)
!
! Cells are odd i = 3, 5, ..., imax-2 and faces are even i = 2, ...,
! imax-1. Every loop copies a private chunk of the database, works on
! the chunk, and writes back ONLY the slots it changed (the write-back
! rule in shock_mod keeps neighboring threads from tripping over each
! other). The hint directives are written !!$OMP so they stay comments
! in an -fopenmp build; drop one "!" when a loop is real.
!
!loop_on_cycles: do while ( running )
!
!   !*** FACE loop: momentum and position (Step 1).
!   !!$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,chunk)
!   !do i = 2, imax-1, 2
!   !   chunk = database(:,i-ns:i+ns)
!   !   call face_update( chunk, ... )
!   !   database(ju,i) = chunk(ju,0)          ! only what changed
!   !   database(jx,i) = chunk(jx,0)
!   !end do
!   !!$OMP END PARALLEL DO
!
!   !*** CELL loop: density, energy, EOS, sound speed, q (Step 2).
!   !!$OMP PARALLEL DO DEFAULT(SHARED) PRIVATE(i,chunk)
!   !do i = 3, imax-2, 2
!   !   chunk = database(:,i-ns:i+ns)
!   !   call cell_update( chunk, ... )
!   !   database(jrho,i) = chunk(jrho,0)      ! only what changed
!   !   database(je,i)   = chunk(je,0)
!   !   ...
!   !end do
!   !!$OMP END PARALLEL DO
!
!   !*** Time step: a cell loop with REDUCTION(MIN:dtmin) for the CFL
!   !*** limit, and the first tensile cell (flag it, set P = 0).
!
!   ! One heartbeat line for this cycle: write( khb, ... ), then flush.
!
!   ! Conditions to write tracers and snapshots (Output block).
!
!   ! Conditions to end the simulation: t >= t_end or cycle = cycle_max.
!
!end do loop_on_cycles

!===============================!
! 8. Close the heartbeat file.  !
!===============================!
call close_heartbeat( 'normal end' )

!=================================!
! End of run: how long it took.   !
!=================================!

! Same layout as the banner, so a run's screen output opens and closes
! the same way. (See the start of the program for wall vs. CPU time.)
call system_clock( tick1 )
call cpu_time( cpu1 )
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 206 ) 'run end',    clock()
write( kpt6, 207 ) 'wall clock', real(tick1-tick0,dp)/real(rate,dp), ' s'
write( kpt6, 207 ) 'CPU time',   cpu1-cpu0, ' s (all threads)'
write( kpt6, 202 ) repeat('=',56)

contains

   !*****************************************************!
   ! Print what went wrong on the command line, how to   !
   ! run the code, and stop with a nonzero exit status.  !
   ! (STOP, not ERROR STOP: a typo on the command line   !
   ! is the user's slip, not a crash, so no backtrace.)  !
   !*****************************************************!
   subroutine usage( msg )
   use, intrinsic :: iso_fortran_env, only: error_unit
   implicit none
   character(len=*), intent(in) :: msg
   write( error_unit, '(a)' ) ' bitwhiz: '//msg
   write( error_unit, '(a)' ) ' usage:   bitwhiz <deck>'
   write( error_unit, '(a)' ) '          e.g. bitwhiz input/'// &
      'me697_double_shock_2p00.deck'
   stop 1, quiet=.true.
   end subroutine usage

   !*****************************************************!
   ! A one-line summary of how this executable was       !
   ! compiled, from the compiler's own record of its     !
   ! options, e.g. "debug (-O0, -fcheck), OpenMP".       !
   ! "debug" means unoptimized or with run-time checks.  !
   !*****************************************************!
   function build_kind() result(s)
   implicit none
   character(len=:), allocatable :: s, opts, olevel
   logical :: checks, openmp
   integer(kind=int32) :: k

   opts = ' '//compiler_options()//' '

   ! Optimization level: the last -O option wins, as in gfortran.
   olevel = '-O0'
   k = index(opts, ' -O', back=.true.)
   if ( k > 0 ) olevel = opts(k+1:k-1+index(opts(k+1:), ' '))

   checks = ( index(opts, ' -fcheck') > 0 )
   openmp = .false.
   !$ openmp = .true.

   if ( olevel == '-O0' .or. olevel == '-Og' .or. checks ) then
      s = 'debug ('//olevel
   else
      s = 'optimized ('//olevel
   end if
   if ( checks ) s = s//', -fcheck'
   s = s//')'
   if ( openmp ) then
      s = s//', OpenMP'
   else
      s = s//', serial'
   end if
   end function build_kind

   !*****************************************************!
   ! Write the last line of the heartbeat and close it.  !
   ! Every way out of a run after section 4 should come  !
   ! through here, with a word on how the run ended      !
   ! ('normal end', or the reason for stopping), so the  !
   ! heartbeat never just stops without saying why.      !
   !*****************************************************!
   subroutine close_heartbeat( how )
   implicit none
   character(len=*), intent(in) :: how
   if ( .not. hb_open ) return
   write( khb, '(a)' ) '# ended   : '//clock()//'  ('//how//')'
   close( khb )
   hb_open = .false.
   end subroutine close_heartbeat

   !*****************************************************!
   ! The date, time and time zone as text, for the       !
   ! banner and the heartbeat:                           !
   !     "2026-10-13 21:41:07 -0400"                     !
   ! The zone keeps runs on different machines (laptop,  !
   ! cluster) comparable.                                !
   !*****************************************************!
   function clock() result(stamp)
   implicit none
   character(len=25) :: stamp
   character(len=8)  :: ymd
   character(len=10) :: hms
   character(len=5)  :: zone
   call date_and_time( ymd, hms, zone )
   stamp = ymd(1:4)//'-'//ymd(5:6)//'-'//ymd(7:8)//' '// &
           hms(1:2)//':'//hms(3:4)//':'//hms(5:6)//' '//zone
   end function clock

end program bitwhiz

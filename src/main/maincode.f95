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
!
!**********************************************************************!
use bits, only: dp,int32,kpt6
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads, &
   thread_num,nalive,title,khb,hb_open,hb_file
use deck, only: read_deck,write_resolved_deck
!$ use omp_lib, only: omp_get_num_procs,omp_set_num_threads, &
!$    omp_get_num_threads,omp_get_thread_num
implicit none
real(kind=dp) :: cpu1,cpu2              ! wall clock at start and end
integer(kind=int32) :: nargs            ! command line word count
integer(kind=int32) :: kerr             ! errors found in the deck
integer(kind=int32) :: ios              ! I/O status from open()
character(len=256) :: deckname          ! the deck file, from the
                                        ! command line

201 format("CPU Elapsed Time = ",1(1f15.3)," seconds")
202 format(1x,a)                        ! a plain line
203 format(3x,a,t40,': ',i6,2x,a)       ! label : integer  note
204 format(3x,a,t40,': ',a)             ! label : text
205 format(3x,a,t40,': ',i6)            ! label : integer

call timestamp( cpu1 ) !~ save for reference.

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
write( kpt6, 202 ) '   "It will not work the first time.'
write( kpt6, 202 ) '    That is the assignment."                  -- ME 697'
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
call get_command_argument( 1, deckname )
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
if ( hb_open ) then
   write( khb, '(a)' ) '# ended   : '//clock()//'  (normal end)'
   close( khb )
   hb_open = .false.
end if

!=======================================!
! Compute CPU time and write to screen. !
!=======================================!
call timestamp( cpu2 )

write( kpt6, 201 ) cpu2-cpu1

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
   ! The date and time as text, "2026-10-13 21:41:07",   !
   ! for the heartbeat (and later the run log).          !
   !*****************************************************!
   function clock() result(stamp)
   implicit none
   character(len=19) :: stamp
   character(len=8)  :: ymd
   character(len=10) :: hms
   call date_and_time( ymd, hms )
   stamp = ymd(1:4)//'-'//ymd(5:6)//'-'//ymd(7:8)//' '// &
           hms(1:2)//':'//hms(3:4)//':'//hms(5:6)
   end function clock

end program bitwhiz

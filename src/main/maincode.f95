program bitwhiz
use bits, only: dp,int32,kpt6
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads, &
   thread_num,nalive
use deck, only: read_deck,write_resolved_deck
!$ use omp_lib, only: omp_get_num_procs,omp_set_num_threads, &
!$    omp_get_num_threads,omp_get_thread_num
implicit none
real(kind=dp) :: cpu1,cpu2
character(len=80) :: cmap
integer(kind=int32) :: nargs            ! command line word count
integer(kind=int32) :: kerr             ! errors found in the deck
character(len=256) :: deckname          ! the deck file, from the
                                        ! command line
cmap = ' ' ! default

201 format("CPU Elapsed Time = ",1(1f15.3)," seconds")
202 format(1x,a)                        ! a plain line
203 format(3x,a,t40,': ',i6,2x,a)       ! label : integer  note
204 format(3x,a,t40,': ',a)             ! label : text
205 format(3x,a,t40,': ',i6)            ! label : integer

call timestamp( cpu1 ) !~ save for reference.

! Testing, testing, 1, 2, 3... 
!call draw_colormaps() ! whack this, eventually

!====================!
! 0. Loading screen. !
!====================!

! TODO / something cool to look at on the terminal

!====================================!
! 1. Read execution line parameters. !
!====================================!

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

!====================!
! 2. Initialization. !
!====================!

! TODO / includes time zero and cycle zero

!===========================!
! 3. Open a heartbeat file. !
!===========================!

! TODO / called 'heartbeat' updated every cycle

!=========================!
! 4. Read the input deck. !
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
write( kpt6, 202 ) ' 4. Input deck: '//trim(deckname)
write( kpt6, 202 ) repeat('=',56)
call write_resolved_deck( int(kpt6) )

!===================================!
! 5. Test OpenMP settings, if used. !
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
write( kpt6, 202 ) ' 5. OpenMP settings'
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
else if ( nproc /= 1 ) then
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

! TODO / hints:
!loop_on_cycles: do while (running)
! ...
   !***NOTE: the hint directives below are written !!$OMP so that they
   ! stay comments in an -fopenmp build. A live !$OMP PARALLEL with no
   ! loop under it would not compile. Drop one "!" when the loop is real.
   !********************************************!
   ! If needed, FORWARD TIME INTEGRATION of all
   ! CELL-CENTERED VARIABLES goes like this:
   !!$OMP PARALLEL DEFAULT(SHARED) PRIVATE(slice)
   !!$OMP DO
   !do i=3,imax-2,2
   !   slice(1,:) = database(i,:)
   !   call my_fcn( slice, ... )
   !   database(i,:) = slice(1,:)
   !end do
   !!$OMP END DO
   !!$OMP END PARALLEL
   !********************************************!
! ...
   !********************************************!
   ! If needed, RIEMANN PROBLEM solution of all
   ! FACE-CENTERED VARIABLES goes like this:
   !!$OMP PARALLEL DEFAULT(SHARED) PRIVATE(chunk)
   !!$OMP DO
   !do i=2,imax-1,2
   !   chunk(1:3,:) = database(i-1:i+1,:)
   !   call my_fcn( chunk, ... )
   !   database(i,:) = chunk(2,:)
   !end do
   !!$OMP END DO
   !!$OMP END PARALLEL
   !********************************************!
! ...
   !********************************************!
   ! If needed, THERMODYNAMIC UPDATE using LEFT
   ! and RIGHT cell centers goes like this:
   !!$OMP PARALLEL DEFAULT(SHARED) PRIVATE(chunk)
   !!$OMP DO
   !do i=3,imax-2,2
   !   chunk(1:3,:) = database(i-1:i+1,:)
   !   call my_fcn( chunk, ... )
   !   database(i,:) = chunk(2,:)
   !end do
   !!$OMP END DO
   !!$OMP END PARALLEL
   !********************************************!
! ...

   ! Conditions to dump the database.

! ...

   ! Conditions to make bitwhiz images on-the-fly.

! ...

   ! Conditions to end the simulation.

! ...

!end do loop_on_cycles

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

end program bitwhiz

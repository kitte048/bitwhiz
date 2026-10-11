program bitwhiz
use bits, only: dp,int32,kpt6
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads, &
   thread_num,nalive
!$ use omp_lib, only: omp_get_num_procs,omp_set_num_threads, &
!$    omp_get_num_threads,omp_get_thread_num
implicit none
real(kind=dp) :: cpu1,cpu2
character(len=80) :: cmap
integer(kind=int32) :: nargs,iarg       ! command line bookkeeping
character(len=32) :: arg,val            ! one command line word
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

! Usage:  bitwhiz [-np N]
!
!   -np N   number of OpenMP threads to use (default 1). It is capped
!           at the number of processors in section 4.
!
! The input deck will add '-i deck' here later; for now -np is the
! only option. Anything else stops the run with a short message.
nargs = command_argument_count()
iarg = 1
read_args: do while ( iarg <= nargs )
   call get_command_argument( iarg, arg )
   select case ( trim(arg) )
   case ( '-np' )
      if ( iarg == nargs ) call usage( '-np needs a number, e.g. -np 4' )
      call get_command_argument( iarg+1, val )
      ! Digits only, so "4" passes but "4.0", "-2", "/" and "four"
      ! do not (a bare read would quietly accept some of those).
      if ( len_trim(val) == 0 .or. len_trim(val) > 6 .or. &
           verify(trim(val),'0123456789') /= 0 ) &
         call usage( '-np "'//trim(val)//'" is not a positive whole number' )
      read( val, * ) nproc
      if ( nproc < 1 ) call usage( '-np must be at least 1' )
      iarg = iarg + 2
   case default
      call usage( 'unknown argument "'//trim(arg)//'"' )
   end select
end do read_args

!====================!
! 2. Initialization. !
!====================!

! TODO / includes time zero and cycle zero

!===========================!
! 3. Open a heartbeat file. !
!===========================!

! TODO / called 'heartbeat' updated every cycle

!===================================!
! 4. Test OpenMP settings, if used. !
!===================================!

! Every line that starts with !$ is compiled ONLY with -fopenmp. In a
! serial build they are comments, the shock module defaults describe
! one thread, and this section still prints a sensible report.

!*** Ask the system how many processors there are, and never ask for
!*** more threads than that (oversubscribing is very slow, see
!*** NOTES_bitwhiz_Performance_IO_v1.md section 2).
!$ omp_on    = .true.
!$ num_procs = omp_get_num_procs()
max_threads = min( nproc, num_procs )
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
write( kpt6, 202 ) ' 4. OpenMP settings'
write( kpt6, 202 ) repeat('-',56)
if ( omp_on ) then
   write( kpt6, 204 ) 'OpenMP compiled in', 'yes'
else
   write( kpt6, 204 ) 'OpenMP compiled in', 'no (serial build)'
end if
write( kpt6, 205 ) 'Threads requested (-np)', nproc
if ( omp_on ) then
   write( kpt6, 205 ) 'Processors available', num_procs
else
   write( kpt6, 204 ) 'Processors available', '(not asked: serial)'
end if
if ( nproc > num_procs .and. omp_on ) then
   write( kpt6, 203 ) 'Threads in the team', max_threads, &
      '(capped at processors)'
else if ( nproc > num_procs ) then
   write( kpt6, 203 ) 'Threads in the team', max_threads, &
      '(-np ignored: serial)'
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

!=========================!
! 5. Read the input deck. !
!=========================!

! TODO / hints:
! example input deck that I'd like to parse
!
!         FORMAT STYLE SUGGESTION
!
!*****************************************!
!Begin bitwhiz
! # by default hash is for comment lines.
!
! Begin Solver
!  Method = AV # choose AV or ???
! 
!  # other settings, like
!  BL=0.3
!  BQ=2.2
!
! # maybe the safety factor of 0.6 in CFL
! # should be exposed, as well as the final
! # simulation time?
!
! End Solver
!
! Begin Stack
!  # materials load up from left to right
!  # along the x-axis. Place x=0 at the start of
!  # the first layer to be inserted.
!
!  Begin New_Layer
!   width=4.5 # default units are mm (double-check) REQUIRED
!   xvel=1.55 # initial velocity in mm/us applied
!             # uniformly across zones OPTIONAL (=0 if absent)
!  # one of the following MUST be specified. If both
!  # are specified, use requested number of zones.
!   resolution=15.  # zones per millimeter REQUIRED if no zones
!   zones=600       # this is REQUIRED if no resolution
!   R0=1.65    # grams per cc
!   C0=4.5     # mm/us
!   S1=1.3     # [-]
!   G0=1.1     # [-]
!  End New_Layer
!
!  Begin New_Layer
!   width=5.0
!   zones=100
!   R0=2.7
!   C0=3.0
!   S1=1.2
!   G1=1.0
!  End New_Layer
!
!  Begin New_Layer
!   width=7.0
!   zones=200
!   R0=2.7
!   C0=3.0
!   S1=1.1
!   G1=1.2
!  End New_Layer
!
! End Stack
!
!End bitwhiz
!*****************************************!
! Notes: the parser should be able to trap
!        and identify the following:
!
!#param=12.0 #nothing
!param=12.0# something
!param = 12E+10
!    param=12.0e10
!param =-1.234
!param=1
!param   = -3.1415e-9
!param   = +3.1415e9
!param= +3.1415E-12#this one is very small
!param = "cat" # oops
!param=220.9
!param = +-99 #bogus
!param = -+99.8 #bogus
!param = 2323cv5#bogus
!param = 23..67#bogus
!param = 23.1.5e5 #bogus
!param=77.5e+5
!param=77.5e+-5 #bogus
!param=12345
!param=2.22e11e11 #bogus
!
!  AND
!
!Harden against line return characters.
!*****************************************!

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
   ! (STOP 1, not ERROR STOP: a typo on the command line !
   ! is the user's slip, not a crash, so no backtrace.)  !
   !*****************************************************!
   subroutine usage( msg )
   use, intrinsic :: iso_fortran_env, only: error_unit
   implicit none
   character(len=*), intent(in) :: msg
   write( error_unit, '(a)' ) ' bitwhiz: '//msg
   write( error_unit, '(a)' ) ' usage:   bitwhiz [-np N]'
   write( error_unit, '(a)' ) '          N = OpenMP threads (default 1)'
   stop 1
   end subroutine usage

end program bitwhiz

program bitwhiz
use bits, only: dp,kpt6
implicit none
real(kind=dp) :: cpu1,cpu2
character(len=80) :: cmap
cmap = ' ' ! default

201 format("CPU Elapsed Time = ",1(1f15.3)," seconds")

call timestamp( cpu1 ) !~ save for reference.

! Testing, testing, 1, 2, 3... 
call draw_colormaps() ! whack this, eventually

!====================!
! 0. Loading screen. !
!====================!

! TODO / something cool to look at on the terminal

!====================================!
! 1. Read execution line parameters. !
!====================================!

! TODO / includes -i 'input deck' and -np 'nproc'

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

! TODO / hints:
!$ max_threads = OMP_get_num_procs()
!$ max_threads = min(max_threads,nproc)
!$ call OMP_set_num_threads(max_threads)
!$OMP SINGLE
!$ num_threads = OMP_get_num_threads()
!$ max_threads = OMP_get_max_threads()
!$ thread_num  = OMP_get_thread_num()
!$ num_procs   = OMP_get_num_procs()
!write(*,*) "Retrieving OpenMP parallel settings"
!write(*,*) " Inside OMP SINGLE / END SINGLE:"
!write(*,*) "  OMP_get_num_threads(): ",num_threads
!write(*,*) "  OMP_get_max_threads(): ",max_threads
!write(*,*) "  OMP_get_thread_num():  ",thread_num
!write(*,*) "  OMP_get_num_procs():   ",num_procs
!$OMP END SINGLE

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
   !********************************************!
   ! If needed, FORWARD TIME INTEGRATION of all
   ! CELL-CENTERED VARIABLES goes like this:
   !$OMP PARALLEL DEFAULT(SHARED) PRIVATE(slice)
   !$OMP DO
   !do i=3,imax-2,2
   !   slice(1,:) = database(i,:)
   !   call my_fcn( slice, ... )
   !   database(i,:) = slice(1,:)
   !end do
   !$OMP END DO
   !$OMP END PARALLEL
   !********************************************!
! ...
   !********************************************!
   ! If needed, RIEMANN PROBLEM solution of all
   ! FACE-CENTERED VARIABLES goes like this:
   !$OMP PARALLEL DEFAULT(SHARED) PRIVATE(chunk)
   !$OMP DO
   !do i=2,imax-1,2
   !   chunk(1:3,:) = database(i-1:i+1,:)
   !   call my_fcn( chunk, ... )
   !   database(i,:) = chunk(2,:)
   !end do
   !$OMP END DO
   !$OMP END PARALLEL
   !********************************************!
! ...
   !********************************************!
   ! If needed, THERMODYNAMIC UPDATE using LEFT
   ! and RIGHT cell centers goes like this:
   !$OMP PARALLEL DEFAULT(SHARED) PRIVATE(chunk)
   !$OMP DO
   !do i=3,imax-2,2
   !   chunk(1:3,:) = database(i-1:i+1,:)
   !   call my_fcn( chunk, ... )
   !   database(i,:) = chunk(2,:)
   !end do
   !$OMP END DO
   !$OMP END PARALLEL
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

end program bitwhiz

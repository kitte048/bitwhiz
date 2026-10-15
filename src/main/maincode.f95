program bitwhiz
!**********************************************************************!
!
!  Purpose:
!    bitwhiz, a one-dimensional Lagrangian hydrocode for the ME 697
!    class project. Usage:   bitwhiz <deck>
!
!    The run goes section by section, top to bottom:
!      0. Loading screen.            5. Allocate the data arrays.
!      1. Read the command line.     6. Initialization (t = 0).
!      2. Read the input deck.       7. Begin the simulation.
!      3. Test OpenMP settings.      8. Close the heartbeat file,
!      4. Open the heartbeat file.      free the memory.
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
!    10/14/26    D. E. Kittell        Sections 5 and 6 swapped. 5 sizes
!                (with Claude)        and fills the database (t = 0
!                                     state, mass-weighted impact face);
!                                     6 starts the clock, audits the
!                                     setup, records the t = 0 totals
!    10/14/26    D. E. Kittell        P and c at t = 0 from the EOS
!                (with Claude)        (module eos), checked in the audit
!    10/15/26    D. E. Kittell        Section 7: the time loop (module
!                (with Claude)        av), OpenMP style 2, heartbeat
!                                     line every cycle; first dt in 6
!
!**********************************************************************!
use bits, only: dp,int32,int64,kpt6,zero,half,one
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads, &
   thread_num,nalive,title,khb,hb_open,hb_file, &
   kmax,imax,nvar,nlay,layer,database,ilay,icell,iface, &
   jx,ju,jx_old,ju_old,jmf,jm,jrho,je,jp,jq,jc,jrho_old,je_old, &
   jr0,jc0,js1,js2,jg0,face_slots,cell_slots,dbname,not_finite, &
   kcell,t_end,cycle_max,CFL,BL,BQ,omp_min_zones, &
   alloc_database,dealloc_database,dealloc_layers, &
   dealloc_materials,dealloc_tracers
use deck, only: read_deck,write_resolved_deck
use eos, only: mg_eos,eos_message,eos_ok
use av, only: face_step,cell_step,cell_state,cell_dt
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
!*** Setup (sections 5 and 6). All local: see the RULE in bit_mod.
integer(kind=int32) :: i,j,k            ! database index, counter, cell
integer(kind=int32) :: l,ll,lr          ! layer; layers left/right of a face
integer(kind=int32) :: nz               ! zones in one layer
integer(kind=int32) :: nimpact          ! impact faces found
integer(kind=int32) :: nbad             ! setup checks that failed
integer(kind=int32) :: ierr             ! status from the EOS
integer(kind=int32) :: neos,ieos        ! EOS failures at setup, last status
integer(kind=int32) :: ncycle           ! cycle number, n
real(kind=dp) :: time                   ! problem time, us
real(kind=dp) :: ml,mr                  ! cell masses left/right of a face
real(kind=dp) :: ubar                   ! cell-average velocity, km/s
real(kind=dp) :: mass0,xmom0,etot0      ! t = 0 totals (per unit area)
real(kind=dp) :: mdeck,pdeck            ! the same, straight from the deck
real(kind=dp) :: tol                    ! round-off allowance, relative
character(len=16) :: buf                ! scratch text for a number
!*** The time loop (section 7). All local; the ones a thread changes
!*** are PRIVATE in the parallel region.
real(kind=dp) :: dt                     ! us, this cycle's step, dt(n)
real(kind=dp) :: dt_prev                ! us, last cycle's step, dt(n-1)
real(kind=dp) :: dth                    ! us, (dt_prev + dt)/2, for u
real(kind=dp) :: dt_used                ! us, the step just taken
real(kind=dp) :: dtcfl                  ! us, smallest cell dt_k
real(kind=dp) :: dtl                    ! us, one thread's smallest dt_k
real(kind=dp) :: dtk                    ! us, one cell's dt_k
real(kind=dp) :: unew,xnew              ! a face's new u and x
real(kind=dp) :: rnew,enew              ! a cell's new rho and e
real(kind=dp) :: pnew,cnew,qnew         ! a cell's new P, c and q
real(kind=dp) :: pmax                   ! GPa, largest P this cycle
real(kind=dp) :: tnext                  ! us, next screen progress line
real(kind=dp) :: merr,eerr,xmom         ! heartbeat: errors, momentum
real(kind=dp) :: tens_time,tens_x       ! first tensile cell: t, x
integer(kind=int32) :: kdt,kdt_used     ! cell that set dt (0 = t_end)
integer(kind=int32) :: kl               ! one thread's dt cell
integer(kind=int32) :: ktens,kbad       ! first tensile / EOS-failed cell
integer(kind=int32) :: tens_k           ! first tensile cell, 0 = none
integer(kind=int32) :: tens_cycle       ! ... and its cycle
integer(kind=int32) :: nloop            ! threads in the time loop
logical :: last                         ! this step lands on t_end
logical :: use_team                     ! kmax >= omp_min_zones
logical :: tens                         ! a cell's P was floored (tension)
logical :: isvoid                       ! a cell was treated as void
integer(kind=int32) :: kvoid,nvoid      ! first void cell, void count
integer(kind=int32) :: void_k,void_cycle ! first void cell ever, its cycle
integer(kind=int32) :: nvoid_max        ! most void cells at one time
real(kind=dp) :: void_time              ! us, when the first one appeared
logical :: done                         ! leave the time loop
logical :: stopped                      ! left at cycle_max, not t_end
character(len=64) :: endhow             ! how the run ended (heartbeat)

202 format(1x,a)                        ! a plain line
203 format(3x,a,t40,': ',i8,2x,a)       ! label : integer  note
204 format(3x,a,t40,': ',a)             ! label : text
205 format(3x,a,t40,': ',i8)            ! label : integer
206 format(3x,a,t15,': ',a)             ! banner label : text
207 format(3x,a,t15,': ',f10.3,a)       ! banner label : seconds  note
208 format(3x,a10,i9,es11.4,f13.6,f10.4) ! layer table row
209 format(3x,a,f10.6,a)                ! label number unit
210 format(5x,a,f8.4,a,f8.4,a,f8.4)     ! impact face velocities
211 format(3x,a,t40,': ',es15.8)        ! label : real
212 format(3x,a,t40,': ',i0,' (',a,'), t =',f9.4,' us') ! tensile event

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
   write( kpt6, 204 ) 'Threads requested (deck)', '       0  (all processors)'
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

!*** Header: where the run came from. Section 6 adds the t = 0
!*** totals and then the column names; the cycle lines that section 7
!*** writes line up under those names.
write( khb, '(a)' ) '# bitwhiz heartbeat'
write( khb, '(a)' ) '# deck    : '//trim(deckname)
write( khb, '(a)' ) '# title   : '//trim(title)
write( khb, '(a)' ) '# started : '//clock()
write( khb, '(a)' ) '# version : '//build_version()
write( khb, '(a)' ) '# built   : '//build_date()//', '//compiler_version()
write( khb, '(a)' ) '# flags   : '//compiler_options()
write( khb, '(a)' ) '# units   : us, GPa; errors are relative to t = 0'
flush( khb )                            ! so tail -f sees it now

write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 4. Heartbeat'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 204 ) 'Heartbeat file', trim(hb_file)
write( kpt6, 202 ) repeat('=',56)

!==============================!
! 5. Allocate the data arrays. !
!==============================!

! The deck reader has already done the zone bookkeeping. Each layer
! knows its zone count, its first and last cell (kfirst, klast), the
! x of its left face (xleft, after the origin shift) and its own copy
! of the material constants; kmax is the total. Here the database is
! sized to fit and every face and cell gets the t = 0 state of
! equation sheet Step 0.
!
! These are plain serial loops, on purpose. They run once: about a
! millisecond for the class problem, under a second for a million
! cells in the debug build. The chunk-and-write-back machinery
! (shock_mod) is for the time loop, not for setup.
!
! FORTRAN ARRAY INDEX SUMMARY (shock_mod has the full picture)
!
!  i= 1   2   3   4   5      imax-1 imax
!   +---+---+---+---+---+-   -+---+---+
!   | G | F | C | F | C | ... | F | G |
!   +---+---+---+---+---+-   -+---+---+
!
!   cell k     at  i = icell(k) = 2k+1    (ghosts are k = 0, kmax+1)
!   face k+1/2 at  i = iface(k) = 2k+2    (k = 0 .. kmax)
!
! alloc_database first fills EVERY slot with a signaling NaN, so a
! slot that the loops below forget to set stops the run the first
! time any arithmetic touches it, instead of quietly reading as zero.
! Section 6 checks that every slot that should be set, was.
call alloc_database( kmax, kerr )
if ( kerr > 0 ) then
   write( kpt6, 202 ) 'bitwhiz: cannot allocate the database '// &
      '(out of memory?)'
   call close_heartbeat( 'could not allocate the database' )
   stop 1, quiet=.true.
end if

!*** 5a. Face positions, layer by layer. Faces are evenly spaced
!*** inside a layer, and the layer's left face sits exactly at xleft,
!*** so every material interface lands on a face (Step 0). Face j of
!*** a layer is written as xleft + width*(j/nz), not by adding dx over
!*** and over, so round-off cannot pile up across a layer.
!***
!*** ilay on a face: a face between two layers belongs to the layer
!*** on its LEFT (shock_mod). The very first face has only void on its
!*** left, so it belongs to layer 1.
layer_faces: do l = 1, nlay
   nz = layer(l)%zones
   do j = 0, nz-1
      i = iface( layer(l)%kfirst - 1 + j )
      database(jx,i) = layer(l)%xleft + &
         layer(l)%width*( real(j,dp)/real(nz,dp) )
      if ( j == 0 ) then
         ilay(i) = max( l-1, 1 )          ! left face: the layer to its left
      else
         ilay(i) = l
      end if
   end do
end do layer_faces
i = iface( kmax )                         ! the right edge of the stack
database(jx,i) = layer(nlay)%xleft + layer(nlay)%width
ilay(i) = nlay

neos = 0                                  ! EOS failures at setup
ieos = eos_ok                             ! the last failure's status

!*** 5b. Cells. The material constants are copied in from the layer
!*** (option 6(a): each cell carries its own, so a chunk is complete),
!*** then the cell mass, fixed for all time,
!***
!***    M_k = R0 * ( x(k+1/2) - x(k-1/2) )          [g/cm^3 * mm]
!***
!*** and the reference state: rho = R0, e = 0, q = 0. P and c come
!*** from the equation of state (module eos), the same call the time
!*** loop will make. At rho = R0 and e = 0 it must give P = 0 and
!*** c = C0 (equation sheet Step 0); section 6 checks that it does.
layer_cells: do l = 1, nlay
   do k = layer(l)%kfirst, layer(l)%klast
      i = icell( k )
      ilay(i) = l
      database(jr0,i) = layer(l)%R0
      database(jc0,i) = layer(l)%C0
      database(js1,i) = layer(l)%S1
      database(js2,i) = layer(l)%S2
      database(jg0,i) = layer(l)%G0
      database(jm,i)       = layer(l)%R0*( database(jx,i+1) - database(jx,i-1) )
      database(jrho,i)     = layer(l)%R0
      database(je,i)       = zero
      database(jq,i)       = zero
      database(jrho_old,i) = layer(l)%R0
      database(je_old,i)   = zero
      call mg_eos( database(jrho,i), database(je,i), &
         database(jr0,i), database(jc0,i), database(js1,i), &
         database(js2,i), database(jg0,i), &
         database(jp,i), database(jc,i), ierr )
      if ( ierr /= eos_ok ) then          ! counted here, reported in 6
         neos = neos + 1
         ieos = ierr
      end if
   end do
end do layer_cells

!*** 5c. The two ghost cells: void on both ends, M = P = q = 0
!*** (equation sheet, Boundary Conditions). With a zero mass the
!*** Step 1 and Step 2 formulas need nothing special at the ends: the
!*** end face gets half a real cell's mass and zero stress, which is
!*** a free surface. Every OTHER ghost slot stays a signaling NaN, so
!*** a loop that reads, say, the density of a ghost stops on the spot.
database( (/jm,jp,jq/), 1    ) = zero    ! left ghost,  i = 1
database( (/jm,jp,jq/), imax ) = zero    ! right ghost, i = imax

!*** 5d. Faces: node mass and velocity. The node mass is half of each
!*** neighbor cell, mf = (M_k + M_k+1)/2 (a ghost adds 0). The velocity
!*** belongs to time level n = -1/2 (leapfrog, equation sheet Step 1),
!*** and is the layer's xvel, except on an IMPACT face, where the two
!*** layers meet with different velocities. There we use the momentum-
!*** weighted value of equation sheet Step 0,
!***
!***    u = ( M_k*u_k + M_k+1*u_k+1 ) / ( M_k + M_k+1 )
!***
!*** so the face carries exactly the momentum of the two half-cells it
!*** stands for, and the total momentum at t = 0 matches the deck.
nimpact = 0
face_loop: do k = 0, kmax
   i  = iface( k )
   ml = database(jm,i-1)                  ! cell on the left  (0 if ghost)
   mr = database(jm,i+1)                  ! cell on the right (0 if ghost)
   database(jmf,i) = half*( ml + mr )

   ll = ilay(i-1)                         ! layer on the left  (0 if ghost)
   lr = ilay(i+1)                         ! layer on the right (0 if ghost)
   if ( ll == 0 ) then                    ! left free surface
      database(ju,i) = layer(lr)%xvel
   else if ( lr == 0 ) then               ! right free surface
      database(ju,i) = layer(ll)%xvel
   else if ( abs( layer(ll)%xvel - layer(lr)%xvel ) > zero ) then
      database(ju,i) = ( ml*layer(ll)%xvel + mr*layer(lr)%xvel )/( ml + mr )
      nimpact = nimpact + 1               ! an impact face
   else
      database(ju,i) = layer(ll)%xvel     ! same velocity on both sides
   end if

   database(jx_old,i) = database(jx,i)
   database(ju_old,i) = database(ju,i)
end do face_loop

!*** Report.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 5. Data arrays'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 205 ) 'Real cells (kmax)', kmax
write( kpt6, 205 ) 'Database places (imax)', imax
!*** Memory, in MB. Done in real arithmetic on purpose: 8*nvar*imax
!*** passes the largest 4-byte integer (about 2.1 billion) near 15
!*** million cells, and Fortran integers wrap around without a word.
write( buf, '(f12.1)' ) 8.0_dp*real(nvar,dp)*real(imax,dp)/1024.0_dp**2
write( kpt6, 203 ) 'Database slots (nvar)', nvar, &
   '('//trim(adjustl(buf))//' MB)'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 202 ) '  layer     '//'    zones'//'    dx (mm)'// &
   '  x left (mm)'//'  u (km/s)'
do l = 1, nlay
   write( kpt6, 208 ) layer(l)%name(1:10), layer(l)%zones, &
      layer(l)%width/real(layer(l)%zones,dp), layer(l)%xleft, &
      layer(l)%xvel
end do
if ( nimpact > 0 ) then
   write( kpt6, 202 ) repeat('-',56)
   do k = 0, kmax
      i  = iface( k )
      ll = ilay(i-1)
      lr = ilay(i+1)
      if ( ll == 0 .or. lr == 0 ) cycle
      if ( abs( layer(ll)%xvel - layer(lr)%xvel ) > zero ) then
         write( kpt6, 209 ) 'Impact face '//trim(layer(ll)%name)//':'// &
            trim(layer(lr)%name)//' at x =', database(jx,i), ' mm'
         write( kpt6, 210 ) 'u =', database(ju,i), &
            ' km/s, weighted from', layer(ll)%xvel, ' |', layer(lr)%xvel
      end if
   end do
end if
write( kpt6, 202 ) repeat('=',56)

!===================================================!
! 6. Initialization: time zero and cycle zero.      !
!===================================================!

! Start the clock at t = 0, cycle 0 (the moment of impact), check the
! setup, and record the t = 0 totals that the heartbeat measures every
! later cycle against.
time   = zero
ncycle = 0

!*** 6a. The t = 0 totals (per unit area), equation sheet notation:
!***
!***    mass       sum_k  M_k
!***    momentum   sum_k  M_k * ubar_k,   ubar_k = (u(k-1/2) + u(k+1/2))/2
!***    energy     sum_k  M_k * ( e_k + ubar_k**2/2 )
!***
!*** Summing M_k*ubar_k over cells is the same as summing mf*u over
!*** faces, which is what the momentum update conserves exactly.
!*** Units: mass g/cm^3*mm; momentum that times km/s; energy that
!*** times (km/s)^2, which is GPa*mm.
mass0 = zero
xmom0 = zero
etot0 = zero
do k = 1, kmax
   i = icell( k )
   ubar  = half*( database(ju,i-1) + database(ju,i+1) )
   mass0 = mass0 + database(jm,i)
   xmom0 = xmom0 + database(jm,i)*ubar
   etot0 = etot0 + database(jm,i)*( database(je,i) + half*ubar**2 )
end do

!*** 6b. Setup audit. Each check below is cheap and is run every time,
!*** because every one of them guards against a slip in the index
!*** bookkeeping above, the part of a hydrocode that is easiest to get
!*** wrong and hardest to see in the results.
nbad = 0

! (1) The slot lists cover every slot exactly once (shock_mod).
if ( size(face_slots) + size(cell_slots) /= nvar ) then
   call setup_fail( 'face_slots and cell_slots do not add up to nvar' )
end if

! (2) The equation of state: no failures, and at the reference state
!     exactly P = 0 and c = C0 (to a few units in the last place) in
!     every cell. This ties the EOS to equation sheet Step 0.
if ( neos > 0 ) then
   call setup_fail( 'the EOS failed in '//itoa(neos)//' cells: '// &
      eos_message(ieos) )
else
   nz = 0
   do k = 1, kmax
      i = icell( k )
      if ( abs(database(jp,i)) > zero .or. abs(database(jc,i) - &
           database(jc0,i)) > 4.0_dp*epsilon(one)*database(jc0,i) ) nz = nz + 1
   end do
   if ( nz > 0 ) call setup_fail( 'the EOS does not give P = 0, c = C0 '// &
      'at the reference state in '//itoa(nz)//' cells' )
end if

! (3) Every slot a face or real cell should have is a real number,
!     i.e. nothing was left at its signaling-NaN fill. Checked one
!     slot at a time, so a forgotten slot is reported once, by name
!     (dbname), with how many places missed it.
!     (Even i from 2 to imax-1 are the faces; odd i from 3 to imax-2
!     are the real cells.)
do j = 1, size(face_slots)
   nz = count( not_finite( database(face_slots(j), 2:imax-1:2) ) )
   if ( nz > 0 ) call setup_fail( 'face slot '// &
      trim(dbname(face_slots(j)))//' was never set ('//itoa(nz)// &
      ' of '//itoa(kmax+1)//' faces)' )
end do
do j = 1, size(cell_slots)
   nz = count( not_finite( database(cell_slots(j), 3:imax-2:2) ) )
   if ( nz > 0 ) call setup_fail( 'cell slot '// &
      trim(dbname(cell_slots(j)))//' was never set ('//itoa(nz)// &
      ' of '//itoa(kmax)//' cells)' )
end do

! (4) Every place knows its layer. The cells of layer l are exactly
!     kfirst..klast; face k+1/2 belongs to cell k's layer (the layer on
!     its left), except the first face, which belongs to layer 1.
do l = 1, nlay
   if ( any( ilay( icell( (/ (k, k = layer(l)%kfirst, layer(l)%klast) /) ) ) &
        /= l ) ) then
      call setup_fail( 'layer '//trim(layer(l)%name)//': ilay is wrong '// &
         'on its cells' )
   end if
end do
nz = 0
do k = 1, kmax
   if ( ilay(iface(k)) /= ilay(icell(k)) ) nz = nz + 1
end do
if ( ilay(iface(0)) /= 1 ) nz = nz + 1
if ( nz > 0 ) call setup_fail( 'ilay is wrong on '//itoa(nz)//' faces' )

! (5) Material interfaces sit exactly on faces, where the deck put them.
do l = 1, nlay
   if ( abs( database(jx, iface(layer(l)%kfirst-1)) - layer(l)%xleft ) &
        > zero ) then
      call setup_fail( 'layer '//trim(layer(l)%name)//': left face is '// &
         'not at xleft' )
   end if
end do

! (6) Mass and momentum match the deck, layer by layer: sum of
!     R0*width and of R0*width*xvel. The impact faces are weighted so
!     that momentum comes out exact (to round-off).
!
!     How close is "exact to round-off"? Adding up kmax numbers one
!     after another can lose up to about kmax*epsilon (relative), and
!     that is what we allow. Measured on the class deck: 3e-15 at 945
!     cells, growing to 4e-11 at 9.45 million cells, always below
!     kmax*epsilon (2e-13 and 2e-9). A real setup slip is far bigger:
!     one wrong cell mass, or a plain average at the impact face, is
!     off by 1e-5 or more.
mdeck = zero
pdeck = zero
do l = 1, nlay
   mdeck = mdeck + layer(l)%R0*layer(l)%width
   pdeck = pdeck + layer(l)%R0*layer(l)%width*layer(l)%xvel
end do
tol = real(kmax,dp)*epsilon(one)
if ( abs( mass0 - mdeck ) > tol*mdeck ) then
   call setup_fail( 'total mass does not match the deck' )
end if
if ( abs( xmom0 - pdeck ) > tol*max( abs(pdeck), abs(xmom0) ) ) then
   call setup_fail( 'total momentum does not match the deck' )
end if

if ( nbad > 0 ) then
   write( kpt6, '(1x,i0,a)' ) nbad, ' setup check(s) failed; stopping. '// &
      'This is a bug in bitwhiz, not in the deck.'
   call close_heartbeat( 'setup check failed' )
   stop 1, quiet=.true.
end if

!*** 6c. The first time step, dt(0), from the t = 0 state (c = C0 and
!*** the initial face velocities), with dt(-1) = dt(0), so the first
!*** velocity half step spans exactly dt(0), as in the sheet's fixed-dt
!*** case. (Commercial codes let the user set the cycle-0 step and limit
!*** how fast dt may grow; those may become Solver keys one day. For
!*** now bitwhiz does exactly what the equation sheet says.)
dtcfl = huge(one)
kdt   = 0
do k = 1, kmax
   i   = icell( k )
   dtk = cell_dt( database(:,i-2:i+2), database(jc,i) )
   if ( dtk < dtcfl ) then
      dtcfl = dtk
      kdt   = k
   end if
end do
dt      = CFL*dtcfl
dt_prev = dt
merr    = zero
eerr    = zero
xmom    = xmom0
endhow  = 'normal end'

!*** The t = 0 totals also go into the heartbeat header, so the file
!*** that reports relative errors also says what they are relative to.
write( khb, '(a,es16.9,a)' ) '# mass0   : ', mass0, '  g/cm^3*mm'
write( khb, '(a,es16.9,a)' ) '# xmom0   : ', xmom0, '  g/cm^3*mm*km/s'
write( khb, '(a,es16.9,a)' ) '# etot0   : ', etot0, '  GPa*mm'
write( khb, '(a)' ) '#   cycle      t (us)     dt (us)  dt cell'// &
   '   max P (GPa)    mass err  energy err   x-momentum   wall (s)'
call heartbeat_line( dt, kdt, zero )      ! cycle 0: the first dt(0)

!*** Report.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 6. Initialization'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 211 ) 'Time (us)', time
write( kpt6, 205 ) 'Cycle', ncycle
write( kpt6, 211 ) 'Total mass (g/cm^3*mm)', mass0
write( kpt6, 211 ) 'x-momentum (g/cm^3*mm*km/s)', xmom0
write( kpt6, 211 ) 'Total energy (GPa*mm)', etot0
write( kpt6, 211 ) 'First time step (us)', dt
write( kpt6, 205 ) '... set by cell', kdt
write( kpt6, 204 ) 'Setup checks', 'all passed'
write( kpt6, 202 ) repeat('=',56)

!==========================!
! 7. Begin the simulation. !
!==========================!

! One cycle, in the order of the equation sheet ("One Cycle"):
!
!   a. velocity u(n+1/2) on every face, from P(n), q(n)       loop 1
!   b. positions x(n+1), then densities rho(n+1)              loops 1, 2
!   c. energies e(n+1), from P(n), q(n), u(n-1/2), u(n+1/2)   loop 2
!   d. pressures P(n+1) (kept >= 0), then sound speeds c      loop 3
!   e. viscosities q(n+1), then the next time step dt(n+1)    loop 3
!   f. the heartbeat line; n <- n+1; repeat until t_end
!
! Why three loops and not one: each loop must FINISH before the next
! one starts. Loop 2 needs the new x and u of every face from loop 1,
! and the energy of cell k needs the OLD P and q of cells k-1 and k+1,
! which loop 3 overwrites. Inside a loop every place is independent:
! it reads its chunk and writes back only its own new values (the
! WRITE-BACK RULE in shock_mod), so the places can be done in any
! order, by any thread. The physics itself is in module av
! (src/modules/av_mod.f95), one small routine per loop.
!
! OPENMP, "style 2" of the timing study (NOTES_bitwhiz_Performance_
! IO_v1.md, section 2): ONE parallel region per cycle, with an OMP DO
! on each loop inside it. Each END DO makes every thread wait for the
! rest, which is the "must finish" above. The region runs on a single
! thread when the mesh has fewer than omp_min_zones cells (deck: Run
! block), where threads only slow things down. DEFAULT(NONE) makes the
! compiler insist that every variable used inside is declared SHARED
! or PRIVATE: a forgotten one is a compile error, not a race.
!
! Threads give the serial answer BIT FOR BIT (checked: the whole final
! database is identical at 1, 2, 3, 4 and 8 threads). Every place gets
! the same arithmetic either way, and what the loops reduce does not
! depend on the order: minimums (the smallest time step, the first
! tensile, void or EOS-failed cell; ties go to the lowest cell number),
! a maximum (the largest P) and an integer count (void cells). The
! heartbeat sums are done serially, after the region, for the same
! reason.

use_team = ( kmax >= omp_min_zones )      ! big enough to pay for threads
nloop = 1                                 ! threads the loop will use
!$ if ( use_team ) nloop = max_threads

write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 7. Simulation'
write( kpt6, 202 ) repeat('-',56)
if ( .not. use_team .and. max_threads > 1 ) then
   write( kpt6, 203 ) 'Threads in the time loop', nloop, &
      '(kmax < omp_min_zones)'
else
   write( kpt6, 205 ) 'Threads in the time loop', nloop
end if
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 202 ) '        cycle      t (us)     dt (us)    max P (GPa)'

tnext   = 0.1_dp*t_end                    ! next progress line on screen
done    = .false.
stopped = .false.
tens_k  = 0                               ! first tensile cell, 0 = none
void_k  = 0                               ! first void cell, 0 = none
nvoid_max = 0                             ! most void cells at one time

time_loop: do while ( .not. done )

   !*** This cycle's step: dt from the CFL limit found last cycle (or
   !*** in 6c), shortened if need be to land exactly on t_end. dth is
   !*** the time between the velocity half steps (equation sheet,
   !*** Step 1 note), time-centered as dt changes.
   kdt_used = kdt
   last = .not. ( time + dt < t_end )
   if ( last ) then
      dt = t_end - time
      kdt_used = 0                        ! set by t_end, not by a cell
   end if
   dth = half*( dt_prev + dt )

   dtcfl = huge(one)                      ! smallest dt_k this cycle
   kdt   = 0                              ! ... and the cell that has it
   pmax  = zero
   ktens = huge(ktens)                    ! first cell with P < 0
   kvoid = huge(kvoid)                    ! first void cell
   nvoid = 0                              ! void cells this cycle
   kbad  = huge(kbad)                     ! first cell the EOS rejects

   !$OMP PARALLEL IF( use_team ) DEFAULT(NONE) &
   !$OMP    SHARED( database, imax, dt, dth, BL, BQ, dtcfl, kdt, &
   !$OMP            pmax, ktens, kbad, kvoid, nvoid ) &
   !$OMP    PRIVATE( i, unew, xnew, rnew, enew, pnew, cnew, qnew, &
   !$OMP             dtk, tens, isvoid, ierr, dtl, kl )

   !*** Loop 1, faces (even i): u(n+1/2), then x(n+1). Steps a, b.
   !$OMP DO
   step_faces: do i = 2, imax-1, 2
      call face_step( database(:,i-1:i+1), dth, dt, unew, xnew )
      database(ju_old,i) = database(ju,i)
      database(ju,i)     = unew
      database(jx_old,i) = database(jx,i)
      database(jx,i)     = xnew
   end do step_faces
   !$OMP END DO

   !*** Loop 2, cells (odd i): rho(n+1) and e(n+1). Steps b, c.
   !$OMP DO
   step_cells: do i = 3, imax-2, 2
      call cell_step( database(:,i-2:i+2), dt, rnew, enew )
      database(jrho_old,i) = database(jrho,i)
      database(jrho,i)     = rnew
      database(je_old,i)   = database(je,i)
      database(je,i)       = enew
   end do step_cells
   !$OMP END DO

   !*** Loop 3, cells: P (floored at 0), c, q and dt_k. Steps d, e.
   !*** cell_state applies the floor; the loop records the first cell
   !*** that was really in tension (see cell_state). Each thread keeps
   !*** its own smallest dt_k (dtl, cell kl); they are merged below.
   dtl = huge(one)
   kl  = 0
   !$OMP DO REDUCTION(min: ktens, kbad, kvoid) REDUCTION(max: pmax) &
   !$OMP    REDUCTION(+: nvoid)
   step_states: do i = 3, imax-2, 2
      call cell_state( database(:,i-2:i+2), BL, BQ, pnew, cnew, qnew, &
         dtk, tens, isvoid, ierr )
      if ( ierr /= eos_ok ) then          ! reported after the region
         kbad = min( kbad, kcell(i) )
         cycle step_states
      end if
      if ( tens ) ktens = min( ktens, kcell(i) )   ! P was floored
      if ( isvoid ) then                  ! see cell_state, VOID CELLS
         nvoid = nvoid + 1
         kvoid = min( kvoid, kcell(i) )
      end if
      database(jp,i) = pnew
      database(jc,i) = cnew
      database(jq,i) = qnew
      pmax = max( pmax, pnew )
      if ( dtk < dtl ) then               ! strictly less: the lowest
         dtl = dtk                        ! cell wins a tie
         kl  = kcell(i)
      end if
   end do step_states
   !$OMP END DO

   !*** Merge each thread's smallest dt_k, one thread at a time; a tie
   !*** goes to the lower cell number, as in a serial run.
   !$OMP CRITICAL (cfl_merge)
   if ( dtl < dtcfl .or. ( .not. ( dtl > dtcfl ) .and. kl < kdt ) ) then
      dtcfl = dtl
      kdt   = kl
   end if
   !$OMP END CRITICAL (cfl_merge)

   !$OMP END PARALLEL

   !*** An EOS failure stops the run, naming the first cell it hit.
   if ( kbad < huge(kbad) ) then
      i = icell( kbad )
      call cell_state( database(:,i-2:i+2), BL, BQ, pnew, cnew, qnew, &
         dtk, tens, isvoid, ierr )
      write( kpt6, '(1x,a,i0,3a,i0,a,es12.5,a)' ) 'bitwhiz: the EOS '// &
         'failed in cell ', kbad, ' (layer ', trim(layer(ilay(i))%name), &
         ') on cycle ', ncycle+1, ', t = ', time+dt, ' us:'
      write( kpt6, '(1x,a)' ) '         '//eos_message(ierr)
      call close_heartbeat( 'EOS failure in cell '//itoa(kbad)//': '// &
         eos_message(ierr) )
      stop 1, quiet=.true.
   end if

   !*** The first cell to go tensile, recorded once (equation sheet,
   !*** Step 2; project Sec. 3): cycle, time, cell, layer and x.
   if ( ktens < huge(ktens) .and. tens_k == 0 ) then
      tens_k     = ktens
      tens_cycle = ncycle + 1
      tens_time  = time + dt
      i          = icell( ktens )
      tens_x     = half*( database(jx,i-1) + database(jx,i+1) )
      write( khb, '(a,i0,a,f0.6,a,i0,3a,f0.6,a)' ) '# tensile : first '// &
         'P < 0 on cycle ', tens_cycle, ', t = ', tens_time, ' us, cell ', &
         tens_k, ' (', trim(layer(ilay(i))%name), '), x = ', tens_x, &
         ' mm; P set to 0'
   end if

   !*** The first void cell, recorded once, and the most at any time.
   if ( nvoid > 0 .and. void_k == 0 ) then
      void_k     = kvoid
      void_cycle = ncycle + 1
      void_time  = time + dt
      i          = icell( kvoid )
      write( khb, '(a,i0,a,f0.6,a,i0,3a)' ) '# void    : first void '// &
         'cell on cycle ', void_cycle, ', t = ', void_time, ' us, cell ', &
         void_k, ' (', trim(layer(ilay(i))%name), '): stretched past '// &
         'its EOS at P = 0; P = q = c = 0'
   end if
   nvoid_max = max( nvoid_max, nvoid )

   !*** Advance the clock: n <- n+1. Then the next step from the CFL
   !*** limit (equation sheet, Time Step): dt(n+1) = CFL * min dt_k.
   ncycle = ncycle + 1
   if ( last ) then
      time = t_end                        ! exactly, no round-off
   else
      time = time + dt
   end if
   dt_used = dt
   dt_prev = dt
   dt      = CFL*dtcfl
   if ( .not. ( dt > zero ) ) then        ! can not happen; a backstop
      write( kpt6, '(1x,a,i0)' ) 'bitwhiz: the time step collapsed '// &
         'on cycle ', ncycle
      call close_heartbeat( 'time step collapsed' )
      stop 1, quiet=.true.
   end if

   !*** Step f: one heartbeat line per cycle, a screen line every 10%.
   call heartbeat_line( dt_used, kdt_used, pmax )
   if ( .not. ( time < tnext ) .or. last ) then
      write( kpt6, '(3x,i10,f12.6,es12.4,f15.6)' ) ncycle, time, &
         dt_used, pmax
      do while ( .not. ( time < tnext ) )
         tnext = tnext + 0.1_dp*t_end
      end do
   end if

   !*** Done? At t_end, or (the backstop) at cycle_max.
   if ( last ) then
      done = .true.
   else if ( ncycle >= cycle_max ) then
      done    = .true.
      stopped = .true.
   end if

end do time_loop

!*** Report.
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 205 ) 'Cycles', ncycle
write( kpt6, 211 ) 'Final time (us)', time
write( kpt6, 211 ) 'Mass error (relative)', merr
if ( etot0 > zero ) then
   write( kpt6, 211 ) 'Energy error (relative)', eerr
else
   write( kpt6, 211 ) 'Energy change (GPa*mm)', eerr
end if
write( kpt6, 211 ) 'x-momentum change', xmom - xmom0
if ( tens_k > 0 ) then
   write( kpt6, 212 ) 'First tensile cell (P set to 0)', tens_k, &
      trim(layer(ilay(icell(tens_k)))%name), tens_time
else
   write( kpt6, 204 ) 'First tensile cell', 'none'
end if
if ( void_k > 0 ) then
   write( kpt6, 212 ) 'First void cell', void_k, &
      trim(layer(ilay(icell(void_k)))%name), void_time
   write( kpt6, 205 ) 'Most void cells at one time', nvoid_max
end if
call system_clock( tick1 )
write( kpt6, 211 ) 'Wall time per cycle (us)', &
   1.0e6_dp*real(tick1-tick0,dp)/real(rate,dp)/real(max(ncycle,1),dp)
if ( stopped ) then
   write( kpt6, 202 ) repeat('-',56)
   write( kpt6, 202 ) '  WARNING: stopped at cycle_max = '// &
      itoa(cycle_max)//' before t_end.'
   endhow = 'cycle_max reached before t_end'
end if
write( kpt6, 202 ) repeat('=',56)

!===============================================!
! 8. Close the heartbeat file, free the memory. !
!===============================================!
call close_heartbeat( trim(endhow) )

! Every alloc_ in shock_mod has its dealloc_ (bits RULE). kerr only
! counts; a failure here at the very end is reported, not fatal.
kerr = 0
call dealloc_database( kerr )
call dealloc_tracers( kerr )
call dealloc_layers( kerr )
call dealloc_materials( kerr )
if ( kerr > 0 ) write( kpt6, 202 ) 'bitwhiz: warning: could not free '// &
   'all memory at the end of the run'

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
   ! One heartbeat line: cycle, time, the step just      !
   ! taken and the cell that set it (0 = shortened to    !
   ! land on t_end), the largest pressure, and the       !
   ! conservation checks against the t = 0 totals:       !
   !    mass err    (sum M - mass0)/mass0     exactly 0  !
   !    energy err  (E - etot0)/etot0, E = sum_k M_k*    !
   !                (e_k + ubar_k**2/2), ubar at n+1/2   !
   !    x-momentum  sum_k M_k*ubar_k (constant: the end  !
   !                faces push on void, P = q = 0)       !
   ! Summed serially, so the line is the same with or    !
   ! without threads. Flushed, so tail -f sees it now.   !
   !*****************************************************!
   subroutine heartbeat_line( dtu, kdtu, pm )
   implicit none
   real(kind=dp), intent(in) :: dtu       ! us, the step just taken
   integer(kind=int32), intent(in) :: kdtu ! the cell that set it
   real(kind=dp), intent(in) :: pm        ! GPa, largest pressure
   integer(kind=int32) :: kk, ii
   integer(kind=int64) :: tk
   real(kind=dp) :: ub, ms, et, xm
   ms = zero
   et = zero
   xm = zero
   do kk = 1, kmax
      ii = icell( kk )
      ub = half*( database(ju,ii-1) + database(ju,ii+1) )
      ms = ms + database(jm,ii)
      xm = xm + database(jm,ii)*ub
      et = et + database(jm,ii)*( database(je,ii) + half*ub*ub )
   end do
   merr = ( ms - mass0 )/mass0
   if ( etot0 > zero ) then
      eerr = ( et - etot0 )/etot0
   else
      eerr = et - etot0                   ! nothing moving at t = 0
   end if
   xmom = xm
   call system_clock( tk )
   write( khb, '(i9,f12.6,es12.4,i9,f14.6,es12.3,es12.3,es13.5,f11.3)' ) &
      ncycle, time, dtu, kdtu, pm, merr, eerr, xmom, &
      real(tk-tick0,dp)/real(rate,dp)
   flush( khb )
   end subroutine heartbeat_line

   !*****************************************************!
   ! One failed setup check (section 6): say what, and   !
   ! count it. All the checks run, so one run lists      !
   ! every problem, the same way the deck reader does.   !
   !*****************************************************!
   subroutine setup_fail( msg )
   implicit none
   character(len=*), intent(in) :: msg
   write( kpt6, '(1x,a)' ) 'bitwhiz: setup check failed: '//msg
   nbad = nbad + 1
   end subroutine setup_fail

   !*****************************************************!
   ! An integer as text, without padding: 945 -> "945".  !
   !*****************************************************!
   function itoa( n ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim(buf)
   end function itoa

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

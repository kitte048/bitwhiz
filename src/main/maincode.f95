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
!
!**********************************************************************!
use bits, only: dp,int32,int64,kpt6,zero,half,one
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads, &
   thread_num,nalive,title,khb,hb_open,hb_file, &
   kmax,imax,nvar,nlay,layer,database,ilay,icell,iface, &
   jx,ju,jx_old,ju_old,jmf,jm,jrho,je,jp,jq,jc,jrho_old,je_old, &
   jr0,jc0,js1,js2,jg0,face_slots,cell_slots,dbname,not_finite, &
   alloc_database,dealloc_database,dealloc_layers, &
   dealloc_materials,dealloc_tracers
use deck, only: read_deck,write_resolved_deck
use eos, only: mg_eos,eos_message,eos_ok
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

!*** The t = 0 totals also go into the heartbeat header, so the file
!*** that reports relative errors also says what they are relative to.
write( khb, '(a,es16.9,a)' ) '# mass0   : ', mass0, '  g/cm^3*mm'
write( khb, '(a,es16.9,a)' ) '# xmom0   : ', xmom0, '  g/cm^3*mm*km/s'
write( khb, '(a,es16.9,a)' ) '# etot0   : ', etot0, '  GPa*mm'
write( khb, '(a)' ) '#   cycle      t (us)     dt (us)  dt cell'// &
   '   max P (GPa)    mass err  energy err   x-momentum   wall (s)'
flush( khb )

!*** Report.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 6. Initialization'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 211 ) 'Time (us)', time
write( kpt6, 205 ) 'Cycle', ncycle
write( kpt6, 211 ) 'Total mass (g/cm^3*mm)', mass0
write( kpt6, 211 ) 'x-momentum (g/cm^3*mm*km/s)', xmom0
write( kpt6, 211 ) 'Total energy (GPa*mm)', etot0
write( kpt6, 204 ) 'Setup checks', 'all passed'
write( kpt6, 202 ) repeat('=',56)

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

!===============================================!
! 8. Close the heartbeat file, free the memory. !
!===============================================!
call close_heartbeat( 'normal end' )

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

program bitwhiz
!**********************************************************************!
!
!  Purpose:
!    bitwhiz, a one-dimensional Lagrangian hydrocode for the ME 697
!    class project. Usage:   bitwhiz <deck>
!
!    The run goes section by section, top to bottom:
!      0. Read the command line.     5. Allocate the data arrays.
!      1. Loading screen.            6. Initialization (t = 0).
!      2. Read the input deck.       7. Begin the simulation.
!      3. Test OpenMP settings.      8. Close the output files.
!      4. Open the output files.     9. Pictures; free the memory.
!
!    A deck with plots_only = yes goes from 2 straight to 9: no run,
!    only the pictures, from the files an earlier run of it left.
!
!    On the screen every section opens with a rule of '=' and the run
!    ends with one; sections do not close their own, so there is one
!    rule between two sections. The resolved deck goes to its own file,
!    <title>.resolved (section 2), not to the screen.
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
!    10/15/26    D. E. Kittell        Spall: cells hold tension, break
!                (with Claude)        at spall_strength; first break,
!                                     count and most tension reported
!    10/15/26    D. E. Kittell        Every cycle, check that x, u, rho,
!                (with Claude)        e, P, q, c are still numbers (for
!                                     machines and builds without traps)
!    10/15/26    D. E. Kittell        Tracer file <title>.tracers.csv
!                (with Claude)        (module trace): a row at cycle 0,
!                                     then by tracer_dt; trailer written
!                                     by close_outputs
!    10/15/26    D. E. Kittell        close_heartbeat renamed
!                (with Claude)        close_outputs: it closes every
!                                     output file, tracers included
!    10/15/26    D. E. Kittell        method = RS (Riemann solver) runs
!                (with Claude)        setup and cycle 0, then stops: the
!                                     RS time loop is under construction
!    10/19/26    D. E. Kittell        Method RS time loop (module rs,
!                (with Claude)        RS sheet v3): faces solve the
!                                     Riemann problem, cells take their
!                                     fluxes; the RS stop is removed
!    10/20/26    D. E. Kittell        RS order 1 or 2 (deck: order,
!                (with Claude)        default 2): a cell loop builds the
!                                     face states first; the method and
!                                     order are echoed in every output
!    10/20/26    D. E. Kittell        History file <title>.hist (module
!                (with Claude)        hist): x, u, P on the whole mesh,
!                                     one frame per snapshot (plot_every,
!                                     plot_dt); closed by close_outputs
!    10/20/26    D. E. Kittell        Section 9, pictures (module pics):
!                (with Claude)        after a run, and the whole of a
!                                     plots_only run; plot_dt and
!                                     plot_every in the history file
!    10/22/26    D. E. Kittell        Velocity profiles: a layer's
!                (with Claude)        starting u may vary across it
!                                     (xvel_profile, module
!                                     distributions); faces take the
!                                     momentum-weighted u of their two
!                                     cells; the momentum check scales
!                                     with the momentum's magnitude
!    10/23/26    D. E. Kittell        Exits through quit (module bits),
!                (with Claude)        not "stop n, quiet=.true.", so
!                                     gfortran 9 and 10 compile it
!    11/03/26    D. E. Kittell        Temperature (module temperature),
!                (with Claude)        for materials with eos =
!                                     mie_gruneisen_t: set in 5e,
!                                     checked in 6, updated every cycle
!                                     after the hydro step; the run's T
!                                     range and hottest cell reported
!!    11/03/26    D. E. Kittell        The screen, for a quick read: the
!                (with Claude)        resolved deck to <title>.resolved
!                                     (section 2), one rule between
!                                     sections, section 8 lists the
!                                     files written with their sizes,
!                                     times in us as plain numbers, and
!                                     the command line read before the
!                                     banner (a usage error alone)
!
!**********************************************************************!
use bits, only: dp,int32,int64,kpt6,zero,half,one,quit
use shock, only: omp_on,nproc,num_procs,max_threads,num_threads,method, &
   thread_num,nalive,title,khb,hb_open,hb_file, &
   kmax,imax,nvar,nlay,layer,database,ilay,icell,iface, &
   jx,ju,jx_old,ju_old,jmf,jm,jrho,je,jp,jq,jc,jrho_old,je_old, &
   jr0,jc0,js1,js2,jg0,jdam,jsp,ju_star,jp_star,juc, &
   ju_lf,ju_rf,jp_lf,jp_rf,rs_order, &
   face_slots,cell_slots,dbname,not_finite, &
   kcell,t_end,cycle_max,CFL,BL,BQ,omp_min_zones, &
   alloc_database,dealloc_database,dealloc_layers, &
   dealloc_materials,dealloc_tracers,plots_only,plot_dt,plot_every
use temperature, only: alloc_temperature,dealloc_temperature, &
   temp_update,nt,kt,tk,etac,tmin_run,tmax_run,hot_k,hot_time,hot_x
use deck, only: read_deck,write_resolved_deck,fmt_real
use pics, only: make_pictures
use eos, only: mg_eos,eos_message,eos_ok
use av, only: face_step,cell_step,cell_state,cell_dt
use rs, only: rs_face_states,riemann_face,rs_cell_step,rs_state,rs_cell_dt
use trace, only: open_tracers,tracer_row,close_tracers,trc_open,trc_file
use hist, only: open_history,history_frame,close_history,hst_open, &
   hst_file,hst_frames
use build, only: build_date,build_version       ! written by 'make'
use distributions, only: dist_t,dist_set,dist_cdf,dist_sf
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
character(len=1024) :: hinfo(9)         ! the history file's text lines
integer(kind=int32) :: npic = 0         ! problems making the pictures
integer(kind=int32) :: nlen             ! full length of the deck path
character(len=256) :: deckname          ! the deck file, from the
                                        ! command line
character(len=72) :: rv_file            ! <title>.resolved
integer :: krv                          ! its unit (newunit)
!*** Setup (sections 5 and 6). All local: see the RULE in bit_mod.
integer(kind=int32) :: i,j,k            ! database index, counter, cell
integer(kind=int32) :: l,ll,lr          ! layer; layers left/right of a face
integer(kind=int32) :: nz               ! zones in one layer
integer(kind=int32) :: nimpact          ! impact faces found
integer(kind=int32) :: nbad             ! setup checks that failed
integer(kind=int32) :: ierr             ! status from the EOS
integer(kind=int32) :: ierr_d           ! status from dist_set
integer(kind=int32) :: neos,ieos        ! EOS failures at setup, last status
integer(kind=int32) :: ncycle           ! cycle number, n
real(kind=dp) :: time                   ! problem time, us
real(kind=dp) :: ml,mr                  ! cell masses left/right of a face
real(kind=dp) :: ubar                   ! cell-average velocity, km/s
real(kind=dp) :: mass0,xmom0,etot0      ! t = 0 totals (per unit area)
real(kind=dp) :: xabs0                  ! t = 0 sum of M*|u|, momentum's
                                        ! scale (a layer may be at rest
                                        ! on average yet moving)
real(kind=dp), allocatable :: ucell(:)  ! km/s, each cell's starting u
real(kind=dp), allocatable :: gface(:)  ! a layer's profile, F (or -S) at
                                        ! each of its faces
type(dist_t) :: dprof                   ! a layer's velocity profile
character(len=200) :: dmsg              ! dist_set's message (unused:
                                        ! the deck reader checked it)
real(kind=dp) :: du,gmass,xi,dxi        ! profile: amplitude (km/s), the
                                        ! probability on the layer, a
                                        ! face's xi, a cell's width in xi
logical :: use_sf                       ! profile: build G from -S
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
real(kind=dp) :: mtot,etot,ekin,eint    ! heartbeat: totals (tracer file)
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
logical :: spl                          ! a cell broke (spall) this step
real(kind=dp) :: dnew                   ! a cell's damage D after the step
real(kind=dp) :: pmin                   ! GPa, most tension this cycle
real(kind=dp) :: pmin_run               ! GPa, most tension, whole run
real(kind=dp) :: pbrk                   ! GPa, a cell's EOS P as it broke
real(kind=dp) :: pbmin                  ! GPa, deepest of those this cycle
real(kind=dp) :: pbreak_run             ! GPa, ... and over the whole run
integer(kind=int32) :: kspall,nspall    ! first cell to break, count
integer(kind=int32) :: spall_k          ! first cell to break, 0 = none
integer(kind=int32) :: spall_cycle      ! ... its cycle
integer(kind=int32) :: nbroken          ! cells broken so far
real(kind=dp) :: spall_time,spall_x     ! us, mm, of the first break
integer(kind=int32) :: kvoid,nvoid      ! first void cell, void count
integer(kind=int32) :: void_k,void_cycle ! first void cell ever, its cycle
integer(kind=int32) :: nvoid_max        ! most void cells at one time
real(kind=dp) :: void_time              ! us, when the first one appeared
logical :: done                         ! leave the time loop
logical :: stopped                      ! left at cycle_max, not t_end
character(len=64) :: endhow             ! how the run ended (heartbeat)
character(len=25) :: started            ! when the run started (clock)
logical :: running = .false.            ! the time loop has started

202 format(1x,a)                        ! a plain line
203 format(3x,a,t40,': ',i8,2x,a)       ! label : integer  note
204 format(3x,a,t40,': ',a)             ! label : text
205 format(3x,a,t40,': ',i8)            ! label : integer
206 format(3x,a,t15,': ',a)             ! banner label : text
208 format(3x,a10,i9,es11.4,f13.6,f10.4) ! layer table row
209 format(3x,a,f10.6,a)                ! label number unit
210 format(5x,a,f8.4,a,f8.4,a,f8.4)     ! impact face velocities
211 format(3x,a,t40,': ',es15.8)        ! label : real
212 format(3x,a,t40,': ',i0,' (',a,'), t =',f9.4,' us') ! tensile event
213 format(3x,a,f9.4,a,f9.4,a)          ! a profile's velocity range
214 format(3x,a,t40,': ',f0.3,' to ',f0.3) ! label : a range
215 format(3x,a,t40,': ',i0,' (',a,'), t =',f9.4,' us, x =',f9.4,' mm')
216 format(3x,a,t40,': ',f15.6)          ! label : a time, us
217 format(3x,a,t40,': ',f15.1)          ! label : wall time per cycle, us

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

!=============================!
! 0. Read the command line.   !
!=============================!

! Usage:  bitwhiz <deck>
!
! Read first, before the loading screen, so a mistake on the command
! line gets its usage message alone, not under 20 lines of banner.
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

!====================!
! 1. Loading screen. !
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

!=========================!
! 2. Read the input deck. !
!=========================!

! The deck reader (module deck, src/modules/deck_mod.f95) checks every
! line against input/README.md and fills the input tables in the shock
! module. It lists ALL the problems it finds before giving up, each
! with the deck's file name and line number, so one run shows every
! mistake, under this section's heading. If the deck is clean, the
! "resolved deck" is written to <title>.resolved: the same run with
! every default filled in and every define substituted. It is the
! record of what this run actually used, and running it gives exactly
! the same run (bitwhiz <title>.resolved). Its name does not end in
! .deck, so nothing that looks for decks (input/*.deck, the tests, the
! nanoHUB picker) ever takes it for one.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 2. Input deck: '//trim(deckname)
write( kpt6, 202 ) repeat('-',56)
call read_deck( trim(deckname), kerr )
if ( kerr > 0 ) then
   write( kpt6, 202 ) repeat('-',56)
   write( kpt6, '(1x,i0,a)' ) kerr, ' error(s) in the input deck; stopping.'
   call quit( 1 )                       ! exit status 1, quietly (bits)
end if
write( kpt6, 204 ) 'Title', trim(title)
!*** A plots_only run keeps the resolved deck of the run it draws from
!*** (that is the record of the run), so it writes none of its own.
if ( plots_only ) then
   write( kpt6, 204 ) 'Resolved deck', trim(title)//'.resolved (the '// &
      'run''s, kept: plots_only writes none)'
else
   rv_file = trim(title)//'.resolved'
   open( newunit=krv, file=trim(rv_file), status='replace', &
         action='write', iostat=ios )
   if ( ios /= 0 ) then
      write( kpt6, 202 ) 'bitwhiz: cannot open the resolved deck '// &
         trim(rv_file)
      call quit( 1 )
   end if
   call write_resolved_deck( int(krv) )
   close( krv )
   write( kpt6, 204 ) 'Resolved deck', trim(rv_file)//' (every '// &
      'default filled in)'
end if

!*** plots_only = yes: no run. Straight to the pictures (section 9),
!*** from the files an earlier run of this deck left. Nothing else is
!*** opened, so the heartbeat, tracer and history files it reads are
!*** never touched.
if ( plots_only ) then
   call make_pictures( npic )
   call finish_run()
   if ( npic > 0 ) call quit( 1 )
   call quit( 0 )
end if

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

!==============================!
! 4. Open the output files.    !
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
   call quit( 1 )
end if
hb_open = .true.

!*** Header: where the run came from. Section 6 adds the t = 0
!*** totals and then the column names; the cycle lines that section 7
!*** writes line up under those names.
write( khb, '(a)' ) '# bitwhiz heartbeat'
write( khb, '(a)' ) '# deck    : '//trim(deckname)
write( khb, '(a)' ) '# title   : '//trim(title)
write( khb, '(a)' ) '# method  : '//method_text()
started = clock()
write( khb, '(a)' ) '# started : '//started
write( khb, '(a)' ) '# version : '//build_version()
write( khb, '(a)' ) '# built   : '//build_date()//', '//compiler_version()
write( khb, '(a)' ) '# flags   : '//compiler_options()
write( khb, '(a)' ) '# units   : us, GPa; errors are relative to t = 0'
flush( khb )                            ! so tail -f sees it now

!*** The tracer file, <title>.tracers.csv (module trace), if the deck
!*** has tracers: two header lines now, a row at cycle 0 (section 6)
!*** and then every tracer_dt (section 7), and a trailer when the run
!*** ends (close_outputs), however it ends.
call open_tracers( title, ios )
if ( ios /= 0 ) then
   write( kpt6, 202 ) 'bitwhiz: cannot open the tracer file '// &
      trim(title)//'.tracers.csv'
   call close_outputs( 'cannot open the tracer file' )
   call quit( 1 )
end if

!*** The history file, <title>.hist (module hist), if the deck asks for
!*** snapshots (plot_every or plot_dt): the header now, with the same
!*** lines as the heartbeat's header for its text block, a frame at
!*** cycle 0 (section 6) and at every snapshot (section 7), and the
!*** frame count and how the run ended when it ends (close_outputs).
hinfo    = ' '
hinfo(1) = 'deck    : '//trim(deckname)
hinfo(2) = 'title   : '//trim(title)
hinfo(3) = 'method  : '//method_text()
hinfo(4) = 'started : '//started
hinfo(5) = 'version : '//build_version()
hinfo(6) = 'built   : '//build_date()//', '//compiler_version()
hinfo(7) = 'flags   : '//compiler_options()
hinfo(8) = 'plot_dt    : '//fmt_real(plot_dt)
hinfo(9) = 'plot_every : '//itoa(plot_every)
call open_history( title, hinfo, ios )
if ( ios /= 0 ) then
   write( kpt6, 202 ) 'bitwhiz: cannot open the history file '// &
      trim(title)//'.hist'
   call close_outputs( 'cannot open the history file' )
   call quit( 1 )
end if

write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 4. Output files'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 204 ) 'Heartbeat file', trim(hb_file)
if ( trc_open ) then
   write( kpt6, 204 ) 'Tracer file', trim(trc_file)
else
   write( kpt6, 204 ) 'Tracer file', 'none (no tracers in the deck)'
end if
if ( hst_open ) then
   write( kpt6, 204 ) 'History file', trim(hst_file)
else
   write( kpt6, 204 ) 'History file', 'none (no plot_every or plot_dt)'
end if

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
   call close_outputs( 'could not allocate the database' )
   call quit( 1 )
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
!*** Each cell's starting velocity, ucell(k). A layer without
!*** xvel_profile: its xvel. With one (input/README.md, Layer block;
!*** doc/design/distributions.md):
!***
!***    u = xvel + du*( fbar - 1 ),   du = xvel_amplitude (else xvel)
!***
!*** fbar is the mean over the cell of the profile's density on the
!*** layer, xi = (x - xleft)/width from 0 to 1, truncated to [0, 1]
!*** and renormalized:
!***
!***    fbar_k = ( G(xi_r) - G(xi_l) ) / ( ( G(1) - G(0) )*( xi_r - xi_l ) )
!***
!*** G is the cumulative distribution F, or -S (S = 1 - F, the
!*** accurate tail) where F(0) >= 1/2. G is computed once at every
!*** face, so the differences telescope: the layer's momentum is
!*** R0*width*xvel to round-off, which section 6, check (6), checks.
allocate( ucell(kmax), gface(0:maxval( layer(:)%zones )) )
layer_velocity: do l = 1, nlay
   if ( len_trim( layer(l)%prof_name ) == 0 ) then
      ucell( layer(l)%kfirst:layer(l)%klast ) = layer(l)%xvel
      cycle layer_velocity
   end if
   call dist_set( dprof, layer(l)%prof_name, &
      layer(l)%prof_par(1:layer(l)%prof_np), ierr_d, dmsg )
   du = layer(l)%xvel
   if ( layer(l)%have_amp ) du = layer(l)%xamp
   use_sf = ( dist_cdf( dprof, zero ) >= half )
   nz = layer(l)%zones
   do j = 0, nz
      i  = iface( layer(l)%kfirst - 1 + j )
      xi = ( database(jx,i) - layer(l)%xleft )/layer(l)%width
      if ( use_sf ) then
         gface(j) = -dist_sf( dprof, xi )
      else
         gface(j) = dist_cdf( dprof, xi )
      end if
   end do
   gmass = gface(nz) - gface(0)
   do j = 1, nz
      k   = layer(l)%kfirst - 1 + j
      dxi = ( database(jx,iface(k)) - database(jx,iface(k-1)) )/layer(l)%width
      ucell(k) = layer(l)%xvel + du*( ( gface(j) - gface(j-1) )/ &
         ( gmass*dxi ) - one )
   end do
end do layer_velocity

layer_cells: do l = 1, nlay
   do k = layer(l)%kfirst, layer(l)%klast
      i = icell( k )
      ilay(i) = l
      database(jr0,i) = layer(l)%R0
      database(jc0,i) = layer(l)%C0
      database(js1,i) = layer(l)%S1
      database(js2,i) = layer(l)%S2
      database(jg0,i) = layer(l)%G0
      database(jsp,i) = layer(l)%spall_strength
      database(jdam,i) = zero             ! every cell starts intact
      database(juc,i)  = ucell(k)         ! RS: the cell's velocity
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
      !*** RS: the face states, rebuilt every cycle before use; at t = 0
      !*** they are the cell's own u and P.
      database(ju_lf,i) = database(juc,i)
      database(ju_rf,i) = database(juc,i)
      database(jp_lf,i) = database(jp,i)
      database(jp_rf,i) = database(jp,i)
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
!*** and is its cells' velocity (ucell, above) where both have the
!*** same; where they differ (an IMPACT face, where two layers meet
!*** with different velocities, or inside a layer with a velocity
!*** profile) it is the momentum-weighted value of equation sheet
!*** Step 0,
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
      database(ju,i) = ucell(k+1)
   else if ( lr == 0 ) then               ! right free surface
      database(ju,i) = ucell(k)
   else if ( abs( ucell(k) - ucell(k+1) ) > zero ) then
      database(ju,i) = ( ml*ucell(k) + mr*ucell(k+1) )/( ml + mr )
      if ( ll /= lr ) nimpact = nimpact + 1   ! an impact face
   else
      database(ju,i) = ucell(k)           ! same velocity on both sides
   end if

   database(jx_old,i) = database(jx,i)
   database(ju_old,i) = database(ju,i)

   !*** RS: u* and P* are the Riemann solution, first solved in cycle
   !*** 1. Until then u* is the face's starting velocity (so x and the
   !*** cycle-0 tracer row read the same value as AV) and P* is 0, the
   !*** pressure everywhere at t = 0. Both methods fill both slots, so
   !*** the setup audit does not depend on the method.
   database(ju_star,i) = database(ju,i)
   database(jp_star,i) = zero
end do face_loop

!*** 5e. Temperature (module temperature), only if some material's
!*** model carries it (eos = mie_gruneisen_t): each such cell's cold
!*** energy, the eta it holds at, and T, from the t = 0 state above
!*** (eta = 0, e_c = 0, T = T0; checked in 6). Its own arrays, not
!*** database slots: a deck without it allocates nothing more.
call alloc_temperature( kerr )
if ( kerr > 0 ) then
   write( kpt6, 202 ) 'bitwhiz: cannot allocate the temperatures '// &
      '(out of memory?)'
   call close_outputs( 'could not allocate the temperatures' )
   call quit( 1 )
end if

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
if ( nt > 0 ) write( kpt6, 203 ) 'Cells carrying T', nt, &
   '(eos = mie_gruneisen_t)'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 202 ) '  layer     '//'    zones'//'    dx (mm)'// &
   '  x left (mm)'//'  u (km/s)'
do l = 1, nlay
   write( kpt6, 208 ) layer(l)%name(1:10), layer(l)%zones, &
      layer(l)%width/real(layer(l)%zones,dp), layer(l)%xleft, &
      layer(l)%xvel
end do
!*** A layer with a velocity profile: the table gives its mean (xvel);
!*** here, the range its cells start with.
if ( any( len_trim( layer(:)%prof_name ) > 0 ) ) then
   write( kpt6, 202 ) repeat('-',56)
   do l = 1, nlay
      if ( len_trim( layer(l)%prof_name ) == 0 ) cycle
      write( kpt6, 213 ) 'Profile '//trim(layer(l)%name)//' ('// &
         trim(layer(l)%prof_name)//'): u from', &
         minval( ucell(layer(l)%kfirst:layer(l)%klast) ), ' to', &
         maxval( ucell(layer(l)%kfirst:layer(l)%klast) ), ' km/s'
   end do
end if
if ( nimpact > 0 ) then
   write( kpt6, 202 ) repeat('-',56)
   do k = 0, kmax
      i  = iface( k )
      ll = ilay(i-1)
      lr = ilay(i+1)
      if ( ll == 0 .or. lr == 0 .or. ll == lr ) cycle
      if ( abs( ucell(k) - ucell(k+1) ) > zero ) then
         write( kpt6, 209 ) 'Impact face '//trim(layer(ll)%name)//':'// &
            trim(layer(lr)%name)//' at x =', database(jx,i), ' mm'
         write( kpt6, 210 ) 'u =', database(ju,i), &
            ' km/s, weighted from', ucell(k), ' |', ucell(k+1)
      end if
   end do
end if
deallocate( ucell, gface )

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
!***
!*** That is AV, whose velocities live on the faces. RS carries a
!*** velocity in every cell (uc), and its totals use that instead:
!*** ubar_k = uc_k. (At t = 0 it is the cell's starting velocity,
!*** ucell, so RS's totals match the deck exactly, impact face or
!*** velocity profile or not.)
mass0 = zero
xmom0 = zero
xabs0 = zero
etot0 = zero
do k = 1, kmax
   i = icell( k )
   if ( method == 'RS' ) then
      ubar = database(juc,i)
   else
      ubar = half*( database(ju,i-1) + database(ju,i+1) )
   end if
   mass0 = mass0 + database(jm,i)
   xmom0 = xmom0 + database(jm,i)*ubar
   xabs0 = xabs0 + database(jm,i)*abs( ubar )
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
!     that momentum comes out exact (to round-off), and so are layers
!     with a velocity profile (their xvel is their mean velocity).
!     Momentum's round-off is measured against xabs0, the sum of
!     M*|u|: a layer at rest on average (xvel = 0) can still be moving,
!     and then the total, 0, is no scale at all.
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
if ( abs( xmom0 - pdeck ) > tol*max( abs(pdeck), abs(xmom0), xabs0 ) ) then
   call setup_fail( 'total momentum does not match the deck' )
end if

! (7) Temperature, in the cells that carry it: at the reference state
!     eta = 0 and T = T0, exactly (e = 0 and e_c = 0, so T is T0 times
!     exp(0) = 1). This ties module temperature to the t = 0 state.
nz = 0
do j = 1, nt
   k = kt(j)
   if ( abs( etac(k) ) > zero .or. abs( tk(k) - &
        layer(ilay(icell(k)))%T0 ) > zero ) nz = nz + 1
end do
if ( nz > 0 ) call setup_fail( 'T is not T0 at the reference state in '// &
   itoa(nz)//' cells' )

if ( nbad > 0 ) then
   write( kpt6, '(1x,i0,a)' ) nbad, ' setup check(s) failed; stopping. '// &
      'This is a bug in bitwhiz, not in the deck.'
   call close_outputs( 'setup check failed' )
   call quit( 1 )
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
   if ( method == 'RS' ) then             ! RS: dx/c (module rs)
      dtk = rs_cell_dt( database(:,i-2:i+2), database(jc,i) )
   else
      dtk = cell_dt( database(:,i-2:i+2), database(jc,i) )
   end if
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
call tracer_row( ncycle, time, dt, mtot, etot, ekin, eint, xmom, &
   .false. )                              ! cycle 0, always written
call history_frame( ncycle, time, .false. )   ! cycle 0, always written

!*** Report.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 6. Initialization'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 216 ) 'Time (us)', time
write( kpt6, 205 ) 'Cycle', ncycle
write( kpt6, 211 ) 'Total mass (g/cm^3*mm)', mass0
write( kpt6, 211 ) 'x-momentum (g/cm^3*mm*km/s)', xmom0
write( kpt6, 211 ) 'Total energy (GPa*mm)', etot0
write( kpt6, 211 ) 'First time step (us)', dt
write( kpt6, 205 ) '... set by cell', kdt
write( kpt6, 204 ) 'Setup checks', 'all passed'

!==========================!
! 7. Begin the simulation. !
!==========================!

! One cycle, in the order of the equation sheet ("One Cycle"):
!
!   a. velocity u(n+1/2) on every face, from P(n), q(n)       loop 1
!   b. positions x(n+1), then densities rho(n+1)              loops 1, 2
!   c. energies e(n+1), from P(n), q(n), u(n-1/2), u(n+1/2)   loop 2
!   d. pressures P(n+1) (spall rule), then sound speeds c     loop 3
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
! That is method AV. Method RS (Godunov, a Riemann solver at every
! face) runs its own cycle instead, in the contained routine rs_region
! with module rs: two loops, the same OpenMP pattern, and the same
! reports after the region.
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
! tensile, broken, void or EOS-failed cell, the most negative P; ties
! go to the lowest cell number), a maximum (the largest P) and integer
! counts (broken and void cells). The
! heartbeat sums are done serially, after the region, for the same
! reason.

use_team = ( kmax >= omp_min_zones )      ! big enough to pay for threads
nloop = 1                                 ! threads the loop will use
!$ if ( use_team ) nloop = max_threads

write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 7. Simulation'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 204 ) 'Method', method_text()
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
spall_k = 0                               ! first cell to break, 0 = none
nbroken = 0                               ! cells broken so far
pmin_run = zero                           ! most tension held, whole run
pbreak_run = zero                         ! deepest pull at a break, run
nvoid_max = 0                             ! most void cells at one time
running = .true.                          ! (for the tracer trailer)

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
   pmin  = zero                           ! most tension this cycle
   ktens = huge(ktens)                    ! first cell with P < 0
   kvoid = huge(kvoid)                    ! first void cell
   nvoid = 0                              ! void cells this cycle
   kspall = huge(kspall)                  ! first cell to break
   nspall = 0                             ! cells that broke this cycle
   pbmin  = zero                          ! deepest pull at a break
   kbad  = huge(kbad)                     ! first cell the EOS rejects

   if ( method == 'RS' ) then
      call rs_region()                    ! method RS (contained, below)
   else                                   ! method AV:

   !$OMP PARALLEL IF( use_team ) DEFAULT(NONE) &
   !$OMP    SHARED( database, imax, dt, dth, BL, BQ, dtcfl, kdt, &
   !$OMP            pmax, pmin, ktens, kbad, kvoid, nvoid, kspall, &
   !$OMP            nspall, pbmin ) &
   !$OMP    PRIVATE( i, unew, xnew, rnew, enew, pnew, cnew, qnew, &
   !$OMP             dtk, dnew, tens, spl, pbrk, isvoid, ierr, dtl, kl )

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

   !*** Loop 3, cells: P (with the spall rule), c, q, D and dt_k. Steps
   !*** d, e. cell_state decides whether a cell holds its tension or
   !*** breaks (see cell_state); the loop records the first tensile and
   !*** the first broken cell, and counts breaks. Each thread keeps
   !*** its own smallest dt_k (dtl, cell kl); they are merged below.
   dtl = huge(one)
   kl  = 0
   !$OMP DO REDUCTION(min: ktens, kbad, kvoid, kspall, pmin, pbmin) &
   !$OMP    REDUCTION(max: pmax) REDUCTION(+: nvoid, nspall)
   step_states: do i = 3, imax-2, 2
      call cell_state( database(:,i-2:i+2), BL, BQ, pnew, cnew, qnew, &
         dtk, dnew, tens, spl, pbrk, isvoid, ierr )
      if ( ierr /= eos_ok ) then          ! reported after the region
         kbad = min( kbad, kcell(i) )
         cycle step_states
      end if
      if ( tens ) ktens = min( ktens, kcell(i) )   ! in tension
      if ( spl ) then                     ! broke on this step
         nspall = nspall + 1
         kspall = min( kspall, kcell(i) )
         pbmin  = min( pbmin, pbrk )      ! deepest pull at a break
      end if
      pmin = min( pmin, pnew )            ! most tension held
      if ( isvoid ) then                  ! see cell_state, VOID CELLS
         nvoid = nvoid + 1
         kvoid = min( kvoid, kcell(i) )
      end if
      database(jp,i)   = pnew
      database(jc,i)   = cnew
      database(jq,i)   = qnew
      database(jdam,i) = dnew             ! only this cell's own D
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

   end if                                 ! method AV / RS

   !*** An EOS failure stops the run, naming the first cell it hit.
   if ( kbad < huge(kbad) ) then
      i = icell( kbad )
      if ( method == 'RS' ) then
         call rs_state( database(:,i-2:i+2), pnew, cnew, dtk, dnew, &
            tens, spl, pbrk, isvoid, ierr )
      else
         call cell_state( database(:,i-2:i+2), BL, BQ, pnew, cnew, qnew, &
            dtk, dnew, tens, spl, pbrk, isvoid, ierr )
      end if
      write( kpt6, '(1x,a,i0,3a,i0,a,es12.5,a)' ) 'bitwhiz: the EOS '// &
         'failed in cell ', kbad, ' (layer ', trim(layer(ilay(i))%name), &
         ') on cycle ', ncycle+1, ', t = ', time+dt, ' us:'
      write( kpt6, '(1x,a)' ) '         '//eos_message(ierr)
      call close_outputs( 'EOS failure in cell '//itoa(kbad)//': '// &
         eos_message(ierr) )
      call quit( 1 )
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
         tens_k, ' (', trim(layer(ilay(i))%name), '), x = ', tens_x, ' mm'
   end if

   !*** Spall: the first cell to break, recorded once, and a count of
   !*** every cell that has broken (each breaks only once).
   if ( nspall > 0 ) then
      if ( spall_k == 0 ) then
         spall_k     = kspall
         spall_cycle = ncycle + 1
         spall_time  = time + dt
         i           = icell( kspall )
         spall_x     = half*( database(jx,i-1) + database(jx,i+1) )
         write( khb, '(a,i0,a,f0.6,a,i0,3a,f0.6,a,f0.4,a,f0.4,a)' ) &
            '# spall   : first cell breaks on cycle ', spall_cycle, &
            ', t = ', spall_time, ' us, cell ', spall_k, ' (', &
            trim(layer(ilay(i))%name), '), x = ', spall_x, &
            ' mm, spall_strength ', database(jsp,i), &
            ' GPa; deepest pull at a break this cycle ', pbmin, ' GPa'
      end if
      nbroken = nbroken + nspall
   end if
   pmin_run   = min( pmin_run, pmin )
   pbreak_run = min( pbreak_run, pbmin )

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
      call close_outputs( 'time step collapsed' )
      call quit( 1 )
   end if

   !*** Temperature (module temperature; nothing to do without it):
   !*** each cell that carries T moves its cold energy to its new
   !*** volume and takes its new T, after the hydro step of either
   !*** method, on the same team of threads. Its cold-curve integral
   !*** evaluates Pi with the EOS at points between two volumes the
   !*** hydro accepted, so it can not fail; if it ever does, it stops
   !*** the run as an EOS failure would.
   call temp_update( use_team, time, ncycle, kbad )
   if ( kbad < huge(kbad) ) then
      write( kpt6, '(1x,a,i0,3a,i0)' ) 'bitwhiz: the cold curve '// &
         '(temperature) failed in cell ', kbad, ' (layer ', &
         trim(layer(ilay(icell(kbad)))%name), ') on cycle ', ncycle
      call close_outputs( 'cold curve failure in cell '//itoa(kbad) )
      call quit( 1 )
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

   !*** A tracer row, if this cycle is an output time (tracer_dt), and
   !*** always on the last cycle.
   call tracer_row( ncycle, time, dt_used, mtot, etot, ekin, eint, &
      xmom, done )

   !*** A history frame, if this cycle is a snapshot (plot_every,
   !*** plot_dt), and always on the last cycle.
   call history_frame( ncycle, time, done )

end do time_loop

!*** Report.
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 205 ) 'Cycles', ncycle
write( kpt6, 216 ) 'Final time (us)', time
write( kpt6, 211 ) 'Mass error (relative)', merr
if ( etot0 > zero ) then
   write( kpt6, 211 ) 'Energy error (relative)', eerr
else
   write( kpt6, 211 ) 'Energy change (GPa*mm)', eerr
end if
write( kpt6, 211 ) 'x-momentum change', xmom - xmom0
if ( tens_k > 0 ) then
   write( kpt6, 212 ) 'First tensile cell', tens_k, &
      trim(layer(ilay(icell(tens_k)))%name), tens_time
   write( kpt6, 211 ) 'Most tension held, intact (GPa)', pmin_run
else
   write( kpt6, 204 ) 'First tensile cell', 'none'
end if
if ( spall_k > 0 ) then
   write( kpt6, 212 ) 'First cell to break (spall)', spall_k, &
      trim(layer(ilay(icell(spall_k)))%name), spall_time
   write( kpt6, 205 ) 'Cells broken by the end', nbroken
   write( kpt6, 211 ) 'Deepest tension at a break (GPa)', pbreak_run
else
   write( kpt6, 204 ) 'First cell to break (spall)', 'none'
end if
if ( void_k > 0 ) then
   write( kpt6, 212 ) 'First void cell', void_k, &
      trim(layer(ilay(icell(void_k)))%name), void_time
   write( kpt6, 205 ) 'Most void cells at one time', nvoid_max
end if
if ( nt > 0 ) then
   write( kpt6, 214 ) 'T range, intact cells (K)', tmin_run, &
      tmax_run
   write( kpt6, 215 ) 'Hottest intact cell', hot_k, &
      trim(layer(ilay(icell(hot_k)))%name), hot_time, hot_x
end if
call system_clock( tick1 )
write( kpt6, 217 ) 'Wall time per cycle (us)', &
   1.0e6_dp*real(tick1-tick0,dp)/real(rate,dp)/real(max(ncycle,1),dp)
if ( stopped ) then
   write( kpt6, 202 ) repeat('-',56)
   write( kpt6, 202 ) '  WARNING: stopped at cycle_max = '// &
      itoa(cycle_max)//' before t_end.'
   endhow = 'cycle_max reached before t_end'
end if

!=============================!
! 8. Close the output files.  !
!=============================!
call close_outputs( trim(endhow) )

!*** Report: every file the run wrote, with its size on disk, so a big
!*** history file (it grows with cells times frames) is seen at once.
write( kpt6, 202 ) repeat('=',56)
write( kpt6, 202 ) ' 8. Output files, closed'
write( kpt6, 202 ) repeat('-',56)
write( kpt6, 204 ) 'Resolved deck', trim(rv_file)//'  ('// &
   file_size(rv_file)//')'
write( kpt6, 204 ) 'Heartbeat file', trim(hb_file)//'  ('// &
   file_size(hb_file)//')'
if ( len_trim(trc_file) > 0 ) write( kpt6, 204 ) 'Tracer file', &
   trim(trc_file)//'  ('//file_size(trc_file)//')'
if ( len_trim(hst_file) > 0 ) write( kpt6, 204 ) 'History file', &
   trim(hst_file)//'  ('//file_size(hst_file)//', '//itoa(hst_frames)// &
   ' frames)'

!========================================!
! 9. Pictures (module pics), then free   !
!    the memory and say how long it took.!
!========================================!

! Read back from the files just closed, exactly as a plots_only run
! reads them, so both make the same pictures from the same numbers.
call make_pictures( npic )
call finish_run()
if ( npic > 0 ) call quit( 1 )     ! a picture could not be made

contains

   !*****************************************************!
   ! The end of every run that gets this far (a normal   !
   ! one, and plots_only): free the memory and say how   !
   ! long it took. (The caller then stops with exit      !
   ! status 1 if a picture could not be made, npic.)     !
   !                                                     !
   ! Every alloc_ in shock_mod has its dealloc_ (bits    !
   ! RULE). A failure to free memory at the very end is  !
   ! reported, not fatal. The closing lines have the     !
   ! banner's layout, so a run's screen output opens and !
   ! closes the same way. (See the start of the program  !
   ! for wall vs. CPU time.)                             !
   !*****************************************************!
   subroutine finish_run()
   implicit none
   integer(kind=int32) :: kfree
   kfree = 0
   call dealloc_temperature( kfree )
   call dealloc_database( kfree )
   call dealloc_tracers( kfree )
   call dealloc_layers( kfree )
   call dealloc_materials( kfree )
   if ( kfree > 0 ) write( kpt6, '(1x,a)' ) 'bitwhiz: warning: could '// &
      'free all memory at the end of the run'
   call system_clock( tick1 )
   call cpu_time( cpu1 )
   write( kpt6, '(1x,a)' ) repeat('=',56)
   write( kpt6, '(3x,a,t15,": ",a)' ) 'run end', clock()
   write( kpt6, '(3x,a,t15,": ",f10.3,a)' ) 'wall clock', &
      real(tick1-tick0,dp)/real(rate,dp), ' s'
   write( kpt6, '(3x,a,t15,": ",f10.3,a)' ) 'CPU time', cpu1-cpu0, &
      ' s (all threads)'
   write( kpt6, '(1x,a)' ) repeat('=',56)
   end subroutine finish_run

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
   call quit( 1 )
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
   ! One cycle of method RS (RS equation sheet, One      !
   ! Cycle; the physics is in module rs). Three loops,   !
   ! and each must finish before the next starts:        !
   !                                                     !
   !   loop 0, cells: the u and P each cell offers its   !
   !     two faces (rs_face_states; order 1 or 2). (a)   !
   !   loop 1, faces: the Riemann problem between the    !
   !     two cells at time n gives u* and P*; the face   !
   !     moves, x(n+1) = x(n) + dt*u*.           (b, c)  !
   !   loop 2, cells: rho, u and E from the two faces'   !
   !     fluxes, then e, then P (spall rule), c, D and   !
   !     the cell's dt_k.                  (c, d, e, f)  !
   !                                                     !
   ! Loop 2 can do the state in the same pass as the     !
   ! update, because a cell's new P and c depend only on !
   ! itself; nobody reads them until loop 1 of the next  !
   ! cycle. Same OpenMP pattern as method AV (one region,!
   ! DEFAULT(NONE), the same reductions and dt merge), so!
   ! threads give the serial answer bit for bit. The     !
   ! cycle's results go back through the host variables  !
   ! (dtcfl, kdt, pmax, ...), exactly as AV's do.        !
   !*****************************************************!
   subroutine rs_region()
   implicit none
   integer(kind=int32) :: i, ierr, kl
   real(kind=dp) :: us, ps, xnew, rnew, unew, enew, pnew, cnew, dtk, &
      dnew, pbrk, dtl, ul, ur, pl, pr
   logical :: tens, spl, isvoid

   !$OMP PARALLEL IF( use_team ) DEFAULT(NONE) &
   !$OMP    SHARED( database, imax, dt, dtcfl, kdt, pmax, pmin, ktens, &
   !$OMP            kbad, kvoid, nvoid, kspall, nspall, pbmin, rs_order ) &
   !$OMP    PRIVATE( i, us, ps, xnew, rnew, unew, enew, pnew, cnew, dtk, &
   !$OMP             dnew, tens, spl, pbrk, isvoid, ierr, dtl, kl, &
   !$OMP             ul, ur, pl, pr )

   !*** Loop 0, cells (odd i): the u and P each cell offers its two
   !*** faces (its own for order 1; MUSCL-Hancock for order 2).
   !$OMP DO
   rs_states: do i = 3, imax-2, 2
      call rs_face_states( database(:,i-2:i+2), dt, rs_order, ul, ur, &
         pl, pr )
      database(ju_lf,i) = ul
      database(ju_rf,i) = ur
      database(jp_lf,i) = pl
      database(jp_rf,i) = pr
   end do rs_states
   !$OMP END DO

   !*** Loop 1, faces (even i): u*, P*, then x(n+1).
   !$OMP DO
   rs_faces: do i = 2, imax-1, 2
      call riemann_face( database(:,i-1:i+1), us, ps )
      xnew = database(jx,i) + dt*us
      database(ju_star,i) = us
      database(jp_star,i) = ps
      database(jx_old,i)  = database(jx,i)
      database(jx,i)      = xnew
   end do rs_faces
   !$OMP END DO

   !*** Loop 2, cells (odd i): rho, u, e at n+1, then the state.
   dtl = huge(one)
   kl  = 0
   !$OMP DO REDUCTION(min: ktens, kbad, kvoid, kspall, pmin, pbmin) &
   !$OMP    REDUCTION(max: pmax) REDUCTION(+: nvoid, nspall)
   rs_cells: do i = 3, imax-2, 2
      call rs_cell_step( database(:,i-2:i+2), dt, rnew, unew, enew )
      database(jrho_old,i) = database(jrho,i)
      database(jrho,i)     = rnew
      database(juc,i)      = unew
      database(je_old,i)   = database(je,i)
      database(je,i)       = enew
      call rs_state( database(:,i-2:i+2), pnew, cnew, dtk, dnew, tens, &
         spl, pbrk, isvoid, ierr )
      if ( ierr /= eos_ok ) then          ! reported after the region
         kbad = min( kbad, kcell(i) )
         cycle rs_cells
      end if
      if ( tens ) ktens = min( ktens, kcell(i) )   ! in tension
      if ( spl ) then                     ! broke on this step
         nspall = nspall + 1
         kspall = min( kspall, kcell(i) )
         pbmin  = min( pbmin, pbrk )      ! deepest pull at a break
      end if
      pmin = min( pmin, pnew )            ! most tension held
      if ( isvoid ) then
         nvoid = nvoid + 1
         kvoid = min( kvoid, kcell(i) )
      end if
      database(jp,i)   = pnew
      database(jc,i)   = cnew
      database(jdam,i) = dnew             ! only this cell's own D
      pmax = max( pmax, pnew )
      if ( dtk < dtl ) then               ! strictly less: the lowest
         dtl = dtk                        ! cell wins a tie
         kl  = kcell(i)
      end if
   end do rs_cells
   !$OMP END DO

   !*** Merge each thread's smallest dt_k (as for method AV).
   !$OMP CRITICAL (cfl_merge_rs)
   if ( dtl < dtcfl .or. ( .not. ( dtl > dtcfl ) .and. kl < kdt ) ) then
      dtcfl = dtl
      kdt   = kl
   end if
   !$OMP END CRITICAL (cfl_merge_rs)

   !$OMP END PARALLEL
   end subroutine rs_region

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
   !                                                     !
   ! It also checks, every cycle, that the state is      !
   ! still made of numbers: x, u on every face and rho,  !
   ! e, P, q, c in every cell. In a debug build a NaN    !
   ! stops the run on the spot (-ffpe-trap), but not     !
   ! every machine can trap floating-point errors, and   !
   ! an optimized build has no traps at all. The check   !
   ! is one running sum of all those values: a NaN or an !
   ! infinity anywhere makes the sum one too, so a       !
   ! finite sum means every value is finite. That costs  !
   ! one add per value; only when the sum is bad does    !
   ! find_bad search for the place and stop the run.     !
   ! Method RS's own slots (u_star, p_star on the faces, !
   ! uc and the face states in the cells) are in the sum !
   ! too; for method AV they keep their t = 0 values,    !
   ! which costs nothing.                                !
   !*****************************************************!
   subroutine heartbeat_line( dtu, kdtu, pm )
   implicit none
   real(kind=dp), intent(in) :: dtu       ! us, the step just taken
   integer(kind=int32), intent(in) :: kdtu ! the cell that set it
   real(kind=dp), intent(in) :: pm        ! GPa, largest pressure
   integer(kind=int32) :: kk, ii
   integer(kind=int64) :: tk
   real(kind=dp) :: ub, ms, et, xm, chk, ek, ei

   !*** One pass: the conservation sums, and the running sum chk of
   !*** every value that must stay a number (each face's x and u, each
   !*** cell's rho, e, P, q, c). Checked once, after the loop.
   ms  = zero
   et  = zero
   xm  = zero
   ek  = zero
   ei  = zero
   chk = zero
   do kk = 1, kmax
      ii  = icell( kk )
      if ( method == 'RS' ) then
         ub = database(juc,ii)            ! RS: the cell's own velocity
      else
         ub = half*( database(ju,ii-1) + database(ju,ii+1) )
      end if
      ms  = ms + database(jm,ii)
      xm  = xm + database(jm,ii)*ub
      et  = et + database(jm,ii)*( database(je,ii) + half*ub*ub )
      ek  = ek + database(jm,ii)*half*ub*ub
      ei  = ei + database(jm,ii)*database(je,ii)
      chk = chk + database(jx,ii-1) + database(ju,ii-1) + database(jrho,ii) &
                + database(je,ii) + database(jp,ii) + database(jq,ii) &
                + database(jc,ii) + database(ju_star,ii-1) &
                + database(jp_star,ii-1) + database(juc,ii) &
                + database(ju_lf,ii) + database(ju_rf,ii) &
                + database(jp_lf,ii) + database(jp_rf,ii)
   end do
   ii  = iface( kmax )                    ! the last face
   chk = chk + database(jx,ii) + database(ju,ii) + database(ju_star,ii) &
             + database(jp_star,ii)
   if ( not_finite( chk ) ) call find_bad()
   merr = ( ms - mass0 )/mass0
   if ( etot0 > zero ) then
      eerr = ( et - etot0 )/etot0
   else
      eerr = et - etot0                   ! nothing moving at t = 0
   end if
   xmom = xm
   mtot = ms                              ! the totals, for the tracer
   etot = et                              ! file (EK + EINT = ETOT up
   ekin = ek                              ! to round-off)
   eint = ei
   call system_clock( tk )
   write( khb, '(i9,f12.6,es12.4,i9,f14.6,es12.3,es12.3,es13.5,f11.3)' ) &
      ncycle, time, dtu, kdtu, pm, merr, eerr, xmom, &
      real(tk-tick0,dp)/real(rate,dp)
   flush( khb )
   end subroutine heartbeat_line

   !*****************************************************!
   ! The state has stopped being numbers somewhere: find !
   ! the first face or cell (and which value), say so,   !
   ! close the output files with the reason, and stop.   !
   !*****************************************************!
   subroutine find_bad()
   implicit none
   integer(kind=int32), parameter, dimension(4) :: fchk = &
      (/ jx, ju, ju_star, jp_star /)
   integer(kind=int32), parameter, dimension(10) :: cchk = &
      (/ jrho, je, jp, jq, jc, juc, ju_lf, ju_rf, jp_lf, jp_rf /)
   integer(kind=int32) :: ii, jj, jbad, ibad
   ibad = 0
   jbad = 0
   search: do ii = 2, imax-1
      if ( mod(ii,2) == 0 ) then             ! a face
         do jj = 1, size(fchk)
            if ( not_finite( database(fchk(jj),ii) ) ) then
               ibad = ii
               jbad = fchk(jj)
               exit search
            end if
         end do
      else                                   ! a cell
         do jj = 1, size(cchk)
            if ( not_finite( database(cchk(jj),ii) ) ) then
               ibad = ii
               jbad = cchk(jj)
               exit search
            end if
         end do
      end if
   end do search
   if ( ibad == 0 ) then                     ! the sum itself overflowed
      write( kpt6, '(1x,a,i0)' ) 'bitwhiz: the state grew too large '// &
         'to add up on cycle ', ncycle
      call close_outputs( 'state too large' )
   else if ( mod(ibad,2) == 0 ) then
      write( kpt6, '(1x,a,i0,a,i0,a,es12.5,a)' ) 'bitwhiz: '// &
         trim(dbname(jbad))//' on face ', kcell(ibad), '+1/2 is not a '// &
         'finite number on cycle ', ncycle, ', t = ', time, ' us'
      call close_outputs( trim(dbname(jbad))//' not a finite number' )
   else
      write( kpt6, '(1x,a,i0,3a,i0,a,es12.5,a)' ) 'bitwhiz: '// &
         trim(dbname(jbad))//' in cell ', kcell(ibad), ' (', &
         trim(layer(ilay(ibad))%name), ') is not a finite number on cycle ', &
         ncycle, ', t = ', time, ' us'
      call close_outputs( trim(dbname(jbad))//' not a finite number' )
   end if
   call quit( 1 )
   end subroutine find_bad


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
   !*****************************************************!
   ! A file's size on disk, for people: 812 B, 362 KB,   !
   ! 12.3 MB, 1.2 GB (1 KB = 1024 B). '?' if it can not  !
   ! be asked (no such file).                            !
   !*****************************************************!
   function file_size( fname ) result(s)
   implicit none
   character(len=*), intent(in) :: fname
   character(len=:), allocatable :: s
   integer(kind=int64) :: nb
   character(len=16) :: b
   inquire( file=trim(fname), size=nb )
   if ( nb < 0 ) then
      s = '?'
   else if ( nb < 1024_int64 ) then
      write( b, '(i0,a)' ) nb, ' B'
      s = trim(b)
   else if ( nb < 1024_int64**2 ) then
      write( b, '(i0,a)' ) nint( real(nb,dp)/1024.0_dp ), ' KB'
      s = trim(b)
   else if ( nb < 1024_int64**3 ) then
      write( b, '(f0.1,a)' ) real(nb,dp)/1024.0_dp**2, ' MB'
      s = trim(b)
   else
      write( b, '(f0.1,a)' ) real(nb,dp)/1024.0_dp**3, ' GB'
      s = trim(b)
   end if
   end function file_size

   function itoa( n ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim(buf)
   end function itoa

   !*****************************************************!
   ! The method as the outputs name it: "AV", or "RS,    !
   ! order 2 (MUSCL-Hancock, Van Leer)" / "RS, order 1   !
   ! (first-order Godunov)".                             !
   !*****************************************************!
   function method_text() result(s)
   implicit none
   character(len=:), allocatable :: s
   if ( method == 'RS' ) then
      if ( rs_order == 2 ) then
         s = 'RS, order 2 (MUSCL-Hancock, Van Leer)'
      else
         s = 'RS, order 1 (first-order Godunov)'
      end if
   else
      s = 'AV (artificial viscosity)'
   end if
   end function method_text

   !*****************************************************!
   ! Close every output file the run has open, each with !
   ! a word on how the run ended ('normal end', or the   !
   ! reason for stopping), so no file just stops without !
   ! saying why. Every way out of a run after section 4  !
   ! comes through here. Each file is closed only if it  !
   ! is open, so this is safe to call from any exit, and !
   ! twice.                                              !
   !                                                     !
   ! A NEW KIND OF OUTPUT FILE (snapshots, a run log,    !
   ! ...) gets one line below, a call to its own finish  !
   ! routine, and then every exit closes it too.         !
   !*****************************************************!
   subroutine close_outputs( how )
   implicit none
   character(len=*), intent(in) :: how
   call finish_tracers( how )             ! <title>.tracers.csv
   call finish_history( how )             ! <title>.hist
   call finish_heartbeat( how )           ! <title>.heartbeat, last
   end subroutine close_outputs

   !*****************************************************!
   ! The heartbeat's last line, then close it.           !
   !*****************************************************!
   subroutine finish_heartbeat( how )
   implicit none
   character(len=*), intent(in) :: how
   if ( .not. hb_open ) return
   write( khb, '(a)' ) '# ended   : '//clock()//'  ('//how//')'
   close( khb )
   hb_open = .false.
   end subroutine finish_heartbeat

   !*****************************************************!
   ! The history file's frame count and how the run      !
   ! ended (header bytes 20 and 24), then close it:      !
   ! status 1 at t_end, 2 at cycle_max, 3 for any other  !
   ! way out (an error).                                 !
   !*****************************************************!
   subroutine finish_history( how )
   implicit none
   character(len=*), intent(in) :: how
   if ( .not. hst_open ) return
   select case ( how )
   case ( 'normal end' )
      call close_history( 1_int32 )
   case ( 'cycle_max reached before t_end' )
      call close_history( 2_int32 )
   case default
      call close_history( 3_int32 )
   end select
   end subroutine finish_history

   !*****************************************************!
   ! The tracer file's trailer (module trace adds the    !
   ! rows and where each tracer sits), then close it.    !
   ! Called by close_outputs, so every way out of a      !
   ! run writes it. The run's results are added only     !
   ! once the time loop has started.                     !
   !*****************************************************!
   subroutine finish_tracers( how )
   implicit none
   character(len=*), intent(in) :: how
   character(len=1024) :: info(13)
   integer(kind=int32) :: n
   integer(kind=int64) :: tk
   if ( .not. trc_open ) return
   call system_clock( tk )
   info    = ' '
   info(1) = 'bitwhiz tracers'
   info(2) = 'deck     : '//trim(deckname)
   info(3) = 'title    : '//trim(title)
   info(4) = 'method   : '//method_text()
   info(5) = 'started  : '//started
   info(6) = 'ended    : '//clock()//'  ('//how//')'
   info(7) = 'version  : '//build_version()
   info(8) = 'built    : '//build_date()//', '//compiler_version()
   info(9) = 'flags    : '//compiler_options()
   info(10) = 'units    : us, mm, km/s, GPa, g/cm^3, kJ/g; totals per '// &
              'unit area (masses in g/cm^3*mm, energies in GPa*mm)'
   n = 10
   if ( running ) then
      write( info(11), '(a,i0,a,f10.6,a,f9.3,a)' ) 'cycles   : ', ncycle, &
         ', final time ', time, ' us, wall ', &
         real(tk-tick0,dp)/real(rate,dp), ' s'
      write( info(12), '(a,es13.5,a,es13.5,a,es13.5)' ) 'errors   : '// &
         'mass', merr, ', energy', eerr, ', x-momentum change', xmom - xmom0
      write( info(13), '(a,i0)' ) 'spall    : cells broken ', nbroken
      n = 13
   end if
   call close_tracers( info(1:n) )
   end subroutine finish_tracers

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

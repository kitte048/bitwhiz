module shock
!**********************************************************************!
!
!  Purpose:
!    Module contains variables and data arrays used for the hydrocode:
!    the layer table read from the input deck, the database that
!    holds every face and cell of the mesh, and the index rules that
!    tie the numerical method (k) to the Fortran array (i).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/06/26    D. E. Kittell        Original code
!    10/08/26    D. E. Kittell        Data dictionary for the database,
!                (with Claude)        layer table and index functions
!    10/10/26    D. E. Kittell        OpenMP settings
!                (with Claude)
!    10/11/26    D. E. Kittell        Input deck tables: run, solver,
!                (with Claude)        material, layer, tracer
!    10/13/26    D. E. Kittell        Stress lives at cell centers only:
!                (with Claude)        removed the face-stress slot; ns = 2
!                                     explained by the energy update
!    10/13/26    D. E. Kittell        Output block (tracers, snapshots,
!                (with Claude)        colormap); BL, BQ defaults from the
!                                     equation sheet; heartbeat file
!    10/14/26    D. E. Kittell        face_slots and cell_slots lists;
!                (with Claude)        not_finite() for the setup audit
!    10/15/26    D. E. Kittell        omp_min_zones (deck: Run block)
!                (with Claude)
!    10/15/26    D. E. Kittell        Spall: damage slot D (jdam) and
!                (with Claude)        each cell's spall_strength (jsp)
!    10/15/26    D. E. Kittell        tracer_dt (Output block); which
!                (with Claude)        cell a tracer on a node reports
!    10/15/26    D. E. Kittell        Second method, RS (Riemann solver,
!                (with Claude)        under construction): slots u_star,
!                                     p_star (faces) and uc (cells); the
!                                     stress RULE is now a RECOMMENDATION
!    10/20/26    D. E. Kittell        RS second order: rs_order (deck key
!                (with Claude)        order, default 2) and the cell's
!                                     face states u, P (slots u_lf, u_rf,
!                                     p_lf, p_rf)
!    10/20/26    D. E. Kittell        Pictures: plots_only (Run block);
!                (with Claude)        plot_u_lo, plot_u_hi, plot_p_lo,
!                                     plot_p_hi (Output block)
!    10/24/26    D. E. Kittell        plot_range (Output block): robust
!                (with Claude)        (default) or full
!    11/02/26    D. E. Kittell        movie_frames (Output block): a
!                (with Claude)        pressure movie from the snapshots,
!                                     2 to max_movie_frames (50), 0 = off
!    11/03/26    D. E. Kittell        Material models: eos (Material
!                (with Claude)        block), mie_gruneisen (the default)
!                                     or mie_gruneisen_t, which also
!                                     carries T (CV, T0; module
!                                     temperature)
!
!**********************************************************************!
!
!  THE BIG PICTURE
!  ===============
!  Everything the solver knows about the mesh lives in one 2-D array,
!
!     database( nvar, imax )
!
!  The FIRST index picks a variable (x, u, rho, p, ...), and the SECOND
!  index picks a place on the mesh (a ghost, a face or a cell center).
!  Fortran stores arrays column by column, so all nvar values for one
!  place sit next to each other in memory. That makes the two copies
!  below cheap, contiguous, and safe to do inside an OpenMP loop:
!
!     slice = database(:,i)            ! one place, all variables
!     chunk = database(:,i-ns:i+ns)    ! a place and its neighbors
!
!  FORTRAN ARRAY INDEX SUMMARY (from maincode.f95)
!  differs from the numerical method index, "k"
!
!  i= 1   2   3   4   5      imax-1 imax
!   +---+---+---+---+---+-   -+---+---+
!   | G | F | C | F | C | ... | F | G |
!   +---+---+---+---+---+-   -+---+---+
!       even odd              even odd
!
!   G = Ghost Cell, F = Face, C = Center
!
!  Cells are numbered k = 1..kmax in the method. The two ghosts are
!  simply "cell 0" and "cell kmax+1", so ONE rule covers all of them:
!
!     cell k        lives at  i = 2*k + 1     (k = 0 .. kmax+1)
!     face k+1/2    lives at  i = 2*k + 2     (k = 0 .. kmax)
!     imax          =         2*kmax + 3
!
!  Odd i is always a cell (or ghost), even i is always a face. Use the
!  functions icell(), iface() and kcell() below rather than writing
!  the arithmetic by hand all over the code.
!
!**********************************************************************!
!
!  WHY "use bits, only: ..." AND NOT "use bits"
!  ============================================
!  We take only the kind parameters and a few named constants from
!  bits, so there is exactly one definition of dp in the code, and it
!  is plain at the top of every file what it borrows. (bits once held
!  shared loop counters i, j, k, ...; they are gone. Module variables
!  are SHARED between OpenMP threads, so a solver loop that used a
!  module "i" would be a race condition.) Every loop index in the
!  solver is a local variable of the routine that runs the loop; see
!  the RULE in bit_mod.f95.
!
!**********************************************************************!
use bits, only: dp, int32, zero, one
implicit none
save

! Declare all items to be public
public

!**********************************************************************!
! Data dictionary: database column (variable) indices.
!
!  Faces and cells share the same nvar slots. A face only fills the
!  face slots, and a cell only fills the cell and material slots.
!  Every slot that does not apply is left as a SIGNALING NaN (see
!  alloc_database), so if the code ever does arithmetic with, say,
!  the density at a face, -ffpe-trap=invalid stops the run right
!  there and the backtrace points at the guilty line.
!
!  Units follow the class convention: mm, us, g/cm^3, km/s, GPa.
!  (1 km/s = 1 mm/us, and GPa*cm^3/g = kJ/g = (km/s)^2.)
!  Masses are per unit cross-sectional area (planar 1-D), so a mass
!  is a density times a length: (g/cm^3)*mm.
!
!  RECOMMENDATION: stress (p, q, and any stress added later) lives at
!  the cell centers. When an update needs the stress acting across a
!  face (AV: the mass-weighted p plus the averaged q in the energy
!  update), compute it on the spot from the two cells on either side
!  of that face. That keeps one copy of every stress, so it can never
!  go stale, and the code reads term for term like the equation sheet.
!
!  THE ONE EXCEPTION, p_star (method RS). The Riemann solver's P* is
!  not a copy of a cell's stress: it is the SOLUTION of the Riemann
!  problem at the face, the pressure on the contact for the whole
!  step, n to n+1, and it is the momentum flux both neighbor cells
!  must use. It is stored at the face because
!    - each face is solved ONCE, so the cell on its left and the cell
!      on its right are guaranteed the same flux (that is what makes
!      momentum and energy conserved), and no Riemann solve is done
!      twice;
!    - it is written by the face loop every cycle BEFORE any cell
!      reads it, and nothing reads it after the cycle ends, so it can
!      not go stale: it is a flux for this step, not part of the state;
!    - u_star, its partner, must be stored anyway (it moves the face),
!      and the two belong together.
!  The cell's own P (from its EOS) still lives at the cell center.
!**********************************************************************!

!*** FACE slots (even i). Kinematics live on the faces.
integer(kind=int32), parameter :: jx      =  1 ! position x, mm
integer(kind=int32), parameter :: ju      =  2 ! velocity u, km/s
integer(kind=int32), parameter :: jx_old  =  3 ! x at the old time level
integer(kind=int32), parameter :: ju_old  =  4 ! u at the old time level
integer(kind=int32), parameter :: jmf     =  5 ! face (nodal) mass, half
                                               ! of each neighbor cell
                                               ! (jx, ju, jx_old, ju_old
                                               ! and jmf are AV's; RS
                                               ! uses jx and the two
                                               ! _star slots)
integer(kind=int32), parameter :: ju_star = 21 ! RS: u*, the Riemann
                                               ! solution's velocity on
                                               ! the contact, km/s; the
                                               ! face moves with it
                                               ! (n+1/2)
integer(kind=int32), parameter :: jp_star = 22 ! RS: P*, the Riemann
                                               ! solution's pressure on
                                               ! the contact, GPa (n+1/2;
                                               ! the exception above)

!*** CELL slots (odd i). Thermodynamics live at the cell centers.
integer(kind=int32), parameter :: jm      =  6 ! cell mass (fixed, it is
                                               ! a Lagrangian code)
integer(kind=int32), parameter :: jrho    =  7 ! density, g/cm^3
integer(kind=int32), parameter :: je      =  8 ! specific internal
                                               ! energy, kJ/g
integer(kind=int32), parameter :: jp      =  9 ! pressure, GPa
integer(kind=int32), parameter :: jq      = 10 ! artificial viscosity, GPa
integer(kind=int32), parameter :: jc      = 11 ! sound speed, km/s
integer(kind=int32), parameter :: jrho_old= 12 ! rho at the old time level
integer(kind=int32), parameter :: je_old  = 13 ! e at the old time level
                                               ! (add more _old slots
                                               ! here as the method
                                               ! needs them)
integer(kind=int32), parameter :: juc     = 23 ! RS: the cell-average
                                               ! velocity, km/s (RS's
                                               ! velocity lives in the
                                               ! cells; AV's on faces)
!*** RS: the states this cell offers its two faces' Riemann problems,
!*** at n+1/2: u and P on its LEFT face (_lf) and on its RIGHT face
!*** (_rf). Order 1: the cell's own u and P. Order 2: reconstructed
!*** with a Van Leer slope and advanced half a step (MUSCL-Hancock,
!*** module rs). Rewritten every cycle before any face reads them.
integer(kind=int32), parameter :: ju_lf   = 24 ! RS: u on the left face
integer(kind=int32), parameter :: ju_rf   = 25 ! RS: u on the right face
integer(kind=int32), parameter :: jp_lf   = 26 ! RS: P on the left face
integer(kind=int32), parameter :: jp_rf   = 27 ! RS: P on the right face

!*** MATERIAL slots (odd i). Option 6(a): each cell carries its own
!*** copy of its layer's Mie-Gruneisen constants, so a slice or a
!*** chunk is self-contained and my_fcn() never has to look anything
!*** up in the layer table. The names match the input deck keys.
integer(kind=int32), parameter :: jr0     = 14 ! R0, reference density
integer(kind=int32), parameter :: jc0     = 15 ! C0, bulk sound speed
integer(kind=int32), parameter :: js1     = 16 ! S1, Us-up slope
integer(kind=int32), parameter :: js2     = 17 ! S2, Us-up curvature
integer(kind=int32), parameter :: jg0     = 18 ! G0, Gruneisen gamma
integer(kind=int32), parameter :: jsp     = 20 ! spall_strength, GPa (> 0)

!*** DAMAGE slot (odd i). D = 0: intact, the cell holds tension down to
!*** -spall_strength. D = 1: broken (spalled, or stretched to void); its
!*** pressure is floored at 0 forever, but it can still be compressed
!*** and shocked (rubble). Real, not logical, so a gradual damage model
!*** can use values in between later. Written only by the cell's own
!*** state update (av_mod, cell_state), which keeps the write-back rule.
integer(kind=int32), parameter :: jdam    = 19 ! D, damage, 0 or 1

!*** Total number of variables (rows of the database). If you add a
!*** slot above, give it the next number, bump nvar, add its name to
!*** dbname below, and add it to face_slots or cell_slots. The compiler
!*** checks that dbname has nvar items; the setup audit in maincode
!*** checks that the two lists add up to nvar.
integer(kind=int32), parameter :: nvar    = 27

!*** Which slots a face fills, and which a real cell fills. The setup
!*** audit (maincode section 6) uses these to check that every slot a
!*** place should have was actually set.
!*** Both methods fill every slot at setup (each method then updates
!*** only its own), so these lists, the audit and the finite check do
!*** not depend on the method.
integer(kind=int32), parameter, dimension(7)  :: face_slots = (/ &
   jx, ju, jx_old, ju_old, jmf, ju_star, jp_star /)
integer(kind=int32), parameter, dimension(20) :: cell_slots = (/ &
   jm, jrho, je, jp, jq, jc, jrho_old, je_old, jr0, jc0, js1, js2, jg0, &
   jdam, jsp, juc, ju_lf, ju_rf, jp_lf, jp_rf /)

!*** Short names for each slot, in slot order. Used for output file
!*** headers, plot labels and the XDMF sidecar.
character(len=8), parameter, dimension(nvar) :: dbname = (/ &
   'x       ', 'u       ', 'x_old   ', 'u_old   ', 'mf      ', &
   'm       ', 'rho     ', 'e       ', 'p       ', 'q       ', &
   'c       ', 'rho_old ', 'e_old   ', 'R0      ', 'C0      ', &
   'S1      ', 'S2      ', 'G0      ', 'D       ', 'spall   ', &
   'u_star  ', 'p_star  ', 'uc      ', 'u_lf    ', 'u_rf    ', &
   'p_lf    ', 'p_rf    ' /)

!**********************************************************************!
! Data dictionary: stencil half-width for a chunk.
!
!  A chunk is a place plus ns neighbors on each side,
!
!     chunk(1:nvar, -ns:ns) = database(1:nvar, i-ns:i+ns)
!
!  so chunk(:,0) is the center, chunk(:,-1) the left neighbor and
!  chunk(:,+1) the right neighbor. ns = 2 because the energy update
!  (equation sheet, Step 2) for cell k uses p, q and M in cells k-1,
!  k and k+1 to build the stress across each face, plus the velocity
!  of the faces k-1/2 and k+1/2. In the interleaved database the next
!  cells over are i-2 and i+2:
!
!     i-2    i-1      i     i+1    i+2
!     k-1   k-1/2     k    k+1/2   k+1
!     cell  face    cell   face   cell
!
!  The two extra columns cost almost nothing: a chunk is 5 x nvar
!  doubles, tiny next to one equation-of-state call.
!
!***NOTE: the WRITE-BACK RULE that keeps a 5-wide chunk thread safe.
! Neighboring threads read the same places this thread is updating,
! so a loop must:
!   (1) write back ONLY the slots it updates, e.g. for the energy loop
!          database(je,i) = chunk(je,0)
!       and never the whole column, database(:,i) = chunk(:,0), which
!       would also rewrite the p and q that neighbors are reading; and
!   (2) never read a neighbor's copy of a slot that the same loop
!       writes (the energy loop writes e, so it must not use e from
!       chunk(:,-2) or chunk(:,+2)).
! Then every value a thread reads is one that no thread is changing.
!
!***NOTE: slice and chunk are NOT declared in this module on purpose.
! Module variables are shared by every OpenMP thread. Declare them
! locally in the routine that holds the parallel loop, and list them
! in PRIVATE( ), e.g.
!
!     real(kind=dp) :: slice(nvar), chunk(nvar,-ns:ns)
!     !$OMP PARALLEL DEFAULT(SHARED) PRIVATE(i,slice,chunk)
!**********************************************************************!
integer(kind=int32), parameter :: ns = 2

!**********************************************************************!
! Data dictionary: mesh sizes.
!**********************************************************************!
integer(kind=int32) :: nmat = 0  ! number of Material blocks in the deck
integer(kind=int32) :: nlay = 0  ! number of layers in the deck's Stack
integer(kind=int32) :: ntrc = 0  ! number of tracers in the deck's Run
integer(kind=int32) :: kmax = 0  ! number of real cells (all layers)
integer(kind=int32) :: imax = 0  ! last database index, 2*kmax+3

!**********************************************************************!
! Data dictionary: OpenMP settings.
!
!  These are set ONCE, in maincode section 3, before the time loop.
!  Module variables are shared by every thread, so they must only be
!  written outside a parallel region, or inside an OMP SINGLE block
!  (one thread writes, the rest wait). Never write them inside an
!  OMP DO loop.
!
!  The defaults describe a serial run, so a build without -fopenmp
!  (where every !$ line is just a comment) reports sensible values.
!**********************************************************************!
logical :: omp_on = .false.            ! true only in an -fopenmp build
integer(kind=int32) :: nproc       = 1 ! threads requested by the user
                                       ! (deck: Run num_threads;
                                       ! 0 means all processors)
integer(kind=int32) :: num_procs   = 1 ! processors the system reports
integer(kind=int32) :: max_threads = 1 ! threads the team will use,
                                       ! min(nproc,num_procs)
integer(kind=int32) :: num_threads = 1 ! threads counted by OpenMP
                                       ! inside a parallel region
integer(kind=int32) :: thread_num  = 0 ! the thread that ran SINGLE
integer(kind=int32) :: nalive      = 0 ! threads that actually showed
                                       ! up (each one adds 1)
integer(kind=int32) :: omp_min_zones = 2000 ! below this many cells the
                                       ! time loop runs on ONE thread,
                                       ! whatever num_threads says
                                       ! (deck: Run omp_min_zones)
!***NOTE: why 2000. The OpenMP timing study (NOTES_bitwhiz_Performance_
! IO_v1.md, section 2) found threads cost more than they save below
! about 2,000 zones on 4 cores: 945 zones ran at 0.92x of serial speed,
! 3,000 at 1.4x, 30,000 at 3.1x. Set it to 0 to force threads on any
! mesh (e.g. to test that threads reproduce the serial answer).

!**********************************************************************!
! Data dictionary: the heartbeat file.
!
!  The heartbeat is a small text file, <title>.heartbeat, that gets one
!  line per cycle while the run goes: cycle, time, time step and the
!  conservation checks. Watch it with "tail -f" in another terminal.
!  It is opened once the deck has been read (the title names it) and
!  closed at the end of the run.
!
!***NOTE: open(newunit=) hands out NEGATIVE unit numbers, so "is the
! file open?" is the logical hb_open, never a test on the unit number.
!**********************************************************************!
integer(kind=int32) :: khb      = 0            ! heartbeat unit number
logical             :: hb_open  = .false.      ! heartbeat file is open
character(len=64)   :: hb_file  = ' '          ! <title>.heartbeat

!**********************************************************************!
! Data dictionary: the input deck.
!
!  Everything below is filled by the deck reader (module deck, file
!  deck_mod.f95) and then left alone. The names match the deck keys
!  (input/README.md), so "R0 = 16.65" in the deck is R0 in the code.
!
!  Required values start as "unset" (a large negative number) so the
!  reader can tell "never given" from "given as zero". Use is_unset()
!  to test them. Optional values start at their documented defaults.
!
!  None of this is used inside the time loop: setup copies what the
!  solver needs into the database.
!**********************************************************************!
real(kind=dp), parameter :: unset = -huge(one) ! "not given in the deck"

!*** Where the deck came from, and its syntax version.
character(len=256)  :: deck_file    = ' '      ! as given on the command line
integer(kind=int32) :: deck_version = 0        ! must be 1

!*** Block "Run": what to run, for how long, on how many threads.
character(len=32)   :: title      = ' '        ! names the run's files
real(kind=dp)       :: t_end      = unset      ! us, termination time
integer(kind=int32) :: cycle_max  = 1000000    ! backstop on cycles
                                               ! (threads: nproc, above)
logical             :: plots_only = .false.    ! yes: no run, only re-draw
                                               ! the pictures from the
                                               ! files a run left

!*** Block "Output": what to write. Nothing given means nothing is
!*** written (except the heartbeat and the run log, which always are).
integer(kind=int32) :: plot_every = 0          ! snapshot every N cycles,
                                               ! 0 = off
real(kind=dp)       :: plot_dt    = zero       ! us, snapshot interval,
                                               ! 0 = off
integer(kind=int32) :: movie_frames = 0       ! frames of the pressure
                                               ! movie (P against x, from
                                               ! the snapshots), 2 to
                                               ! max_movie_frames, 0 = off
integer(kind=int32), parameter :: max_movie_frames = 50   ! so a deck
                                               ! cannot flood its folder
real(kind=dp)       :: tracer_dt  = zero       ! us, between rows of the
                                               ! tracer file, 0 = every
                                               ! cycle
character(len=80)   :: colormap   = 'viridis'  ! for bitmap pictures; a
                                               ! name bmpmaker knows
                                               ! (tracers: tracer table)
!*** The color range of each t-x diagram: from the data's min to its
!*** max (plot_range = full), or to the largest value the run held for
!*** 50 cycles (robust, the default: a start-up spike at an impact does
!*** not set the colors; module pics). The color window is a fraction
!*** of that range: the colors run from min + lo*(top - min) to
!*** min + hi*(top - min), and values beyond saturate. 0 <= lo < hi <= 1.
character(len=8)    :: plot_range = 'robust'   ! robust or full
real(kind=dp)       :: plot_u_lo  = zero       ! velocity, low end
real(kind=dp)       :: plot_u_hi  = one        ! velocity, high end
real(kind=dp)       :: plot_p_lo  = zero       ! pressure, low end
real(kind=dp)       :: plot_p_hi  = one        ! pressure, high end

!*** Block "Solver". method = AV: the artificial viscosity of the
!*** equation sheet,
!***    q = BL*rho*c*|du| + BQ*rho*du**2   (only while compressing),
!*** with the sheet's default coefficients. method = RS: Godunov's
!*** method with the acoustic Riemann solver at every face (module rs;
!*** BL and BQ are AV's and RS ignores them; order is RS's, AV ignores
!*** it).
character(len=8)    :: method     = 'AV'       ! 'AV' or 'RS'
integer(kind=int32) :: rs_order   = 2          ! RS only (deck: order):
                                               ! 1 = first order (the
                                               ! project's Option B),
                                               ! 2 = MUSCL-Hancock with a
                                               ! Van Leer limiter
real(kind=dp)       :: BL         = 0.1_dp     ! linear viscosity coef.
real(kind=dp)       :: BQ         = 2.0_dp     ! quadratic viscosity coef.
real(kind=dp)       :: CFL        = 0.6_dp     ! Courant safety factor

!*** Block "Stack" (the keys that are not inside a Layer).
real(kind=dp)       :: stack_resolution = zero ! zones/mm, 0 = not given
character(len=72)   :: origin     = ' '        ! location text, ' ' = none
real(kind=dp)       :: x_left     = zero       ! mm, x of the left face
logical             :: have_x_left = .false.   ! x_left given in the deck

!**********************************************************************!
! Data dictionary: the material table (one entry per Material block).
!
!  Mie-Gruneisen referenced to the principal Hugoniot (project rev-0,
!  Eq. 4), with Us = C0 + S1*up + (S2/C0)*up**2 and rho*Gamma = R0*G0.
!
!  The model (deck key eos; doc/design/materials.md). Both have the same
!  P and c, from the same code (module eos); mie_gruneisen_t also
!  carries each cell's temperature (module temperature), so it needs
!  CV and T0. The names are the deck's, in eos_names(model).
!**********************************************************************!
integer(kind=int32), parameter :: eos_mie_gruneisen   = 1  ! the default
integer(kind=int32), parameter :: eos_mie_gruneisen_t = 2  ! ... plus T
character(len=16), parameter, dimension(2) :: eos_names = (/ &
   'mie_gruneisen   ', 'mie_gruneisen_t ' /)

!*** A burn, and its products (deck keys burn and products; doc/design/
!*** materials.md, phase 3). A burn needs eos = mie_gruneisen_t (its
!*** closure needs the cold curve and T) and a products EOS, named in
!*** the deck: products has no default. Today there is one of each:
!*** HVRB (module hvrb) with ideal-gas products (module products). The
!*** names are the deck's, in burn_names and products_names.
integer(kind=int32), parameter :: burn_none          = 0  ! the default
integer(kind=int32), parameter :: burn_hvrb          = 1
integer(kind=int32), parameter :: products_none      = 0  ! the default
integer(kind=int32), parameter :: products_ideal_gas = 1
character(len=16), parameter, dimension(1) :: burn_names = (/ &
   'hvrb            ' /)
character(len=16), parameter, dimension(1) :: products_names = (/ &
   'ideal_gas       ' /)

type :: material_t
   character(len=32)   :: name   = ' '    ! from "Begin Material <name>"
   integer(kind=int32) :: eos    = eos_mie_gruneisen ! the model
   real(kind=dp)       :: R0     = unset  ! g/cm^3            REQUIRED
   real(kind=dp)       :: C0     = unset  ! km/s              REQUIRED
   real(kind=dp)       :: S1     = unset  ! -                 REQUIRED
   real(kind=dp)       :: S2     = zero   ! -                 optional
   real(kind=dp)       :: G0     = unset  ! -                 REQUIRED
   real(kind=dp)       :: spall_strength = 0.01_dp ! GPa      optional
                                          ! tension it holds before
                                          ! it breaks (a magnitude)
   real(kind=dp)       :: CV     = unset  ! J/(g K), as the deck gives
                                          ! it; mie_gruneisen_t only,
                                          ! and REQUIRED there
   real(kind=dp)       :: T0     = unset  ! K, at R0 and e = 0; ditto
   integer(kind=int32) :: burn     = burn_none      ! burn = hvrb
   integer(kind=int32) :: products = products_none  ! products = ideal_gas
   ! HVRB (burn = hvrb), each REQUIRED there and only there:
   real(kind=dp)       :: PR     = unset  ! GPa, reference pressure, > 0
   real(kind=dp)       :: ZR     = unset  ! pressure exponent, >= 0
   real(kind=dp)       :: MR     = unset  ! delay exponent, > 0
   real(kind=dp)       :: XR     = unset  ! completion exponent, > 0
   real(kind=dp)       :: PI     = unset  ! GPa, threshold, >= 0
   real(kind=dp)       :: TAU0   = unset  ! us, time constant, > 0
   ! The ideal-gas products (products = ideal_gas), ditto:
   real(kind=dp)       :: GAMMA  = unset  ! ratio of specific heats, > 1
   real(kind=dp)       :: Q      = unset  ! kJ/g (= MJ/kg), heat of
                                          ! reaction, >= 0
   integer(kind=int32) :: nused  = 0      ! layers that use it
   integer(kind=int32) :: line   = 0      ! deck line of its Begin
end type material_t

type(material_t), allocatable :: material(:)  ! material(1:nmat)

!**********************************************************************!
! Data dictionary: the layer table (one entry per Layer block).
!
!  Layers are listed left to right, all in contact. The deck gives the
!  geometry and the initial velocity; the material constants are copied
!  in from the material table once the deck is read (option 6(a): every
!  cell later carries its own copy).
!**********************************************************************!
type :: layer_t
   character(len=32)   :: name       = ' '    ! defaults to the material
   character(len=32)   :: matname    = ' '    ! "material =" as written
   integer(kind=int32) :: imat       = 0      ! index into material(:)
   real(kind=dp)       :: width      = unset  ! mm               REQUIRED
   real(kind=dp)       :: xvel       = zero   ! km/s, initial u  optional
   character(len=32)   :: xvel_from  = ' '    ! define name, if one used
   ! xvel_profile and xvel_amplitude (optional; module distributions,
   ! doc/design/distributions.md): u = xvel + du*( f - 1 ) across the
   ! layer. prof_name is blank for a uniform layer.
   character(len=16)   :: prof_name  = ' '    ! the distribution's name
   integer(kind=int32) :: prof_np    = 0      ! its number of parameters
   real(kind=dp)       :: prof_par(4) = zero  ! its parameters
   real(kind=dp)       :: xamp       = zero   ! km/s, du, if given
   logical             :: have_amp   = .false. ! xvel_amplitude given
   integer(kind=int32) :: line_amp   = 0      ! ... on this deck line
   real(kind=dp)       :: resolution = zero   ! zones/mm, 0 = not given
   integer(kind=int32) :: zones      = 0      ! zone count, 0 = not given
   ! Copied from the material table:
   real(kind=dp)       :: R0         = unset  ! g/cm^3
   real(kind=dp)       :: C0         = unset  ! km/s
   real(kind=dp)       :: S1         = unset  ! -
   real(kind=dp)       :: S2         = zero   ! -
   real(kind=dp)       :: G0         = unset  ! -
   real(kind=dp)       :: spall_strength = 0.01_dp ! GPa
   integer(kind=int32) :: eos        = eos_mie_gruneisen ! the model
   real(kind=dp)       :: cv         = zero   ! kJ/(g K): the deck's CV
                                              ! over 1000 (bitwhiz's e is
                                              ! in kJ/g); 0 = no T
   real(kind=dp)       :: T0         = zero   ! K; 0 = no T
   integer(kind=int32) :: burn       = burn_none      ! as the material's
   integer(kind=int32) :: products   = products_none
   real(kind=dp)       :: PR         = zero   ! the burn's and products'
   real(kind=dp)       :: ZR         = zero   ! constants, as the deck
   real(kind=dp)       :: MR         = zero   ! gives them (PR, PI in
   real(kind=dp)       :: XR         = zero   ! GPa; TAU0 in us; Q in
   real(kind=dp)       :: PI         = zero   ! kJ/g); all 0 for a layer
   real(kind=dp)       :: TAU0       = zero   ! that does not burn
   real(kind=dp)       :: GAMMA      = zero
   real(kind=dp)       :: Q          = zero
   ! Filled in once the whole deck is read:
   real(kind=dp)       :: xleft      = zero   ! mm, left face position
   integer(kind=int32) :: kfirst     = 0      ! first cell k of layer
   integer(kind=int32) :: klast      = 0      ! last cell k of layer
   integer(kind=int32) :: line       = 0      ! deck line of its Begin
end type layer_t

type(layer_t), allocatable :: layer(:)        ! layer(1:nlay)

!**********************************************************************!
! Data dictionary: the tracer table (one entry per "tracer =" line).
!
!  A tracer follows one material point. Its position is stored as the
!  face (node) just to its left plus a weight toward the next face:
!
!     u_tracer = (1-w)*u(face kface) + w*u(face kface+1)
!
!  where face "k" means face k+1/2 (database index iface(k)). A tracer
!  that sits exactly on a node has w = 0. Because the initial mesh is
!  uniform inside each layer, the length fraction equals the mass
!  fraction, so w never changes as the mesh moves. That keeps the same
!  material point at every resolution (needed for the convergence
!  study). kcell is the cell that holds the tracer, or 0 for a tracer
!  exactly on a node, which has a cell on each side.
!
!  Cell values (P, rho, e, q, c, D) come from ONE cell, kval: kcell
!  when the tracer is inside a cell. On a node, it is the cell on the
!  tracer's own layer's side: the cell to the LEFT of the node (the
!  same rule as ilay: a face belongs to the layer on its left), except
!  at its layer's left face ("A@0"), where the cell to the right is the
!  one in layer A. So "MatX:PMMA" reports MatX's cell, and "PMMA@0"
!  (the same node) reports PMMA's. No averaging across the node: rho,
!  e and c jump at an interface, and an average of two materials is
!  neither one.
!**********************************************************************!
integer(kind=int32), parameter :: loc_interface = 1  ! "A:B"
integer(kind=int32), parameter :: loc_fraction  = 2  ! "A@f"
integer(kind=int32), parameter :: loc_x         = 3  ! a number

type :: tracer_t
   character(len=32)   :: name   = ' '    ! heads its output columns
   character(len=72)   :: at     = ' '    ! the location as written
   integer(kind=int32) :: kind   = 0      ! loc_interface, _fraction, _x
   integer(kind=int32) :: lay    = 0      ! layer it is in (left layer
                                          ! for an interface)
   real(kind=dp)       :: x0     = zero   ! mm, initial position
   integer(kind=int32) :: kface  = 0      ! face just left (face k+1/2)
   real(kind=dp)       :: w      = zero   ! weight toward kface+1
   integer(kind=int32) :: kcell  = 0      ! cell that holds it, or 0
   integer(kind=int32) :: kval   = 0      ! cell whose values it reports
   integer(kind=int32) :: line   = 0      ! deck line
end type tracer_t

type(tracer_t), allocatable :: tracer(:)      ! tracer(1:ntrc)

!**********************************************************************!
! Data dictionary: the database and its integer companion.
!
!  database(nvar,imax) : all real data, see the slot list above.
!  ilay(imax)          : which layer each place belongs to (an integer,
!                        so it is kept OUT of the real database).
!                        Ghosts are 0. A face between two layers takes
!                        the layer on its LEFT; an interface is where
!                        ilay(i-1) /= ilay(i+1).
!
!  Memory: 8*nvar bytes per place, so about 410 KB for the 945-zone
!  class problem. It does not depend on nlay at all.
!
!***NOTE: a burn model can later get its own array with the SAME
! second dimension, e.g. burnbase(nbvar,imax), so that index i means
! the same place in both. It would follow the same rules: slot
! parameters, a name list, and its own alloc/dealloc pair.
!**********************************************************************!
real(kind=dp), allocatable :: database(:,:)
integer(kind=int32), allocatable :: ilay(:)

!***NOTE: for every subroutine that allocates memory, there should be
! a corresponding subroutine to deallocate that memory.
contains

   !**********************************************!
   ! Map a cell number k to its database index i. !
   ! k = 0 and k = kmax+1 are the ghost cells.    !
   !**********************************************!
   elemental function icell(k) result(i)
   implicit none
   integer(kind=int32), intent(in) :: k
   integer(kind=int32) :: i
   i = 2*k + 1
   end function icell

   !*****************************************************!
   ! Map face k+1/2 (between cells k and k+1) to its i.  !
   ! k = 0 is the left boundary face, k = kmax the right. !
   !*****************************************************!
   elemental function iface(k) result(i)
   implicit none
   integer(kind=int32), intent(in) :: k
   integer(kind=int32) :: i
   i = 2*k + 2
   end function iface

   !*************************************************!
   ! Go back from i to k. For a cell (odd i) this is !
   ! the cell number; for a face (even i) it is the  !
   ! k of the cell on the face's LEFT (face k+1/2).  !
   !*************************************************!
   elemental function kcell(i) result(k)
   implicit none
   integer(kind=int32), intent(in) :: i
   integer(kind=int32) :: k
   k = (i - 1)/2
   end function kcell

   !*****************************************!
   ! True if database index i is a cell (or  !
   ! ghost cell), false if it is a face.     !
   !*****************************************!
   elemental function is_cell(i) result(yes)
   implicit none
   integer(kind=int32), intent(in) :: i
   logical :: yes
   yes = ( mod(i,2) == 1 )
   end function is_cell

   !*************************************************!
   ! True if a layer value was never set by the deck. !
   ! (Testing x == unset directly works, but trips    !
   ! -Wcompare-reals; any value below -huge/2 can     !
   ! only be the sentinel.)                           !
   !*************************************************!
   elemental function is_unset(x) result(yes)
   implicit none
   real(kind=dp), intent(in) :: x
   logical :: yes
   yes = ( x < 0.5_dp*unset )
   end function is_unset

   !*****************************************************!
   ! True if x is NOT an ordinary finite number: a NaN   !
   ! (signaling or quiet) or an infinity. Used to check  !
   ! that setup left no slot at its signaling-NaN fill.  !
   !                                                     !
   ! Why not ieee_is_nan()? Asking a signaling NaN ANY   !
   ! question with floating-point hardware (a compare,   !
   ! ieee_is_nan, ieee_is_finite) raises "invalid", and  !
   ! -ffpe-trap=invalid then stops the run: the very     !
   ! thing we are trying to report. So we look at the    !
   ! bits instead, which is integer work and can never   !
   ! trap. In an IEEE double, NaN and infinity are the   !
   ! only values whose 11 exponent bits are all ones.    !
   !*****************************************************!
   elemental function not_finite(x) result(bad)
   use, intrinsic :: iso_fortran_env, only: int64
   implicit none
   real(kind=dp), intent(in) :: x
   logical :: bad
   integer(kind=int64) :: bits
   bits = transfer(x, bits)                    ! same 64 bits, as an integer
   bad  = ( iand(shiftr(bits, 52), 2047_int64) == 2047_int64 )
   end function not_finite

   !********************************************!
   ! Allocate the Layer Table (nlay entries).   !
   ! Every entry starts at the layer_t defaults. !
   !********************************************!
   subroutine alloc_layers(n,kerr)
   implicit none
   integer(kind=int32), intent(in) :: n       ! number of layers
   integer(kind=int32), intent(inout) :: kerr ! increment on failure
   integer(kind=int32) :: status

   if (allocated(layer)) return
   if (n < 1) then
      kerr = kerr+1                           ! a Stack needs a layer
      return
   end if

   allocate( layer(n), stat=status )
   mem_fail: if (status /= 0) then
      kerr = kerr+1
   else
      nlay = n
   end if mem_fail

   return
   end subroutine alloc_layers

   !******************************!
   ! Deallocate the Layer Table.  !
   !******************************!
   subroutine dealloc_layers(kerr)
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status

   if (allocated(layer)) then
      deallocate(layer,stat=status)
      mem_fail: if (status /= 0) then
         kerr = kerr+1
      else
         nlay = 0
      end if mem_fail
   end if

   return
   end subroutine dealloc_layers

   !**********************************************!
   ! Allocate the Material Table (nmat entries).  !
   ! Every entry starts at the material_t defaults. !
   !**********************************************!
   subroutine alloc_materials(n,kerr)
   implicit none
   integer(kind=int32), intent(in) :: n       ! number of materials
   integer(kind=int32), intent(inout) :: kerr ! increment on failure
   integer(kind=int32) :: status

   if (allocated(material)) return
   if (n < 1) then
      kerr = kerr+1                           ! a deck needs a material
      return
   end if

   allocate( material(n), stat=status )
   mem_fail: if (status /= 0) then
      kerr = kerr+1
   else
      nmat = n
   end if mem_fail

   return
   end subroutine alloc_materials

   !*******************************!
   ! Deallocate the Material Table. !
   !*******************************!
   subroutine dealloc_materials(kerr)
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status

   if (allocated(material)) then
      deallocate(material,stat=status)
      mem_fail: if (status /= 0) then
         kerr = kerr+1
      else
         nmat = 0
      end if mem_fail
   end if

   return
   end subroutine dealloc_materials

   !*********************************************!
   ! Allocate the Tracer Table (ntrc entries).   !
   ! Zero tracers is allowed (a size-0 table).   !
   !*********************************************!
   subroutine alloc_tracers(n,kerr)
   implicit none
   integer(kind=int32), intent(in) :: n       ! number of tracers
   integer(kind=int32), intent(inout) :: kerr ! increment on failure
   integer(kind=int32) :: status

   if (allocated(tracer)) return
   if (n < 0) then
      kerr = kerr+1
      return
   end if

   allocate( tracer(n), stat=status )
   mem_fail: if (status /= 0) then
      kerr = kerr+1
   else
      ntrc = n
   end if mem_fail

   return
   end subroutine alloc_tracers

   !*****************************!
   ! Deallocate the Tracer Table. !
   !*****************************!
   subroutine dealloc_tracers(kerr)
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status

   if (allocated(tracer)) then
      deallocate(tracer,stat=status)
      mem_fail: if (status /= 0) then
         kerr = kerr+1
      else
         ntrc = 0
      end if mem_fail
   end if

   return
   end subroutine dealloc_tracers

   !**********************************************************!
   ! Allocate the Database for kmax real cells, and fill it   !
   ! with signaling NaN.                                      !
   !                                                          !
   ! Why fill it? -finit-real=snan only covers ordinary local !
   ! variables; ALLOCATED arrays start with whatever was in   !
   ! memory. Filling with signaling NaN means any slot that   !
   ! setup forgets to set, or any face/cell slot mix-up,      !
   ! traps with -ffpe-trap=invalid the first time it is used  !
   ! in arithmetic. (Plain copies like slice = database(:,i)  !
   ! do not trap; only math and comparisons on the NaN do.)   !
   !**********************************************************!
   subroutine alloc_database(nk,kerr)
   use, intrinsic :: ieee_arithmetic, only: ieee_value, &
      ieee_signaling_nan
   implicit none
   integer(kind=int32), intent(in) :: nk      ! number of real cells
   integer(kind=int32), intent(inout) :: kerr ! increment on failure
   integer(kind=int32) :: status
   real(kind=dp) :: snan

   if (allocated(database)) return
   if (nk < 1) then
      kerr = kerr+1                           ! need at least one cell
      return
   end if

   kmax = nk
   imax = 2*kmax + 3                          ! G F C F ... C F G

   allocate( database(nvar,imax), ilay(imax), stat=status )
   mem_fail: if (status /= 0) then
      kerr = kerr+1
      kmax = 0
      imax = 0
   else
      snan = ieee_value( snan, ieee_signaling_nan )
      database = snan                         ! "not set yet" everywhere
      ilay = 0                                ! ghosts stay 0
   end if mem_fail

   return
   end subroutine alloc_database

   !**************************!
   ! Deallocate the Database. !
   !**************************!
   subroutine dealloc_database(kerr)
   implicit none
   integer(kind=int32), intent(inout) :: kerr
   integer(kind=int32) :: status

   if (allocated(database)) then
      deallocate(database,ilay,stat=status)
      mem_fail: if (status /= 0) then
         kerr = kerr+1
      else
         kmax = 0
         imax = 0
      end if mem_fail
   end if

   return
   end subroutine dealloc_database

end module shock

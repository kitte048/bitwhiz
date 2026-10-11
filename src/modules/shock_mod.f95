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
!  bits, so there is exactly one definition of dp in the code. We do
!  NOT take the rest of bits, because it declares module-level loop
!  counters (i, j, k, ii, jj, kk). Module variables are SHARED between
!  OpenMP threads, so a solver loop that silently used bits' "i"
!  would be a race condition. Every loop index in the solver must be
!  a local variable of the routine that runs the loop.
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
!**********************************************************************!

!*** FACE slots (even i). Kinematics live on the faces.
integer(kind=int32), parameter :: jx      =  1 ! position x, mm
integer(kind=int32), parameter :: ju      =  2 ! velocity u, km/s
integer(kind=int32), parameter :: jx_old  =  3 ! x at the old time level
integer(kind=int32), parameter :: ju_old  =  4 ! u at the old time level
integer(kind=int32), parameter :: jsf     =  5 ! face stress sigma_f, GPa
                                               ! (mass-weighted p, plus q)
integer(kind=int32), parameter :: jmf     =  6 ! face (nodal) mass, half
                                               ! of each neighbor cell

!*** CELL slots (odd i). Thermodynamics live at the cell centers.
integer(kind=int32), parameter :: jm      =  7 ! cell mass (fixed, it is
                                               ! a Lagrangian code)
integer(kind=int32), parameter :: jrho    =  8 ! density, g/cm^3
integer(kind=int32), parameter :: je      =  9 ! specific internal
                                               ! energy, kJ/g
integer(kind=int32), parameter :: jp      = 10 ! pressure, GPa
integer(kind=int32), parameter :: jq      = 11 ! artificial viscosity, GPa
integer(kind=int32), parameter :: jc      = 12 ! sound speed, km/s
integer(kind=int32), parameter :: jrho_old= 13 ! rho at the old time level
integer(kind=int32), parameter :: je_old  = 14 ! e at the old time level
                                               ! (add more _old slots
                                               ! here as the method
                                               ! needs them)

!*** MATERIAL slots (odd i). Option 6(a): each cell carries its own
!*** copy of its layer's Mie-Gruneisen constants, so a slice or a
!*** chunk is self-contained and my_fcn() never has to look anything
!*** up in the layer table. The names match the input deck keys.
integer(kind=int32), parameter :: jr0     = 15 ! R0, reference density
integer(kind=int32), parameter :: jc0     = 16 ! C0, bulk sound speed
integer(kind=int32), parameter :: js1     = 17 ! S1, Us-up slope
integer(kind=int32), parameter :: js2     = 18 ! S2, Us-up curvature
integer(kind=int32), parameter :: jg0     = 19 ! G0, Gruneisen gamma

!*** Total number of variables (rows of the database). If you add a
!*** slot above, give it the next number, bump nvar, and add its name
!*** to dbname below. The compiler checks that dbname has nvar items.
integer(kind=int32), parameter :: nvar    = 19

!*** Short names for each slot, in slot order. Used for output file
!*** headers, plot labels and the XDMF sidecar.
character(len=8), parameter, dimension(nvar) :: dbname = (/ &
   'x       ', 'u       ', 'x_old   ', 'u_old   ', 'sf      ', &
   'mf      ', 'm       ', 'rho     ', 'e       ', 'p       ', &
   'q       ', 'c       ', 'rho_old ', 'e_old   ', 'R0      ', &
   'C0      ', 'S1      ', 'S2      ', 'G0      ' /)

!**********************************************************************!
! Data dictionary: stencil half-width for a chunk.
!
!  A chunk is a place plus ns neighbors on each side,
!
!     chunk(1:nvar, -ns:ns) = database(1:nvar, i-ns:i+ns)
!
!  so chunk(:,0) is the center, chunk(:,-1) the left neighbor and
!  chunk(:,+1) the right neighbor. ns = 2 because the energy update
!  at a cell needs the NEXT cells over (i-2 and i+2), not just the
!  faces on either side (i-1 and i+1).
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
integer(kind=int32) :: nlay = 0  ! number of layers in the deck's Stack
integer(kind=int32) :: kmax = 0  ! number of real cells (all layers)
integer(kind=int32) :: imax = 0  ! last database index, 2*kmax+3

!**********************************************************************!
! Data dictionary: the layer table (user input, one entry per layer).
!
!  One New_Layer block in the deck fills one layer_t. Names match the
!  deck keys. Required keys start as "unset" (a large negative number)
!  so the deck reader can tell "never given" from "given as zero".
!  Optional keys start at their documented defaults.
!
!  The table is small (nlay entries) and is NOT used inside the time
!  loop: setup copies the material constants into the database.
!**********************************************************************!
real(kind=dp), parameter :: unset = -huge(one) ! "not given in the deck"

type :: layer_t
   character(len=32)   :: name       = ' '    ! optional label
   real(kind=dp)       :: width      = unset  ! mm               REQUIRED
   real(kind=dp)       :: xvel       = zero   ! km/s, initial u  optional
   real(kind=dp)       :: resolution = zero   ! zones per mm  } one of
   integer(kind=int32) :: zones      = 0      ! zone count    } these two
   real(kind=dp)       :: R0         = unset  ! g/cm^3           REQUIRED
   real(kind=dp)       :: C0         = unset  ! km/s             REQUIRED
   real(kind=dp)       :: S1         = unset  ! -                REQUIRED
   real(kind=dp)       :: S2         = zero   ! s/km             optional
   real(kind=dp)       :: G0         = unset  ! -                REQUIRED
   ! Filled in by setup, not by the deck:
   real(kind=dp)       :: xleft      = zero   ! mm, left face position
   integer(kind=int32) :: kfirst     = 0      ! first cell k of layer
   integer(kind=int32) :: klast      = 0      ! last cell k of layer
end type layer_t

type(layer_t), allocatable :: layer(:)        ! layer(1:nlay)

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
!  Memory: 8*nvar bytes per place, so about 300 KB for the 945-zone
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

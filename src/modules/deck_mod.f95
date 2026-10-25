module deck
!**********************************************************************!
!
!  Purpose:
!    Read a bitwhiz input deck (deck_version 1), check every line of it,
!    and fill the input tables in the shock module: the run and solver
!    settings, the material table, the layer table and the tracer table.
!    Then write the "resolved deck": the same run with every default
!    filled in, which re-reads to exactly the same tables.
!
!    The syntax is specified in input/README.md. If this file and that
!    page ever disagree, fix one of them on purpose.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/11/26    D. E. Kittell        Original code
!                (with Claude)
!    10/13/26    D. E. Kittell        Output block (tracer, plot_every,
!                (with Claude)        plot_dt, colormap); a key in the
!                                     wrong block names its home block
!    10/13/26    D. E. Kittell        Hardening: a folder, an empty
!                (with Claude)        file or an unreadable file each
!                                     says so; maintainer notes added
!    10/15/26    D. E. Kittell        Run block: omp_min_zones
!                (with Claude)
!    10/15/26    D. E. Kittell        Material block: spall_strength
!                (with Claude)
!    10/15/26    D. E. Kittell        Output block: tracer_dt
!                (with Claude)
!    10/15/26    D. E. Kittell        Solver block: method = RS (Riemann
!                (with Claude)        solver, under construction)
!    10/20/26    D. E. Kittell        Solver block: order (RS only;
!                (with Claude)        1 or 2, default 2)
!    10/20/26    D. E. Kittell        Run block: plots_only (yes, no);
!                (with Claude)        Output block: plot_u_lo, plot_u_hi,
!                                     plot_p_lo, plot_p_hi (0 to 1, lo
!                                     below hi); fmt_real and get_line
!                                     are public (module pics)
!    10/24/26    D. E. Kittell        Output block: plot_range (robust,
!                (with Claude)        full)
!
!**********************************************************************!
!
!  HOW THE READER WORKS
!  ====================
!  The deck is read in four stages. Each stage only starts if the one
!  before it could do its job, but every stage reports ALL the problems
!  it finds before stopping, so one run lists every mistake in a deck.
!
!   1. LINES      read_lines: read the file, strip comments ('#'), tabs
!                 and Windows line endings, check line length and
!                 characters, and keep only the statements between
!                 "Begin bitwhiz" and "End bitwhiz".
!
!   2. COUNT      count_blocks: count Material blocks, Layer blocks and
!                 tracer lines so the tables can be allocated once.
!
!   3. STATEMENTS parse_statements: walk the statements with a stack of
!                 open blocks. Every "key = value" is checked against
!                 the keys its block allows, its value is checked
!                 (number, integer, name, ...), and it is stored in the
!                 shock module. Duplicates and missing keys are caught.
!
!   4. RESOLVE    resolve_deck: things that need the whole deck. Layers
!                 find their materials, layer names are settled, zone
!                 counts and positions are computed, the origin is
!                 applied, and every tracer is located on the mesh.
!
!  Every message names the deck file and line, e.g.
!
!     input/foo.deck:23: error: R0 = "abc" is not a number
!
!  DESIGN RULES (keep these when changing the reader)
!  ==================================================
!   - A key matches only itself: no matching on the first few letters,
!     which once let "ng" also match "ngrains" in an older reader.
!   - Anything the reader does not recognize is an error, never
!     silently skipped. A typo must stop the run, not change it.
!   - Values land in named variables and tables in the shock module,
!     never in a numbered ui(:) array.
!   - Every message carries the deck file name and line number.
!
!  MAINTAINER NOTES: adding a new deck key
!  =======================================
!  A new key touches six places. Miss one and either the key is
!  rejected, or it works but is lost from the resolved deck.
!   1. shock_mod: a variable with the key's name and its default,
!      with units in the comment.
!   2. key_<block> (below): a case that checks and stores the value.
!   3. The "allowed:" list in that routine's unknown_key call.
!   4. home_block: the key's block, so a misplaced key says where it
!      belongs.
!   5. write_resolved_deck: echo it, so the resolved deck still
!      reproduces the run (tests/run_deck_tests.sh checks this).
!   6. input/README.md: the key's row in its block's table. Then add a
!      test deck or two in tests/decks/ (an "# expect:" line on top).
!
!**********************************************************************!
use bits,  only: dp, int32, int64, zero, one, kpt6, nline
use shock
implicit none
private

public :: read_deck, write_resolved_deck, fmt_real, get_line

!**********************************************************************!
! Data dictionary: limits.
!**********************************************************************!
integer(kind=int32), parameter :: namelen  = 32   ! longest name
integer(kind=int32), parameter :: wordlen  = 72   ! longest word (a location)
integer(kind=int32), parameter :: maxdef   = 100  ! most defines
integer(kind=int32), parameter :: maxkeys  = 32   ! keys per block
integer(kind=int32), parameter :: maxdepth = 8    ! block nesting
integer(kind=int32), parameter :: maxerr   = 50   ! stop listing after
integer(kind=int32), parameter :: maxzones = 10000000 ! sanity cap

!**********************************************************************!
! Data dictionary: block types (what the "Begin" line opened).
!**********************************************************************!
integer(kind=int32), parameter :: bk_skip     = 0  ! unknown: skip it
integer(kind=int32), parameter :: bk_bitwhiz  = 1
integer(kind=int32), parameter :: bk_run      = 2
integer(kind=int32), parameter :: bk_solver   = 3
integer(kind=int32), parameter :: bk_material = 4
integer(kind=int32), parameter :: bk_stack    = 5
integer(kind=int32), parameter :: bk_layer    = 6
integer(kind=int32), parameter :: bk_output   = 7

!**********************************************************************!
! Data dictionary: the statements kept from the file.
!
!  One entry per non-blank line between "Begin bitwhiz" and
!  "End bitwhiz", with its comment removed and its line number kept.
!**********************************************************************!
type :: stmt_t
   integer(kind=int32)  :: line = 0
   character(len=nline) :: text = ' '
end type stmt_t

type(stmt_t), allocatable :: stmt(:)
integer(kind=int32) :: nstmt = 0

!**********************************************************************!
! Data dictionary: the defines ("define u_fly = 2.00").
!**********************************************************************!
character(len=namelen) :: def_name(maxdef) = ' '
real(kind=dp)          :: def_val(maxdef)  = zero
integer(kind=int32)    :: def_line(maxdef) = 0
integer(kind=int32)    :: ndef = 0

!**********************************************************************!
! Data dictionary: the stack of open blocks while parsing.
!**********************************************************************!
type :: open_t
   integer(kind=int32)    :: kind  = bk_skip
   character(len=namelen) :: word  = ' '   ! block word as written
   integer(kind=int32)    :: line  = 0     ! line of its Begin
   integer(kind=int32)    :: nseen = 0     ! keys seen in this block
   character(len=namelen) :: seen(maxkeys) = ' '
end type open_t

type(open_t)        :: blk(maxdepth)
integer(kind=int32) :: depth = 0

!**********************************************************************!
! Data dictionary: bookkeeping.
!**********************************************************************!
integer(kind=int32) :: nerr  = 0   ! errors found so far
integer(kind=int32) :: nwarn = 0   ! warnings found so far
integer(kind=int32) :: line_run = 0, line_solver = 0, line_stack = 0
integer(kind=int32) :: line_output = 0
integer(kind=int32) :: line_version = 0
integer(kind=int32) :: line_origin  = 0, line_xleft = 0
integer(kind=int32) :: line_ulo = 0, line_uhi = 0  ! color windows
integer(kind=int32) :: line_plo = 0, line_phi = 0
integer(kind=int32) :: imat_now = 0, ilay_now = 0  ! block being filled
logical             :: tend_given = .false.        ! t_end appeared

contains

!======================================================================!
!  PUBLIC: read the deck.                                              !
!======================================================================!

   !*******************************************************************!
   ! Read, check and resolve the deck in file fname. On return, kerr   !
   ! holds the number of errors found (0 means the shock module tables !
   ! are complete and consistent). Messages go to the terminal.        !
   !*******************************************************************!
   subroutine read_deck(fname, kerr)
   implicit none
   character(len=*), intent(in) :: fname
   integer(kind=int32), intent(out) :: kerr
   integer(kind=int32) :: nm, nl, nt, kalloc

   nerr  = 0
   nwarn = 0
   deck_file = fname

   ! Stage 1: lines.
   call read_lines(fname)
   if (nerr > 0 .or. nstmt == 0) then
      kerr = max(nerr,1)
      return
   end if

   ! Stage 2: count, then allocate the tables once.
   call count_blocks(nm, nl, nt)
   kalloc = 0
   if (nm > 0) call alloc_materials(nm, kalloc)
   if (nl > 0) call alloc_layers(nl, kalloc)
   call alloc_tracers(nt, kalloc)
   if (kalloc /= 0) then
      call deck_error(0, 'could not allocate the input tables')
      kerr = nerr
      return
   end if
   nmat = 0      ! the tables are refilled as the blocks are read
   nlay = 0
   ntrc = 0

   ! Stage 3: statements.
   call parse_statements()

   ! Stage 4: resolve (only if the statements were clean, because the
   ! checks below assume every block and key is where it should be).
   if (nerr == 0) call resolve_deck()

   if (nerr == 0 .and. (nmat /= nm .or. nlay /= nl .or. ntrc /= nt)) &
      call deck_error(0, 'internal: table counts do not match')

   kerr = nerr
   return
   end subroutine read_deck

!======================================================================!
!  STAGE 1: LINES                                                      !
!======================================================================!

   !*******************************************************************!
   ! Read the whole file. Keep the statements between "Begin bitwhiz"  !
   ! and "End bitwhiz"; stop reading at "End bitwhiz" (anything after  !
   ! it is free space for notes).                                      !
   !*******************************************************************!
   subroutine read_lines(fname)
   implicit none
   character(len=*), intent(in) :: fname
   character(len=:), allocatable :: raw
   character(len=nline) :: text
   integer(kind=int32) :: lu, ios, n, ic, k
   logical :: started, ended, eof, bad, isdir

   nstmt = 0
   if (allocated(stmt)) deallocate(stmt)
   allocate(stmt(64))

   ! A folder is not a deck. Standard Fortran cannot ask "is this a
   ! folder?", so we use the usual POSIX trick: "name/." exists only
   ! when name is a folder. (gfortran on a folder happily opens it and
   ! then reports end-of-file, which would look like an empty deck.)
   inquire(file=trim(fname)//'/.', exist=isdir)
   if (isdir) then
      call deck_error(0, '"'//trim(fname)//'" is a folder, not a deck file')
      return
   end if

   open(newunit=lu, file=fname, status='old', action='read', &
        iostat=ios)
   if (ios /= 0) then
      call deck_error(0, 'cannot open the deck file "'//trim(fname)//'"')
      return
   end if

   started = .false.
   ended   = .false.
   n = 0
   read_loop: do
      call get_line(lu, raw, eof, bad)
      if (bad) then
         call deck_error(n+1, 'cannot read the deck file (is it a '// &
            'folder, or not a text file?)')
         close(lu)
         return
      end if
      if (eof) exit read_loop
      n = n + 1

      ! Tabs become spaces; carriage returns (Windows) are removed.
      do ic = 1, len(raw)
         if (raw(ic:ic) == achar(9))  raw(ic:ic) = ' '
         if (raw(ic:ic) == achar(13)) raw(ic:ic) = ' '
      end do

      if (len_trim(raw) > nline) then
         call deck_error(n, 'line is longer than 200 characters')
         cycle read_loop
      end if

      ! Cut the comment, then left-justify.
      k = index(raw, '#')
      if (k > 0) then
         text = raw(1:k-1)
      else
         text = raw
      end if
      text = adjustl(text)
      if (len_trim(text) == 0) cycle read_loop

      ! Statements must be plain printable ASCII (comments may hold
      ! anything, e.g. a pasted degree sign).
      do ic = 1, len_trim(text)
         if (iachar(text(ic:ic)) < 32 .or. iachar(text(ic:ic)) > 126) then
            call deck_error(n, 'a character that is not plain ASCII '// &
               '(a pasted symbol or curly quote?) is outside a comment')
            cycle read_loop
         end if
      end do

      if (.not. started) then
         if (is_block_line(text, 'begin', 'bitwhiz')) then
            started = .true.
            call add_stmt(n, text)
         else
            call deck_error(n, 'only comments may come before '// &
               '"Begin bitwhiz"')
         end if
         cycle read_loop
      end if

      call add_stmt(n, text)
      if (is_block_line(text, 'end', 'bitwhiz')) then
         ended = .true.
         exit read_loop
      end if
   end do read_loop
   close(lu)

   if (n == 0) then
      call deck_error(0, 'the deck file is empty')
   else if (.not. started) then
      call deck_error(0, 'no "Begin bitwhiz" line found')
   else if (.not. ended) then
      call deck_error(n, 'the deck ends without "End bitwhiz"')
   end if

   return
   end subroutine read_lines

   !*******************************************************************!
   ! Read one line of any length (non-advancing reads, in pieces).     !
   ! eof is set at the end of the file. bad is set if the file cannot  !
   ! be read at all (e.g. the "deck" is a folder); the caller reports  !
   ! it, so a bad file is never mistaken for an empty one.             !
   !*******************************************************************!
   subroutine get_line(lu, line, eof, bad)
   implicit none
   integer(kind=int32), intent(in) :: lu
   character(len=:), allocatable, intent(out) :: line
   logical, intent(out) :: eof, bad
   character(len=256) :: piece
   integer(kind=int32) :: ios, nread

   line = ''
   eof  = .false.
   bad  = .false.
   do
      read(lu, '(a)', advance='no', iostat=ios, size=nread) piece
      if (is_iostat_end(ios)) then
         eof = (len(line) == 0)   ! a last line with no newline still counts
         return
      end if
      line = line // piece(1:nread)
      if (is_iostat_eor(ios)) return
      if (ios /= 0) then          ! a read error, not the end of the file
         eof = .true.
         bad = .true.
         return
      end if
   end do
   end subroutine get_line

   !*******************************************************************!
   ! Append one statement, growing the list when it fills up.          !
   !*******************************************************************!
   subroutine add_stmt(n, text)
   implicit none
   integer(kind=int32), intent(in) :: n
   character(len=*), intent(in) :: text
   type(stmt_t), allocatable :: tmp(:)

   if (nstmt == size(stmt)) then
      allocate(tmp(2*size(stmt)))
      tmp(1:nstmt) = stmt(1:nstmt)
      call move_alloc(tmp, stmt)
   end if
   nstmt = nstmt + 1
   stmt(nstmt)%line = n
   stmt(nstmt)%text = text
   end subroutine add_stmt

   !*******************************************************************!
   ! True if text is exactly "<w1> <w2>" (any case, any spacing).      !
   !*******************************************************************!
   logical function is_block_line(text, w1, w2)
   implicit none
   character(len=*), intent(in) :: text, w1, w2
   character(len=wordlen) :: words(4)
   integer(kind=int32) :: nw
   call split_words(text, words, nw)
   is_block_line = (nw == 2)
   if (is_block_line) is_block_line = &
      (lower(words(1)) == w1 .and. lower(words(2)) == w2)
   end function is_block_line

!======================================================================!
!  STAGE 2: COUNT                                                      !
!======================================================================!

   !*******************************************************************!
   ! Count Material blocks, Layer blocks and tracer lines, so each     !
   ! table is allocated once, at its final size.                       !
   !*******************************************************************!
   subroutine count_blocks(nm, nl, nt)
   implicit none
   integer(kind=int32), intent(out) :: nm, nl, nt
   character(len=wordlen) :: words(4)
   character(len=nline) :: key, val
   integer(kind=int32) :: is, nw
   logical :: iskv

   nm = 0
   nl = 0
   nt = 0
   do is = 1, nstmt
      call split_words(stmt(is)%text, words, nw)
      if (nw >= 2 .and. lower(words(1)) == 'begin') then
         if (lower(words(2)) == 'material') nm = nm + 1
         if (lower(words(2)) == 'layer')    nl = nl + 1
      else
         call split_kv(stmt(is)%text, key, val, iskv)
         if (iskv .and. lower(key) == 'tracer') nt = nt + 1
      end if
   end do
   end subroutine count_blocks

!======================================================================!
!  STAGE 3: STATEMENTS                                                 !
!======================================================================!

   !*******************************************************************!
   ! Walk the statements with a stack of open blocks.                  !
   !*******************************************************************!
   subroutine parse_statements()
   implicit none
   character(len=wordlen) :: words(4)
   character(len=nline) :: key, val
   integer(kind=int32) :: is, nw, ln
   logical :: iskv

   depth = 0
   ndef  = 0
   line_run = 0; line_solver = 0; line_stack = 0; line_version = 0
   line_output = 0
   line_origin = 0; line_xleft = 0
   imat_now = 0; ilay_now = 0
   tend_given = .false.

   do is = 1, nstmt
      ln = stmt(is)%line
      call split_words(stmt(is)%text, words, nw)

      select case (lower(words(1)))
      case ('begin')
         call do_begin(ln, words, nw)
      case ('end')
         call do_end(ln, words, nw)
      case ('define')
         if (depth > 0) then
            if (blk(depth)%kind == bk_skip) cycle
         end if
         call do_define(ln, stmt(is)%text)
      case default
         if (depth > 0) then
            if (blk(depth)%kind == bk_skip) cycle   ! inside a bad block
         end if
         call split_kv(stmt(is)%text, key, val, iskv)
         if (iskv) then
            call do_key(ln, key, val)
         else
            call bad_kv(ln, stmt(is)%text)
         end if
      end select
   end do

   ! "End bitwhiz" is the last statement; anything still open is an
   ! error (do_end reports those).

   ! Blocks and keys that must appear somewhere in the deck.
   if (line_version == 0) call deck_error(0, &
      'deck_version = 1 is required (first lines of the deck)')
   if (line_run == 0) call deck_error(0, &
      'no Run block (it holds the required key t_end)')
   if (line_run > 0 .and. .not. tend_given) call deck_error(line_run, &
      't_end is required in the Run block')
   if (nmat == 0) call deck_error(0, 'no Material blocks')
   if (line_stack == 0) then
      call deck_error(0, 'no Stack block')
   else if (nlay == 0) then
      call deck_error(line_stack, 'the Stack has no Layer blocks')
   end if

   return
   end subroutine parse_statements

   !*******************************************************************!
   ! "Begin <block> [name]"                                            !
   !*******************************************************************!
   subroutine do_begin(ln, words, nw)
   implicit none
   integer(kind=int32), intent(in) :: ln, nw
   character(len=wordlen), intent(in) :: words(4)
   character(len=namelen) :: bw
   integer(kind=int32) :: parent, newkind, im

   if (nw < 2) then
      call deck_error(ln, '"Begin" needs a block name')
      call push_block(bk_skip, 'unknown', ln)
      return
   end if
   bw = lower(words(2))

   ! Inside a block being skipped, just track nesting.
   if (depth > 0) then
      if (blk(depth)%kind == bk_skip) then
         call push_block(bk_skip, words(2), ln)
         return
      end if
      parent = blk(depth)%kind
   else
      parent = -1    ! nothing open yet: only "Begin bitwhiz" is allowed
   end if

   newkind = bk_skip
   select case (bw)
   case ('bitwhiz')
      if (parent /= -1) then
         call deck_error(ln, '"Begin bitwhiz" may only appear once '// &
            '(this line is ignored)')
         return
      else
         newkind = bk_bitwhiz
      end if
   case ('run', 'output', 'solver', 'stack')
      if (parent /= bk_bitwhiz) then
         call deck_error(ln, 'Begin '//trim(words(2))// &
            ' must be at the top level of the deck')
      else
         newkind = bk_run
         if (bw == 'output') newkind = bk_output
         if (bw == 'solver') newkind = bk_solver
         if (bw == 'stack')  newkind = bk_stack
         call once_only(ln, newkind)
      end if
   case ('material')
      if (parent /= bk_bitwhiz) then
         call deck_error(ln, 'Begin Material must be at the top level '// &
            'of the deck')
      else if (nw < 3) then
         call deck_error(ln, 'Begin Material needs a name, e.g. '// &
            '"Begin Material Ta"')
      else if (.not. is_name(words(3))) then
         call deck_error(ln, '"'//trim(words(3))//'" is not a valid '// &
            'name (a letter, then letters, digits or _, at most 32)')
      else
         im = find_material(words(3))
         if (im > 0) then
            call deck_error(ln, 'Material '//trim(words(3))// &
               ' is already defined on line '//itoa(material(im)%line))
         else
            newkind = bk_material
            nmat = nmat + 1
            material(nmat)%name = words(3)(1:namelen)
            material(nmat)%line = ln
            imat_now = nmat
         end if
      end if
   case ('layer')
      if (parent /= bk_stack) then
         call deck_error(ln, 'Begin Layer must be inside the Stack block')
      else
         newkind = bk_layer
         nlay = nlay + 1
         layer(nlay)%line = ln
         ilay_now = nlay
      end if
   case default
      call deck_error(ln, 'unknown block "'//trim(words(2))// &
         '" (blocks: Run, Output, Solver, Material, Stack, Layer)')
   end select

   ! A name on the Begin line is only allowed for Material.
   if (newkind /= bk_skip .and. newkind /= bk_material .and. nw > 2) &
      call deck_error(ln, 'Begin '//trim(words(2))//' does not take a name')
   if (nw > 3) call deck_error(ln, 'too many words on the Begin line')

   call push_block(newkind, words(2), ln)
   end subroutine do_begin

   !*******************************************************************!
   ! Run, Output, Solver and Stack may each appear only once.          !
   !*******************************************************************!
   subroutine once_only(ln, kind)
   implicit none
   integer(kind=int32), intent(in) :: ln
   integer(kind=int32), intent(inout) :: kind

   select case (kind)
   case (bk_run)
      if (line_run > 0) then
         call deck_error(ln, 'a second Run block (the first is on line '// &
            itoa(line_run)//')')
         kind = bk_skip
      else
         line_run = ln
      end if
   case (bk_output)
      if (line_output > 0) then
         call deck_error(ln, 'a second Output block (the first is on '// &
            'line '//itoa(line_output)//')')
         kind = bk_skip
      else
         line_output = ln
      end if
   case (bk_solver)
      if (line_solver > 0) then
         call deck_error(ln, 'a second Solver block (the first is on '// &
            'line '//itoa(line_solver)//')')
         kind = bk_skip
      else
         line_solver = ln
      end if
   case (bk_stack)
      if (line_stack > 0) then
         call deck_error(ln, 'a second Stack block (the first is on '// &
            'line '//itoa(line_stack)//')')
         kind = bk_skip
      else
         line_stack = ln
      end if
   end select
   end subroutine once_only

   !*******************************************************************!
   ! "End <block> [name]": must close the innermost open block.        !
   !*******************************************************************!
   subroutine do_end(ln, words, nw)
   implicit none
   integer(kind=int32), intent(in) :: ln, nw
   character(len=wordlen), intent(in) :: words(4)
   integer(kind=int32) :: d

   if (nw < 2) then
      call deck_error(ln, '"End" must name the block it closes, e.g. '// &
         '"End Layer"')
      return
   end if
   if (depth == 0) then
      call deck_error(ln, '"End '//trim(words(2))//'" with no open block')
      return
   end if

   ! The usual case: it closes the innermost block.
   if (lower(words(2)) == lower(blk(depth)%word)) then
      if (nw == 3 .and. blk(depth)%kind == bk_material) then
         if (lower(words(3)) /= lower(material(imat_now)%name)) &
            call deck_error(ln, 'End Material '//trim(words(3))// &
               ' closes Material '//trim(material(imat_now)%name))
      else if (nw > 2) then
         call deck_error(ln, 'too many words on the End line')
      end if
      call close_block()
      return
   end if

   ! It names a block further out: report every block it skips over,
   ! then close down to it. Otherwise it matches nothing: report it.
   do d = depth-1, 1, -1
      if (lower(words(2)) == lower(blk(d)%word)) then
         do while (depth > d)
            call deck_error(ln, 'Begin '//trim(blk(depth)%word)// &
               ' on line '//itoa(blk(depth)%line)//' is never closed')
            call close_block()
         end do
         call close_block()
         return
      end if
   end do
   call deck_error(ln, '"End '//trim(words(2))//'" does not match the '// &
      'open block (Begin '//trim(blk(depth)%word)//' on line '// &
      itoa(blk(depth)%line)//')')
   end subroutine do_end

   !*******************************************************************!
   ! Push a block, and pop one (checking required keys on the way out). !
   !*******************************************************************!
   subroutine push_block(kind, word, ln)
   implicit none
   integer(kind=int32), intent(in) :: kind, ln
   character(len=*), intent(in) :: word

   if (depth == maxdepth) then
      call deck_error(ln, 'blocks are nested too deeply')
      return
   end if
   depth = depth + 1
   blk(depth)%kind  = kind
   blk(depth)%word  = word
   blk(depth)%line  = ln
   blk(depth)%nseen = 0
   blk(depth)%seen  = ' '
   end subroutine push_block

   subroutine close_block()
   implicit none
   integer(kind=int32) :: lb

   if (depth == 0) return
   lb = blk(depth)%line

   select case (blk(depth)%kind)
   ! A required key that was given with a bad value has already been
   ! reported, so only keys that never appeared are "missing".
   case (bk_material)
      associate (m => material(imat_now))
         if (.not. seen('r0')) call missing(lb, 'R0', 'Material '//m%name)
         if (.not. seen('c0')) call missing(lb, 'C0', 'Material '//m%name)
         if (.not. seen('s1')) call missing(lb, 'S1', 'Material '//m%name)
         if (.not. seen('g0')) call missing(lb, 'G0', 'Material '//m%name)
      end associate
      imat_now = 0
   case (bk_layer)
      if (.not. seen('material')) call missing(lb, 'material', 'Layer')
      if (.not. seen('width'))    call missing(lb, 'width', 'Layer')
      ilay_now = 0
   case (bk_run)
      tend_given = seen('t_end')
   end select
   depth = depth - 1
   end subroutine close_block

   !*** True if key k (lower case) appeared in the innermost block.
   logical function seen(k)
   implicit none
   character(len=*), intent(in) :: k
   seen = any(blk(depth)%seen(1:blk(depth)%nseen) == k)
   end function seen

   subroutine missing(ln, key, where)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key, where
   call deck_error(ln, trim(key)//' is required in '//trim(where)// &
      ' (the block that begins here)')
   end subroutine missing

   !*******************************************************************!
   ! "define <name> = <number>"  (top level only, before first use)    !
   !*******************************************************************!
   subroutine do_define(ln, text)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: text
   character(len=nline) :: key, val, dname
   real(kind=dp) :: x
   logical :: iskv, ok
   integer(kind=int32) :: k
   character(len=:), allocatable :: msg

   if (depth /= 1) then
      call deck_error(ln, 'define is only allowed at the top level')
      return
   end if

   ! Drop the word "define", then read "name = number".
   k = index(lower(text), 'define')
   call split_kv(text(k+6:), key, val, iskv)
   dname = key
   if (.not. iskv .or. len_trim(dname) == 0) then
      call deck_error(ln, 'expected "define <name> = <number>"')
      return
   end if
   if (.not. is_name(dname)) then
      call deck_error(ln, '"'//trim(dname)//'" is not a valid name '// &
         'for a define')
      return
   end if
   if (find_define(dname) > 0) then
      call deck_error(ln, 'define '//trim(dname)//' is already set on '// &
         'line '//itoa(def_line(find_define(dname))))
      return
   end if
   call parse_real(val, x, ok, msg)
   if (.not. ok) then
      call deck_error(ln, 'define '//trim(dname)//' = "'//trim(val)// &
         '" '//msg)
      return
   end if
   if (ndef == maxdef) then
      call deck_error(ln, 'too many defines (at most 100)')
      return
   end if
   ndef = ndef + 1
   def_name(ndef) = dname(1:namelen)
   def_val(ndef)  = x
   def_line(ndef) = ln
   end subroutine do_define

   !*******************************************************************!
   ! One "key = value" line, checked against the keys its block allows. !
   !*******************************************************************!
   subroutine do_key(ln, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key, val
   character(len=namelen) :: k
   integer(kind=int32) :: n, kb

   if (depth == 0) return
   kb = blk(depth)%kind
   if (kb == bk_skip) return

   if (.not. is_name(key)) then
      call deck_error(ln, '"'//trim(key)//'" is not a valid key name')
      return
   end if
   k = lower(key)

   ! A key may appear once per block ("tracer" may repeat).
   if (k /= 'tracer') then
      do n = 1, blk(depth)%nseen
         if (blk(depth)%seen(n) == k) then
            call deck_error(ln, trim(key)//' is given twice in this '// &
               trim(blk(depth)%word)//' block')
            return
         end if
      end do
      if (blk(depth)%nseen < maxkeys) then
         blk(depth)%nseen = blk(depth)%nseen + 1
         blk(depth)%seen(blk(depth)%nseen) = k
      end if
   end if

   select case (kb)
   case (bk_bitwhiz)
      call key_top(ln, k, key, val)
   case (bk_run)
      call key_run(ln, k, key, val)
   case (bk_output)
      call key_output(ln, k, key, val)
   case (bk_solver)
      call key_solver(ln, k, key, val)
   case (bk_material)
      call key_material(ln, k, key, val)
   case (bk_stack)
      call key_stack(ln, k, key, val)
   case (bk_layer)
      call key_layer(ln, k, key, val)
   end select
   end subroutine do_key

   !*** Top level: deck_version.
   subroutine key_top(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   integer(kind=int32) :: iv
   logical :: ok

   select case (k)
   case ('deck_version')
      call get_int(ln, key, val, iv, ok)
      if (ok) then
         if (iv /= 1) then
            call deck_error(ln, 'deck_version = '//trim(val)// &
               ' is not supported; this bitwhiz reads deck_version 1')
         else
            deck_version = iv
         end if
      end if
      line_version = ln
   case default
      call unknown_key(ln, key, 'at the top level', &
         'deck_version, define, and the blocks Run, Output, Solver, '// &
         'Material, Stack')
   end select
   end subroutine key_top

   !*** Block Run: what to run, for how long, on how many threads.
   subroutine key_run(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   integer(kind=int32) :: iv
   real(kind=dp) :: x
   logical :: ok

   select case (k)
   case ('title')
      if (get_name(ln, key, val)) title = val
   case ('t_end')
      call get_real(ln, key, val, x, ok)
      if (ok) call positive(ln, key, x, ok)
      if (ok) t_end = x
   case ('cycle_max')
      call get_int(ln, key, val, iv, ok)
      if (ok .and. iv < 1) call deck_error(ln, 'cycle_max must be at '// &
         'least 1')
      if (ok .and. iv >= 1) cycle_max = iv
   case ('num_threads')
      call get_int(ln, key, val, iv, ok)
      if (ok) nproc = iv          ! 0 = all processors (maincode, OpenMP)
   case ('omp_min_zones')
      call get_int(ln, key, val, iv, ok)
      if (ok .and. iv < 0) call deck_error(ln, 'omp_min_zones must be '// &
         '0 or more')
      if (ok .and. iv >= 0) omp_min_zones = iv
   case ('plots_only')
      ! yes: read the deck, then only re-draw the pictures from the
      ! files an earlier run of it left (no time steps, no new files
      ! but the pictures). no (the default): a normal run.
      select case (lower(val))
      case ('yes')
         plots_only = .true.
      case ('no')
         plots_only = .false.
      case default
         call deck_error(ln, 'plots_only = '//trim(val)//' is not yes '// &
            'or no')
      end select
   case default
      call unknown_key(ln, key, 'in the Run block', &
         'title, t_end, cycle_max, num_threads, omp_min_zones, plots_only')
   end select
   end subroutine key_run

   !*** Block Output: what to write. Nothing given = nothing written.
   subroutine key_output(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   character(len=wordlen) :: words(4)
   integer(kind=int32) :: iv, nw, it
   real(kind=dp) :: x
   logical :: ok

   select case (k)
   case ('plot_every')
      call get_int(ln, key, val, iv, ok)
      if (ok) plot_every = iv
   case ('plot_dt')
      call get_real(ln, key, val, x, ok)
      if (ok .and. x < zero) call deck_error(ln, 'plot_dt cannot be '// &
         'negative (0 turns it off)')
      if (ok .and. x >= zero) plot_dt = x
   case ('tracer_dt')
      call get_real(ln, key, val, x, ok)
      if (ok .and. x < zero) call deck_error(ln, 'tracer_dt cannot be '// &
         'negative (0 writes a row every cycle)')
      if (ok .and. x >= zero) tracer_dt = x
   case ('colormap')
      ! The colormaps built into bitwhiz (src/colormaps), by the names
      ! bmpmaker knows them.
      select case (lower(val))
      case ('grayscale', 'viridis', 'plasma', 'inferno', 'blackbody', &
            'kindlmann', 'extendedkindlmann', 'smoothcoolwarm', &
            'bentcoolwarm')
         colormap = lower(val)
      case default
         call deck_error(ln, 'colormap = '//trim(val)//' is not one of '// &
            'grayscale, viridis, plasma, inferno, blackbody, kindlmann, '// &
            'extendedkindlmann, smoothcoolwarm, bentcoolwarm')
      end select
   case ('plot_range')
      ! What a t-x diagram's color range is (module pics): the data's
      ! min to max, or to the largest value the run held (robust).
      select case (lower(val))
      case ('robust', 'full')
         plot_range = lower(val)
      case default
         call deck_error(ln, 'plot_range = '//trim(val)//' is not '// &
            'robust or full')
      end select
   case ('plot_u_lo', 'plot_u_hi', 'plot_p_lo', 'plot_p_hi')
      ! A t-x diagram's color window, as a fraction of the data's range
      ! (0 = its min, 1 = its max). lo below hi is checked once the
      ! whole deck is read (resolve_deck).
      call get_real(ln, key, val, x, ok)
      if (ok .and. (x < zero .or. x > one)) then
         call deck_error(ln, trim(key)//' must be from 0 to 1 (a '// &
            'fraction of the data''s range)')
      else if (ok) then
         select case (k)
         case ('plot_u_lo'); plot_u_lo = x; line_ulo = ln
         case ('plot_u_hi'); plot_u_hi = x; line_uhi = ln
         case ('plot_p_lo'); plot_p_lo = x; line_plo = ln
         case ('plot_p_hi'); plot_p_hi = x; line_phi = ln
         end select
      end if
   case ('tracer')
      call split_words(val, words, nw)
      if (nw /= 2) then
         call deck_error(ln, 'expected "tracer = <name> <location>", '// &
            'e.g. "tracer = pdv MatX:PMMA"')
         return
      end if
      if (.not. is_name(words(1))) then
         call deck_error(ln, 'tracer name "'//trim(words(1))//'" is not '// &
            'a valid name (it must start with a letter)')
         return
      end if
      do it = 1, ntrc
         if (lower(tracer(it)%name) == lower(words(1))) then
            call deck_error(ln, 'tracer '//trim(words(1))//' is already '// &
               'defined on line '//itoa(tracer(it)%line))
            return
         end if
      end do
      ntrc = ntrc + 1
      tracer(ntrc)%name = words(1)(1:namelen)
      tracer(ntrc)%at   = words(2)
      tracer(ntrc)%line = ln
   case default
      call unknown_key(ln, key, 'in the Output block', &
         'tracer, tracer_dt, plot_every, plot_dt, colormap, plot_range, '// &
         'plot_u_lo, plot_u_hi, plot_p_lo, plot_p_hi')
   end select
   end subroutine key_output

   !*** Block Solver.
   subroutine key_solver(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   real(kind=dp) :: x
   logical :: ok

   select case (k)
   case ('method')
      ! The two solution methods: AV (artificial viscosity, module av)
      ! and RS (Godunov's method with a Riemann solver, module rs).
      select case (lower(val))
      case ('av')
         method = 'AV'
      case ('rs')
         method = 'RS'
      case default
         call deck_error(ln, 'method = '//trim(val)//' is not one of '// &
            'AV (artificial viscosity), RS (Riemann solver)')
      end select
   case ('bl', 'bq')
      call get_real(ln, key, val, x, ok)
      if (ok .and. x < zero) call deck_error(ln, trim(key)// &
         ' cannot be negative')
      if (ok .and. x >= zero) then
         if (k == 'bl') BL = x
         if (k == 'bq') BQ = x
      end if
   case ('cfl')
      call get_real(ln, key, val, x, ok)
      if (ok .and. (x <= zero .or. x > one)) then
         call deck_error(ln, 'CFL must be in (0, 1]')
      else if (ok) then
         CFL = x
      end if
   case ('order')
      ! Method RS's order of accuracy: exactly 1 or 2, nothing else
      ! (not 2.0, not -7). Method AV ignores it.
      select case (trim(val))
      case ('1')
         rs_order = 1
      case ('2')
         rs_order = 2
      case default
         call deck_error(ln, 'order = '//trim(val)//' is not 1 (first '// &
            'order) or 2 (second order, the default)')
      end select
   case default
      call unknown_key(ln, key, 'in the Solver block', &
         'method, BL, BQ, CFL, order')
   end select
   end subroutine key_solver

   !*** Block Material.
   subroutine key_material(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   real(kind=dp) :: x
   logical :: ok

   select case (k)
   case ('r0', 'c0', 's1', 's2', 'g0')
      call get_real(ln, key, val, x, ok)
      if (.not. ok) return
      if ((k == 'r0' .or. k == 'c0') .and. x <= zero) then
         call deck_error(ln, trim(key)//' must be greater than zero')
         return
      end if
      associate (m => material(imat_now))
         select case (k)
         case ('r0'); m%R0 = x
         case ('c0'); m%C0 = x
         case ('s1'); m%S1 = x
         case ('s2'); m%S2 = x
         case ('g0'); m%G0 = x
         end select
      end associate
   case ('spall_strength')
      call get_real(ln, key, val, x, ok)
      if (.not. ok) return
      if (x < zero) then
         call deck_error(ln, 'spall_strength is a magnitude in GPa: '// &
            'give it as 0 or more (the code uses -spall_strength)')
         return
      end if
      material(imat_now)%spall_strength = x
   case default
      call unknown_key(ln, key, 'in a Material block', &
         'R0, C0, S1, S2, G0, spall_strength')
   end select
   end subroutine key_material

   !*** Block Stack.
   subroutine key_stack(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   real(kind=dp) :: x
   logical :: ok

   select case (k)
   case ('resolution')
      call get_real(ln, key, val, x, ok)
      if (ok) call positive(ln, key, x, ok)
      if (ok) stack_resolution = x
   case ('origin')
      if (len_trim(val) > len(origin)) then
         call deck_error(ln, 'origin is longer than 72 characters')
      else
         origin = val
      end if
      line_origin = ln
   case ('x_left')
      call get_real(ln, key, val, x, ok)
      if (ok) then
         x_left = x
         have_x_left = .true.
      end if
      line_xleft = ln
   case default
      call unknown_key(ln, key, 'in the Stack block', &
         'resolution, origin, x_left, and Layer blocks')
   end select
   end subroutine key_stack

   !*** Block Layer.
   subroutine key_layer(ln, k, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: k, key, val
   real(kind=dp) :: x
   integer(kind=int32) :: iv, id
   logical :: ok

   associate (l => layer(ilay_now))
   select case (k)
   case ('material')
      if (get_name(ln, key, val)) l%matname = val
   case ('name')
      if (get_name(ln, key, val)) l%name = val
   case ('width')
      call get_real(ln, key, val, x, ok)
      if (ok) call positive(ln, key, x, ok)
      if (ok) l%width = x
   case ('xvel')
      call get_real(ln, key, val, x, ok)
      if (ok) then
         l%xvel = x
         id = find_define(val)
         if (id > 0) l%xvel_from = def_name(id)
      end if
   case ('zones')
      call get_int(ln, key, val, iv, ok)
      if (ok .and. iv < 1) call deck_error(ln, 'zones must be at least 1')
      if (ok .and. iv >= 1) l%zones = iv
   case ('resolution')
      call get_real(ln, key, val, x, ok)
      if (ok) call positive(ln, key, x, ok)
      if (ok) l%resolution = x
   case default
      call unknown_key(ln, key, 'in a Layer block', &
         'material, name, width, xvel, zones, resolution')
   end select
   end associate
   end subroutine key_layer

   !*******************************************************************!
   ! Say exactly what is wrong with a line that is not "key = value".   !
   ! If the key itself is fine, record it as seen, so a required key   !
   ! with a broken value is not also reported as missing.              !
   !*******************************************************************!
   subroutine bad_kv(ln, text)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: text
   character(len=nline) :: key, val
   integer(kind=int32) :: k

   k = index(text, '=')
   if (k == 0) then
      call deck_error(ln, 'expected "key = value", "Begin ...", '// &
         '"End ..." or "define ..."')
      return
   end if
   key = adjustl(text(1:k-1))
   val = adjustl(text(k+1:))
   if (len_trim(key) == 0) then
      call deck_error(ln, 'nothing before the "="')
      return
   end if
   if (len_trim(val) == 0) then
      call deck_error(ln, trim(key)//' has no value after the "="')
   else
      call deck_error(ln, 'only one "=" is allowed on a line')
   end if
   if (is_name(key) .and. depth > 0) then
      if (blk(depth)%nseen < maxkeys) then
         blk(depth)%nseen = blk(depth)%nseen + 1
         blk(depth)%seen(blk(depth)%nseen) = lower(key(1:namelen))
      end if
   end if
   end subroutine bad_kv

   subroutine unknown_key(ln, key, where, allowed)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key, where, allowed
   character(len=:), allocatable :: home

   ! A real key in the wrong block is a common slip (e.g. a tracer left
   ! in the Run block): say where it belongs instead of "unknown".
   home = home_block(lower(key))
   if (len(home) > 0) then
      call deck_error(ln, trim(key)//' belongs in '//home//', not '// &
         where(4:))
   else
      call deck_error(ln, 'unknown key "'//trim(key)//'" '//where// &
         ' (allowed: '//allowed//')')
   end if
   end subroutine unknown_key

   !*** The block each key belongs to ('' if it is not a key at all).
   function home_block(k) result(b)
   implicit none
   character(len=*), intent(in) :: k
   character(len=:), allocatable :: b
   select case (trim(k))
   case ('deck_version')
      b = 'the top level'
   case ('title', 't_end', 'cycle_max', 'num_threads', 'omp_min_zones', &
         'plots_only')
      b = 'the Run block'
   case ('tracer', 'tracer_dt', 'plot_every', 'plot_dt', 'colormap', &
         'plot_range', 'plot_u_lo', 'plot_u_hi', 'plot_p_lo', 'plot_p_hi')
      b = 'the Output block'
   case ('method', 'bl', 'bq', 'cfl', 'order')
      b = 'the Solver block'
   case ('r0', 'c0', 's1', 's2', 'g0', 'spall_strength')
      b = 'a Material block'
   case ('origin', 'x_left')
      b = 'the Stack block'
   case ('material', 'name', 'width', 'xvel', 'zones')
      b = 'a Layer block'
   case default
      b = ''
   end select
   end function home_block

!======================================================================!
!  STAGE 4: RESOLVE                                                    !
!======================================================================!

   !*******************************************************************!
   ! Everything that needs the whole deck.                             !
   !*******************************************************************!
   subroutine resolve_deck()
   implicit none
   integer(kind=int32) :: l, l2, im, it, ksum, nz
   real(kind=dp) :: res, xz, xraw, shift
   real(kind=dp), allocatable :: xstart(:)
   character(len=:), allocatable :: msg
   logical :: ok

   !*** 0. The title defaults to the deck's file name (no folder, no
   !***    extension), made into a valid name.
   if (len_trim(title) == 0) title = name_from_file(deck_file)

   !*** 1. Each layer finds its material, and takes a copy of it.
   do l = 1, nlay
      im = find_material(layer(l)%matname)
      if (im == 0) then
         call deck_error(layer(l)%line, 'material '// &
            trim(layer(l)%matname)//' is not defined (materials: '// &
            material_list()//')')
         cycle
      end if
      layer(l)%imat = im
      material(im)%nused = material(im)%nused + 1
      layer(l)%R0 = material(im)%R0
      layer(l)%C0 = material(im)%C0
      layer(l)%S1 = material(im)%S1
      layer(l)%S2 = material(im)%S2
      layer(l)%G0 = material(im)%G0
      layer(l)%spall_strength = material(im)%spall_strength
   end do
   if (nerr > 0) return

   !*** 2. Layer names: default to the material, unique (any case).
   do l = 1, nlay
      if (len_trim(layer(l)%name) > 0) cycle
      im = layer(l)%imat
      if (material(im)%nused > 1) then
         call deck_error(layer(l)%line, 'material '// &
            trim(material(im)%name)//' is used by '// &
            itoa(material(im)%nused)//' layers, so each of them needs '// &
            '"name =" (locations refer to layer names)')
      else
         layer(l)%name = material(im)%name
      end if
   end do
   do l = 1, nlay
      do l2 = 1, l-1
         if (len_trim(layer(l)%name) == 0) cycle
         if (lower(layer(l)%name) == lower(layer(l2)%name)) &
            call deck_error(layer(l)%line, 'layer name '// &
               trim(layer(l)%name)//' is already used by the layer on '// &
               'line '//itoa(layer(l2)%line))
      end do
   end do
   do im = 1, nmat
      if (material(im)%nused == 0) call deck_warn(material(im)%line, &
         'Material '//trim(material(im)%name)//' is not used by any layer')
   end do
   if (nerr > 0) return

   !*** 3. Zone counts: zones, else the layer's resolution, else the
   !***    Stack's. The width is kept exact; only dx = width/zones moves.
   ksum = 0
   do l = 1, nlay
      res = layer(l)%resolution
      if (res <= zero) res = stack_resolution
      if (layer(l)%zones > 0) then
         nz = layer(l)%zones
         if (res > zero) call deck_note(layer(l)%line, 'layer '// &
            trim(layer(l)%name)//': zones = '//itoa(nz)// &
            ' overrides the resolution')
      else if (res > zero) then
         xz = layer(l)%width * res
         if (xz > real(maxzones, dp)) then
            call deck_error(layer(l)%line, 'layer '//trim(layer(l)%name)// &
               ' would have more than 10 million zones')
            cycle
         end if
         nz = max(1, nint(xz))
         if (abs(xz - real(nz, dp)) > 1.0e-9_dp*max(one, xz)) &
            call deck_warn(layer(l)%line, 'layer '//trim(layer(l)%name)// &
               ': width*resolution = '//fmt_real(xz)//' is not whole; '// &
               'using '//itoa(nz)//' zones (dx = '// &
               fmt_real(round6(layer(l)%width/real(nz, dp)))//' mm)')
      else
         call deck_error(layer(l)%line, 'layer '//trim(layer(l)%name)// &
            ' has no zone count: give zones or resolution here, or '// &
            'resolution in the Stack')
         cycle
      end if
      layer(l)%zones  = nz
      layer(l)%kfirst = ksum + 1
      ksum = ksum + nz
      layer(l)%klast  = ksum
      if (ksum > maxzones) then
         call deck_error(layer(l)%line, 'more than 10 million zones in all')
         return
      end if
   end do
   if (nerr > 0) return
   kmax = ksum

   !*** 4. Positions. First with x = 0 at the left face of the stack,
   !***    then shifted by origin or x_left.
   allocate(xstart(nlay+1))
   xstart(1) = zero
   do l = 1, nlay
      xstart(l+1) = xstart(l) + layer(l)%width
   end do

   shift = zero
   if (line_origin > 0 .and. have_x_left) then
      call deck_error(line_xleft, 'origin (line '//itoa(line_origin)// &
         ') and x_left cannot both be given')
      return
   else if (line_origin > 0) then
      do l = 1, nlay
         layer(l)%xleft = xstart(l)
      end do
      call locate(origin, .false., xraw, it, ok, msg)
      if (.not. ok) then
         call deck_error(line_origin, 'origin = '//trim(origin)//': '//msg)
         return
      end if
      shift = -xraw
   else if (have_x_left) then
      shift = x_left
   end if
   do l = 1, nlay
      layer(l)%xleft = xstart(l) + shift
   end do
   x_left = layer(1)%xleft           ! the resolved frame, for the echo

   !*** 5. Tracers.
   do it = 1, ntrc
      call locate(tracer(it)%at, .true., xraw, l, ok, msg, it)
      if (.not. ok) call deck_error(tracer(it)%line, 'tracer '// &
         trim(tracer(it)%name)//' at '//trim(tracer(it)%at)//': '//msg)
   end do

   !*** 6. Color windows: the low end below the high end (each is
   !***    already in 0 to 1). The error points at the later line.
   if (.not. (plot_u_lo < plot_u_hi)) call deck_error(max(line_ulo, &
      line_uhi), 'plot_u_lo ('//fmt_real(plot_u_lo)//') must be less '// &
      'than plot_u_hi ('//fmt_real(plot_u_hi)//')')
   if (.not. (plot_p_lo < plot_p_hi)) call deck_error(max(line_plo, &
      line_phi), 'plot_p_lo ('//fmt_real(plot_p_lo)//') must be less '// &
      'than plot_p_hi ('//fmt_real(plot_p_hi)//')')

   return
   end subroutine resolve_deck

   !*******************************************************************!
   ! Turn a location ("A:B", "A@f" or a number) into an x position.    !
   ! Named forms use the CURRENT layer positions. With it > 0, the     !
   ! tracer it is also placed on the mesh (kface, w, kcell, ...).      !
   ! Numbers are allowed only when allow_x is true (tracers, not the   !
   ! origin).                                                          !
   !*******************************************************************!
   subroutine locate(text, allow_x, x, lay, ok, msg, it)
   implicit none
   character(len=*), intent(in) :: text
   logical, intent(in) :: allow_x
   real(kind=dp), intent(out) :: x
   integer(kind=int32), intent(out) :: lay
   logical, intent(out) :: ok
   character(len=:), allocatable, intent(out) :: msg
   integer(kind=int32), intent(in), optional :: it
   character(len=nline) :: a, b
   integer(kind=int32) :: kc, ka, la, lb, kind, nz, m
   real(kind=dp) :: f, s, w
   logical :: okn

   ok   = .false.
   msg  = ''
   x    = zero
   lay  = 0
   kc   = index(text, ':')
   ka   = index(text, '@')
   f    = zero

   if (kc > 0 .and. ka > 0) then
      msg = 'use either A:B or A@f, not both'
      return
   end if

   if (kc > 0) then
      !*** "A:B", the interface between neighboring layers.
      kind = loc_interface
      a = text(1:kc-1)
      b = text(kc+1:)
      if (index(b, ':') > 0) then
         msg = 'only one ":" is allowed'
         return
      end if
      if (len_trim(a) == 0 .or. len_trim(b) == 0) then
         msg = 'an interface needs a layer name on each side of ":"'
         return
      end if
      la = find_layer(a)
      lb = find_layer(b)
      if (la == 0 .or. lb == 0) then
         msg = 'no layer named '//trim(merge(a, b, la == 0))// &
            ' (layers: '//layer_list()//')'
         return
      end if
      if (abs(la - lb) /= 1) then
         msg = trim(layer(la)%name)//' and '//trim(layer(lb)%name)// &
            ' are not neighbors'
         return
      end if
      la = min(la, lb)           ! either order is the same interface
      lay = la
      f = one                    ! the right face of the left layer
   else if (ka > 0) then
      !*** "A@f", a fraction across layer A.
      kind = loc_fraction
      a = text(1:ka-1)
      b = text(ka+1:)
      if (len_trim(a) == 0) then
         msg = 'a layer name is needed before "@"'
         return
      end if
      la = find_layer(a)
      if (la == 0) then
         msg = 'no layer named '//trim(a)//' (layers: '//layer_list()//')'
         return
      end if
      call parse_real(b, f, okn, msg)
      if (.not. okn) then
         msg = 'the fraction "'//trim(b)//'" '//msg
         return
      end if
      if (f < zero .or. f > one) then
         msg = 'the fraction must be between 0 and 1'
         return
      end if
      lay = la
   else
      !*** A number: an x position in the final frame.
      kind = loc_x
      if (.not. allow_x) then
         msg = 'origin must name a location (A:B or A@f); for a number, '// &
            'use x_left instead'
         return
      end if
      call parse_real(text, x, okn, msg)
      if (.not. okn) then
         msg = '"'//trim(text)//'" '//msg//' (locations are A:B, A@f '// &
            'or a number)'
         return
      end if
      la = 0
      do m = 1, nlay
         if (x >= layer(m)%xleft - 1.0e-12_dp .and. &
             x <= layer(m)%xleft + layer(m)%width + 1.0e-12_dp) then
            la = m
            exit
         end if
      end do
      if (la == 0) then
         msg = 'x = '//fmt_real(x)//' is outside the stack ['// &
            fmt_real(layer(1)%xleft)//', '// &
            fmt_real(layer(nlay)%xleft + layer(nlay)%width)//']'
         return
      end if
      f = (x - layer(la)%xleft) / layer(la)%width
      f = min(one, max(zero, f))
      lay = la
   end if

   ok = .true.
   x  = layer(lay)%xleft + f*layer(lay)%width

   if (.not. present(it)) return

   !*** Place the tracer on the mesh. s counts zones from the layer's
   !*** left face; the tracer sits w of the way from face kface to
   !*** face kface+1 (faces are k+1/2, so the left face of cell kfirst
   !*** is face kfirst-1).
   nz = layer(lay)%zones
   s  = f*real(nz, dp)
   m  = int(s)
   w  = s - real(m, dp)
   if (w < 1.0e-9_dp) w = zero
   if (w > one - 1.0e-9_dp) then
      m = m + 1
      w = zero
   end if
   m = min(m, nz)
   tracer(it)%kind  = kind
   tracer(it)%lay   = lay
   tracer(it)%x0    = x
   tracer(it)%kface = layer(lay)%kfirst - 1 + m
   tracer(it)%w     = w
   if (w > zero) then
      tracer(it)%kcell = layer(lay)%kfirst + m   ! inside cell kfirst+m
      tracer(it)%kval  = tracer(it)%kcell
   else
      tracer(it)%kcell = 0                        ! exactly on a node
      !*** On a node, report the cell on this layer's side (shock_mod,
      !*** tracer table): the right cell at the layer's left face,
      !*** otherwise the left cell.
      if (m == 0) then
         tracer(it)%kval = layer(lay)%kfirst
      else
         tracer(it)%kval = tracer(it)%kface
      end if
   end if
   end subroutine locate

!======================================================================!
!  PUBLIC: the resolved deck.                                          !
!======================================================================!

   !*******************************************************************!
   ! Write the deck back out with every value resolved: defaults       !
   ! filled in, defines substituted, zone counts and the frame made    !
   ! explicit. Reading this output gives exactly the same tables.      !
   ! Comments show what was resolved (positions, cells, tracers).      !
   !*******************************************************************!
   subroutine write_resolved_deck(lu)
   implicit none
   integer, intent(in) :: lu
   integer(kind=int32) :: id, im, l, it
   character(len=:), allocatable :: where

   write(lu,'(a)') '#'//repeat('*',70)//'#'
   write(lu,'(a)') '#  Resolved deck, from '//trim(deck_file)
   write(lu,'(a)') '#  Every default is filled in and every define is '// &
      'substituted. Reading'
   write(lu,'(a)') '#  this deck gives exactly the same run.'
   write(lu,'(a)') '#'//repeat('*',70)//'#'
   write(lu,'(a)') 'Begin bitwhiz'
   write(lu,'(a)') ' deck_version = 1'
   do id = 1, ndef
      write(lu,'(a)') ' # define '//trim(def_name(id))//' = '// &
         fmt_real(def_val(id))//'   (substituted below)'
   end do

   write(lu,'(a)') ''
   write(lu,'(a)') ' Begin Run'
   call kv(lu, 2, 'title',       trim(title))
   call kv(lu, 2, 't_end',       fmt_real(t_end), 'us')
   call kv(lu, 2, 'cycle_max',   itoa(cycle_max))
   if (nproc == 0) then
      call kv(lu, 2, 'num_threads', '0', 'all processors')
   else
      call kv(lu, 2, 'num_threads', itoa(nproc))
   end if
   call kv(lu, 2, 'omp_min_zones', itoa(omp_min_zones), &
      'cells; fewer runs on one thread')
   if (plots_only) then
      call kv(lu, 2, 'plots_only', 'yes', 'no run: re-draw the pictures')
   else
      call kv(lu, 2, 'plots_only', 'no')
   end if
   write(lu,'(a)') ' End Run'

   write(lu,'(a)') ''
   write(lu,'(a)') ' Begin Output'
   call kv(lu, 2, 'plot_every',  itoa(plot_every), &
      merge('off       ', 'cycles    ', plot_every == 0))
   call kv(lu, 2, 'plot_dt',     fmt_real(plot_dt), &
      merge('off', 'us ', plot_dt <= zero))
   call kv(lu, 2, 'colormap',    trim(colormap))
   call kv(lu, 2, 'plot_range',  trim(plot_range), &
      merge('color ranges: min to the top held 50 cycles', &
            'color ranges: min to max                   ', &
            plot_range == 'robust'))
   call kv(lu, 2, 'plot_u_lo',   fmt_real(plot_u_lo), &
      'u colors: fractions of the u range')
   call kv(lu, 2, 'plot_u_hi',   fmt_real(plot_u_hi))
   call kv(lu, 2, 'plot_p_lo',   fmt_real(plot_p_lo), &
      'P colors: fractions of the P range')
   call kv(lu, 2, 'plot_p_hi',   fmt_real(plot_p_hi))
   call kv(lu, 2, 'tracer_dt',   fmt_real(tracer_dt), &
      merge('us, 0 = every cycle', 'us                 ', tracer_dt <= zero))
   do it = 1, ntrc
      associate (t => tracer(it))
         where = 'x0 = '//fmt_real(t%x0)//' mm, '
         if (t%w > zero) then
            where = where//'between faces '//itoa(t%kface)//' and '// &
               itoa(t%kface+1)//' (w = '//fmt_real(round6(t%w))// &
               '), cell '//itoa(t%kcell)
         else
            where = where//'face '//itoa(t%kface)//' (i = '// &
               itoa(iface(t%kface))//'), cell values from cell '// &
               itoa(t%kval)
         end if
         call kv(lu, 2, 'tracer', trim(t%name)//'  '//trim(t%at), where)
      end associate
   end do
   write(lu,'(a)') ' End Output'

   write(lu,'(a)') ''
   write(lu,'(a)') ' Begin Solver'
   call kv(lu, 2, 'method', trim(method))
   call kv(lu, 2, 'BL',     fmt_real(BL), &
      merge('AV only; RS ignores it', '                      ', method == 'RS'))
   call kv(lu, 2, 'BQ',     fmt_real(BQ), &
      merge('AV only; RS ignores it', '                      ', method == 'RS'))
   call kv(lu, 2, 'CFL',    fmt_real(CFL))
   if (method == 'RS') then
      call kv(lu, 2, 'order', itoa(rs_order), merge( &
         'second order: MUSCL-Hancock, Van Leer', &
         'first order: Godunov                 ', rs_order == 2))
   else
      call kv(lu, 2, 'order', itoa(rs_order), 'RS only; AV ignores it')
   end if
   write(lu,'(a)') ' End Solver'

   do im = 1, nmat
      associate (m => material(im))
         write(lu,'(a)') ''
         write(lu,'(a)') ' Begin Material '//trim(m%name)// &
            '      # used by '//itoa(m%nused)//' layer(s)'
         call kv(lu, 2, 'R0', fmt_real(m%R0), 'g/cm^3')
         call kv(lu, 2, 'C0', fmt_real(m%C0), 'km/s')
         call kv(lu, 2, 'S1', fmt_real(m%S1))
         call kv(lu, 2, 'S2', fmt_real(m%S2))
         call kv(lu, 2, 'G0', fmt_real(m%G0))
         call kv(lu, 2, 'spall_strength', fmt_real(m%spall_strength), &
            'GPa; breaks below -this pressure')
         write(lu,'(a)') ' End Material'
      end associate
   end do

   write(lu,'(a)') ''
   write(lu,'(a)') ' Begin Stack'
   if (line_origin > 0) then
      call kv(lu, 2, 'x_left', fmt_real(x_left), &
         'mm (from origin = '//trim(origin)//')')
   else
      call kv(lu, 2, 'x_left', fmt_real(x_left), 'mm')
   end if
   do l = 1, nlay
      associate (y => layer(l))
         write(lu,'(a)') ''
         write(lu,'(a)') '  Begin Layer'
         call kv(lu, 3, 'name',     trim(y%name))
         call kv(lu, 3, 'material', trim(material(y%imat)%name))
         call kv(lu, 3, 'width',    fmt_real(y%width), 'mm, x = '// &
            fmt_real(y%xleft)//' to '//fmt_real(y%xleft + y%width))
         if (len_trim(y%xvel_from) > 0) then
            call kv(lu, 3, 'xvel', fmt_real(y%xvel), &
               'km/s, from define '//trim(y%xvel_from))
         else
            call kv(lu, 3, 'xvel', fmt_real(y%xvel), 'km/s')
         end if
         call kv(lu, 3, 'zones', itoa(y%zones), 'cells '//itoa(y%kfirst)// &
            ' to '//itoa(y%klast)//', dx = '// &
            fmt_real(round6(y%width/real(y%zones, dp)))//' mm')
         write(lu,'(a)') '  End Layer'
      end associate
   end do
   write(lu,'(a)') ' End Stack'
   write(lu,'(a)') 'End bitwhiz'
   end subroutine write_resolved_deck

   !*** One "key = value   # note" line, with the values lined up.
   subroutine kv(lu, indent, key, val, note)
   implicit none
   integer, intent(in) :: lu
   integer(kind=int32), intent(in) :: indent
   character(len=*), intent(in) :: key, val
   character(len=*), intent(in), optional :: note
   character(len=:), allocatable :: s
   s = repeat(' ', indent)//key
   s = s//repeat(' ', max(1, indent+12-len(s)))//'= '//val
   if (present(note)) then
      if (len_trim(note) > 0) &
         s = s//repeat(' ', max(2, indent+40-len(s)))//'# '//trim(note)
   end if
   write(lu,'(a)') s
   end subroutine kv

   !*** Round to 6 significant digits, for comments only.
   real(kind=dp) function round6(x)
   implicit none
   real(kind=dp), intent(in) :: x
   character(len=32) :: buf
   write(buf,'(es20.5e3)') x
   read(buf,*) round6
   end function round6

!======================================================================!
!  VALUES: numbers, integers, names, defines.                          !
!======================================================================!

   !*******************************************************************!
   ! A real value: a number, or the name of a define.                  !
   !*******************************************************************!
   subroutine get_real(ln, key, val, x, ok)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key, val
   real(kind=dp), intent(out) :: x
   logical, intent(out) :: ok
   character(len=:), allocatable :: msg
   integer(kind=int32) :: id

   x = zero
   if (is_name(val)) then
      id = find_define(val)
      ok = (id > 0)
      if (ok) then
         x = def_val(id)
      else
         call deck_error(ln, trim(key)//' = '//trim(val)//': no define '// &
            'named '//trim(val)//' (a define must come before its use)')
      end if
      return
   end if
   call parse_real(val, x, ok, msg)
   if (.not. ok) call deck_error(ln, trim(key)//' = "'//trim(val)//'" '// &
      msg)
   end subroutine get_real

   !*******************************************************************!
   ! An integer value: digits only.                                    !
   !*******************************************************************!
   subroutine get_int(ln, key, val, iv, ok)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key, val
   integer(kind=int32), intent(out) :: iv
   logical, intent(out) :: ok
   integer(kind=int32) :: ios, n

   iv = 0
   n = len_trim(val)
   ok = (n >= 1 .and. n <= 9)
   if (ok) ok = (verify(val(1:n), '0123456789') == 0)
   if (ok) then
      read(val(1:n), *, iostat=ios) iv
      ok = (ios == 0)
   end if
   if (.not. ok) call deck_error(ln, trim(key)//' = "'//trim(val)// &
      '" is not a whole number (digits only, at most 9)')
   end subroutine get_int

   !*******************************************************************!
   ! A name value (title, material, layer name).                       !
   !*******************************************************************!
   logical function get_name(ln, key, val)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key, val
   get_name = is_name(val)
   if (.not. get_name) call deck_error(ln, trim(key)//' = "'//trim(val)// &
      '" is not a valid name (a letter, then letters, digits or _, '// &
      'at most 32)')
   end function get_name

   subroutine positive(ln, key, x, ok)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: key
   real(kind=dp), intent(in) :: x
   logical, intent(inout) :: ok
   if (x <= zero) then
      call deck_error(ln, trim(key)//' must be greater than zero')
      ok = .false.
   end if
   end subroutine positive

   !*******************************************************************!
   ! Strict number grammar:                                            !
   !    [+|-] digits [. [digits]] [(e|E) [+|-] digits]                 !
   !    [+|-] . digits [(e|E) [+|-] digits]                            !
   ! A plain list-directed read would accept "1,2", "/", "T", "1d0"    !
   ! and leave junk behind, so every character is checked first. The   !
   ! size is also checked BEFORE the read, because reading 1e400 with  !
   ! -ffpe-trap=overflow would stop the program.                       !
   !*******************************************************************!
   subroutine parse_real(text, x, ok, msg)
   use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
   implicit none
   character(len=*), intent(in) :: text
   real(kind=dp), intent(out) :: x
   logical, intent(out) :: ok
   character(len=:), allocatable, intent(out) :: msg
   character(len=:), allocatable :: s
   integer(kind=int32) :: i, n, nint_d, nfrac_d, nexp_d, lead0, ios
   integer(kind=int32) :: iexp, mag, esign, nsig
   logical :: nonzero

   x   = zero
   ok  = .false.
   msg = 'is not a number'
   s   = trim(adjustl(text))
   n   = len(s)
   if (n == 0) then
      msg = 'is empty; a number is needed'
      return
   end if

   i = 1
   if (s(i:i) == '+' .or. s(i:i) == '-') i = i + 1

   ! Integer digits (count leading zeros and significant digits).
   nint_d = 0
   lead0  = 0
   nsig   = 0
   nonzero = .false.
   do while (i <= n)
      if (.not. is_digit(s(i:i))) exit
      nint_d = nint_d + 1
      if (s(i:i) /= '0') nonzero = .true.
      if (nonzero) nsig = nsig + 1
      i = i + 1
   end do

   ! Optional fraction.
   nfrac_d = 0
   if (i <= n) then
      if (s(i:i) == '.') then
         i = i + 1
         do while (i <= n)
            if (.not. is_digit(s(i:i))) exit
            nfrac_d = nfrac_d + 1
            if (.not. nonzero) then
               if (s(i:i) == '0') then
                  lead0 = lead0 + 1
               else
                  nonzero = .true.
               end if
            end if
            i = i + 1
         end do
      end if
   end if
   if (nint_d + nfrac_d == 0) return

   ! Optional exponent.
   iexp  = 0
   esign = 1
   nexp_d = 0
   if (i <= n) then
      if (s(i:i) == 'e' .or. s(i:i) == 'E') then
         i = i + 1
         if (i <= n) then
            if (s(i:i) == '+' .or. s(i:i) == '-') then
               if (s(i:i) == '-') esign = -1
               i = i + 1
            end if
         end if
         do while (i <= n)
            if (.not. is_digit(s(i:i))) exit
            nexp_d = nexp_d + 1
            if (nexp_d <= 5) iexp = 10*iexp + (iachar(s(i:i)) - 48)
            i = i + 1
         end do
         if (nexp_d == 0) then
            msg = 'has an exponent with no digits'
            return
         end if
         if (nexp_d > 5) iexp = 99999
      else if (s(i:i) == 'd' .or. s(i:i) == 'D') then
         msg = 'uses a Fortran "d" exponent; write e or E instead'
         return
      end if
   end if
   if (i <= n) return            ! something left over: not a number

   ! Size check, before reading. mag is about log10(|x|).
   if (nonzero) then
      if (nsig > 0) then
         mag = esign*iexp + nsig - 1
      else
         mag = esign*iexp - lead0 - 1
      end if
      if (mag > 300 .or. mag < -300) then
         msg = 'is out of range (|x| must be between 1e-300 and 1e300)'
         return
      end if
   end if

   read(s, *, iostat=ios) x
   if (ios /= 0) return
   if (.not. ieee_is_finite(x)) return
   ok  = .true.
   msg = ''
   end subroutine parse_real

   logical function is_digit(c)
   implicit none
   character(len=1), intent(in) :: c
   is_digit = (c >= '0' .and. c <= '9')
   end function is_digit

   !*******************************************************************!
   ! Shortest decimal that reads back to exactly the same double.      !
   ! Plain decimals for 1e-5 <= |x| < 1e15, otherwise e-notation.      !
   !*******************************************************************!
   function fmt_real(x) result(str)
   implicit none
   real(kind=dp), intent(in) :: x
   character(len=:), allocatable :: str
   character(len=40) :: buf, fmt
   character(len=20) :: dig
   real(kind=dp) :: y
   integer(kind=int32) :: p, ios, e, nd, k
   logical :: neg

   if (abs(x) <= zero) then         ! zero (either sign)
      str = '0.0'
      return
   end if

   do p = 1, 17
      write(fmt,'(a,i0,a)') '(es30.', p-1, 'e4)'
      write(buf, fmt) x
      read(buf, *, iostat=ios) y
      if (ios == 0) then
         if (transfer(y, 0_int64) == transfer(x, 0_int64)) exit
      end if
   end do

   ! buf holds e.g. "-1.6500E+0001": split into sign, digits, exponent.
   buf = adjustl(buf)
   neg = (buf(1:1) == '-')
   if (neg) buf = buf(2:)
   k = index(buf, 'E')
   read(buf(k+1:), *) e
   dig = buf(1:1)//buf(3:k-1)        ! drop the decimal point
   if (k == 2) dig = buf(1:1)        ! one digit, no decimal point
   nd = len_trim(dig)
   do while (nd > 1 .and. dig(nd:nd) == '0')
      nd = nd - 1
   end do

   if (e >= 0 .and. e < 15) then
      if (nd <= e+1) then
         str = dig(1:nd)//repeat('0', e+1-nd)//'.0'
      else
         str = dig(1:e+1)//'.'//dig(e+2:nd)
      end if
   else if (e < 0 .and. e >= -5) then
      str = '0.'//repeat('0', -e-1)//dig(1:nd)
   else
      if (nd > 1) then
         str = dig(1:1)//'.'//dig(2:nd)//'e'//itoa(e)
      else
         str = dig(1:1)//'e'//itoa(e)
      end if
   end if
   if (neg) str = '-'//str
   end function fmt_real

!======================================================================!
!  TEXT HELPERS                                                        !
!======================================================================!

   !*** Split "key = value". iskv is false if there is no "=", or no
   !*** key, or no value, or a second "=".
   subroutine split_kv(text, key, val, iskv)
   implicit none
   character(len=*), intent(in) :: text
   character(len=*), intent(out) :: key, val
   logical, intent(out) :: iskv
   integer(kind=int32) :: k

   key = ' '
   val = ' '
   k = index(text, '=')
   iskv = (k > 1)
   if (.not. iskv) return
   key = adjustl(text(1:k-1))
   val = adjustl(text(k+1:))
   iskv = (len_trim(key) > 0 .and. len_trim(val) > 0 .and. &
           index(val, '=') == 0)
   end subroutine split_kv

   !*** Split text into up to 4 blank-separated words (nw counts all of
   !*** them, so nw > 4 means "too many").
   subroutine split_words(text, words, nw)
   implicit none
   character(len=*), intent(in) :: text
   character(len=wordlen), intent(out) :: words(4)
   integer(kind=int32), intent(out) :: nw
   integer(kind=int32) :: i, n, i0

   words = ' '
   nw = 0
   n = len_trim(text)
   i = 1
   do while (i <= n)
      if (text(i:i) == ' ') then
         i = i + 1
         cycle
      end if
      i0 = i
      do while (i <= n)
         if (text(i:i) == ' ') exit
         i = i + 1
      end do
      nw = nw + 1
      if (nw <= 4) words(nw) = text(i0:min(i-1, i0+wordlen-1))
   end do
   end subroutine split_words

   !*** A name: a letter, then letters, digits or '_', at most 32.
   logical function is_name(text)
   implicit none
   character(len=*), intent(in) :: text
   integer(kind=int32) :: n, i
   character(len=1) :: c

   n = len_trim(text)
   is_name = (n >= 1 .and. n <= namelen)
   if (.not. is_name) return
   if (text(1:1) == ' ') then
      is_name = .false.
      return
   end if
   do i = 1, n
      c = text(i:i)
      if (i == 1) then
         is_name = is_letter(c)
      else
         is_name = is_letter(c) .or. is_digit(c) .or. c == '_'
      end if
      if (.not. is_name) return
   end do
   end function is_name

   logical function is_letter(c)
   implicit none
   character(len=1), intent(in) :: c
   is_letter = (c >= 'a' .and. c <= 'z') .or. (c >= 'A' .and. c <= 'Z')
   end function is_letter

   !*** Lower case copy (ASCII).
   function lower(text) result(s)
   implicit none
   character(len=*), intent(in) :: text
   character(len=len(text)) :: s
   integer(kind=int32) :: i, ic
   s = text
   do i = 1, len(text)
      ic = iachar(text(i:i))
      if (ic >= 65 .and. ic <= 90) s(i:i) = achar(ic + 32)
   end do
   end function lower

   !*** Integer to text.
   function itoa(i) result(s)
   implicit none
   integer(kind=int32), intent(in) :: i
   character(len=:), allocatable :: s
   character(len=16) :: buf
   write(buf,'(i0)') i
   s = trim(buf)
   end function itoa

   !*** Look-ups, all ignoring case.
   integer(kind=int32) function find_material(name)
   implicit none
   character(len=*), intent(in) :: name
   integer(kind=int32) :: i
   find_material = 0
   do i = 1, nmat
      if (lower(trim(material(i)%name)) == lower(trim(name))) then
         find_material = i
         return
      end if
   end do
   end function find_material

   integer(kind=int32) function find_layer(name)
   implicit none
   character(len=*), intent(in) :: name
   integer(kind=int32) :: i
   find_layer = 0
   do i = 1, nlay
      if (lower(trim(layer(i)%name)) == lower(trim(adjustl(name)))) then
         find_layer = i
         return
      end if
   end do
   end function find_layer

   integer(kind=int32) function find_define(name)
   implicit none
   character(len=*), intent(in) :: name
   integer(kind=int32) :: i
   find_define = 0
   do i = 1, ndef
      if (lower(trim(def_name(i))) == lower(trim(adjustl(name)))) then
         find_define = i
         return
      end if
   end do
   end function find_define

   !*** "input/me697 run-2.deck" -> "me697_run_2". Characters that are
   !*** not allowed in a name become '_', a leading digit gets "run_"
   !*** in front, and the result is cut to 32 characters.
   function name_from_file(path) result(nm)
   implicit none
   character(len=*), intent(in) :: path
   character(len=namelen) :: nm
   character(len=:), allocatable :: b
   integer(kind=int32) :: i, k

   b = trim(path)
   k = index(b, '/', back=.true.)
   if (k > 0) b = b(k+1:)
   k = index(b, '.', back=.true.)
   if (k > 1) b = b(1:k-1)
   do i = 1, len(b)
      if (.not. (is_letter(b(i:i)) .or. is_digit(b(i:i)))) b(i:i) = '_'
   end do
   if (len(b) == 0) then
      b = 'run'
   else if (.not. is_letter(b(1:1))) then
      b = 'run_'//b
   end if
   nm = b(1:min(len(b), namelen))
   end function name_from_file

   function material_list() result(s)
   implicit none
   character(len=:), allocatable :: s
   integer(kind=int32) :: i
   s = ''
   do i = 1, nmat
      if (i > 1) s = s//', '
      s = s//trim(material(i)%name)
   end do
   end function material_list

   function layer_list() result(s)
   implicit none
   character(len=:), allocatable :: s
   integer(kind=int32) :: i
   s = ''
   do i = 1, nlay
      if (i > 1) s = s//', '
      s = s//trim(layer(i)%name)
   end do
   end function layer_list

!======================================================================!
!  MESSAGES                                                            !
!======================================================================!

   subroutine deck_error(ln, msg)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: msg
   nerr = nerr + 1
   if (nerr <= maxerr) then
      write(kpt6,'(a)') ' '//where_am_i(ln)//'error: '//msg
   else if (nerr == maxerr + 1) then
      write(kpt6,'(a)') ' '//trim(deck_file)//': too many errors; '// &
         'not listing any more'
   end if
   end subroutine deck_error

   subroutine deck_warn(ln, msg)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: msg
   nwarn = nwarn + 1
   write(kpt6,'(a)') ' '//where_am_i(ln)//'warning: '//msg
   end subroutine deck_warn

   subroutine deck_note(ln, msg)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=*), intent(in) :: msg
   write(kpt6,'(a)') ' '//where_am_i(ln)//'note: '//msg
   end subroutine deck_note

   function where_am_i(ln) result(s)
   implicit none
   integer(kind=int32), intent(in) :: ln
   character(len=:), allocatable :: s
   if (ln > 0) then
      s = trim(deck_file)//':'//itoa(ln)//': '
   else
      s = trim(deck_file)//': '
   end if
   end function where_am_i

end module deck

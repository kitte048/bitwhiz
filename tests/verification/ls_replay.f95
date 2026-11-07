program ls_replay
!**********************************************************************!
!
!  Purpose:
!    The lead-shock detector (module leadshock) replayed on a real run:
!    one tracer's rows of a tracer file, written every cycle
!    (tracer_dt = 0), fed through ls_step exactly as module burn steps
!    a cell (the cell's rho, e and P at each row's time, the step from
!    the row before). For tests/verification/study_leadshock.py, which
!    checks the mark against exact Hugoniot states (doc/design/
!    burn_models.md, step 4); the hydro is not touched.
!
!       bin/ls_replay <file.tracers.csv> <tracer> <R0> <C0> [trace]
!
!    prints one line,  marked P_s t_s h_max  (or  not-marked 0 0 h_max),
!    and with "trace" first every row's  t P h flag.
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/06/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, zero, quit
use leadshock, only: ls_step, ls_h, ls_marked, ls_nst, ls_hmax, ls_flag, &
   ls_ps, ls_ts
implicit none
integer, parameter :: maxlen = 200000, maxcol = 4000
character(len=maxlen) :: line
character(len=256) :: fname, tname, arg
character(len=64) :: names(maxcol)
real(kind=dp) :: row(maxcol), st(ls_nst), R0, C0, t, tlast
integer :: lu, ios, ncol, it, ip, ir, ie, j, nhead, nrow
logical :: trace, first

if ( command_argument_count() < 4 ) then
   write(*,'(a)') 'usage: ls_replay <file.tracers.csv> <tracer> <R0> '// &
      '<C0> [trace]'
   call quit( 2 )
end if
call get_command_argument( 1, fname )
call get_command_argument( 2, tname )
call get_command_argument( 3, arg );  read( arg, * ) R0
call get_command_argument( 4, arg );  read( arg, * ) C0
trace = .false.
if ( command_argument_count() >= 5 ) then
   call get_command_argument( 5, arg )
   trace = trim(arg) == 'trace'
end if

open( newunit=lu, file=trim(fname), status='old', action='read', iostat=ios )
if ( ios /= 0 ) then
   write(*,'(a)') 'ls_replay: can not open '//trim(fname)
   call quit( 2 )
end if

!*** The first line that is not a comment names the columns; the next
!*** gives their long names; then the rows.
nhead = 0
ncol  = 0
it = 0; ip = 0; ir = 0; ie = 0
st = zero
first = .true.
nrow = 0
do
   read( lu, '(a)', iostat=ios ) line
   if ( ios /= 0 ) exit
   if ( len_trim(line) == 0 .or. line(1:1) == '#' ) cycle
   nhead = nhead + 1
   if ( nhead == 1 ) then
      call split( line, names, ncol )
      do j = 1, ncol
         if ( trim(names(j)) == 'TIME' ) it = j
         if ( trim(names(j)) == 'GPA.'//trim(tname) ) ip = j
         if ( trim(names(j)) == 'RHO.'//trim(tname) ) ir = j
         if ( trim(names(j)) == 'SIE.'//trim(tname) ) ie = j
      end do
      if ( it*ip*ir*ie == 0 ) then
         write(*,'(a)') 'ls_replay: no tracer '//trim(tname)//' in '// &
            trim(fname)
         call quit( 2 )
      end if
      cycle
   end if
   if ( nhead == 2 ) cycle                       ! the long names
   read( line, *, iostat=ios ) row(1:ncol)
   if ( ios /= 0 ) cycle                         ! a trailer line
   t = row(it)
   if ( .not. first ) then
      call ls_step( st, row(ir), row(ie), row(ip), R0, C0, t, t - tlast )
      nrow = nrow + 1
      if ( trace ) write(*,'(3es25.16e3,i3)') t, row(ip), &
         ls_h( row(ir), row(ie), row(ip), R0 ), nint( st(ls_flag) )
   end if
   first = .false.
   tlast = t
end do
close( lu )

if ( ls_marked( st ) ) then
   write(*,'(a,3es25.16e3)') 'marked', st(ls_ps), st(ls_ts), st(ls_hmax)
else
   write(*,'(a,3es25.16e3)') 'not-marked', zero, zero, st(ls_hmax)
end if

contains

   !*** The comma-separated names of a header line.
   subroutine split( s, w, n )
   implicit none
   character(len=*), intent(in) :: s
   character(len=*), intent(out) :: w(:)
   integer, intent(out) :: n
   integer :: a, b
   n = 0
   a = 1
   do
      b = index( s(a:), ',' )
      n = n + 1
      if ( b == 0 ) then
         w(n) = adjustl( s(a:) )
         exit
      end if
      w(n) = adjustl( s(a:a+b-2) )
      a = a + b
      if ( n == size(w) ) exit
   end do
   end subroutine split

end program ls_replay

program test_hist
!**********************************************************************!
!
!  Purpose:
!    Check one history file, <title>.hist, against its format
!    (input/README.md, section 9). Run by tests/run_hist_tests.sh,
!    which makes the runs; the exit status is 0 if every check
!    passes, 1 if any fails.
!
!       test_hist <file> <status> [<face> <cell>]
!
!    status is the run's expected ending (1 t_end, 2 cycle_max,
!    3 error). With a face and a cell (both numbered from 1, as in
!    the file), it also prints one line per frame,
!
!       F  cycle  time  x(face)  u(face)  P(cell)
!
!    which the script compares with the same run's tracer file.
!
!  Independent of module hist on purpose: this program reads the
!  file the way the README says to, so it checks the README and the
!  writer against each other. Only + - * / and comparisons; a value
!  is tested for NaN or infinity by its bits, never by arithmetic
!  (with -ffpe-trap=invalid, comparing a NaN would stop the program).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/20/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: sp, dp, int32, int64
implicit none

!*** The fixed part (64 bytes).
character(len=8)    :: magic, meth
integer(kind=int32) :: version, header_bytes, frame_bytes, nframes, &
   status, kmax, nvar, nlayer, order, text_bytes, spare(2)
!*** The tables and the text.
character(len=8),  allocatable :: vname(:)
character(len=16), allocatable :: vunit(:)
integer(kind=int32), allocatable :: vwhere(:), vspare(:)
character(len=32), allocatable :: lname(:), lmat(:)
integer(kind=int32), allocatable :: kfirst(:), klast(:)
character(len=:), allocatable :: text
!*** A frame.
real(kind=dp) :: time, tprev
integer(kind=int32) :: cycle, frame, cprev
real(kind=sp), allocatable :: vals(:)
integer(kind=int32), allocatable :: off(:), nval(:)

character(len=256) :: fname, arg
integer(kind=int32) :: lu, ios, j, k, n, want_status, face, cell, nbad
integer(kind=int32) :: ix, iu, ip
integer(kind=int64) :: fsize
logical :: printing

nbad = 0
if ( command_argument_count() < 2 ) then
   write( *, '(a)' ) 'usage: test_hist <file> <status> [<face> <cell>]'
   stop 1, quiet=.true.
end if
call get_command_argument( 1, fname )
call get_command_argument( 2, arg ); read( arg, * ) want_status
printing = ( command_argument_count() >= 4 )
face = 0; cell = 0
if ( printing ) then
   call get_command_argument( 3, arg ); read( arg, * ) face
   call get_command_argument( 4, arg ); read( arg, * ) cell
end if

open( newunit=lu, file=trim(fname), status='old', action='read', &
      access='stream', form='unformatted', iostat=ios )
if ( ios /= 0 ) call fail( 'cannot open '//trim(fname) )
inquire( unit=lu, size=fsize )

!*** 1. Fixed part.
read( lu ) magic, version, header_bytes, frame_bytes, nframes, status, &
   kmax, nvar, nlayer, meth, order, text_bytes, spare
call check( magic == 'BWHIST  ', 'magic is "BWHIST  "' )
call check( version == 1, 'version is 1' )
call check( status == want_status, 'status is '//itoa(want_status)// &
   ' (file: '//itoa(status)//')' )
call check( kmax > 0 .and. nvar > 0 .and. nlayer > 0, &
   'kmax, nvar and nlayer are positive' )
call check( text_bytes == 2048, 'text_bytes is 2048' )
call check( all( spare == 0 ), 'spare bytes are 0' )
call check( ( meth == 'AV' .and. order == 0 ) .or. &
   ( meth == 'RS' .and. ( order == 1 .or. order == 2 ) ), &
   'method and order agree (AV 0; RS 1 or 2)' )
call check( header_bytes == 64 + 32*nvar + 72*nlayer + text_bytes, &
   'header_bytes = 64 + 32 nvar + 72 nlayer + text_bytes' )
if ( nbad > 0 ) call finish()

!*** 2. Variables: this beta's three, in this order, at these places.
allocate( vname(nvar), vunit(nvar), vwhere(nvar), vspare(nvar) )
do j = 1, nvar
   read( lu ) vname(j), vunit(j), vwhere(j), vspare(j)
end do
call check( nvar == 3, 'nvar is 3' )
if ( nvar == 3 ) then
   call check( vname(1) == 'XPOS' .and. vunit(1) == 'mm' .and. &
      vwhere(1) == 0, 'variable 1 is XPOS, mm, faces' )
   call check( vname(2) == 'KMPS' .and. vunit(2) == 'km/s' .and. &
      vwhere(2) == 0, 'variable 2 is KMPS, km/s, faces' )
   call check( vname(3) == 'GPA' .and. vunit(3) == 'GPa' .and. &
      vwhere(3) == 1, 'variable 3 is GPA, GPa, cells' )
end if
call check( all( vspare == 0 ), 'variable spares are 0' )

!*** 3. Layers: they tile cells 1 to kmax, left to right, no gaps.
allocate( lname(nlayer), lmat(nlayer), kfirst(nlayer), klast(nlayer) )
do j = 1, nlayer
   read( lu ) lname(j), lmat(j), kfirst(j), klast(j)
end do
call check( kfirst(1) == 1 .and. klast(nlayer) == kmax, &
   'layers start at cell 1 and end at kmax' )
call check( all( klast >= kfirst ), 'every layer has a cell' )
if ( nlayer > 1 ) call check( all( kfirst(2:) == klast(:nlayer-1) + 1 ), &
   'layers are contiguous' )
call check( all( len_trim(lname) > 0 ) .and. all( len_trim(lmat) > 0 ), &
   'layer and material names are not blank' )

!*** 4. Text: key : value lines, the title and the flags among them.
allocate( character(len=text_bytes) :: text )
read( lu ) text
call check( index(text, 'title   : ') > 0, 'the text names the title' )
call check( index(text, 'flags   : ') > 0, 'the text names the flags' )

!*** Sizes: the frame length follows from the table, and the file is
!*** the header plus nframes whole frames.
allocate( off(nvar), nval(nvar) )
n = 0
do j = 1, nvar
   nval(j) = kmax + 1 - vwhere(j)
   off(j)  = n
   n = n + nval(j)
end do
call check( frame_bytes == 16 + 4*n, 'frame_bytes = 16 + 4 * values' )
call check( nframes > 0, 'nframes is filled in' )
call check( fsize == int(header_bytes,int64) + &
   int(nframes,int64)*int(frame_bytes,int64), &
   'file size = header_bytes + nframes * frame_bytes' )
if ( nbad > 0 ) call finish()

!*** Frames.
allocate( vals(n) )
ix = 1; iu = 2; ip = 3                     ! XPOS, KMPS, GPA (checked)
if ( printing ) call check( face >= 1 .and. face <= kmax + 1 .and. &
   cell >= 1 .and. cell <= kmax, 'the face and cell asked for exist' )
if ( nbad > 0 ) call finish()
cprev = -1; tprev = -1.0_dp
do j = 1, nframes
   read( lu, iostat=ios ) time, cycle, frame, vals
   if ( ios /= 0 ) call fail( 'cannot read frame '//itoa(j) )
   if ( frame /= j ) call fail( 'frame '//itoa(j)//' is numbered '// &
      itoa(frame) )
   if ( j == 1 .and. ( cycle /= 0 .or. abs(time) > 0.0_dp ) ) &
      call fail( 'frame 1 is not cycle 0 at t = 0' )
   if ( cycle <= cprev .or. .not. ( time > tprev ) ) &
      call fail( 'frame '//itoa(j)//': cycle and time do not increase' )
   do k = 1, n
      if ( not_finite32( vals(k) ) ) call fail( 'frame '//itoa(j)// &
         ': a value is not a finite number' )
   end do
   do k = 1, kmax
      if ( .not. ( vals(off(ix)+k+1) > vals(off(ix)+k) ) ) &
         call fail( 'frame '//itoa(j)//': faces '//itoa(k)//' and '// &
            itoa(k+1)//' are not in order' )
   end do
   if ( j == 1 .and. any( abs(vals(off(ip)+1:off(ip)+kmax)) > 0.0_sp ) ) &
      call fail( 'frame 1: P is not 0 everywhere at t = 0' )
   if ( printing ) write( *, '(a,i0,4(1x,es24.16e3))' ) 'F ', cycle, time, &
      real( vals(off(ix)+face), dp ), real( vals(off(iu)+face), dp ), &
      real( vals(off(ip)+cell), dp )
   cprev = cycle; tprev = time
end do
close( lu )
call finish()

contains

   subroutine check( ok, what )
   logical, intent(in) :: ok
   character(len=*), intent(in) :: what
   if ( .not. ok ) then
      write( *, '(a)' ) 'FAIL  '//trim(fname)//': '//what
      nbad = nbad + 1
   end if
   end subroutine check

   subroutine fail( what )
   character(len=*), intent(in) :: what
   call check( .false., what )
   call finish()
   end subroutine fail

   subroutine finish()
   if ( nbad > 0 ) stop 1, quiet=.true.
   stop 0, quiet=.true.
   end subroutine finish

   !*** NaN or infinity: all 8 exponent bits set (IEEE 754 single).
   logical function not_finite32( x )
   real(kind=sp), intent(in) :: x
   not_finite32 = ( iand( ishft( transfer(x, 0_int32), -23 ), 255 ) == 255 )
   end function not_finite32

   function itoa( i ) result(s)
   integer(kind=int32), intent(in) :: i
   character(len=:), allocatable :: s
   character(len=16) :: buf
   write( buf, '(i0)' ) i
   s = trim(buf)
   end function itoa

end program test_hist

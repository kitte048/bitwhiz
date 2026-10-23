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
!       F  cycle  time  x(face)  u(face)  P(cell)  D(cell)
!
!    which the script compares with the same run's tracer file. The
!    last line it prints is always
!
!       B  <cells broken (D = 1) in the last frame>
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
!    10/20/26    D. E. Kittell        DMG (int8, cells) and the variable
!                (with Claude)        type field; the text's plot_dt and
!                                     plot_every lines; B line
!    10/23/26    D. E. Kittell        Exits through quit (module bits),
!                (with Claude)        for gfortran 9 and 10
!
!**********************************************************************!
use bits, only: sp, dp, int8, int32, int64, quit
implicit none

!*** The fixed part (64 bytes).
character(len=8)    :: magic, meth
integer(kind=int32) :: version, header_bytes, frame_bytes, nframes, &
   status, kmax, nvar, nlayer, order, text_bytes, spare(2)
!*** The tables and the text.
character(len=8),  allocatable :: vname(:)
character(len=16), allocatable :: vunit(:)
integer(kind=int32), allocatable :: vwhere(:), vtype(:), nval(:)
character(len=32), allocatable :: lname(:), lmat(:)
integer(kind=int32), allocatable :: kfirst(:), klast(:)
character(len=:), allocatable :: text
!*** A frame: XPOS, KMPS (faces), GPA (cells) and DMG (cells).
real(kind=dp) :: time, tprev
integer(kind=int32) :: cycle, frame, cprev
real(kind=sp), allocatable :: x(:), u(:), p(:)
integer(kind=int8), allocatable :: d(:)

character(len=256) :: fname, arg
integer(kind=int32) :: lu, ios, j, k, want_status, face, cell, nbad, nbytes
integer(kind=int64) :: fsize
logical :: printing

nbad = 0
if ( command_argument_count() < 2 ) then
   write( *, '(a)' ) 'usage: test_hist <file> <status> [<face> <cell>]'
   call quit( 1 )
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

!*** 2. Variables: this version's four, in this order, at these places,
!*** of these types (0 real32, 1 int8).
allocate( vname(nvar), vunit(nvar), vwhere(nvar), vtype(nvar), nval(nvar) )
do j = 1, nvar
   read( lu ) vname(j), vunit(j), vwhere(j), vtype(j)
end do
call check( nvar == 4, 'nvar is 4' )
if ( nbad > 0 ) call finish()
call check( vname(1) == 'XPOS' .and. vunit(1) == 'mm' .and. &
   vwhere(1) == 0 .and. vtype(1) == 0, 'variable 1 is XPOS, mm, faces, real32' )
call check( vname(2) == 'KMPS' .and. vunit(2) == 'km/s' .and. &
   vwhere(2) == 0 .and. vtype(2) == 0, 'variable 2 is KMPS, km/s, faces, real32' )
call check( vname(3) == 'GPA' .and. vunit(3) == 'GPa' .and. &
   vwhere(3) == 1 .and. vtype(3) == 0, 'variable 3 is GPA, GPa, cells, real32' )
call check( vname(4) == 'DMG' .and. vunit(4) == '-' .and. &
   vwhere(4) == 1 .and. vtype(4) == 1, 'variable 4 is DMG, -, cells, int8' )

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

!*** 4. Text: key : value lines, among them the title, the flags and
!*** the snapshot rule.
allocate( character(len=text_bytes) :: text )
read( lu ) text
call check( index(text, 'title   : ') > 0, 'the text names the title' )
call check( index(text, 'flags   : ') > 0, 'the text names the flags' )
call check( index(text, new_line('a')//'plot_dt    : ') > 0 .and. &
   index(text, new_line('a')//'plot_every : ') > 0, &
   'the text has plot_dt and plot_every' )

!*** Sizes: the frame length follows from the table (4 bytes a real32,
!*** 1 an int8), and the file is the header plus nframes whole frames.
nbytes = 16
do j = 1, nvar
   nval(j) = kmax + 1 - vwhere(j)
   nbytes  = nbytes + nval(j)*merge( 4, 1, vtype(j) == 0 )
end do
call check( frame_bytes == nbytes, 'frame_bytes = 16 + the values'' bytes' )
call check( nframes > 0, 'nframes is filled in' )
call check( fsize == int(header_bytes,int64) + &
   int(nframes,int64)*int(frame_bytes,int64), &
   'file size = header_bytes + nframes * frame_bytes' )
if ( nbad > 0 ) call finish()

!*** Frames.
allocate( x(kmax+1), u(kmax+1), p(kmax), d(kmax) )
if ( printing ) call check( face >= 1 .and. face <= kmax + 1 .and. &
   cell >= 1 .and. cell <= kmax, 'the face and cell asked for exist' )
if ( nbad > 0 ) call finish()
cprev = -1; tprev = -1.0_dp
do j = 1, nframes
   read( lu, iostat=ios ) time, cycle, frame, x, u, p, d
   if ( ios /= 0 ) call fail( 'cannot read frame '//itoa(j) )
   if ( frame /= j ) call fail( 'frame '//itoa(j)//' is numbered '// &
      itoa(frame) )
   if ( j == 1 .and. ( cycle /= 0 .or. abs(time) > 0.0_dp ) ) &
      call fail( 'frame 1 is not cycle 0 at t = 0' )
   if ( cycle <= cprev .or. .not. ( time > tprev ) ) &
      call fail( 'frame '//itoa(j)//': cycle and time do not increase' )
   if ( any( not_finite32(x) ) .or. any( not_finite32(u) ) .or. &
        any( not_finite32(p) ) ) call fail( 'frame '//itoa(j)// &
      ': a value is not a finite number' )
   do k = 1, kmax
      if ( .not. ( x(k+1) > x(k) ) ) call fail( 'frame '//itoa(j)// &
         ': faces '//itoa(k)//' and '//itoa(k+1)//' are not in order' )
   end do
   if ( any( d /= 0_int8 .and. d /= 1_int8 ) ) call fail( 'frame '// &
      itoa(j)//': a DMG value is not 0 or 1' )
   if ( j == 1 .and. any( abs(p) > 0.0_sp ) ) &
      call fail( 'frame 1: P is not 0 everywhere at t = 0' )
   if ( j == 1 .and. any( d /= 0_int8 ) ) &
      call fail( 'frame 1: a cell is broken at t = 0' )
   if ( printing ) write( *, '(a,i0,4(1x,es24.16e3),1x,i0)' ) 'F ', &
      cycle, time, real( x(face), dp ), real( u(face), dp ), &
      real( p(cell), dp ), int( d(cell), int32 )
   cprev = cycle; tprev = time
end do
close( lu )
write( *, '(a,i0)' ) 'B ', count( d == 1_int8 )
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
   if ( nbad > 0 ) call quit( 1 )
   call quit( 0 )
   end subroutine finish

   !*** NaN or infinity: all 8 exponent bits set (IEEE 754 single).
   elemental logical function not_finite32( v )
   real(kind=sp), intent(in) :: v
   not_finite32 = ( iand( ishft( transfer(v, 0_int32), -23 ), 255 ) == 255 )
   end function not_finite32

   function itoa( i ) result(s)
   integer(kind=int32), intent(in) :: i
   character(len=:), allocatable :: s
   character(len=16) :: buf
   write( buf, '(i0)' ) i
   s = trim(buf)
   end function itoa

end program test_hist

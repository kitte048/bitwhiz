module trace
!**********************************************************************!
!
!  Purpose:
!    The tracer file, <title>.tracers.csv: the history of every tracer
!    in the deck's Output block, one row per output time, laid out
!    like the verification data (tests/verification) so one reader
!    handles both:
!
!       line 1   short names:  TIME, CYCLE, DTIME, MTOT, ..., XPOS.pdv, ...
!       line 2   long names with units
!       rows     comma-separated numbers, full double precision
!       trailer  "# ===== end of data =====" and then '#' lines: where
!                the run came from, how it ended, and where each tracer
!                sits on the mesh
!
!    Every trailer line starts with '#', so numpy (loadtxt, genfromtxt)
!    and pandas (comment='#') skip it. The trailer is written by every
!    way out of a run that the code controls (maincode, close_outputs),
!    so a file WITHOUT the end-of-data line is from a run that crashed.
!
!    Called from maincode only, outside the parallel region, so the
!    file is the same on any number of threads.
!
!  Units, as everywhere in bitwhiz: mm, us, g/cm^3, km/s, GPa,
!  e in kJ/g = (km/s)^2, totals per unit area (masses in g/cm^3*mm).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    10/15/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits,  only: dp, int32, zero
use shock, only: jx, ju, jrho, je, jp, jq, jc, jdam, face_slots, &
   database, iface, icell, ilay, layer, tracer, ntrc, tracer_dt
implicit none
private

public :: open_tracers, tracer_row, close_tracers, trc_open, trc_file

!**********************************************************************!
! THE COLUMN TABLE. One row per column of each tracer, in the order
! they appear in the file. To add a variable, add one row (its slot
! in the database, a short name and a long name with units) and bump
! ncol. New columns go at the END, so old columns never move and old
! plotting scripts, which find columns by name, keep working.
!
! A face slot (x, u) is interpolated between the tracer's two faces
! with its weight w; a cell slot is read from the tracer's cell kval
! (shock_mod, tracer table).
!**********************************************************************!
integer(kind=int32), parameter :: ncol = 8
integer(kind=int32), parameter, dimension(ncol) :: col_slot = (/ &
   jx, ju, jp, jrho, je, jq, jc, jdam /)
character(len=4), parameter, dimension(ncol) :: col_short = (/ &
   'XPOS', 'KMPS', 'GPA ', 'RHO ', 'SIE ', 'Q   ', 'CS  ', 'DMG ' /)
character(len=34), parameter, dimension(ncol) :: col_long = (/ &
   'X Position (mm)                   ', &
   'Velocity (km/s)                   ', &
   'Pressure (GPa)                    ', &
   'Density (g/cm^3)                  ', &
   'Specific Internal Energy (kJ/g)   ', &
   'Artificial Viscosity (GPa)        ', &
   'Sound Speed (km/s)                ', &
   'Damage (0 intact, 1 broken)       ' /)

!*** The whole-problem columns that start every row (per unit area).
integer(kind=int32), parameter :: ntot = 8
character(len=5), parameter, dimension(ntot) :: tot_short = (/ &
   'TIME ', 'CYCLE', 'DTIME', 'MTOT ', 'ETOT ', 'EK   ', 'EINT ', &
   'XMOM ' /)
character(len=34), parameter, dimension(ntot) :: tot_long = (/ &
   'Time (us)                         ', &
   'Cycle Number                      ', &
   'Dt (us)                           ', &
   'Total Mass (g/cm^3*mm)            ', &
   'Total Energy (GPa*mm)             ', &
   'Kinetic Energy (GPa*mm)           ', &
   'Internal Energy (GPa*mm)          ', &
   'X Momentum (g/cm^3*mm*km/s)       ' /)

!*** The file. "Is it open?" is trc_open, never a test on the unit.
integer(kind=int32) :: ktr      = 0            ! unit number
logical             :: trc_open = .false.      ! the file is open
character(len=72)   :: trc_file = ' '          ! <title>.tracers.csv
integer(kind=int32) :: nrows    = 0            ! rows written so far
real(kind=dp)       :: tnext    = zero         ! us, next output time
logical             :: isface(ncol)            ! column is a face slot

!*** One row: 8 totals (CYCLE goes out as an integer) and ncol values
!*** per tracer. Sized when the file is opened.
real(kind=dp), allocatable :: row(:)

contains

   !******************************************************************!
   ! Open <title>.tracers.csv and write its two header lines. With no !
   ! tracers in the deck there is nothing to write: no file, and      !
   ! ios = 0. ios /= 0 means the file could not be opened.           !
   !******************************************************************!
   subroutine open_tracers( title, ios )
   implicit none
   character(len=*), intent(in) :: title
   integer(kind=int32), intent(out) :: ios
   integer(kind=int32) :: it, j

   ios = 0
   if ( ntrc == 0 ) return
   trc_file = trim(title)//'.tracers.csv'
   open( newunit=ktr, file=trim(trc_file), status='replace', &
         action='write', iostat=ios )
   if ( ios /= 0 ) return
   trc_open = .true.
   nrows    = 0
   tnext    = zero
   do j = 1, ncol
      isface(j) = any( face_slots == col_slot(j) )
   end do
   allocate( row( ntot - 1 + ncol*ntrc ) )

   !*** Line 1, short names: a tracer's columns carry its name, e.g.
   !*** KMPS.pdv (the verification data number them instead: KMPS.4).
   write( ktr, '(a)', advance='no' ) trim(tot_short(1))
   do j = 2, ntot
      write( ktr, '(a)', advance='no' ) ', '//trim(tot_short(j))
   end do
   do it = 1, ntrc
      do j = 1, ncol
         write( ktr, '(a)', advance='no' ) ', '//trim(col_short(j))// &
            '.'//trim(tracer(it)%name)
      end do
   end do
   write( ktr, '(a)' ) ''

   !*** Line 2, long names with units.
   write( ktr, '(a)', advance='no' ) trim(tot_long(1))
   do j = 2, ntot
      write( ktr, '(a)', advance='no' ) ', '//trim(tot_long(j))
   end do
   do it = 1, ntrc
      do j = 1, ncol
         write( ktr, '(a)', advance='no' ) ', '//trim(col_long(j))
      end do
   end do
   write( ktr, '(a)' ) ''
   end subroutine open_tracers

   !******************************************************************!
   ! One row, if this cycle is an output time. Called once per cycle, !
   ! after the heartbeat line, with that line's totals.               !
   !                                                                  !
   ! tracer_dt = 0: every cycle. Otherwise the first cycle at or      !
   ! after each multiple of tracer_dt, at that cycle's own time       !
   ! (nothing is interpolated in time: the comparison script does     !
   ! that, as it must for the reference data anyway). Cycle 0 and the !
   ! last cycle are always written. The next output time is counted   !
   ! in whole multiples of tracer_dt, so it never drifts.             !
   !                                                                  !
   ! The row holds the state at the end of the cycle: x, P, rho, e,   !
   ! q, c, D at TIME, and u at the half step before it (n+1/2), the   !
   ! velocity the method carries (the heartbeat uses the same one).   !
   !******************************************************************!
   subroutine tracer_row( ncycle, time, dtu, mtot, etot, ekin, eint, &
      xmom, last )
   implicit none
   integer(kind=int32), intent(in) :: ncycle ! cycle number, n
   real(kind=dp), intent(in) :: time      ! us
   real(kind=dp), intent(in) :: dtu       ! us, the step just taken
   real(kind=dp), intent(in) :: mtot      ! g/cm^3*mm
   real(kind=dp), intent(in) :: etot      ! GPa*mm
   real(kind=dp), intent(in) :: ekin      ! GPa*mm
   real(kind=dp), intent(in) :: eint      ! GPa*mm
   real(kind=dp), intent(in) :: xmom      ! g/cm^3*mm*km/s
   logical, intent(in) :: last            ! the run's last cycle
   integer(kind=int32) :: it, j, n, ia, ib, ic
   real(kind=dp) :: w

   if ( .not. trc_open ) return
   if ( tracer_dt > zero .and. ncycle > 0 .and. .not. last .and. &
        time < tnext ) return
   if ( tracer_dt > zero ) &
      tnext = ( aint( time/tracer_dt ) + 1.0_dp )*tracer_dt

   row(1:ntot-1) = (/ time, dtu, mtot, etot, ekin, eint, xmom /)
   n = ntot - 1
   do it = 1, ntrc
      ia = iface( tracer(it)%kface )        ! face on the left
      ib = iface( tracer(it)%kface + 1 )    ! face on the right (w > 0)
      ic = icell( tracer(it)%kval )         ! the cell it reports
      w  = tracer(it)%w
      do j = 1, ncol
         n = n + 1
         if ( .not. isface(j) ) then
            row(n) = database( col_slot(j), ic )
         else if ( w > zero ) then
            row(n) = (1.0_dp - w)*database( col_slot(j), ia ) + &
                     w*database( col_slot(j), ib )
         else
            row(n) = database( col_slot(j), ia )   ! exactly on a node
         end if
      end do
   end do

   !*** One write per row (fast): TIME, then CYCLE as an integer, then
   !*** the rest. es0.16e3 is 17 significant digits, all a double has,
   !*** so a row read back is the same number to the last bit.
   write( ktr, '(es0.16e3,a,i0,*(a,es0.16e3))' ) row(1), ', ', ncycle, &
      ( ', ', row(j), j = 2, n )
   nrows = nrows + 1
   end subroutine tracer_row

   !******************************************************************!
   ! The trailer, then close. info holds the run's lines (deck, how   !
   ! it ended, ...), written as given after a '# '; this routine adds !
   ! the rows, the output rule and where each tracer sits.            !
   !******************************************************************!
   subroutine close_tracers( info )
   implicit none
   character(len=*), dimension(:), intent(in) :: info
   integer(kind=int32) :: it, j
   character(len=32) :: buf
   character(len=:), allocatable :: line

   if ( .not. trc_open ) return
   write( ktr, '(a)' ) '# ===== end of data ====='
   do j = 1, size(info)
      write( ktr, '(a)' ) '# '//trim(info(j))
   end do
   write( buf, '(i0)' ) nrows
   if ( tracer_dt > zero ) then
      write( ktr, '(a)' ) '# rows     : '//trim(buf)//', tracer_dt = '// &
         fnum(tracer_dt)//' us (first cycle at or after each multiple; '// &
         'cycle 0 and the last cycle always)'
   else
      write( ktr, '(a)' ) '# rows     : '//trim(buf)//', one every cycle '// &
         '(tracer_dt = 0)'
   end if
   write( ktr, '(a)' ) '# columns  : x, P, rho, e, q, c, D at TIME; u at '// &
      'the half step before TIME (n+1/2), as the method carries it'
   do it = 1, ntrc
      associate ( t => tracer(it) )
         write( buf, '(i0)' ) it
         line = '# tracer '//trim(buf)//' '//trim(t%name)//' : '// &
            trim(t%at)//', x0 = '//fnum(t%x0)//' mm, '
         if ( t%w > zero ) then
            line = line//'between faces '//inum(t%kface)//' and '// &
               inum(t%kface + 1)//' (w = '//fnum(t%w)//'), in cell '// &
               inum(t%kval)
         else
            line = line//'on face '//inum(t%kface)// &
               '; cell values from cell '//inum(t%kval)
         end if
         line = line//' ('//trim(layer(ilay(icell(t%kval)))%name)//')'
         write( ktr, '(a)' ) line
      end associate
   end do
   close( ktr )
   trc_open = .false.
   if ( allocated(row) ) deallocate( row )
   end subroutine close_tracers

   !*** Numbers as text for the trailer, without padding and with the
   !*** leading zero (f0.6 would print 0.005 as ".005000").
   function fnum( x ) result(s)
   implicit none
   real(kind=dp), intent(in) :: x
   character(len=:), allocatable :: s
   character(len=32) :: buf
   write( buf, '(f32.6)' ) x
   s = trim(adjustl(buf))
   end function fnum

   function inum( n ) result(s)
   implicit none
   integer(kind=int32), intent(in) :: n
   character(len=:), allocatable :: s
   character(len=12) :: buf
   write( buf, '(i0)' ) n
   s = trim(buf)
   end function inum

end module trace

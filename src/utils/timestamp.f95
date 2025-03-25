subroutine timestamp ( cpu )
!**********************************************************************!
!  About:                                                              !
!    TIMESTAMP is a FORTRAN77 style code, adapted from one that is     !
!    distributed under the GNU LGPL license. The original author is    !
!    John Burkardt, last modified 12 January 2007.                     !
!                                                                      !
!  Purpose:                                                            !
!    To convert the current YMDHMS into a timestamp.                   !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    11/19/23    D. E. Kittell      Started from J. Burkardt's code    !
!                                                                      !
!**********************************************************************!
use bits, only: dp,six,ten,kpt6
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
real(kind=dp), intent(out) :: cpu

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
character * ( 8 ) :: ampm
integer :: d
character * ( 8 ) :: date
integer :: h
integer :: m
integer :: mm
character * ( 9 ) :: month(12)
integer :: n
integer :: s
character * ( 10 ) :: time
integer :: y

save month

data month / &
  'January  ', 'February ', 'March    ', 'April    ', &
  'May      ', 'June     ', 'July     ', 'August   ', &
  'September', 'October  ', 'November ', 'December ' /

call date_and_time ( date, time )

read ( date, '(i4,i2,i2)' ) y, m, d
read ( time, '(i2,i2,i2,1x,i3)' ) h, n, s, mm

cpu = h*(six*ten)**2 + n*(six*ten) + s + mm/(ten**3)

check24hour: if ( h .lt. 12 ) then
   ampm = 'AM'
else if ( h .eq. 12 ) then
   if ( n .eq. 0 .and. s .eq. 0 ) then
      ampm = 'Noon'
   else
      ampm = 'PM'
   end if
else
   h = h - 12
   if ( h .lt. 12 ) then
      ampm = 'PM'
   else if ( h .eq. 12 ) then
      if ( n .eq. 0 .and. s .eq. 0 ) then
         ampm = 'Midnight'
      else
         ampm = 'AM'
      end if
   end if
end if check24hour

write ( kpt6, &
  '(i2,1x,a,1x,i4,2x,i2,a1,i2.2,a1,i2.2,a1,i3.3,1x,a)' ) &
  d, month(m), y, h, ':', n, ':', s, '.', mm, ampm

return
end subroutine

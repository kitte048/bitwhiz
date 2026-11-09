program drv_burn
! Audit driver for the rate laws. Lines:
!  H phi MR XR            -> hvrb_lambda
!  R p PR ZR PI TAU0      -> hvrb_rate
!  T T Ps HT TC GT NS PR  -> tc_rate
!  O x                    -> tc_om
!  S lam1 r dt            -> tc_step
use bits,           only: dp
use hvrb,           only: hvrb_lambda, hvrb_rate
use thermalcascade, only: tc_rate, tc_step, tc_om
implicit none
character(len=1) :: kind
character(len=400) :: line
real(kind=dp) :: a(7), r
integer :: ios
do
   read( *, '(a)', iostat=ios ) line
   if ( ios /= 0 ) exit
   kind = line(1:1)
   select case ( kind )
   case ( 'H' ); read( line(2:), * ) a(1:3); r = hvrb_lambda( a(1), a(2), a(3) )
   case ( 'R' ); read( line(2:), * ) a(1:5); r = hvrb_rate( a(1), a(2), a(3), a(4), a(5) )
   case ( 'T' ); read( line(2:), * ) a(1:7); r = tc_rate( a(1), a(2), a(3), a(4), a(5), a(6), a(7) )
   case ( 'O' ); read( line(2:), * ) a(1:1); r = tc_om( a(1) )
   case ( 'S' ); read( line(2:), * ) a(1:3); r = tc_step( a(1), a(2), a(3) )
   case default; cycle
   end select
   write( *, '(1x,es24.17)' ) r
end do
end program drv_burn

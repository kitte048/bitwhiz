program drv_mix
! Audit driver: read "rho e lam es R0 C0 S1 S2 G0 cv T0 gamma Q rhold eshold"
! lines; print p c theta dpdlam ifb ierr from mix_state (held if rhold > 0).
use bits,    only: dp, int32
use mixture, only: mix_state
implicit none
real(kind=dp) :: rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, gam, Q, rhold, eshold
real(kind=dp) :: p, c, theta, dpdlam
integer(kind=int32) :: ifb, ierr, ios
do
   read( *, *, iostat=ios ) rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, gam, Q, rhold, eshold
   if ( ios /= 0 ) exit
   if ( rhold > 0.0_dp ) then
      call mix_state( rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, gam, Q, &
         p, c, theta, dpdlam, ifb, ierr, rhold, eshold )
   else
      call mix_state( rho, e, lam, es, R0, C0, S1, S2, G0, cv, T0, gam, Q, &
         p, c, theta, dpdlam, ifb, ierr )
   end if
   if ( ierr == 0 ) then
      write( *, '(4(1x,es24.17),2(1x,i0))' ) p, c, theta, dpdlam, ifb, ierr
   else
      write( *, '(a,1x,es24.17,2(1x,i0))' ) ' nan nan', theta, ifb, ierr
   end if
end do
end program drv_mix

program drv_eos
! Audit driver: read "rho e R0 C0 S1 S2 G0" lines from stdin, print p, c, ierr
! from bitwhiz's mg_eos at full precision. Not part of bitwhiz.
use bits, only: dp, int32
use eos,  only: mg_eos
implicit none
real(kind=dp) :: rho, e, R0, C0, S1, S2, G0, p, c
integer(kind=int32) :: ierr, ios
do
   read( *, *, iostat=ios ) rho, e, R0, C0, S1, S2, G0
   if ( ios /= 0 ) exit
   call mg_eos( rho, e, R0, C0, S1, S2, G0, p, c, ierr )
   if ( ierr == 0 ) then
      write( *, '(2(1x,es24.17),1x,i0)' ) p, c, ierr
   else
      write( *, '(a,1x,i0)' ) ' nan nan', ierr
   end if
end do
end program drv_eos

subroutine r8_uniform_01 ( scalar )
!**********************************************************************!
!  About:                                                              !
!    This code is random number generator that I made myself. It uses  !
!    the random module, which contains >10k random numbers based on    !
!    atmospheric noise. Then, using the bootstrap sampling method, it  !
!    returns one of these values at random.                            !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    03/31/25    D. E. Kittell      Original code.                     !
!                                                                      !
!**********************************************************************!
use bits, only: dp,int64
use random, only: nbig,randlist
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
real(kind=dp), intent(out) :: scalar

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.                      !
!**********************************************************************!
real(kind=dp) :: u               ! Resampled dataset
integer(kind=int64) :: i, rand_index

! Bootstrap method.
call random_number(u)            ! Generate a random number in (0,1)
rand_index = min(int(u * nbig) + 1, nbig)   ! Scale to 1:N 
scalar = randlist(rand_index)    ! Pick a random value from original data

return
end subroutine

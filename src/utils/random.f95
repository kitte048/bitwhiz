!**********************************************************************!
!  About:                                                              !
!    File "random.f95" contains two pseudorandom number generators     !
!    that sample the standard normal PDF and uniform distributions.    !
!    These functions had been developed in F77 by John Burkardt; all   !
!    license agreements and source documentation are found with the    !
!    individual function descriptions. Converted into F95 by David     !
!    Kittell, beginning August 2018.                                   !
!                                                                      !
! ~REAL NUMBERS~                                                       !
!    function r8_normal_01 ( seed )                                    !
!    function r8_uniform_01 ( seed )                                   !
!                                                                      !
!**********************************************************************!

function r8_normal_01 ( seed )
!**********************************************************************!
!                                                                      !
!  R8_NORMAL_01 returns a unit pseudonormal R8.                        !
!                                                                      !
!  Licensing:                                                          !
!                                                                      !
!    This code is distributed under the GNU LGPL license.              !
!                                                                      !
!  Modified:                                                           !
!                                                                      !
!    06 August 2013                                                    !
!                                                                      !
!  Author:                                                             !
!                                                                      !
!    John Burkardt                                                     !
!                                                                      !
!                                                                      !
!  Parameters:                                                         !
!                                                                      !
!    Input/output, integer SEED for the random number generator.       !
!                                                                      !
!    Output, R8_NORMAL_01, a sample of the standard normal PDF.        !
!                                                                      !
!**********************************************************************!
use bits, only: dp,int64
implicit none
real(kind=dp) :: r1
real(kind=dp) :: r2
real(kind=dp) :: r8_normal_01
real(kind=dp),parameter :: r8_pi = 3.141592653589793D+00
real(kind=dp) :: r8_uniform_01
integer(kind=int64) :: seed
real(kind=dp) :: x

r1 = r8_uniform_01 ( seed )
r2 = r8_uniform_01 ( seed )
x = sqrt ( - 2.0D+00 * log ( r1 ) ) &
   * cos ( 2.0D+00 * r8_pi * r2 )

r8_normal_01 = x

return
end function

function r8_uniform_01 ( seed )
!**********************************************************************!
!                                                                      !
!  R8_UNIFORM_01 returns a unit pseudorandom R8.                       !
!                                                                      !
!  Discussion:                                                         !
!                                                                      !
!    This routine implements the recursion                             !
!                                                                      !
!      seed = 16807 * seed mod ( 2^31 - 1 )                            !
!      r8_uniform_01 = seed / ( 2^31 - 1 )                             !
!                                                                      !
!    The integer arithmetic never requires more than 32 bits,          !
!    including a sign bit.                                             !
!                                                                      !
!    If the initial seed is 12345, then the first three computations   !
!    are                                                               !
!                                                                      !
!      Input     Output      R8_UNIFORM_01                             !
!      SEED      SEED                                                  !
!                                                                      !
!         12345   207482415  0.096616                                  !
!     207482415  1790989824  0.833995                                  !
!    1790989824  2035175616  0.947702                                  !
!                                                                      !
!  Licensing:                                                          !
!                                                                      !
!    This code is distributed under the GNU LGPL license.              !
!                                                                      !
!  Modified:                                                           !
!                                                                      !
!    17 July 2006                                                      !
!                                                                      !
!  Author:                                                             !
!                                                                      !
!    John Burkardt                                                     !
!                                                                      !
!  Reference:                                                          !
!                                                                      !
!    Paul Bratley, Bennett Fox, Linus Schrage,                         !
!    A Guide to Simulation,                                            !
!    Springer Verlag, pages 201-202, 1983.                             !
!                                                                      !
!    Pierre L'Ecuyer,                                                  !
!    Random Number Generation,                                         !
!    in Handbook of Simulation,                                        !
!    edited by Jerry Banks,                                            !
!    Wiley Interscience, page 95, 1998.                                !
!                                                                      !
!    Bennett Fox,                                                      !
!    Algorithm 647:                                                    !
!    Implementation and Relative Efficiency of Quasirandom             !
!    Sequence Generators,                                              !
!    ACM Transactions on Mathematical Software,                        !
!    Volume 12, Number 4, pages 362-376, 1986.                         !
!                                                                      !
!    Peter Lewis, Allen Goodman, James Miller,                         !
!    A Pseudo-Random Number Generator for the System/360,              !
!    IBM Systems Journal,                                              !
!    Volume 8, pages 136-143, 1969.                                    !
!                                                                      !
!  Parameters:                                                         !
!                                                                      !
!    Input/output, integer SEED, the "seed" value, which               !
!    should NOT be 0. On output, SEED has been updated.                !
!                                                                      !
!    Output, double precision R8_UNIFORM_01, a new pseudorandom        !
!    variate, strictly between 0 and 1.                                !
!                                                                      !
!**********************************************************************!
use bits, only: dp,int32,int64
implicit none
integer(kind=int32), parameter :: i4_huge = 2147483647
integer(kind=int64) :: kk
real(kind=dp) :: r8_uniform_01
integer(kind=int64) :: seed

kk = seed / 127773

seed = 16807 * ( seed - kk * 127773 ) - kk * 2836

if ( seed .lt. 0 ) then
   seed = seed + i4_huge
end if
!
!  Although SEED can be represented exactly as a 32 bit integer,
!  it generally cannot be represented exactly as a 32 bit real number!
!
r8_uniform_01 = dble ( seed ) * 4.656612875D-10

return
end

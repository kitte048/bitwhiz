subroutine cmap_extendedkindlmann(nx,ny,fcn,RGB,npr)
!**********************************************************************!
!  About:                                                              !
!    CMAP_EXTENDEDKINDLMANN is one of the color map options.           !
!    In addition, this map allows users to permute the RGB channels,   !
!    for up to 6 different maps from the same high-def data.           !
!                                                                      !
!    All of the scalar and RGB channel data comes from                 !
!                                                                      !
!         http://www.kennethmoreland.com/color-advice/                 !
!                                                                      !
!    See also Kenneth Moreland's paper, entitled "Why we use bad color !
!    maps and what you can do about it."                               !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer        Description of change              !
!      ====       ==========        =====================              !
!    11/26/23    D. E. Kittell      Original code.                     !
!    10/06/26    Claude (for DEK)   F2018 clean: character(len=), int32 !
!                                   locals, explicit int() truncation  !
!    10/06/26    Claude (for DEK)   Blend real channel values, then    !
!                                   truncate once (was int, then blend)!
!    10/06/26    Claude (for DEK)   Round to nearest, nint() (was int  !
!                                   truncation) for the 0-255 channels !
!                                                                      !
!**********************************************************************!
use bits, only: int16,int32,dp,zero,one,i,j,k
use extendedkindlmann, only: ncls,ctable,scalar
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.
!**********************************************************************!
integer(kind=int32), intent(in) :: nx,ny               ! pixel size
integer(kind=int16), intent(in) :: npr                 ! permutation
real(kind=dp), dimension(nx,ny), intent(in) :: fcn     ! real vals [0,1]
character(len=1), dimension(nx,ny,3), intent(out) :: RGB    ! RGB values

!**********************************************************************!
! Data dictionary: Subroutine Internal Variables.
!**********************************************************************!
integer(kind=int32) :: i1,i2                           ! color indices
real(kind=dp) :: a,b                                   ! channel ends [0,255]
integer(kind=int32) :: ch1,ch2,ch3      ! 0-255 channel value
integer(kind=int32), dimension(3) :: id ! column ID for permutation
real(kind=dp) :: val                    ! original values check if [0,1]
real(kind=dp) :: x1,x2,w1,w2            ! constants for interpolation

! Choose the ordering of RGB channels.
npr_if: if (npr .eq. 1) then
   id = (/1,2,3/) ! Correct Ordering.
else if (npr .eq. 2) then
   id = (/1,3,2/)
else if (npr .eq. 3) then
   id = (/2,1,3/)
else if (npr .eq. 4) then
   id = (/2,3,1/)
else if (npr .eq. 5) then
   id = (/3,1,2/)
else if (npr .eq. 6) then
   id = (/3,2,1/)
else
   id = (/1,2,3/) ! Correct Ordering.
end if npr_if

! Loop over scalars to convert to RGB.
do i=1,nx,1
   do j=1,ny,1

      ! Preprocess scalar value.
      val = min(max(fcn(i,j),zero),one)

      ! Bound the value from the bottom.
      i1 = 1
      lower_bound: do k=1,ncls,1
         if ( val .ge. scalar( k ) ) then
            i1 = k
         else
            exit lower_bound
         end if
      end do lower_bound

      ! Bound the value from the top.
      i2 = ncls
      upper_bound: do k=ncls,1,-1
         if ( scalar( k ) .ge. val ) then
            i2 = k
         else
            exit upper_bound
         end if
      end do upper_bound

      ! Do this so that i1 and i2 are different.
      if ( i1 .lt. ncls ) i2=i1+1
      if ( i2 .gt. 1 ) i1=i2-1
      if ( i1 .eq. i2 ) write(*,*)"OOPS! Something went wrong in CMAP."

      ! Calculate weighting values.
      x1 = scalar(i1)
      x2 = scalar(i2)
      w1 = ( x2 - val ) / ( x2 - x1 )
      w2 = ( val - x1 ) / ( x2 - x1 )

      ! Ch1 - Blending Analysis.
      a = ctable( i1, id(1) ) * 255.0_dp
      b = ctable( i2, id(1) ) * 255.0_dp
      ch1 = min(max(nint( w1 * a + w2 * b ),0),255)

      ! Ch2 - Blending Analysis.
      a = ctable( i1, id(2) ) * 255.0_dp
      b = ctable( i2, id(2) ) * 255.0_dp
      ch2 = min(max(nint( w1 * a + w2 * b ),0),255)

      ! Ch3 - Blending Analysis.
      a = ctable( i1, id(3) ) * 255.0_dp
      b = ctable( i2, id(3) ) * 255.0_dp
      ch3 = min(max(nint( w1 * a + w2 * b ),0),255)

      ! Package the results.
      RGB(i,j,1) = achar(ch3)
      RGB(i,j,2) = achar(ch2)
      RGB(i,j,3) = achar(ch1)
   end do
end do

return
end subroutine cmap_extendedkindlmann

subroutine draw_trace( bout, n, t, u, ylo, yhi )
!**********************************************************************!
!  About:                                                              !
!    DRAW_TRACE makes one tracer plot (velocity against time) as a     !
!    fixed-size bitmap, 800 by 600 pixels: draw_profile draws it, with !
!    time across from the first point to the last and the title        !
!    BITWHIZ SCOPE VIEW. Called by module pics (maincode section 9),   !
!    once per tracer, after a run and in a plots_only run. What        !
!    follows describes the picture; the code is draw_profile's.        !
!                                                                      !
!    The picture: a white page, a margin of nm pixels, and inside it   !
!    the plot area, framed by a box with rounded outside corners (the  !
!    spines) and tick marks at tenths of each axis, pointing in; in    !
!    it, the tracer's velocity against time, a line through its n      !
!    points. Time runs across, from the first point (the left edge of  !
!    the plot area) to the last (the right edge); velocity up, from    !
!    ylo (the bottom edge) to yhi (the top edge). The only text is a   !
!    title engraved in the margin above the box, BITWHIZ SCOPE VIEW;   !
!    the screen gives the ranges.                                      !
!                                                                      !
!    THE TITLE is drawn with strokes, like the curve: each letter is a !
!    few straight lines and elliptical arcs in a cell one cap height   !
!    tall, from bitwhiz's own small stroke font (module strokes, which !
!    also draws the frame, so draw_tx's pictures share this look), set !
!    at th pixels with strokes tsw wide, in slate, centered over the   !
!    box and in the margin's height. A stroke font keeps the letters   !
!    anti-aliased the same way as everything else, with no font file.  !
!                                                                      !
!    Colors, from the equation sheets' figures (the Okabe-Ito palette, !
!    which colorblind readers can tell apart, beside a dark ink): the  !
!    frame slate #2C3E50 (the sheets' ink), the curve vermilion        !
!    #D55E00. The curve is 3.0 pixels wide, a little wider than the    !
!    2.5-pixel spines; where they meet, the frame is on top.           !
!                                                                      !
!    ANTI-ALIASING. Everything is drawn at ns x ns samples per pixel,  !
!    each sample frame ink, curve ink or paper, and each pixel takes   !
!    the fraction of its samples of each, its coverages cf and cc:     !
!       color = cf*slate + cc*vermilion + (1 - cf - cc)*white.         !
!    A sample is frame ink if it is on a spine or a tick, and curve    !
!    ink (if not frame) if it is within half the curve's width of the  !
!    line through the points: the union of the segments, each with     !
!    round ends, so the joins are round too. This is neighborhood      !
!    averaging of a supersampled image (Russ and Neal, The Image       !
!    Processing Handbook, ch. 4): an edge that cuts a pixel gets the   !
!    shade of how much of the pixel it covers, so curves and rounded   !
!    corners are smooth instead of stair-stepped, and a line does not  !
!    jump from ink to white within one pixel. (A median filter, from   !
!    the same chapter, preserves edges instead: on a drawing that is   !
!    only ink or paper it keeps every edge hard, and a window wider    !
!    than about twice a line's width removes the line.) Straight       !
!    spines start on a pixel boundary, so their outer edge is crisp    !
!    and their inner edge takes the half pixel of the 2.5-pixel width. !
!                                                                      !
!    Colors are set here, pixel by pixel, so no colormap is used       !
!    (bmpmaker writes RGB as given when cmap names none of its         !
!    colormaps). RGB( i, j, 1:3 ) is BLUE, GREEN, RED, the order of a  !
!    bitmap file, as the colormap routines fill it.                    !
!                                                                      !
!  Record of revisions:                                                !
!      Date       Programmer          Description of change            !
!      ====       ==========          =====================            !
!    10/20/26    D. E. Kittell        Original code: the frame         !
!                (with Claude)                                         !
!    10/21/26    D. E. Kittell        The frame restyled: 2.5-pixel    !
!                (with Claude)        navy spines, rounded outside     !
!                                     corners, anti-aliased (4 x 4     !
!                                     samples per pixel, averaged)     !
!    10/21/26    D. E. Kittell        The curve: the tracer's velocity !
!                (with Claude)        against time, 3.0 pixels wide,   !
!                                     vermilion, anti-aliased the same !
!                                     way; the frame slate #2C3E50     !
!                                     (was navy #1F497D), the sheets'  !
!                                     ink                              !
!    10/21/26    D. E. Kittell        The title BITWHIZ SCOPE VIEW,    !
!                (with Claude)        engraved above the box (a stroke !
!                                     font of its 12 letters)          !
!    10/21/26    D. E. Kittell        The frame, stamp and the font    !
!                (with Claude)        moved to module strokes, shared  !
!                                     with draw_tx; the picture is the !
!                                     same, byte for byte              !
!    11/02/26    D. E. Kittell        The drawing moved to             !
!                (with Claude)        draw_profile (x range and title  !
!                                     as arguments), shared with the   !
!                                     movies; the picture is the same, !
!                                     byte for byte                    !
!                                                                      !
!**********************************************************************!
use bits, only: int32,dp
implicit none

!**********************************************************************!
! Data dictionary: Subroutine I/O.                                     !
!**********************************************************************!
character(len=80), intent(in) :: bout      ! file name, without ".bmp"
integer(kind=int32), intent(in) :: n       ! points
real(kind=dp), intent(in) :: t(n)          ! us, increasing
real(kind=dp), intent(in) :: u(n)          ! km/s
real(kind=dp), intent(in) :: ylo, yhi      ! km/s, the plot's y axis

interface
   subroutine draw_profile( bout, n, x, y, xlo, xhi, ylo, yhi, title_text )
      import :: dp, int32
      character(len=80), intent(in) :: bout
      integer(kind=int32), intent(in) :: n
      real(kind=dp), intent(in) :: x(n), y(n), xlo, xhi, ylo, yhi
      character(len=*), intent(in) :: title_text
   end subroutine draw_profile
end interface

!*** Time across, from the first point to the last.
call draw_profile( bout, n, t, u, t(1), t(n), ylo, yhi, &
   'BITWHIZ SCOPE VIEW' )

return

end subroutine draw_trace

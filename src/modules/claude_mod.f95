module claude
!**********************************************************************!
!
!  Purpose:
!    CLAUDE (Centers Lit by Accumulated Unrecoverable Dissipated
!    Energy), a burn model proposed by Claude (Anthropic) at D. E.
!    Kittell's invitation (deck: burn = claude, with eos =
!    mie_gruneisen_t and products = ideal_gas): burn centers lit by the
!    cell's entropy from a finite pool, growing at a deflagration speed,
!    overlapping exactly (Avrami's extended volume, by its moments), and
!    quenched at a rate.
!
!       s    = cl_entropy( e, ec, eta, cv, T0, G0 )   J/(g K): below 0
!                                                      under the isentrope
!       dn   = cl_dn( w1, w2, NMAX, W0, KW )           centers lit, as
!                                                      n(w2) - n(w1)
!                                                      without cancellation
!       call cl_moments( m1, vq1, dn, dr, dt, TQ, m2, vq2 )   one step
!       lam  = cl_lam( m3, vq )                        1 - exp(-4pi/3 V)
!       call cl_step( ... )                            all of it, in order
!
!    Elemental and pure; it holds no state. Module burn gives it the
!    cell's history (w, M_0 to M_3, V_q: bst(1:6)), its entropy now
!    (cl_s, from the state module temperature carries), its P^n and its
!    rho. CLAUDE is not gated by the lead shock.
!
!  The model (doc/design/burn_models.md, "CLAUDE" and "Step 9", approved
!  11/14/26):
!    w     the largest entropy the cell has had above its reference
!          isentrope, as if unreacted (THE ACTIVATION);
!    n(w)  = NMAX (1 - exp(-(w/W0)**KW)), centers lit per initial mm^3;
!    G     = D0 (max(P, 0)/PR)**NG (rho/R0)**(1/3), their radius' growth
!          in reference lengths (THE MOMENTS);
!    M_j   = the growing centers' sum of radius**j per initial mm^3;
!    V_q   = the volume burnt by centers since quenched (rate 1/TQ);
!    lam   = 1 - exp(-(4 pi/3)(M_3 + V_q)), Avrami's extended volume.
!
!  THE ACTIVATION: ENTROPY, A STATE FUNCTION
!  ========================================
!  For bitwhiz's Mie-Gruneisen (rho Gamma = R0 G0) with a constant C_V,
!  every isentrope has T proportional to exp(G0 eta), so the specific
!  entropy is exactly s - s_0 = C_V ln(T/(T0 exp(G0 eta))), with T the
!  cell's as if unreacted, T = T0 exp(G0 eta) + (e - e_c(eta))/C_V
!  (module temperature's formula, with its carried e_c). No sum: a
!  captured shock's state is right whatever its width, so w converges
!  with the mesh and is the same under either method (within 0.3 % of
!  the Hugoniot's entropy at 25 zones/mm, 0.1 % from 50, AV and RS). As if
!  unreacted: the reaction, at fixed e, does not move it, and a burning
!  cell's expansion lowers it, so the running maximum holds w; only
!  compression raises it (Cowperthwaite's isentropic-expansion idea, in
!  bitwhiz's density-temperature closure; DK, 11/14/26). The closed form
!  needs C_V constant and rho Gamma constant: module deck refuses burn =
!  claude with any other EOS (module burn_table, burn_needs_s). w in
!  J/(g K): C_V here is kJ/(g K), so 1000 C_V.
!
!  THE MOMENTS: EXACT STEPS
!  ========================
!  Over a step, G constant (P^n, rho), every growing radius gains DR = G
!  dt and survives the quench with probability f = exp(-dt/TQ); the dn
!  new centers are lit evenly through the step (exact for a constant
!  lighting rate). Then, with J_k = integral from 0 to dt of u**k
!  exp(-u/TQ) du,
!       M_j <- f sum_i C(j,i) DR**(j-i) M_i + (dn/dt) G**j J_j
!       V_q <- V_q + q sum_i C(3,i) G**(3-i) M_i J_(3-i)
!                  + (dn/dt) q G**3 (dt J_3 - J_4),       q = 1/TQ
!  the first the old centers' shift and survival, the second the new
!  ones' (born at u before the end, radius G u); V_q the volume of those
!  quenched within the step, each keeping what it had burnt. Where f
!  rounds to 1 (TQ = 1e30) the quench is skipped, V_q and all, and the
!  new centers add dn DR**j/(j + 1): the unquenched step, bit for bit.
!  J_k by its series in q dt below 2, by the recursion J_k = (k J_(k-1)
!  - dt**k e**(-q dt))/q above (to 1e-15 against 50 digits; the
!  recursion just above 1 lost a digit, hence 2). The old centers'
!  quenched share, q J_0 M_3, is formed as (1 - f) M_3, so that with no
!  growth M_3 + V_q is kept to round-off.
!
!***NOTE: D0 = 0 is the inert limit: G = 0, so every DR**j and G**j with
! j >= 1 is 0, M_3 and V_q stay 0, and lam = 0 exactly (centers are lit,
! M_0 counts them, nothing burns).
!
!***NOTE: the tests, not max(...)**: (max(P, 0)/PR)**NG is 1 at NG = 0
! whatever P, and 0 for P <= 0 otherwise. A cell whose inert T is not
! above 0 (none in practice: far tension) gets s = 0; one below its
! isentrope (e < e_c) a negative s: w, a running maximum from 0, never
! takes either.
!
!  Units, as everywhere in bitwhiz: w and W0 in J/(g K); NMAX in 1/mm^3;
!  radii in mm (reference); D0 and G in mm/us; P and PR in GPa; dt and TQ
!  in us; M_j in mm^(j-3); KW and NG dimensionless.
!
!  References:
!    doc/design/burn_models.md, "CLAUDE" (approved 11/06/26), and "Step
!    9, CLAUDE: the plan" (approved 11/14/26); doc/manual, chapter 8,
!    CLAUDE; checked against 50-digit values (tests/test_claude.f95,
!    tests/claude_reference.py).
!    J. Farjas and P. Roura, Acta Mater. 54, 5573 (2006): Avrami's
!    extended volume for any nucleation and growth history (the moments).
!    L. G. Hill, B. Zimmermann and A. L. Nichols III, AIP Conf. Proc.
!    1195, 432 (2009): every center lit at once, 1 - exp(-(pi/6) t^3).
!
!  Record of revisions:
!      Date       Programmer          Description of change
!      ====       ==========          =====================
!    11/14/26    D. E. Kittell        Original code
!                (with Claude)
!
!**********************************************************************!
use bits, only: dp, int32, zero, half, one
use thermalcascade, only: tc_om
implicit none
private

public :: cl_entropy, cl_dn, cl_moments, cl_lam, cl_growth, cl_jk, cl_step

real(kind=dp), parameter :: four_pi_3 = 4.18879020478639098461685784437_dp

contains

   !******************************************************************!
   ! The entropy above the reference isentrope, J/(g K), as if        !
   ! unreacted (THE ACTIVATION); 0 where the inert T is not above 0.  !
   !******************************************************************!
   elemental function cl_entropy( e, ec, eta, cv, T0, G0 ) result( s )
   implicit none
   real(kind=dp), intent(in) :: e        ! the cell's e, kJ/g
   real(kind=dp), intent(in) :: ec       ! its carried e_c at eta, kJ/g
   real(kind=dp), intent(in) :: eta      ! 1 - R0/rho, where e_c holds
   real(kind=dp), intent(in) :: cv       ! C_V, kJ/(g K)
   real(kind=dp), intent(in) :: T0, G0   ! K; Gruneisen at rest
   real(kind=dp) :: s, ts, t
   s  = zero
   ts = T0*exp( G0*eta )
   t  = ts + ( e - ec )/cv
   if ( t > zero ) s = 1000.0_dp*cv*log( t/ts )
   end function cl_entropy

   !******************************************************************!
   ! Centers lit as w rises from w1 to w2: n(w2) - n(w1) >= 0,        !
   ! n(w) = NMAX (1 - exp(-(w/W0)**KW)), formed without cancellation. !
   !******************************************************************!
   elemental function cl_dn( w1, w2, NMAX, W0, KW ) result( dn )
   implicit none
   real(kind=dp), intent(in) :: w1, w2, NMAX, W0, KW
   real(kind=dp) :: dn, x1, x2, dx
   dn = zero
   if ( .not. ( w2 > w1 .and. w2 > zero ) ) return
   x2 = ( w2/W0 )**KW
   if ( w1 > zero ) then                   ! x2 - x1 without cancellation:
      x1 = ( w1/W0 )**KW                   ! x2 (1 - (w1/w2)**KW), the
      dx = -x2*em1( -KW*lp1( ( w2 - w1 )/w1 ) )   ! power below 1: no
   else                                    ! overflow, whatever KW (the
      x1 = zero                            ! review, 11/14/26)
      dx = x2
   end if
   dn = NMAX*exp( -x1 )*tc_om( dx )
   end function cl_dn

   !*** ln(1 + r), accurate for small r (Goldberg's: u = 1 + r rounded).
   elemental function lp1( r ) result( y )
   implicit none
   real(kind=dp), intent(in) :: r
   real(kind=dp) :: y, u
   u = one + r
   if ( abs( u - one ) <= zero ) then
      y = r
   else
      y = log( u )*r/( u - one )
   end if
   end function lp1

   !*** exp(y) - 1, accurate for small y (Kahan's: u = exp(y) rounded).
   elemental function em1( y ) result( x )
   implicit none
   real(kind=dp), intent(in) :: y
   real(kind=dp) :: x, u
   u = exp( y )
   if ( abs( u - one ) <= zero ) then
      x = y
   else if ( abs( u - one ) < half ) then
      x = ( u - one )*y/log( u )
   else
      x = u - one
   end if
   end function em1

   !******************************************************************!
   ! The growth speed in reference lengths, mm/us (THE MOMENTS; the   !
   ! NOTE on NG).                                                     !
   !******************************************************************!
   elemental function cl_growth( P, rho, R0, D0, NG, PR ) result( g )
   implicit none
   real(kind=dp), intent(in) :: P, rho, R0, D0, NG, PR
   real(kind=dp) :: g, fp
   g = zero
   if ( .not. ( D0 > zero ) ) return
   if ( NG > zero ) then
      if ( .not. ( P > zero ) ) return
      fp = ( P/PR )**NG
   else
      fp = one
   end if
   g = D0*fp*( rho/R0 )**( one/3.0_dp )
   end function cl_growth

   !******************************************************************!
   ! J_k = integral from 0 to dt of u**k exp(-q u) du, k = 0 to 4.    !
   !******************************************************************!
   pure function cl_jk( dt, q ) result( jk )
   implicit none
   real(kind=dp), intent(in) :: dt, q
   real(kind=dp) :: jk(0:4), x, term, sm, ex
   integer(kind=int32) :: k, m
   x = q*dt
   if ( x < 2.0_dp ) then                  ! the series, alternating
      do k = 0, 4
         term = one                        ! (-x)**m/m!
         sm   = one/real( k + 1, dp )
         do m = 1, 40
            term = -term*x/real( m, dp )
            sm   = sm + term/real( k + m + 1, dp )
            if ( abs( term ) < 1.0e-18_dp ) exit
         end do
         jk(k) = dt**( k + 1 )*sm
      end do
   else                                    ! the recursion
      ex    = exp( -x )
      jk(0) = ( one - ex )/q
      do k = 1, 4
         jk(k) = ( real( k, dp )*jk(k-1) - dt**k*ex )/q
      end do
   end if
   end function cl_jk

   !******************************************************************!
   ! The moments and the quenched volume over one step (THE MOMENTS). !
   ! m1(0:3), vq1 at the start; dn lit through the step; dr = G dt.   !
   !******************************************************************!
   pure subroutine cl_moments( m1, vq1, dn, dr, dt, TQ, m2, vq2 )
   implicit none
   real(kind=dp), intent(in)  :: m1(0:3), vq1, dn, dr, dt, TQ
   real(kind=dp), intent(out) :: m2(0:3), vq2
   real(kind=dp) :: f, q, g, jk(0:4), sh(0:3)
   integer(kind=int32) :: j
   !*** The old centers' radii shifted by dr (binomial).
   sh(0) = m1(0)
   sh(1) = m1(1) + dr*m1(0)
   sh(2) = m1(2) + 2.0_dp*dr*m1(1) + dr*dr*m1(0)
   sh(3) = m1(3) + 3.0_dp*dr*m1(2) + 3.0_dp*dr*dr*m1(1) + dr**3*m1(0)
   q = one/TQ
   f = exp( -q*dt )
   vq2 = vq1
   if ( .not. ( f < one ) ) then           ! no quench (TQ = 1e30)
      m2(0) = sh(0) + dn
      do j = 1, 3
         m2(j) = sh(j) + dn*dr**j/real( j + 1, dp )
      end do
      return
   end if
   g  = dr/dt
   jk = cl_jk( dt, q )
   do j = 0, 3
      m2(j) = f*sh(j) + ( dn/dt )*g**j*jk(j)
   end do
   vq2 = vq1 + ( tc_om( q*dt )*m1(3) + q*3.0_dp*g*m1(2)*jk(1) &
      + q*3.0_dp*g*g*m1(1)*jk(2) + q*g**3*m1(0)*jk(3) ) &
      + ( dn/dt )*q*g**3*( dt*jk(3) - jk(4) )
   end subroutine cl_moments

   !******************************************************************!
   ! lam = 1 - exp(-(4 pi/3)(M_3 + V_q)).                             !
   !******************************************************************!
   elemental function cl_lam( m3, vq ) result( lam )
   implicit none
   real(kind=dp), intent(in) :: m3, vq
   real(kind=dp) :: lam
   lam = zero
   if ( m3 + vq > zero ) lam = tc_om( four_pi_3*( m3 + vq ) )
   end function cl_lam

   !******************************************************************!
   ! One step, in order: w (the running maximum of s), the centers    !
   ! lit, the moments and V_q, lam.                                   !
   !******************************************************************!
   pure subroutine cl_step( w1, m1, vq1, s, P, rho, dt, R0, NMAX, W0, KW, &
      D0, NG, PR, TQ, w2, m2, vq2, lam2 )
   implicit none
   real(kind=dp), intent(in)  :: w1, m1(0:3), vq1   ! history at the start
   real(kind=dp), intent(in)  :: s                  ! entropy now, J/(g K)
   real(kind=dp), intent(in)  :: P, rho, dt         ! P^n, rho, us
   real(kind=dp), intent(in)  :: R0, NMAX, W0, KW, D0, NG, PR, TQ
   real(kind=dp), intent(out) :: w2, m2(0:3), vq2, lam2
   real(kind=dp) :: dn
   w2 = max( w1, s )
   dn = cl_dn( w1, w2, NMAX, W0, KW )
   call cl_moments( m1, vq1, dn, cl_growth( P, rho, R0, D0, NG, PR )*dt, &
      dt, TQ, m2, vq2 )
   lam2 = cl_lam( m2(3), vq2 )
   end subroutine cl_step

end module claude

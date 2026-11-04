#!/usr/bin/env python3
"""Reference values for tests/test_hvrb.f95 (the "lam" and "mix" tables).

Independent of the Fortran AND of its formulas: everything here is built
from the definitions in doc/HVRB_Eqns_v8 (the frozen equation sheet), at
50 digits (mpmath), and the derivatives are taken numerically, not from the
closed forms in module hvrb.

- The topology: lam(phi) = 1 - (1 - phi^MR/XR)^XR, to phi_end = XR^(1/MR).
- The reactant: Mie-Grüneisen, P_sol(rho, e) = R0 G0 e + Pi(rho), with Pi
  built as tests/eos_reference.py and tests/temp_reference.py build it (the
  closed-form Us root and the Rayleigh line in compression; the cubic in
  x = rho - R0, its coefficients from the compression form's own numerical
  derivatives at x = 0, in tension). The isentrope from rest, e_S (the
  cold energy module temperature carries), is the integral itself, by
  mpmath's quadrature.
- The closure, density-temperature equilibrium with one C_V (the sheet's
  T-free form), with the solid's pressure dropped while it would pull in a
  cell that has started to burn (doc/design/materials.md, phase 3):
      vartheta = e - (1 - lam)(e_S - C_V T_S) + lam Q,  T_S = T0 exp(G0 eta)
      P = (1 - lam) P_sol(rho, e_S - C_V T_S + vartheta) + lam (gamma-1) rho vartheta
      (for lam > 0, P_sol replaced by max(P_sol, 0))
- c^2 = (dP/drho)_e + (P/rho^2)(dP/de)_rho at fixed lam, and dP/dlam at
  fixed rho and e, by mpmath's numerical differentiation of that P. At
  lam = 0, dP/dlam is the slope of the burn's first step (from the right,
  on the dropped branch if the solid pulls); at lam = 1, of the gas-only
  form (from the left), as the design note defines them.

The states are given by (eta, vartheta, lam), so that the solid's pressure
is chosen to be well away from 0 (no derivative across the clamp's kink);
e follows from vartheta. Needs Python 3 and mpmath (pip install mpmath).

    python3 tests/hvrb_reference.py > rows.txt

prints the Fortran rows to paste into test_hvrb.f95.
D. E. Kittell (with Claude), 11/04/26.
"""
import mpmath as mp
mp.mp.dps = 50

# Materials: Mie-Grüneisen (R0, C0, S1, S2, G0) and the burn's closure
# (C_V in kJ/(g K), T0 in K, gamma, Q in kJ/g). 1: Material X with the
# sheet's values (and the gold-standard runs' C_V); 2: aluminum's
# Mie-Grüneisen with made-up products, so that a second set of constants,
# and a material with S2 = 0 (a Hugoniot with a reach), are exercised.
mats = [((1.60, 2.50, 1.80, -0.10, 1.20), ('1.1633418e-3', 298, '2.60', '4.8828')),
        ((2.78, 5.30, 1.34,  0.00, 2.00), ('0.9e-3',       300, '3.0',  '2.0'))]

def us_of(eta, c0, s1, s2):
    return 2*c0/(1 - s1*eta + mp.sqrt((1 - s1*eta)**2 - 4*s2*eta**2))

def pi_c(x, r0, c0, s1, s2, g0):              # compression, as a function of x
    V = 1/(r0 + x); eta = 1 - r0*V; us = us_of(eta, c0, s1, s2); up = eta*us
    PH = r0*us*up if eta != 0 else mp.mpf(0)
    return PH - r0*g0*up**2/2

CUBIC = {}
def cubic(m):
    if m not in CUBIC:
        f = lambda x: pi_c(x, *m)
        CUBIC[m] = tuple(mp.diff(f, mp.mpf(0), n, direction=1) for n in (1, 2, 3))
    return CUBIC[m]

def Pi_eta(s, m):                              # Pi at eta = s
    r0 = m[0]; x = r0/(1 - s) - r0
    if s < 0:
        a1, a2, a3 = cubic(m)
        return a1*x + a2*x**2/2 + a3*x**3/6
    return pi_c(x, *m)

def e_S(eta, m):                               # the isentrope from rest
    g0 = m[4]
    return mp.quad(lambda s: mp.exp(g0*(eta - s))*Pi_eta(s, m)/m[0], [0, eta])

def pressure(rho, e, lam, m, b, clamp=False, gas_only=False):
    r0, g0 = m[0], m[4]; cv, t0, gam, q = b
    eta = (rho - r0)/rho
    ecs = e_S(eta, m) - cv*t0*mp.exp(g0*eta)   # the sheet's e_c
    th = e - (1 - lam)*ecs + lam*q
    psol = r0*g0*(ecs + th) + Pi_eta(eta, m)
    if ((lam > 0 or clamp) and psol < 0) or gas_only:
        psol = mp.mpf(0)
    return (1 - lam)*psol + lam*(gam - 1)*rho*th

def lam_of(phi, mr, xr):
    if phi >= xr**(1/mr):
        return mp.mpf(1)
    return 1 - (1 - phi**mr/xr)**xr

f = lambda x: mp.nstr(x, 20, min_fixed=-30, max_fixed=30, strip_zeros=False) + '_dp'

# The topology: (MR, XR, phi). The sheet's Material X set; the d^2 law's
# (MR = 1, XR = 1.5); MR and XR below 1 (legal: no delay, an abrupt
# finish); tiny phi (where 1 - (1 - x)^XR loses digits in floating point).
lams = []
for mr, xr in (('1.5', '2.5'), ('1', '1.5'), ('0.8', '0.7')):
    mr, xr = mp.mpf(mr), mp.mpf(xr)
    pend = xr**(1/mr)
    for frac in ('1e-9', '1e-4', '0.02', '0.3', '0.7', '0.99'):
        phi = mp.mpf(frac)*pend
        lams.append((mr, xr, phi, lam_of(phi, mr, xr)))
print(f"! {len(lams)} topology rows: MR, XR, phi, lam(phi)")
for mr, xr, phi, lam in lams:
    print(f"   lam_t( {mp.nstr(mr, 3)}_dp, {mp.nstr(xr, 3)}_dp, &\n      {f(phi)}, &\n"
          f"      {f(lam)} ), &")

# The closure: (material, eta, vartheta, lam).
rows = []
for im, (m, b) in enumerate(mats, start=1):
    m = tuple(mp.mpf(str(x)) for x in m)
    b = tuple(mp.mpf(str(x)) for x in b)
    for eta in ('-0.2', '-0.05', '0.1', '0.25'):
        eta = mp.mpf(eta)
        rho = m[0]/(1 - eta)
        es = e_S(eta, m)
        ecs = es - b[0]*b[1]*mp.exp(m[4]*eta)
        for th in ('0.3', '3.0'):
            th = mp.mpf(th)
            for lam in ('0', '0.3', '0.8', '1'):
                lam = mp.mpf(lam)
                e = th + (1 - lam)*ecs - lam*b[3]
                p = pressure(rho, e, lam, m, b)
                psol = m[0]*m[4]*(ecs + th) + Pi_eta(eta, m)
                dpdr = mp.diff(lambda r: pressure(r, e, lam, m, b), rho)
                dpde = mp.diff(lambda x: pressure(rho, x, lam, m, b), e)
                c = mp.sqrt(dpdr + p/rho**2*dpde)
                if lam == 0:      # from the right: the burn's first step
                    # (with the solid dropped if it pulls: P itself jumps
                    # there, from P_sol < 0 to >= 0, so this is the slope
                    # of the clamped branch the burning cell is on)
                    dpdl = mp.diff(lambda l: pressure(rho, e, l, m, b, True),
                                   mp.mpf(0), direction=1)
                elif lam == 1:    # burnt out: the solid is not evaluated
                    # (its weight is 0), so the slope is the gas-only
                    # form's, from the left; nothing multiplies it, as
                    # the burn is over (design note, phase 3)
                    dpdl = mp.diff(lambda l: pressure(rho, e, l, m, b,
                                   gas_only=True), lam, direction=-1)
                else:
                    dpdl = mp.diff(lambda l: pressure(rho, e, l, m, b), lam)
                clamp = psol < 0 and lam > 0
                rows.append((im, rho, e, lam, es, p, c, th, dpdl, clamp, psol))
print(f"! {len(rows)} closure rows: material, rho, e, lam, e_S; "
      "then P, c, vartheta, dP/dlam")
for im, rho, e, lam, es, p, c, th, dpdl, clamp, psol in rows:
    note = 'solid dropped' if clamp else ('P_sol = ' + mp.nstr(psol, 4) + ' GPa')
    print(f"   mix_t( {im}, {f(rho)}, &\n      {f(e)}, {mp.nstr(lam, 2)}_dp, &\n"
          f"      {f(es)}, &\n      {f(p)}, &\n      {f(c)}, &\n      {f(th)}, &\n"
          f"      {f(dpdl)} ), & ! {note}")

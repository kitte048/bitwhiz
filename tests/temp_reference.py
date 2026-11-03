#!/usr/bin/env python3
"""Reference values for tests/test_temp.f95 (the "ref" and "hug" tables).

Independent of the Fortran AND of its method: the cold energy here is the
integral itself,

    e_c(eta) = integral from 0 to eta of exp(G0 (eta - s)) Pi(s)/R0 ds,

by mpmath's own quadrature (tanh-sinh) at 50 digits, not the step-by-step
propagator and 3-point Gauss pieces of module temperature. Pi is built as
eos_reference.py builds P: in compression from the closed-form Us root and
the Rayleigh line, Pi = rho0 Us up - R0 G0 up^2/2; in tension from bitwhiz's
cubic in x = rho - rho0, with its coefficients taken from the compression
form's own numerical derivatives at x = 0, not from the formulas in eos_mod.
The temperature is the formula of doc/design/materials.md,

    T = T0 exp(G0 eta) + (e - e_c)/C_V,

with C_V and T0 as in the gold-standard runs (1.35e11 erg/(g eV) over
11604.5 K/eV = 1.1633418 J/(g K), T0 = 298 K), at e = e_H, the Hugoniot's
energy. Needs Python 3 and mpmath (pip install mpmath).

    python3 tests/temp_reference.py > rows.txt

prints the Fortran rows to paste into test_temp.f95. Material constants are
the input deck values (input/me697_double_shock_2p00.deck).
D. E. Kittell (with Claude), 11/03/26.
"""
import mpmath as mp
mp.mp.dps = 50
mats = [('Ta',16.65,3.40,1.20,0.0,1.60), ('Al',2.78,5.30,1.34,0.0,2.00),
        ('MatX',1.60,2.50,1.80,-0.10,1.20), ('PMMA',1.187,2.55,1.54,0.0,0.90)]
CV = mp.mpf('1.1633418')/1000          # kJ/(g K), as bitwhiz holds it
T0 = mp.mpf(298)
def us_of(eta, c0, s1, s2):
    return 2*c0/(1 - s1*eta + mp.sqrt((1 - s1*eta)**2 - 4*s2*eta**2))
def phi_c(x, r0, c0, s1, s2, g0):                # compression, as a function of x
    V = 1/(r0 + x); eta = 1 - r0*V; us = us_of(eta, c0, s1, s2); up = eta*us
    PH = r0*us*up if eta != 0 else mp.mpf(0)      # Rayleigh line: rho0*Us*up
    return PH - r0*g0*up**2/2
CUBIC = {}
def cubic(m):                                     # a1, a2, a3 = derivatives of phi_c at x = 0
    if m not in CUBIC:
        f = lambda x: phi_c(x, *m)
        CUBIC[m] = tuple(mp.diff(f, mp.mpf(0), n, direction=1) for n in (1, 2, 3))
    return CUBIC[m]
def Pi(s, m):
    r0 = m[0]; x = r0/(1 - s) - r0
    if s < 0:                                     # tension: the cubic
        a1, a2, a3 = cubic(m)
        return a1*x + a2*x**2/2 + a3*x**3/6
    return phi_c(x, *m)
def e_cold(eta, m):
    g0 = m[4]
    return mp.quad(lambda s: mp.exp(g0*(eta - s))*Pi(s, m)/m[0], [0, eta])
idx = {n: i+1 for i, (n, *_) in enumerate(mats)}
f = lambda x: mp.nstr(x, 20, min_fixed=-30, max_fixed=30, strip_zeros=False) + '_dp'
rows, hug = [], []
for name, *m in mats:
    m = tuple(mp.mpf(str(x)) for x in m)
    for eta in ('-0.2', '-0.05', '0.05', '0.1', '0.15', '0.25'):
        eta = mp.mpf(eta)
        rows.append((name, eta, e_cold(eta, m)))
    for eta in ('0.05', '0.15', '0.25'):
        eta = mp.mpf(eta)
        eH = (eta*us_of(eta, *m[1:4]))**2/2
        T = T0*mp.exp(m[4]*eta) + (eH - e_cold(eta, m))/CV
        hug.append((name, eta, eH, T))
print(f"! {len(rows)} cold energies: material, eta, e_c (kJ/g)")
for name, eta, ec in rows:
    print(f"   cold_t( {idx[name]}, {mp.nstr(eta, 3)}_dp, &\n      {f(ec)} ), & ! {name}")
print(f"! {len(hug)} Hugoniot states: material, eta, e_H (kJ/g), T (K)")
for name, eta, eH, T in hug:
    print(f"   hug_t( {idx[name]}, {mp.nstr(eta, 3)}_dp, &\n      {f(eH)}, &\n      {f(T)} ), & ! {name}")

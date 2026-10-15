#!/usr/bin/env python3
"""Reference values for tests/test_eos.f95 (the "ref" table).

Independent of the Fortran AND of the analytic derivatives in eos_mod:
  P  from the closed-form Us root and the Rayleigh line, rho0*Us*up,
  c  from its thermodynamic definition, c^2 = V^2 [P (dP/de)_V - (dP/dV)_e],
     with mpmath's own numerical derivatives,
all at 50 digits. Needs Python 3 and mpmath (pip install mpmath).

    python3 tests/eos_reference.py > rows.txt

prints the Fortran rows to paste into test_eos.f95. Material constants are
the input deck values (input/me697_double_shock_2p00.deck).
D. E. Kittell (with Claude), 10/14/26.
"""
import mpmath as mp
mp.mp.dps = 50
mats = [('Ta',16.65,3.40,1.20,0.0,1.60), ('Al',2.78,5.30,1.34,0.0,2.00),
        ('MatX',1.60,2.50,1.80,-0.10,1.20), ('PMMA',1.187,2.55,1.54,0.0,0.90)]
def us_of(eta, c0, s1, s2):
    return 2*c0/(1 - s1*eta + mp.sqrt((1 - s1*eta)**2 - 4*s2*eta**2))
def P_of(V, e, r0, c0, s1, s2, g0):
    eta = 1 - r0*V; us = us_of(eta, c0, s1, s2); up = eta*us
    PH = r0*us*up if eta != 0 else mp.mpf(0)      # Rayleigh line: rho0*Us*up
    eH = up**2/2
    return PH + r0*g0*(e - eH)
def c_of(V, e, m):
    dPdV = mp.diff(lambda x: P_of(x, e, *m), V)
    dPde = mp.diff(lambda x: P_of(V, x, *m), e)
    return mp.sqrt(V**2*(P_of(V, e, *m)*dPde - dPdV))
rows = []
for name, *m in mats:
    m = [mp.mpf(str(x)) for x in m]
    r0, c0, s1, s2, g0 = m
    for eta in ('0.05', '0.15', '0.25', '-0.05', '-0.2'):
        eta = mp.mpf(eta); V = (1 - eta)/r0; rho = 1/V
        eH = (eta*us_of(eta, c0, s1, s2))**2/2
        for e, tag in ((mp.mpf(0), 'cold'), (eH, 'on Hugoniot'), (eH + mp.mpf('0.3'), 'hot')):
            if eta < 0 and tag != 'cold': continue
            rows.append((name, rho, e, P_of(V, e, *m), c_of(V, e, m), f'eta = {mp.nstr(eta,3)}, {tag}'))
# the 1.5 km/s first shock: Al flyer into MatX at rest, both on their Hugoniots
al = [mp.mpf(str(x)) for x in mats[1][1:]]; mx = [mp.mpf(str(x)) for x in mats[2][1:]]
def PHug(up, r0, c0, s1, s2, g0): return r0*(c0 + s1*up + (s2/c0)*up**2)*up
upx = mp.findroot(lambda u: PHug(u, *mx) - PHug(mp.mpf('1.5') - u, *al), 1.0)
usx = mx[1] + mx[2]*upx + (mx[3]/mx[1])*upx**2
etax = upx/usx; Vx = (1 - etax)/mx[0]
rows.append(('MatX', 1/Vx, upx**2/2, P_of(Vx, upx**2/2, *mx), c_of(Vx, upx**2/2, mx),
             f'1.5 km/s first shock, up = {mp.nstr(upx,5)}, contract V2: 7.331 GPa'))
idx = {n:i+1 for i,(n,*_) in enumerate(mats)}
f = lambda x: mp.nstr(x, 20, min_fixed=-30, max_fixed=30, strip_zeros=False) + '_dp'
print(f"! {len(rows)} states: material, rho (g/cm^3), e ((km/s)^2), P (GPa), c (km/s)")
for name, rho, e, P, c, note in rows:
    print(f"   state_t( {idx[name]}, {f(rho)}, &\n      {f(e)}, &\n      {f(P)}, &\n      {f(c)} ), & ! {name}, {note}")

#!/usr/bin/env python3
"""Independent 50-digit EOS reference (from the sheet's definitions, derivatives
numerical) against bitwhiz's mg_eos, at random states for the four class
materials, in compression and in expansion. Usage: check_eos.py <driver>"""
import sys, random, subprocess
import mpmath as mp
mp.mp.dps = 50
random.seed(20261107)

mats = {'Ta':   (16.65, 3.41, 1.20, 0.0, 1.60),
        'Al':   (2.70, 5.35, 1.34, 0.0, 2.00),
        'MatX': (1.60, 2.50, 1.80, -0.10, 1.20),
        'PMMA': (1.186, 2.57, 1.54, 0.0, 1.00)}

def Us(eta, C0, S1, S2):
    return 2*C0/((1 - S1*eta) + mp.sqrt((1 - S1*eta)**2 - 4*S2*eta**2))

def PH_eH(V, R0, C0, S1, S2):
    eta = 1 - R0*V
    us = Us(eta, C0, S1, S2); up = eta*us
    return R0*eta*us**2, up**2/2

def cubic_coeffs(m):
    R0, C0, S1, S2, G0 = m
    # from the compression form's own derivatives at x = 0 (numerical), not the code's formulas
    def phi_x(x):
        V = 1/(R0 + x)
        PH, eH = PH_eH(V, R0, C0, S1, S2)
        return PH - R0*G0*eH
    return tuple(mp.diff(phi_x, mp.mpf(0), n, direction=1) for n in (1, 2, 3))

def P_and_c(rho, e, m):
    R0, C0, S1, S2, G0 = m
    V = 1/rho
    if rho >= R0:
        def P_of_V(VV, ee):
            PH, eH = PH_eH(VV, R0, C0, S1, S2)
            return PH + R0*G0*(ee - eH)
    else:
        a1, a2, a3 = cubic_coeffs(m)
        def P_of_V(VV, ee):
            x = 1/VV - R0
            return R0*G0*ee + a1*x + a2*x**2/2 + a3*x**3/6
    P = P_of_V(V, e)
    # c^2 = -V^2 (dP/dV)_S, de/dV = -P : total derivative along the isentrope
    dPdV_e = mp.diff(lambda VV: P_of_V(VV, e), V)
    dPde = mp.diff(lambda ee: P_of_V(V, ee), e)
    c2 = -V**2*(dPdV_e + dPde*(-P))
    return P, (mp.sqrt(c2) if c2 > 0 else mp.mpf('nan'))

states = []
for name, m in mats.items():
    R0, C0, S1, S2, G0 = m
    for _ in range(40):
        eta = random.uniform(-0.6, 0.35) if S2 >= 0 else random.uniform(-0.6, 0.6)
        if S2 == 0 and eta > 0.9/S1: eta = 0.9/S1
        rho = R0/(1 - eta)
        e = random.uniform(-0.2, 4.0)
        states.append((name, m, rho, e))

inp = '\n'.join(f'{rho!r} {e!r} {m[0]!r} {m[1]!r} {m[2]!r} {m[3]!r} {m[4]!r}' for _, m, rho, e in states) + '\n'
out = subprocess.run([sys.argv[1]], input=inp, capture_output=True, text=True).stdout.strip().split('\n')
worst = {}
nbad = 0
for (name, m, rho, e), line in zip(states, out):
    toks = line.split()
    mm = tuple(mp.mpf(repr(v)) for v in m)
    P, c = P_and_c(mp.mpf(repr(rho)), mp.mpf(repr(e)), mm)
    if toks[0] == 'nan':
        print(f'  {name}: Fortran ierr={toks[2]} at rho={rho:.4f} e={e:.4f}; ref P={mp.nstr(P,8)} c={mp.nstr(c,8)}')
        nbad += 1
        continue
    pf, cf = mp.mpf(toks[0]), mp.mpf(toks[1])
    scale = max(abs(P), mm[0]*mm[1]**2)           # pressure scale: bulk modulus
    ep = abs(pf - P)/scale
    ec = abs(cf - c)/abs(c) if not mp.isnan(c) else mp.mpf(0)
    w = worst.setdefault(name, [0, 0])
    w[0] = max(w[0], ep); w[1] = max(w[1], ec)
for name, (ep, ec) in worst.items():
    print(f'{name:5s}: worst |dP|/K0 = {mp.nstr(ep, 3)}, worst |dc|/c = {mp.nstr(ec, 3)}')
print('states with Fortran error status:', nbad)

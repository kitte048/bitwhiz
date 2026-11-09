#!/usr/bin/env python3
"""Independent 50-digit check of the mixture closure (mix_state) against the
sheet's definitions, with c^2 and dP/dlam by numerical differentiation of
the pressure actually used (solid in / dropped / held). Usage: <driver>"""
import sys, random, subprocess
import mpmath as mp
mp.mp.dps = 40
random.seed(7)

MATX = (1.60, 2.50, 1.80, -0.10, 1.20)
AL   = (2.78, 5.30, 1.34, 0.00, 2.00)
BX   = (1.1633418e-3, 298.0, 2.60, 4.8828)
BA   = (0.9e-3, 300.0, 3.0, 2.0)

def Us(eta, C0, S1, S2):
    return 2*C0/((1 - S1*eta) + mp.sqrt((1 - S1*eta)**2 - 4*S2*eta**2))

def phi_comp_x(x, m):
    R0, C0, S1, S2, G0 = m
    V = 1/(R0 + x); eta = 1 - R0*V
    us = Us(eta, C0, S1, S2); up = eta*us
    return R0*eta*us**2 - R0*G0*up**2/2

_cub = {}
def cubic(m):
    if m not in _cub:
        _cub[m] = tuple(mp.diff(lambda x: phi_comp_x(x, m), mp.mpf(0), n, direction=1) for n in (1, 2, 3))
    return _cub[m]

def Pi(rho, m):
    R0 = m[0]; x = rho - R0
    if rho < R0:
        a1, a2, a3 = cubic(m)
        return a1*x + a2*x**2/2 + a3*x**3/6
    return phi_comp_x(x, m)

def eS(rho, m):   # isentrope from rest: de/drho = (R0 G0 e + Pi)/rho^2, e(R0) = 0 -> exact propagator
    R0, G0 = m[0], m[4]
    eta = 1 - R0/rho
    return mp.quad(lambda s: mp.exp(G0*(eta - s))*Pi(R0/(1 - s), m)/R0, [0, eta])

def closure(rho, e, lam, m, b, rhold=None, eshold=None):
    R0, C0, S1, S2, G0 = m; cv, T0, gam, Q = b
    held = rhold is not None and lam > 0 and rho < rhold
    rs = rhold if held else rho
    eta_s = 1 - R0/rs
    es_s = eshold if held else eS(rs, m)
    ecs = es_s - cv*T0*mp.exp(G0*eta_s)
    th = e - (1 - lam)*ecs + lam*Q
    pg = (gam - 1)*rho*th if th > 0 else mp.mpf(0)
    if lam == 0:
        return R0*G0*e + Pi(rho, m), th
    if lam == 1:
        return pg, th
    psol = R0*G0*(ecs + th) + Pi(rs, m)
    if psol < 0:
        return lam*pg, th
    return (1 - lam)*psol + lam*pg, th

def ref(rho, e, lam, m, b, rhold=None, eshold=None):
    P, th = closure(rho, e, lam, m, b, rhold, eshold)
    dPdr = mp.diff(lambda r: closure(r, e, lam, m, b, rhold, eshold)[0], rho)
    dPde = mp.diff(lambda x: closure(rho, x, lam, m, b, rhold, eshold)[0], e)
    c2 = dPdr + P/rho**2*dPde
    if lam == 0:
        dPdl = mp.diff(lambda l: closure(rho, e, l, m, b, rhold, eshold)[0], mp.mpf(0), direction=1)
    elif lam == 1:
        dPdl = mp.diff(lambda l: closure(rho, e, l, m, b, rhold, eshold)[0], mp.mpf(1), direction=-1)
    else:
        dPdl = mp.diff(lambda l: closure(rho, e, l, m, b, rhold, eshold)[0], lam)
    return P, c2, th, dPdl

cases = []
for m, b in ((MATX, BX), (AL, BA)):
    mm = tuple(mp.mpf(repr(v)) for v in m); bb = tuple(mp.mpf(repr(v)) for v in b)
    for _ in range(60):
        eta = mp.mpf(random.uniform(-0.3, 0.3))
        rho = mm[0]/(1 - eta)
        lam = mp.mpf(random.choice([0, 1, random.uniform(0.001, 0.999), random.uniform(0.001, 0.999)]))
        th = mp.mpf(random.uniform(0.05, 4.0))
        es = eS(rho, mm)
        ecs = es - bb[0]*bb[1]*mp.exp(mm[4]*eta)
        e = th + (1 - lam)*ecs - lam*bb[3]
        hold = None
        if 0 < lam < 1 and random.random() < 0.4:
            rhold = rho*mp.mpf(random.uniform(1.02, 1.3))      # held at a higher density
            hold = (rhold, eS(rhold, mm))
        cases.append((mm, bb, rho, e, lam, es, hold))

lines = []
for mm, bb, rho, e, lam, es, hold in cases:
    rh, eh = hold if hold else (mp.mpf(0), mp.mpf(0))
    vals = [rho, e, lam, es] + list(mm) + list(bb) + [rh, eh]
    lines.append(' '.join(repr(float(v)) for v in vals))
out = subprocess.run([sys.argv[1]], input='\n'.join(lines) + '\n', capture_output=True, text=True).stdout.strip().split('\n')

worst = [0, 0, 0, 0]; nguard = 0; nerr = 0; n = 0
for (mm, bb, rho, e, lam, es, hold), line in zip(cases, out):
    toks = line.split()
    # evaluate the reference at the double-precision inputs the Fortran saw
    rho_d, e_d, lam_d, es_d = (mp.mpf(repr(float(v))) for v in (rho, e, lam, es))
    hold_d = (mp.mpf(repr(float(hold[0]))), mp.mpf(repr(float(hold[1])))) if hold else None
    # the Fortran uses es (the given e_S at rho), so make the reference use it too:
    def closure_es(r, x, l):
        R0, C0, S1, S2, G0 = mm; cv, T0, gam, Q = bb
        held = hold_d is not None and l > 0 and r < hold_d[0]
        rs = hold_d[0] if held else r
        eta_s = 1 - R0/rs
        # e_S at rs: the given value at rho_d, moved along the isentrope to r (needed for d/drho)
        es_s = hold_d[1] if held else es_d*mp.exp(G0*((1 - R0/r) - (1 - R0/rho_d))) + \
            mp.quad(lambda s: mp.exp(G0*((1 - R0/r) - s))*Pi(R0/(1 - s), mm)/R0, [1 - R0/rho_d, 1 - R0/r])
        ecs = es_s - cv*T0*mp.exp(G0*eta_s)
        th = x - (1 - l)*ecs + l*Q
        pg = (gam - 1)*r*th if th > 0 else mp.mpf(0)
        if l == 0: return R0*G0*x + Pi(r, mm), th
        if l == 1: return pg, th
        psol = R0*G0*(ecs + th) + Pi(rs, mm)
        if psol < 0: return l*pg, th
        return (1 - l)*psol + l*pg, th
    P, th = closure_es(rho_d, e_d, lam_d)
    dPdr = mp.diff(lambda r: closure_es(r, e_d, lam_d)[0], rho_d)
    dPde = mp.diff(lambda x: closure_es(rho_d, x, lam_d)[0], e_d)
    c2 = dPdr + P/rho_d**2*dPde
    if lam_d == 0:
        dPdl = mp.diff(lambda l: closure_es(rho_d, e_d, l)[0], mp.mpf(0), direction=1)
    elif lam_d == 1:
        dPdl = mp.diff(lambda l: closure_es(rho_d, e_d, l)[0], mp.mpf(1), direction=-1)
    else:
        dPdl = mp.diff(lambda l: closure_es(rho_d, e_d, l)[0], lam_d)
    if toks[0] == 'nan':
        nerr += 1; continue
    pf, cf, thf, dlf, ifb = mp.mpf(toks[0]), mp.mpf(toks[1]), mp.mpf(toks[2]), mp.mpf(toks[3]), int(toks[4])
    if ifb != 0:
        nguard += 1; continue          # guard branches are not the exact derivative
    n += 1
    K = mm[0]*mm[1]**2
    worst[0] = max(worst[0], abs(pf - P)/K)
    worst[1] = max(worst[1], abs(cf**2 - c2)/abs(c2))
    worst[2] = max(worst[2], abs(thf - th)/max(abs(th), 1))
    err = abs(dlf - dPdl)/max(abs(dPdl), K)
    if not (0 < lam_d < 1): err = mp.mpf(0)   # endpoint conventions differ by design (see report)
    if err > 1e-10:
        R0, C0, S1, S2, G0 = mm; cv, T0, gam, Q = bb
        held = hold_d is not None and lam_d > 0 and rho_d < hold_d[0]
        print(f'  MISMATCH lam={float(lam_d):.4f} eta={float(1-R0/rho_d):+.3f} held={held} th={float(th):.3f} P={float(P):.4f} fortran dPdl={float(dlf):.6f} ref={float(dPdl):.6f}')
    worst[3] = max(worst[3], err)
print(f'{n} states compared (exact-rule branch), {nguard} by a guard (skipped), {nerr} EOS errors')
print('worst |dP|/K0        =', mp.nstr(worst[0], 3))
print('worst |dc^2|/c^2     =', mp.nstr(worst[1], 3))
print('worst |dtheta|       =', mp.nstr(worst[2], 3))
print('worst |d dP/dlam|/.. =', mp.nstr(worst[3], 3))

#!/usr/bin/env python3
"""Independent checks of hvrb_lambda, hvrb_rate, tc_rate, tc_om, tc_step at 50
digits, including the series/direct switch points and large exponents."""
import sys, subprocess, random
import mpmath as mp
mp.mp.dps = 50
random.seed(3)

def lam_ref(phi, MR, XR):
    pend = XR**(1/MR)
    if phi <= 0: return mp.mpf(0)
    if phi >= pend: return mp.mpf(1)
    return 1 - (1 - phi**MR/XR)**XR

def rate_ref(p, PR, ZR, PI, TAU0):
    if not p > PI: return mp.mpf(0)
    return ((p - PI)/PR)**ZR/TAU0 if ZR > 0 else 1/TAU0

def tc_ref(T, Ps, HT, TC, GT, NS, PR):
    if not T > TC: return mp.mpf(0)
    f = (1 + max(Ps, 0)/PR)**NS
    return HT*f if GT == 0 else HT*(T - TC)**GT*f

lines, refs, tags = [], [], []
# hvrb_lambda: sweep XR including large, phi so that x = phi^MR/XR spans the switch at 0.05
for MR in (0.8, 1.0, 1.5, 3.0):
    for XR in (0.7, 1.0, 1.5, 2.5, 5.0, 10.0, 20.0, 40.0, 80.0):
        for x in (1e-12, 1e-8, 1e-4, 0.01, 0.04999, 0.05001, 0.2, 0.6, 0.999):
            phi = (mp.mpf(x)*XR)**(1/mp.mpf(MR))
            lines.append(f'H {float(phi)!r} {MR!r} {XR!r}')
            refs.append(lam_ref(mp.mpf(repr(float(phi))), mp.mpf(repr(MR)), mp.mpf(repr(XR))))
            tags.append(f'lam MR={MR} XR={XR} x={x}')
# hvrb_rate
for _ in range(40):
    p = random.uniform(-2, 40); PR = random.uniform(1, 10); ZR = random.choice([0, 0.5, 1, 2, 3])
    PI = random.uniform(0, 2); TAU0 = random.uniform(0.1, 3)
    lines.append(f'R {p!r} {PR!r} {ZR!r} {PI!r} {TAU0!r}')
    refs.append(rate_ref(*[mp.mpf(repr(v)) for v in (p, PR, ZR, PI, TAU0)])); tags.append('rate')
# tc_rate
for _ in range(40):
    T = random.uniform(200, 3000); Ps = random.uniform(-5, 40); HT = random.uniform(0, 1e-3)
    TC = random.uniform(300, 1500); GT = random.choice([0, 0.5, 1, 1.5, 2]); NS = random.choice([0, 1, 2]); PR = random.uniform(1, 10)
    lines.append(f'T {T!r} {Ps!r} {HT!r} {TC!r} {GT!r} {NS!r} {PR!r}')
    refs.append(tc_ref(*[mp.mpf(repr(v)) for v in (T, Ps, HT, TC, GT, NS, PR)])); tags.append('tc_rate')
# tc_om across the switch and extremes
for x in (0, 1e-300, 1e-17, 1e-8, 0.001, 0.1, 0.4999, 0.5, 0.5001, 1, 5, 50, 700, 1e6):
    lines.append(f'O {float(x)!r}')
    refs.append(1 - mp.exp(-mp.mpf(repr(float(x))))); tags.append(f'om x={x}')
# tc_step
for _ in range(30):
    lam1 = random.choice([0, 1e-10, 0.3, 0.999, 1 - 1e-15]); r = random.uniform(0, 50); dt = random.uniform(1e-5, 0.01)
    lines.append(f'S {lam1!r} {r!r} {dt!r}')
    l1, rr, dd = (mp.mpf(repr(v)) for v in (lam1, r, dt))
    refs.append(l1 + (1 - l1)*(1 - mp.exp(-rr*dd))); tags.append('tc_step')

out = subprocess.run([sys.argv[1]], input='\n'.join(lines) + '\n', capture_output=True, text=True).stdout.strip().split('\n')
worst = {}
for tag, ref, line in zip(tags, refs, out):
    t = line.strip()
    import re as _re
    t = _re.sub(r'(\d)([+-]\d{3})$', r'\1e\2', t)     # Fortran drops 'E' for 3-digit exponents
    f = mp.mpf(t)
    err = abs(f - ref)/abs(ref) if ref != 0 else abs(f)
    key = tag.split()[0]
    if err > 1e-13:
        print(f'  {tag}: fortran={mp.nstr(f, 17)} ref={mp.nstr(ref, 17)} rel.err={mp.nstr(err, 3)}')
    worst[key] = max(worst.get(key, 0), err)
for k, v in worst.items():
    print(f'{k:8s} worst relative error {mp.nstr(v, 3)}')

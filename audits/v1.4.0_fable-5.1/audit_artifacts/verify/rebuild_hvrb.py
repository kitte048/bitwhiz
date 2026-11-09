#!/usr/bin/env python3
"""The HVRB sheet's check: rebuild lam(t) from a tracer's P(t) history with the
two HVRB boxes (phi^{n+1} = phi^n + Phi(P^n) dt^n, lam = topology(phi)), and
compare with the run's XRN column. Rows must be every cycle (tracer_dt = 0).
Usage: rebuild_hvrb.py <tracers.csv> PR ZR MR XR PI TAU0 tracer1 tracer2 ..."""
import sys, math
import numpy as np

fn = sys.argv[1]
PR, ZR, MR, XR, PI, TAU0 = map(float, sys.argv[2:8])
names = sys.argv[8:]
with open(fn) as f:
    header = f.readline().strip().split(', ')
    f.readline()
    rows = []
    for line in f:
        if line.startswith('#'): break
        rows.append([float(x) for x in line.split(',')])
data = np.array(rows)
col = {h: i for i, h in enumerate(header)}
t = data[:, col['TIME']]; dt = data[:, col['DTIME']]
pend = XR**(1.0/MR)
def lam_of(phi):
    if phi <= 0: return 0.0
    if phi >= pend: return 1.0
    x = phi**MR/XR
    return -math.expm1(XR*math.log1p(-x))      # 1 - (1-x)^XR, accurately
def rate(p):
    if not p > PI: return 0.0
    return ((p - PI)/PR)**ZR/TAU0 if ZR > 0 else 1.0/TAU0
for nm in names:
    P = data[:, col['GPA.' + nm]]; X = data[:, col['XRN.' + nm]]
    phi = 0.0; worst = 0.0; nburn = 0; first = None
    lam_rb = np.zeros_like(X)
    for n in range(len(t) - 1):
        phi = min(phi + rate(P[n])*dt[n + 1], pend)
        lam_rb[n + 1] = lam_of(phi)
        if X[n + 1] > 0 and first is None: first = n + 1
        worst = max(worst, abs(lam_rb[n + 1] - X[n + 1]))
    print(f'{nm:8s}: rows {len(t)}, first lam>0 at row {first}, final XRN {X[-1]:.6f} rebuilt {lam_rb[-1]:.6f}, '
          f'max |rebuilt - XRN| = {worst:.3e}')

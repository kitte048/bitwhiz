#!/usr/bin/env python3
"""Independent in-situ check of ThermalCascade: an independent Python lead-shock
detector (written from doc/design/burn_models.md, "As built: step 4", and the
lshk_mod header) replayed on a tracer's rows written every cycle gives the
mark row and P_s; then lam is rebuilt from the run's own T^n (TK) and dt with
the exact first-order step, gated at the mark, and compared with XRN.
Usage: rebuild_tcas.py <tracers.csv> R0 C0 HT TC GT NS PR tracer..."""
import sys, math
import numpy as np

fn = sys.argv[1]
R0, C0, HT, TC, GT, NS, PR = map(float, sys.argv[2:9])
names = sys.argv[9:]
FLOOR, KNEE = 1e-10, 0.01

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

def detector(rho, e, P):
    """Returns (mark_row, Ps, ts). Row n holds the state after step n; the
    detector is stepped once per row from row 1 on (cycle 0 is the start)."""
    hlast = 0.0; hmax = 0.0; flag = 0; fall = 0.0
    for n in range(1, len(rho)):
        h = e[n] - 0.5*(1.0/R0 - 1.0/rho[n])*P[n]
        hl = hlast; hlast = h
        if flag == 0:
            if rho[n] > R0 and h > FLOOR*C0*C0:
                hmax = h; fall = 0.0; flag = 1
            continue
        if h > hmax:
            hmax = h; fall = 0.0; flag = 1; continue
        if flag == 1 and h < hl:
            flag = 2; fall = hl - h
            if not h > 0:
                return n, P[n], t[n] - dt[n]*h/(h - hl)
            continue
        if flag == 2:
            if not h > 0:
                return n, P[n], t[n] - dt[n]*h/(h - hl)
            if h > hl:
                return n, P[n], t[n] - dt[n]
            d = hl - h
            if d < KNEE*fall:
                return n, P[n], t[n]
            fall = max(fall, d)
    return None, 0.0, 0.0

def rate(T, Ps):
    if not T > TC: return 0.0
    f = (1.0 + max(Ps, 0.0)/PR)**NS
    return HT*f if GT == 0 else HT*(T - TC)**GT*f

for nm in names:
    rho = data[:, col['RHO.' + nm]]; e = data[:, col['SIE.' + nm]]; P = data[:, col['GPA.' + nm]]
    TK = data[:, col['TK.' + nm]]; X = data[:, col['XRN.' + nm]]
    m, Ps, ts = detector(rho, e, P)
    first = next((i for i in range(len(X)) if X[i] > 0), None)
    lam = 0.0; worst = 0.0; lam_rb = np.zeros_like(X)
    if m is not None:
        for n in range(m, len(t) - 1):          # marked at the end of cycle m: burns from step m -> m+1
            r = rate(TK[n], Ps)
            lam = lam + (1.0 - lam)*(-math.expm1(-r*dt[n + 1]))
            lam_rb[n + 1] = lam
    worst = np.max(np.abs(lam_rb - X))
    print(f'{nm:8s}: mark row {m} (P_s {Ps:.5f} GPa, t_s {ts:.5f} us); first XRN>0 at row {first}; '
          f'final XRN {X[-1]:.6f} rebuilt {lam_rb[-1]:.6f}; max |rebuilt - XRN| = {worst:.3e}')

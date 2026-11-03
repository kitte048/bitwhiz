#!/usr/bin/env python3
"""gold.py -- read the reference tracer files in tests/verification/ and
compute the quantities bitwhiz is compared on (Python 3 and NumPy).

One reader for every file here: the five ME697_<v>_kmps.dat (5 tracers,
x, u, P) and the gold-standard sets, inert_gauges/G1_* and hvrb/G2_* to G5_*
(13 to 41 tracers, adding density, temperature and reaction progress), and
bitwhiz's own tracer files, <title>.tracers.csv, so that both codes are
measured by the same lines of code. They share one format: line 1 the
column names, line 2 their units, then one row per output time; globals
first, then NAME.n for tracer n (a number in the reference files, the
deck's tracer name in bitwhiz's).

Units, converted on reading to the course's. The reference files mix the
code's own (TIME and DTIME in s, XPOS in cm); bitwhiz writes the course's
already (input/README.md, section 8). Line 2 says which:
   t           us        x0, XPOS    mm
   KMPS        km/s      GPA     GPa       DENS    g/cm^3 (bitwhiz: RHO)
   TK          K         XRN3    lambda    MJKG    MJ/kg (written, never filled)
   bitwhiz's   SIE kJ/g, Q GPa, CS km/s, DMG (0 intact, 1 broken)
   globals     as written: MTOT g, ETOT/EK/EINT erg, VTOT cm^3, XMOM g cm/s
               in the reference; per cm^2 and mm in bitwhiz (GPa mm)

    import gold
    r = gold.read('tests/verification/inert_gauges/G1_inert_2p00_kmps.dat')
    r.t                           # output times, us
    r.x0[6]                       # tracer 6's initial position, mm (= 4.0)
    r['GPA', 6]                   # its pressure history, GPa
    gold.arrival(r, 6)            # first u > 0.05 km/s, interpolated, us
    gold.shock_fit(r, 1, 9)       # (U_S, intercept) from arrivals 1-9 mm
    gold.run_distance(r, 10.0)    # mm, or None if no transition in 10 mm
    gold.trust_end(r)             # us: last time MTOT is still constant
    gold.impedance_match(2.00)    # exact (u1, P1, U_S): Al onto Material X
    gold.temperature('PMMA', rho, e)        # K, the model of eos =
    gold.hugoniot_temperature('MatX', rho)  # mie_gruneisen_t; on the Hugoniot

    python3 tests/verification/gold.py

reads every file present and reproduces the derived results the dataset's
README publishes (G1-G5 tables, section 4), so the reader is checked against
numbers computed independently of it. The definitions are that README's,
unchanged, so bitwhiz and the reference are measured the same way:

   arrival       first u > 0.05 km/s at a tracer, linearly interpolated
                 between output rows; G4 (positions only): first motion,
                 |x - x0| > 0.1 um
   run distance  the midpoint of the first tracer interval (in x0 order)
                 whose mean shock speed, dx0/dt_arrival, exceeds
                 0.9 D_CJ = 6.75 km/s
   trust window  until total mass first changes (material leaving the mesh)

and one the README uses without defining, settled here:

   first shock   at a tracer, the median over 50-200 ns after its arrival
                 (the plateau scatters by about 0.001 GPa row to row)

A tracer already moving at t = 0 (in the flyer) arrives at t = 0.

D. E. Kittell (with Claude), 11/02/26.
"""
import os, sys, glob
import numpy as np

D_CJ = 7.4999904                   # km/s, exact for Material X's HVRB model
U_ARRIVE = 0.05                    # km/s, the arrival threshold
X_ARRIVE = 1.0e-4                  # mm (0.1 um), first motion for G4
GLOBALS = ('TIME', 'CYCLE', 'DTIME', 'MTOT', 'ETOT', 'EK', 'EINT', 'VTOT',
           'XMOM')
ALIAS = {'RHO': 'DENS'}            # bitwhiz's name -> the reference's

def _scale(var, unit):
    # The factor to the course's units, from the file's own unit label.
    if var in ('TIME', 'DTIME'):
        return 1.0e6 if unit.startswith('Time (s)') or unit.startswith(
            'Dt (s)') else 1.0
    if var == 'XPOS':
        return 10.0 if '(cm)' in unit else 1.0
    return 1.0

class Run:
    """One file: r.t (us), r.x0 {n: mm}, r.g {name: column}, r[var, n]."""
    def __init__(self, path):
        self.path = path
        self.name = os.path.basename(path)
        with open(path) as fh:
            names = [s.strip() for s in fh.readline().split(',')]
            self.units = [s.strip() for s in fh.readline().split(',')]
        a = np.loadtxt(path, delimiter=',', skiprows=2, ndmin=2)
        if a.shape[1] != len(names):
            raise ValueError(f'{path}: {len(names)} names, '
                             f'{a.shape[1]} columns')
        k = names.index('TIME')
        self.t = a[:, k] * _scale('TIME', self.units[k])     # -> us
        self.g = {n: a[:, j] for j, n in enumerate(names) if n in GLOBALS}
        self.cols = {}
        for j, n in enumerate(names):
            if '.' not in n:
                continue
            var, tr = n.split('.', 1)
            var = ALIAS.get(var, var)
            tr = int(tr) if tr.isdigit() else tr
            self.cols[var, tr] = a[:, j] * _scale(var, self.units[j])
        self.tracers = sorted({tr for _, tr in self.cols},
                              key=lambda k: (str(type(k)), k))
        self.vars = sorted({v for v, _ in self.cols})
        self.x0 = {tr: self.cols['XPOS', tr][0] for tr in self.tracers}

    def __getitem__(self, key):
        return self.cols[key]

    def has(self, var):
        return var in self.vars

def read(path):
    return Run(path)

#*** Derived quantities: the dataset README's definitions (section 4).

def _first_crossing(t, y, level):
    # The time y first exceeds level, linear between the two rows that
    # bracket it; None if it never does.
    i = np.flatnonzero(y > level)
    if len(i) == 0:
        return None
    i = i[0]
    if i == 0:
        return t[0]
    return t[i-1] + (level - y[i-1]) * (t[i] - t[i-1]) / (y[i] - y[i-1])

def arrival(r, n, level=None):
    """Arrival time (us) of the first wave at tracer n, or None."""
    if r.has('KMPS'):
        return _first_crossing(r.t, r['KMPS', n], U_ARRIVE if level is None
                               else level)
    moved = np.abs(r['XPOS', n] - r.x0[n])            # G4: positions only
    return _first_crossing(r.t, moved, X_ARRIVE if level is None else level)

def arrivals(r, x_lo=-np.inf, x_hi=np.inf):
    """[(x0, t_arrival)] for tracers with x_lo <= x0 <= x_hi, in x0 order;
    tracers the wave never reaches are left out."""
    out = []
    for n in sorted(r.tracers, key=lambda k: r.x0[k]):
        if x_lo <= r.x0[n] <= x_hi:
            ta = arrival(r, n)
            if ta is not None:
                out.append((r.x0[n], ta))
    return out

def shock_fit(r, x_lo, x_hi):
    """Least-squares straight line x0 = U_S * t + b through the arrivals
    between x_lo and x_hi (mm): (U_S in km/s, b in mm)."""
    xa = np.array(arrivals(r, x_lo, x_hi))
    if len(xa) < 2:
        return None
    us, b = np.polyfit(xa[:, 1], xa[:, 0], 1)
    return us, b

def run_distance(r, x_end, x_start=0.0, frac=0.9):
    """Run to detonation (mm): the midpoint of the first interval between
    neighboring tracers (x_start <= x0 <= x_end) whose mean shock speed
    exceeds frac*D_CJ. None if no interval does."""
    xa = arrivals(r, x_start, x_end)
    for (x1, t1), (x2, t2) in zip(xa, xa[1:]):
        if t2 > t1 and (x2 - x1) / (t2 - t1) > frac * D_CJ:
            return 0.5 * (x1 + x2)
    return None

def first_shock(r, n, var='GPA'):
    """The first-shock state at tracer n: the median of var over 50-200 ns
    after the arrival (the plateau before any second wave; it scatters by
    about 0.001 GPa from row to row, so the median, not one row)."""
    ta = arrival(r, n)
    m = (r.t > ta + 0.05) & (r.t < ta + 0.20)
    return float(np.median(r[var, n][m]))

#*** The exact first shock: an impedance match on the principal Hugoniots.

# Project rev-0 Table 1, as in input/me697_double_shock_2p00.deck:
# rho0 (g/cm^3), C0 (km/s), S1, S2, with U_S = C0 + S1 up + (S2/C0) up^2.
MATERIALS = {'Ta':   (16.65, 3.40, 1.20,  0.00),
             'Al':   (2.78,  5.30, 1.34,  0.00),
             'MatX': (1.60,  2.50, 1.80, -0.10),
             'PMMA': (1.187, 2.55, 1.54,  0.00)}

def hugoniot(mat, up):
    """(P in GPa, U_S in km/s) on mat's principal Hugoniot at up (km/s)."""
    r0, c0, s1, s2 = MATERIALS[mat]
    us = c0 + s1 * up + (s2 / c0) * up * up
    return r0 * us * up, us

def impedance_match(u_fly, flyer='Al', target='MatX'):
    """A flyer at u_fly strikes the target at rest: the state behind the
    two shocks, (u1, P1, U_S in the target). Bisection on
    P_target(u) = P_flyer(u_fly - u), to round-off."""
    lo, hi = 0.0, u_fly
    for _ in range(200):
        u = 0.5 * (lo + hi)
        if hugoniot(target, u)[0] < hugoniot(flyer, u_fly - u)[0]:
            lo = u
        else:
            hi = u
    p, us = hugoniot(target, u)
    return u, p, us

#*** Temperature, for the materials with eos = mie_gruneisen_t
#*** (doc/design/materials.md): T = T0 exp(G0 eta) + (e - e_c(eta))/C_V,
#*** eta = 1 - rho0/rho. The cold energy here is the integral from V0,
#***    e_c(eta) = integral from 0 to eta of exp(G0 (eta - s)) Pi(s)/rho0 ds,
#*** by 16-point Gauss-Legendre on 8 pieces: not bitwhiz's step-by-step
#*** method, so the two check each other. Pi = P_H (1 - G0 eta/2) in
#*** compression, and bitwhiz's own cubic in rho - rho0 in tension (its
#*** rule there, src/modules/eos_mod.f95). Agrees with the 50-digit
#*** tests/temp_reference.py to 1e-14.

GRUNEISEN = {'Ta': 1.60, 'Al': 2.00, 'MatX': 1.20, 'PMMA': 0.90}  # G0
CV = 1.1633418e-3        # kJ/(g K): 1.35e11 erg/(g eV) / 11604.5 K/eV, as
                         # in the G1 deck (CV = 1.1633418 J/(g K))
T0 = 298.0               # K, every material in G1-G5
_XG, _WG = np.polynomial.legendre.leggauss(16)

def _pi(mat, s):
    # Pi(eta) = P(V, e = 0), GPa, for an array of eta.
    r0, c0, s1, s2 = MATERIALS[mat]
    g0 = GRUNEISEN[mat]
    s = np.asarray(s, dtype=float)
    out = np.empty_like(s)
    c = s >= 0
    a = 1.0 - s1 * s[c]
    us = 2.0 * c0 / (a + np.sqrt(a * a - 4.0 * s2 * s[c] ** 2))
    out[c] = r0 * s[c] * us * us * (1.0 - 0.5 * g0 * s[c])
    x = r0 / (1.0 - s[~c]) - r0
    a1 = c0 * c0
    a2 = (c0 * c0 / r0) * (4.0 * s1 - 2.0 - g0)
    a3 = (6.0 * c0 * c0 / r0 ** 2) * (3 * s1 * s1 - 4 * s1 - g0 * s1 + g0
                                      + 2 * s2 + 1)
    out[~c] = x * (a1 + x * (0.5 * a2 + x * a3 / 6.0))
    return out

def cold_energy(mat, eta):
    """e_c (kJ/g) on mat's cold curve at eta (scalar or array)."""
    r0, g0 = MATERIALS[mat][0], GRUNEISEN[mat]
    eta = np.atleast_1d(np.asarray(eta, dtype=float))[:, None]
    edges = np.linspace(0.0, 1.0, 9)
    tot = 0.0
    for a, b in zip(edges[:-1], edges[1:]):    # piece [a, b] of [0, eta]
        s = eta * (0.5 * (a + b) + 0.5 * (b - a) * _XG)
        f = np.exp(g0 * (eta - s)) * _pi(mat, s.ravel()).reshape(s.shape)
        tot = tot + 0.5 * (b - a) * eta[:, 0] * (f @ _WG)
    return tot / r0

def temperature(mat, rho, e):
    """T (K) at density rho (g/cm^3) and energy e (kJ/g), arrays or not."""
    r0, g0 = MATERIALS[mat][0], GRUNEISEN[mat]
    rho = np.asarray(rho, dtype=float)
    eta = (rho - r0) / rho
    return T0 * np.exp(g0 * eta) + (np.asarray(e) - cold_energy(mat, eta)
                                    .reshape(eta.shape)) / CV

def hugoniot_temperature(mat, rho):
    """T (K) on mat's principal Hugoniot at density rho (g/cm^3): the state
    a single shock from rest gives, e = e_H = (eta U_S)^2/2."""
    r0, c0, s1, s2 = MATERIALS[mat]
    eta = (rho - r0) / rho
    a = 1.0 - s1 * eta
    us = 2.0 * c0 / (a + np.sqrt(a * a - 4.0 * s2 * eta * eta))
    return float(temperature(mat, rho, 0.5 * (eta * us) ** 2))

def trust_end(r, rel=1.0e-6):
    """The last output time (us) at which total mass is still its initial
    value (to rel); the end of the file if it never changes."""
    m = r.g['MTOT']
    bad = np.flatnonzero(np.abs(m - m[0]) > rel * abs(m[0]))
    return r.t[-1] if len(bad) == 0 else r.t[bad[0] - 1]

def energy_drift(r, t_end=None):
    """Largest |ETOT - ETOT(0)| / ETOT(0) up to t_end (default: the trust
    window's end)."""
    t_end = trust_end(r) if t_end is None else t_end
    e = r.g['ETOT'][r.t <= t_end]
    return np.max(np.abs(e - e[0])) / abs(e[0])

#*** The self-test: the dataset README's published results (section 4),
#*** recomputed from the files with the definitions above.

# u_fly (km/s) -> published value. Arrivals, fits and energy drifts are
# given to 1 ns, 1 m/s or their last digit, so they must agree to half that
# digit; "P at 1 mm" to 0.002 GPa, its plateau's own scatter (first_shock).
# (The README's G5 drift at 100 zones/mm read 0.004 % until Nov 2, 2026:
# 0.00346 rounded twice. It now reads 0.0035 %, as the file gives.)
G1 = {1.00: dict(P1=4.371, Us=3.780, P1mm=4.371, Usfit=3.778, pdv=2.640),
      1.25: dict(P1=5.793, Us=4.070, P1mm=5.793, Usfit=4.069, pdv=2.451),
      1.50: dict(P1=7.331, Us=4.351, P1mm=7.330, Usfit=4.356, pdv=2.292),
      1.75: dict(P1=8.979, Us=4.625, P1mm=8.978, Usfit=4.624, pdv=2.156),
      2.00: dict(P1=10.736, Us=4.893, P1mm=10.736, Usfit=4.889, pdv=2.037)}
G2 = {2.00: (3.5, 1.520), 1.75: (5.5, 1.661), 1.50: (7.5, 1.950),
      1.25: (None, 2.406), 1.00: (None, 2.626)}     # run (mm), PDV arrival
G3 = {1.25: 12.5, 1.50: 7.5, 1.75: 4.75, 2.00: 3.75, 2.25: 2.375}
POP = (6.158, -2.074)              # ln x_run = a + b ln P1   (mm, GPa)
G4 = {(10, 20): 7.505, (10, 15): 7.505, (15, 20): 7.506}
G5 = {25: (1.5194, 0.583, 0.731, 0.015), 50: (1.5201, 0.589, 0.729, 0.007),
      100: (1.5203, 0.591, 0.729, 0.0035), 200: (1.5201, 0.592, 0.730, 0.002),
      400: (1.5201, 0.595, 0.730, 0.001)}
      # zones/mm: PDV arrival, arrivals at 3 and 4 mm (us), energy drift (%)
TRUST = {'G1': {1.00: 6.5, 1.25: 6.5, 2.00: 5.2}, 'G2': {1.00: 6.0, 2.00: 4.6},
         'G3': {1.25: 4.0, 1.50: 4.0, 2.25: 3.6}, 'G4': {3.00: 3.5}}

def _velocity(name):               # 'G2_react_1p75_kmps.dat' -> 1.75
    return float(name.split('_')[2].replace('p', '.'))

def _half_digit(x):                # half a unit in x's last printed digit
    return 0.51 * 10.0 ** -len(repr(x).split('.')[1])

def _near(r, x):                   # the tracer starting closest to x (mm)
    return min(r.tracers, key=lambda n: abs(r.x0[n] - x))

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    files = sorted(glob.glob(os.path.join(here, '*.dat')) +
                   glob.glob(os.path.join(here, 'inert_gauges', '*.dat')) +
                   glob.glob(os.path.join(here, 'hvrb', '*.dat')),
                   key=lambda f: (not os.path.basename(f).startswith('ME697'),
                                  os.path.basename(f)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        npass, nfail = npass + bool(ok), nfail + (not ok)
        print(('   pass  ' if ok else '   FAIL  ') + what)
    def close(got, want, tol):
        return got is not None and abs(got - want) <= tol
    pop = []
    for f in files:
        r = read(f)
        g = r.name.split('_')[0]
        print(f'{r.name}: {len(r.tracers)} tracers, {len(r.t)} rows, '
              f'variables {", ".join(r.vars)}')
        if g.startswith('ME697'):
            check(len(r.tracers) == 5 and r.has('GPA'), 'five tracers, x, u, P')
            continue
        v = _velocity(r.name)
        if g in TRUST and v in TRUST[g]:
            te = trust_end(r)
            # the README gives it to 0.1 us; one output row (5 ns) more
            check(abs(te - TRUST[g][v]) <= 0.055,
                  f'mass constant to {te:.2f} us '
                  f'(README {TRUST[g][v]})')
        if g == 'G1':
            p = G1[v]
            u1, p1, us = impedance_match(v)
            check(close(p1, p['P1'], 5.1e-4) and close(us, p['Us'], 5.1e-4),
                  f'exact P1 {p1:.3f} GPa, U_S {us:.3f} km/s')
            got = first_shock(r, _near(r, 1.0))
            check(close(got, p['P1mm'], 0.002), f'P at 1 mm {got:.4f} '
                  f'(README {p["P1mm"]}, exact {p1:.4f})')
            fit = shock_fit(r, 1.0, 9.0)[0]
            check(close(fit, p['Usfit'], 5.1e-4), f'U_S fit 1-9 mm {fit:.4f} '
                  f'(README {p["Usfit"]})')
            ta = arrival(r, _near(r, 10.0))
            check(close(ta, p['pdv'], 5.1e-4), f'PDV arrival {ta:.4f} us '
                  f'(README {p["pdv"]})')
            dr = 100 * energy_drift(r)
            check(dr <= 0.006, f'energy drift {dr:.4f} % (README <= 0.006 %)')
        elif g == 'G2':
            run, pdv = G2[v]
            got = run_distance(r, 10.0)
            check(got == run, f'run distance {got} mm (README {run})')
            ta = arrival(r, _near(r, 10.0))
            check(close(ta, pdv, 5.1e-4),
                  f'PDV arrival {ta:.4f} us (README {pdv})')
            if v == 2.00:          # also G5's 100 zones/mm member
                _, t3, t4, dr = G5[100]
                a3, a4 = arrival(r, _near(r, 3.0)), arrival(r, _near(r, 4.0))
                check(close(a3, t3, 5.1e-4) and close(a4, t4, 5.1e-4),
                      f'100 zones/mm: arrivals at 3 and 4 mm '
                      f'{a3:.4f}, {a4:.4f} us')
                got = 100 * energy_drift(r)
                check(close(got, dr, _half_digit(dr)), f'100 zones/mm: '
                      f'energy drift {got:.5f} % (README {dr})')
        elif g == 'G3':
            got = run_distance(r, 20.0)
            check(got == G3[v], f'run distance {got} mm (README {G3[v]})')
            pop.append((impedance_match(v)[1], got))
        elif g == 'G4':
            for (a, b), d in G4.items():
                got = shock_fit(r, a, b)[0]
                check(close(got, d, 5.1e-4),
                      f'D over {a}-{b} mm {got:.4f} km/s '
                      f'(README {d}; D_CJ {D_CJ:.4f})')
        elif g == 'G5':
            z = int(r.name.split('_')[4])
            pdv, t3, t4, dr = G5[z]
            ta = arrival(r, _near(r, 10.0))
            check(close(ta, pdv, 5.1e-5),
                  f'{z} zones/mm: PDV arrival {ta:.4f} us')
            a3, a4 = arrival(r, _near(r, 3.0)), arrival(r, _near(r, 4.0))
            check(close(a3, t3, 5.1e-4) and close(a4, t4, 5.1e-4),
                  f'{z} zones/mm: arrivals at 3 and 4 mm {a3:.4f}, {a4:.4f} us')
            got = 100 * energy_drift(r)
            check(close(got, dr, _half_digit(dr)), f'{z} zones/mm: energy '
                  f'drift {got:.5f} % (README {dr})')
            check(run_distance(r, 10.0) == 3.5,
                  f'{z} zones/mm: run distance 3.5 mm')
    if len(pop) == len(G3):
        b, a = np.polyfit(np.log([p for p, _ in pop]),
                          np.log([x for _, x in pop]), 1)
        check(close(a, POP[0], 5.1e-4) and close(b, POP[1], 5.1e-4),
              f'Pop plot: ln x_run = {a:.3f} {b:+.3f} ln P1 (README '
              f'{POP[0]} {POP[1]:+})')
    print(f'gold.py: {npass} passed, {nfail} failed ({len(files)} files)')
    return 1 if nfail else 0

if __name__ == '__main__':
    sys.exit(main())

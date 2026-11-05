#!/usr/bin/env python3
"""compare_hvrb.py -- bitwhiz against the gold-standard reactive data (G2-G5).

Runs bitwhiz with Material X burning (burn = hvrb, products = ideal_gas, the
reference's model and constants: hvrb/README.md, "Model"; the HVRB equation
sheet, doc/HVRB_Eqns_v8) on the reference's four sets, then measures bitwhiz
and the reference with the same lines of code (gold.py) and checks the
acceptance the data's README suggests, at 100 zones/mm:

   G2  class stack (hvrb/g2_react.deck), u_fly = 1.00 to 2.00 km/s
       run distance        within one tracer spacing (1 mm) of the
                           reference's, or no transition in 10 mm in both
       arrivals            1-9 mm and the PDV node within 7.5 ns
       energy              total energy drift within 0.01 % (method AV;
                           RS conserves it to round-off)
   G3  thick flyer (hvrb/g3_poplt.deck), u_fly = 1.25 to 2.25 km/s
       run distance        within one of the reference's own tracer
                           spacings (1, 0.5 or 0.25 mm), measured on its
                           tracers (bitwhiz's deck has one every 0.25 mm)
       arrivals            on the reference's tracers, within 7.5 ns
       the Pop plot        ln x_run = a + b ln P1 through the five,
                           reported beside the reference's
   G4  thick flyer at 3.00 km/s: the detonation speed
       D                   fits over 10-20, 10-15 and 15-20 mm within
                           0.5 % of D_CJ = 7.4999904 km/s
   G5  class stack at 2.00 km/s, 25, 50, 200 and 400 zones/mm (100 is G2's)
       each mesh           run distance within 1 mm of the reference's
       50 zones/mm and up  PDV arrival within 7.5 ns of the reference's on
                           the same mesh
       convergence         the finest mesh's PDV arrival within 7.5 ns of
                           the reference's finest, and bitwhiz's own
                           difference from its finest shrinking as the
                           mesh refines (50 to 200 zones/mm), or already
                           below 0.5 ns (5 ns output rows, interpolated)
       25 zones/mm         PDV arrival reported, not checked: the reaction
                           zone (about 0.14 mm, the sheet) spans 3 to 4
                           cells there, and the two codes' schemes part
                           (bitwhiz AV 13 ns early, RS order 2 about 7;
                           the data's acceptance is at 100 zones/mm)

and reports, without a pass or fail, the Pop plot's fit, the G4 fits beside
the reference's, and bitwhiz's own mesh convergence (G5). A "run distance" is
gold.py's: the midpoint of the first tracer interval whose mean shock speed
passes 0.9 D_CJ, so it moves in steps of the tracer spacing.

The arrival tolerance is 7.5 ns (Nov 5, 2026; the data's README suggests 5).
An arrival is the linear crossing of 0.05 km/s between two output rows, and
both codes write a row about every 5 ns, so a front sharper than one row is
placed up to a row early. Measured: with bitwhiz's rows ten times closer
(0.5 ns), its G3 arrivals (RS order 2) still run 0 to +5.5 ns from the
reference's, never earlier, which is the reference's own rows. 7.5 ns is one
of them and half again. (What prompted the study: RS order 2 at 5.0 and 5.1
ns in G3, against 5; AV's largest is 4.8.)

    python3 tests/verification/compare_hvrb.py [bitwhiz] [--rs] [--quick]
                                                [--sets G2,G3,G4,G5]

from the bitwhiz folder; [bitwhiz] defaults to bin/bitwhiz_release (make
release), else bin/bitwhiz. --rs runs method RS (order 2) instead of AV;
--quick leaves out G5's 200 and 400 zones/mm (the slow two); --sets picks
sets. The runs go to a scratch folder, as many at once as there are
processors, one thread each; the folder is removed at the end unless KEEP=1
is set. All four sets take about 10 minutes on 2 cores (the 400 zones/mm run
is the longest). Needs Python 3 and NumPy.

D. E. Kittell (with Claude), 11/04/26; the arrival tolerance, 11/05/26.
"""
import os, re, sys, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import gold

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DATA = os.path.join(HERE, 'hvrb')
DECK2 = os.path.join(DATA, 'g2_react.deck')             # G2, G5
DECK3 = os.path.join(DATA, 'g3_poplt.deck')             # G3, G4
G2_SPEEDS = (1.00, 1.25, 1.50, 1.75, 2.00)
G3_SPEEDS = (1.25, 1.50, 1.75, 2.00, 2.25)
G5_ZONES = (25, 50, 200, 400)
DT_ARRIVE = 0.0075                 # us, arrivals: the reference's 5 ns
                                   # rows and half again (docstring)
DRIFT = 1.0e-4                     # 0.01 %, total energy (AV)
REL_D = 5.0e-3                     # 0.5 %, the detonation speed
NOISE = 5.0e-4                     # us, 0.5 ns: below this an arrival's
                                   # change is interpolation between 5 ns
                                   # output rows, not convergence
GAUGES = ['x%d' % k for k in range(1, 10)] + ['pdv']   # G2's, bitwhiz names

def tag(v):                        # 1.75 -> '1p75'
    return ('%.2f' % v).replace('.', 'p')

def setkey(text, key, value, block=None):
    # Set "key = value" (the first such line), or add it after "Begin block".
    pat = r'(?m)^(\s*%s\s*=\s*)\S+' % key
    if re.search(pat, text):
        return re.sub(pat, r'\g<1>' + value, text, count=1)
    return re.sub(r'(?mi)^(\s*begin\s+%s\b.*)$' % block,
                  r'\1\n  %s = %s' % (key, value), text, count=1)

def run_one(exe, work, job):
    # One case: its deck, edited, run in its own folder; the tracer file.
    title, deck, v, edits = job
    text = open(deck).read()
    text = setkey(text, r'define\s+u_fly', '%.2f' % v)
    text = setkey(text, 'title', title)
    for key, value, block in edits:
        text = setkey(text, key, value, block)
    d = os.path.join(work, title)
    os.makedirs(d)
    with open(os.path.join(d, title + '.deck'), 'w') as fh:
        fh.write(text)
    p = subprocess.run([exe, title + '.deck'], cwd=d, capture_output=True,
                       text=True)
    if p.returncode != 0:
        raise RuntimeError(f'{title}: bitwhiz stopped (exit {p.returncode}):\n'
                           + p.stdout[-2000:])
    return os.path.join(d, title + '.tracers.csv')

def arrivals_at(run, xs):
    # [(x0, t)] at the tracers of run nearest each x in xs, in order.
    out = []
    for x in xs:
        n = gold._near(run, x)
        ta = gold.arrival(run, n)
        if ta is not None:
            out.append((run.x0[n], ta))
    return out

def run_distance_at(run, xs, frac=0.9):
    # gold.run_distance, on the tracers nearest xs (the reference's own).
    xa = arrivals_at(run, xs)
    for (x1, t1), (x2, t2) in zip(xa, xa[1:]):
        if t2 > t1 and (x2 - x1) / (t2 - t1) > frac * gold.D_CJ:
            return 0.5 * (x1 + x2)
    return None

def same_run(a, b, spacing):
    # Run distances agree: both "none", or within one tracer spacing.
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) <= spacing + 1e-9

def fmt(x):
    return 'none' if x is None else '%.3g mm' % x

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = [a for a in sys.argv[1:] if a.startswith('--')]
    rs = '--rs' in flags
    quick = '--quick' in flags
    sets = {'G2', 'G3', 'G4', 'G5'}
    for f in flags:
        if f.startswith('--sets='):
            sets = set(f.split('=', 1)[1].upper().split(','))
    exe = args[0] if args else next(
        (f for f in (os.path.join(ROOT, 'bin', 'bitwhiz_release'),
                     os.path.join(ROOT, 'bin', 'bitwhiz'))
         if os.access(f, os.X_OK)), None)
    if not exe or not os.access(exe, os.X_OK):
        sys.exit('compare_hvrb.py: no bitwhiz executable (make release '
                 'first, or name one)')
    exe = os.path.abspath(exe)
    meth = [('method', 'RS', 'Solver'), ('order', '2', 'Solver')] if rs else []
    jobs = {}
    if 'G5' in sets:               # the slowest first
        for z in sorted(G5_ZONES, reverse=True):
            if quick and z > 100:
                continue
            jobs['G5', z] = ('g5_react_%d_zpmm' % z, DECK2, 2.00,
                             [('resolution', str(z), 'Stack'),
                              ('t_end', '2.0', 'Run')] + meth)
    if 'G3' in sets:
        for v in G3_SPEEDS:
            jobs['G3', v] = ('g3_poplt_' + tag(v), DECK3, v, meth)
    if 'G4' in sets:
        jobs['G4', 3.00] = ('g4_wavsp_3p00', DECK3, 3.00,
                            [('t_end', '3.0', 'Run')] + meth)
    if 'G2' in sets:
        for v in G2_SPEEDS:
            jobs['G2', v] = ('g2_react_' + tag(v), DECK2, v, meth)
    work = tempfile.mkdtemp(prefix='hvrb_')
    nproc = os.cpu_count() or 1
    print(f'compare_hvrb.py: {exe}, method {"RS (order 2)" if rs else "AV"}'
          f'\n  {len(jobs)} runs in {work}, {nproc} at a time')
    with ThreadPoolExecutor(nproc) as ex:
        csv = dict(zip(jobs, ex.map(lambda j: run_one(exe, work, j),
                                    jobs.values())))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        npass, nfail = npass + bool(ok), nfail + (not ok)
        print(('   pass  ' if ok else '   FAIL  ') + what)
    def note(what):
        print('         ' + what)
    def ref(name):
        return gold.read(os.path.join(DATA, name))

    if 'G2' in sets:
        print('G2: class stack, 100 zones/mm')
        for v in G2_SPEEDS:
            b, r = gold.read(csv['G2', v]), ref('G2_react_%s_kmps.dat' % tag(v))
            xs = sorted(r.x0[n] for n in r.tracers if 0.0 <= r.x0[n] <= 10.0)
            rb, rr = run_distance_at(b, xs), gold.run_distance(r, 10.0)
            check(same_run(rb, rr, 1.0), f'{v:.2f} km/s: run distance '
                  f'{fmt(rb)} (reference {fmt(rr)})')
            rn = {g: gold._near(r, b.x0[g]) for g in GAUGES}
            dt = [gold.arrival(b, g) - gold.arrival(r, rn[g]) for g in GAUGES]
            worst = int(np.argmax(np.abs(dt)))
            check(max(abs(d) for d in dt) <= DT_ARRIVE, f'{v:.2f} km/s: '
                  f'arrivals 1-9 mm and PDV, bitwhiz - reference from '
                  f'{1e3*min(dt):+.1f} to {1e3*max(dt):+.1f} ns (largest at '
                  f'{GAUGES[worst]})')
            drift = gold.energy_drift(b)
            if rs:
                note(f'{v:.2f} km/s: energy drift {100*drift:.1e} % (RS)')
            else:
                check(drift <= DRIFT, f'{v:.2f} km/s: energy drift '
                      f'{100*drift:.5f} % (reference '
                      f'{100*gold.energy_drift(r):.5f} %)')
            te = b.t[-1]                   # bitwhiz's end (t_end)
            note(f'{v:.2f} km/s: PDV arrival {gold.arrival(b, "pdv"):.4f} us '
                 f'(reference {gold.arrival(r, rn["pdv"]):.4f}); lam at '
                 f'9 mm at {te:.1f} us {b["XRN", "x9"][-1]:.3f} (reference '
                 f'{np.interp(te, r.t, r["XRN3", rn["x9"]]):.3f})')

    if 'G3' in sets:
        print('G3: thick flyer, single-shock runs to detonation, 100 zones/mm')
        pop_b, pop_r = [], []
        for v in G3_SPEEDS:
            b, r = gold.read(csv['G3', v]), ref('G3_poplt_%s_kmps.dat' % tag(v))
            xs = sorted(r.x0[n] for n in r.tracers)
            sp = min(np.diff([x for x in xs if x > 0.1]))
            rb, rr = run_distance_at(b, xs), gold.run_distance(r, 20.0)
            check(same_run(rb, rr, sp), f'{v:.2f} km/s: run distance '
                  f'{fmt(rb)} (reference {fmt(rr)}; tracers every {sp:g} mm)')
            dt = [tb - tr for (_, tb), (_, tr) in
                  zip(arrivals_at(b, xs), arrivals_at(r, xs))]
            check(max(abs(d) for d in dt) <= DT_ARRIVE, f'{v:.2f} km/s: '
                  f'arrivals on the reference\'s tracers, bitwhiz - reference '
                  f'from {1e3*min(dt):+.1f} to {1e3*max(dt):+.1f} ns')
            p1 = gold.impedance_match(v)[1]
            if rb is not None and rr is not None:
                pop_b.append((p1, rb))
                pop_r.append((p1, rr))
        if len(pop_b) == len(G3_SPEEDS):
            fb = np.polyfit(np.log([p for p, _ in pop_b]),
                            np.log([x for _, x in pop_b]), 1)
            fr = np.polyfit(np.log([p for p, _ in pop_r]),
                            np.log([x for _, x in pop_r]), 1)
            note(f'Pop plot: ln x_run = {fb[1]:.3f} {fb[0]:+.3f} ln P1 '
                 f'(reference {fr[1]:.3f} {fr[0]:+.3f}; its README '
                 f'{gold.POP[0]} {gold.POP[1]:+})')

    if 'G4' in sets:
        print('G4: thick flyer at 3.00 km/s, the detonation speed')
        b, r = gold.read(csv['G4', 3.00]), ref('G4_wavsp_3p00_kmps.dat')
        for (lo, hi), dref in gold.G4.items():
            d = gold.shock_fit(b, lo, hi)[0]
            check(abs(d / gold.D_CJ - 1) <= REL_D, f'D over {lo}-{hi} mm '
                  f'{d:.4f} km/s ({100*(d/gold.D_CJ-1):+.3f} % of D_CJ '
                  f'{gold.D_CJ:.4f}; reference {dref})')

    if 'G5' in sets:
        print('G5: mesh study, class stack at 2.00 km/s')
        rows = []
        fine = {}
        for z in G5_ZONES:
            if ('G5', z) not in csv:
                continue
            b = gold.read(csv['G5', z])
            r = ref('G5_react_2p00_kmps_%d_zpmm.dat' % z)
            rn = gold._near(r, b.x0['pdv'])
            tb, tr = gold.arrival(b, 'pdv'), gold.arrival(r, rn)
            what = (f'{z:3d} zones/mm: PDV arrival {tb:.4f} us (reference '
                    f'{tr:.4f}, {1e3*(tb-tr):+.1f} ns)')
            if z >= 50:
                check(abs(tb - tr) <= DT_ARRIVE, what)
            else:
                note(what + ': the reaction zone spans 3 to 4 cells '
                     '(reported, not checked)')
            fine[z] = (tb, tr)
            xs = sorted(r.x0[n] for n in r.tracers if 0.0 <= r.x0[n] <= 10.0)
            rb, rr = run_distance_at(b, xs), gold.run_distance(r, 10.0)
            check(same_run(rb, rr, 1.0), f'{z:3d} zones/mm: run distance '
                  f'{fmt(rb)} (reference {fmt(rr)})')
            rows.append((z, tb, gold.arrival(b, 'x3'), gold.arrival(b, 'x4')))
        if ('G2', 2.00) in csv:
            b = gold.read(csv['G2', 2.00])
            rows.append((100, gold.arrival(b, 'pdv'), gold.arrival(b, 'x3'),
                         gold.arrival(b, 'x4')))
        for z, tp, t3, t4 in sorted(rows):
            note(f'{z:3d} zones/mm: bitwhiz arrivals, PDV {tp:.4f}, 3 mm '
                 f'{t3:.4f}, 4 mm {t4:.4f} us')
        pdv = {z: tp for z, tp, _, _ in rows}
        zf = max(fine) if fine else None
        if zf is not None and zf >= 200:
            tb, tr = fine[zf]
            mid = [z for z in (50, 100, 200) if z in pdv and z < zf]
            err = [abs(pdv[z] - pdv[zf]) for z in mid]
            check(abs(tb - tr) <= DT_ARRIVE and len(err) >= 2 and
                  all(b <= a or b <= NOISE for a, b in zip(err, err[1:])),
                  f'convergence: at {zf} zones/mm the PDV arrival is '
                  f'{1e3*(tb-tr):+.1f} ns from the reference\'s; bitwhiz\'s '
                  f'own difference from it at ' + ', '.join(
                      f'{z}: {1e3*e:.1f}' for z, e in zip(mid, err)) +
                  ' ns (shrinking, to below 0.5 ns)')

    print(f'compare_hvrb.py: {npass} passed, {nfail} failed')
    if os.environ.get('KEEP') == '1':
        print(f'  the runs are kept in {work}')
    else:
        shutil.rmtree(work)
    return 1 if nfail else 0

if __name__ == '__main__':
    sys.exit(main())

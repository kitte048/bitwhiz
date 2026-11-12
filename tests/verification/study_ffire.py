#!/usr/bin/env python3
"""study_ffire.py -- FlashFire (burn = flashfire) in runs: its gate and
seed, the lead shock inside the hydro, and its detonation against mesh
(doc/design/burn_models.md, "Verification, without reference data", and
"Step 6, FlashFire"). From the bitwhiz folder:

    python3 tests/verification/study_ffire.py [bitwhiz] [--quick]

  E1  the detector in the hydro, against its replay. The class stack
      (input/me697_ffire_2p00.deck) with TA = 0, AFF = BFF = 0, NS = 1,
      PR = 1 GPa, KFF = 1e-6/us and LAM0 = 1e-12: once a cell's lead
      shock is marked it is seeded to LAM0 and its rate is exactly KFF
      (1 + P_s), a constant, which RK4 integrates exactly, so its first
      step's lam gives P_s back, P_s = (lam_1 - LAM0)/(KFF dt) - 1 (dt
      that row's step). Five Material X tracers, rows every cycle, AV and
      RS (order 2):
        the step   the first row with lam > 0 is the row after the one
                   where bin/ls_replay, stepping the same rows, marks it
        P_s        the run's, from lam_1, is the replay's to REC_TOL
      (KFF is small enough that the burn does not touch the hydro before
      the marks: lam stays below 1e-4.)
  E2  the detonation (the example deck as it is, 2.00 km/s), 25 to 200
      zones/mm, AV and RS, beside HVRB's class deck (input/
      me697_hvrb_2p00.deck) on the same meshes: each Material X cell's
      lead-shock arrival (P > 1 GPa) from the history file, the detonation
      speed fitted over 6 to 9.5 mm (the front is past its run distance
      there):
        D          converged: at the two finest meshes within CONV_TOL
                   of each other (not checked with --quick); and within
                   DCJ_TOL of D_CJ = 7.4999904 km/s at the finest.
                   Beside HVRB's (the same products), within HVRB_TOL: not as close as ThermalCascade's
                   (study_tcas.py). FlashFire's reaction zone is about 2.5
                   times HVRB's (lam = 0.99 about 0.16 mm behind the front
                   against 0.07, at 200 zones/mm, RS), and the deck's
                   drive, its second shock, which keeps HVRB 0.6 % above
                   D_CJ (doc/design/av_study.md), holds FlashFire only
                   0.1 % above it: likely the longer zone, not checked
                   further
        run        the run distance (where the speed first passes 0.9
                   D_CJ, over 1 mm windows) reported, and its spread over
                   the meshes checked against RUN_TOL

Exit status 0 if every check passes. --quick runs 25 and 100 zones/mm only
in E2. About 4 minutes on 2 cores (--quick, about 1).
"""
import os, sys, re, glob, math, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from compare_hvrb import setkey
from study_av import history

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK = os.path.join(ROOT, 'input', 'me697_ffire_2p00.deck')
DECK_HV = os.path.join(ROOT, 'input', 'me697_hvrb_2p00.deck')
REPLAY = os.path.join(ROOT, 'bin', 'ls_replay')
MATX = dict(R0=1.60, C0=2.50)
D_CJ = 7.4999904
METHODS = {'AV': [('method', 'AV', 'Solver')],
           'RS2': [('method', 'RS', 'Solver'), ('order', '2', 'Solver')]}

#*** Tolerances (regression guards, set Nov 12 from these runs).
REC_TOL  = 1.0e-9       # E1: the run's P_s against the replay's (relative;
                        # measured 1e-15)
CONV_TOL = 0.001        # E2: D at the two finest meshes within 0.1 %
                        # (measured AV -0.03 %, RS -0.09 %)
DCJ_TOL  = 0.01         # E2: D within 1 % of D_CJ (measured AV +0.10, RS +0.13 %)
HVRB_TOL = 0.01         # E2: and within 1 % of HVRB's (measured AV -0.47, RS -0.44 %)
RUN_TOL  = 1.0          # E2: run distances within 1 mm of each other
                        # (measured 3.35 to 3.60 mm)

def run_one(exe, work, job):
    name, edits, extra = job
    text = open(DECK_HV if name.startswith('E2h') else DECK).read()
    for key, value, block in edits:
        text = setkey(text, key, value, block)
    for t in extra:
        text = re.sub(r'(?m)^(\s*Begin Output.*)$', r'\1\n  tracer = ' + t,
                      text, count=1)
    d = os.path.join(work, name)
    os.makedirs(d)
    with open(os.path.join(d, 'run.deck'), 'w') as fh:
        fh.write(text)
    p = subprocess.run([exe, 'run.deck'], cwd=d, capture_output=True,
                       text=True)
    if p.returncode != 0:
        raise RuntimeError(f'{name}: bitwhiz stopped (exit {p.returncode}):\n'
                           + p.stdout[-2000:])
    for f in glob.glob(os.path.join(d, '*.bmp')):
        os.remove(f)
    return d

def tracer_rows(d, name):
    f = glob.glob(os.path.join(d, '*.tracers.csv'))[0]
    lines = [l for l in open(f) if l.strip() and not l.startswith('#')]
    h = [x.strip() for x in lines[0].split(',')]
    a = []
    for l in lines[2:]:
        try:
            a.append([float(x) for x in l.split(',')])
        except ValueError:
            pass
    a = np.array(a)
    return a[:, h.index('TIME')], a[:, h.index('DTIME')], \
        a[:, h.index('XRN.' + name)], f

def replay_mark_row(csv, name):
    # The replay, row by row: the first row whose flag is 3 (marked),
    # counted as the tracer file counts its rows (row 0 is t = 0).
    o = subprocess.run([REPLAY, csv, name, repr(MATX['R0']),
                        repr(MATX['C0']), 'trace'], capture_output=True,
                       text=True).stdout.split('\n')
    flags = [int(l.split()[3]) for l in o if len(l.split()) == 4
             and not l.startswith(('marked', 'not-marked'))]
    last = o[-2].split() if o[-1] == '' else o[-1].split()
    k = next((i for i, f in enumerate(flags) if f == 3), None)
    return (None if k is None else k + 1), float(last[1])

def arrivals(d, P1=1.0):
    F, lay = history(d)
    kf, kl = lay['MatX']
    x0 = None
    ta = np.full(kl - kf, np.nan)
    for f in F:
        if x0 is None:
            x = f['XPOS'][kf:kl+1].astype(float)
            x0 = 0.5*(x[:-1] + x[1:]); x0 -= x0[0]
        P = f['GPA'][kf:kl].astype(float)
        new = np.isnan(ta) & (P > P1)
        ta[new] = f['time']
    ok = ~np.isnan(ta)
    return x0[ok], ta[ok]

def detonation(d):
    x0, ta = arrivals(d)
    w = (x0 >= 6.0) & (x0 <= 9.5)
    D = np.polyfit(ta[w], x0[w], 1)[0]
    run = np.nan
    for a in np.arange(0.0, 9.0, 0.05):
        w = (x0 >= a) & (x0 <= a + 1.0)
        if w.sum() > 3 and np.polyfit(ta[w], x0[w], 1)[0] > 0.9*D_CJ:
            run = a + 0.5
            break
    return D, run

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    quick = '--quick' in sys.argv
    exe = args[0] if args else (os.path.join(ROOT, 'bin', 'bitwhiz_release')
          if os.path.exists(os.path.join(ROOT, 'bin', 'bitwhiz_release'))
          else os.path.join(ROOT, 'bin', 'bitwhiz'))
    exe = os.path.abspath(exe)
    if not os.path.exists(REPLAY):
        subprocess.run(['make', 'ls_replay'], cwd=ROOT, check=True,
                       capture_output=True)
    meshes = [25, 100] if quick else [25, 50, 100, 200]
    tracers = [('x1', 'MatX@0.1'), ('x3', 'MatX@0.3'), ('x5', 'MatX@0.5'),
               ('x7', 'MatX@0.7'), ('x9', 'MatX@0.9')]
    clock = [('KFF', '1.0e-6', None), ('TA', '0.0', None), ('AFF', '0.0', None),
             ('BFF', '0.0', None), ('NS', '1.0', None), ('PR', '1.0', None),
             ('LAM0', '1.0e-12', None),
             ('tracer_dt', '0', None), ('plot_dt', '100', None)]
    jobs = [(f'E1_{m}', ed + clock, [f'{n:4s} {w}' for n, w in tracers])
            for m, ed in METHODS.items()]
    jobs += [(f'E2{h}_{m}_{z}', ed + [('resolution', str(z), 'Stack'),
                                      ('plot_dt', '0.005', None)], [])
             for h in ('', 'h') for m, ed in METHODS.items() for z in meshes]
    work = tempfile.mkdtemp(prefix='ffire_')
    print(f'study_ffire.py: {exe}\n  {len(jobs)} runs in {work}, 2 at a time')
    with ThreadPoolExecutor(2) as pool:
        dirs = dict(zip([j[0] for j in jobs],
                        pool.map(lambda j: run_one(exe, work, j), jobs)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        print('   %s  %s' % ('pass' if ok else 'FAIL', what))
        if ok: npass += 1
        else:  nfail += 1

    print('\nE1. The lead shock in the hydro, against its replay (a seed, '
          'then a constant rate, after the mark)')
    for m in METHODS:
        d = dirs[f'E1_{m}']
        for n, w in tracers:
            t, dt, lam, csv = tracer_rows(d, n)
            k = int(np.flatnonzero(lam > 0)[0])
            ps_run = (lam[k] - 1.0e-12)/(1.0e-6*dt[k]) - 1.0
            kr, ps_rep = replay_mark_row(csv, n)
            err = abs(ps_run/ps_rep - 1)
            check(kr is not None and k == kr + 1 and err <= REC_TOL and
                  lam.max() < 1e-4,
                  f'{m} {w:9s}: burns from row {k} (replay marks row {kr}), '
                  f'P_s {ps_run:.6f} GPa, the replay\'s to {err:.1e}')

    print('\nE2. The detonation, 2.00 km/s, against mesh (D_CJ = '
          f'{D_CJ} km/s)')
    for m in METHODS:
        Ds, runs = [], []
        for z in meshes:
            D, run = detonation(dirs[f'E2_{m}_{z}'])
            Dh, runh = detonation(dirs[f'E2h_{m}_{z}'])
            Ds.append((D, Dh)); runs.append(run)
            print(f'  {m:3s} {z:3d} zones/mm: D {D:.4f} km/s '
                  f'({100*(D/D_CJ - 1):+.2f} % from D_CJ, '
                  f'{100*(D/Dh - 1):+.2f} % from HVRB\'s {Dh:.4f}); '
                  f'run distance {run:.2f} mm (HVRB {runh:.2f})')
        D, Dh = Ds[-1]
        D2 = Ds[-2][0]
        if not quick:                     # 100 and 200 zones/mm (not 25)
            check(abs(D/D2 - 1) <= CONV_TOL,
                  f'{m}: D at {meshes[-2]} and {meshes[-1]} zones/mm '
                  f'within {100*CONV_TOL} % ({100*(D/D2 - 1):+.3f} %)')
        check(abs(D/D_CJ - 1) <= DCJ_TOL,
              f'{m}: D at {meshes[-1]} zones/mm within {100*DCJ_TOL} % of '
              f'D_CJ')
        check(abs(D/Dh - 1) <= HVRB_TOL,
              f'{m}: and within {100*HVRB_TOL} % of HVRB\'s')
        check(max(runs) - min(runs) <= RUN_TOL,
              f'{m}: run distances within {RUN_TOL} mm over the meshes '
              f'({min(runs):.2f} to {max(runs):.2f})')

    print(f'\nstudy_ffire.py: {npass} passed, {nfail} failed')
    shutil.rmtree(work)
    sys.exit(1 if nfail else 0)

if __name__ == '__main__':
    main()

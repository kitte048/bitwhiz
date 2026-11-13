#!/usr/bin/env python3
"""study_sign.py -- StochasticIgnite (burn = stochasticignite) in runs: its
gate, its bins and frozen noise, and its detonation as an ensemble against
mesh (doc/design/burn_models.md, "Verification, without reference data",
and "Step 7, StochasticIgnite"). From the bitwhiz folder:

    python3 tests/verification/study_sign.py [bitwhiz] [--quick]

  E1  the detector in the hydro, against its replay. The class stack
      (input/me697_sign_2p00.deck) with SIGMA = 0, AVRAMI = 1, NS = 1,
      PR = 1 GPa and MU = 1e-6/us: once a cell's lead shock is marked its
      clock runs at exactly MU (1 + P_s), a constant, so its first step's
      lam gives P_s back, P_s = -ln(1 - lam_1)/(MU dt) - 1 (dt that row's
      step). Five Material X tracers, rows every cycle, AV and RS (order
      2), as study_ffire.py's E1:
        the step   the first row with lam > 0 is the row after the one
                   where bin/ls_replay, stepping the same rows, marks it
        P_s        the run's, from lam_1, is the replay's to REC_TOL
  E2  the detonation as an ensemble (the example deck, 2.00 km/s, RS
      order 2), NSEED seeds at 25, 50 and 100 zones/mm. Z's draws are
      keyed by the cycle, so a seed's noise is another sample on each
      mesh: only the ensemble converges, not each run. Each run's
      lead-shock arrivals (P > 1 GPa) from the history file, its speed
      fitted over 6 to 9.5 mm and its run distance (where the speed
      first passes 0.9 D_CJ, over 1 mm windows), as study_ffire.py's:
        detonates  every run of every mesh reaches 0.9 D_CJ within 9 mm
        converged  the mean run distance at the two finest meshes agree:
                   their mean paired difference (seed by seed: the same
                   seed starts from the same Z on both meshes, so the
                   two are correlated) within ENS_SE of its standard
                   error
        SIGMA = 0  the clock alone (no noise) at the two finest meshes:
                   D converged, within CONV_TOL (not checked with
                   --quick), and within DCJ_TOL of D_CJ = 7.4999904 km/s
      The ensemble's D is reported, not checked: 2 to 4 % below D_CJ over
      6 to 9.5 mm. A bin whose rate is low or floored when the front
      reaches it burns behind the front, too late to drive it, so the
      front runs as a detonation that has not released all its energy by
      its sonic point (the model's result, not a fault: SIGMA = 0, the same
      deck without the noise, runs at D_CJ).
  E3  frozen noise, TAUZ = 1e30, SIGMA = 1.4 (so about one bin in six has
      MU + SIGMA Z <= 0), seeds SEEDS3 at two meshes, AV and RS: Z never
      moves from its table value, so a bin with MU + SIGMA Z0 <= 0 never
      burns and every other bin does. Z0 here from the table (src/
      modules/rand_mod.f95) at 50 digits, the bins from each cell's
      center, by the Fortran's own arithmetic:
        exactly    at t_end the Material X cells with lam = 0 are exactly
                   the cells of the dead bins, on every run
        burns      and every other cell has begun to burn (lam > 0; a
                   bin just above the floor burns slowly)

Exit status 0 if every check passes. --quick runs E2 at 25 and 50 zones/mm
with fewer seeds. About 5 minutes on 2 cores (--quick, about 2).
"""
import os, sys, re, glob, math, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import mpmath as mp
from compare_hvrb import setkey
from study_av import history
from study_ffire import (tracer_rows, replay_mark_row, detonation, D_CJ,
                         MATX, METHODS)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK = os.path.join(ROOT, 'input', 'me697_sign_2p00.deck')
REPLAY = os.path.join(ROOT, 'bin', 'ls_replay')

#*** Tolerances (regression guards, set Nov 12 from these runs).
REC_TOL = 1.0e-9        # E1: the run's P_s against the replay's (relative)
ENS_SE  = 3.0           # E2: mean run distances, 50 and 100 zones/mm,
                        # their paired difference within 3 standard errors
                        # (measured -0.13 +- 0.21 mm, 0.6)
CONV_TOL = 0.001        # E2: SIGMA = 0, D at the two finest meshes within
                        # 0.1 % (measured 50 and 100 zones/mm, -0.007 %)
DCJ_TOL = 0.01          # E2: SIGMA = 0, D within 1 % of D_CJ (measured
                        # +0.13 % at 100 zones/mm)
NSEED   = 12            # E2: the ensemble's seeds
SEEDS3  = [11, 222, 3333, 4444]        # E3

def run_one(exe, work, job):
    name, edits, extra = job
    text = open(DECK).read()
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

#*** The table's Z0 for bin j (module stochignite, si_z0), at 50 digits.
mp.mp.dps = 50
_src = open(os.path.join(ROOT, 'src', 'modules', 'rand_mod.f95')).read()
TABLE = [mp.mpf(v) for v in re.findall(r'(-?[0-9]*\.[0-9]+)_z', _src)]
assert len(TABLE) == 20000

def z0(seed, j):
    u = TABLE[(seed + 7919*j) % 20000]
    return float(mp.sqrt(2)*mp.erfinv(2*u - 1))

def bins(nz, width, LC, xleft=0.0):
    # Each cell's bin, as module burn's alloc_burn and bin_of compute it
    # (IEEE doubles, no contraction: the same bits).
    return [math.floor((xleft + width*((i + 0.5)/nz))/LC) for i in range(nz)]

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
    meshes = [25, 50] if quick else [25, 50, 100]
    nseed = 8 if quick else NSEED
    seeds = [101*s + 7 for s in range(nseed)]
    tracers = [('x1', 'MatX@0.1'), ('x3', 'MatX@0.3'), ('x5', 'MatX@0.5'),
               ('x7', 'MatX@0.7'), ('x9', 'MatX@0.9')]
    clock = [('MU', '1.0e-6', None), ('SIGMA', '0.0', None),
             ('AVRAMI', '1.0', None), ('NS', '1.0', None), ('PR', '1.0', None),
             ('tracer_dt', '0', None), ('plot_dt', '100', None)]
    rs2 = METHODS['RS2']
    jobs = [(f'E1_{m}', ed + clock, [f'{n:4s} {w}' for n, w in tracers])
            for m, ed in METHODS.items()]
    jobs += [(f'E2_{z}_{s}', rs2 + [('resolution', str(z), 'Stack'),
                                    ('SEED', str(s), None),
                                    ('plot_dt', '0.005', None)], [])
             for z in meshes for s in seeds]
    jobs += [(f'E2_s0_{z}', rs2 + [('resolution', str(z), 'Stack'),
                                   ('SIGMA', '0.0', None),
                                   ('plot_dt', '0.005', None)], [])
             for z in meshes[-2:]]
    m3 = [25, 50]
    frozen = [('SIGMA', '1.4', None), ('TAUZ', '1.0e30', None),
              ('plot_dt', '100', None)]
    jobs += [(f'E3_{m}_{z}_{s}', ed + frozen + [('resolution', str(z), 'Stack'),
                                                ('SEED', str(s), None)], [])
             for m, ed in METHODS.items() for z in m3 for s in SEEDS3]
    work = tempfile.mkdtemp(prefix='sign_')
    print(f'study_sign.py: {exe}\n  {len(jobs)} runs in {work}, 2 at a time')
    with ThreadPoolExecutor(2) as pool:
        dirs = dict(zip([j[0] for j in jobs],
                        pool.map(lambda j: run_one(exe, work, j), jobs)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        print('   %s  %s' % ('pass' if ok else 'FAIL', what))
        if ok: npass += 1
        else:  nfail += 1

    print('\nE1. The lead shock in the hydro, against its replay (SIGMA = 0: '
          'a constant rate after the mark)')
    for m in METHODS:
        d = dirs[f'E1_{m}']
        for n, w in tracers:
            t, dt, lam, csv = tracer_rows(d, n)
            k = int(np.flatnonzero(lam > 0)[0])
            ps_run = -math.log1p(-lam[k])/(1.0e-6*dt[k]) - 1.0
            kr, ps_rep = replay_mark_row(csv, n)
            err = abs(ps_run/ps_rep - 1)
            check(kr is not None and k == kr + 1 and err <= REC_TOL and
                  lam.max() < 1e-4,
                  f'{m} {w:9s}: burns from row {k} (replay marks row {kr}), '
                  f'P_s {ps_run:.6f} GPa, the replay\'s to {err:.1e}')

    print(f'\nE2. The detonation as an ensemble, {nseed} seeds, RS order 2, '
          f'2.00 km/s (D_CJ = {D_CJ} km/s)')
    stats, runs = [], {}
    for z in meshes:
        r = np.array([detonation(dirs[f'E2_{z}_{s}']) for s in seeds])
        D, run = r[:, 0], r[:, 1]
        runs[z] = run
        ok = not np.isnan(run).any()
        mean, se = np.nanmean(run), np.nanstd(run, ddof=1)/math.sqrt(len(run))
        stats.append((mean, se))
        print(f'  {z:3d} zones/mm: run distance {mean:.2f} +- {se:.2f} mm '
              f'(sd {np.nanstd(run, ddof=1):.2f}, {np.nanmin(run):.2f} to '
              f'{np.nanmax(run):.2f}); D {D.mean():.3f} km/s '
              f'({100*(D.mean()/D_CJ - 1):+.1f} % from D_CJ)')
        check(ok, f'{z} zones/mm: every seed detonates within 9 mm')
    (m1, s1), (m2, s2) = stats[-2], stats[-1]
    d = runs[meshes[-1]] - runs[meshes[-2]]               # seed by seed
    sd = np.std(d, ddof=1)/math.sqrt(len(d))
    dz = abs(d.mean())/sd
    check(dz <= ENS_SE, f'the mean run distance at {meshes[-2]} and '
          f'{meshes[-1]} zones/mm agree: {m1:.2f} and {m2:.2f} mm, '
          f'paired difference {d.mean():+.2f} +- {sd:.2f} mm, {dz:.1f} '
          f'standard errors (at most {ENS_SE})')
    D1, run1 = detonation(dirs[f'E2_s0_{meshes[-2]}'])
    D, run = detonation(dirs[f'E2_s0_{meshes[-1]}'])
    print(f'  SIGMA = 0: D {D1:.4f} and {D:.4f} km/s at {meshes[-2]} and '
          f'{meshes[-1]} zones/mm; run distance {run1:.2f} and {run:.2f} mm')
    if not quick:
        check(abs(D/D1 - 1) <= CONV_TOL,
              f'SIGMA = 0: D at {meshes[-2]} and {meshes[-1]} zones/mm '
              f'within {100*CONV_TOL} % ({100*(D/D1 - 1):+.3f} %)')
    check(abs(D/D_CJ - 1) <= DCJ_TOL,
          f'SIGMA = 0 at {meshes[-1]} zones/mm: D within {100*DCJ_TOL} % '
          f'of D_CJ ({100*(D/D_CJ - 1):+.2f} %)')

    print('\nE3. Frozen noise (TAUZ = 1e30, SIGMA = 1.4): the cells that never '
          'burn are the bins with MU + SIGMA Z0 <= 0')
    MU, SIG, LC = 1.35, 1.4, 0.5         # the deck's MU and LC
    for m in METHODS:
        for z in m3:
            for s in SEEDS3:
                F, lay = history(dirs[f'E3_{m}_{z}_{s}'])
                kf, kl = lay['MatX']
                lam = F[-1]['XRN'][kf:kl].astype(float)
                jb = bins(kl - kf, 10.0, LC)
                dead = np.array([MU + SIG*z0(s, j) <= 0 for j in jb])
                nd = len(set(j for j, dd in zip(jb, dead) if dd))
                check(np.array_equal(lam == 0.0, dead) and
                      (lam[~dead] > 0.0).all(),
                      f'{m} {z} zones/mm, SEED {s:4d}: {nd} dead bins of '
                      f'{len(set(jb))}, {dead.sum()} cells unburnt, '
                      f'exactly them; the rest burning (least lam '
                      f'{lam[~dead].min():.3f})')

    print(f'\nstudy_sign.py: {npass} passed, {nfail} failed')
    shutil.rmtree(work)
    sys.exit(1 if nfail else 0)

if __name__ == '__main__':
    main()

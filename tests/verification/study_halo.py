#!/usr/bin/env python3
"""study_halo.py -- HALO (burn = halo) in runs: its activation measure in
the hydro, its detonation against mesh, AV beside RS, and the shock
desensitization it is for (doc/design/burn_models.md, "Verification,
without reference data", and "Step 8, HALO"). From the bitwhiz folder:

    python3 tests/verification/study_halo.py [bitwhiz] [--quick]

  E1  the activation measure in the hydro, against its replay. The class
      stack (input/me697_halo_2p00.deck) with DFRAC = 1, NH = 0, BETAH = 1,
      ED0 = 1, TAUD = 1e30 and KB = 1e-6/us: the burn's potential then
      grows at KB Erf(E_D) and nothing dissipates, so wherever E_D has
      stopped growing, a step's lam gives E_D back, E_D = erfinv(Ds/(KB
      dt)), s = -ln(1 - lam). Five Material X tracers, rows every cycle, AV
      and RS (order 2):
        the run    E_D from lam is the replay's to REC_TOL: the replay
                   sums sqrt(max(De, 0) max(v_min - v, 0)) over the same
                   tracer's rho and e rows, v_min the smallest v so far
        AV and RS  at the end, each tracer's E_D under AV within METH_TOL
                   of RS's (DK: the methods' tracer data should look
                   alike; the new-compression rule is what makes them)
      (KB is small enough that the burn does not touch the hydro: lam stays
      below 1e-4.)
  E2  the detonation (the example deck as it is, 2.00 km/s), 25 to 200
      zones/mm, AV and RS: each Material X cell's lead-shock arrival (P > 1
      GPa) from the history file, the detonation speed fitted over 6 to 9.5
      mm and the run distance (where the speed first passes 0.9 D_CJ, over
      1 mm windows), as study_ffire.py's:
        D          converged: at the two finest meshes within CONV_TOL (not
                   checked with --quick); within DCJ_TOL of D_CJ at the
                   finest
        run        the run distances within RUN_TOL over the meshes, and AV
                   within RUN_AVRS of RS at the finest
  E3  shock desensitization: a Ta flyer (one strong shock into Material X)
      against the same flyer faced with 1 mm of PMMA (a weak shock, then
      the Ta's), at 1.25 km/s (with --quick; also 1.50 and 1.75 without),
      HALO as the example deck, HALO without dissipation (TAUD = 1e30),
      and HVRB's class deck, RS order 2, 35 zones/mm. The run distance
      from Material X's face; the delay the facing costs:
        HALO       at 1.25 km/s HALO's delay at least DES_MIN times HVRB's
                   (measured 2.6 mm against 1.35)
        TAUD       and dissipation lengthens it (HALO's run with the facing
                   longer than without dissipation)
      Regression guards on the model's behavior, set from these runs: the
      memory of the weak shock (less E_D, and dissipated hot spots never
      reactivated) delays the detonation beyond HVRB's, which has none.

Exit status 0 if every check passes. --quick runs 25 and 100 zones/mm only
in E2, and 1.25 km/s only in E3. About 5 minutes on 2 cores (--quick,
about 2).
"""
import os, sys, re, glob, math, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy.special import erfinv
from compare_hvrb import setkey
from study_av import history
from study_ffire import detonation, D_CJ, METHODS

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK = os.path.join(ROOT, 'input', 'me697_halo_2p00.deck')
DECK_HV = os.path.join(ROOT, 'input', 'me697_hvrb_2p00.deck')

#*** Tolerances (regression guards, set Nov 13 from these runs).
REC_TOL  = 1.0e-11      # E1: E_D from lam against the replay (relative;
                        # measured 4e-13)
METH_TOL = 0.01         # E1: AV's E_D within 1 % of RS's (measured 0.2 %)
CONV_TOL = 0.001        # E2: D at the two finest meshes within 0.1 %
DCJ_TOL  = 0.01         # E2: D within 1 % of D_CJ
RUN_TOL  = 1.0          # E2: run distances within 1 mm over the meshes
RUN_AVRS = 0.25         # E2: AV's run distance within 0.25 mm of RS's
DES_MIN  = 1.5          # E3: HALO's delay at least 1.5 times HVRB's
                        # at 1.25 km/s (measured 1.9)
KB_E1    = 1.0e-6

def run_one(exe, work, job):
    name, text = job
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

def edited(path, edits, tracers=(), u=None):
    text = open(path).read()
    if u:
        text = re.sub(r'define u_fly = [0-9.]+', f'define u_fly = {u}', text)
    for key, value, block in edits:
        text = setkey(text, key, value, block)
    for t in tracers:
        text = re.sub(r'(?m)^(\s*Begin Output.*)$', r'\1\n  tracer = ' + t,
                      text, count=1)
    return text

def faced(path, u, face):
    # The class stack's flyer without its Al: Ta alone, or Ta faced with 1
    # mm of PMMA (layers named, PMMA being the window too).
    lay = lambda m, w, v, n: (f'  Begin Layer\n   name = {n}\n   material = '
                              f'{m}\n   width    = {w}\n'
                              + (f'   xvel     = {v}\n' if v else '')
                              + '  End Layer\n')
    s = (' Begin Stack\n  resolution = 35\n  origin     = '
         + ('face' if face else 'Ta') + ':MatX\n' + lay('Ta', '3.0', 'u_fly', 'Ta')
         + (lay('PMMA', '1.0', 'u_fly', 'face') if face else '')
         + lay('MatX', '10.0', None, 'MatX') + lay('PMMA', '10.0', None, 'win')
         + ' End Stack\n')
    t = re.sub(r'(?s) Begin Stack.*? End Stack\n', s, open(path).read())
    t = re.sub(r'define u_fly = [0-9.]+', f'define u_fly = {u}', t)
    t = re.sub(r'(?m)^\s*tracer\s*=.*$', '', t)
    t = re.sub(r'(?m)^(\s*Begin Output.*)$', r'\1\n  tracer = pdv MatX:win', t,
               count=1)
    return setkey(t, 'plot_dt', '0.005', None)

def tracer_table(d):
    f = glob.glob(os.path.join(d, '*.tracers.csv'))[0]
    lines = [l for l in open(f) if l.strip() and not l.startswith('#')]
    h = [x.strip() for x in lines[0].split(',')]
    a = []
    for l in lines[2:]:
        try:
            a.append([float(x) for x in l.split(',')])
        except ValueError:
            pass
    return h, np.array(a)

def replay(rho, e):
    # E_D, row by row, as module halo computes it: new compression only.
    v = 1.0/rho
    ed, vm, out = 0.0, v[0], [0.0]
    for k in range(1, len(v)):
        ed += math.sqrt(max(e[k] - e[k-1], 0.0)*max(vm - v[k], 0.0))
        vm = min(vm, v[k])
        out.append(ed)
    return np.array(out)

def rundist(d):
    # As study_ffire's detonation(), from Material X's face.
    return detonation(d)[1]

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    quick = '--quick' in sys.argv
    exe = args[0] if args else (os.path.join(ROOT, 'bin', 'bitwhiz_release')
          if os.path.exists(os.path.join(ROOT, 'bin', 'bitwhiz_release'))
          else os.path.join(ROOT, 'bin', 'bitwhiz'))
    exe = os.path.abspath(exe)
    meshes = [25, 100] if quick else [25, 50, 100, 200]
    speeds = ['1.25'] if quick else ['1.25', '1.50', '1.75']
    tracers = [('x1', 'MatX@0.1'), ('x3', 'MatX@0.3'), ('x5', 'MatX@0.5'),
               ('x7', 'MatX@0.7'), ('x9', 'MatX@0.9')]
    clock = [('DFRAC', '1.0', None), ('NH', '0.0', None),
             ('BETAH', '1.0', None), ('ED0', '1.0', None),
             ('TAUD', '1.0e30', None), ('KB', repr(KB_E1), None),
             ('tracer_dt', '0', None), ('plot_dt', '100', None)]
    jobs = [(f'E1_{m}', edited(DECK, ed + clock,
                               [f'{n:4s} {w}' for n, w in tracers]))
            for m, ed in METHODS.items()]
    jobs += [(f'E2_{m}_{z}', edited(DECK, ed + [('resolution', str(z), 'Stack'),
                                                ('plot_dt', '0.005', None)]))
             for m, ed in METHODS.items() for z in meshes]
    for u in speeds:
        for face in (None, 'PMMA'):
            tag = f'{"PMMA" if face else "Ta"}_{u}'
            jobs.append((f'E3_halo_{tag}', faced(DECK, u, face)))
            jobs.append((f'E3_nod_{tag}', setkey(faced(DECK, u, face), 'TAUD',
                                                 '1.0e30', None)))
            jobs.append((f'E3_hvrb_{tag}', faced(DECK_HV, u, face)))
    work = tempfile.mkdtemp(prefix='halo_')
    print(f'study_halo.py: {exe}\n  {len(jobs)} runs in {work}, 2 at a time')
    with ThreadPoolExecutor(2) as pool:
        dirs = dict(zip([j[0] for j in jobs],
                        pool.map(lambda j: run_one(exe, work, j), jobs)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        print('   %s  %s' % ('pass' if ok else 'FAIL', what))
        if ok: npass += 1
        else:  nfail += 1

    print('\nE1. The activation measure in the hydro, against its replay '
          '(new compression only)')
    final = {}
    for m in METHODS:
        h, a = tracer_table(dirs[f'E1_{m}'])
        t = a[:, h.index('TIME')]
        for n, w in tracers:
            rho = a[:, h.index('RHO.' + n)]
            e = a[:, h.index('SIE.' + n)]
            lam = a[:, h.index('XRN.' + n)]
            E = replay(rho, e)
            s = -np.log1p(-lam)
            # rows where the replay's E_D has not moved for 3 rows
            flat = [k for k in range(4, len(E)) if E[k] == E[k-3] and E[k] > 0]
            if not flat:
                check(False, f'{m} {w}: E_D never stopped growing (no row '
                      'to compare)')
                continue
            k = flat[-1]
            Er = erfinv((s[k] - s[k-1])/(KB_E1*(t[k] - t[k-1])))
            err = abs(Er/E[k] - 1)
            final[(m, n)] = E[-1]
            check(err <= REC_TOL and lam.max() < 1e-4,
                  f'{m:3s} {w:9s}: E_D from lam {Er:.10f}, the replay\'s to '
                  f'{err:.1e}')
    worst = max(abs(final[('AV', n)]/final[('RS2', n)] - 1) for n, _ in tracers)
    print('  E_D at the end, AV and RS: ' + ', '.join(
        f'{final[("AV", n)]:.4f}/{final[("RS2", n)]:.4f}' for n, _ in tracers))
    check(worst <= METH_TOL, f'AV\'s E_D within {100*METH_TOL} % of RS\'s at '
          f'every tracer ({100*worst:.2f} % at worst)')

    print(f'\nE2. The detonation, 2.00 km/s, against mesh (D_CJ = {D_CJ} km/s)')
    finest = {}
    for m in METHODS:
        Ds, runs = [], []
        for z in meshes:
            D, run = detonation(dirs[f'E2_{m}_{z}'])
            Ds.append(D); runs.append(run)
            print(f'  {m:3s} {z:3d} zones/mm: D {D:.4f} km/s '
                  f'({100*(D/D_CJ - 1):+.2f} % from D_CJ); run distance '
                  f'{run:.2f} mm')
        finest[m] = runs[-1]
        if not quick:
            check(abs(Ds[-1]/Ds[-2] - 1) <= CONV_TOL,
                  f'{m}: D at {meshes[-2]} and {meshes[-1]} zones/mm within '
                  f'{100*CONV_TOL} % ({100*(Ds[-1]/Ds[-2] - 1):+.3f} %)')
        check(abs(Ds[-1]/D_CJ - 1) <= DCJ_TOL,
              f'{m}: D at {meshes[-1]} zones/mm within {100*DCJ_TOL} % of D_CJ')
        check(max(runs) - min(runs) <= RUN_TOL,
              f'{m}: run distances within {RUN_TOL} mm over the meshes '
              f'({min(runs):.2f} to {max(runs):.2f})')
    check(abs(finest['AV'] - finest['RS2']) <= RUN_AVRS,
          f'AV\'s run distance within {RUN_AVRS} mm of RS\'s at '
          f'{meshes[-1]} zones/mm ({finest["AV"]:.2f} and {finest["RS2"]:.2f})')

    print('\nE3. Shock desensitization: Ta flyer, and Ta faced with 1 mm of '
          'PMMA; run distance from Material X\'s face (mm)')
    delay = {}
    for u in speeds:
        row = []
        for mdl in ('halo', 'nod', 'hvrb'):
            r1 = rundist(dirs[f'E3_{mdl}_Ta_{u}'])
            r2 = rundist(dirs[f'E3_{mdl}_PMMA_{u}'])
            delay[(mdl, u)] = (r1, r2)
            row.append(f'{mdl} {r1:.2f} / {r2:.2f} (delay {r2 - r1:+.2f})')
        print(f'  {u} km/s: ' + '; '.join(row))
    (h1, h2), (n1, n2), (v1, v2) = (delay[('halo', '1.25')],
                                    delay[('nod', '1.25')],
                                    delay[('hvrb', '1.25')])
    check(h2 - h1 >= DES_MIN*(v2 - v1),
          f'1.25 km/s: HALO\'s delay {h2 - h1:.2f} mm at least {DES_MIN} times '
          f'HVRB\'s {v2 - v1:.2f}')
    check(h2 > n2, f'1.25 km/s: dissipation lengthens the faced run '
          f'({h2:.2f} mm, without dissipation {n2:.2f})')

    print(f'\nstudy_halo.py: {npass} passed, {nfail} failed')
    shutil.rmtree(work)
    sys.exit(1 if nfail else 0)

if __name__ == '__main__':
    main()

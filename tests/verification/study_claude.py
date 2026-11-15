#!/usr/bin/env python3
"""study_claude.py -- CLAUDE (burn = claude) in runs: its entropy against
the Hugoniot's, the whole model replayed from a tracer's own rows, its
detonation against mesh, and the shock desensitization it is for
(doc/design/burn_models.md, "Verification, without reference data", and
"Step 9, CLAUDE"). From the bitwhiz folder:

    python3 tests/verification/study_claude.py [bitwhiz] [--quick]

  E1  the entropy behind a shock, against the exact entropy on Material
      X's Hugoniot at the same pressure. CLAUDE's inert test deck (D0 = 0)
      with a Solver block, AV and RS (order 2), 25 to 200 zones/mm; two
      tracers, rows every cycle; s = C_V ln(T/(T0 exp(G0 eta))) from the
      tracer's TK and RHO on the first shock's plateau (P within FLAT over
      the window); the Hugoniot's from Material X's Us-up line and its cold
      curve, integrated here:
        entropy    within S_TOL of the Hugoniot's, every method and mesh
                   (it is a state function: no sum over steps)
  E2  the model in the hydro, against its replay. The class stack
      (input/me697_claude_2p00.deck) with D0 = 1e-5 mm/us, so lam stays
      near 1e-12 and neither the hydro nor the tracer's T (the mixture's,
      which the reaction heats by about 4000 K per unit lam) feels it;
      NG = 1, so the growth takes P^n; five Material X tracers, rows every
      cycle, AV and RS: the whole step (the entropy from the tracer's TK
      and RHO, the running maximum, the centers lit, the growth at P^n,
      the moments, the quench, lam) redone here from the rows, the state
      at the end of each step under AV and at its start under RS:
        the step   the first row with lam > 0 the code's and the replay's
        lam        the replay's to REC_TOL wherever lam is above 1e-6 of
                   its largest
  E3  the detonation (the example deck, 2.00 km/s), 25 to 200 zones/mm, AV
      and RS, as study_halo.py's E2:
        D          converged (the two finest meshes within CONV_TOL; not
                   with --quick); within DCJ_TOL of D_CJ at the finest
        run        within RUN_TOL over the meshes; AV within RUN_AVRS of
                   RS at the finest
  E4  shock desensitization: study_halo.py's Ta flyer, alone and faced with
      1 mm of PMMA, at 1.50 km/s (and 1.25 and 1.75 without --quick); CLAUDE
      as the example deck and without its quench (TQ = 1e30), HALO's and
      HVRB's class decks, RS order 2, 35 zones/mm; the run distance from
      Material X's face, and the delay the facing costs:
        CLAUDE     its delay at least DES_MIN times HALO's at 1.50 km/s
                   (and 1.75): the entropy of a weak shock is far less
                   than of a strong one to the same pressure
      (At 1.25 km/s the faced flyer does not detonate CLAUDE's Material X
      within 9 mm: reported.)

Exit status 0 if every check passes. --quick runs 25 and 100 zones/mm only
in E1 and E3, and 1.50 km/s only in E4. About 6 minutes on 2 cores
(--quick, about 2).
"""
import os, sys, re, glob, math, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy.integrate import solve_ivp
from scipy.optimize import brentq
from compare_hvrb import setkey
from study_ffire import detonation, D_CJ, METHODS
from study_halo import faced, rundist

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK = os.path.join(ROOT, 'input', 'me697_claude_2p00.deck')
DECK_HA = os.path.join(ROOT, 'input', 'me697_halo_2p00.deck')
DECK_HV = os.path.join(ROOT, 'input', 'me697_hvrb_2p00.deck')
INERT = os.path.join(ROOT, 'tests', 'decks', 'ok_claude_inert.deck')

#*** Tolerances (regression guards, set Nov 14 from these runs).
S_TOL    = 0.005        # E1: within 0.5 % of the Hugoniot's (measured
                        # 0.31 % at worst, AV at 25 zones/mm)
FLAT     = 0.05         # E1: P within 5 % over the window, so it is the
                        # plateau, not the shock's rise or a second wave
                        # (measured 3.5 % at worst: AV's ringing, 25
                        # zones/mm; RS 1.1 %)
REC_TOL  = 1.0e-9       # E2: lam against the replay (relative)
CONV_TOL = 0.001        # E3: D at the two finest meshes within 0.1 %
DCJ_TOL  = 0.01         # E3: D within 1 % of D_CJ
RUN_TOL  = 1.0          # E3: run distances within 1 mm over the meshes
RUN_AVRS = 0.3          # E3: AV's run distance within 0.3 mm of RS's
DES_MIN  = 1.5          # E4: CLAUDE's delay at least 1.5 times HALO's

#*** Material X, as the decks have it.
R0, C0, S1, S2, G0, T0, CV = 1.6, 2.5, 1.8, -0.1, 1.2, 298.0, 1.1633418e-3
NMAX, W0, KW, PR, TQ = 1000.0, 0.66, 4.0, 7.0, 0.25
D0_E2 = 1.0e-5

def hug(up):
    Us = C0 + S1*up + (S2/C0)*up**2
    return R0*Us*up, (1/R0)*(1 - up/Us), 0.5*up**2

def e_cold(eta):
    # module temperature's cold curve: de_c/deta = G0 e_c + Pi/R0, Pi =
    # P_H - R0 G0 e_H on the principal Hugoniot
    def Pi(x):
        if x <= 0:
            return 0.0
        v = (1/R0)*(1 - x)
        P, _, e = hug(brentq(lambda u: hug(u)[1] - v, 0, 3))
        return P - R0*G0*e
    s = solve_ivp(lambda x, y: [G0*y[0] + Pi(x)/R0], [0, eta], [0.0],
                  rtol=1e-11, atol=1e-14)
    return s.y[0, -1]

def s_hugoniot(P):
    P, v, e = hug(brentq(lambda u: hug(u)[0] - P, 1e-9, 3))
    eta = 1 - R0*v
    ts = T0*math.exp(G0*eta)
    return 1000*CV*math.log((ts + (e - e_cold(eta))/CV)/ts)

def s_of(T, rho):
    eta = 1 - R0/rho
    return 1000*CV*np.log(T/(T0*np.exp(G0*eta)))

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

def jk(dt, q):
    # J_k = int_0^dt u^k e^(-q u) du by its series (q dt here ~ 0.01)
    x, out = q*dt, []
    for k in range(5):
        term, sm = 1.0, 1.0/(k + 1)
        for m in range(1, 30):
            term *= -x/m
            sm += term/(k + m + 1)
        out.append(dt**(k + 1)*sm)
    return out

def replay(t, T, rho, P, av):
    # CLAUDE's step, row by row, from the tracer's rows (module claude's
    # definition, written again here): AV takes the state at the step's
    # end, RS at its start.
    s = s_of(T, rho)
    w, M, vq, q = 0.0, [0.0]*4, 0.0, 1/TQ
    lam = [0.0]
    for k in range(1, len(t)):
        dt = t[k] - t[k-1]
        j = k if av else k - 1
        w2, dn = max(w, s[j]), 0.0
        if w2 > w and w2 > 0:                # n(w2) - n(w), no cancellation
            if w > 0:
                x1 = (w/W0)**KW
                dx = x1*math.expm1(KW*math.log1p((w2 - w)/w))
            else:
                x1, dx = 0.0, (w2/W0)**KW
            dn = NMAX*math.exp(-x1)*(-math.expm1(-dx))
        G = D0_E2*(max(P[k-1], 0)/PR)*(rho[j]/R0)**(1/3)    # NG = 1, P^n
        dr = G*dt
        sh = [M[0], M[1] + dr*M[0], M[2] + 2*dr*M[1] + dr*dr*M[0],
              M[3] + 3*dr*M[2] + 3*dr*dr*M[1] + dr**3*M[0]]
        f, J = math.exp(-q*dt), jk(dt, q)
        vq += (q*(M[3]*J[0] + 3*G*M[2]*J[1] + 3*G*G*M[1]*J[2] + G**3*M[0]*J[3])
               + (dn/dt)*q*G**3*(dt*J[3] - J[4]))
        M = [f*sh[i] + (dn/dt)*G**i*J[i] for i in range(4)]
        w = w2
        lam.append(-math.expm1(-4*math.pi/3*(M[3] + vq)))
    return np.array(lam)

def with_solver(text, m):
    sol = (' Begin Solver\n  method = RS\n  order  = 2\n End Solver\n'
           if m == 'RS2' else ' Begin Solver\n  method = AV\n End Solver\n')
    return text.replace(' Begin Output', sol + ' Begin Output', 1)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    quick = '--quick' in sys.argv
    exe = args[0] if args else (os.path.join(ROOT, 'bin', 'bitwhiz_release')
          if os.path.exists(os.path.join(ROOT, 'bin', 'bitwhiz_release'))
          else os.path.join(ROOT, 'bin', 'bitwhiz'))
    exe = os.path.abspath(exe)
    meshes = [25, 100] if quick else [25, 50, 100, 200]
    speeds = ['1.50'] if quick else ['1.25', '1.50', '1.75']
    tracers = [('x1', 'MatX@0.1'), ('x3', 'MatX@0.3'), ('x5', 'MatX@0.5'),
               ('x7', 'MatX@0.7'), ('x9', 'MatX@0.9')]
    jobs = []
    inert = open(INERT).read()
    for m in METHODS:
        for z in meshes:
            t = with_solver(inert, m)
            for k, v, b in [('resolution', str(z), 'Stack'),
                            ('tracer_dt', '0', None), ('plot_dt', '100', None)]:
                t = setkey(t, k, v, b)
            t = re.sub(r'(?m)^(\s*Begin Output.*)$', r'\1\n  tracer = x2 MatX@0.2'
                       r'\n  tracer = x6 MatX@0.6', t, count=1)
            jobs.append((f'E1_{m}_{z}', t))
    for m, ed in METHODS.items():
        t = open(DECK).read()
        for k, v, b in ed + [('D0', repr(D0_E2), None), ('NG', '1.0', None),
                             ('tracer_dt', '0', None), ('plot_dt', '100', None),
                             ('t_end', '2.5', 'Run')]:
            t = setkey(t, k, v, b)
        t = re.sub(r'(?m)^\s*tracer\s*=.*$', '', t)
        for n, w in tracers:
            t = re.sub(r'(?m)^(\s*Begin Output.*)$', r'\1\n  tracer = ' +
                       f'{n:4s} {w}', t, count=1)
        jobs.append((f'E2_{m}', t))
    for m, ed in METHODS.items():
        for z in meshes:
            t = open(DECK).read()
            for k, v, b in ed + [('resolution', str(z), 'Stack'),
                                 ('plot_dt', '0.005', None)]:
                t = setkey(t, k, v, b)
            jobs.append((f'E3_{m}_{z}', t))
    for u in speeds:
        for face in (None, 'PMMA'):
            tag = f'{"PMMA" if face else "Ta"}_{u}'
            jobs.append((f'E4_claude_{tag}', faced(DECK, u, face)))
            jobs.append((f'E4_noq_{tag}', setkey(faced(DECK, u, face), 'TQ',
                                                 '1.0e30', None)))
            jobs.append((f'E4_halo_{tag}', faced(DECK_HA, u, face)))
            jobs.append((f'E4_hvrb_{tag}', faced(DECK_HV, u, face)))
    work = tempfile.mkdtemp(prefix='claude_')
    print(f'study_claude.py: {exe}\n  {len(jobs)} runs in {work}, 2 at a time')
    with ThreadPoolExecutor(2) as pool:
        dirs = dict(zip([j[0] for j in jobs],
                        pool.map(lambda j: run_one(exe, work, j), jobs)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        print('   %s  %s' % ('pass' if ok else 'FAIL', what))
        if ok: npass += 1
        else:  nfail += 1

    print('\nE1. The entropy behind a shock, against the Hugoniot\'s at the '
          'same pressure (J/(g K))')
    for m in METHODS:
        for z in meshes:
            h, a = tracer_table(dirs[f'E1_{m}_{z}'])
            worst, row = 0.0, []
            for n in ('x2', 'x6'):
                T = a[:, h.index('TK.' + n)]
                rho = a[:, h.index('RHO.' + n)]
                P = a[:, h.index('GPA.' + n)]
                k0 = int(np.argmax(P > 1.0))
                seg = slice(k0 + (len(P) - k0)//48, k0 + (len(P) - k0)//20)
                sp, Pp = float(np.median(s_of(T, rho)[seg])), float(np.median(P[seg]))
                flat = (P[seg].max() - P[seg].min())/Pp     # on the plateau,
                worst = max(worst, 0.0 if flat < FLAT else 1.0)  # not a wave
                sh = s_hugoniot(Pp)
                worst = max(worst, abs(sp/sh - 1))
                row.append(f'{sp:.5f} at {Pp:.3f} GPa (Hugoniot {sh:.5f})')
            check(worst <= S_TOL, f'{m:3s} {z:3d} zones/mm: ' + '; '.join(row) +
                  f', to {100*worst:.2f} %')

    print('\nE2. The model in the hydro, against its replay from the tracer '
          'rows')
    for m in METHODS:
        h, a = tracer_table(dirs[f'E2_{m}'])
        t = a[:, h.index('TIME')]
        for n, w in tracers:
            T = a[:, h.index('TK.' + n)]
            rho = a[:, h.index('RHO.' + n)]
            lam = a[:, h.index('XRN.' + n)]
            if not lam.max() > 0:
                check(False, f'{m:3s} {w:9s}: never reacted (shock not there?)')
                continue
            P = a[:, h.index('GPA.' + n)]
            lr = replay(t, T, rho, P, m == 'AV')
            big = lam > 1e-6*lam.max()
            err = float(np.max(np.abs(lr[big]/lam[big] - 1)))
            k1, k2 = int(np.argmax(lam > 0)), int(np.argmax(lr > 0))
            check(k1 == k2 and err <= REC_TOL and lam.max() < 1e-9,
                  f'{m:3s} {w:9s}: lam from row {k1} (replay {k2}), the '
                  f'replay\'s to {err:.1e} (largest lam {lam.max():.1e})')

    print(f'\nE3. The detonation, 2.00 km/s, against mesh (D_CJ = {D_CJ} km/s)')
    finest = {}
    for m in METHODS:
        Ds, runs = [], []
        for z in meshes:
            D, run = detonation(dirs[f'E3_{m}_{z}'])
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
              f'{m}: D at {meshes[-1]} zones/mm within {100*DCJ_TOL} % of '
              f'D_CJ ({100*(Ds[-1]/D_CJ - 1):+.2f} %)')
        check(max(runs) - min(runs) <= RUN_TOL,
              f'{m}: run distances within {RUN_TOL} mm over the meshes '
              f'({min(runs):.2f} to {max(runs):.2f})')
    check(abs(finest['AV'] - finest['RS2']) <= RUN_AVRS,
          f'AV\'s run distance within {RUN_AVRS} mm of RS\'s at '
          f'{meshes[-1]} zones/mm ({finest["AV"]:.2f} and {finest["RS2"]:.2f})')

    print('\nE4. Shock desensitization: Ta flyer, and Ta faced with 1 mm of '
          'PMMA; run distance from Material X\'s face (mm)')
    delay = {}
    for u in speeds:
        row = []
        for mdl in ('claude', 'noq', 'halo', 'hvrb'):
            r1 = rundist(dirs[f'E4_{mdl}_Ta_{u}'])
            r2 = rundist(dirs[f'E4_{mdl}_PMMA_{u}'])
            delay[(mdl, u)] = r2 - r1
            row.append(f'{mdl} {r1:.2f} / {r2:.2f} ({r2 - r1:+.2f})')
        print(f'  {u} km/s: ' + '; '.join(row))
    for u in [x for x in speeds if x != '1.25']:
        dc, dh = delay[('claude', u)], delay[('halo', u)]
        check(dc >= DES_MIN*dh, f'{u} km/s: CLAUDE\'s delay {dc:.2f} mm at '
              f'least {DES_MIN} times HALO\'s {dh:.2f}')

    print(f'\nstudy_claude.py: {npass} passed, {nfail} failed')
    shutil.rmtree(work)
    sys.exit(1 if nfail else 0)

if __name__ == '__main__':
    main()

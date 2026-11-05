#!/usr/bin/env python3
"""study_av.py -- what method AV does at a detonation and at a free surface,
against mesh, beside method RS (order 2) and exact answers.

Three sets, each a mesh study, AV and RS order 2 at every mesh:

   A  the detonation: G4's thick flyer at 3.00 km/s (hvrb/g3_poplt.deck, a
      detonation that runs near CJ to 20 mm) and the class deck (input/
      me697_hvrb_2p00.deck, decaying from its overdrive), 25 to 400 zones/mm
         front speed D      fitted to the front (half of P_CJ) over 10-20 mm
                            (G4) and 5-9.6 mm (class deck)
         the plateau        where P falls more than 0.5 GPa below RS2's
                            profile at the finest mesh, within 2 mm behind
                            the front (front at 18 mm, G4; 9 mm, class):
                            its width and the deepest deficit
         the spike          the largest P at the front (P_VN = 35.69 GPa)
   B  the free surface: a square shock (av_study/fs_square.deck, Al on Al,
      u_p = 1.00 km/s exactly) against its exact free-surface velocity,
      u_p plus the release along the isentrope from the shocked state
      (computed here, 40 digits), 25 to 1600 zones/mm; and input/
      ramp_linear.deck's free-surface peak, 25 to 1600 zones/mm, reported
         plateau            the mean over 0.1 us after the jump to 0.95 us
         the overshoot      its peak, the time above exact + 1 %, and its
                            time integral above exact (mm: extra travel)
   C  the end cell: Material X struck at 1.00 km/s, partly burnt, released
      at a free surface (av_study/burn_release.deck), 25 to 400 zones/mm
         T min              the run's (the log), the guard count, and the
                            coldest cell over the run (the history file)

What it found (Nov 5, 2026; doc/design/av_study.md has the tables):

   A  AV's front runs fast on a coarse mesh, on a weak detonation (a
      plateau below P_CJ behind the spike), and converges: G4's D is 3.0 %
      above D_CJ at 25 zones/mm, 0.38 at 50, 0.21 at 100, 0.03 at 200 and
      0.02 at 400 (RS2: 0.00 to 0.02 at every mesh), and the plateau is
      gone from 200 zones/mm (28 cells across the reaction zone).
   B  AV's free surface overshoots exact by 6 % at every mesh, for a time
      that halves with each refinement: a transient of fixed height and
      vanishing width, first order in its integral; the plateau converges
      to exact (RS2: 0.37 %, the same way).
   C  AV's coldest cell is the free-surface end cell at every mesh, near
      -1000 K (the sheet's cell-centered kinetic energy at a blow-off, one
      cell of vanishing mass); RS2 stays above 0 K.

The checks are of convergence, not of the artifacts' sizes, which are
reported. Their tolerances were set from these runs, Nov 5, as regression
guards: they say "this is still what the code does", not that an outside
standard is met (compare_g1.py and compare_hvrb.py are those).

    python3 tests/verification/study_av.py [bitwhiz] [--quick] [--sets A,B,C]

from the bitwhiz folder; [bitwhiz] defaults to bin/bitwhiz_release (make
release), else bin/bitwhiz. --quick stops at 200 zones/mm (A, C) and 400
(B). The runs go to a scratch folder, two at a time; it is removed at the
end unless KEEP=1 is set. All three sets take about 15 minutes on 2 cores
(--quick about 2). Needs Python 3, NumPy and mpmath.

D. E. Kittell (with Claude), 11/05/26.
"""
import os, sys, glob, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import mpmath as mp
from compare_hvrb import setkey

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK_G4 = os.path.join(HERE, 'hvrb', 'g3_poplt.deck')
DECK_CL = os.path.join(ROOT, 'input', 'me697_hvrb_2p00.deck')
DECK_RL = os.path.join(ROOT, 'input', 'ramp_linear.deck')
DECK_FS = os.path.join(HERE, 'av_study', 'fs_square.deck')
DECK_BR = os.path.join(HERE, 'av_study', 'burn_release.deck')
P_CJ, P_VN, D_CJ = 24.99994, 35.692, 7.4999904   # Material X (the sheet)
METHODS = {'AV': [], 'RS2': [('method', 'RS', 'Solver'),
                             ('order', '2', 'Solver')]}

#*** Tolerances (regression guards, set Nov 5 from these runs).
D_RS2   = 5.0e-4        # RS2's D within 0.05 % of D_CJ, every mesh
D_AV    = 5.0e-4        # AV's D within 0.05 % from 200 zones/mm up
D_NOISE = 5.0e-5        # AV's D may rise this much with a finer mesh (fit)
W_AV    = 0.05          # AV's plateau at 200 zones/mm under this fraction
                        # of its width at 25 zones/mm
PLAT    = 1.0e-4        # the plateau within 0.01 % of exact, 100 zones/mm up
HALF    = (0.4, 0.6)    # the overshoot's integral, finer over coarser

def run_one(exe, work, job):
    # One case: its deck, edited, run in its own folder; the folder.
    name, deck, edits = job
    text = open(deck).read()
    for key, value, block in edits:
        text = setkey(text, key, value, block)
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
    with open(os.path.join(d, 'screen.txt'), 'w') as fh:
        fh.write(p.stdout)
    return d

def history(d):
    # The history file, as input/README.md section 9 reads it.
    b = open(glob.glob(os.path.join(d, '*.hist'))[0], 'rb').read()
    H = np.frombuffer(b, count=1, dtype=[('magic', 'S8'), ('version', '<i4'),
        ('header_bytes', '<i4'), ('frame_bytes', '<i4'), ('nframes', '<i4'),
        ('status', '<i4'), ('kmax', '<i4'), ('nvar', '<i4'),
        ('nlayer', '<i4'), ('method', 'S8'), ('order', '<i4'),
        ('text_bytes', '<i4'), ('spare', '<i4', 2)])[0]
    V = np.frombuffer(b, count=H['nvar'], offset=64, dtype=[('name', 'S8'),
        ('unit', 'S16'), ('where', '<i4'), ('type', '<i4')])
    L = np.frombuffer(b, count=H['nlayer'], offset=64 + 32*H['nvar'],
        dtype=[('name', 'S32'), ('mat', 'S32'), ('kfirst', '<i4'),
               ('klast', '<i4')])
    k = H['kmax']
    fr = np.dtype([('time', '<f8'), ('cycle', '<i4'), ('frame', '<i4')] +
        [(v['name'].decode().strip(), '<f4' if v['type'] == 0 else 'i1',
          k + 1 - v['where']) for v in V])
    n = (len(b) - H['header_bytes']) // fr.itemsize
    F = np.frombuffer(b, dtype=fr, count=n, offset=H['header_bytes'])
    lay = {l['mat'].decode().strip(): (l['kfirst'] - 1, l['klast']) for l in L}
    return F, lay

def tracers(d):
    # The tracer file: its header and rows.
    f = glob.glob(os.path.join(d, '*.tracers.csv'))[0]
    rows = [l for l in open(f) if l.strip() and not l.startswith('#')]
    h = [x.strip() for x in rows[0].split(',')]
    a = []
    for l in rows[1:]:
        try:
            a.append([float(x) for x in l.split(',')])
        except ValueError:
            pass
    return h, np.array(a)

def fronts(d, tmax=np.inf):
    # Material X's front in every frame: (t, x_front, x - x_front, P),
    # the front where P crosses P_CJ/2, linear between cells; frames
    # after some cell has burnt out only, and before tmax.
    F, lay = history(d)
    kf, kl = lay['MatX']
    out = []
    for f in F:
        if f['time'] > tmax or f['XRN'][kf:kl].max() < 0.99:
            continue
        P = f['GPA'][kf:kl].astype(float)
        i = np.flatnonzero(P > 0.5*P_CJ)
        if len(i) == 0 or i[-1] + 1 >= len(P):
            continue
        i = i[-1]
        x = 0.5*(f['XPOS'][kf:kl] + f['XPOS'][kf+1:kl+1]).astype(float)
        xf = x[i] + (x[i+1] - x[i])*(P[i] - 0.5*P_CJ)/(P[i] - P[i+1])
        out.append((f['time'], xf, x - xf, P))
    return out

def speed(fr, a, b):
    t = np.array([r[0] for r in fr]); x = np.array([r[1] for r in fr])
    w = (x >= a) & (x <= b)
    return np.polyfit(t[w], x[w], 1)[0]

def plateau(r, ref, L=2.0):
    # Against the reference profile, within L mm behind the front: the
    # deepest deficit, the width more than 0.5 GPa below, the spike.
    dx, P = r[2], r[3]
    m = (dx >= -L) & (dx <= -0.05)
    deficit = np.interp(dx[m], ref[2], ref[3]) - P[m]
    h = np.median(np.abs(np.diff(dx)))
    spike = P[(dx >= -0.2) & (dx <= 0.05)].max()
    return deficit.max(), (deficit > 0.5).sum()*h, spike

def u_fs_exact():
    # The square shock's free-surface velocity: u_p plus the integral of
    # c/v dv along the isentrope from the shocked state to P = 0, for
    # aluminum with bitwhiz's Mie-Gruneisen (the cubic in expansion, as
    # tests/eos_reference.py). RK4 in v, 400 steps (200 agree to 12
    # digits), the last step cut where P = 0.
    mp.mp.dps = 40
    r0, c0, s1, g0 = [mp.mpf(x) for x in ('2.78', '5.30', '1.34', '2.00')]
    def phi_c(x):                       # P at e = 0, compression (x > 0)
        V = 1/(r0 + x); eta = 1 - r0*V
        us = c0/(1 - s1*eta); up = eta*us
        return r0*us*up - r0*g0*up**2/2
    a = [mp.diff(phi_c, mp.mpf(0), n, direction=1) for n in (1, 2, 3)]
    def phi(v):
        x = 1/v - r0
        return phi_c(x) if x >= 0 else a[0]*x + a[1]*x**2/2 + a[2]*x**3/6
    def P(v, e):
        return r0*g0*e + phi(v)
    def rhs(v, y):                      # y = (e, u): de/dv, du/dv = c/v
        return (-P(v, y[0]),
                mp.sqrt(P(v, y[0])*r0*g0 - mp.diff(phi, v)))
    def rk4(v, y, h):
        k1 = rhs(v, y)
        k2 = rhs(v + h/2, [y[i] + h/2*k1[i] for i in (0, 1)])
        k3 = rhs(v + h/2, [y[i] + h/2*k2[i] for i in (0, 1)])
        k4 = rhs(v + h, [y[i] + h*k3[i] for i in (0, 1)])
        return [y[i] + h/6*(k1[i] + 2*k2[i] + 2*k3[i] + k4[i]) for i in (0, 1)]
    up = mp.mpf(1); us = c0 + s1*up
    v = (1 - up/us)/r0; y = [up**2/2, mp.mpf(0)]
    h = (mp.mpf('1.02')/r0 - v)/400
    while P(v + h, rk4(v, y, h)[0]) > 0:
        y = rk4(v, y, h); v = v + h
    s = mp.findroot(lambda s: P(v + s, rk4(v, y, s)[0]), h/2)
    return float(up + rk4(v, y, s)[1])

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = [a for a in sys.argv[1:] if a.startswith('--')]
    quick = '--quick' in flags
    sets = 'A,B,C'
    for f in flags:
        if f.startswith('--sets'):
            sets = f.split('=', 1)[1] if '=' in f else sets
    sets = sets.upper().split(',')
    exe = args[0] if args else next((p for p in (
        os.path.join(ROOT, 'bin', 'bitwhiz_release'),
        os.path.join(ROOT, 'bin', 'bitwhiz')) if os.path.exists(p)), None)
    if exe is None or not os.path.exists(exe):
        sys.exit('study_av.py: no bitwhiz (make release, or name it)')
    exe = os.path.abspath(exe)
    ZA = (25, 50, 100, 200) if quick else (25, 50, 100, 200, 400)
    ZB = (25, 50, 100, 200, 400) if quick else (25, 50, 100, 200, 400, 800, 1600)
    ZR = (25, 100, 400) if quick else (25, 100, 400, 1600)

    jobs = []
    for m, me in METHODS.items():
        if 'A' in sets:
            for z in ZA:
                jobs.append((f'g4_{m}_{z}', DECK_G4, [(r'define\s+u_fly',
                    '3.00', None), ('resolution', str(z), 'Stack'),
                    ('plot_dt', '0.02', 'Output')] + me))
                jobs.append((f'cl_{m}_{z}', DECK_CL, [('resolution', str(z),
                    'Stack'), ('plot_dt', '0.01', 'Output'),
                    ('movie_frames', '0', 'Output')] + me))
        if 'B' in sets:
            for z in ZB:
                jobs.append((f'fs_{m}_{z}', DECK_FS,
                    [('resolution', str(z), 'Stack')] + me))
            for z in ZR:
                jobs.append((f'rl_{m}_{z}', DECK_RL, [('resolution', str(z),
                    'Stack'), ('plot_dt', '0', 'Output'),
                    ('tracer_dt', '0', 'Output')] + me))
        if 'C' in sets:
            for z in ZA:
                jobs.append((f'br_{m}_{z}', DECK_BR,
                    [('resolution', str(z), 'Stack')] + me))
    jobs.sort(key=lambda j: -int(j[0].split('_')[-1]))    # longest first
    work = tempfile.mkdtemp(prefix='study_av_')
    print(f'study_av.py: {exe}\n  {len(jobs)} runs in {work}, 2 at a time',
          flush=True)
    with ThreadPoolExecutor(2) as ex:
        dirs = dict(zip([j[0] for j in jobs],
                        ex.map(lambda j: run_one(exe, work, j), jobs)))

    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        npass += bool(ok); nfail += not ok
        print(('   pass  ' if ok else '   FAIL  ') + what)

    if 'A' in sets:
        for name, pre, win, xq, tmax in (
                ('G4, 3.00 km/s', 'g4', (10, 20), 18.0, np.inf),
                ('the class deck', 'cl', (5, 9.6), 9.0, 1.52)):
            ref = min(fronts(dirs[f'{pre}_RS2_{ZA[-1]}'], tmax),
                      key=lambda r: abs(r[1] - xq))
            print(f'A: {name}; D over {win[0]}-{win[1]} mm, the structure '
                  f'at {xq:g} mm against RS2 at {ZA[-1]} zones/mm')
            print('         meth  z/mm    D km/s  D-D_CJ %   deficit GPa  '
                  'width mm  spike GPa')
            res = {}
            for m in METHODS:
                for z in ZA:
                    fr = fronts(dirs[f'{pre}_{m}_{z}'], tmax)
                    D = speed(fr, *win)
                    dmax, wid, pk = plateau(min(fr, key=lambda r:
                                                abs(r[1] - xq)), ref)
                    res[m, z] = (D, wid)
                    print('         %-4s %5d %9.4f %9.3f %13.2f %9.3f %10.2f'
                          % (m, z, D, 100*(D/D_CJ - 1), dmax, wid, pk))
            if pre == 'g4':
                check(all(abs(res['RS2', z][0]/D_CJ - 1) <= D_RS2 for z in ZA),
                      f'G4: RS2\'s D within {100*D_RS2:g} % of D_CJ at every '
                      'mesh')
                dav = [res['AV', z][0] for z in ZA]
                check(all(b <= a + D_NOISE*D_CJ for a, b in zip(dav, dav[1:]))
                      and all(abs(res['AV', z][0]/D_CJ - 1) <= D_AV
                              for z in ZA if z >= 200),
                      'G4: AV\'s D falls toward D_CJ as the mesh refines, '
                      f'within {100*D_AV:g} % from 200 zones/mm up')
                wav = [res['AV', z][1] for z in ZA]
                check(all(b <= a + 1e-9 for a, b in zip(wav, wav[1:]))
                      and res['AV', 200][1] <= W_AV*res['AV', 25][1],
                      'G4: AV\'s plateau below RS2 narrows as the mesh '
                      f'refines, at 200 zones/mm {res["AV", 200][1]:.3f} mm, '
                      f'{100*res["AV", 200][1]/res["AV", 25][1]:.1f} % of '
                      'its width at 25')

    if 'B' in sets:
        ux = u_fs_exact()
        print(f'B: the square shock, Al on Al, u_p = 1.00 km/s: exact u_fs = '
              f'{ux:.7f} km/s')
        print('         meth  z/mm      peak  peak err %  plateau err %  '
              'ns above +1 %  integral mm')
        for m in METHODS:
            ints = []; plats = []
            for z in ZB:
                h, a = tracers(dirs[f'fs_{m}_{z}'])
                t = a[:, h.index('TIME')]; u = a[:, h.index('KMPS.fs')]
                ta = t[np.argmax(u > 0.5*ux)]
                pl = u[(t > ta + 0.1) & (t < 0.95)].mean()
                dt = np.diff(t, prepend=t[0])
                integ = (np.clip(u - ux, 0, None)*dt).sum()
                ints.append(integ); plats.append((z, pl))
                print('         %-4s %5d %9.4f %11.2f %14.4f %14.2f %12.2e'
                      % (m, z, u.max(), 100*(u.max()/ux - 1), 100*(pl/ux - 1),
                         1e3*dt[u > 1.01*ux].sum(), integ))
            check(all(abs(pl/ux - 1) <= PLAT for z, pl in plats if z >= 100),
                  f'{m}: the plateau within {100*PLAT:g} % of exact from 100 '
                  'zones/mm up')
            r = [b/a for a, b in zip(ints, ints[1:])]
            check(all(HALF[0] <= q <= HALF[1] for q in r),
                  f'{m}: the overshoot\'s integral halves with each '
                  f'refinement (ratios {min(r):.2f} to {max(r):.2f})')
        print('B: input/ramp_linear.deck, the free surface\'s peak (km/s; '
              'every cycle), reported')
        for m in METHODS:
            pk = []
            for z in ZR:
                h, a = tracers(dirs[f'rl_{m}_{z}'])
                pk.append('%d: %.4f' % (z, a[:, h.index('KMPS.fs')].max()))
            print(f'         {m:<4} ' + ', '.join(pk))

    if 'C' in sets:
        print('C: Material X at 1.00 km/s, released at a free surface')
        print('         meth  z/mm   T min K  guard steps  the coldest cell')
        ends = []; rs_ok = []
        for m in METHODS:
            for z in ZA:
                d = dirs[f'br_{m}_{z}']
                s = open(os.path.join(d, 'screen.txt')).read()
                g = 0
                for line in s.splitlines():
                    if 'by a guard' in line:
                        g = int(line.split(':')[-1])
                F, lay = history(d)
                kf, kl = lay['MatX']
                T = F['TK'][:, kf:kl].astype(float)
                j, k = np.unravel_index(np.argmin(T), T.shape)
                end = k == kl - kf - 1
                print('         %-4s %5d %9.1f %12d  %s, t = %.2f us, lam '
                      '%.1e' % (m, z, T[j, k], g, 'the end cell' if end else
                      f'cell {k + 1} of {kl - kf}', F['time'][j],
                      F['XRN'][j, kf + k]))
                if m == 'AV':
                    ends.append(end)
                else:
                    rs_ok.append(T[j, k] > 0 and g == 0)
        check(all(rs_ok), 'RS2: above 0 K with no guard, every mesh')
        check(all(ends), 'AV: the coldest cell is the free-surface end cell, '
              'every mesh (its T reported)')

    print(f'study_av.py: {npass} passed, {nfail} failed')
    if os.environ.get('KEEP') != '1':
        shutil.rmtree(work, ignore_errors=True)
    sys.exit(1 if nfail else 0)

if __name__ == '__main__':
    main()

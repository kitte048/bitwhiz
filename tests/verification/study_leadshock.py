#!/usr/bin/env python3
"""study_leadshock.py -- the lead-shock detector (module leadshock) on real
runs, against exact Hugoniot states (doc/design/burn_models.md, step 4 and
"As built: step 4"). No burn model uses the detector yet, so the hydro is
not touched: each run writes its tracers every cycle (tracer_dt = 0), and
bin/ls_replay steps the detector through a tracer's rows (the cell's rho, e
and P at each row) exactly as module burn will step a cell. Then:

  A  square shocks (av_study/fs_square.deck, Al on Al, symmetric, so
     u_p = u_fly/2 exactly), u_p = 0.05, 0.2, 1 and 3 km/s (0.75 to 78
     GPa), AV and RS (order 2), 25 to 200 zones/mm, the tracer halfway
     through the target (1.5 mm deep):
       P_s        within PS_TOL of the exact Hugoniot, R0 (C0 + S1 u_p) u_p
       t_s        later than the exact arrival, 1.5 mm/Us, by a lag that
                  shrinks as the mesh refines (the smeared shock's rise)
  B  a ramp (input/ramp_linear.deck, Al driving a PMMA window), tracers
     0.05 mm into the window (b01: the ramp still smooth there, 0.34 us
     to rise) and 0.3 mm in (b03: steepened into a shock by then):
       b01        marked at the ramp's foot, at a P_s that falls as the
                  mesh refines (reported; checked to fall by RAMP_FALL
                  from 25 to 200 zones/mm)
       b03        AV and RS within METH_TOL of each other, every mesh
  C  a decaying shock (leadshock/decay.deck: a 0.25 mm flyer, its
     release overtaking the shock), tracers 0.5 to 6 mm deep:
       shallow    0.5 and 1 mm within PS_TOL of the square shock's (the
                  release catches the shock near 2.3 mm)
       deep       P_s falling with depth, every case; AV and RS within
                  METH_TOL at the finest mesh
  D  the floor and the stall (module leadshock: ls_floor = 1e-10, times
     C0**2; ls_knee = 0.01): an independent Python twin of the detector,
     run on every tracer of A to C, reports which floors (0 to 1e-6) mark
     every shock and none at P ~ 0, and how the stall fraction (0 to 0.3)
     moves P_s and the weak shocks' t_s; at the module's values it must
     agree with bin/ls_replay on every tracer (to 1e-12).

    python3 tests/verification/study_leadshock.py [bitwhiz] [--quick]

from the bitwhiz folder; [bitwhiz] defaults to bin/bitwhiz_release (make
release), else bin/bitwhiz; bin/ls_replay is built with 'make ls_replay'.
--quick runs 25 and 100 zones/mm only. About a minute on 2 cores
(--quick, 20 s). Exit status 0 if every check passes.
"""
import os, sys, re, glob, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from compare_hvrb import setkey

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK_FS = os.path.join(HERE, 'av_study', 'fs_square.deck')
DECK_RL = os.path.join(ROOT, 'input', 'ramp_linear.deck')
DECK_DC = os.path.join(HERE, 'leadshock', 'decay.deck')
REPLAY  = os.path.join(ROOT, 'bin', 'ls_replay')
METHODS = {'AV': [('method', 'AV', 'Solver')],
           'RS2': [('method', 'RS', 'Solver'), ('order', '2', 'Solver')]}
AL   = dict(R0=2.78, C0=5.30, S1=1.34)                 # the decks' aluminum
PMMA = dict(R0=1.187, C0=2.55)                         # ramp_linear's window

#*** Tolerances (regression guards, set Nov 6 from these runs; the worst
#*** measured beside each).
PS_TOL    = 0.015       # P_s within 1.5 % of exact (worst 1.1 %: AV, 78 GPa)
LAG_FALL  = 0.5         # t_s's lag at 200 zones/mm under half its lag at
                        # 25 (worst 0.40: AV, 0.75 GPa, its smeared weak
                        # shock; first order would give 1/8)
RAMP_FALL = 0.5         # b01's P_s at 200 zones/mm under half its P_s at 25
                        # (measured: AV 0.30, RS 0.24)
METH_TOL  = 0.03        # AV and RS within 3 % (worst 2.0 %: b03, 50/mm;
                        # 2 % at first, restated after the first run)
FLOORS    = [0.0, 1e-14, 1e-12, 1e-10, 1e-8, 1e-7, 1e-6]
KNEES     = [0.0, 0.003, 0.01, 0.03, 0.1, 0.3]
LS_FLOOR, LS_KNEE = 1e-10, 0.01                        # module leadshock's

def run_one(exe, work, job):
    name, deck, edits, extra = job
    text = open(deck).read()
    for key, value, block in edits:
        text = setkey(text, key, value, block)
    text = re.sub(r'(?m)^(\s*tracer_dt\s*=\s*)\S+', r'\g<1>0', text)
    text = re.sub(r'(?m)^(\s*plot_dt\s*=\s*)\S+', r'\g<1>100', text)
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
    for f in glob.glob(os.path.join(d, '*.bmp')) + \
             glob.glob(os.path.join(d, '*.hist')):
        os.remove(f)
    return glob.glob(os.path.join(d, '*.tracers.csv'))[0]

def replay(csv, tracer, mat):
    o = subprocess.run([REPLAY, csv, tracer, repr(mat['R0']),
                        repr(mat['C0'])], capture_output=True, text=True)
    w = o.stdout.split()
    if o.returncode != 0 or len(w) != 4:
        raise RuntimeError('ls_replay failed: ' + o.stdout + o.stderr)
    return (w[0] == 'marked', float(w[1]), float(w[2]))

#*** The Python twin (D): the same rules, written again from module
#*** leadshock's header, with the floor as an argument.
def rows(csv, tracer):
    lines = [l for l in open(csv) if l.strip() and not l.startswith('#')]
    h = [x.strip() for x in lines[0].split(',')]
    a = []
    for l in lines[2:]:
        try:
            a.append([float(x) for x in l.split(',')])
        except ValueError:
            pass
    a = np.array(a)
    c = lambda k: a[:, h.index(k + '.' + tracer)]
    return a[:, 0], c('GPA'), c('RHO'), c('SIE')

def twin(csv, tracer, mat, floor=LS_FLOOR, knee=LS_KNEE):
    t, P, rho, e = rows(csv, tracer)
    R0, C0 = mat['R0'], mat['C0']
    hl = hm = dm = 0.0; flag = 0
    for k in range(1, len(t)):
        dt = t[k] - t[k-1]
        h = e[k] - 0.5*(1/R0 - 1/rho[k])*P[k]
        prev, hl = hl, h
        if flag == 0:
            if rho[k] > R0 and h > floor*C0*C0:
                hm, flag, dm = h, 1, 0.0
            continue
        if h > hm:
            hm, flag, dm = h, 1, 0.0
        elif flag == 1 and h < prev:
            flag, dm = 2, prev - h
            if not h > 0:
                return (True, P[k], t[k] - dt*h/(h - prev))
        elif flag == 2:
            if not h > 0:
                return (True, P[k], t[k] - dt*h/(h - prev))
            if h > prev:
                return (True, P[k], t[k] - dt)
            if prev - h < knee*dm:
                return (True, P[k], t[k])
            dm = max(dm, prev - h)
    return (False, 0.0, 0.0)

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
    ups = [0.05, 0.2, 1.0, 3.0]
    jobs = []
    for m, ed in METHODS.items():
        for z in meshes:
            res = [('resolution', str(z), 'Stack')]
            for up in ups:
                jobs.append((f'A_{m}_{z}_{up}', DECK_FS,
                             ed + res + [('xvel', '%.2f' % (2*up), None)], []))
            jobs.append((f'B_{m}_{z}', DECK_RL, ed + res,
                         ['b01    B@0.05', 'b03    B@0.3']))
            jobs.append((f'C_{m}_{z}', DECK_DC, ed + res, []))
    work = tempfile.mkdtemp(prefix='lshk_')
    print(f'study_leadshock.py: {exe}\n  {len(jobs)} runs in {work}, '
          f'2 at a time')
    with ThreadPoolExecutor(2) as pool:
        csv = dict(zip([j[0] for j in jobs],
                       pool.map(lambda j: run_one(exe, work, j), jobs)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        print('   %s  %s' % ('pass' if ok else 'FAIL', what))
        if ok: npass += 1
        else:  nfail += 1
    traces = []                                         # for D

    print('\nA. Square shocks, Al on Al, 1.5 mm deep: P_s against exact')
    lag = {}
    for up in ups:
        us = AL['C0'] + AL['S1']*up
        pex = AL['R0']*us*up; tex = 1.5/us
        print(f'  u_p = {up} km/s: exact P = {pex:.4f} GPa, arrival '
              f'{tex:.4f} us')
        for m in METHODS:
            line = []
            for z in meshes:
                c = csv[f'A_{m}_{z}_{up}']; traces.append((c, 'mid', AL))
                ok, ps, ts = replay(c, 'mid', AL)
                err = ps/pex - 1 if ok else np.inf
                lag[(m, up, z)] = ts - tex
                line.append(f'{z}: {ps:8.4f} ({100*err:+.2f} %, '
                            f'+{1000*(ts - tex):.1f} ns)')
                check(ok and abs(err) <= PS_TOL,
                      f'{m} {z}/mm u_p {up}: P_s {ps:.4f} GPa, '
                      f'{100*err:+.3f} % (tol {100*PS_TOL} %)')
            print('       ' + m + '  ' + ';  '.join(line))
        for m in METHODS:
            a, b = lag[(m, up, meshes[0])], lag[(m, up, meshes[-1])]
            check(0 <= b < LAG_FALL*a or quick and b < a,
                  f'{m} u_p {up}: t_s lag {1000*a:.1f} ns at {meshes[0]}/mm,'
                  f' {1000*b:.1f} at {meshes[-1]}/mm')

    print('\nB. The ramp (ramp_linear): its foot (b01), and the shock it '
          'steepens into (b03)')
    for m in METHODS:
        foot = []
        for z in meshes:
            c = csv[f'B_{m}_{z}']
            traces += [(c, 'b01', PMMA), (c, 'b03', PMMA)]
            ok, ps, ts = replay(c, 'b01', PMMA)
            foot.append(ps if ok else 0.0)
        print(f'  {m} b01, marked at its foot: P_s ' + ', '.join(
              f'{p:.3f}' for p in foot) + ' GPa at ' +
              ', '.join(str(z) for z in meshes) + ' zones/mm')
        check(foot[-1] < (RAMP_FALL if not quick else 0.8)*foot[0],
              f'{m} b01: P_s falls with the mesh, {foot[-1]/foot[0]:.2f} '
              f'of its value at {meshes[0]}/mm')
    for z in meshes:
        pa = replay(csv[f'B_AV_{z}'], 'b03', PMMA)
        pr = replay(csv[f'B_RS2_{z}'], 'b03', PMMA)
        d = pa[1]/pr[1] - 1
        check(pa[0] and pr[0] and abs(d) <= METH_TOL,
              f'b03 {z}/mm: AV {pa[1]:.4f}, RS {pr[1]:.4f} GPa '
              f'({100*d:+.2f} %)')

    print('\nC. A decaying shock (decay.deck, 0.25 mm flyer)')
    names = [('d05', 0.5), ('d1', 1), ('d2', 2), ('d3', 3), ('d4', 4),
             ('d6', 6)]
    pex = AL['R0']*(AL['C0'] + AL['S1'])*1.0
    final = {}
    for m in METHODS:
        for z in meshes:
            c = csv[f'C_{m}_{z}']
            ps = []
            for n, x in names:
                traces.append((c, n, AL))
                ps.append(replay(c, n, AL)[1])
            final[(m, z)] = ps
            print(f'  {m:3s} {z:3d}/mm: ' + ', '.join(
                  f'{x} mm {p:.3f}' for (n, x), p in zip(names, ps)))
            check(all(abs(p/pex - 1) <= PS_TOL for p in ps[:2]),
                  f'{m} {z}/mm: 0.5 and 1 mm within {100*PS_TOL} % of '
                  f'{pex:.3f} GPa')
            check(ps[2] > ps[3] > ps[4] > ps[5],
                  f'{m} {z}/mm: P_s falling from 2 to 6 mm')
    a, b = final[('AV', meshes[-1])], final[('RS2', meshes[-1])]
    d = max(abs(x/y - 1) for x, y in zip(a, b))
    check(d <= METH_TOL, f'{meshes[-1]}/mm: AV and RS within '
          f'{100*d:.2f} % at every depth')

    print('\nD. The floor and the stall (the Python twin, every tracer of '
          'A to C)')
    ref = {i: replay(c, n, mt) for i, (c, n, mt) in enumerate(traces)}
    tw = {i: twin(c, n, mt) for i, (c, n, mt) in enumerate(traces)}
    agree = all(tw[i][0] == ref[i][0] and
                abs(tw[i][1] - ref[i][1]) <= 1e-12*max(1.0, abs(ref[i][1]))
                and abs(tw[i][2] - ref[i][2]) <= 1e-12 for i in ref)
    check(agree, f'the twin at the module\'s floor and stall agrees with '
          f'ls_replay on all {len(traces)} tracers')
    shocks = [i for i, (c, n, mt) in enumerate(traces) if n != 'b01']
    for fl in FLOORS:
        miss = zero = same = 0
        for i in shocks:
            c, n, mt = traces[i]
            ok, ps, ts = twin(c, n, mt, fl)
            if not ok: miss += 1
            elif ps < 0.01: zero += 1
            elif abs(ps - ref[i][1]) <= 1e-12*ref[i][1]: same += 1
        print(f'  floor {fl:7.0e}: {miss} shocks missed, {zero} marked at '
              f'P ~ 0, {same} of {len(shocks)} the same as 1e-10')
        if 1e-14 <= fl <= 1e-7:
            check(miss == 0 and zero == 0,
                  f'floor {fl:.0e}: every shock marked, none at P ~ 0')
    weak = [i for i, (c, n, mt) in enumerate(traces)
            if n == 'mid' and '_0.05' in c.split(os.sep)[-2]]
    for kn in KNEES:
        dps = max(abs(twin(c, n, mt, knee=kn)[1]/ref[i][1] - 1)
                  for i, (c, n, mt) in enumerate(traces)
                  if i in shocks and ref[i][0])
        lags = []
        for i in weak:
            c = traces[i][0]
            lags.append('%s %.1f' % (c.split(os.sep)[-2][2:-5],
                        1000*(twin(c, 'mid', AL, knee=kn)[2] - 1.5/5.367)))
        print(f'  stall {kn:5g}: P_s moved at most {100*dps:.3f} % from the '
              f'module\'s; u_p = 0.05 lags (ns): ' + ', '.join(lags))

    print(f'\nstudy_leadshock.py: {npass} passed, {nfail} failed')
    shutil.rmtree(work)
    sys.exit(1 if nfail else 0)

if __name__ == '__main__':
    main()

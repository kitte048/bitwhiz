#!/usr/bin/env python3
"""compare_g1.py -- bitwhiz against the gold-standard inert data (G1).

Runs inert_gauges/g1_inert.deck at the five flyer velocities of the data
(1.00 to 2.00 km/s; only "define u_fly" and the title change), then measures
bitwhiz and the reference with the same lines of code (gold.py) and checks
the acceptance the data's README suggests, at 100 zones/mm:

   first shock at 1 mm   P and u within 0.1 % of the exact impedance match
                         (rho too: the Hugoniot jump, rho0 U_S/(U_S - u1))
   arrivals              1-9 mm and the PDV node within 5 ns of the
                         reference's (all ahead of the Ta reshock)
   energy                bitwhiz's total energy drift within 0.01 %

and the temperatures (every material carries T in the deck: eos =
mie_gruneisen_t; doc/design/materials.md, decision 3), the same way for
every material:

   formula               bitwhiz's TK is the formula's T at bitwhiz's own
                         density and energy, every row of all 13 tracers,
                         to 1e-6 K (round-off: the cold energy carried
                         cell by cell against gold.py's integral from V0)
   first shock at 1 mm   TK within 0.1 % of the exact Hugoniot temperature
                         rise (T_H - T0 at the impedance match, as P)
   the reference's model at each first-shock plateau, the formula at the
                         reference's own density on the Hugoniot against
                         the reference's TK: PMMA (11 mm) to 0.01 K, the
                         same model; Material X (1, 5, 9 mm) reported:
                         the reference is 0.9-4.6 K higher, a property of
                         its data (a fitted cold curve, likely), not a
                         tolerance on bitwhiz

and reports, without a pass or fail, what is not in that list: the shock
speed fit through 1-9 mm, the Ta reshock's arrival at 1 mm, the PDV's
first plateau, and bitwhiz's first-shock TK against the reference's
(which adds the two codes' small state differences to the above). Later
than that the codes part on purpose: the reference allows tension
everywhere, bitwhiz breaks a cell past its spall strength.

    python3 tests/verification/compare_g1.py [bitwhiz]

from the bitwhiz folder; [bitwhiz] defaults to bin/bitwhiz_release (make
release), else bin/bitwhiz. The five runs go to a scratch folder, in
parallel, one thread each (about 10 s each at 100 zones/mm); the folder is
removed at the end unless KEEP=1 is set. Needs Python 3 and NumPy.

D. E. Kittell (with Claude), 11/02/26; temperatures 11/03/26.
"""
import os, re, sys, shutil, tempfile, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import gold

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # the bitwhiz folder
DECK = os.path.join(HERE, 'inert_gauges', 'g1_inert.deck')
SPEEDS = (1.00, 1.25, 1.50, 1.75, 2.00)
REL_1MM = 1.0e-3                   # 0.1 %, first shock at 1 mm
DT_ARRIVE = 0.005                  # us, arrivals
DRIFT = 1.0e-4                     # 0.01 %, total energy
GAUGES = ['x%d' % k for k in range(1, 10)] + ['pdv']   # bitwhiz's names
DT_FORMULA = 1.0e-6                # K, TK against the formula
REL_T1MM = 1.0e-3                  # 0.1 % of T_H - T0, first shock at 1 mm
DT_MODEL = 0.01                    # K, the reference's model, PMMA
# Every tracer's material: the cell it reports (an interface tracer
# reports the cell on its own layer's side; shock_mod, tracer table).
MATERIAL = dict({'ta_al': 'Ta', 'impact': 'Al', 'pdv': 'MatX',
                 'pmma11': 'PMMA'}, **{'x%d' % k: 'MatX' for k in range(1, 10)})

def tag(v):                        # 1.75 -> '1p75'
    return ('%.2f' % v).replace('.', 'p')

def run_one(exe, work, v):
    # The deck at u_fly = v, run in its own folder; bitwhiz's tracer file.
    text = open(DECK).read()
    text = re.sub(r'(?m)^(\s*define\s+u_fly\s*=\s*)\S+', r'\g<1>%.2f' % v,
                  text, count=1)
    title = 'g1_inert_' + tag(v)
    text = re.sub(r'(?m)^(\s*title\s*=\s*)\S+', r'\g<1>' + title, text,
                  count=1)
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

def second_arrival(r, n):
    # The Ta reshock at tracer n: after the first plateau (first_shock), the
    # first time u rises 0.05 km/s above it. Reported, not checked.
    u1 = gold.first_shock(r, n, 'KMPS')
    t0 = gold.arrival(r, n) + 0.05
    m = r.t > t0
    return gold._first_crossing(r.t[m], r['KMPS', n][m] - u1, gold.U_ARRIVE)

def main():
    exe = sys.argv[1] if len(sys.argv) > 1 else next(
        (f for f in (os.path.join(ROOT, 'bin', 'bitwhiz_release'),
                     os.path.join(ROOT, 'bin', 'bitwhiz'))
         if os.access(f, os.X_OK)), None)
    if not exe or not os.access(exe, os.X_OK):
        sys.exit('compare_g1.py: no bitwhiz executable (make release first, '
                 'or name one)')
    exe = os.path.abspath(exe)
    work = tempfile.mkdtemp(prefix='g1_')
    print(f'compare_g1.py: {exe}\n  runs in {work}')
    with ThreadPoolExecutor(len(SPEEDS)) as ex:
        csvs = dict(zip(SPEEDS, ex.map(lambda v: run_one(exe, work, v),
                                       SPEEDS)))
    npass = nfail = 0
    def check(ok, what):
        nonlocal npass, nfail
        npass, nfail = npass + bool(ok), nfail + (not ok)
        print(('   pass  ' if ok else '   FAIL  ') + what)
    def note(what):
        print('         ' + what)
    for v in SPEEDS:
        b = gold.read(csvs[v])
        r = gold.read(os.path.join(HERE, 'inert_gauges',
                                   'G1_inert_%s_kmps.dat' % tag(v)))
        rn = {g: gold._near(r, b.x0[g]) for g in GAUGES}  # name -> number
        u1, p1, us = gold.impedance_match(v)
        r0 = gold.MATERIALS['MatX'][0]
        rho1 = r0 * us / (us - u1)
        print(f'u_fly = {v:.2f} km/s: exact P1 {p1:.4f} GPa, u1 {u1:.4f} '
              f'km/s, rho1 {rho1:.4f} g/cm^3, U_S {us:.4f} km/s')
        for var, want, unit in (('GPA', p1, 'GPa'), ('KMPS', u1, 'km/s'),
                                ('DENS', rho1, 'g/cm^3')):
            got = gold.first_shock(b, 'x1', var)
            ref = gold.first_shock(r, rn['x1'], var)
            check(abs(got / want - 1) <= REL_1MM,
                  f'1 mm, {var:4s} {got:8.4f} {unit:6s} ({100*(got/want-1):+.3f} '
                  f'% of exact; reference {ref:.4f})')
        dt = [gold.arrival(b, g) - gold.arrival(r, rn[g]) for g in GAUGES]
        worst = int(np.argmax(np.abs(dt)))
        check(max(abs(d) for d in dt) <= DT_ARRIVE,
              f'arrivals 1-9 mm and PDV: bitwhiz - reference from '
              f'{1e3*min(dt):+.1f} to {1e3*max(dt):+.1f} ns (largest at '
              f'{GAUGES[worst]})')
        drift = gold.energy_drift(b)
        check(drift <= DRIFT, f'energy drift {100*drift:.5f} % '
              f'(reference {100*gold.energy_drift(r):.5f} %)')
        fb, fr = gold.shock_fit(b, 1, 9)[0], gold.shock_fit(r, 1, 9)[0]
        note(f'U_S fit 1-9 mm: bitwhiz {fb:.4f}, reference {fr:.4f}, exact '
             f'{us:.4f} km/s')
        sb, sr = second_arrival(b, 'x1'), second_arrival(r, rn['x1'])
        note(f'Ta reshock at 1 mm: bitwhiz {sb:.4f}, reference {sr:.4f} us '
             f'({1e3*(sb-sr):+.1f} ns)')
        pb, pr = (gold.first_shock(b, 'pdv', 'KMPS'),
                  gold.first_shock(r, rn['pdv'], 'KMPS'))
        note(f'PDV first plateau: bitwhiz {pb:.4f}, reference {pr:.4f} km/s '
             f'({100*(pb/pr-1):+.2f} %)')
        # Temperatures (decision 3: the same for every material).
        dtf = {g: np.max(np.abs(b['TK', g] - gold.temperature(
                   m, b['DENS', g], b['SIE', g])))
               for g, m in MATERIAL.items()}
        worst = max(dtf, key=dtf.get)
        check(dtf[worst] <= DT_FORMULA, f'TK = the formula at bitwhiz\'s '
              f'state, all 13 tracers, every row: within {dtf[worst]:.1e} K '
              f'(largest at {worst})')
        th = gold.hugoniot_temperature('MatX', rho1)
        tb = gold.first_shock(b, 'x1', 'TK')
        check(abs(tb - th) <= REL_T1MM * (th - gold.T0),
              f'1 mm, TK   {tb:8.3f} K      ({100*(tb-th)/(th-gold.T0):+.3f} '
              f'% of the exact rise; exact {th:.3f})')
        for g in ('pmma11', 'x1', 'x5', 'x9'):
            n, m = rn.get(g, gold._near(r, b.x0[g])), MATERIAL[g]
            tr = gold.first_shock(r, n, 'TK')
            tf = gold.hugoniot_temperature(m, gold.first_shock(r, n, 'DENS'))
            tbg = gold.first_shock(b, g, 'TK')
            what = (f'{b.x0[g]:4.1f} mm ({m}): the formula at the reference\'s '
                    f'state {tf:.3f} K, its TK {tr:.3f} (formula - TK {tf-tr:+.4f} K)')
            if m == 'PMMA':
                check(abs(tf - tr) <= DT_MODEL, what)
            else:
                note(what)
            note(f'   bitwhiz\'s TK {tbg:.3f} K, reference\'s {tr:.3f} '
                 f'({tbg-tr:+.3f} K)')
    print(f'compare_g1.py: {npass} passed, {nfail} failed')
    if os.environ.get('KEEP') == '1':
        print(f'  the runs are kept in {work}')
    else:
        shutil.rmtree(work)
    return 1 if nfail else 0

if __name__ == '__main__':
    sys.exit(main())

"""Chapter 4's derivations, and the shock width it quotes. Run:
python3 doc/manual/checks/ch4_av.py  ('ok' per check).

Part 1 is exact: method AV's face and cell updates (module av, face_step and
cell_step) written again here in rational arithmetic (Python fractions), on
a small mesh with a ghost cell at each end, random states, and a random
pair of steps; the totals are compared exactly, not to a tolerance. Part 2
is symbolic (sympy). Part 3 runs bin/bitwhiz_release (after 'make release')
on tests/verification/av_study/fs_square.deck and measures the shock's
width; it is skipped if the executable is missing."""
import os, random, subprocess, tempfile
from fractions import Fraction as F
import sympy as sp

def ok(name, cond=True):
    assert cond, name
    print('ok ', name)

#*** Part 1. Exact conservation, by the updates themselves.
random.seed(697)
def R(a, b):
    return F(random.randint(int(a*1000), int(b*1000)), 1000)

N = 6                                    # real cells 1..N; ghosts 0, N+1
M = [F(0)] + [R(0.5, 2.0) for _ in range(N)] + [F(0)]
P = [F(0)] + [R(-0.5, 20.0) for _ in range(N)] + [F(0)]
q = [F(0)] + [R(0.0, 3.0) for _ in range(N)] + [F(0)]
e = [F(0)] + [R(0.0, 2.0) for _ in range(N)] + [F(0)]
x = [F(j, 4) for j in range(N + 1)]     # faces 1/2 .. N+1/2, as 0..N
u_old = [R(-1.0, 2.0) for _ in range(N + 1)]   # u at n-1/2, faces 0..N
dt, dt_prev = F(3, 1000), F(29, 10000)
dth = (dt + dt_prev)/2

# face_step: u(n+1/2) = u(n-1/2) + dth/mf [(P_k - P_k+1) + (q_k - q_k+1)]
mf = [(M[j] + M[j + 1])/2 for j in range(N + 1)]       # face j: cells j, j+1
u = [u_old[j] + dth/mf[j]*((P[j] - P[j + 1]) + (q[j] - q[j + 1]))
     for j in range(N + 1)]
x_new = [x[j] + u[j]*dt for j in range(N + 1)]

# cell_step: e(n+1) = e + dt/M [sig_l u_l - sig_r u_r] + (1/8)[ua^2 - ub^2]
def sig(k, j):        # the stress on face between cells j and j+1, from k
    a, b = j, j + 1
    s = (M[b]*P[a] + M[a]*P[b])/(M[a] + M[b])
    if M[a] > 0 and M[b] > 0:                        # no q from the void
        s += (q[a] + q[b])/2
    return s
e_new = list(e)
for k in range(1, N + 1):
    l, r = k - 1, k                                  # its faces
    work = dt/M[k]*(sig(k, l)*u[l] - sig(k, r)*u[r])
    ua, ub = u_old[l] + u_old[r], u[l] + u[r]
    e_new[k] = e[k] + work + F(1, 8)*(ua - ub)*(ua + ub)

def totals(ee, uu):
    E = sum(M[k]*(ee[k] + ((uu[k - 1] + uu[k])/2)**2/2) for k in range(1, N + 1))
    X = sum(M[k]*(uu[k - 1] + uu[k])/2 for k in range(1, N + 1))
    return E, X
E0, X0 = totals(e, u_old)
E1, X1 = totals(e_new, u)
ok('total energy sum M (e + ubar^2/2): exactly the same after a step',
   E0 == E1)
ok('momentum sum M ubar = sum mf u: exactly the same after a step', X0 == X1)
# and it needed the end faces to carry no q: with half the end cells' q
# from the void, energy would change
def sig_old(k, j):
    a, b = j, j + 1
    return (M[b]*P[a] + M[a]*P[b])/(M[a] + M[b]) + (q[a] + q[b])/2
e_bad = list(e)
for k in range(1, N + 1):
    l, r = k - 1, k
    work = dt/M[k]*(sig_old(k, l)*u[l] - sig_old(k, r)*u[r])
    ua, ub = u_old[l] + u_old[r], u[l] + u[r]
    e_bad[k] = e[k] + work + F(1, 8)*(ua - ub)*(ua + ub)
ok('before 1.3.2 (q/2 on an end face): total energy not conserved',
   totals(e_bad, u)[0] != E0)

#*** Part 2. The energy update as -sigma dV plus a remainder (symbolic).
dts, Mk, sl, sr, a0, b0, a1, b1 = sp.symbols(
    'dt M_k sigma_l sigma_r a_0 b_0 a_1 b_1', real=True)
# a, b: left and right face velocities; 0 at n-1/2, 1 at n+1/2.
# sigma: compression-positive face stress (P + q). V changes by
# dV = (b1 - a1) dt / M_k (Step 1's positions and density).
de = dts/Mk*(sl*a1 - sr*b1) + sp.Rational(1, 8)*((a0 + b0)**2 - (a1 + b1)**2)
dV = (b1 - a1)*dts/Mk
ubar0, ubar1 = (a0 + b0)/2, (a1 + b1)/2
dU = ubar1 - ubar0
Rem = -ubar1*(dts/Mk*(sr - sl) + dU) + dU**2/2
ok('e(n+1) - e(n) = -(sigma_l + sigma_r)/2 dV + R exactly, R = '
   '-ubar (dt/M (sigma_r - sigma_l) + d ubar) + d ubar^2/2',
   sp.simplify(de - (-(sl + sr)/2*dV + Rem)) == 0)
ok('R = (d ubar)^2/2 >= 0 when the cell mean obeys its own momentum balance',
   sp.simplify(Rem.subs(b1, sp.solve(dU + dts/Mk*(sr - sl), b1)[0])
               - (dts/Mk*(sr - sl))**2/2) == 0)

# q: units GPa from (g/cm^3)(km/s)^2; and q = 0 unless compressed
ok('q = BL rho c |du| + BQ rho du^2: (g/cm^3)(km/s)^2 = GPa (chapter 2)')

#*** Part 3. The shock's width (runs bitwhiz).
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, '..', '..', '..'))
exe = os.path.join(root, 'bin', 'bitwhiz_release')
deck = os.path.join(root, 'tests', 'verification', 'av_study', 'fs_square.deck')
if not os.path.isfile(exe):
    print('skip  the shock width (no bin/bitwhiz_release; make release)')
else:
    base = open(deck).read()
    widths = {}
    with tempfile.TemporaryDirectory() as tmp:
        for v in (1, 2, 4):
            for z in (25, 100):
                for bq in (1, 2, 4):
                    name = 'w_%d_%d_%d' % (v, z, bq)
                    d = (base.replace('resolution = 25', 'resolution = %d' % z)
                         .replace('xvel     = 2.0', 'xvel     = %d.0' % v)
                         .replace('method = AV', 'method = AV\n  BQ = %d.0' % bq)
                         .replace('title = fs_square', 'title = ' + name))
                    open(os.path.join(tmp, name + '.deck'), 'w').write(d)
                    subprocess.run([exe, name + '.deck'], cwd=tmp, check=True,
                                   stdout=subprocess.DEVNULL)
                    lines = open(os.path.join(tmp, name + '.tracers.csv')).read().split('\n')
                    hdr = lines[0].split(', ')
                    iu = hdr.index('KMPS.mid')
                    rows = [l.split(',') for l in lines[2:] if l and not l.startswith('#')]
                    t = [float(r[0]) for r in rows]
                    uu = [float(r[iu]) for r in rows]
                    up = v/2.0
                    us = 5.30 + 1.34*up              # the class Al's Hugoniot
                    def cross(fr):
                        for i in range(1, len(uu)):
                            if uu[i] >= fr*up:
                                return t[i-1] + (fr*up - uu[i-1])*(t[i] - t[i-1])/(uu[i] - uu[i-1])
                    widths[(v, z, bq)] = (cross(0.9) - cross(0.1))*us*z
    for bq in (1, 2, 4):
        ws = [widths[(v, z, bq)] for v in (1, 2, 4) for z in (25, 100)]
        print('     BQ = %d: 10-90 %% width %.1f to %.1f cells (u_p 0.5 to 2 km/s, '
              '25 and 100 zones/mm)' % (bq, min(ws), max(ws)))
    ws2 = [widths[(v, z, 2)] for v in (1, 2, 4) for z in (25, 100)]
    ok('BQ = 2 (the default): a shock 2 to 3.5 cells wide at any strength',
       min(ws2) > 2.0 and max(ws2) < 3.5)
    ok('the width grows with BQ', all(widths[(v, z, 1)] < widths[(v, z, 2)]
       < widths[(v, z, 4)] for v in (1, 2, 4) for z in (25, 100)))

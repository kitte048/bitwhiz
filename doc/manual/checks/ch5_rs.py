"""Chapter 5's derivations, and the shock widths it quotes. Run:
python3 doc/manual/checks/ch5_rs.py  ('ok' per check).

Part 1 is symbolic (sympy): the pressure equation, the eigenvalues and
invariants of the acoustic system, the acoustic Riemann solution and its
limits, and the MUSCL-Hancock half step. Part 2 is exact: method RS's face
and cell updates (module rs, riemann_face and rs_cell_step) written again in
rational arithmetic on a small mesh with ghost cells, and the totals compared
exactly. Part 3 runs bin/bitwhiz_release (after 'make release') on
tests/verification/av_study/fs_square.deck and measures the shock's width at
orders 1 and 2; it is skipped if the executable is missing."""
import os, random, subprocess, tempfile
from fractions import Fraction as F
import sympy as sp

def ok(name, cond=True):
    assert cond, name
    print('ok ', name)

#*** Part 1a. The pressure equation. With P = P(V, e) and, for a smooth
#     flow, de/dt = -P dV/dt (chapter 2, q = 0):
#     dP/dt = [(dP/dV)_e - P (dP/de)_V] dV/dt = -Z^2 dV/dt = -Z^2 du/dh,
#     with c^2 = V^2 [P (dP/de)_V - (dP/dV)_e] and Z = c/V.
V, e, Pv = sp.symbols('V e P', positive=True)
Pf = sp.Function('P')(V, e)
dVdt = sp.symbols('dVdt')
dPdt = sp.diff(Pf, V)*dVdt + sp.diff(Pf, e)*(-Pf*dVdt)
c2 = V**2*(Pf*sp.diff(Pf, e) - sp.diff(Pf, V))
Z2 = c2/V**2
ok('dP/dt = -Z^2 dV/dt (= -Z^2 du/dh), Z^2 = rho^2 c^2',
   sp.simplify(dPdt + Z2*dVdt) == 0)

#*** Part 1b. The acoustic system W = (V, u, P): dW/dt + A dW/dh = 0.
Z, lam = sp.symbols('Z lambda', positive=True)
A = sp.Matrix([[0, -1, 0], [0, 0, 1], [0, Z**2, 0]])
ok('eigenvalues of A: -Z, 0, +Z',
   set(A.eigenvals().keys()) == {-Z, 0, Z})
for L, l in ((sp.Matrix([[0, -Z, 1]]), -Z), (sp.Matrix([[Z**2, 0, 1]]), 0),
             (sp.Matrix([[0, Z, 1]]), Z)):
    ok('left eigenvector %s for lambda = %s' % (list(L), l),
       sp.simplify(L*A - l*L) == sp.zeros(1, 3))
# so P - Z u is constant along dh/dt = -Z, P + Z u along dh/dt = +Z, and
# across the contact (lambda = 0) only V changes: u and P are continuous.

#*** Part 1c. The acoustic Riemann solution: the left state sends its
#     invariant P + Z_L u to the face along dh/dt = +Z_L, the right state
#     sends P - Z_R u along dh/dt = -Z_R; both hold at the face.
ZL, ZR, uL, uR, PL, PR, us, ps = sp.symbols('Z_L Z_R u_L u_R P_L P_R u_s P_s')
sol = sp.solve([ps + ZL*us - (PL + ZL*uL), ps - ZR*us - (PR - ZR*uR)],
               [us, ps])
ustar = (ZL*uL + ZR*uR + PL - PR)/(ZL + ZR)
pstar = (ZR*PL + ZL*PR + ZL*ZR*(uL - uR))/(ZL + ZR)
ok('u* = (Z_L u_L + Z_R u_R + P_L - P_R)/(Z_L + Z_R) (riemann_face)',
   sp.simplify(sol[us] - ustar) == 0)
ok('P* = (Z_R P_L + Z_L P_R + Z_L Z_R (u_L - u_R))/(Z_L + Z_R)',
   sp.simplify(sol[ps] - pstar) == 0)
ok('equal Z: P* = (P_L + P_R)/2 + (Z/2)(u_L - u_R)',
   sp.simplify(pstar.subs(ZR, ZL) - ((PL + PR)/2 + ZL/2*(uL - uR))) == 0)
ok('a free surface (Z_L = 0): u* = u_R - P_R/Z_R, P* = 0',
   sp.simplify(ustar.subs({ZL: 0, PL: 0}) - (uR - PR/ZR)) == 0
   and sp.simplify(pstar.subs({ZL: 0, PL: 0})) == 0)
ok('impact (P = 0 both sides, u_R = 0): the acoustic impedance match',
   sp.simplify(pstar.subs({PL: 0, PR: 0, uR: 0}) - ZL*ZR*uL/(ZL + ZR)) == 0)

#*** Part 1d. MUSCL-Hancock: values at the faces, W -/+ M s/2, each moved
#     half a step by du/dt = -dP/dh = -s_P, dP/dt = -Z^2 du/dh = -Z^2 s_u.
dt, M, su, spp, u0, p0 = sp.symbols('dt M s_u s_P u0 P0')
ulf = u0 - M*su/2 - dt/2*spp
plf = p0 - M*spp/2 - dt/2*Z**2*su
ok('the half step obeys du/dt = -dP/dh and dP/dt = -Z^2 du/dh (rs_face_states)',
   sp.simplify((ulf - (u0 - M*su/2))/(dt/2) + spp) == 0
   and sp.simplify((plf - (p0 - M*spp/2))/(dt/2) + Z**2*su) == 0)
# Van Leer's limiter: 2ab/(a + b) when ab > 0; between a and b, at most
# twice the smaller; zero at an extremum
a, b = sp.symbols('a b', positive=True)
vl = 2*a*b/(a + b)
ok("Van Leer: 2ab/(a+b) <= 2 min(a, b), and lies between a and b",
   sp.simplify(sp.Min(2*a, 2*b) - vl).subs({a: 1, b: 3}) >= 0
   and all(min(x, y) <= 2*x*y/(x + y) <= max(x, y)
           for x, y in ((1, 3), (0.2, 5), (2, 2), (7, 0.01))))
# on equal masses (M = 1), the face values W -/+ s/2 stay between the
# neighbors' averages, so the reconstruction makes no new extremum
random.seed(7)
okb = True
for _ in range(2000):
    w0, w1, w2 = (random.uniform(-5, 5) for _ in range(3))
    s_ = 2*(w1 - w0)*(w2 - w1)/((w1 - w0) + (w2 - w1)) \
        if (w1 - w0)*(w2 - w1) > 0 else 0.0
    lo, hi = w1 - s_/2, w1 + s_/2
    okb &= min(w0, w1) - 1e-12 <= lo <= max(w0, w1) + 1e-12
    okb &= min(w1, w2) - 1e-12 <= hi <= max(w1, w2) + 1e-12
ok("Van Leer, equal masses: each face value lies between the two cells' "
   "averages beside that face", okb)

#*** Part 2. Exact conservation of the Godunov update.
random.seed(5)
def R(lo, hi):
    return F(random.randint(int(lo*1000), int(hi*1000)), 1000)
N = 6
Mk = [F(0)] + [R(0.5, 2.0) for _ in range(N)] + [F(0)]
rho = [F(0)] + [R(1.0, 9.0) for _ in range(N)] + [F(0)]
cc = [F(0)] + [R(1.0, 6.0) for _ in range(N)] + [F(0)]
Pk = [F(0)] + [R(-0.5, 20.0) for _ in range(N)] + [F(0)]
uk = [F(0)] + [R(-1.0, 2.0) for _ in range(N)] + [F(0)]
ek = [F(0)] + [R(0.0, 2.0) for _ in range(N)] + [F(0)]
dtv = F(3, 1000)
def face(j):                       # between cells j and j+1 (order 1)
    zl = rho[j]*cc[j] if Mk[j] > 0 else F(0)
    zr = rho[j + 1]*cc[j + 1] if Mk[j + 1] > 0 else F(0)
    pl = Pk[j] if Mk[j] > 0 else F(0)
    pr = Pk[j + 1] if Mk[j + 1] > 0 else F(0)
    ul = uk[j] if Mk[j] > 0 else F(0)
    ur = uk[j + 1] if Mk[j + 1] > 0 else F(0)
    return ((zl*ul + zr*ur + pl - pr)/(zl + zr),
            (zr*pl + zl*pr + zl*zr*(ul - ur))/(zl + zr))
fs = [face(j) for j in range(N + 1)]
un, en = list(uk), list(ek)
for k in range(1, N + 1):
    (ua, pa), (ub, pb) = fs[k - 1], fs[k]
    Et = ek[k] + uk[k]**2/2
    un[k] = uk[k] - dtv/Mk[k]*(pb - pa)
    Et = Et - dtv/Mk[k]*(pb*ub - pa*ua)
    en[k] = Et - un[k]**2/2
tot = lambda uu, ee: (sum(Mk[k]*uu[k] for k in range(1, N + 1)),
                      sum(Mk[k]*(ee[k] + uu[k]**2/2) for k in range(1, N + 1)))
ok('momentum sum M u and total energy sum M E: exactly the same after a step',
   tot(uk, ek) == tot(un, en))
ok('both free surfaces carry P* = 0', fs[0][1] == 0 and fs[N][1] == 0)

#*** Part 3. The shock's width at orders 1 and 2 (runs bitwhiz).
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
        for o in (1, 2):
            for v in (1, 2, 4):
                for z in (25, 100):
                    name = 'r_%d_%d_%d' % (o, v, z)
                    d = (base.replace('resolution = 25', 'resolution = %d' % z)
                         .replace('xvel     = 2.0', 'xvel     = %d.0' % v)
                         .replace('method = AV', 'method = RS\n  order = %d' % o)
                         .replace('title = fs_square', 'title = ' + name))
                    open(os.path.join(tmp, name + '.deck'), 'w').write(d)
                    subprocess.run([exe, name + '.deck'], cwd=tmp, check=True,
                                   stdout=subprocess.DEVNULL)
                    lines = open(os.path.join(tmp, name + '.tracers.csv')).read().split('\n')
                    iu = lines[0].split(', ').index('KMPS.mid')
                    rows = [l.split(',') for l in lines[2:] if l and not l.startswith('#')]
                    t = [float(r[0]) for r in rows]
                    uu = [float(r[iu]) for r in rows]
                    up = v/2.0
                    usp = 5.30 + 1.34*up
                    def cross(fr):
                        for i in range(1, len(uu)):
                            if uu[i] >= fr*up:
                                return t[i-1] + (fr*up - uu[i-1])*(t[i] - t[i-1])/(uu[i] - uu[i-1])
                    widths[(o, v, z)] = (cross(0.9) - cross(0.1))*usp*z
    for o in (1, 2):
        ws = [widths[(o, v, z)] for v in (1, 2, 4) for z in (25, 100)]
        print('     order %d: 10-90 %% width %.1f to %.1f cells (u_p 0.5 to 2 '
              'km/s, 25 and 100 zones/mm, 1.5 mm into the target)'
              % (o, min(ws), max(ws)))
    ok('order 2: a shock under 3 cells wide at every strength and mesh',
       max(widths[(2, v, z)] for v in (1, 2, 4) for z in (25, 100)) < 3.0)
    ok('order 1 is wider than order 2 in every case',
       all(widths[(1, v, z)] > widths[(2, v, z)] for v in (1, 2, 4)
           for z in (25, 100)))
    ok('order 1: weaker shocks are wider',
       all(widths[(1, 1, z)] > widths[(1, 2, z)] > widths[(1, 4, z)]
           for z in (25, 100)))

"""Chapter 7's closed forms, from the definitions (sympy, and mpmath for
numbers). Run: python3 doc/manual/checks/ch7_models.py  ('ok' per check)."""
import sympy as sp
import mpmath as mp
mp.mp.dps = 30
def ok(c, name):
    print(('ok  ' if (c is True or sp.simplify(c) == 0) else 'FAIL') + ' ' + name)

#*** HVRB: topology
phi, MR, XR, lam, t, tau0 = sp.symbols('phi M_R X_R lambda t tau_0', positive=True)
L = 1 - (1 - phi**MR/XR)**XR
F = (XR*(1 - (1 - lam)**(1/XR)))**(1/MR)              # phi(lam)
g = MR*XR**(1 - 1/MR)*(1 - lam)**(1 - 1/XR)*(1 - (1 - lam)**(1/XR))**(1 - 1/MR)
# sympy can not simplify the powers for symbolic exponents: check at 50
# random (MR, XR, lam) to 25 digits instead
import random
random.seed(1)
w1 = w2 = 0
for _ in range(50):
    sub = {MR: mp.mpf(random.uniform(0.5, 4)), XR: mp.mpf(random.uniform(0.5, 6)),
           lam: mp.mpf(random.uniform(0.001, 0.999))}
    f = F.subs(sub)
    w1 = max(w1, abs(mp.mpf(L.subs({MR: sub[MR], XR: sub[XR], phi: f})) - sub[lam]))
    dl = mp.diff(lambda x: mp.mpf(L.subs({MR: sub[MR], XR: sub[XR], phi: x})), mp.mpf(f))
    w2 = max(w2, abs(dl/mp.mpf(g.subs(sub)) - 1))
ok(w1 < 1e-25, 'HVRB: phi(lam) inverts lam(phi) (50 random points)')
ok(w2 < 1e-20, 'HVRB: g(lam) = dlam/dphi (50 random points)')
ok(sp.simplify(L.subs(phi, XR**(1/MR)) - 1), 'HVRB: lam(phi_end) = 1')
# Material X set: g's peak and phi_end
gl = sp.lambdify(lam, g.subs({MR: 1.5, XR: 2.5}), 'mpmath')
lpk = mp.findroot(lambda x: mp.diff(gl, x), 0.4)
print('     Material X: g peaks at lam = %.4f, g_max = %.4f, phi_end = %.4f'
      % (lpk, gl(lpk), 2.5**(1/1.5)))
ok(abs(lpk - 0.394) < 5e-4 and abs(gl(lpk) - 0.854) < 5e-4
   and abs(2.5**(1/1.5) - 1.842) < 5e-4, 'HVRB: 0.394, 0.854, 1.842 as printed')
# ZR = 0, MR = 1: phi = t/tau0, the d^n law with XR = 3/n, t_b = XR tau0
n = sp.symbols('n', positive=True)
tb = sp.symbols('t_b', positive=True)
lam_dn = 1 - (1 - t/tb)**(3/n)                          # d^n law
ok(sp.simplify(L.subs({MR: 1, phi: t/tau0}).subs(XR, 3/n).subs(tau0, tb*n/3)
               - lam_dn), 'HVRB: ZR = 0, MR = 1 is the d^n law, XR = 3/n')

#*** The lead shock: h = q (V0 - V)/2 along a steady wave's Rayleigh line
V0, V, P, q, m = sp.symbols('V_0 V P q m', positive=True)
Sig = m**2*(V0 - V)                                     # P + q, Rayleigh
e_ = sp.Rational(1, 2)*Sig*(V0 - V)                     # energy, steady wave
h = e_ - sp.Rational(1, 2)*(V0 - V)*(Sig - q)
ok(sp.simplify(h - q*(V0 - V)/2), 'lead shock: h = q (V0 - V)/2 in a steady smeared shock')

#*** ThermalCascade
r, dt, l1 = sp.symbols('r Delta_t lambda_1', positive=True)
lt = sp.Function('lam')(t)
sol = sp.dsolve(sp.Eq(lt.diff(t), r*(1 - lt)), lt, ics={lt.subs(t, 0): l1})
ok(sp.simplify(sol.rhs.subs(t, dt) - (l1 + (1 - l1)*(1 - sp.exp(-r*dt)))),
   'TC: exact step at a fixed rate')
# the cascade at constant volume, GT = 1: closed form of the time to lam
A, B, k = sp.symbols('A B k', positive=True)            # A = Ta - TC, B = b, k = HT S
integrand = 1/(k*(1 - lam)*(A + B*lam))
cf = (sp.log((A + B*lam)/A) - sp.log(1 - lam))/(k*(A + B))
ok(sp.simplify(sp.diff(cf, lam) - integrand) == 0 and cf.subs(lam, 0) == 0,
   'TC: cascade at constant volume, GT = 1, closed form')

#*** StochasticIgnite: KJMA
a = sp.symbols('a', positive=True)
ok(sp.simplify(sp.diff(1 - sp.exp(-phi**a), phi)
               - a*phi**(a - 1)*sp.exp(-phi**a)), 'SI: dlam/dphi of KJMA')

#*** HALO: lam = 1 - exp(-s^d), ds/dt = R  =>  dlam/dt = d s^(d-1) (1-lam) R
s, d, R = sp.symbols('s d R', positive=True)
lh = 1 - sp.exp(-s**d)
ok(sp.simplify(sp.diff(lh, s)*R - d*s**(d - 1)*(1 - lh)*R), 'HALO: chain rule')

#*** CLAUDE: moments' exact update; Hill-Zimmermann's limit
dR = sp.symbols('Delta_R', positive=True)
Rs = sp.symbols('R1:4', positive=True)                  # three centers' radii
for j in range(4):
    lhs = sum((Ri + dR)**j for Ri in Rs)
    Mi = [sum(Ri**i for Ri in Rs) for i in range(4)]
    rhs = sum(sp.binomial(j, i)*dR**(j - i)*Mi[i] for i in range(j + 1))
    ok(sp.expand(lhs - rhs), 'CLAUDE: M_%d <- sum_i C(%d,i) dR^(%d-i) M_i' % (j, j, j))
N, G = sp.symbols('N G', positive=True)                 # every center lit at t = 0
M3 = N*(G*t)**3
th = sp.symbols('that', positive=True)                  # t-hat = t / t_c
tc = 1/(2*G*N**sp.Rational(1, 3))                       # t_c: a center's diameter 2 G t reaches the spacing N^(-1/3)
ok(sp.simplify(sp.Rational(4, 3)*sp.pi*M3.subs(t, th*tc)
               - sp.pi/6*th**3), 'CLAUDE: all lit at once, G constant: (pi/6) that^3')

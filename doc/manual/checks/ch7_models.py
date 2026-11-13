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
# SIGMA = 0, a clock: phi = MU S t, lam = 1 - exp(-(MU S t)^a) (test_sign 5)
mu, S = sp.symbols('mu S', positive=True)
ls = 1 - sp.exp(-(mu*S*t)**a)
ok(sp.simplify(sp.diff(ls, t) - a*(mu*S*t)**(a - 1)*(1 - ls)*mu*S),
   'SI: SIGMA = 0, lam = 1 - exp(-(MU S t)^a) solves eq. (si)')
# The OU step: Z' = A Z + sqrt(1 - A^2) xi keeps variance 1, correlation A
Aou = sp.symbols('A', positive=True)
ok(sp.simplify(Aou**2 + (1 - Aou**2) - 1), 'SI: OU step keeps var(Z) = 1')
# var(phi) with no floor: sigma^2 S^2 int int exp(-|t1 - t2|/tau) dt1 dt2
sg, tau, t1, t2 = sp.symbols('sigma tau t_1 t_2', positive=True)
inner = sp.integrate(sp.exp(-(t1 - t2)/tau), (t2, 0, t1))
v = 2*sg**2*S**2*sp.integrate(inner, (t1, 0, t))
ok(sp.simplify(v - 2*sg**2*S**2*tau**2*(t/tau - 1 + sp.exp(-t/tau))),
   'SI: var(phi) = 2 sigma^2 S^2 tau^2 (t/tau - 1 + exp(-t/tau)), no floor')
# The floored mean rate, E[(mu + sigma Z)+] = mu Phi(mu/sigma) + sigma phi(mu/sigma)
def fm(m, g):
    m, g = mp.mpf(m), mp.mpf(g)
    return m*mp.ncdf(m/g) + g*mp.npdf(m/g)
w = max(abs(mp.quad(lambda z: max(m + g*z, 0)*mp.npdf(z), [-mp.inf, -m/g, mp.inf])
            - fm(m, g)) for m, g in [(2, 1), (2, 6), (1.35, 0.7), (0.5, 3)])
ok(w < 1e-20, 'SI: E[(mu + sigma Z)+] = mu Phi + sigma phi (4 points)')
# ... grows as sigma/sqrt(2 pi): the white-noise limit diverges
ok(sp.limit((mu*(1 + sp.erf(mu/(sg*sp.sqrt(2))))/2
             + sg*sp.exp(-mu**2/(2*sg**2))/sp.sqrt(2*sp.pi))/sg, sg, sp.oo)
   - 1/sp.sqrt(2*sp.pi), 'SI: the floored mean over sigma -> 1/sqrt(2 pi)')

#*** HALO: lam = 1 - exp(-s^d), ds/dt = R  =>  dlam/dt = d s^(d-1) (1-lam) R
s, d, R = sp.symbols('s d R', positive=True)
lh = 1 - sp.exp(-s**d)
ok(sp.simplify(sp.diff(lh, s)*R - d*s**(d - 1)*(1 - lh)*R), 'HALO: chain rule')
# ... and in lam: d s^(d-1) = d (-ln(1-lam))^((d-1)/d), the hot-spot topology
lmh = sp.symbols('lambda_h', positive=True)
fr = sp.lambdify((d, lmh), (d*s**(d - 1)).subs(s, (-sp.log(1 - lmh))**(1/d))
                 - d*(-sp.log(1 - lmh))**((d - 1)/d), 'mpmath')
w = max(abs(fr(mp.mpf(dd), mp.mpf(ll))) for dd in ('2', '2.3', '3')
        for ll in ('1e-6', '0.3', '0.99'))
ok(w < 1e-25, 'HALO: the rate in lam, d (-ln(1-lam))^((d-1)/d) (9 points)')
# One step across a Rayleigh line from rest: sqrt(mean P) |Dv| over the
# integral of sqrt(P) |dv| is 3/(2 sqrt 2)
P1, Dv = sp.symbols('P_1 Delta_v', positive=True)
x = sp.symbols('x', positive=True)
I = sp.integrate(sp.sqrt(P1*x), (x, 0, 1))*Dv
ok(sp.simplify(sp.sqrt(P1/2)*Dv/I - 3/(2*sp.sqrt(2))), 'HALO: one step from rest, 3/(2 sqrt 2)')
# eta's bound: decay then add Delta erf keeps eta <= erf (eta1 <= A1, 0 < f <= 1)
eta1, A1, A2, f = sp.symbols('eta_1 A_1 A_2 f', positive=True)
ok(sp.simplify((A2 - (eta1*f + A2 - A1)).subs(eta1, A1 - x) - (A1*(1 - f) + x*f)),
   'HALO: A2 - eta2 = A1 (1 - f) + (A1 - eta1) f >= 0')

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

#*** FlashFire: at a fixed T with B_F = 0, dlam/dt = c (1 - lam)^A_F has the
#*** closed forms test_ffire uses; and h of eq. (ff-h) is RK4-exact for a
#*** constant rate (A_F = B_F = T_a = 0): lam1 + r dt.
c, A, l0 = sp.symbols('c A_F lambda_0', positive=True)
lt = 1 - ((1 - l0)**(1 - A) - (1 - A)*c*t)**(1/(1 - A))
res = sp.lambdify((c, A, l0, t), sp.diff(lt, t) - c*(1 - lt)**A, 'mpmath')
w = max(abs(res(mp.mpf(cc), mp.mpf(aa), mp.mpf('1e-4'), mp.mpf(tt)))
        for cc, aa, tt in [(2, 0.5, 0.3), (2, 2, 1.5), (5, 1.5, 0.1), (1, 0.25, 0.2)])
ok(w < 1e-25, 'FlashFire: (1-lam)^(1-A) linear in t solves dlam/dt = c (1-lam)^A (4 points)')
le = 1 - (1 - l0)*sp.exp(-c*t)
ok(sp.simplify(sp.diff(le, t) - c*(1 - le)), 'FlashFire: A_F = 1, the exponential')
r0, h = sp.symbols('r h', positive=True)
k1 = k2 = k3 = k4 = r0                       # a constant rate: every stage r
ok(sp.simplify(l0 + h*(k1 + 2*k2 + 2*k3 + k4)/6 - (l0 + r0*h)), 'FlashFire: RK4 exact for a constant rate')

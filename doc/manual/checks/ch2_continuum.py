"""Chapter 2's derivations, symbolically (sympy), and its units by
arithmetic. Run: python3 doc/manual/checks/ch2_continuum.py  ('ok' per
check).

Every field is a generic smooth function of (x, t), so each check is an
identity, not a sample: if it prints 'ok', the step in the chapter holds for
any smooth flow."""
import sympy as sp

x, t = sp.symbols('x t', real=True)
rho = sp.Function('rho', positive=True)(x, t)
u = sp.Function('u')(x, t)
e = sp.Function('e')(x, t)
sig = sp.Function('sigma')(x, t)
P = sp.Function('P')(x, t)
q = sp.Function('q')(x, t)
phi_t = sp.Function('phit')(x, t)          # an intensive quantity
S = sp.Function('S')(x, t)                  # its source per unit volume

def ok(name, expr):
    expr = sp.simplify(sp.expand(expr))
    assert expr == 0, (name, expr)
    print('ok ', name)

D = lambda f: sp.diff(f, t) + u*sp.diff(f, x)          # material derivative
mass = sp.diff(rho, t) + sp.diff(rho*u, x)              # = 0, eq. (mass)

# (1) conservative <-> intensive: d(rho f)/dt + d(rho u f)/dx - S
#     = rho Df/Dt - S + f*(mass residual)
ok('intensive form from the conservative one (eq. transport)',
   sp.diff(rho*phi_t, t) + sp.diff(rho*u*phi_t, x)
   - (rho*D(phi_t) + phi_t*mass))

# (2) the mass coordinate h: dh/dx = rho, dh/dt|_x = -rho u, so
#     d/dt|_h = d/dt|_x + u d/dx = D/Dt and d/dh = (1/rho) d/dx.
#     h is a potential only if its cross derivatives agree, which is mass.
ok('h exists: d/dt(rho) = d/dx(-rho u) is conservation of mass',
   sp.diff(rho, t) - sp.diff(-rho*u, x) - mass)
Dh = lambda f: sp.diff(f, x)/rho                        # d/dh
V = 1/rho

# (3) mass: dV/dt|_h = du/dh, given mass = 0
ok('mass in h: D(1/rho)/Dt - du/dh = -(mass)/rho^2',
   D(V) - Dh(u) + mass/rho**2)

# (4) momentum: rho Du/Dt = dsigma/dx  <=>  du/dt|_h = dsigma/dh
mom_x = rho*D(u) - sp.diff(sig, x)
ok('momentum in h: Du/Dt - dsigma/dh = (rho Du/Dt - dsigma/dx)/rho',
   (D(u) - Dh(sig)) - mom_x/rho)

# (5) internal energy: rho De/Dt = sigma du/dx <=> de/dt|_h = sigma dV/dt|_h
en_x = rho*D(e) - sig*sp.diff(u, x)
ok('energy in h: De/Dt - sigma du/dh = (rho De/Dt - sigma du/dx)/rho',
   (D(e) - sig*Dh(u)) - en_x/rho)

# (6) total energy: d(e + u^2/2)/dt|_h = d(sigma u)/dh, from (4) and (5)
ok('total energy in h: the sum of u*(4) and (5)',
   (D(e + u**2/2) - Dh(sig*u)) - ((D(e) - sig*Dh(u)) + u*(D(u) - Dh(sig))))

# (7) the source of kinetic energy and the stress power add to a divergence
ok('u dsigma/dx + sigma du/dx = d(sigma u)/dx',
   u*sp.diff(sig, x) + sig*sp.diff(u, x) - sp.diff(sig*u, x))

# (8) entropy: T Ds/Dt = De/Dt + P DV/Dt (Gibbs), with rho De/Dt = sigma du/dx
#     and DV/Dt = du/dx / rho: rho T Ds/Dt = (sigma + P) du/dx
Tds = D(e) + P*D(V)
ok('entropy: rho (De/Dt + P DV/Dt) - (sigma + P) du/dx = en_x + P*(mass)/rho',
   rho*Tds - (sig + P)*sp.diff(u, x) - (en_x - P*mass/rho))
# with sigma = -(P + q): rho T Ds/Dt = -q du/dx
ok('entropy with sigma = -(P + q): (sigma + P) = -q',
   ((sig + P)*sp.diff(u, x)).subs(sig, -(P + q)) + q*sp.diff(u, x))

# (9) Stokes' hypothesis: 2 mu + lambda = (4/3) mu when lambda = -(2/3) mu
mu = sp.symbols('mu', positive=True)
ok("Stokes: 2 mu + lambda = 4/3 mu", 2*mu + (-sp.Rational(2, 3)*mu) - sp.Rational(4, 3)*mu)

# (10) small disturbances: linearize in h about rest (rho0, P = 0):
#     dV/dt = du/dh, du/dt = -dP/dh, dP = -rho0^2 c^2 dV  gives
#     d2u/dt2 = (rho0 c)^2 d2u/dh2: waves at rho0 c in h, c in x.
h = sp.symbols('h', real=True)
r0, c = sp.symbols('rho0 c', positive=True)
f, g = sp.Function('f'), sp.Function('g')
uw = f(h - r0*c*t) + g(h + r0*c*t)
ok("d'Alembert: u = f(h - rho0 c t) + g(h + rho0 c t) solves the wave eq.",
   sp.diff(uw, t, 2) - (r0*c)**2*sp.diff(uw, h, 2))
# a right-running wave carries dP = rho0 c du: from du/dt = -dP/dh with
# u = f(h - Z t), P = Z f(h - Z t) (Z = rho0 c, the impedance)
Z = r0*c
ok('right-running wave: P = rho0 c u satisfies du/dt = -dP/dh',
   sp.diff(f(h - Z*t), t) + sp.diff(Z*f(h - Z*t), h))

# (11) units: bitwhiz's set needs no conversion factors (SI by arithmetic)
mm, us = 1e-3, 1e-6                    # m, s
g_cc = 1e3                             # kg/m^3
kms = 1e3                              # m/s
GPa = 1e9                              # Pa
kJg = 1e6                              # J/kg
def same(name, a, b):
    assert abs(a/b - 1) < 1e-12, (name, a, b)
    print('ok ', name)
same('mm/us = km/s', mm/us, kms)
same('rho u^2: (g/cm^3)(km/s)^2 = GPa', g_cc*kms**2, GPa)
same('e = u^2: (km/s)^2 = kJ/g', kms**2, kJg)
same('P V: GPa/(g/cm^3) = kJ/g', GPa/g_cc, kJg)
same('dt dP/M: us GPa/((g/cm^3) mm) = km/s', us*GPa/(g_cc*mm), kms)
same('impedance rho c: (g/cm^3)(km/s) = GPa/(km/s)', g_cc*kms, GPa/kms)

# (12) diffusion is too slow (thermal diffusivity alpha, room temperature,
#     handbook values: Al about 97 mm^2/s, PMMA about 0.11 mm^2/s). The
#     chapter says: across 1 mm, ~10 ms (Al) and ~10 s (PMMA); 3 to 6 orders
#     of magnitude longer than a run of a few us; at a shock, conduction
#     acts over alpha/U_s, tens of nm in Al (U_s ~ 6 km/s), less in PMMA
#     (U_s ~ 3 km/s).
import math
a_al, a_pm = 97e-6, 0.11e-6              # m^2/s
t_al, t_pm = (1e-3)**2/a_al, (1e-3)**2/a_pm
assert 8e-3 < t_al < 12e-3 and 5 < t_pm < 12, (t_al, t_pm)
run = 5e-6                               # s, a few microseconds
orders = (math.log10(t_al/run), math.log10(t_pm/run))
assert 3 <= orders[0] and orders[1] <= 6.5, orders
w_al, w_pm = a_al/6e3, a_pm/3e3          # m
assert 1e-8 < w_al < 1e-7 and w_pm < w_al, (w_al, w_pm)
print('ok  diffusion: 1 mm in %.0f ms (Al), %.0f s (PMMA); %.1f to %.1f '
      'orders past a 5 us run; alpha/U_s %.0f nm (Al), %.2f nm (PMMA)'
      % (t_al*1e3, t_pm, orders[0], orders[1], w_al*1e9, w_pm*1e9))

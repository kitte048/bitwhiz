"""Chapter 3's derivations and numbers: sympy for the algebra, mpmath (30
digits) for the numbers. Run: python3 doc/manual/checks/ch3_shocks.py
('ok' per check).

The class materials are the class deck's (input/me697_double_shock_2p00.deck):
Al R0 2.78, C0 5.30, S1 1.34, G0 2.00; Material X R0 1.60, C0 2.50, S1 1.80,
S2 -0.10, G0 1.20; PMMA R0 1.187, C0 2.55, S1 1.54, G0 0.90; Ta R0 16.65,
C0 3.40, S1 1.20, G0 1.60. The Hugoniot is bitwhiz's: U_s = C0 + S1 u_p +
(S2/C0) u_p^2, Gamma rho = Gamma_0 rho_0 (doc/Hydrocode_Eqns_v4)."""
import sympy as sp
import mpmath as mp
mp.mp.dps = 30

def ok(name, cond=True):
    assert cond, name
    print('ok ', name)

def zero(name, expr):
    ok(name, sp.simplify(sp.expand(expr)) == 0)

#*** 1. Jump conditions from the steady control volume (shock frame).
#     Ahead: rho0, speed Us toward the shock, P0, e0. Behind: rho, speed
#     Us - up, P, e. Fluxes in = fluxes out (eq. (3.2)-(3.4)).
r0, r, Us, up, P0, P, e0, e, V0, V = sp.symbols(
    'rho0 rho U_s u_p P0 P e0 e V0 V', positive=True)
mass = r*(Us - up) - r0*Us
mom = (P + r*(Us - up)**2) - (P0 + r0*Us**2)
en = r*(Us - up)*(e + (Us - up)**2/2 + P/r) - r0*Us*(e0 + Us**2/2 + P0/r0)
rho_s = sp.solve(mass, r)[0]                          # rho from mass
P_s = sp.solve(mom.subs(r, rho_s), P)[0]              # P from momentum
e_s = sp.solve(en.subs({r: rho_s, P: P_s}), e)[0]     # e from energy
zero('mass: eta = 1 - rho0/rho = up/Us', (1 - r0/rho_s) - up/Us)
zero('momentum: P - P0 = rho0 Us up', P_s - P0 - r0*Us*up)
zero('energy: e - e0 = up^2/2 + P0 (V0 - V)',
     e_s - e0 - (up**2/2 + P0*(1/r0 - 1/rho_s)))
zero('energy: e - e0 = (P + P0)(V0 - V)/2 (the Hugoniot energy)',
     e_s - e0 - (P_s + P0)*(1/r0 - 1/rho_s)/2)
mdot = r0*Us
zero('Rayleigh line: P - P0 = mdot^2 (V0 - V)',
     P_s - P0 - mdot**2*(1/r0 - 1/rho_s))
zero('up^2 = (P - P0)(V0 - V)', up**2 - (P_s - P0)*(1/r0 - 1/rho_s))
zero('Us^2 = V0^2 (P - P0)/(V0 - V)',
     Us**2 - (P_s - P0)*(1/r0)**2/(1/r0 - 1/rho_s))
# the kinetic energy and the internal energy (P0 = 0): equal halves
ok('P0 = 0: e - e0 = up^2/2, half of P (V0 - V)',
   sp.simplify((e_s - e0 - up**2/2).subs(P0, 0)) == 0)

#*** 2. Inside a steady front with sigma = -(P + q): the Rayleigh line and
#     the Hugoniot energy hold at every point, with P + q in place of P.
q = sp.symbols('q')
Vx = sp.symbols('V_x', positive=True)                  # a point inside
m = sp.symbols('m', positive=True)                     # mdot
PR = sp.solve((P + q) + m**2*Vx - (P0 + m**2*V0), P + q)[0]
zero('inside: P + q = P0 + mdot^2 (V0 - V)', PR - (P0 + m**2*(V0 - Vx)))
# energy flux: e + (mdot V)^2/2 + (P + q) V = e0 + (mdot V0)^2/2 + P0 V0
ex = sp.solve(e + (m*Vx)**2/2 + PR*Vx - (e0 + (m*V0)**2/2 + P0*V0), e)[0]
zero('inside: e - e0 = (P_R + P0)(V0 - V)/2, P_R = P + q',
     ex - e0 - (PR + P0)*(V0 - Vx)/2)

#*** 3. The linear Hugoniot in P-V: P = rho0 c0^2 eta/(1 - s1 eta)^2
c0, s1, eta = sp.symbols('c0 s1 eta', positive=True)
upe = c0*eta/(1 - s1*eta)                     # from up = eta Us, Us = c0 + s1 up
zero('linear Us-up: up = c0 eta/(1 - s1 eta)',
     upe - eta*(c0 + s1*upe))
zero('linear Us-up: P_H = rho0 c0^2 eta/(1 - s1 eta)^2',
     r0*(c0 + s1*upe)*upe - r0*c0**2*eta/(1 - s1*eta)**2)
# its limiting compression: eta -> 1/s1, rho -> rho0 s1/(s1 - 1)
ok('linear Us-up: P_H unbounded as eta -> 1/s1',
   sp.limit(r0*c0**2*eta/(1 - s1*eta)**2, eta, 1/s1, '-') == sp.oo)

#*** 4. Numbers on the class materials (mpmath).
MAT = {'Al': (2.78, 5.30, 1.34, 0.0, 2.00),
       'MatX': (1.60, 2.50, 1.80, -0.10, 1.20),
       'PMMA': (1.187, 2.55, 1.54, 0.0, 0.90),
       'Ta': (16.65, 3.40, 1.20, 0.0, 1.60)}
M = lambda x: mp.mpf(str(x))

def Us_up(mat, u):
    R0, C0, S1, S2, G0 = map(M, MAT[mat])
    return C0 + S1*u + (S2/C0)*u**2

def P_up(mat, u):
    return M(MAT[mat][0])*Us_up(mat, u)*u

def us_eta(mat, et):                          # bitwhiz's inversion
    R0, C0, S1, S2, G0 = map(M, MAT[mat])
    return 2*C0/((1 - S1*et) + mp.sqrt((1 - S1*et)**2 - 4*S2*et**2))

def PH(mat, V):
    R0 = M(MAT[mat][0]); et = 1 - R0*V
    return R0*et*us_eta(mat, et)**2

def eH(mat, V):
    R0 = M(MAT[mat][0]); et = 1 - R0*V
    return (et*us_eta(mat, et))**2/2

def P_mg(mat, V, e):                          # Mie-Gruneisen, Gamma rho fixed
    R0, G0 = M(MAT[mat][0]), M(MAT[mat][4])
    return PH(mat, V) + R0*G0*(e - eH(mat, V))

def c_mg(mat, V, e):                          # c^2 = -V^2 (dP/dV)_s
    dPdV = mp.diff(lambda v: P_mg(mat, v, e), V)
    dPde = M(MAT[mat][0])*M(MAT[mat][4])
    return mp.sqrt(-V**2*(dPdV - P_mg(mat, V, e)*dPde))

# 4a. The impedance match, Al at 2.00 km/s onto Material X at rest:
#     P_A(2 - u1) = P_B(u1). The gold-standard README gives 10.736 GPa,
#     4.893 km/s (tests/verification/inert_gauges/README.md).
u0 = M(2)
u1 = mp.findroot(lambda u: P_up('Al', u0 - u) - P_up('MatX', u), 1.2)
P1 = P_up('MatX', u1); Ux = Us_up('MatX', u1); UA = Us_up('Al', u0 - u1)
ok('impedance match Al 2.00 -> MatX: u1 %.4f km/s, P1 %.3f GPa, Us %.3f km/s'
   % (u1, P1, Ux), abs(P1 - M('10.736')) < M('0.0005')
   and abs(Ux - M('4.893')) < M('0.0005'))
lab_A = u0 - Us_up('Al', u0 - u1)
ok('Al: its shock runs back into the flyer at %.3f km/s (lab)' % lab_A,
   lab_A < 0)
# the acoustic estimate, with Z = rho0 c0 on both sides
ZA, ZB = M(2.78)*M(5.30), M(1.60)*M(2.50)
ua = ZA*u0/(ZA + ZB); Pa = ZB*ua
ok('acoustic estimate: u1 %.4f, P1 %.3f GPa (%.0f %% low)'
   % (ua, Pa, 100*(1 - Pa/P1)), Pa < P1)
# shock impedances at the match
ok('shock impedance rho0 Us: Al %.2f, MatX %.2f GPa/(km/s); acoustic %.2f, %.2f'
   % (M(2.78)*UA, M(1.60)*Ux, ZA, ZB), True)

# 4b. Supersonic ahead, subsonic behind (all four materials, up 0.1-3 km/s)
for mat in MAT:
    R0 = M(MAT[mat][0]); C0 = M(MAT[mat][1])
    worst = None
    for k in range(1, 31):
        u = M(k)/10
        U = Us_up(mat, u); V = (1 - u/U)/R0
        c1 = c_mg(mat, V, eH(mat, V))
        ok_here = (U > C0) and (U - u < c1)
        assert ok_here, (mat, u, U, c1)
        ratio = (U - u)/c1
        worst = ratio if worst is None else max(worst, ratio)
    ok('%s: Us > C0 ahead and Us - up < c behind, up 0.1 to 3 km/s '
       '(largest (Us - up)/c = %.3f)' % (mat, worst))

# 4c. Weak shocks make entropy at third order: the Hugoniot and the
#     isentrope through (V0, e = 0) agree to second order in eta, so
#     P_H - P_S ~ k eta^3. Isentrope: de/dV = -P(V, e), from V0.
mat = 'Al'
R0 = M(MAT[mat][0]); V0n = 1/R0
# in w = V0 - V (mpmath integrates forward): de/dw = +P(V0 - w, e)
iso = mp.odefun(lambda w, ee: P_mg(mat, V0n - w, ee), M(0), M(0))
ratios = []
for et in (M('0.04'), M('0.02'), M('0.01'), M('0.005')):
    V = V0n*(1 - et)
    ratios.append((PH(mat, V) - P_mg(mat, V, iso(V0n - V)))/et**3)
ok('weak shocks: (P_H - P_S)/eta^3 in Al -> %.2f GPa (%.2f, %.2f, %.2f, %.2f)'
   % tuple([ratios[-1]] + ratios),
   all(r > 0 for r in ratios) and abs(ratios[-1]/ratios[-2] - 1) < 0.03)

# 4d. The figure's Hugoniot (U5 sheet, 2024 Al): rho0 c0^2 = 79.06 GPa
ok('rayleigh figure: 2.785 * 5.328^2 = %.2f GPa' % (M('2.785')*M('5.328')**2),
   abs(M('2.785')*M('5.328')**2 - M('79.06')) < M('0.005'))
# 4e. how nearly isentropic a weak shock is: Al at eta = 0.1
V = V0n*(1 - M('0.1'))
dP = PH(mat, V) - P_mg(mat, V, iso(V0n - V))
ok('Al at eta = 0.1: P_H %.2f GPa, the isentrope %.3f GPa below (%.1f %%)'
   % (PH(mat, V), dP, 100*dP/PH(mat, V)), dP/PH(mat, V) < M('0.01'))

#*** 5. bitwhiz's Hugoniot with curvature, U_s = C0 + S1 up + (S2/C0) up^2,
#     in eta = up/U_s: U_s(eta) = 2 C0/((1 - S1 eta) + sqrt((1 - S1 eta)^2
#     - 4 S2 eta^2)) (module eos, mg_ref): the root that gives C0 at eta = 0.
S2s, et = sp.symbols('S2 eta', real=True)
C0s, S1s = sp.symbols('C0 S1', positive=True)
Ue = 2*C0s/((1 - S1s*et) + sp.sqrt((1 - S1s*et)**2 - 4*S2s*et**2))
res = Ue - (C0s + S1s*et*Ue + (S2s/C0s)*(et*Ue)**2)
for vals in ({C0s: 2.5, S1s: 1.8, S2s: -0.1}, {C0s: 5.3, S1s: 1.34, S2s: 0},
             {C0s: 3.0, S1s: 1.5, S2s: 0.2}):
    for ev in (0.0, 0.1, 0.25, 0.4):
        assert abs(sp.N(res.subs(vals).subs(et, ev))) < 1e-12, (vals, ev)
ok('U_s(eta) of mg_ref solves U_s = C0 + S1 up + (S2/C0) up^2, up = eta U_s')
ok('U_s(0) = C0', sp.simplify(Ue.subs(et, 0) - C0s) == 0)

#*** 6. The lead-shock detector's residual (chapter 8, eq. hugoniot-q):
#     inside a steady smeared shock, P0 = e0 = 0, H = e - (V0 - V) P/2
#     = q (V0 - V)/2, from section 2 above with P = P_R - q.
Hres = (ex - (V0 - Vx)*(PR - q)/2).subs({P0: 0, e0: 0})
zero('inside: H = e - (V0 - V) P/2 = q (V0 - V)/2', Hres - q*(V0 - Vx)/2)

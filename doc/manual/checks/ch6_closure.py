"""Chapter 6's closure, symbolically (sympy): every closed form in
ch6_burning_cell.tex derived from the definitions, for a generic Pi(rho).
Run: python3 doc/manual/checks/ch6_closure.py  (prints 'ok' per check)."""
import sympy as sp
rho, e, lam, R0, G0, Cv, T0, gam, Q = sp.symbols(
    'rho e lambda rho_0 Gamma_0 C_V T_0 gamma Q', positive=True)
Pi = sp.Function('Pi')(rho)            # the volume-only part of Mie-Gruneisen
eS = sp.Function('e_S')(rho)           # isentrope from rest
eta = 1 - R0/rho
TS = T0*sp.exp(G0*eta)
# isentrope: de_S/drho = P_sol(rho, e_S)/rho**2
deS = (R0*G0*eS + Pi)/rho**2
def D(expr):                            # d/drho with the isentrope's slope
    return sp.diff(expr, rho).subs(sp.Derivative(eS, rho), deS)
ec = eS - Cv*TS                         # e_c, the T = 0 energy
Pc = R0*G0*ec + Pi                      # P_c, the T = 0 pressure
ok = lambda c, name: print(('ok  ' if sp.simplify(c) == 0 else 'FAIL') + ' ' + name)

# 1. P_c as the sheet writes it: P_sol(rho, e_S) - R0 G0 C_V T_S
ok(Pc - ((R0*G0*eS + Pi) - R0*G0*Cv*TS), 'P_c = P_sol(e_S) - rho0 G0 Cv T_S')
# 2. T of the solid: e_sol = e_S + Cv (T - T_S)  <=>  e_sol = e_c + Cv T
T = sp.symbols('T')
ok((eS + Cv*(T - TS)) - (ec + Cv*T), 'e_sol = e_c + vartheta')
# 3. d e_c/drho = P_c/rho**2
ok(D(ec) - Pc/rho**2, 'de_c/drho = P_c/rho^2')
# 4. vartheta from the energy line
th = sp.symbols('vartheta')
emix = (1 - lam)*(ec + th) + lam*(th - Q)
thsol = sp.solve(sp.Eq(e, emix), th)[0]
ok(thsol - (e - (1 - lam)*ec + lam*Q), 'vartheta = e - (1-lam) e_c + lam Q')
# 5. P of the mixture, solid in
Psl = Pc + R0*G0*thsol                  # P_sol at (rho, e_c + vartheta)
Pg = (gam - 1)*rho*thsol
P = (1 - lam)*Psl + lam*Pg
ok(sp.expand(Psl - (R0*G0*(ec + thsol) + Pi)), 'P_sol = P_c + rho0 G0 vartheta')
# limits
ok(P.subs(lam, 0) - (R0*G0*e + Pi), 'lam = 0: Mie-Gruneisen at (rho, e)')
ok(P.subs(lam, 1) - (gam - 1)*rho*(e + Q), 'lam = 1: (gamma-1) rho (e + Q)')
# 6. c**2 = (dP/drho)_e + P/rho**2 (dP/de)_rho, solid in
c2 = D(P) + P/rho**2*sp.diff(P, e)
es_ = sp.symbols('e_s')                 # inert MG c**2 at (rho, e_s)
c2_inert = sp.diff(R0*G0*es_ + Pi, rho) + (R0*G0*es_ + Pi)/rho**2*R0*G0
csol2 = c2_inert.subs(es_, ec + thsol)
cg2 = gam*(gam - 1)*thsol
claim = (1 - lam)*csol2 + lam*cg2 - lam*(1 - lam)*(R0*G0/rho - gam + 1)**2*thsol
ok(sp.simplify(sp.expand(c2 - claim)), 'c^2 exact, solid in')
# 7. dP/dlam at fixed rho, e, solid in
dPdl = sp.diff(P, lam)
claim = -Psl + Pg + ((1 - lam)*R0*G0 + lam*(gam - 1)*rho)*(ec + Q)
ok(sp.expand(dPdl - claim), 'dP/dlam, solid in')
# 8. Solid dropped: P = lam P_gas
Pd = lam*Pg
c2d = D(Pd) + Pd/rho**2*sp.diff(Pd, e)
claim = lam*(gam - 1)*(thsol*(1 + lam*(gam - 1)) - (1 - lam)*Pc/rho)
ok(sp.expand(c2d - claim), 'c^2, solid dropped')
ok(sp.expand(sp.diff(Pd, lam) - (Pg + lam*(gam - 1)*rho*(ec + Q))), 'dP/dlam, solid dropped')
# 9. Solid held at (rh, esh): e_c fixed there, P_sol at rh
rh, esh, s = sp.symbols('rho_h e_Sh s')
ech = esh - Cv*T0*sp.exp(G0*(1 - R0/rh))
thh = e - (1 - lam)*ech + lam*Q
Pslh = R0*G0*(ech + thh) + Pi.subs(rho, rh)
Ph = s*(1 - lam)*Pslh + lam*(gam - 1)*rho*thh
c2h = sp.diff(Ph, rho) + Ph/rho**2*sp.diff(Ph, e)
claim = lam*(gam - 1)*thh + Ph/rho**2*(s*(1 - lam)*R0*G0 + lam*(gam - 1)*rho)
ok(sp.expand(c2h - claim), 'c^2, solid held (s = 1 pushing, 0 dropped)')
# 10. held and dropped: d vartheta = -(P/rho^2)... adiabatic expansion at fixed lam:
#     de = P drho/rho^2, P = lam (gam-1) rho vartheta, e_c fixed
#     => dvartheta/drho = lam (gam-1) vartheta / rho: vartheta ~ rho**(lam (gam-1))
ok(sp.simplify(sp.diff(thh, e)*(lam*(gam - 1)*rho*thh)/rho**2
               - lam*(gam - 1)*thh/rho), 'held, dropped: vartheta ~ rho^(lam(gam-1))')
# 11. Constant-volume burn of Material X: (gamma-1) rho0 Q
ok((sp.Rational(26, 10) - 1)*sp.Rational(16, 10)*sp.Rational(48828, 10000)
   - sp.Rational(12499968, 1000000), 'Material X burnt at rest: 12.499968 GPa')
# 12. ThermalCascade at constant volume: dvartheta/dlam = e_c + Q
ok(sp.diff(thsol, lam) - (ec + Q), 'constant volume: dvartheta/dlam = e_c + Q')

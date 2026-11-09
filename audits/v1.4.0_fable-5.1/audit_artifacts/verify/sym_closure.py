#!/usr/bin/env python3
"""Independent symbolic derivation of the mixture closure's sound speed and
dP/dlam (bitwhiz mix_mod.f95), for a GENERIC volume function Pi(rho).

P(rho, e, lam) = (1-lam) P_sol + lam P_gas
  ecs(rho)  = e_S(rho) - cv T0 exp(G0 eta),  eta = 1 - R0/rho
  e_S'(rho) = P_S/rho^2  (isentrope from rest), P_S = R0 G0 e_S + Pi
  theta     = e - (1-lam) ecs + lam Q
  P_sol     = R0 G0 (ecs + theta) + Pi(rho)
  P_gas     = (gamma-1) rho theta
c^2 = (dP/drho)_e + (P/rho^2)(dP/de)_rho   (fixed lam)

Checks the code's closed forms:
 (A) solid in:   c^2 = (1-lam) c_sol^2 + lam c_gas^2 - lam(1-lam)(R0G0/rho - gamma + 1)^2 theta
     with c_sol^2 = (dP_sol/drho)_e_sol + (P_sol/rho^2) R0 G0, evaluated at e_sol = ecs + theta
 (B) solid dropped: c^2 = lam g1 [ theta (1 + lam g1) - (1-lam) P_c / rho ],  P_c = R0 G0 ecs + Pi
 (C) held (solid terms at fixed rhold, d ecs/drho = 0), pushing:
     c^2 = lam g1 theta + (P/rho^2) [ (1-lam) R0 G0 + lam g1 rho ]
 (D) held, dropped: c^2 = lam g1 theta (1 + lam g1)
 (E) dP/dlam solid in:  -P_sol + P_gas + [(1-lam) R0 G0 + lam g1 rho] (ecs + Q)
     dP/dlam dropped:            P_gas + lam g1 rho (ecs + Q)
"""
import sympy as sp

rho, e, lam, R0, G0, cv, T0, gam, Q = sp.symbols('rho e lam R0 G0 cv T0 gamma Q', positive=True)
Pi = sp.Function('Pi')(rho)          # generic volume-only pressure
eS = sp.Function('eS')(rho)          # generic isentrope energy, with eS' = P_S/rho^2
g1 = gam - 1
eta = 1 - R0/rho
TS = T0*sp.exp(G0*eta)
ecs = eS - cv*TS
theta = e - (1-lam)*ecs + lam*Q
Psol = R0*G0*(ecs + theta) + Pi
Pgas = g1*rho*theta
PS = R0*G0*eS + Pi                   # the isentrope's pressure
sub_eS = {sp.Derivative(eS, rho): PS/rho**2}

def c2_of(P):
    dPdr = sp.diff(P, rho).subs(sub_eS)
    dPde = sp.diff(P, e)
    return sp.simplify(dPdr + P/rho**2*dPde)

# (A) solid in
P_in = (1-lam)*Psol + lam*Pgas
c2_in = c2_of(P_in)
# c_sol^2 at (rho, e_sol) with e_sol = ecs + theta held as an independent e:
esol = sp.symbols('esol')
Psol_e = R0*G0*esol + Pi
c2_sol = (sp.diff(Psol_e, rho) + Psol_e/rho**2*R0*G0).subs(esol, ecs + theta)
c2_gas = gam*g1*theta
claimA = (1-lam)*c2_sol + lam*c2_gas - lam*(1-lam)*(R0*G0/rho - gam + 1)**2*theta
print('A solid-in c^2 closed form matches:', sp.simplify((c2_in - claimA).subs(sub_eS)) == 0)

# (B) solid dropped (not held): P = lam Pgas
P_dr = lam*Pgas
c2_dr = c2_of(P_dr)
Pc = R0*G0*ecs + Pi
claimB = lam*g1*(theta*(1 + lam*g1) - (1-lam)*Pc/rho)
print('B dropped c^2 closed form matches:', sp.simplify((c2_dr - claimB).subs(sub_eS)) == 0)

# (C), (D): held. ecs is a constant (rhold fixed) -> treat ecs as a symbol independent of rho;
# Psol at rhold depends on e only: Psol_h = R0 G0 (ecs_h + theta) + Pi_h  (Pi_h const)
ecs_h, Pi_h = sp.symbols('ecs_h Pi_h')
theta_h = e - (1-lam)*ecs_h + lam*Q
Psol_h = R0*G0*(ecs_h + theta_h) + Pi_h
Pgas_h = g1*rho*theta_h
P_hp = (1-lam)*Psol_h + lam*Pgas_h
c2_hp = sp.simplify(sp.diff(P_hp, rho) + P_hp/rho**2*sp.diff(P_hp, e))
claimC = lam*g1*theta_h + (P_hp/rho**2)*((1-lam)*R0*G0 + lam*g1*rho)
print('C held-pushing c^2 matches:', sp.simplify(c2_hp - claimC) == 0)
P_hd = lam*Pgas_h
c2_hd = sp.simplify(sp.diff(P_hd, rho) + P_hd/rho**2*sp.diff(P_hd, e))
claimD = lam*g1*theta_h*(1 + lam*g1)
print('D held-dropped c^2 matches:', sp.simplify(c2_hd - claimD) == 0)

# (E) dP/dlam at fixed rho, e
dPdl_in = sp.diff(P_in, lam)
claimE1 = -Psol + Pgas + ((1-lam)*R0*G0 + lam*g1*rho)*(ecs + Q)
print('E dP/dlam solid-in matches:', sp.simplify(dPdl_in - claimE1) == 0)
dPdl_dr = sp.diff(P_dr, lam)
claimE2 = Pgas + lam*g1*rho*(ecs + Q)
print('E dP/dlam dropped matches:', sp.simplify(dPdl_dr - claimE2) == 0)

# Sanity: the sheet's statement that the closure equals the T-based mixture
T = sp.symbols('T')
e_sol_T = eS + cv*(T - TS)
e_gas_T = cv*T - Q
e_mix = (1-lam)*e_sol_T + lam*e_gas_T
T_sol = sp.solve(sp.Eq(e_mix, e), T)[0]
print('closure theta = cv*T solves energy line:', sp.simplify(cv*T_sol - theta) == 0)

# Limiting checks
print('lam=0 -> P_sol(rho,e):', sp.simplify(P_in.subs(lam, 0) - (R0*G0*e + Pi)) == 0)
print('lam=1 -> (gam-1) rho (e+Q):', sp.simplify(P_in.subs(lam, 1) - g1*rho*(e + Q)) == 0)

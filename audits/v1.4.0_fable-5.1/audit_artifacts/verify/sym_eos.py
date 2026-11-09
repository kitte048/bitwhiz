#!/usr/bin/env python3
"""Independent symbolic check of eos_mod.f95 (Mie-Gruneisen on the principal
Hugoniot, rho*Gamma = R0*G0), from the sheet's definitions:

  Us = C0 + S1 up + (S2/C0) up^2,  up = eta Us,  eta = 1 - V/V0
  P_H = R0 eta Us^2,  e_H = up^2/2
  P(V,e) = P_H + R0 G0 (e - e_H) = R0 G0 e + phi(V),  phi = P_H - R0 G0 e_H
  c^2 = -V^2 (dP/dV)_S,  de = -P dV on an isentrope.
Also: the expansion cubic's coefficients a1, a2, a3 should make phi(x),
x = rho - R0, and its first three x-derivatives match the compression form at
x = 0 (C^3 continuity, as the header claims).
"""
import sympy as sp

eta, C0, S1, S2, R0, G0, e = sp.symbols('eta C0 S1 S2 R0 G0 e', positive=True)
# Us as a root of Us = C0 + S1 eta Us + (S2/C0) eta^2 Us^2 (the sheet)
a = 1 - S1*eta
xi = sp.sqrt(a**2 - 4*S2*eta**2)
Us_code = 2*C0/(a + xi)
Us = sp.symbols('Us')
root_eq = sp.Eq(Us, C0 + S1*eta*Us + (S2/C0)*eta**2*Us**2)
print('Us_code satisfies the Us-up relation:',
      sp.simplify(root_eq.lhs.subs(Us, Us_code) - root_eq.rhs.subs(Us, Us_code)) == 0)
print('Us_code -> C0 as eta -> 0:', sp.limit(Us_code, eta, 0) == C0)
# S2 = 0 branch: Us = C0/(1 - S1 eta)
print('S2=0 branch = C0/(1-S1 eta):', sp.simplify(Us_code.subs(S2, 0) - C0/(1 - S1*eta)) == 0)

# dUs/deta as coded
dus_code = 2*C0*(S1 + (S1 - S1**2*eta + 4*S2*eta)/xi)/(a + xi)**2
print('dUs/deta closed form matches:', sp.simplify(sp.diff(Us_code, eta) - dus_code) == 0)

# phi(eta) and its V-derivative. V = (1 - eta)/R0, dV/deta = -1/R0
V = (1 - eta)/R0
PH = R0*eta*Us_code**2
eH = (eta*Us_code)**2/2
phi = PH - R0*G0*eH
dphi_dV = sp.diff(phi, eta)/sp.diff(V, eta)        # chain rule
# code: dph_dv = -R0^2 (Us^2 + 2 eta Us Us'); deh_dv = 1/2 ((eta/R0) dph_dv - ph); phip = dph_dv - R0 G0 deh_dv
dph_dv_code = -R0**2*(Us_code**2 + 2*eta*Us_code*dus_code)
deh_dv_code = sp.Rational(1, 2)*((eta/R0)*dph_dv_code - PH)
phip_code = dph_dv_code - R0*G0*deh_dv_code
print('dP_H/dV closed form matches:', sp.simplify(sp.diff(PH, eta)/sp.diff(V, eta) - dph_dv_code) == 0)
print('de_H/dV identity matches:', sp.simplify(sp.diff(eH, eta)/sp.diff(V, eta) - deh_dv_code) == 0)
print("phi' closed form matches:", sp.simplify(dphi_dV - phip_code) == 0)

# Sound speed: along an isentrope P(V, e(V)) with de/dV = -P
Vs = sp.symbols('V', positive=True)
phiV = sp.Function('phi')(Vs)
P = R0*G0*e + phiV
dPdV_S = sp.diff(P, Vs) + sp.diff(P, e)*(-P)
c2 = -Vs**2*dPdV_S
print("c^2 = V^2 (R0 G0 P - phi'):", sp.simplify(c2 - Vs**2*(R0*G0*P - sp.diff(phiV, Vs))) == 0)

# Expansion cubic: C^3 continuity at x = 0 (x = rho - R0)
x = sp.symbols('x', real=True)
rho = R0 + x
eta_x = (rho - R0)/rho
phi_comp_x = phi.subs(eta, eta_x)
a1 = C0**2
a2 = (C0**2/R0)*(4*S1 - 2 - G0)
a3 = (6*C0**2/R0**2)*(3*S1**2 - 4*S1 - G0*S1 + G0 + 2*S2 + 1)
phi_cub = a1*x + a2*x**2/2 + a3*x**3/6
for n in range(0, 4):
    d_comp = sp.limit(sp.diff(phi_comp_x, x, n), x, 0) if n > 0 else phi_comp_x.subs(x, 0)
    d_cub = sp.diff(phi_cub, x, n).subs(x, 0)
    print(f'  d^{n}phi/dx^{n} at V0: compression == cubic:', sp.simplify(d_comp - d_cub) == 0)
# phi' in expansion: dphi/dV = dphi/dx * dx/dV, x = 1/V - R0 -> dx/dV = -1/V^2 = -rho^2
phip_cub_code = -rho**2*(a1 + x*(a2 + a3*x/2))
print("expansion phi' matches:", sp.simplify(sp.diff(phi_cub, x)*(-(R0 + x)**2) - phip_cub_code) == 0)
# K0' of a linear Us-up fit is 4 S1 - 1 (header remark): B' = 4 s - 1
print('header remark: a2 = (C0^2/R0)(K0p - 1 - G0) with K0p = 4 S1 - 1:',
      sp.simplify(a2 - (C0**2/R0)*((4*S1 - 1) - 1 - G0)) == 0)

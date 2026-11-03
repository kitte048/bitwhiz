# eos_tool

How the reference code behind G1 computes temperature, measured from its own
EOS tool: why its Material X temperatures are 0.9-4.6 K above bitwhiz's, and
where G1's 298.0014 K start comes from. A record, closed Nov 3, 2026: bitwhiz
is verified against its own standard (`doc/design/materials.md`,
"Temperature verification"), not against this tool.

## The data
`g1_eos_tool_results.dat`: D. E. Kittell's EOS testing tool (the reference
code's EOS), queried Nov 3, 2026, with the G1 materials' constants (Material
X with Q = 0, and PMMA; T0 = 298 K). Eight sweeps of 13 densities each,
eta = 1 - rho0/rho = -0.08 to 0.40 in steps of 0.04:

| Run | T (K) | C_V (erg/(g eV)) |
|---|---|---|
| A | 298 | 1.35e11 |
| B | 1000 | 1.35e11 |
| C | 298 | 2.70e11 |
| D | 1000 | 2.70e11 |

Columns: RHO (g/cm^3), T (K), P (GPa), E (MJ/kg = kJ/g), S (not computed:
0), CS (km/s), BT (GPa), CV (MJ/(kg K)), VOL (cm^3/g), A (= E here). The
tool works in single precision (about 7 digits: rho = 1.4814814).

## What it shows
With C_V constant, e = A(rho) + C_V (T - B(rho)) at each density, so the
runs separate the cold curve A from the thermal reference B. Then:

- **rho Gamma = rho0 G0** at every density.
- **Compression (eta >= 0):** e = e_c(eta) + C_V T0 + C_V (T - T0 exp(G0
  eta)), and P = Pi(eta) + rho0 G0 (e - C_V T0*). This is bitwhiz's
  convention (the principal isentrope; reference temperatures within
  0.0007 K), with the energy's zero shifted by C_V T0 (0.3467 MJ/kg).
  Pi is bitwhiz's, from the Hugoniot, to 5e-6 GPa for both materials.
- **G1's 298.0014 K:** T0* = 298.0013-298.0014 K in the pressure, against
  298 K in the energy's shift. A run that starts at P = 0 starts at
  298.0014 K. (Two different eV-to-K factors would do it: 11604.45 against
  11604.5 gives 0.0013 K. Not confirmed.)
- **The cold energy:** PMMA's is the integral of its pressure, to 1.6e-6
  MJ/kg (0.0014 K). Material X's is not: tool minus exact, in K, +0.01,
  +0.05, +0.03, -0.27, -1.13, -2.71, -4.57, -4.72, +1.75, +23.8 at eta =
  0.04 to 0.40. That difference, at each first-shock eta, is G1's Material
  X offset:

  | u_fly (km/s) | from the tool | G1 (5 and 9 mm) |
  |---|---|---|
  | 1.00 | -0.877 K | -0.880, -0.878 |
  | 1.25 | -1.778 K | -1.778, -1.777 |
  | 1.50 | -2.802 K | -2.800, -2.808 |
  | 1.75 | -3.793 K | -3.793, -3.789 |
  | 2.00 | -4.575 K | -4.573, -4.577 |

  (bitwhiz's formula minus G1's TK; bitwhiz's formula is the exact
  integral.) It appears with S2 /= 0 only, and it is not a polynomial of
  degree 5 in eta, rho/rho0 - 1 or V (the best leaves 2e-4 MJ/kg against
  3e-7 of noise); likely an interpolant. Not pursued: bitwhiz uses the
  exact cold curve.
- **Tension (eta < 0):** a separate, linearized model, fitting both
  densities in all four runs to about 1e-7: P = rho0 C0^2 eta + rho0 G0
  C_V (T - T0 (1 + G0 eta)), e = C_V T0 + C0^2 eta^2/2 + C_V (T - T0 (1 +
  G0 eta + (G0 eta)^2/2)). bitwhiz uses its cubic there (module eos), so
  releases into tension differ by design.

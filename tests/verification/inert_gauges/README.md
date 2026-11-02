# inert_gauges
Gold-standard reference tracer histories for the ME 697 double-shock problem with
Material X **inert** (set G1 of the HVRB gold-standard dataset), computed by DK
(Oct 30, 2026) with an independent Eulerian hydrocode. As in `../README.md`, the
reference code is deliberately not named here.

The files are copied byte for byte from the course folder,
`Equation_Sheets/HVRB_rev-0/verification/` (`SHA256SUMS` here checks them);
that folder's README holds the derived results, and
`Equation_Sheets/HVRB_rev-0/GOLD_STANDARD_DATASET.md` the run plan. Not exported to nanoHUB (`src/utils/export_nanohub.sh`).

| File | Flyer velocity | P1 exact (impedance match) | U_S exact |
|---|---|---|---|
| `G1_inert_1p00_kmps.dat` | 1.00 km/s | 4.371 GPa | 3.780 km/s |
| `G1_inert_1p25_kmps.dat` | 1.25 km/s | 5.793 | 4.070 |
| `G1_inert_1p50_kmps.dat` | 1.50 km/s | 7.331 | 4.351 |
| `G1_inert_1p75_kmps.dat` | 1.75 km/s | 8.979 | 4.625 |
| `G1_inert_2p00_kmps.dat` | 2.00 km/s | 10.736 | 4.893 |

## Problem
The class stack, as in `../README.md`: Ta 3.0 mm | Al 4.0 mm (both at the flyer
velocity) -> Material X 10.0 mm -> PMMA 10.0 mm, project rev-0 Table 1 EOS
(Mie-Gruneisen on the principal Hugoniot, Gamma rho = Gamma_0 rho_0). t = 0 at
impact, x = 0 at the Al/Material X impact plane, planar, 1 cm^2. 100 zones/mm,
remap energy fix-up on. Temperature: C_V = 1.163 J/(g K) (1.35e11 erg/(g eV)),
T_0 = 298 K.

## Tracers (Lagrangian), x0 in mm
| # | x0 | Where |
|---|---|---|
| 1 | -3.999 | Al side of Ta:Al (interface: u only) |
| 2 | 0.001 | Material X side of the impact plane (interface: u only) |
| 3-11 | 1, 2, ..., 9 | inside Material X, every 1 mm |
| 12 | 9.999 | Material X side of Material X:PMMA, the PDV node (interface: u only) |
| 13 | 11.0 | inside PMMA |

## Format
As `../README.md` (comma-separated; line 1 names, line 2 units; a row about
every 5 ns to 6.5 us; interpolate on TIME), with more per tracer n:
XPOS.n (cm), MJKG.n (MJ/kg: written, but zero in every file), DENS.n (g/cm^3),
TK.n (K), KMPS.n (km/s), GPA.n (GPa).

## Notes for comparison
- **Interface tracers sample mixed cells** (the code is Eulerian): their u is
  good, their P, rho and T are mixtures. Use tracers 3-11 and 13 for those.
- **Trust window:** total mass is constant until material leaves the mesh,
  6.5 us at 1.00 and 1.25 km/s down to 5.2 us at 2.00 km/s; total energy is
  conserved to 0.006 % before that.
- This code allows tension (no P >= 0 floor, no spall); late-time releases in
  bitwhiz will differ.
- **Compare derived quantities, not traces point by point** (the codes differ:
  Eulerian against Lagrangian). Suggested acceptance at 100 zones/mm: the
  first-shock P and u at 1 mm within 0.1 %; arrivals (first u > 0.05 km/s,
  interpolated) before the Ta reshock, and the PDV arrival, within 5 ns; total
  energy drift within 0.01 % before outflow.

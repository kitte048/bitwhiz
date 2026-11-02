# hvrb
Gold-standard reference tracer histories for Material X with the **HVRB** burn
model (sets G2-G5 of the HVRB gold-standard dataset), computed by DK (Oct 30,
2026) with an independent Eulerian hydrocode, not named here. The reference for
bitwhiz once it has a burn model (TODO.md, sections 3 and 6); the inert set G1 is
in `../inert_gauges/`.

The files are copied byte for byte from the course folder,
`Equation_Sheets/HVRB_rev-0/verification/` (`SHA256SUMS` here checks them);
that folder's README holds the derived results (run distances, the Pop plot,
D_CJ). Not exported to nanoHUB (`src/utils/export_nanohub.sh`). Material X and
its HVRB parameters are notional.

| Files | Set | Case | Stack | u_fly (km/s) |
|---|---|---|---|---|
| `G2_react_<v>_kmps.dat` (5) | G2 | HVRB | class | 1.00, 1.25, 1.50, 1.75, 2.00 |
| `G3_poplt_<v>_kmps.dat` (5) | G3 | HVRB, single shock (Pop plot) | thick flyer | 1.25, 1.50, 1.75, 2.00, 2.25 |
| `G4_wavsp_3p00_kmps.dat` | G4 | HVRB, detonation speed | thick flyer | 3.00 |
| `G5_react_2p00_kmps_<z>_zpmm.dat` (4) | G5 | HVRB, mesh study | class | 2.00, at 25, 50, 200, 400 zones/mm |

`<v>` is the flyer velocity with `p` for the decimal point. All runs are at 100
zones/mm except G5 (its 100 zones/mm member is `G2_react_2p00_kmps.dat`).

## Problem
- **Class stack** (G2, G5): Ta 3.0 mm | Al 4.0 mm -> Material X 10.0 mm -> PMMA
  10.0 mm, as `../README.md`.
- **Thick flyer** (G3, G4): Al 20 mm (at u_fly) -> Material X 20 mm -> PMMA 4 mm.
  No Ta.
- x = 0 at the Al/Material X impact plane; planar, 1 cm^2; remap energy fix-up on.

## Model (all files)
| Item | Setting |
|---|---|
| Reactant | project rev-0 Table 1 Mie-Gruneisen, Gamma rho = Gamma_0 rho_0, with an energy shift +Q, Q = 4.8828 MJ/kg |
| Products | ideal gas, P = (gamma - 1) rho C_V T, gamma = 2.60, energy zero at T = 0 K |
| Both phases | C_V = 1.163 J/(g K) (1.35e11 erg/(g eV)), T_0 = 298 K |
| Closure | density-temperature equilibrium (both phases at the cell's rho and one T) |
| HVRB | P_R 7.0 GPa, Z_R 3.0, M_R 1.5, X_R 2.5, P_I 1.0 GPa, tau_0 1 us |

Exact references: D_CJ = 7.4999904 km/s, P_CJ = 24.999936 GPa,
u_CJ = 2.0833307 km/s, rho_CJ = 2.2153846 g/cm^3. The dataset's README cites
`HVRB_Eqns_v3.tex` for the model; check these parameters against the sheet
bitwhiz follows before using the data (TODO.md, section 3).

## Tracers (Lagrangian), x0 in mm
| Set | Tracers |
|---|---|
| G2, G5 | -3.999 (Ta:Al), 0.001 (impact plane), 1, 2, ..., 9, 9.999 (PDV node), 11 (PMMA) |
| G3 1.25, 1.50 | 0.001, 1, 2, ..., 18, 19.999 (every 1 mm) |
| G3 1.75, 2.00 | 0.001, 0.5, 1.0, ..., 10.0 (every 0.5 mm) |
| G3 2.25 | 0.001, 0.25, 0.5, ..., 5.0 (every 0.25 mm) |
| G4 | 10.00, 10.25, ..., 20.00 (every 0.25 mm; positions only) |

Tracers at an interface sample mixed cells: use their u only.

## Format
As `../inert_gauges/README.md`, plus XRN3.n (reaction progress, lambda) per
tracer. A row about every 5 ns; G4 about every 1 ns and XPOS only (an arrival is
when a tracer starts to move). MJKG is written, but zero in every file.

## Notes for comparison
- **Trust window** (total mass constant until material leaves the mesh): G2 and
  G5 6.0 us (1.00 km/s) down to 4.6 us (2.00 km/s); G3 4.0 us (1.25, 1.50) down
  to 3.6 us (2.25); G4 3.5 us.
- 5 ns output resolves arrivals and plateaus, not spikes or the reaction zone
  (about 19 ns long).
- **Decide "detonated or not" from the shock trajectory, never from PDV
  amplitude:** at 1.00 and 1.25 km/s the burn behind an unreacted front still
  reaches the window as a strong, late wave.
- Suggested acceptance at 100 zones/mm: run distance within one tracer
  spacing; detonation speed (G4) within 0.5 % of D_CJ; arrivals and the PDV
  arrival within 5 ns.

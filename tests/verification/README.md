# verification
Reference tracer histories for the ME 697 double-shock problem, computed with an
independent commercial hydrocode (DK, Oct 2026). bitwhiz results are compared
against these.

| File | Flyer velocity |
|---|---|
| `ME697_1p00_kmps.dat` | 1.00 km/s |
| `ME697_1p25_kmps.dat` | 1.25 km/s |
| `ME697_1p50_kmps.dat` | 1.50 km/s |
| `ME697_1p75_kmps.dat` | 1.75 km/s |
| `ME697_2p00_kmps.dat` | 2.00 km/s |

## Problem
Ta 3.0 mm | Al 4.0 mm (flyer, both at the flyer velocity) -> Material X 10.0 mm |
PMMA 10.0 mm, project rev-0 Table 1 EOS. t = 0 at impact. Planar, 1 cm^2.

## Tracers (Lagrangian), x0 in cm, x = 0 at the Al/Material X impact plane
| # | x0 (cm) | Where |
|---|---|---|
| 1 | -0.55 | Ta mid-plane |
| 2 | -0.20 | Al mid-plane |
| 3 | +0.50 | Material X mid-plane |
| 4 | +1.00 | Material X / PMMA interface (the PDV signal) |
| 5 | +1.50 | PMMA mid-plane |

## Format
Comma-separated text. Line 1: column names; line 2: column units; then one row
about every 5 ns to 6.5 us (the output times are not exactly uniform, so
interpolate on the TIME column). Mixed units, as the code writes them:
- TIME and DTIME in s; MTOT in g; ETOT, EK, EINT in erg; VTOT in cm^3;
  XMOM in g-cm/s (whole problem, per 1 cm^2)
- for each tracer n: XPOS.n (cm), KMPS.n (velocity, km/s), GPA.n (pressure, GPa)

## Notes for comparison
- Trust the data to about 5 us. Between about 5.1 us (2.00 km/s) and 6.0 us
  (1.00 km/s) the release from the PMMA back face reaches the interface and
  re-accelerates it; from about 5.2 to 6.1 us (1.50-2.00 km/s) material also
  leaves the computational domain (MTOT and ETOT drop).
- This code allows tension (negative pressures in the Ta and PMMA). bitwhiz
  floors P at 0 (project Sec. 3), so late-time releases will differ.
- TODO (DK): record the code name/version, EOS options (S2 form; constant
  Gamma or rho*Gamma), mesh size and artificial viscosity settings.

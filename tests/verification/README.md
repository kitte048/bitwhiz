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
- The reference code is deliberately not named here.

## Reading them
`gold.py` here reads any of these files (and those in the subfolders) and
computes the quantities bitwhiz is compared on, with the gold-standard
dataset's definitions; run it to check it against that dataset's published
results (Python 3 and NumPy; not part of `make test`):

    python3 tests/verification/gold.py

`compare_g1.py` runs bitwhiz on `inert_gauges/g1_inert.deck` at the five
velocities and checks it against the inert set G1 with the same code (after
`make release`; about 15 s):

    python3 tests/verification/compare_g1.py

`compare_hvrb.py` runs bitwhiz with Material X burning (HVRB, the reference's
model) on the reactive sets G2-G5, with `hvrb/g2_react.deck` (the class stack:
G2, and G5's mesh study) and `hvrb/g3_poplt.deck` (the thick flyer: G3's runs
to detonation and G4's detonation speed), and checks run distance, arrivals,
D and convergence with the data's own definitions and tolerances (its
docstring has the list; about 10 minutes on 2 cores; `--quick` leaves out the
200 and 400 zones/mm runs, `--rs` runs method RS):

    python3 tests/verification/compare_hvrb.py

`study_av.py` measures what method AV does at a detonation and at a free
surface, against mesh, beside RS order 2 and exact answers: G4's detonation
and the class deck (a weak detonation on a coarse mesh, converging), a
square shock reaching a free surface (`av_study/fs_square.deck`: AV's 6 %
transient, converging in its integral), and a partly burnt free surface
(`av_study/burn_release.deck`: the end cell's temperature). Its checks are
of convergence (regression guards, set from the Nov 5 runs); the results
are in `doc/design/av_study.md` (about 15 minutes on 2 cores, `--quick`
about 2; needs mpmath too):

    python3 tests/verification/study_av.py

`study_leadshock.py` checks the lead-shock detector (module `leadshock`, for
the burn models that need the lead shock's pressure) on real runs, before any
model uses it: each run writes its tracers every cycle, and `bin/ls_replay`
(`ls_replay.f95`, built by `make ls_replay`) steps the detector through a
tracer's rows exactly as module `burn` will step a cell. Square shocks of
known strength, 0.75 to 78 GPa (`av_study/fs_square.deck`: P_s against the
exact Hugoniot), a ramp (`input/ramp_linear.deck`: its smooth foot, and the
shock it steepens into), a decaying shock (`leadshock/decay.deck`, a thin
flyer), AV and RS, 25 to 200 zones/mm; and, with an independent Python twin
of the detector, the range of its floor and stall constants that work. The
results are in `doc/design/burn_models.md`, "As built: step 4" (about a
minute on 2 cores, `--quick` 20 s):

    python3 tests/verification/study_leadshock.py

## Gold-standard sets (subfolders)
- `inert_gauges/`: the same problem, Material X inert, with 13 tracers (every
  1 mm through Material X) and density and temperature: set G1.
- `hvrb/`: Material X with the HVRB burn model, sets G2-G5, the reference for a
  burn model.

Both come from the same independent code (Oct 30, 2026), byte for byte, each
with its own README and `SHA256SUMS`. Neither is exported to nanoHUB.

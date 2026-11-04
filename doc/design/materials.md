# Material models: design note

Started Nov 3, 2026, on `shock` after `f81f2b7` (movies). Status: **approved
Nov 3, 2026** (decisions below); phase 2 built Nov 3 (As built, below). TODO.md, sections 5 and 6, is
the brief: room in the code for more than one material model, Mie-Grüneisen
kept as the default and unchanged, bit for bit; the first new model is
Mie-Grüneisen with temperature, so that G1's temperatures can be compared;
HVRB and graded constants later. The temperature calculation is D. E.
Kittell's (Nov 3, 2026); the per-cell method ("plan C") was settled the same
day.

## The idea

Every material has one equation of state, and may have add-ons on top of it.

- **The equation of state** gives P and c from (rho, e). Today there is one,
  Mie-Grüneisen on the principal Hugoniot with rho Gamma = R0 G0 (`eos_mod`,
  `mg_eos`). A material that names no other gets it, read and computed
  exactly as now.
- **Add-ons** (later) change what a cell carries, not what its EOS is: a burn
  (`burn = hvrb`, with its own keys and a reaction progress per cell), a rate
  law if a burn takes more than one, strength.
- **The first new model is the default one, plus temperature:**
  `eos = mie_gruneisen_t`. Its pressure and sound speed are Mie-Grüneisen's,
  the same code, the same bits; it also carries T. In this model P does not
  depend on T (below), so T is a diagnostic now, and becomes an input when
  HVRB's density-temperature closure needs it.

Why temperature first: it is the smallest real model (two numbers per cell,
no change to P), the G1 gold-standard data has T at every gauge to check it
against, and HVRB needs it.

## The deck

```
Begin Material MatX
  eos = mie_gruneisen_t        # Mie-Grüneisen, plus temperature
  R0  = 1.60
  C0  = 2.50
  S1  = 1.80
  S2  = -0.10
  G0  = 1.20
  CV  = 1.1633418              # J/(g K), constant
  T0  = 298.0                  # K, at R0 and e = 0
End Material
```

| Key | Type | Default | Notes |
|---|---|---|---|
| `eos` | `mie_gruneisen` or `mie_gruneisen_t` | `mie_gruneisen` | the model; the resolved deck always writes it, so every material's model is on record |
| `CV` | number > 0, J/(g K) | (required with `mie_gruneisen_t`) | constant specific heat; converted to kJ/(g K), bitwhiz's energy unit per kelvin, on reading |
| `T0` | number > 0, K | (required with `mie_gruneisen_t`) | the temperature at R0 and e = 0, bitwhiz's initial state |

- `eos =` names what the material is (not `change_eos =`, an action):
  `eos = mie_gruneisen` is the default and may be written out.
- `CV` and `T0` with `eos = mie_gruneisen` (or none) are a deck error that
  says which `eos` takes them; `mie_gruneisen_t` without them is an error too.
- Later add-ons follow the same pattern: `burn = hvrb` and the burn's keys.
- C_V in the gold-standard runs: 1.35e11 erg/(g eV) / 11604.5 K/eV =
  1.1633418 J/(g K), every material; T0 = 298 K. (The dataset's README rounds
  it to 1.163, 0.03 % low: about 0.3 K in a 1000 K rise.)

## The temperature

Mie-Grüneisen with rho Gamma = R0 G0 is

    P(V, e) = R0 G0 e + Pi(V),        eta = 1 - R0 V

where Pi is the part that depends on volume alone; in compression
Pi = P_H - R0 G0 e_H, and with e_H = P_H (V0 - V)/2 that is
**Pi = P_H (1 - G0 eta/2)**. It is `eos_mod`'s phi, already in the code,
with its cubic for tension (`eos_mod`'s header), so the temperature reuses the
tested pressure code; there is no second Hugoniot.

**The cold curve** (the isentrope from V0 at e = 0, which with e_0 = 0 is
also the 0 K isotherm):

    e_c(V) = -exp(G0 eta) * integral from V0 to V of exp(-G0 eta') Pi(V') dV'

or, as an ODE in eta (de = -P dV along an isentrope, d eta = -R0 dV):

    de_c/d eta = G0 e_c + Pi/R0,        e_c(0) = 0

**The temperature,** for constant C_V:

    e = e_c(V) + C_V ( T - T0 exp(G0 eta) ) + e_0 exp(G0 eta)

with e_0 the energy at (V0, T0). bitwhiz starts every cell at e = 0, so
e_0 = 0 and

    T = T0 exp(G0 eta) + ( e - e_c(V) ) / C_V

T0 exp(G0 eta) is the principal isentrope's temperature (d ln T/d ln rho =
Gamma, with Gamma rho constant). The gold-standard code puts Material X's
reactant at e = Q at rest and subtracts Q before computing T, which is the same
reference.

**Checked (sympy, Nov 3):** e_c and the principal isentrope satisfy
de/dV = -P(V, e) exactly; e(V, T) satisfies the Maxwell relation
(de/dV)_T = T (dP/dT)_V - P identically; (dP/dT)_V = R0 G0 C_V = rho Gamma C_V;
on the principal isentrope T = T0 exp(G0 eta).

**Checked against G1 (Nov 3),** with a 50-digit implementation outside
bitwhiz (Pi from the Hugoniot, e_c by quadrature, T from the formula), at
the first-shock state:

| u_fly (km/s) | PMMA at 11 mm: predicted - G1 | Material X, 1-9 mm: predicted - G1 |
|---|---|---|
| 1.00 | -0.002 K | -0.88 K |
| 1.25 | -0.003 | -1.78 |
| 1.50 | +0.002 | -2.81 |
| 1.75 | -0.006 | -3.79 |
| 2.00 | +0.001 | -4.58 |

PMMA agrees to the data's own digits, so the method is right. Material X
does not: the reference's temperatures are 0.9-4.6 K higher than the formula
at the reference's own density and energy, by the same amount at every depth
(not wall heating at the impact plane), growing with the shock. A C_V of
1.33e11 erg/(g eV) would bring it within 0.4 K, not to PMMA's 0.006, and S2
is not the cause (dropping it makes the gap four times worse). A likely
cause, not confirmed: a fitted cold curve in the reference (a fifth-order
polynomial in eta is common), about 1 % off in e_c for Material X at
eta = 0.28, where S2 bends the Hugoniot. bitwhiz is checked against the
formula, exactly, for every material (decision 3).

G1's temperatures start at 298.0014 K, not 298: a known offset of 0.0014 K
(the reference's output precision), not tracked further.

## Numerics: e_c carried by the cell ("plan C")

Integrating the cold curve from V0 at every evaluation is too slow, and a
table per material breaks once constants are graded cell by cell (TODO.md,
section 7: one table per cell would be about 24 kB a cell). So each cell
carries its own cold energy, as it carries its own e:

| Per cell | Stored | Why |
|---|---|---|
| e_c | yes | the only real history: the cold energy at the cell's current V |
| T | yes | derived, T = T0 exp(G0 eta) + (e - e_c)/C_V, each step; for the outputs now and HVRB later |
| de_c/dV, d2e_c/dV2 | no | exact from (V, e_c) through the ODE: de_c/dV = -(R0 G0 e_c + Pi), d2e_c/dV2 = -(R0 G0 de_c/dV + Pi') |

**The update,** once per cell per step, after its new volume is known (both
methods, AV and RS), from eta_1 to eta_2: the linear ODE's exact propagator

    e_c(eta_2) = exp(G0 (eta_2 - eta_1)) e_c(eta_1)
                 + integral from eta_1 to eta_2 of exp(G0 (eta_2 - s)) Pi(s)/R0 ds

with the integral by 3-point Gauss-Legendre (exact for polynomials of degree
5; the integrand is smooth, and a step's Delta eta is small, even across a
shock, which an explicit code spreads over a few cells and steps). Only the
quadrature is approximate; the growth factor is exact. Cost: three Pi
evaluations per cell per step, only in cells whose material carries T.

**What the accuracy depends on:** e_c is a function of V alone, so the
carried value must stay on the curve however the cell moves; the quadrature
error, per step, is O(Delta eta^7) of a smooth function. A test drives one
cell through a hard path (below) to show the drift stays at round-off.

**Edges:**
- Tension: Pi is the cubic in rho - R0 there, as in the pressure, so e_c
  continues smoothly through V0.
- The Hugoniot's reach (`eos_too_compressed`): the pressure stops the run
  first, so e_c never sees it.
- Broken cells (spall): e_c still follows V (it is a function of V), and T is
  computed as everywhere else; an open cell's T is reported as computed (its e
  and V are what the hydro gives it).

**Where it lives:** two optional database rows (`jec`, `jtk`), allocated only
when some material uses `mie_gruneisen_t`; a deck without it allocates
nothing more and runs exactly as now. The model is chosen per layer, once, at
setup: the cell loop gets a per-layer flag, not a per-cell branch on a name.

## Outputs

- **Tracer file:** a `TK.<name>` column (K) for every tracer when some
  material carries T; 0 where a tracer's cell has no temperature model (to
  settle).
- **History file:** a `TK` variable (real32, cells), appended after `DMG`
  when some material carries T. New variables are only ever added at the end
  and are found by name (input/README.md, section 9), so existing readers,
  bitwhiz's own pictures and the notebook's Plot history keep working; format
  version stays 1.
- **Screen:** each material's model in the resolved deck; the run's T range
  at the end.
- `gold.py` already reads `TK` (and bitwhiz's columns by name);
  `compare_g1.py` gets the temperature checks.

## Tests

1. **Old decks, bit for bit.** Every deck in `input/` and `tests/decks/`
   gives the same results, heartbeat, tracer rows and history frames as
   before, on both builds (the release tests already require it; add the
   pre-change outputs as a check for this commit).
2. **The cold curve at 50 digits.** `tests/temp_reference.py` (mpmath,
   independent of the Fortran, as `eos_reference.py` is for P and c): e_c at
   chosen eta in tension and compression, for the four class materials. The
   unit test `tests/test_temp.f95` checks bitwhiz's per-step update against
   them.
3. **A hard path.** One cell driven through a shock (a large Delta eta in a
   few steps), reverberations back and forth, and release into tension, then
   back to chosen eta: the carried e_c against the 50-digit value, to near
   round-off. This is the test for plan C's one risk, accumulated drift.
4. **Units.** C_V in J/(g K) in, kJ/(g K) inside: one case where the answer
   is known by hand.
5. **Deck tests.** `eos` names; `CV`, `T0` with and without
   `mie_gruneisen_t`; missing, negative, zero; the resolved deck's round trip.
6. **G1.** `compare_g1.py`, the same for every material: TK at the interior
   gauges behind the first shock, against the exact Hugoniot temperature
   (the formula, 50-digit cold curve, at bitwhiz's own state) to near
   round-off; and against G1, PMMA to 0.01 K, Material X reported with its
   known difference (decision 3).

## Decisions (Nov 3, 2026)

1. **Names:** `eos = mie_gruneisen_t`, `CV` (J/(g K)), `T0` (K), as above.
2. **A tracer whose cell has no temperature model:** `TK = 0`.
3. **Verification is the same for every material:** bitwhiz's T against the
   exact formula at its own state, to near round-off, everywhere; then
   against G1 at every interior gauge. G1's Material X temperatures are
   0.9-4.6 K above the formula (above), a property of the reference data,
   recorded and reported, not a tolerance on bitwhiz.
4. **The run log:** T's range and the hottest cell (where and when).
5. **The tracer file's G1 offset:** G1 starts at 298.0014 K, not 298: a
   known offset of 0.0014 K, not tracked further.

## As built (Nov 3, 2026)

Phase 2 as approved, with these choices made in the code (all in
`src/modules/temp_mod.f95`, module `temperature`, and its header):

- **Its own arrays, not database rows.** The database's slots are fixed
  at compile time (`nvar`), so "optional rows" would have meant a second
  database layout. Instead the module holds arrays by cell (k = 1 to
  k_max: e_c, T, C_V, T0, and the list of cells with T), allocated only
  when some material uses `mie_gruneisen_t`. The database, its audit and
  every old deck are untouched (checked bit for bit: heartbeat, tracer
  rows and history frames of all 34 decks; only the resolved deck's new
  `eos =` line differs on screen).
- **Each cell also keeps eta_c,** the eta its e_c belongs to. The update
  goes from eta_c to the cell's eta now, so it needs nothing from how AV
  or RS keep their old state.
- **Pi is module eos's own:** `mg_pressure` at e = 0 returns R0 G0 0 +
  phi = phi, bit for bit. No second copy of the Hugoniot or the cubic
  (and `eos_mod.f95` is unchanged).
- **The pieces:** at most 0.005 in eta (times 1 - eta in tension). One
  step of 0.1 from V0, against 50 digits: 3e-11 with pieces of 0.02,
  4e-13 with 0.01, 6e-15 with 0.005. Almost every step of a run is one
  piece; a step across eta = 0 is two (Pi's 4th derivative jumps there).
- **Back from far tension, start again at V0.** Compressing multiplies
  the carried e_c's error by exp(G0 Delta eta). Within the class
  problem's range that is a factor of 2 or 3, but a broken cell
  stretched to 21 V0 and squeezed back multiplied its round-off by about
  1e17 (7e2 relative error, measured): the isentropes' spread shrinks as
  exp(G0 eta) on the way out, so a carried value forgets where it came
  from. A cell whose e_c lies beyond 2 V0 (eta < -1) and is compressed
  integrates from V0 instead (at most 200 pieces, only such cells): back
  on the curve to 1e-13.
- **When:** once per cycle, after the hydro step of either method, on the
  time loop's team of threads (each cell writes only its own k: any
  number of threads gives the same bits, checked in the OpenMP tests). At
  t = 0 the setup audit checks eta = 0 and T = T0 exactly in every cell.
- **Outputs:** `TK.<tracer>` closes each tracer's block in the tracer
  file; `TK` (real32, cells) follows `DMG` in the history file; the run
  log gives the T range over the whole run and the hottest cell (cell,
  layer, time, x). A deck without T writes exactly what it did before.
- **The log's range is over intact cells.** A broken cell's T is written
  as computed (Edges, above), and it falls as the cell opens: its P is
  floored at 0, so the opening does no work, while e_c climbs the cold
  curve. In G1 at 2.00 km/s the PMMA's free-surface cell, spalled and
  stretched, reaches -4,693 K, which is the temperature of nothing; so
  the range and the hottest cell skip broken cells. (A question for
  later, with HVRB or a damage model: what T should a broken cell carry?)

**Tests:** `tests/test_temp.f95` against `tests/temp_reference.py` (24
cold energies in one step and in 997; the hard path, 2,061 steps; out to
21 V0 and back; 12 Hugoniot temperatures; units by hand through the deck
reader): every one within 1e-13 relative. Deck tests: `ok_temperature`,
`ok_temperature_rs` and eight error decks. History tests: `TK` in the file
is the tracer file's. OpenMP and release tests: the two `ok_temperature`
decks, bit for bit.

**G1 (`compare_g1.py`, 40 checks, all pass),** every material the same way:

| u_fly (km/s) | TK - formula, 13 tracers, every row | TK at 1 mm - exact T_H | PMMA 11 mm: formula at the reference's state - its TK | MatX 1/5/9 mm: the same |
|---|---|---|---|---|
| 1.00 | 3.8e-12 K | +0.001 K | +0.0001 K | -0.89 to -0.88 K |
| 1.25 | 4.5e-12 | +0.009 | +0.0027 | -1.79 to -1.78 |
| 1.50 | 5.9e-12 | -0.029 | +0.0036 | -2.81 to -2.80 |
| 1.75 | 1.1e-11 | -0.018 | -0.0039 | -3.79 to -3.76 |
| 2.00 | 1.4e-11 | +0.012 | +0.0014 | -4.58 to -4.50 |

bitwhiz's own first-shock TK against the reference's, reported: PMMA
-0.028 to +0.016 K (the two codes' plateau states differ slightly), Material
X the -0.9 to -4.6 K above, as predicted before any code.

## Temperature verification: bitwhiz's own standard (Nov 3, 2026)

bitwhiz's temperatures are verified against exact values it computes
itself, two independent ways, not against another code. Decision 3 asked
for G1 as well; G1's Material X temperatures turned out to carry the
reference tool's own cold-energy error (below), so G1 is reported, not
checked. The standard, for every material:

| | What | Against | Tolerance | Where |
|---|---|---|---|---|
| T1 | the method: e_c in one step and in many, a 2,061-step path, out to 21 V0 and back; T on the Hugoniot; units | 50-digit values (mpmath, its own quadrature: `tests/temp_reference.py`) | 1e-12 relative | `tests/test_temp.f95`, `make test` |
| T2 | the second exact implementation: `gold.py`'s e_c (Gauss-Legendre from V0, numpy) and Hugoniot T | the same 50-digit values | 1e-12 relative | `gold.py`'s self-test |
| T3 | a run's consistency: TK at every row of every tracer | `gold.py`'s formula at the run's own rho and e | 1e-6 K | `compare_g1.py` |
| T4 | the physics: the first shock's TK, Material X at 1-9 mm and PMMA at 11 mm | the exact Hugoniot T, at the impedance match (Material X) and at the run's density (PMMA) | 0.1 % of T_H - T0, as P | `compare_g1.py` |
| T5 | threads and builds | the 1-thread debug run | bit for bit | OpenMP and release tests |

Measured (G1 deck, five velocities): T1 1e-13, T2 4e-16, T3 1.4e-11 K, T4
0.039 % of the rise at most. G1's own TK, reported beside it: PMMA within
0.03 K of bitwhiz; Material X 0.9-4.6 K higher. That difference was
measured in the reference's EOS tool (`tests/verification/inert_gauges/
eos_tool/`): its pressure is bitwhiz's, but its Material X cold energy is
not the integral of that pressure (PMMA's is), and the gap at each
first-shock density is G1's offset, to 0.006 K. The same queries explain
G1's 298.0014 K start and show the tool's linearized model in tension. The
book on the reference's temperatures is closed there; bitwhiz keeps the
exact cold curve.

## Phases

1. **This note, approved.**
2. **Mie-Grüneisen with temperature:** keys, rows, the update, outputs,
   tests 1-6. A release (1.2.0) when G1's temperatures are settled.
   Done: released as v1.2.0 Nov 3, 2026, on nanoHUB Nov 4.
3. **HVRB** (TODO.md, section 6): reaction progress per cell, ideal-gas
   products, the density-temperature closure (T then feeds P), checked
   against G2-G5.
4. **Graded constants** (section 7): the per-cell e_c already allows them.

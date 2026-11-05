# Material models: design note

Started Nov 3, 2026, on `shock` after `f81f2b7` (movies). Status: **approved
Nov 3, 2026** (decisions below); phase 2 built Nov 3 (As built, below);
phase 3, HVRB, drafted Nov 4 (Phase 3, below). TODO.md, sections 5 and 6, is
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

## Phase 3: HVRB (draft for approval, Nov 4, 2026)

The model is `doc/HVRB_Eqns_v8` (frozen Nov 4; the inputs of the
gold-standard reactive sets G2-G5, `tests/verification/hvrb/`). Decisions
from D. E. Kittell's review of the plan and his answers (Nov 4) are marked
**DK**; none is left open. Nothing in this section is built yet.

### The deck

```
Begin Material MatX
  eos      = mie_gruneisen_t     # the reactant: Mie-Grüneisen plus T (CV, T0)
  R0 = 1.60 ... G0 = 1.20        # as now
  CV       = 1.1633418           # J/(g K), both phases (the sheet's closure)
  T0       = 298.0
  burn     = hvrb                # the rate law
  PR       = 7.0                 # GPa, reference pressure
  ZR       = 3.0                 # pressure exponent
  MR       = 1.5                 # delay exponent
  XR       = 2.5                 # completion exponent
  PI       = 1.0                 # GPa, threshold pressure
  TAU0     = 1.0                 # us, time constant (required)
  products = ideal_gas           # the products' EOS: required, no default
  GAMMA    = 2.60
  Q        = 4.8828              # kJ/g (= MJ/kg), heat of reaction
End Material
```

- **Three independent choices** (**DK**): the reactant's `eos`, the
  `burn`, and the `products`. HVRB is usually paired with JWL or tabular
  products; ideal gas is the first, not the only one: `products = jwl` (or
  Davis, or a table) later is a new products module, with no change to the
  burn or the reactant.
- **Said out loud:** `products` has no default, so a deck that burns names
  its products; the screen and the resolved deck repeat them ("HVRB, ideal-gas
  products").
- **Errors:** `burn = hvrb` with any `eos` but `mie_gruneisen_t` (**DK**: the
  closure needs the cold curve and T); `burn` without `products`, or
  `products` without `burn`; any HVRB or products key without them (the
  message names what takes it); PR, MR, XR, TAU0 not > 0; ZR, PI < 0;
  GAMMA not > 1; Q < 0. MR and XR at or below 1 are legal (the sheet's
  shape notes: no delay, an abrupt finish) and accepted as given; so is
  ZR = 0 (below).
- **Names** (**DK**): the sheet's symbols without subscripts, as R0, C0, S1,
  G0 are: PR, ZR, MR, XR, PI, TAU0, GAMMA, Q. Every one is required; a burn
  has no hidden defaults.
- **TAU0 is a parameter in its own right** (**DK**). For ZR > 0 only the
  product TAU0 PR^ZR enters the rate (the sheet), so the pair has one
  redundant degree of freedom. At ZR = 0 the pressure factor is 1 above
  threshold, PR drops out, and TAU0 is the only rate scale left: it is the
  one parameter that always carries the time. Kept, required, and graded
  like the rest later.

### Notation: two "cold" energies

bitwhiz's carried `e_c` (module temperature) is the isentrope from rest, the
sheet's **e_S**. The sheet's **e_c** is e_S - C_V T_S, with T_S = T0
exp(G0 eta). The code keeps its name; this note and the module's header say
e_S where they mean the sheet's. Energy zero is bitwhiz's: e = 0 at rest,
unreacted (the sheet's convention; the reference code puts the reactant at
e = Q and subtracts it).

### The closure, per cell

With vartheta = C_V T (both phases share one C_V, so no iteration):

    vartheta = e - (1 - lam)(e_S - C_V T_S) + lam Q
    e_sol    = e_S - C_V T_S + vartheta            (the solid's energy at T)
    P_sol    = mg pressure at (rho, e_sol)         (module eos, unchanged)
    P_gas    = (gamma - 1) rho vartheta
    P        = (1 - lam) P_sol + lam P_gas
    T        = vartheta / C_V

**Checked (sympy, Nov 4):** this is the sheet's T-free form exactly; at
lam = 0 it is Mie-Grüneisen at (rho, e); at lam = 1, (gamma - 1) rho (e + Q);
a constant-volume burn from rest ends at (gamma - 1) R0 Q = 12.499968 GPa;
the strong-detonation D_CJ = sqrt(2 (gamma^2 - 1) Q) = 7.4999904 km/s, the
dataset's exact value.

**A cell that has started to burn holds no tension** (**DK**). The gas
fills the cracks of a reacting solid, so the condensed phase is not mixed in
while it would pull: for lam > 0,

    P = (1 - lam) max(P_sol, 0) + lam P_gas

so P >= 0 always (P_gas >= 0 with vartheta floored at 0), and a burning
cell can never reach -spall_strength: it never "breaks", it expands with
the gas. A cell at lam = 0 keeps today's tension and spall exactly. The
burn itself stops in tension on its own: P < PI there, so Phi = 0 and lam
holds (HVRB never runs backward). **Only the solid's pressure is
dropped** (**DK**): vartheta, T and the energy balance stay as written, so
energy is conserved exactly as in an unclamped cell.

*Revised Nov 5: the dropped solid is held where it first pulled ("The solid
held where it first pulled", below, before Phases).*

**The Hugoniot's reach.** The gas phase has no compression limit; the solid
does (`eos_too_compressed`, Us past 100 C0). A fully burnt cell (lam = 1,
which the exact topology reaches exactly, at phi_end) never evaluates the
solid. A cell with 0 < lam < 1 past the reach stops the run, as today, with
a message giving the cell, lam and eta. If G2-G5 runs ever trip it, the
choice is then a cutoff in 1 - lam, made on evidence.

### The sound speed: exact (**DK**)

The sheet's exact rule (checked with sympy, Nov 4, for any Pi):

    c^2 = (1 - lam) c_sol^2 + lam gamma (gamma - 1) vartheta
          - lam (1 - lam) (R0 G0 / rho - gamma + 1)^2 vartheta

with c_sol the inert Mie-Grüneisen sound speed at (rho, e_sol). Guardrails:
vartheta floored at 0 in the gas terms; where the solid is dropped (P_sol <
0), c^2 is that of the pressure actually used (the solid's terms out, the
same exact derivative); if c^2 <= 0 anyway, the mass-weighted value, then
the gas's alone, with a count in the log. The unit test checks c^2 against
(dP/drho)_e + (P/rho^2)(dP/de)_rho of the closure, by 50-digit finite
differences, at every state in its table, clamped ones included.

### The rate law, per cell, once per cycle

    Phi      = (1/TAU0) ((P^n - PI)/PR)^ZR   if P^n > PI,  else 0
    phi^n+1  = min(phi^n + Phi dt, phi_end),  phi_end = XR^(1/MR)
    lam^n+1  = 1 - (1 - phi^MR/XR)^XR                       exact, 0..1

P^n is the cell's pressure. **Phi = 0 at or below PI is written out, not
left to max(., 0)^ZR:** at ZR = 0 that would be 0^0, which Fortran leaves
to the processor (gfortran gives 1), and a cell at rest would burn. With
the test explicit, a cell at rest or in tension never burns, for every ZR
and even with PI = 0.

**ZR = 0: a burn on a clock** (**DK**: used in practice in place of
time-dependent burns, e.g. aluminum droplet combustion). Above PI, Phi =
1/TAU0, so phi is the time spent above threshold over TAU0, and the
topology shapes lam(t). With MR = 1 it is a d^n law exactly: a droplet whose
d^n falls linearly burns out at t_b, its mass goes as d^3, so

    lam(t) = 1 - (1 - t/t_b)^(3/n)  =  HVRB with ZR = 0, MR = 1, XR = 3/n,
                                       t_b = XR TAU0

(the D^2 law: XR = 1.5, t_b = 1.5 TAU0; d^1: XR = 3; checked numerically,
Nov 4, identical to round-off). MR > 1 puts an ignition delay in front.
With ZR = 0 the first-order quadrature of Phi is exact while the cell stays
above PI; the only error is a step that crosses it.

Then the closure at (rho^n+1, e^n+1, lam^n+1). Burning changes lam at fixed
rho and e, so total energy is conserved by the hydro's own update (e holds
the chemical energy through + lam Q); the heartbeat's energy error is the
check (the sheet: <= 0.01 % while Material X burns).

**Order within a cycle** (a change from 1.2.0): the closure needs e_S at the
new volume, so for burning materials the cold-curve update (module
temperature) moves before the pressure is evaluated. e_S is a function of
the cell's volume alone, so moving the update changes no number in an
`mie_gruneisen_t` deck (checked bit for bit).

### Method RS: the reaction as a source (**DK**)

AV needs nothing more: its pressure comes from the closure each step. In RS
a cell's P at the end of a step also comes from the closure, so order 1
needs nothing more either. Order 2 advances P inside the step: the
MUSCL-Hancock predictor (`rs_face_states`, step 1b) moves each face value
half a step with the cell's acoustic equations, dP/dt = -Z^2 du/dh. With
reaction the pressure equation gains a source (Fickett and Davis's
thermicity sigma, r = dlam/dt):

    dP/dt = -Z^2 du/dh + rho c^2 sigma r

For this closure

    rho c^2 sigma = (dP/dlam)_{rho,e}
                  = -(P_c + R0 G0 vartheta) + (gamma - 1) rho vartheta
                    + [(1 - lam) R0 G0 + lam (gamma - 1) rho] (e_S - C_V T_S + Q)

with P_c = P_sol(rho, e_S) - R0 G0 C_V T_S (the sheet's cold pressure)
(checked with sympy, Nov 4).

- **Where:** in the predictor's half step only, dp = -(dt/2)(Z^2 du/dh -
  rho c^2 sigma r), the same for both faces of the cell. The Riemann
  problem itself is unchanged (it takes the face values and Z), and so is
  the conservative update, so energy conservation is untouched: the
  source only shapes the face pressures.
- **Held constant across a step** (**DK**), as Z is: rho c^2 sigma from the
  cell's state at time n. The PEP paper (D. E. Kittell et al., Propellants
  Explos. Pyrotech. 45 (2020) 295-315, doi:10.1002/prep.201900209, p. 297;
  already `rs_mod`'s reference for the star values) and DK's other journal
  paper fold thermicity into an effective heat of reaction held constant
  for the whole run; DK's notes hold it constant for one step. bitwhiz
  takes the per-step form: the closure gives rho c^2 sigma exactly per cell,
  for a few operations, so a constant for the whole run would only discard
  information (a cell's rho c^2 sigma changes as it burns). The paper's
  form is the same scheme with a frozen value.
- **The rate r is the step's own:** r = (lam^n+1 - lam^n)/dt from the exact
  burn update, computed from P^n before the predictor runs (it needs
  nothing later). Not g(lam^n) Phi^n: g is infinite at lam = 0 when MR < 1,
  and zero there when MR > 1 (the delay), while the step average is always
  finite and consistent with the lam the closure then uses.
- **A check on its effect:** G2 at 2.00 km/s with RS order 2, the source on
  and off, before choosing to keep it; it should sharpen the reaction
  zone's face pressures, not move the run distance by more than the mesh
  study's spread. Off is a development switch only, not a deck key.

### Per cell, for grading later

Every constant is an array by cell, filled from the cell's layer at setup
(PR, ZR, MR, XR, PI, TAU0, GAMMA, Q, and phi_end from MR and XR), beside
module temperature's C_V and T0; the state is phi and lam by cell. Grading
(section 7) then changes how the arrays are filled, not the physics. The
arrays live in the burn's own module (`hvrb_mod.f95`, module `hvrb`) and the
products' (`prod_mod.f95`, module `products`, the ideal gas: P, e and c from
rho and vartheta), allocated only when a deck burns. A deck that does not
burn allocates nothing and runs exactly as now; the model is chosen per
layer at setup, never per cell by name.

The products module is written for what comes after ideal gas: each phase
gives P and e as functions of (rho, T). With one shared C_V the closure is
linear in T, as above; a JWL or Davis products EOS (its own C_V) turns it
into a one-variable Newton solve for T, in the same place.

### Outputs

- **Tracer file:** `XRN.<tracer>` (lam, 0 to 1) closing each tracer's block
  when some material burns, 0 in cells that do not (**DK**: the gold
  data's XRN3 is "material 3"; the tracer's name does that job here). TK
  for a burning cell is vartheta/C_V.
- **History file:** `XRN` (real32, cells) after `TK`.
- **Log:** each burning material's model ("HVRB, ideal-gas products"); the
  first cell to react (lam > 0: cell, layer, time, x); at the end, per
  burning layer, the cells fully burnt and the largest lam.
- `gold.py` reads XRN already; a `compare_hvrb.py` beside `compare_g1.py`.

### Tests

1. **Old decks, bit for bit,** both builds, MG+T decks included (the moved
   cold-curve update).
2. **50 digits:** `tests/hvrb_reference.py` (mpmath): the topology (lam of
   phi, phi of lam, g), the closure (P, T, c^2, dP/dlam) on a table of
   (rho, e, lam) in compression and tension, clamped states included; the
   constant-volume burn. `tests/test_hvrb.f95` checks the module against it,
   and also: the rate at or below PI is 0 for every ZR, ZR = 0 included, at
   rest and in tension; ZR = 0, MR = 1, XR = 1.5 integrated step by step
   against the D^2 law's closed form (exact while above PI).
3. **The inert limit:** an HVRB deck with PI far above any pressure gives
   the `mie_gruneisen_t` deck's results bit for bit (a lam = 0 cell takes
   the plain Mie-Grüneisen path), XRN all 0.
4. **A rebuilt history** (the sheet's check): lam from one tracer's P(t)
   with the two HVRB boxes, in Python, against the tracer's XRN.
5. **Deck tests:** every error above; the resolved deck's round trip.
6. **OpenMP and release:** an HVRB deck, AV and RS, bit for bit.
7. **G2-G5** (`compare_hvrb.py`), with the dataset README's tolerances: run
   distance within one tracer spacing; D_CJ (G4) within 0.5 %; the Pop
   plot (G3); the mesh study (G5); energy within 0.01 % while burning.

### Steps

1. This section, approved.
2. Modules `hvrb` and `products`, the reference and the unit test: no hydro.
   Done Nov 4 (below).
3. Keys, deck tests, the per-cell arrays, AV wired, the inert limit, the
   outputs and the log. Done Nov 4 for method AV (3a, below); RS is 3b,
   with step 4.
4. RS, with the thermicity source in the order-2 predictor (above), and
   the on/off check at G2. Done Nov 4, with 3b (below).
5. G2-G5; then a release (1.3.0) and an HVRB deck for nanoHUB. G2-G5
   done Nov 4 (below).

Performance: only burning cells do more; the default Mie-Grüneisen path's
cost per cycle is checked unchanged (TODO.md, section 8).

### As built: step 2 (Nov 4, 2026)

`src/modules/prod_mod.f95` (module `products`: `idg_state`, P_gas and
c_gas^2 from rho and vartheta, nothing at vartheta <= 0) and
`src/modules/hvrb_mod.f95` (module `hvrb`: `hvrb_phi_end`, `hvrb_lambda`,
`hvrb_rate`, `hvrb_step`, `hvrb_state`), elemental and stateless; the
time loop does not call them yet. Choices made in the code:

- **lam for small phi** by the binomial series (16 terms below x =
  phi^MR/XR = 0.05), so a tiny lam keeps its relative precision: 1 - (1 -
  x)^XR loses half its digits at x = 1e-8, and Fortran 2018 has no log1p.
- **The threshold** is `.not. (P > PI)`, not max(P - PI, 0)^ZR (no 0^0),
  and ZR = 0 is the clock 1/TAU0.
- **dP/dlam at the ends:** at lam = 0 the slope of the burn's first step
  (the dropped form if the solid pulls: P itself jumps there, from P_sol <
  0 to >= 0); at lam = 1 the gas-only form, as the solid is not evaluated
  (nothing multiplies it: the burn is over). The reference defines them the
  same way.
- **The exact c^2 needs vartheta > 0** (the gas has no pressure below
  that); otherwise the guards take over, mass-weighted first.

**Tests:** `tests/test_hvrb.f95`, 11 checks, against `tests/hvrb_reference.py`
(mpmath, 50 digits, from the sheet's definitions; c^2 and dP/dlam by
numerical differentiation of the closure, not from the closed forms):
18 values of lam(phi) to 9e-16 relative (phi from 1e-9 of phi_end, MR and
XR above and below 1); 64 closure states, two materials, tension and
compression, lam = 0, 0.3, 0.8 and 1, the solid dropped in 12, P, c,
vartheta and dP/dlam to 4e-15; lam = 0 is mg_eos bit for bit; the
constant-volume burn, 12.499968 GPa; the D^2 law (ZR = 0, MR = 1, XR =
1.5), 650 steps, to 7e-15; the rate's threshold for ZR = 0 to 3; the
Hugoniot's reach; the guards; elemental calls. Clean with gfortran 9 and
13 under the strict flags.

### As built: step 3a, method AV (Nov 4, 2026)

- **Module `burn`** (`src/modules/burn_mod.f95`, approved as a refinement
  of "the burn's own module"): the cells' phi and lam, and every constant by
  cell, filled from the layer; `burn_step`, `burn_cell`, `burn_track`. It
  hands each cell to module `hvrb`, which stays stateless; a second burn
  model is a second branch here. A deck without a burn allocates nothing.
- **The cycle (AV):** loops 1 and 2 as before; then loop 2b, `burn_step`, an
  orphaned OMP DO on the time loop's team over the cells that can burn:
  e_S to the new volume (`temp_cold_cell`, module temperature), then phi
  and lam from P^n (`hvrb_step`); then loop 3, where a cell with lam > 0 is
  handed its burn (`cell_state(..., burn_cell(k))`, module av:
  `hvrb_state`) and every other cell, lam = 0 included, is called exactly
  as before. After the step, `temp_update` (T of a burning cell is the
  inert T plus lam (e_c - C_V T_S + Q)/C_V, which is vartheta/C_V; nothing
  added at lam = 0) and `burn_track`. temp_update's own cold step for a
  burning cell is then of zero length, which leaves e_c bit for bit.
- **A burning cell in `cell_pressure`:** P and c from the closure, never
  tensile, never broken; a gas with no sound speed (vartheta <= 0) is void,
  as an inert cell past c = 0 is. The count of guard sound speeds goes to
  the log if any.
- **Method RS refused a burn** at the deck ("not yet available with method =
  RS") until 3b gave it the reaction's source (below).
- **Outputs:** `XRN.<tracer>` after `TK.<tracer>`; `XRN` (real32, cells) after
  `TK` in the history file; in the log, the first cell to react, the cells
  burnt out per burning layer, the largest lam, and the guard count.

**Tests:** 13 error decks (`bad_burn_*`, `bad_products_*`,
`bad_pr_without_burn`) and three good ones: `ok_hvrb` (detonates; also an
OpenMP and a release test deck), `ok_hvrb_clock` (ZR = 0, the D^2 law's
exponents) and `ok_hvrb_inert`. History tests: `hvrb` (XRN in the file: 0
at t = 0, 0 to 1, never falling; the tracer file's, every frame; 1 by the
end) and **the inert limit**, `hvrb_inert`: ok_temperature's deck with a
burn whose PI no pressure reaches gives its heartbeat, tracer rows and
history frames, bit for bit (XRN left out). Every earlier deck (the ten
inputs and every good test deck) gives the same heartbeat, tracer rows,
history file and screen as before 3a, bit for bit; the class deck's cost
per cycle is unchanged (77.9 against 77.7 us, release, best of three).
gfortran 9 and 13: no new warnings.

**A first look at G2** (2.00 km/s, 100 zones/mm, AV, G1's deck with Material
X burning; the comparison script is step 5): the shock arrives within 5 ns
of the gold standard at all nine Material X gauges (0.0 to 4.8 ns), the
peak pressures within a few percent, every Material X cell burns out, and
the energy error is 4.6e-5 (the sheet asks for 1e-4 or less). At 10
zones/mm (`ok_hvrb`) it is 4.5e-4: the reaction zone (about 0.14 mm) is
not resolved there, as expected.

**Cost:** a burning cell adds about a third to a temperature-carrying run's
cycle (G2 against G1, release: 1,590 against 1,203 us per cycle). The
temperature itself is the larger cost: G1 without `mie_gruneisen_t` takes
207 us per cycle, so carrying T (1.2.0) is about 6 times that (TODO.md,
section 8).

### As built: steps 3b and 4, method RS (Nov 4, 2026)

- **The cycle (RS):** loop 0', `burn_rate_rs` (module burn), at the cycle's
  start: phi and lam over dt from P^n, and each burning cell's source, src =
  (dP/dlam) (lam^(n+1) - lam^n)/dt, with dP/dlam from the closure at the
  cell's state n (`hvrb_state`). Loop 0, the predictor: a cell with src /= 0
  adds (dt/2) src to its face pressures (`rs_face_states`, optional src);
  any other cell is called as before. Loop 2: after rho, u and e, a cell
  that can burn moves its e_S to its new volume (`temp_cold_cell`), then its
  state comes from the closure if lam > 0 (`rs_state`, optional brn, through
  `cell_pressure`). Order 1 has no predictor, so no source.
- **Held per cell, per step** (DK's notes): the PEP paper (p. 297) holds an
  effective heat of reaction for the whole run; here the closure gives
  dP/dlam exactly at each cell's state, for the price of one closure call
  in each cell that burns that step.
- **A development switch,** `rs_reaction_source` (module burn, a parameter),
  for the on/off check; not a deck key.

**The on/off check** (RS order 2, G2's deck; release build): with the
source off, the gauge arrivals move by at most 0.3 ns at 100 zones/mm and
2.00 km/s (0.1 ns at 1.50 km/s), and the P traces by 1.5e-4 of their peak
on average; at 25 zones/mm by 6e-4, where the source brings the arrivals
after detonation closer to the reference's own 25 zones/mm run (x4 to x9
within 1.9 to 4.8 ns of it, against 4.3 to 7.2 off). A small effect, as
expected (it shapes the face pressures in the reaction zone, not the run
distance), and in the right direction: kept on.

**Against G2** (a first look; the comparison script is step 5): gauge
arrivals x1 to x9 and the PDV arrival within 5 ns of the gold standard for
AV, RS order 2 and RS order 1 at 2.00 km/s, and for AV and RS order 2 at
1.50 km/s (within 3.9 ns); peak pressures within a few percent; every
Material X cell burns out. Energy: RS conserves it to round-off (2e-15), AV
to 5e-5 or better at 100 zones/mm.

**Tests:** `ok_hvrb_rs` (RS order 2; also an OpenMP and a release test
deck) and `ok_hvrb_inert_rs` (the inert limit with RS: ok_temperature_rs's
run, bit for bit, but for XRN); history tests `hvrb_rs` and `hvrb_inert_rs`
(the inert limit is now a function, `inert_limit`, run for AV and RS).
`bad_burn_rs` is gone (RS takes a burn). Every earlier deck, the three AV
burn decks included, gives the same results as 3a, bit for bit.

### As built: step 5, against G2-G5 (Nov 4, 2026)

`tests/verification/compare_hvrb.py`, with `hvrb/g2_react.deck` (G1's deck
with Material X burning: G2, and G5's mesh study) and `hvrb/g3_poplt.deck`
(the thick flyer, a tracer every 0.25 mm through Material X: G3 and G4),
method AV, the data's own definitions (gold.py) and the tolerances its
README suggests; 36 checks, all pass:

| Set | What | bitwhiz | Reference |
|---|---|---|---|
| G2 | run distance, 1.00 / 1.25 / 1.50 / 1.75 / 2.00 km/s | none / none / 7.5 / 5.5 / 3.5 mm | the same |
| G2 | arrivals 1-9 mm and PDV, every velocity | within -0.1 to +4.8 ns | |
| G2 | energy drift | 0.0006-0.0017 % | 0.0028-0.0055 % |
| G2 | lam at 9 mm, 3.0 us, 1.00 km/s (no detonation) | 0.035 | 0.034 |
| G3 | run distance, 1.25 / 1.50 / 1.75 / 2.00 / 2.25 km/s | 12.5 / 7.5 / 4.75 / 3.25 / 2.38 mm | 12.5 / 7.5 / 4.75 / 3.75 / 2.38 |
| G3 | arrivals on the reference's tracers | within -0.2 to +4.8 ns | |
| G3 | Pop plot, ln x_run = a + b ln P1 | 6.298 - 2.152 ln P1 | 6.158 - 2.074 ln P1 |
| G4 | D over 10-20 / 10-15 / 15-20 mm (D_CJ 7.5000) | 7.5150 / 7.5230 / 7.5118 km/s | 7.505 / 7.505 / 7.506 |
| G5 | PDV arrival, 25 / 50 / 100 / 200 / 400 zones/mm | 1.5061 / 1.5209 / 1.5202 / 1.5202 / 1.5201 us | 1.5194 / 1.5201 / 1.5203 / 1.5201 / 1.5201 |

- **Run distance** is a first crossing on tracer intervals, so it moves in
  steps of the spacing: G3 at 2.00 km/s is one step (0.5 mm) early, within
  the data's tolerance, and that one point moves the Pop plot's fit.
- **The mesh study converges:** bitwhiz's PDV arrival settles on the
  reference's own converged value to 0.0 ns. At 25 zones/mm it is 13 ns
  early against the reference's 25 zones/mm run (RS order 2: about 7): the
  reaction zone (about 0.14 mm) spans 3 to 4 cells there, and the two codes'
  schemes part. Reported, not checked; the data's acceptance is at 100
  zones/mm, and the check from 50 zones/mm up is within 5 ns.
- **G4's D** is 0.16-0.31 % above D_CJ (the reference: 0.07 %), inside the
  0.5 % tolerance; at 3.00 km/s the drive is overdriven at first, and the
  fits over 15-20 mm, furthest from it, are the closest.
- **Not compared:** after the trust window (material leaving the
  reference's mesh), and the reference's mixed-cell tracers at interfaces
  (u only, as its README says).

**The example deck,** `input/me697_hvrb_2p00.deck` (the class problem with
Material X burning, 35 zones/mm, a 35-frame pressure movie; 3 s release):
in `make runs` and the deck tests with the other inputs, and exported to
the nanoHUB tool's picker with them (decided Nov 4: the model in action for
students who do not use Fortran; the code is open and verified).

### The solid held where it first pulled (Nov 5, 2026)

**The problem.** With only the pressure dropped, a partly burnt cell in
tension went on charging the solid's cold energy as it stretched: ecs(rho)
grows below R0, and vartheta = e - (1 - lam) ecs + lam Q pays for it, with no
force doing the work (the dropped solid adds nothing to P). vartheta and T
went negative: -4049 K in Material X at 1.00 km/s (AV, after the free-face
fix of v1.3.2), -1858 K with RS, and the sound-speed guards fired in 16164
and 12702 cell-steps.

**The rule (DK: the solid's temperature should guide it; in equilibrium the
solid never ends below the expanded gas).** A dropped solid does no work, so
its cold energy should not change: it is **held at the density where it
first pulled**, rho_hold, with e_S there, es_hold, while the cell is
stretched past it. It cavitates; the gas fills the rest of the cell. Module
`burn` keeps rho_hold and es_hold by cell (`burn_hold`, once a step, after
e_S is at the new volume and lam is lam^(n+1), before P): kept while rho <
rho_hold; otherwise set to (rho, e_S) if the solid pulls at rho, else
cleared; never held at lam = 0 or 1. Every user of the closure sees the
same hold: the pressure for both methods (`cell_pressure`), RS's source,
and T (`temp_update`).

**The closure, held** (module `hvrb`, optional `rhold`, `eshold`): every
solid term at (rho_hold, es_hold), the gas at the cell's rho. Then
d ecs/drho = 0, and P_sol at a fixed density depends on e alone (dP_sol/de
= R0 G0), so

    c^2 = lam (gamma - 1) vartheta + (P / rho^2) [ s (1 - lam) R0 G0 + lam (gamma - 1) rho ]

with s = 1 if the held solid pushes and 0 if it is dropped. Dropped, that is
lam (gamma - 1) vartheta (1 + lam (gamma - 1)) > 0: no guard is needed, and
an expansion cools vartheta as rho^(lam (gamma - 1)), never to 0 and never
below the gas alone expanded the same way (rho^(gamma - 1)). dP/dlam keeps
its two forms, with the held ecs. If burning heats a held solid until it
pushes, it pushes at rho_hold, paid from vartheta, until it no longer does.
At rho = rho_hold the held and unheld closures agree, so P is continuous;
energy is the hydro's, untouched.

**Tests:** `test_hvrb` section 12, 3 checks: no hold at rho = rho_hold or
lam = 0 (the same bits as none); held, dropped and pushing, c^2 and dP/dlam
against central differences of the module's P, to 4e-11; a held cell
stretched to rho/100 along de = -P dv stays at vartheta > 0 and ends
6.6e-9 from the closed form.

**Results** (the guard decks: Material X struck at 1.00 and 2.00 km/s,
partly burnt, released at a free surface; v1.3.2 against the hold):

| Deck | T min, K | Guard cell-steps | Energy error |
|---|---|---|---|
| 1.00 km/s, AV | -4049 / -968 | 16164 / 2575 | 8e-15 / 7e-15 |
| 1.00 km/s, RS | -1858 / +8.6 | 12702 / 0 | round-off |
| 2.00 km/s, AV | -2172 / +8.7 | 8221 / 0 | round-off |
| 2.00 km/s, RS | +0.5 / +7.8 | 0 / 0 | round-off |
| inert controls, AV and RS | unchanged, bit for bit | 0 | unchanged |

Every input deck and `ok` test deck (43), and `compare_hvrb.py` under AV
(36 checks), give the same bits as v1.3.2: no cell of theirs is held.

**What is left: one cell, and not the closure.** The 1.00 km/s AV run's
remaining -968 K, and all 2575 guard steps, are one cell: the free-surface
end cell of Material X, barely burnt (lam = 9e-4), blown off to 1/500 of its
density. After 3.39 us its own -P dv is 0, yet its e falls by 1.39 kJ/g:
its neighbor's face work (+8.12) is outrun by the growth of its
cell-centered kinetic energy, (1/2) ubar^2 (-9.51), which AV's energy
update takes from e. That is AV's bookkeeping at a free surface (the same
family as its free-surface overshoot), for the AV free-surface study (TODO).

## Phases

1. **This note, approved.**
2. **Mie-Grüneisen with temperature:** keys, rows, the update, outputs,
   tests 1-6. A release (1.2.0) when G1's temperatures are settled.
   Done: released as v1.2.0 Nov 3, 2026, on nanoHUB Nov 4.
3. **HVRB** (TODO.md, section 6): reaction progress per cell, ideal-gas
   products, the density-temperature closure (T then feeds P), checked
   against G2-G5. Drafted Nov 4 (Phase 3, above), for approval.
4. **Graded constants** (section 7): the per-cell e_c already allows them.

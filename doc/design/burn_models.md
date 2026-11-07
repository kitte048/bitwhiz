# Phase 4: five more burn models (approved Nov 6, 2026)

Status: **approved.** Decisions marked **DK** are David's (Nov 6,
2026); the rest are proposals. Phase 3, HVRB, is `materials.md`; this note
extends it.

## The goal (DK)

Six burn models in bitwhiz, each with ideal-gas products and one common C_V
(phase 3's closure), so that bitwhiz carries a family of reactive burn
models on one verified footing:

| `burn =` | Model | Source | Status |
|---|---|---|---|
| `hvrb` | History Variable Reactive Burn | Kerley; Starkenberg (2002); the HVRB sheet | done, 1.3.0 |
| `flashfire` | FlashFire | SAND2025-09228 §5.2.1 (proposed by ChatGPT 4o-mini) | this note |
| `stochasticignite` | StochasticIgnite | SAND2025-09228 §5.2.2 (ChatGPT 4o-mini) | this note |
| `thermalcascade` | ThermalCascade | SAND2025-09228 §5.2.3 (ChatGPT 4o-mini) | this note |
| `halo` | HALO: Hot-spot Activation, Loss and Overlap | Kittell (2016), ADRB, revised here | this note |
| `claude` | CLAUDE: Centers Lit by Accumulated Unrecoverable Dissipated Energy | proposed by Claude (Anthropic), Nov 6, 2026 | this note |

Then graded materials (TODO.md, section 7) (**DK**). The order serves the
JOSS case (sustained work, one model per release) and an SCCM 2027 study.

**Sources** (`Class_Project/Literature/Burn_Models/`, outside the
repository): D. E. Kittell et al., "A Short Survey of Current Reactive Burn
Model Capabilities as of Mid-Year 2025", SAND2025-09228 (2025),
doi:10.2172/2585504; L. G. Hill, B. Zimmermann and A. L. Nichols III, "On
the burn topology of hot-spot-initiated reactions", AIP Conf. Proc. 1195,
432 (2009), doi:10.1063/1.3295166; J. Farjas and P. Roura, Acta Mater. 54,
5573 (2006), doi:10.1016/j.actamat.2006.07.037; R. Menikoff and M. S. Shaw,
"Reactive burn models and ignition & growth concept", EPJ Web Conf. 10,
00003 (2010), doi:10.1051/epjconf/20101000003; D. E. Kittell, the
activation and dissipation reactive burn (ADRB) model (2016, unpublished;
DK's, written for a production hydrocode). Every equation below was checked
against the rendered pages, not a text extraction.

## What the six share

### The closure, factored out first (DK)

Phase 3's closure is model-independent once the products are an ideal gas
with the solid's C_V: the density-temperature mixture, the solid held where
it first pulled, the exact sound speed with its guards, and dP/dλ for RS's
source. Step 2 moves it out of module `hvrb` into a module of its own
(proposed: `mixture`, `mix_mod.f95`); module `hvrb` keeps HVRB's rate law
and topology. **HVRB bit for bit** through the move: G2-G5, the 43 decks,
`test_hvrb`. Each new model then adds only its rate, its per-cell state and
its deck keys.

One density for both phases means the product volume fraction equals the
mass fraction, α ≡ λ, exactly; Hill et al.'s volume-to-mass correction
(their eqs. 14-15) does not arise in bitwhiz (it would under a
pressure-equilibrium closure).

### Products and temperature (DK)

`products = ideal_gas` (GAMMA, Q, the common C_V) for every model, the only
option for now. T in every rate is the closure's one temperature, ϑ/C_V:
solid and products share it, so burning raises it.

### Per-cell parameters and state, ready for grading (DK)

Module `burn` keeps, by cell k, laid out as the main database is (each
cell's numbers together in memory, one contiguous column per cell):

- `bmod(k)`: the cell's model (0 if it does not burn);
- `bpar(1:npar_max, k)`: the constants of its rate law, in slots each
  model names (HVRB: `hv_PR = 1`, `hv_ZR = 2`, ...; HALO's would be
  `ha_ED0 = 1`, ...); npar_max = 8, the most any model needs (**DK**,
  Nov 6: sized by the table's high-water mark, the same for every deck);
- `bst(1:nst_max, k)`: its state, sized the same way (nst_max = 6);

and, common to every model as today: λ (`lam(k)`, which the closure, the
temperature and the outputs read), the products' GAMMA and Q, and the
closure's held-solid state (`rhold`, `eshold`). A deck without a burn
allocates nothing (bit for bit, as now).

| `burn =` | `bpar` slots (npar) | `bst` slots (nst) |
|---|---|---|
| `hvrb` | PR, ZR, MR, XR, PI, TAU0 (6) | φ (1) |
| `flashfire` | KFF, AFF, BFF, TA, NS, PR, LAM0 (7) | the detector (5) |
| `stochasticignite` | MU, SIGMA, AVRAMI, NS, PR, LC, SEED, and Z (8) | the detector, φ (6) |
| `thermalcascade` | HT, TC, GT, NS, PR (5) | the detector (5) |
| `halo` | ED0, BETAH, TAUD, DELTA, DFRAC, NH, TAUB, PR (8) | E_D, η, s (3) |
| `claude` | NMAX, W0, KW, D0, NG, PR (6) | w, M_0, M_1, M_2, M_3 (5) |

The detector's five: h at the last step, its largest value, the shocked
flag, P_s, t_s. At most 8 + 6 numbers per burning cell.

**Why this layout:** grading a constant (TODO.md, section 7) then changes
only how `bpar` is filled at setup, by the same profile machinery as the
velocity profiles; the physics does not change. The t = 0 parameter file
(TODO.md, section 7) writes these columns. StochasticIgnite's Z is stored
the same way: a per-cell constant computed once at setup from SEED, the
cell's initial position and LC, so the realization is in that file too.
HVRB moves into this layout first (step 3 below), bit for bit; its eight
arrays (`prk`, `zrk`, ... `qk`) become `bpar` slots and the products'
common pair.

Each model's mathematics lives in a stateless module of its own, as `hvrb`
does; one routine, `cell_burn`, dispatches on `bmod(k)` for `burn_step`
and `burn_rate_rs` (`burn_cell`, what the closure needs, is common).
Every cell writes only its own column: results stay bit for bit on any
number of threads.

### Deck keys (DK)

Flat in the Material block, as HVRB's are (no nested block, so the deck
grammar and every existing deck are unchanged), under three rules:

1. **One key, one meaning, across all models;** a shared meaning shares the
   name. PR, HVRB's reference pressure (GPa), serves every model; NS, the
   exponent on (1 + P_S/PR), serves the three P_S models.
2. **Each model accepts only its own keys.** Any other burn key is a deck
   error, as PR without a burn is today (`tests/decks/bad_pr_without_burn
   .deck`): a key cannot silently do nothing.
3. **No collisions** with the equation of state's, the temperature's, the
   products' or HVRB's keys: R0, C0, S1, S2, G0, CV, T0, GAMMA, Q, PR, ZR,
   MR, XR, PI, TAU0 (PR shared on purpose). Hence ED0, not E0 (which reads
   as an equation-of-state reference energy); GT, not a second GAMMA (the
   products'); BETAH and BFF, not one BETA for two meanings; NS, NH and NG
   distinct (three different exponents).

Keys are case-insensitive, as every key is (`input/README.md`, section 5).
Which keys are required, and any defaults, are set with each model's deck
syntax and its bad-deck tests, at implementation.

### The lead shock, P_S and t_s (Menikoff and Shaw 2010, §4) (DK)

FlashFire, StochasticIgnite and ThermalCascade need the lead shock's
pressure, P_S. It comes from SURF's lead-shock detector, which needs no
artificial-viscosity threshold and no shock counter. Per cell, with the
state ahead of the lead shock (V_0, e_0, P_0) the cell's own state at rest
at t = 0:

    h(t) = e - e_0 - ½ (V_0 - V)(P + P_0)

the energy jump condition (Menikoff and Shaw print P - P_0, an erratum;
moot here, since P_0 = 0 exactly in bitwhiz). Inside a smeared shock h is
positive (≈ ½ q (V_0 - V) with AV) and returns toward zero as the cell
reaches the shocked state. The lead shock is marked at the first **zero
crossing** of h (compression follows the shock) or the first **local
minimum** of h after it has risen (expansion follows); then t_s = t and
P_s = P, interpolated within the step. **P_S is frozen** at the lead shock:
a reshock acts only through the local pressure (as SURF's (P/P_s)^n), which
gives shock desensitization; P_S never updates. The detector works the same
with AV and RS, is local to a cell, and keeps no history beyond five
numbers: h at the last step, its largest value, a shocked flag, P_s, t_s.

**Gating (DK):** for the three P_S models, λ = 0 until the lead shock is
marked. This keeps their burn out of AV's smeared shock (the
weak-detonation mechanism of `av_study.md`) by the models' definition, not
by a control. HVRB, HALO and CLAUDE do not use P_S and are not gated.

Open, to settle in runs (DK): the detector's noise tolerance (a relative
floor on h, an algorithm constant documented here, not a key), and smooth
(ramp) loading: with no lead shock nothing is marked and nothing burns,
agreed physically; a ramp that steepens into a shock is marked there.

### Steps that stay exact (DK)

Where a model's topology has a closed form, the step integrates a
potential and maps it to λ (HVRB's φ, SURF's s): exact in λ, no trouble
starting from λ = 0, no singularity at λ = 1. A rate first order in (1-λ)
takes the exact step 1-λ <- (1-λ) exp(-r Δt). A decay takes its exact
exponential. Only FlashFire, whose topology has no closed form, is
sub-cycled (below). As for HVRB, each model's rate uses the state at the
start of the step (P^n, T^n), and lam^(n+1) feeds the closure.

### Method RS (DK)

RS's reaction source, ρ c² σ r = (dP/dλ) (λ^(n+1) - λ^n)/Δt, is the
closure's (phase 3) and the step's own rate, for every model unchanged.

### Repaired, not verbatim (DK)

The three AI models go in with the minimum repairs that make them
well-posed, each named in its section and in its equation sheet. Faithful
where they can run as written; repaired only where they cannot.

## The models (DK)

Units throughout are bitwhiz's: mm, us, g/cm^3, km/s, GPa, kJ/g, K. Deck
keys follow the rules under "Deck keys" above; P_ref in an equation is the
key PR.

### FlashFire (`burn = flashfire`) (DK)

As proposed: dλ/dt = k (1-λ)^α λ^β exp(-E_a/RT) (1 + P_S/P_ref)^n.

Repairs:
1. λ^β is zero at λ = 0, so the burn never starts. **Seed at the lead
   shock:** λ <- λ_0 at t_s (an ignition fraction, in the spirit of I&G's
   ignition term).
2. E_a/R as one activation temperature, T_a (**DK**): no per-mole or
   per-gram units.
3. Gated by the lead shock (above); P_S frozen there.

Step: no closed form, so sub-cycled explicit steps, each changing λ by at
most Δλ_max (an algorithm constant), λ clipped to [λ_0, 1]. State: the
detector's five numbers.

| Key | Units | Meaning |
|---|---|---|
| KFF | 1/us | rate constant k |
| AFF, BFF | - | the topology's exponents α (on 1-λ) and β (on λ) |
| TA | K | activation temperature, E_a/R |
| NS | - | sensitivity to the lead shock's pressure (n) |
| PR | GPa | reference pressure (HVRB's key, shared) |
| LAM0 | - | ignition fraction set at the lead shock |

Tests: λ_0 alone at constant state against the closed form for β = 0
(1-λ)^(1-α) decay; the Arrhenius factor at 50 digits; no lead shock, no
burn.

### StochasticIgnite (`burn = stochasticignite`) (DK)

As proposed: dλ/dt = g(λ) (μ + σ Z) (1 + P_S/P_ref)^m.

Choices (g(λ) Claude's, DK Nov 6; the clock burning as proposed):
- **g(λ): KJMA** with Avrami exponent a: λ = 1 - exp(-φ^a), dφ/dt = (μ +
  σZ)_+ (1 + P_S/P_ref)^m. A potential, so exact steps and a natural start.
  After the lead shock the rate is constant but for λ: a burn on a clock
  (as HVRB with ZR = 0).
- **Z from atmospheric noise (DK's idea):** `rand_mod`'s 20,000 uniforms
  (RANDOM.ORG, 2025). Z is a **frozen field**, one value per bin of the
  material's initial position, x_0, in bins of a correlation length ℓ_c: a
  deck SEED sets the starting index, and bin j reads table entry
  mod(SEED + j·stride, 20000) + 1, stride a fixed prime coprime with 20,000.
  Refining the mesh converges to the same realization; a new SEED is a new
  member of an ensemble; every draw is a pure function of (SEED, x_0), so
  results stay bit for bit on any number of threads. Uniform to standard
  normal by Wichura's AS241 (accurate to about 1e-16; tested at 50 digits).
  Per-step noise was considered and not chosen: it needs √Δt scaling (the
  SDE treatment of Kittell et al., PEP 2020) and would exhaust and
  correlate the table.

Repairs: μ + σZ floored at 0 (a cell cannot burn backward); gated by the
lead shock. `rand_mod`'s header ("Named RGB Color Values") and its own
kinds are tidied when it is first used.

| Key | Units | Meaning |
|---|---|---|
| MU | 1/us | mean rate μ |
| SIGMA | 1/us | its standard deviation σ |
| AVRAMI | - | Avrami exponent a (3: random points in 3D) |
| NS | - | sensitivity to the lead shock's pressure (m) |
| PR | GPa | reference pressure (HVRB's key, shared) |
| LC | mm | correlation length of Z |
| SEED | integer | the realization |

Tests: σ = 0 against KJMA's closed form; AS241 against 50 digits; the
field's mean and variance over the table; the same SEED, the same bits;
mesh refinement keeps the realization.

### ThermalCascade (`burn = thermalcascade`) (DK)

As proposed: dλ/dt = h (1-λ) (T - T_c)^γ (1 + P_S/P_ref)^p.

Repairs: (T - T_c)^γ -> max(T - T_c, 0)^γ (no burn below T_c; γ need not be
an integer); gated by the lead shock. Its feedback (burning raises T,
which raises the rate) is the cascade; the exact step keeps it stable:
1-λ <- (1-λ) exp(-r Δt), r = h max(T - T_c, 0)^γ (1 + P_S/P_ref)^p at T^n.

| Key | Units | Meaning |
|---|---|---|
| HT | 1/(us K^GT) | rate coefficient h |
| TC | K | critical temperature |
| GT | - | temperature exponent γ |
| NS | - | sensitivity to the lead shock's pressure (p) |
| PR | GPa | reference pressure (HVRB's key, shared) |

Tests: constant T against the exponential closed form; T <= T_c, no burn;
the cascade's runaway time against a 50-digit integration at constant
volume.

### HALO (`burn = halo`) (DK)

Kittell's ADRB (2016), revised Nov 6 (DK accepted each change): no shock
detector and no switches; hot spots are activated by compression and
dissipated, never reactivated, so a weak first shock desensitizes.

1. **Activation measure,** ΔE_D = sqrt(max(Δe, 0) · max(-Δv, 0)) per step,
   converging to E_D = ∫ sqrt(σ) |dv| over compression (σ = -de/dv, the
   stress doing the work): independent of the mesh and time step. (The
   2016 form put the root over max(Δe, 0) alone, making each increment of
   order Δt^(3/2) and E_D shrink as N^(-1/2) over the N steps of a shock;
   changed, DK.) The 2016 (1-λ) safeguard is off (DK): bitwhiz burns at
   fixed e, so reaction heat never enters Δe.
2. **Hot spots,** η in [0, 1]:
   dη/dt = d/dt Erf[(E_D/E_D0)^β] - η (1-λ)^δ/τ_d;
   exact step η <- η exp(-(1-λ)^δ Δt/τ_d) + ΔErf.
3. **Burn,** a potential (DK): ds/dt = η^(1/d) (max(P, 0)/P_ref)^n / τ_b,
   λ = 1 - exp(-s^d): the 2016 rate exactly (chain rule), without its ε.
   d is a fractal dimension, 2 (SURF's cylinders) to 3 (SHS's spheres).

Order within a step: E_D, then η, then s (DK's sequence). State: E_D, η, s.

| Key | Units | Meaning |
|---|---|---|
| ED0 | GPa^(1/2) cm^3/g | activation scale E_D0 (Erf of 1 is 0.84) |
| BETAH | - | sharpness of activation (2016: 4) |
| TAUD | us | hot-spot dissipation time (2016: 0.25) |
| DELTA | - | reaction-deficit exponent of dissipation (2016: 2) |
| DFRAC | - | fractal dimension of the burn, 2 to 3 (2016: 2.3) |
| NH | - | burn-rate pressure exponent (2016: 2) |
| TAUB | us | burn time at P = PR, η = 1 |
| PR | GPa | pressure unit (only TAUB·PR^NH matters; HVRB's key, shared) |

The 2016 PBX 9502 constants do not carry over (E_D is a different
quantity, and the production code's cgs units). HALO is not gated: it
burns where η > 0, inside AV's smeared shock too; the study shows what that
does.

Tests: η and P constant against λ = 1 - exp(-(t/τ)^d) (KJMA; d = 3,
Hill-Zimmermann); no compression, no burn; dissipation alone, the exact
exponential; E_D for a double shock below a single shock to the same state.

### CLAUDE (`burn = claude`) (DK)

Proposed by Claude (Anthropic) at DK's invitation, Nov 6, 2026, and on the
list exactly as described (DK). Built on SAND2025-09228 §2.4's key areas
(burn centers from the shock, growth by deflagration, overlap, quenching),
exact where the others approximate. Like the ChatGPT models of §5.2 it is
an AI's proposal; unlike them it comes with a derivation and tests that can
prove it wrong.

1. **Activation from the dissipated energy:** w += max(Δe + P Δv, 0) per
   step, T ds: the cell's entropy production (with AV, -q Δv; with RS, the
   Riemann solver's dissipation). The entropy jump across a shock is fixed
   by the jump conditions, so w converges with the mesh; a double shock
   makes less entropy than a single shock to the same state, so
   desensitization comes without a switch or a detector. (CREST's idea,
   entropy, without its fit function.)
2. **Burn centers from a finite pool:** n(w) = n_max (1 - exp(-(w/w_0)^k)),
   centers born whenever w rises, at a reshock too.
3. **Growth at a deflagration speed:** G = D_0 (max(P, 0)/P_ref)^ng.
4. **Exact overlap with history (Avrami; Farjas and Roura eqs. 3-5):**
   λ = 1 - exp(-(4π/3) M_3), with the moments M_j = Σ over centers of
   (radius)^j per volume: M_0' = dn/dt, M_1' = G M_0, M_2' = 2 G M_1,
   M_3' = 3 G M_2. This is Avrami's extended volume exactly, for any
   nucleation and growth history; centers born at a reshock start small and
   grow on their own clock (the other five models collapse this history).
   Exact step for G constant over Δt (every radius grows by ΔR = G Δt):
   M_j <- Σ_i C(j,i) ΔR^(j-i) M_i, then M_0 += Δn (new centers, radius 0).

State: w, M_0 to M_3.

| Key | Units | Meaning, and how to set it before fitting |
|---|---|---|
| NMAX | 1/mm^3 | burn centers available; NMAX^(-1/3) is their spacing (microstructure: grain or pore spacing) |
| W0 | kJ/g | dissipated energy that lights 63 % of them (the shock threshold) |
| KW | - | sharpness of lighting (1: gradual) |
| D0 | mm/us | deflagration speed at PR (burning-rate data) |
| NG | - | its pressure exponent (Vieille; about 1) |
| PR | GPa | reference pressure (HVRB's key, shared) |

**Calibration (DK's caution: SHS never took off, with too many parameters
that analysts could not interpret).** CLAUDE's answer is that every
parameter is a measurable: NMAX from the microstructure, D0 and NG from
deflagration data, before any shock data; only W0 and KW are then fitted,
to a single-shock Pop plot or run distance. A quench time (lit centers
dying before they grow) is held back as a seventh parameter, added only if
the double-shock study needs it.

Tests: every center lit at once with G constant gives Hill-Zimmermann's
α = 1 - exp(-(π/6) t̂^3) exactly; the moment update against direct
quadrature of Avrami's integral at 50 digits for a varying history; w
across a shock against the exact entropy jump on the Hugoniot. Risk to
measure: round-off accumulating into w in smooth flow (max(·, 0) keeps
every bit of noise).

## Verification, without reference data (DK)

None of the five new models has independent reference data (HVRB had G2-G5).
Each is held to the standard phase 2 set for temperature (T1-T5), and that
`av_study.md` set for AV:
1. **Unit tests at 50 digits** (`tests/*_reference.py`, mpmath): every rate,
   topology, step and the closed forms named in its section.
2. **Closed-form limits in a run:** a constant-volume burn (P = (γ-1) R0 Q
   burnt out, as phase 3), the clock and KJMA limits.
3. **Convergence:** front speed and the state behind it against mesh, AV
   and RS, as `study_av.py`; D -> D_CJ = 7.4999904 km/s for Material X.
4. **Bit for bit** on threads, the inert limit (a burn that never starts
   gives the inert run), and the existing decks unchanged.

## Calibration and the study (DK)

Tailor each model's parameters so that it approximates the class problem's
Material X HVRB for a single shock (comparable detonation: run distance,
the PDV), then vary them to show unusual or interesting behavior in the
double-shock scenarios, where models with a shock history (the P_S models,
HALO, CLAUDE) should part from HVRB: shock desensitization. The six models
on the same problems, AV and RS: the SCCM 2027 study, and a figure for the
JOSS paper.

## Steps (one release each, each to nanoHUB) (DK)

1. This note, approved (with the per-cell layout and the deck keys above).
2. The closure in module `mixture`: a pure move; HVRB bit for bit (G2-G5,
   the 43 decks, `test_hvrb`).
3. Module `burn` generalized to `bmod`, `bpar` and `bst`, and the deck
   reader's burn keys driven by one table (a new model is then a table row
   and its module); HVRB migrated, bit for bit.
4. The lead-shock detector, with its own tests: shocks of known strength
   (P_s against the exact Hugoniot), a decaying and a strengthening shock
   (Menikoff and Shaw's Fig. 3), AV and RS.
5. ThermalCascade (the simplest P_S model, exact step).
6. FlashFire.
7. StochasticIgnite, with the noise table.
8. HALO, with its equation sheet (DK's model, revised).
9. CLAUDE, last: the closure, the detector and the potential pattern all
   tested by then, and it is judged on the same footing.
10. The study: calibration to HVRB's Material X, the double shocks.

Steps 2 to 4 change no result: patch releases (1.3.x). Each model is a
minor release (1.4.0 on).

Each model gets an equation sheet in `Equation_Sheets/` (frozen into `doc/`
when checked against the code), a design-note section here when built, an
example deck, and the deck reference in `input/README.md`.

## As built: step 2, the closure in module `mixture` (Nov 6, 2026)

`src/modules/mix_mod.f95` (module `mixture`): the closure moved out of
module `hvrb` with its notes, `hvrb_state`, `hvrb_pulls` and `hvrb_c_*`
renamed `mix_state`, `mix_pulls` and `mix_c_*`, `burn_cell_t` with them;
the code otherwise the same, character for character (checked by script).
Module `hvrb` keeps the rate law, the topology and the step, and uses only
module `bits`. HVRB bit for bit: the 43 decks against the commit before,
`make test`, `make release`, and `compare_hvrb.py --quick` (AV 31 passed,
RS 26) with the same output.

## As built: step 3, the burn table and the per-cell arrays (Nov 6, 2026)

**Module `burn_table`** (`src/modules/btab_mod.f95`, uses only `bits`):
constants only. The model codes (`burn_none`, `burn_hvrb`) and names,
moved from module `shock`; `npar_max = 8`, `nst_max = 6`; every burn key
once (`bkey_name`, `bkey_check`: `> 0` or `>= 0`, `bkey_note`: the
resolved deck's comment); each model's row (`burn_npar`, `burn_key(s, ib)`:
its keys in slot order, as indices into the keys; `burn_nst`); HVRB's
slots by name (`hv_PR` ... `hv_TAU0`, `hv_phi`). A row longer than
`npar_max` does not compile.

**The deck** (module `deck`): the burn keys are looked up in the table
(`key_material`, `home_block`, the unknown-key hint); a material keeps
them by key (`material_t%bkey(nbkey)`), and its layers by slot
(`layer_t%bpar(npar_max)`, filled from the model's row). At the block's
end (`close_burn`): the model's keys required, any other burn key an
error, "PR is not a key of burn = ... (it is for burn = hvrb; ...)" (rule
2; no deck can reach it until a second model), and with no burn the
messages as before ("PR is only for burn = hvrb"), built from the table.
The resolved deck writes the model's keys in slot order with the table's
notes: the same file as before.

**The cells** (module `burn`): `bmod(k)`, `bpar(npar_max, k)` and
`bst(nst_max, k)`, protected, replace `phi` and the six HVRB arrays;
`lam`, `qk`, `gamk` (now protected), `rhold` and `eshold` are as they
were. `cell_burn`, pure, is the one place a model is chosen (`select
case (bmod(k))`) and takes the cell's constants as `intent(in)`;
`burn_step` and `burn_rate_rs` store what it returns. `maincode`'s setup
check (8) requires every `bst` and `lam` to be 0.

**The guards on the constants** (`bmod`, `bpar`, `qk`, `gamk`): protected
(another module that assigns to them does not compile); in module `burn`,
written only by `fill_constants`, from `alloc_burn`; handed to the models
as `intent(in)`, in pure and elemental routines. And `burn_audit`, at the
time loop's end: the constants filled again from the layers and compared
bit by bit with the cells'; any difference stops the run with an error
(a bug in bitwhiz, not in the deck). Silent when they agree, so a run's
output is unchanged; every burning deck in `make test` runs it. Each guard
was tried once in a scratch build (Nov 6): an assignment to `bpar` in
`maincode`, and to a model's constants in `cell_burn`, do not compile
(PROTECTED; INTENT(IN)); one cell's PR doubled at cycle 10 from inside
module `burn` (`ok_hvrb.deck`) stops the run, exit status 1, "the burn's
constants changed during the run in 1 cell", in the heartbeat's end line
too.

**Tests:** `tests/test_btab.f95` (7 checks, in `make test`): the keys'
rules on the table (unique names; no burn key named as another Material
key; each row's slots, `npar <= npar_max`, `nst <= nst_max`; every key a
model's, with a check and a note; the lookups; HVRB's row as the slot
table has it). HVRB bit for bit: the 43 decks (their resolved decks too)
against step 2's commit, `make test` (188 deck tests, their messages
unchanged), `make release`, and `compare_hvrb.py --quick`, AV and RS, with
the same output.

## As built: step 4, the lead-shock detector (Nov 6, 2026)

**Module `leadshock`** (`src/modules/lshk_mod.f95`, uses only `bits`):
`ls_h`, h = e - ½(V_0 - V) P from the cell's own state at t = 0 (e_0 = P_0
= 0, V_0 = 1/R0), and `ls_step`, pure, one step of the detector on its five
numbers (h at the last step, its largest since armed, the flag, P_s, t_s),
from the cell's state at the step's end. Module `burn` keeps them in a
cell's `bst(1:5)` and steps them in `burn_detect`, after the pressures,
for a model whose row says `burn_uses_ls` (module `burn_table`); no model
does yet, so `burn_detect` returns at once and every result is unchanged.

**The rule, as measured** (it differs from "The lead shock" above in three
details, each from a measurement below):

- **Armed** when the cell is compressed and h > `ls_floor`·C0², with
  `ls_floor` = 1e-10: a floor in the material's own energy scale (C0² in
  kJ/g), not one relative to h, which has no scale of its own at the start
  (a wave's first rows carry an exponentially small precursor, P down to
  1e-233 GPa, and h/(½ΔV·P) is about 1 there for any wave).
- **Marked** at the first of, after h's peak: h ≤ 0 (t_s interpolated);
  a local minimum, however shallow (t_s at the minimum); or a **stall**,
  the step's fall below `ls_knee` = 0.01 of the largest since the peak
  (t_s at that step). P_s is P at the step that marks it. Before the mark
  the P_s slot holds that largest fall, so five numbers still suffice.
- **No hysteresis:** a weak shock's h does not come back down (AV, 0.75
  GPa: from 3.1e-5 to a plateau at 3.0e-5 kJ/g), so a minimum "below half
  the peak" misses every weak shock.

**The study** (`tests/verification/study_leadshock.py`, 69 checks, all
pass; tolerances set from these runs). The runs write tracers every cycle,
and `bin/ls_replay` steps the detector through a tracer's rows exactly as
module `burn` steps a cell; an independent Python twin agrees with it on
all 96 tracers to 1e-12.

| Square shock, Al on Al, 1.5 mm deep | exact P (GPa) | P_s, AV, 25-200 zones/mm | P_s, RS | t_s lag, 25 → 200 zones/mm |
|---|---|---|---|---|
| u_p = 0.05 km/s | 0.7460 | -0.37 to -0.04 % | -0.05 to +0.01 % | AV 36 → 14 ns, RS 39 → 6 |
| u_p = 0.2 | 3.0958 | -0.31 to -0.03 % | -0.03 to 0.00 % | AV 33 → 6.5, RS 31 → 4 |
| u_p = 1 | 18.459 | +0.15 to +0.55 % | -0.10 to -0.05 % | AV 13 → 1.2, RS 18 → 1.8 |
| u_p = 3 | 77.729 | +0.97 to +1.09 % | +0.46 to +0.77 % | AV 8 → 0.7, RS 8 → 0.7 |

AV's P_s at strong shocks is high by about 1 % on every mesh: its
post-shock ringing, which the mark samples at a phase; RS's ringing is
smaller. The lag is the smeared shock's rise: first order for strong
shocks, slower for weak ones.

- **A decaying shock** (`leadshock/decay.deck`, a 0.25 mm flyer): P_s at
  0.5 and 1 mm within 0.5 % of 18.459 GPa on every mesh, then falling with
  depth as the release overtakes the shock, 17.2, 14.5 and 11.3 GPa at 3, 4
  and 6 mm (200 zones/mm), AV and RS within 0.6 %.
- **A ramp that steepens into a shock** (`ramp_linear`, 0.3 mm into the
  window): marked at the shock, 8.38 to 8.57 GPa, every mesh, AV and RS
  within 2.0 %.
- **The floor:** every value from 1e-14 to 1e-7 (times C0²) marks every
  shock above and none at P ≈ 0; with none, two false marks at P ≈ 0 (a
  precursor's round-off wiggle read as a minimum); at 1e-6 five weak
  shocks are missed. 1e-10, three decades from either edge.
- **The stall:** without it, a weak shock in AV was marked at h's first
  local minimum, where round-off ends a slow creep: 36, 38, 73 and 117 ns
  after the shock at 25, 50, 100 and 200 zones/mm, growing with the mesh,
  so not converging. With it, the lag shrinks for every value from 0.003
  up; larger values mark sooner but move P_s where P falls right behind
  the front (a decaying shock: up to 1.3 % at 0.003, 2.7 % at 0.03 and 0.1,
  5 % at 0.3, against 0.01). 0.01.

**Open (DK): a smooth ramp.** Its foot is a compression front too, and the
detector, as Menikoff and Shaw wrote it, marks the first one: h rises a
little there (AV's q, RS's dissipation) and comes back as the ramp goes on.
So `ramp_linear` 0.05 mm into the window, where the ramp still takes 0.34
us to rise, is marked at its foot, at a P_s that falls with the mesh: AV
0.67, 0.44, 0.30, 0.20 GPa and RS 0.47, 0.30, 0.19, 0.11 at 25, 50, 100,
200 zones/mm (toward 0, about as Δx^0.6 for AV and Δx^0.7 for RS). This
differs from "with no lead shock nothing is marked" above: the gate of the
three P_S models opens at a smooth ramp's arrival, with P_s → 0. Nothing
tried tells a smooth ramp from a weak shock on a coarse mesh: the size of
h's peak against the work ½ΔV·P (0.009 to 0.03 for the ramp, falling with
the mesh, but 0.01 to 0.03 for weak shocks too), or the time from h's peak
to the mark (the ramp's foot is marked within one to three of the cell's
sound transits, as quickly as a strong shock). The choice is DK's, at
step 5.

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
| `thermalcascade` | ThermalCascade | SAND2025-09228 §5.2.3 (ChatGPT 4o-mini) | done, step 5 |
| `halo` | HALO: Hot-spot Activation, Loss and Overlap | Kittell (2016), ADRB, revised here | this note |
| `claude` | CLAUDE: Centers Lit by Accumulated Unrecoverable Dissipated Energy | proposed by Claude (Anthropic), Nov 6, 2026 | this note |

Then graded materials (TODO.md, section 7) (**DK**). The order serves the
JOSS case (sustained work, one model per release) and an SCCM 2027 study.

**Sources** (`Class_Project/Literature/Burn_Models/`, outside the
repository): D. E. Kittell et al., "A Short Survey of Current Reactive Burn
Model Capabilities as of Mid-Year 2025", Sandia National Laboratories,
SAND2025-09228 (July 2025), doi:10.2172/2585504; L. G. Hill, B. Zimmermann
and A. L. Nichols III, "On
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
Settled in runs (step 4, "As built"): the floor is 1e-10 C0², and a smooth
ramp's foot is marked, at a P_s that falls toward 0 as the mesh refines;
the gate then opens, and each model's own rate decides what follows
(**DK**, Nov 7: option (a), as AV's behavior was taken in `av_study.md`).

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

**Open, for CLAUDE's write-up (the v1.4.0 review, F-12, Nov 8).** The
review read this section and left three questions; none is decided here,
and the manual's CLAUDE section (1.5.0, under development) must settle
them or say they are open:
1. **What w is.** w += max(Δe + P Δv, 0) sums T ds, dissipated energy
   (kJ/g, W0's unit), not entropy; "the cell's entropy production" above
   names the wrong one. Either serves as the activation measure, and both
   desensitize a double shock: pick one and say it.
2. **Does w converge under RS?** With AV the sum converges to the exact
   integral along the shock path. RS captures a shock in one or two cells
   and a few steps whatever the mesh, so a left-point sum (P^n Δv) is off
   by a fixed fraction and does not converge with refinement. A
   trapezoidal P, and the planned test (w across a shock against the
   exact jump) run with both methods on several meshes, before "w
   converges with the mesh" is claimed.
3. **Per initial or per current volume.** NMAX and the moments M_j: per
   unit initial volume (the Lagrangian cell's mass) or current volume?
   A cell compressed 1.4 to 2 times needs the factor rho/rho_0 one way or
   the other. Also: centers added at the end of a step make nucleation's
   timing first order in Δt (growth's update is exact); say so.

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

**Decided (DK, Nov 7): option (a).** Accept and document, as AV's
behavior was (`av_study.md`): the gate opens at a smooth ramp's foot with
P_s → 0, and each model's own rate decides what follows (ThermalCascade
still needs T > TC). The alternative, a threshold on P_s, would be a deck
key that does not converge with the mesh.

## As built: step 5, ThermalCascade (Nov 7, 2026)

**Module `thermalcascade`** (`src/modules/tcas_mod.f95`, uses only `bits`):
`tc_rate`, HT (T - TC)^GT (1 + P_s/PR)^NS above TC and 0 at or below it
(a test, not max(T - TC, 0)^GT: at GT = 0 that would be 0^0, which gfortran
takes as 1), with P_s below 0 taken as 0; and `tc_step`, exact for the rate
at the step's start, lam2 = lam1 + (1 - lam1)(1 - exp(-r dt)), with 1 -
exp(-x) by its series below x = 0.5 (Fortran has no expm1; a first cut at
0.05 lost a digit just above it, measured). Elemental, no state.

**Its row** (module `burn_table`): `burn_tcas`, keys HT, TC, GT, NS (each
>= 0, so HT = 0 is the inert limit) and PR (HVRB's, shared), in that slot
order (`tc_HT` ... `tc_PR`); its history is the detector's five numbers
(`burn_uses_ls`), and lam is the model's own variable (module `burn`'s
`lam`). **Module `burn`:** `cell_burn` is given the cell's lam and T^n
(module `temperature`'s `tk`, the closure's one temperature, as it stands at
the step's start, both methods) and holds the gate: ThermalCascade burns only
once its lead shock is marked. The deck reader needed nothing new: the
table's row made `burn = thermalcascade`, its keys, their checks, the
resolved deck and every message ("ZR is not a key of burn = thermalcascade
(it is for burn = hvrb ...)", step 3's rule 2, now reachable).

**Tests.** `tests/test_tcas.f95` (5 checks) against
`tests/tcas_reference.py` (50 digits): the rate at 11 states (at, below and
just above TC; GT = 0; P_s < 0) to 3e-16; 1 - exp(-x) from 1e-16 to 50 to
2e-16; the step to 2e-22; 1000 steps at a fixed rate are one step (exact);
and the cascade at constant volume (T = Ta + b lam there, the closure's),
its time to lam = 0.99 first order in dt (errors 7.4e-5, 3.7e-5, 1.9e-5
for GT = 1; 1.7e-4, 8.5e-5, 4.3e-5 for GT = 1.5), against the 50-digit
quadrature. `test_btab` gains ThermalCascade's row (9 checks). Decks: two
good runs (`ok_tcas`, `ok_tcas_rs`: also OpenMP and release decks, and in
the history tests), two inert limits (`ok_tcas_inert`, `_rs`: HT = 0, the
detector running in every Material X cell, the inert run's heartbeat,
tracers and frames bit for bit, AV and RS), and six bad decks (a key left
out, an HVRB key in ThermalCascade and the reverse, GT < 0, TC without a
burn, the default eos).

**In runs** (`tests/verification/study_tcas.py`, 16 checks):

- **The lead shock in the hydro is its replay's.** With TC = 0, GT = 0,
  NS = 1, PR = 1 GPa and a small HT, a marked cell burns as a clock, so its
  first lam gives P_s back. At five Material X tracers, AV and RS, each
  cell burns from the row after the one where `ls_replay` marks it, and its
  P_s is the replay's to 3e-16: step 4's promise, kept inside the hydro.
- **Its detonation is HVRB's.** The example deck at 2.00 km/s, 25 to 200
  zones/mm: D over 6 to 9.5 mm within 0.07 % (AV) and 0.09 % (RS) of HVRB's
  class deck on the same mesh at 200 zones/mm (the same products). Both are
  0.5 to 0.7 % above D_CJ there: this deck's drive, as `av_study.md` found
  for HVRB. AV at 25 zones/mm is 2.7 % fast, HVRB's weak detonation again.
  Run distance 3.0 to 3.3 mm over the meshes (HVRB: 3.25 to 3.4).

**The equation sheets** (Nov 7, frozen in `doc/` with 1.4.0, their sources in
the course's `Equation_Sheets/`): `ThermalCascade_Eqns_v2` (the rate law as
proposed and as repaired, the gate) and `LeadShock_Eqns_v1` (the Hugoniot
function, 𝓗 = ½ q (V_0 - V) in a smeared shock), shared by the later P_S
models. Student-facing, not class-project sheets (DK); the remaining boxes
(the cascade at constant volume, one cycle, the rules on a mesh, what to
expect) are for later versions.

**The example deck** (`input/me697_tcas_2p00.deck`; HT = 3e-5, TC = 600 K,
GT = 1.5, NS = 2, PR = 7 GPa): an example, not a calibration, chosen so
that at 2.00 km/s it detonates near HVRB's 3.5 mm (at its 35 zones/mm, AV).
Its threshold is in T, so sharper than HVRB's: 1.75 km/s about 6 mm; 1.50
reacts first at 1.27 us and does not detonate within 10 mm; 1.25 and below
never pass TC and do not burn. The run log's "cells burnt out" counts lam
= 1 exactly, which this exact step reaches only by rounding (0 of 350 at
2.00 km/s, with lam 1 to round-off behind the front); left as it is, since
changing it would change HVRB's screen output. (Later, 1.6.1: counted from lam >=
1 - 1e-12 for every model, the v1.4.0 review's F-05(a); the screen only.)

## Step 6, FlashFire: the plan (approved Nov 12, 2026)

Approved by DK, Nov 12, with the step changed from Heun to RK4 (below).
FlashFire as designed above ("FlashFire", the seed at the lead shock, T_a,
the gate), with DK's decisions of Nov 12 and the details the build needs.

**Decided (DK, Nov 12):**
1. **Written up in the manual only** (`doc/manual/`, chapter 7's FlashFire
   section from "under development" to as built, with trace tags): no
   course equation sheet, since the manual now owns bitwhiz's equations
   (`doc/design/manual.md`).
2. **T follows lam within the step.** At fixed rho and e the closure makes
   vartheta linear in lam (manual, eq. (6.6)), so each sub-step uses
       T(lam) = T^n + (lam - lam^n) b,     b = (e_c + Q)/C_V,
   b from the cell's state at the step's start (e_c of the held solid if
   held). The cascade's feedback is resolved within the step for a few
   flops, with no EOS call.
3. **LAM0 required,** with 0 < LAM0 < 1; 1e-4 in the example deck.
4. Released as 1.6.0, on branch `flashfire`.

**The rate, as it will be built:**

    r(lam, T) = KFF (1 - lam)^AFF lam^BFF exp(-TA/T) (1 + max(P_s, 0)/PR)^NS

for T > 0 and lam < 1, else 0 (tests, not max(..)^.., as for HVRB and
ThermalCascade: no 0^0 at lam = 1 with AFF = 0). TA = 0 is no Arrhenius
factor; KFF = 0 the inert limit.

**The seed.** In the first step after the lead shock is marked, lam <-
max(lam, LAM0), then the sub-steps. At fixed rho and e, so energy is
conserved; P moves by about (dP/dlam) LAM0. For method RS the step's rate,
(lam^(n+1) - lam^n)/dt, includes the seed for that one step (with LAM0 =
1e-4 and dt about 3e-3 us, 0.03/us: small against a burning cell's rate).

**The step: RK4 sub-steps, Delta lam relative to lam and to 1 - lam
(DK, Nov 12).** FlashFire's topology has no closed form, so the step is
sub-cycled: each sub-step h = min(time left, eps min(lam, 1 - lam)/r), the
classical fourth-order Runge-Kutta method (RK4) with T(lam) at each stage,
lam kept in [LAM0, 1]; once 1 - lam < 1e-12 the cell is burnt out, lam = 1
(so a cell whose AFF < 1 reaches 1 in a finite number of sub-steps).
**eps = 0.1, an algorithm constant, not a deck key (DK).** Prototyped
against the constant-volume cascade (T = 740 K + 4200 K lam, TA = 12000 K,
Material X's scale), the time to lam = 0.99 against a 30-digit quadrature;
first Heun (the plan as first proposed):

| step | eps (or Delta lam_max) | dt = 1e-3 us | dt = 4e-3 us | sub-steps |
|---|---|---|---|---|
| Euler, Delta lam <= 0.01 (absolute, as first designed) | 0.01 | 9e-3 | | 580 |
| Euler, relative | 0.05 | 8e-3 | 2.1e-2 | 300-600 |
| Heun, relative | 0.1 | 2.1e-4 | 7.6e-4 | 190-540 |
| **Heun, relative** | **0.05** | **9.7e-5** | **3.3e-4** | **290-600** |
| Heun, relative | 0.02 | 3.6e-5 | 6.4e-5 | 670-860 |

(AFF, BFF = 1, 0.5 and 0.5, 0.5; AFF = 2, BFF = 0 gives 4e-4 at 0.05.)
Then RK4 against Heun, and against a fixed number of sub-steps per hydro
step (the trade's rule of thumb, 10 to 20, DK), for AFF, BFF = 1, 0.5 and
2, 0 (the ranges span both):

| step | dt = 1e-3 us | dt = 4e-3 us | rate evaluations | most sub-steps in one hydro step |
|---|---|---|---|---|
| Heun, 10 per step | 2.7e-4 to 4.7e-3 | 6.8e-4 to 1.7e-2 | 2,400-9,700 | 10 |
| Heun, 20 per step | 6.7e-5 to 1.3e-3 | 6.7e-4 to 7.9e-4 | 4,900-19,000 | 20 |
| Heun, relative, eps = 0.05 | 9.7e-5 to 4.0e-4 | 3.3e-4 to 4.3e-4 | 500-1,200 | 102-129 |
| RK4, relative, eps = 0.2 | 8.6e-6 to 4.2e-5 | 1.9e-5 to 1.0e-4 | 260-2,000 | 23-31 |
| **RK4, relative, eps = 0.1** | **2.0e-7 to 1.0e-5** | **2.9e-7 to 1.4e-5** | **510-2,200** | **49-64** |

Most hydro steps take one or two sub-steps (about one on average over a
whole burn); they pile up only in the runaway. A fixed number per step
spends 10 to 40 times the evaluations sub-stepping the induction, where
nothing happens, and too few in the runaway. RK4 at eps = 0.1 costs about
what Heun at 0.05 does and is one to three orders more accurate, its error
falling as a fourth-order method's should.
An absolute cap on Delta lam does not converge: in the slow induction from
LAM0, where most of the time is spent, it never limits the sub-step, and
the error is the hydro's dt. The relative cap does, with sub-steps over a
cell's whole burn of about (ln(1/LAM0) + ln(1e12))/eps, under 400 at 0.1.
What remains is the rate's frozen inputs (P_s, T^n, b), first order in dt,
as for every model.

**The burn table.** A row for `burn_ffire`: keys KFF (1/us, >= 0), AFF (>=
0), BFF (>= 0), TA (K, >= 0), NS (shared, >= 0), PR (shared, > 0) and LAM0
(new check, `chk_open01`: 0 < LAM0 < 1), in that slot order; 5 new keys
(nbkey 10 to 15), npar 7 (<= npar_max = 8); its history the detector's five
numbers (`burn_uses_ls`), nst 5. The deck reader takes the new check from
the table; its message: "LAM0 must be between 0 and 1 (not 0 or 1)".

**The code.** Module `flashfire` (`src/modules/ffire_mod.f95`, uses only
`bits`, pure and elemental, no state): `ff_rate` and `ff_step`. Module
`burn`: `cell_burn` gains b (an argument the other models ignore, so they
stay bit for bit) and FlashFire's case, gated as ThermalCascade is;
`burn_step` (AV) and `burn_rate_rs` (RS) compute b from the cell's carried
e_S and its eta at the step's start (before `temp_cold_cell` moves them).

**Tests.**
- `tests/test_ffire.f95` against `tests/ffire_reference.py` (50 digits):
  the rate at states across T > 0, T <= 0, lam at LAM0, near 1, AFF = 0,
  BFF = 0, TA = 0, P_s < 0; with T fixed (b = 0) and BFF = 0 against the
  closed form, (1 - lam)^(1 - AFF) linear in t (AFF /= 1), exp for AFF = 1;
  the cascade at constant volume against the 50-digit quadrature, its error
  falling with eps; the seed; burn-out at 1 - lam < 1e-12; KFF = 0, no burn.
- `test_btab`: FlashFire's row, and the new check.
- Decks: `ok_ffire`, `ok_ffire_rs` (also OpenMP, release and history
  decks), the inert limits `ok_ffire_inert`, `_rs` (KFF = 0, bit for bit
  with the inert run), and bad decks: a key left out, LAM0 = 0 and 1, a
  ThermalCascade key in FlashFire and the reverse, AFF < 0.
- `tests/verification/study_ffire.py`, as `study_tcas.py`: (E1) with TA = 0,
  AFF = BFF = 0, NS = 1, PR = 1 GPa, the rate is the clock KFF (1 + P_s), and
  Heun is exact for a constant rate, so the first burning row's lam gives
  P_s back against `ls_replay`; (E2) the example deck's detonation against
  mesh, AV and RS, beside HVRB's: D against HVRB's and D_CJ, run distance.
- HVRB and ThermalCascade bit for bit: the 43 decks and the burn decks
  against `9ec1ead`, `make test`, `make release`, `compare_hvrb.py
  --quick`, `study_tcas.py --quick`.

**The example deck** (`input/me697_ffire_2p00.deck`, method RS, order 2):
constants chosen, as ThermalCascade's were, so that 2.00 km/s detonates near
HVRB's 3.5 mm; LAM0 = 1e-4. An example, not a calibration.

## As built: step 6, FlashFire (Nov 12, 2026)

**Module `flashfire`** (`src/modules/ffire_mod.f95`, uses only `bits`):
`ff_rate`, KFF (1 - lam)^AFF lam^BFF exp(-TA/T) (1 + max(P_s, 0)/PR)^NS for
0 < lam < 1 and T > 0, else 0 (tests, so no 0^0 and no T = 0 division);
`ff_step`, the seed, then RK4 sub-steps with the relative cap (eps = 0.1),
T following lam as T1 + (lam - lam1) b, lam = 1 once 1 - lam < 1e-12, and a
hard limit of 100,000 sub-steps per call against a fault (not reached in
the tests or studies), and `ff_tslope`, b = (e_c + Q)/C_V.
Elemental, no state. **KFF = 0 is the inert limit, with no seed** (decided
in the build: otherwise no key would give an inert run, and the inert-limit
test, as ThermalCascade's at HT = 0, needs one).

**Its row** (module `burn_table`): `burn_ffire`, keys KFF, AFF, BFF, TA (>= 0),
NS (ThermalCascade's), PR (shared) and LAM0, with the new check
`chk_open01` (0 < LAM0 < 1; module `deck`: "LAM0 must be between 0 and 1
(not 0 or 1)"); slots `ff_KFF` ... `ff_LAM0`; its history the detector's
five numbers. **Module `burn`:** `cell_burn` takes b, from `ff_slope`, (e_c
+ Q)/C_V at the step's start (`ff_tslope`, from the carried e_S and its
eta, or the held solid's), computed before `temp_cold_cell` in `burn_step` (AV) and at
the cycle's start in `burn_rate_rs` (RS); 0, and unused, for the other
models.

**HVRB and ThermalCascade bit for bit:** every input deck and every `ok_`
deck (48), debug builds, against `9ec1ead`: heartbeat, tracer rows, history
frames, the resolved deck and every bitmap identical (the screen's
heartbeat size line aside, which carries the build's version string).

**Tests.** `tests/test_ffire.f95` (6 checks) against `tests/ffire_reference.py`
(50 digits): the rate at 11 states to 2.1e-15; the seed exactly, and KFF = 0
seeding nothing; a constant rate exactly; a fixed T with BFF = 0 against the
closed forms (AFF = 1, 0.5, 2, 1.5), 1 - lam to 1.7e-6, and burn-out at lam
= 1 exactly; the cascade at constant volume, where T follows lam exactly, so
only the integration errs: the times to lam = 0.5 and 0.99 within 6e-7 for
1000 and 100 hydro steps; and b against module mixture's own vartheta at
two lam (held solid too), to 3.5e-16 (added after an independent review
found `ff_slope` otherwise untested). `test_btab` gains FlashFire's row (check 9, and 4
knows `chk_open01`). Decks: `ok_ffire`, `ok_ffire_rs` (also OpenMP, release
and history decks), the inert limits `ok_ffire_inert`, `_rs` (KFF = 0, the
inert run bit for bit, XRN aside), six bad decks (LAM0 left out, 0 and 1;
AFF < 0; a ThermalCascade key in FlashFire and the reverse).

**In runs** (`tests/verification/study_ffire.py`, 18 checks):

- **The lead shock in the hydro is its replay's.** With TA = 0, AFF = BFF =
  0, NS = 1, PR = 1 GPa, KFF = 1e-6 and LAM0 = 1e-12, a marked cell is
  seeded and burns at the constant rate KFF (1 + P_s), which RK4 integrates
  exactly: at five tracers, AV and RS, each cell burns from the row after
  `ls_replay`'s mark, its P_s the replay's to 1e-15.
- **Its detonation converges.** The example deck at 2.00 km/s, 25 to 200
  zones/mm: D 7.5075 (AV) and 7.5099 km/s (RS) at 200, within 0.1 % of 100
  zones/mm's and +0.10, +0.13 % from D_CJ; 0.44 to 0.47 % below HVRB's on the
  same meshes (HVRB +0.6 %: the deck's drive holds HVRB, with its shorter
  reaction zone, further above D_CJ; FlashFire's lam = 0.99 is about 0.16 mm
  behind its front, HVRB's 0.07). AV at 25 zones/mm is only 0.4 % fast: the
  gate keeps the burn out of AV's smeared shock. Run distance 3.35 to 3.60
  mm over the meshes.

**The example deck** (`input/me697_ffire_2p00.deck`; KFF = 55, AFF = 1, BFF
= 0.5, TA = 3000 K, NS = 1, PR = 7 GPa, LAM0 = 1e-4): an example, not a
calibration, chosen so that at 2.00 km/s it detonates near HVRB's 3.5 mm;
at its 35 zones/mm, RS order 2: 1.75 km/s 4.9 mm and 1.50 7.2 mm (HVRB 5.0
and 7.5); at 1.25 a burn behind the shock that does not detonate within
10 mm, at 1.00 a slow one (no threshold). **A first set** (KFF = 400, TA =
6000 K, NS = 2), tuned to the same 3.5 mm, burned within one cell at the
detonation front on every mesh to 200 zones/mm (the Arrhenius factor at
the von Neumann state, and (1 + P_s/PR)^2 there, made the burn
near-instantaneous), and its D did not converge (RS 7.486 to 7.599 km/s
from 25 to 200 zones/mm; AV 2.7 to 3.4 % fast): replaced by the set above,
whose reaction zone the mesh resolves.

**The manual:** chapter 7's FlashFire section, as built, with its trace
tags; chapter 1 and the appendices updated. No course equation sheet (DK).

## Step 7, StochasticIgnite: the plan (approved Nov 12, 2026)

StochasticIgnite as designed above ("StochasticIgnite"), with DK's change
of Nov 12: Z varies in time, as an Ornstein-Uhlenbeck process, instead of
being frozen. Three prototypes were run first (Python, in 
`Claude outputs/si_prototypes/`); their numbers are below.

### What the survey proposed, what bitwhiz repairs, and what it extends

The manual's section and the example deck will say this, in three layers
(DK: "the guide will need to say how we remedied the proposed model"):

| | As proposed (SAND2025-09228 §5.2.2) | In bitwhiz | Why |
|---|---|---|---|
| Rate | dlam/dt = g(lam) (mu + sigma Z) (1 + P_s/P_ref)^m | the same, with (mu + sigma Z)+ | |
| g(lam) | not given | KJMA as a potential: lam = 1 - exp(-phi^a), dphi/dt the rest | **repair**: the model is not defined without it; the potential makes the step exact |
| mu + sigma Z < 0 | not addressed | floored at 0 | **repair**: a cell can not burn backward |
| P_S | the lead shock's | gated by the lead shock, P_S frozen there | **repair**, as the other two gated models |
| Z in time and space | "Z" random; when and where it is drawn not said | an Ornstein-Uhlenbeck process in time, correlation time TAUZ; one value per bin of width LC of the material's initial position | **repair** (some choice is needed) **and extension** (DK, Nov 12): one key spans both natural readings (below) |
| Z's values | not said | the bin's starting Z from the atmospheric table by SEED; its later steps from a counter-based generator | reproducible bit for bit on any number of threads |

**Both natural readings of the proposal are limits of the OU model.**
TAUZ -> infinity is a frozen field, one Z per bin for the whole run (the
design of Nov 6, kept as this limit); TAUZ = 1e30 gives it exactly, since
exp(-dt/TAUZ) rounds to 1 and the noise term to 0, with no special case.
The other reading, a fresh Z every cycle, is not a model at all: its
result depends on the time step, and as dt -> 0 the noise averages away
(measured below). The OU process gives that reading a meaning: fluctuations
with a correlation time of their own, which the mesh and time step then
resolve.

**The white-noise (Langevin-in-phi) limit is not reachable with the floor,
and so is not part of the model.** As TAUZ -> 0 with sigma^2 TAUZ fixed,
sigma -> infinity, and the floored rate's mean, E[(mu + sigma Z)+] = mu
Phi(mu/sigma) + sigma phi(mu/sigma) (Phi, phi the standard normal's
distribution and density), grows as sigma/sqrt(2 pi) without bound. A
Langevin equation in phi needs a phi that can decrease: a cell burning
backward. As TAUZ -> 0 at a fixed sigma, the model goes instead to a
deterministic burn at that mean rate, the floor's rectification: a closed
form, and a test.

### The model, as it will be built

    Z:          Z <- Z exp(-h/TAUZ) + sqrt(1 - exp(-2h/TAUZ)) xi,  xi ~ N(0, 1)
    phi:        phi <- phi + (MU + SIGMA Z)+ (1 + max(P_s, 0)/PR)^NS h
    lam:        lam = 1 - exp(-phi^AVRAMI)        (1 - exp(-x) as tc_om)

in sub-steps h of the hydro's dt, h <= TAUZ/10 (an algorithm constant; one
sub-step when TAUZ >= 10 dt). Z evolves from t = 0 in every cell of the
material, its stationary statistics from the start; phi and lam move only
once the lead shock is marked (the gate). The OU step is exact in
distribution for any h; the error is the quadrature of the rate over the
sub-step (left point, as the prototype measured).

### The random numbers

- **The atmospheric table** (`rand_mod`, 20,000 values from RANDOM.ORG,
  2025), checked: all distinct, all strictly inside (0, 1) (min 4.2e-6, max
  0.999955), mean 0.4985 (0.5, sigma 0.002), variance 0.08325 (1/12 =
  0.08333), Kolmogorov-Smirnov p = 0.51, chi-square (20 bins) p = 0.86,
  lag-1 correlation 0.0018 (sigma 0.007). Sound. Bin j's starting Z is
  AS241 of table entry mod(SEED + 7919 j, 20000) + 1 (7919, prime, shares
  no factor with 20,000 = 2^5 5^4, so 20,000 bins in a row read 20,000
  different entries). Its header ("Named RGB Color Values") and its own
  kinds are tidied, the review's F-13.
- **The steps' draws**, one per bin per sub-step, millions in a run, more
  than any table: a counter-based generator, u = U(SplitMix64 chained over
  (SEED, j, n, s)) for bin j, cycle n, sub-step s, mapped to (0, 1) as
  ((x >> 11) + 0.5) 2^-53. A pure function, so every cell of a bin gets the
  same draw, and any number of threads the same bits. Prototyped: over
  200,000 draws, uniform (KS p = 0.75), mean 0.5003, variance 0.08338;
  correlations between adjacent cycles -0.002, adjacent bins 0.001, two
  seeds 0.007 (sigma 0.002 to 0.005). In Fortran the 64-bit products are
  formed from 16-bit pieces, so no signed integer overflows; the unit test
  checks it against the Python's bits.
- **AS241** (Wichura 1988), uniform to standard normal: against 50 digits
  (mpmath), 3.3e-16 or better relative over 2,000 points and the tails, u
  from 2^-54 (the generator's smallest) to 1 - 2^-53.

### Measured: the OU model in a cell at constant state

One cell after its mark, MU = 2/us, S = 1, phi(0.5 us), 200,000 members (the
Monte Carlo sigma of a variance is 3e-3 relative):

| | dt = 0.02 | 0.01 | 0.005 | 0.0025 us |
|---|---|---|---|---|
| var(phi), TAUZ = 0.01 us, no sub-steps | +33 % | +8.8 % | +1.2 % | +0.09 % |
| var(phi), TAUZ = 0.1 us | +0.2 % | -0.3 % | +0.2 % | +0.6 % |
| var(phi), TAUZ = 1 us | +0.3 % | -0.05 % | +0.2 % | -0.5 % |

against the closed form 2 sigma^2 S^2 TAUZ^2 (t/TAUZ - 1 + exp(-t/TAUZ))
(sigma = 0.25 MU, so the floor is inactive). A step longer than TAUZ/4
misses the fluctuation within it; with sub-steps of TAUZ/4 and TAUZ/10 the
variance at TAUZ = 0.01 us and a hydro dt of 0.02 us is within the Monte
Carlo noise (+0.3, +0.4 %), the mean within 2.4e-4. Hence h <= TAUZ/10. With
the floor active (sigma = MU), the mean of phi is within the noise of a
fine-step reference at every dt tried, and the floored mean rate matches
its closed form (2.0081 against 2.0085 at sigma = 1; 9.013 against 9.019
at sigma = 20).

### The table, the keys, the state

| Key | Units | Check | Meaning |
|---|---|---|---|
| MU | 1/us | >= 0 | mean rate |
| SIGMA | 1/us | >= 0 | its standard deviation |
| AVRAMI | - | > 0 | Avrami exponent a |
| NS | - | >= 0 | exponent on (1 + P_s/PR) (shared) |
| PR | GPa | > 0 | reference pressure (shared) |
| LC | mm | > 0 | correlation length of Z (bin width) |
| SEED | - | an integer, 0 to 19,999 (a new check) | the realization |
| TAUZ | us | > 0 | correlation time of Z (1e30: frozen) |

npar 8 (= npar_max). **State: the detector's five, phi and Z: 7, so
nst_max goes from 6 to 7 (DK's decision: the high-water mark).** A cell's
bin j comes from its initial position, its layer's left face plus (k -
kfirst + 1/2) cell widths, over LC from x = 0 (the impact plane): one
realization across layers of the same material. Not stored: a cell keeps
its initial position's bin, being Lagrangian. Mesh refinement keeps every
bin's starting Z (the bins are the material's, not the mesh's); the later
draws, keyed by cycle, differ with the mesh, so a single run's path does
not converge, only the ensemble's statistics.

### Tests

- `tests/test_sign.f95` against `tests/sign_reference.py` (50 digits): AS241
  over the range and the tails; the generator's bits against the Python
  reference (so the 16-bit products are right); the OU step's statistics
  (mean, variance, lag-1 correlation exp(-h/TAUZ) over 10^5 draws, within
  their sampling error); SIGMA = 0 against KJMA's closed form, lam = 1 -
  exp(-(MU S t)^a), exact; TAUZ = 1e30, Z frozen bit for bit; the floored
  mean rate against mu Phi + sigma phi in the fast-TAUZ limit; the same
  SEED, the same bits.
- `test_btab`: StochasticIgnite's row, the SEED check, nst_max = 7.
- Decks: good (AV, RS; also OpenMP, release, history decks), the inert
  limit (MU = SIGMA = 0), bad decks (a key left out, SEED out of range or
  not an integer, TAUZ = 0, LC <= 0, another model's key).
- `tests/verification/study_sign.py`: E1, the lead shock in the hydro
  against its replay (SIGMA = 0, a = 1: a clock, so the first lam gives P_s
  back); E2, **an ensemble**: N seeds of the example deck at 2.00 km/s,
  25 to 200 zones/mm, AV and RS: the mean and spread of the run distance
  and of D, converging with the mesh (the mean of D within 1 % of D_CJ);
  E3, TAUZ = 1e30: each bin's Z the same on every mesh. Outside `make
  test`; its run time set by N.
- HVRB, ThermalCascade and FlashFire bit for bit.

### The example deck and the manual

`input/me697_sign_2p00.deck`, method RS, order 2: constants chosen, as the
others' were, so that 2.00 km/s detonates near HVRB's 3.5 mm on average,
with SIGMA large enough that the spread of run distance over seeds shows,
and TAUZ and LC on the reaction's scales (to be set by trial). The manual's
section, from "under development" to as built, with the three-layer table
above.

## As built: step 7, StochasticIgnite (Nov 12, 2026)

**Module `stochignite`** (`src/modules/sign_mod.f95`; uses `bits`,
`thermalcascade` for `tc_om`, and `random` for the table): `si_step`, a
cell's phi and Z over the hydro's dt, the plan's three lines in `si_nsub`
sub-steps (h <= TAUZ/10, at most `si_ns_max` = 1000), Z moving in every cell
and phi only once marked; `si_z0`, bin j's starting Z, AS241 of table entry
modulo(SEED + 7919 j, 20000) + 1; `si_uniform`, the counter-based draw,
SplitMix64 chained over (SEED, j, n, s) in 16-bit pieces; `si_normal`,
AS241 (PPND16). Pure, no state. As the plan, but for:

- **The uniform is 52 bits, ((x >> 12) + 1/2) 2^-52, not the plan's 53**
  ((x >> 11) + 1/2) 2^-53: the largest 53-bit value, 2^53 - 1/2, is not a
  double and rounds to 2^53, so u could be exactly 1 and AS241 infinite.
  With 52 bits every u is a double strictly inside (0, 1), from 2^-53 to 1
  - 2^-53.
- **The cycle is module `burn`'s own**, `cycle_next` (1 on the first step;
  `burn_track` sets it to ncycle + 1 after each), not an argument from
  `maincode`: the same number, and `maincode` and its OpenMP clauses
  unchanged. Each cell's bin, `sbin(k)`, is set in `alloc_burn` from its
  layer's left face plus (k - kfirst + 1/2) cell widths, floor(x0/LC),
  counted from x = 0 (after the origin shift) and kept within +-2^62. Two
  layers of StochasticIgnite materials in one bin with one SEED share its
  draws; with another TAUZ their Z differ, as they should.
- On cycle 1 Z starts from the table (`first`, cycle_next = 1), since `bst`
  starts at 0 (maincode's setup check (8) requires it).
- **The OU step's noise factor is sqrt(1 - A^2), as written, not the plan's
  sqrt(1 - exp(-2h/TAUZ)):** the same number, but at TAUZ = 1e30 A rounds
  to 1 and this gives exactly 0, so Z is frozen bit for bit with no
  special case. The cancellation costs at most 3e-9 of the noise's
  amplitude for h/TAUZ >= 1e-8 (measured by the review); between that and
  1e-16 the amplitude's relative error is large but the amplitude itself
  negligible.
- `si_z0` reduces j modulo 20,000 before multiplying by 7919, so the entry,
  modulo(SEED + 7919 j, 20000) + 1, is exact for any bin (an LC below
  about 1e-14 mm would otherwise overflow 7919 j; found by the review).
- **Seeds, frozen:** 7919 is invertible modulo 20,000, so every SEED's
  sequence of starting Z over the bins is SEED 0's, shifted: SEED + 7919
  starts bin j where SEED starts bin j + 1. With TAUZ = 1e30 two such seeds
  are one field moved by whole bins, not two samples (about 0.4 % of seed
  pairs within 40 bins of each other; none among the study's). With TAUZ
  finite the later draws, keyed by SEED itself, differ. Documented (the
  example deck, `input/README.md`, the manual), not changed.

**Its row** (module `burn_table`): `burn_sign` = 4, keys MU, SIGMA (>= 0),
AVRAMI, LC, TAUZ (> 0), NS and PR (shared), SEED with the new check
`chk_count` (a whole number, 0 or more; module `deck`: "SEED must be a whole
number, 0 or more") and `bkey_max` 19999; slots `si_MU` ... `si_TAUZ`; its
history the detector's five, phi (`si_phi` = 6) and Z (`si_z` = 7), so
`nst_max` = 7. **Module `burn`:** `cell_burn` takes the bin and the cycle;
StochasticIgnite's case calls `si_step` with the gate as its `marked`.

**HVRB, ThermalCascade and FlashFire bit for bit:** every input deck and
every `ok_` deck of 1.6.1 (53), debug builds, against `898a473`: heartbeat
rows (the wall clock column aside), tracer rows, history frames and the
screen, identical once the run's time and version stamps are set aside.

**Tests.** `tests/test_sign.f95` (8 checks) against `tests/sign_reference.py`
(50 digits): AS241 at 18 points from 2^-54 to 1 - 2^-53, to 4.4e-16 (2
ulp; the reference takes each u as the double the Fortran reads, exactly:
near u = 1/2 and 1 the deviate depends on u's last bit, not on AS241); the
generator's u exactly the Python's, 8 cases (negative and 2^40-sized bins,
large cycles); 7 bins' starting Z to 6.7e-16 (two at +-2^62); the OU step over 200,000
cycles, at dt = TAUZ/20 (one sub-step) and 2 TAUZ (20): mean, variance and
lag-1 correlation within 4 of their AR(1) standard errors (all within 1);
SIGMA = 0 against the clock's closed form over 1000 steps, phi = MU S t and
lam both to 1.3e-15, with phi ending near 0.33 (the first version ended at
phi = 13, where lam rounds to 1 and the check could not fail: found by the
review); TAUZ = 1e30 freezes Z at the table's value, bit for bit, 5000 steps;
the floored mean rate, 4 cases, 400 bins over 200 TAUZ, within 4 standard
errors of mu Phi(mu/sigma) + sigma phi(mu/sigma) (all within 1; the bound
has 1e-3 of the rate added, the left-point quadrature's share, about 0.4
standard errors); the same SEED the same bits. `test_btab` gains the row (check 11; 4 knows
`chk_count`, 10 SEED's 19999). Decks: `ok_sign`, `ok_sign_rs` (also OpenMP,
release and history decks), the inert limits `ok_sign_inert`, `_rs` (MU =
SIGMA = 0: Z steps, nothing burns; the inert run bit for bit, XRN aside),
seven bad decks (SEED 12.5, -1, 20000; LC = 0; TAUZ = 0; SEED left out; a
FlashFire key). `make test`: 224 deck, 16 OpenMP and 40 history tests.

**In runs** (`tests/verification/study_sign.py`, 32 checks, about 5
minutes):

- **E1, the lead shock in the hydro is its replay's.** SIGMA = 0, AVRAMI =
  1, NS = 1, PR = 1 GPa, MU = 1e-6: at five tracers, AV and RS, each cell
  burns from the row after `ls_replay`'s mark, its P_s (from -ln(1 -
  lam_1)) the replay's to 3e-16.
- **E2, the detonation as an ensemble** (RS order 2, 12 seeds; the plan's
  AV and 200 zones/mm left out for time): every run detonates; mean run
  distance 3.31, 3.26 and 3.13 mm at 25, 50 and 100 zones/mm (standard
  errors 0.13 to 0.19; standard deviation 0.4 to 0.65 mm), 50 and 100
  agreeing: their paired difference, seed by seed, -0.13 +- 0.21 mm, 0.6
  standard errors (paired, since a seed starts from the same Z on both
  meshes: the review's suggestion; the pairs turn out only weakly
  correlated). **Its D is not within 1 % of D_CJ, as
  the plan expected, but 2 to 4 % below** (7.20 to 7.34 km/s over 6 to 9.5
  mm): a bin whose rate is low or floored when the front reaches it burns
  behind the front, too late to drive it. Without the noise (SIGMA = 0) the
  same deck runs at +0.13 % of D_CJ, converged (50 to 100 zones/mm,
  -0.007 %): so the deficit is the noise's, a result of the model, not of
  the hydro. Reported, not checked.
- **E3, frozen noise** (TAUZ = 1e30, SIGMA = 1.4, so about one bin in six
  has MU + SIGMA Z0 <= 0), 4 seeds, 25 and 50 zones/mm, AV and RS: the
  Material X cells with lam = 0 at the end are exactly the cells of the bins
  the table predicts dead (Z0 at 50 digits, the bins by the Fortran's
  arithmetic), 1 to 5 dead bins of 20 per seed, on every run; every other
  cell burns. A test of the bins, the table, AS241 and the freeze together,
  in the hydro. (The run distance of one frozen seed is also nearly
  mesh-converged, but the 0.9 D_CJ criterion jumps when a seed's front sits
  near it: not used.)

**An independent review** (a Claude subagent, Nov 12, read-only) found no
Critical or High defect: it re-derived the 64-bit arithmetic against
Python's integers (72 cases, including j = -2^62 and n = 2^31), AS241's 45
coefficients against CPython's PPND16, the cycle counter on both methods'
paths, OpenMP safety and the bins. Fixed from it: test_sign's check 5 could
not fail (above); `si_z0`'s overflow for tiny LC; E2's comparison made
paired; the frozen seeds' shift documented; doc inconsistencies (the table
entry written in full, max(P_s, 0) in `input/README.md`, 3.4 mm in the
deck's header).

**The example deck** (`input/me697_sign_2p00.deck`; MU = 1.35/us, SIGMA =
0.7/us, AVRAMI = 3, NS = 2, PR = 7 GPa, LC = 0.5 mm, SEED = 108, TAUZ = 0.2
us): at its 35 zones/mm, RS order 2, 2.00 km/s: mean run distance 3.4 mm
over 16 seeds (standard deviation 0.5, 2.75 to 4.65 mm), SEED 108 3.45 mm;
1.75, 1.50 and 1.25 km/s 4.0, 4.4 and 4.8 mm (8 seeds each): **a shallow
Pop plot, every speed detonating**, the model as proposed having no
threshold (P_s enters only through (1 + P_s/PR)^NS). A first set, NS = 1
(MU = 3.8, SIGMA = 2), was flatter still (1.25 km/s 5.2 mm, 2.00 4.2): NS =
2 chosen for some pressure sensitivity. About 3 % of bins have MU + SIGMA Z
< 0 at any moment; with TAUZ = 0.2 us they recover within about TAUZ.

**The manual:** chapter 7's StochasticIgnite section, as built, with the
three-layer table and its trace tags; chapter 1 and the appendices updated.
No course equation sheet (DK).

## Step 8, HALO: the plan (DK: approved Nov. 13, 2026)

HALO as designed above ("HALO", DK's revision of Nov 6 of his 2016 ADRB
model), made precise enough to build. Decisions marked **DK** are open; the
rest follows from the approved design or from what steps 5 to 7 built.
Checks below were computed for this plan (Python, 30 digits or scipy).

### What 2016 wrote, what the Nov 6 revision changed, what the build adds

| | ADRB, 2016 | HALO (Nov 6, approved) | The build (this plan) |
|---|---|---|---|
| Activation measure | E_D += sqrt(max(De (1 - lam), 0) max(-Dv, 0)) per step | the root over the product, De Dv: E_D -> integral of sqrt(sigma) dv over compression, mesh-independent | De, Dv from the database's old and new rho and e (no extra state; below) |
| Hot spots | eta += DErf - gamma eta (1-lam)^delta dt (explicit) | dissipation over TAUD; Erf of (E_D/E_D0)^BETAH | the exact step: decay first, then the new activation; 0 <= eta <= Erf(...) <= 1 always |
| Burn | lam += F eta^(1/d) p^n (eps - ln(1-lam))^((d-1)/d) (1-lam) dt | a potential: ds/dt = eta^(1/d) (max(P,0)/PR)^NH/TAUB, lam = 1 - exp(-s^d); no eps | exact for eta and P constant over the step; lam by tc_om |
| Constants | alpha, beta, gamma, delta, eps, F, d, n | ED0, BETAH, TAUD, DELTA, DFRAC, NH, TAUB, PR | TAUB replaced by its rate, KB (**DK**, below) |

The potential is the 2016 rate exactly: with lam = 1 - exp(-s^d),
dlam/dt = d s^(d-1) e^(-s^d) ds/dt = (d/(TAUB PR^NH)) eta^(1/d) P^NH
(-ln(1-lam))^((d-1)/d) (1-lam), the 2016 form with F = d/(TAUB PR^NH)
(checked symbolically). In s the rate is eta^(1/d)(P/PR)^NH/TAUB, positive
from lam = 0, so the starting problem, and eps with it, are gone.

### The model, as it will be built

Every step, in every HALO cell (no gate; DK's order: E_D, then eta, then s):

    E_D:  E_D <- E_D + sqrt( max(De, 0) max(-Dv, 0) ),   v = 1/rho
    eta:  eta <- eta exp(-(1 - lam)^DELTA dt/TAUD)
                 + Erf((E_D_new/ED0)^BETAH) - Erf((E_D_old/ED0)^BETAH)
    s:    s   <- s + KB eta_new^(1/DFRAC) (max(P^n, 0)/PR)^NH dt
    lam = 1 - exp(-s^DFRAC)

- **eta stays in [0, 1].** Decay only lowers eta and the activation term
  only adds what Erf gained, so by induction eta <= Erf((E_D/ED0)^BETAH) <= 1:
  a hot spot, once dissipated, is never re-activated (DK's design), and a
  weak first shock spends Erf's range that a later shock can not reuse.
- **The steps are exact** for dissipation alone (the exponential) and for
  eta and P constant (s linear in t: lam = 1 - exp(-(K t)^d), KJMA; d = 3
  is Hill and Zimmermann's sphere case). With both at once the split is
  first order in dt, the rate's own order, as every model's.
- **TAUD = 1e30** gives exp(...) = 1 exactly: no dissipation, no special case.

### Measured: the activation measure for Material X

E_D along the Rayleigh line of one shock, and of two to the same pressure
(Material X's Mie-Gruneisen, principal Hugoniot and reshock):

| P (GPa) | one shock | via 2 GPa | via 4 GPa | via 6 GPa |
|---|---|---|---|---|
| 8  | 0.296 | 0.254 (0.86) | 0.262 (0.89) | 0.278 (0.94) |
| 11 | 0.391 | 0.330 (0.84) | 0.331 (0.85) | 0.345 (0.88) |
| 15 | 0.506 | 0.421 (0.83) | 0.413 (0.82) | 0.424 (0.84) |

(GPa^(1/2) cm^3/g; ratios to one shock.) A double shock earns 12 to 18 %
less E_D, and through Erf(x^4) roughly half the hot spots: the
desensitization the model is for, before any dissipation. ED0 near 0.4
puts the class problem's 11 GPa shock at Erf(1) = 0.84.

Two properties of the measure, to be reported, not changed:

- **A ramp activates too.** E_D counts compression work, not only
  dissipation: a quasi-isentropic ramp to the same volume earns 71 to 85 %
  of the shock's E_D (4 to 15 GPa), so 0.26 to 0.52 of its activation at
  BETAH = 4. A measure of dissipation alone (De + P_mean Dv) is not an
  option: for a shock crossed in one Godunov step it is exactly 0 (Rankine-
  Hugoniot). The ramp decks (`input/ramp_*.deck`) will show it.
- **How many steps a cell takes to cross the shock matters a little.**
  Each step adds sqrt(mean sigma) Dv, so a shock crossed in one step
  earns up to 3/(2 sqrt 2) = 1.061 of the converged integral (a linear
  Rayleigh path from rest). The number of steps per crossing is set by the
  method and CFL, not by the mesh, so E_D converges with the mesh but
  differs between AV (a smeared shock, many steps) and RS (one or two): up
  to 6 %. The study measures it; an ED0 fitted with one method carries to
  the other only to that.

### Where De and Dv come from (DK: confirmed Nov. 13, 2026)

The database holds each cell's rho and e at the old and new time levels,
both methods (maincode, loops 2). **AV:** `burn_step` runs after the cell's
update, so De, Dv are this step's (n to n+1). **RS:** `burn_rate_rs` runs at
the cycle's start, so they are the last completed step's (n-1 to n): E_D
lags by one step under RS. On cycle 1 rho_old = R0 and the cell is at R0,
so Dv = 0 and nothing is added. The alternative, HALO keeping its own last
rho and e in `bst`, gives the same lag under RS (the burn must run before
RS's update) and costs two slots: not proposed. **DK** Comment: I prefer
not to add slots if at all possible. These are experimental models, and
having some dependencies on the method(s) is probably unavoidable. Still,
I would expect tracer data from the different methods to at least pass
the eyeball test as being similar, if not to machine precision levels.

### The table, the keys, the state

| Key | Units | Check | Meaning |
|---|---|---|---|
| ED0 | GPa^(1/2) cm^3/g | > 0 | activation scale |
| BETAH | - | > 0 | sharpness of activation (2016: 4) |
| TAUD | us | > 0 | dissipation time (1e30: none) |
| DELTA | - | >= 0 | reaction-deficit exponent of dissipation (2016: 2) |
| DFRAC | - | > 0 | fractal dimension of the burn, 2 (cylinders) to 3 (spheres) |
| NH | - | >= 0 | exponent on max(P, 0)/PR (P, not P_s: not NS) |
| KB | 1/us | >= 0 | burn rate at P = PR, eta = 1; 0 the inert limit |
| PR | GPa | > 0 | reference pressure (shared) |

npar 8. **State: E_D, eta and s, `bst(1:3)`** (`ha_ed`, `ha_eta`, `ha_s`);
not gated, so no detector slots; nst 3, nst_max stays 7. `burn_uses_ls`
false. NH, not NS: NS multiplies (1 + P_s/PR) in the gated models, and NH
is the power of P/PR itself (one key, one meaning).

### Decisions for DK

1. **The source, cited how?** The 2016 note (`Literature/Burn_Models/
   adrb_v1.pdf`) carries no release number and names the lab's code. The
   bitwhiz documents will state HALO in full from the Nov 6 revision and
   need nothing from the note; cite it as "D. E. Kittell, ADRB (2016),
   unpublished note", or name only the concepts (hot-spot activation and
   dissipation; SURF, SHS and Hill-Zimmermann's topology), as you prefer.
   **DK** Comment: this really was a note in my journal, and a week
   messing around with the production code. Never adopted, never peer-
   reviewed. Too bad we can't cite my lab notebook. I would probably
   cite the concepts as you say, and claim originality on the rest.
2. **KB for TAUB.** The approved keys have TAUB, a time, > 0. An inert
   limit that is bit for bit (as KFF = 0 and MU = SIGMA = 0) needs the rate
   to be exactly 0, which no finite TAUB gives (TAUB = 1e30 still burns
   ~1e-69). Proposed: KB = 1/TAUB, >= 0, KB = 0 the inert limit.
   **DK** Comment: this is fine.
3. **An equation sheet.** Step 8 says "with its equation sheet";
   FlashFire and StochasticIgnite went without one (DK), the manual's
   section serving. HALO is your model: a `HALO_Eqns_rev-0` in
   `Class_Project/LaTeX/` beside the HVRB sheet, drafted by Claude for your
   edit, or the manual's section alone?
   **DK** Comment: use the manual's section alone. Since this isn't a
   ME697 class model anymore, there should not be a separate equation
   sheet. We are approaching a new design philosophy with the later
   releases.
4. **De, Dv from the database** (above), with RS one step behind.
   **DK** Comment: yes, for the reason given in a prior comment.

### Tests

- `tests/test_halo.f95` against `tests/halo_reference.py` (50 digits): E_D
  along a Rayleigh path in N steps converging to the integral (and the
  one-step 1.061); nothing on expansion or at rest; dissipation alone, the
  exact exponential; activation alone, eta = Erf((E_D/ED0)^BETAH) exactly;
  eta <= Erf over a random history; eta and P constant, lam = 1 - exp(-(K
  t)^d) (d = 2, 2.3, 3); the potential against the 2016 rate at random
  states; TAUD = 1e30, no decay bit for bit; KB = 0, lam = 0 exactly.
- `test_btab`: HALO's row. Decks: `ok_halo`, `ok_halo_rs` (also OpenMP,
  release, history), the inert limits `ok_halo_inert`, `_rs` (KB = 0), bad
  decks.
- `tests/verification/study_halo.py`: **E1**, E_D in the hydro: with DFRAC
  = 1, NH = 0, BETAH = 1, TAUD = 1e30 and KB small, s grows at KB
  Erf(E_D/ED0) once the shock has passed, so a tracer's lam returns its
  E_D, against a replay of E_D from the same tracer's rho and e (as
  study_ffire's E1 replays the detector), and against the Rayleigh-line
  integral (AV, RS: the 6 % above). **E2**, the detonation against mesh,
  AV and RS, D to D_CJ. **E3**, desensitization: the class stack's own
  double shock (the Ta-Al flyer's second shock), with and without the Ta,
  and TAUD from short to 1e30, beside HVRB, which has no shock memory.
- HVRB, ThermalCascade, FlashFire and StochasticIgnite bit for bit.

### The example deck and the manual

`input/me697_halo_2p00.deck`, RS order 2, constants chosen so that 2.00
km/s detonates near HVRB's 3.5 mm (an example, not a calibration: the 2016
PBX 9502 constants do not carry over). The manual's HALO section from
"under development" to as built, with the three columns above.

# bitwhiz v1.4.0 Release Candidate — Independent Engineering & Scientific Review

**Reviewer:** Claude Fable 5.1 (Anthropic), acting as independent scientific-software reviewer
**Date:** November 7–8, 2026 (overnight audit; America/Denver)
**Subject:** `kitte048/bitwhiz`, branch `Fable-Audit-2026-Nov-7`, commit `cf0eab0dbefd3bcd88b63d89dd12ae56e66900dd` ("1.4.0: open source burn models …"), tagged `v1.4.0` (2026-11-07 22:08 -0700)
**Review environment:** Linux x86-64 (2 cores), GNU Fortran 13.3.0, Python 3.13 with mpmath 1.3.0, sympy 1.14, NumPy. The working copy was taken from the connected folder as an archive (SHA-256 `39d2df1f…b009e`); nothing in the repository was modified. All experimental artifacts live outside the source tree (see §10).

---

## 1. Executive Summary

**Overall assessment.** bitwhiz v1.4.0 is in good shape for release. I found **no defect in the production source that changes a scientific result**, no race condition, no memory error, and no regression against v1.3.4. The new release scope — the closure factored into module `mixture`, the burn table (`bmod`/`bpar`/`bst`), the lead-shock detector, and the ThermalCascade model — is implemented as its design note and equation sheets describe, and I was able to reproduce every important mathematical relationship and every in-situ integration independently, to round-off.

**What I verified independently (not by re-running the project's own tests):**

- The Mie-Grüneisen EOS (pressure, sound speed, the expansion cubic) against a 50-digit implementation written from the equation sheet with numerical derivatives: agreement to ≤ 6e-16 in P (relative to the bulk modulus) and ≤ 2e-14 in c over 160 random states of the four class materials; C³ continuity of the expansion branch proven symbolically.
- The mixture closure (P, c², ϑ, dP/dλ) for every branch — solid in, solid dropped, solid held and pushing, solid held and dropped — by symbolic differentiation for a generic Π(ρ) and e_S(ρ) (all closed forms exact) and by 40-digit finite differences against the Fortran `mix_state` at 120 random states (≤ 4e-15).
- The HVRB and ThermalCascade rate laws and steps at 50 digits (≤ 9e-16), including the series/direct switch points.
- The in-situ time integration of **both burn models inside the hydrocode**: λ(t) rebuilt in Python from each tracer's own P(t) (HVRB) or T(t) and an **independently written lead-shock detector** (ThermalCascade), AV and RS, reproduces the code's XRN column to ≤ 2.2e-16 at every Material X tracer, including the gate's timing (a cell burns from the cycle after its mark).
- D_CJ = 7.4999904 km/s, P_CJ = 24.999936 GPa and the constant-volume burn pressure 12.499968 GPa from the products EOS; G4's detonation speed is within +0.16–0.31 % (AV) and ±0.08 % (RS order 2) of D_CJ.
- **Bit-for-bit backward compatibility:** v1.3.4 (from the nanoHUB clone's tag) and v1.4.0 give **identical** heartbeats, tracer rows, history files and pictures on all 43 pre-1.4.0 decks (11 inputs + 32 `ok_` decks), and on the G1/G2/G3, decay, burn-release and free-surface verification decks with the release builds (144 output files compared). The shared hydro/EOS routines (`eos_mod` untouched; `av_mod`, `rs_mod`, `temp_mod`, `prod_mod` changed only in names/comments) carry no unintended change.
- **Thread determinism:** the OpenMP tests pass at 2 threads on this machine and, with an uncapped test build, at 2, 3, 4 and 8 threads on 2 cores (48/48, oversubscribed), bit for bit; AddressSanitizer/UBSan runs are clean; a serial build and an -O1 build give the same bits as the -O0/-O2 OpenMP builds.

**Most consequential findings** (none Critical or High):

1. **F-01 (Moderate, documentation):** the frozen AV equation sheet (`doc/Hydrocode_Eqns_v4`) states that the end face carries ½q_k in the energy update "and [that is] what bitwhiz does"; since v1.3.2 the code gives the void side no q. The deviation is correct physics and is recorded in TODO/design notes, but `doc/README.md`'s table does not flag it for the AV sheet as it does for the HVRB sheet. A user reproducing from the frozen sheet gets a different free-surface energy balance.
2. **F-02 (Low):** the ThermalCascade sheet (v2) documents the rate law only; the exact step, its first-order-in-Δt evaluation at (Tⁿ, P_s), the gate timing and P_s < 0 → 0 live in the design note, `input/README.md` and the code.
3. **F-04 (Low):** ThermalCascade's example run distance moves monotonically with the mesh (3.30 → 3.00 mm from 25 to 200 zones/mm, both methods) and is not yet shown converged; Δt-sensitivity is small (≤ 4 ns over CFL 0.6 → 0.15).
4. **F-03 (Low):** `hvrb_lambda`'s 16-term binomial series loses precision for X_R ≳ 40 (unphysical range; 7e-6 relative at X_R = 80).

**Recommendation: APPROVE WITH CONDITIONS.** The code is release-ready; the conditions are documentation items (F-01, F-08, and the ThermalCascade sheet's scope statement) that should be fixed in the release's documentation or a 1.4.1 patch, not source changes. See §7–§9.

---

## 2. Repository State and Release Scope

| Item | Finding |
|---|---|
| Branch / commit | `Fable-Audit-2026-Nov-7` at `cf0eab0`, working tree clean, **single squashed commit** (no history on this branch; see F-07). Tag `v1.4.0` points at it. |
| Release package | The nanoHUB clone (`~/Documents/Academic/bitwhiz`, read with permission) carries tag `v1.4.0` (2026-11-07 22:11) whose `src/bitwhiz/` is **identical** to this branch's `src/`, `input/` and `tests/` (gold data excluded by design). Tag `v1.3.4` (2026-11-06) served as the regression baseline. |
| Models in v1.4.0 scope | `burn = hvrb` (since 1.3.0) and `burn = thermalcascade` (new), with module `mixture` (closure), module `burn_table`, module `leadshock`. **FlashFire, StochasticIgnite, HALO and CLAUDE are design-note entries only ("planned")** — no source, no deck keys, no tests. The brief's model list is the full Phase-4 sequence; only its step 5 is in this release. |
| Build | `make` (debug, strict flags) and `make release` (-O2) build with **zero warnings** on gfortran 13.3; `make OMPFLAGS=` (serial) builds (one benign unused-argument warning). gfortran 8 is not available here (**NOT VERIFIED** locally; CI covers gcc 8/13). |
| Tests shipped | 7 unit programs (179 checks), 199 deck tests, 12 OpenMP tests (machine-dependent count), 32 history-file tests, 12 release tests; verification scripts `gold.py` (77), `compare_g1.py` (40), `compare_hvrb.py` (36 AV / 31 RS), `study_leadshock.py` (69), `study_tcas.py` (16), `study_av.py`. All pass here (§5). `make test` 4 m 16 s on 2 cores; `make release` 2 m 13 s. |

The "43 existing input decks" of the brief are the 11 example decks (the ThermalCascade example excluded) plus the 32 pre-1.4.0 `ok_*.deck` test decks; all 43 were compared bit for bit (§5.2).

---

## 3. Finding Register

Severity scale: Critical / High / Moderate / Low / Informational. Confidence: High / Medium / Low.

| ID | Sev. | Location | Description | Evidence | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| **F-01** | **Moderate** | `doc/Hydrocode_Eqns_v4.tex` (Boundary Conditions box, "Note: in the energy update the end face's stress is ½q_k … and what bitwhiz does"); `doc/README.md` row "Hydrocode_Eqns_v4 … checked against 311bf6d (solver source unchanged through 12e5d9f)"; `src/modules/av_mod.f95` `cell_step` lines 156–167 | The frozen AV sheet asserts a behavior the code no longer has: since v1.3.2 (11/05/26) an end face takes no q from the void so that AV conserves total energy at a free surface. The deviation is deliberate and correct (energy error now round-off; compare_hvrb reports 0.00000 % for AV), but the sheet is published as "the equations the code follows" and the doc/README table records the HVRB sheet's deviation ("the solid held … goes beyond the sheet") yet not this one. | Text of the three files; my runs: AV energy error 1e-16 on every deck (§5.3). | A student reproducing the sheet gets a free-surface energy leak of −10⁻⁴…−10⁻³ (the pre-1.3.2 numbers in TODO §8) and cannot match bitwhiz's heartbeat; the "frozen sheet" guarantee is overstated for AV. | Add a row note to `doc/README.md` (as for HVRB) and a "bitwhiz:" box or erratum line in the next AV sheet version; no code change. | High |
| **F-02** | Low | `doc/ThermalCascade_Eqns_v2.tex`; `doc/README.md` | The ThermalCascade sheet documents only the rate law and its two repairs. Not on the sheet: the exact step 1−λ ← (1−λ)e^{−rΔt}; that r uses Tⁿ and the frozen P_s (first order in Δt); that a marked cell burns from the following cycle; P_s < 0 taken as 0; the parameter table and units; the constant-volume cascade. These are in `doc/design/burn_models.md` (steps 5), `input/README.md` and the code, and the doc/README says the sheet is an "early version". | Sheet text; design note "As built: step 5"; `tcas_mod.f95`, `burn_mod.f95` `cell_burn`. | Reproducibility from the sheet alone is not possible; from sheet + design note + input README it is (I did it, §5.4). | Add the "Adding burn to one cycle" box (exact step, Tⁿ, the gate) and the parameter table before or soon after release; state on the sheet that the step is first-order in Δt. | High |
| **F-03** | Low | `src/modules/hvrb_mod.f95` `hvrb_lambda`, series branch (x < 0.05, 16 terms) | The truncated binomial series for 1−(1−x)^{X_R} is accurate only while binomial coefficients stay modest. Measured relative error just below the switch (x = 0.04999): 7.3e-12 at X_R = 40, **6.7e-6 at X_R = 80**; ≤ 1e-15 for X_R ≤ 20. | `verify/check_burn.py` against the Fortran driver, 50 digits. | None for physical X_R (0.7–5); a silent precision loss for unusual decks (X_R ≥ 40). | Document a validity range or switch to the direct form when X_R·x exceeds ~1 (or implement log1p/expm1-based evaluation). | High |
| **F-04** | Low | `src/modules/tcas_mod.f95` (rate at the step's start); `tests/verification/study_tcas.py` E2 | The cascade's rate is held at (Tⁿ, P_s) over the step, so the runaway time is first order in Δt (unit test 5 confirms: errors halve with dt). In runs the Δt effect is small: at 35 zones/mm, RS2, CFL 0.6 → 0.15 moves the PDV arrival by 1.8 ns and the mid-sample λ = 0.5 time by 3.8 ns (HVRB: 0.9 and 1.4 ns). The mesh effect is larger and monotone: run distance 3.30, 3.10, 3.05, 3.00 mm (AV) and 3.30, 3.15, 3.05, 3.00 mm (RS2) at 25–200 zones/mm — not yet visibly converged, while HVRB's spans 3.35–3.25 mm. | `exp/cfl/` runs; `verif_logs/study_tcas.log`. | The example's run distance carries an unquantified mesh error (≳ 2–3 % at 200 zones/mm); a temperature-threshold model is intrinsically sensitive to how the shock's temperature is resolved. | Extend E2 to 400 zones/mm and report the converged value; consider a predictor (midpoint) temperature for the rate in a later version; state the first-order property in the docs. | High |
| **F-05** | Low | `tcas_mod.f95` `tc_step`; `mix_mod.f95` partly-burnt branch; `maincode.f95` lines 1503–1508 ("Cells burnt out": `count(lam >= one)`) | ThermalCascade's exact step never reaches λ = 1. (a) The run log's "Cells burnt out" is then ~0 (1 of 350 by rounding in the example) — documented in `input/README.md`, but misleading on screen. (b) Because λ < 1, the solid EOS is always evaluated (at the cell's ρ, or ρ_hold); a fully burnt cell in a reactant with S2 ≥ 0 that is compressed past the Hugoniot's reach would stop the run with `eos_too_compressed`, where HVRB's exact λ = 1 would not. Material X (S2 < 0, no reach) is unaffected. | Code reading; `exp/robust/` runs (all 100 cells "burnt out" only when rounding reaches 1). | Diagnostic confusion for TC users; a latent robustness edge for future reactants. | Count burn-out as λ ≥ 1 − 10⁻¹² (or report "λ > 0.999") for every model; consider the same tolerance in the closure (materials.md already anticipates "a cutoff in 1−λ, made on evidence"). | High |
| **F-06** | Low | `src/main/bmpmaker.f95`, `src/colormaps/*.f95`, `src/drawings/*.f95`, `src/utils/random.f95` (external procedures); `Makefile` `-Wno-implicit-interface` | 23 call sites use implicit interfaces (`bmpmaker` ×11, `cmap_*` ×9, `apply_colormap` ×3, `r8_uniform_01`); the strict flags deliberately silence the warning. Argument-list mismatches there would not be caught at compile time. Picture code only, no physics. | `exp/static/build_warn.log` with `-Wimplicit-interface`. | Maintainability; a latent class of error in the drawing code. | Put the drawing/colormap routines behind module interfaces (or interface blocks) and drop the `-Wno-`. | High |
| **F-07** | Informational | Branch `Fable-Audit-2026-Nov-7` (1 commit, no parents) | The audit branch has no history: the release's own claims "HVRB bit for bit against the commit before" (steps 2–5) are not reproducible from the repository under review. I obtained v1.3.4 from the nanoHUB clone's tag instead (§5.2). | `git log`, `git count-objects`. | Reviewability; traceability of "frozen" checks. | For future audits, branch from `main` with history, or include the baseline tag; consider checking in golden outputs (heartbeat/tracer hashes) for a few HVRB decks so bit-for-bit regressions are a `make test` item. | High |
| **F-08** | Informational | `doc/design/materials.md` ("As built: step 5", G2 energy drift 0.0006–0.0017 %; "AV to 5e-5 or better"), README Status row | Stale numbers from before v1.3.2: AV now conserves total energy to round-off on every deck tried (heartbeat energy error 10⁻¹⁶; compare_hvrb AV "0.00000 %"). | `verif_logs/compare_hvrb_av.log`; `exp/robust/*.screen`. | Minor: a reader may think AV still leaks energy. | Update the numbers or mark them "(pre-1.3.2)". | High |
| **F-09** | Informational | `src/main/maincode.f95` `heartbeat_line`, `finish_tracers` (`integer(int64) :: tk`) vs `use temperature, only: … tk` | A local `tk` (clock ticks) shadows the host-associated temperature array `tk` in two contained procedures. Legal Fortran, no effect, but easy to misread. Also: `use_team` is an unused dummy in a serial build (one warning with `OMPFLAGS=`). | `-Wall` serial build log. | Readability. | Rename the clock variable (e.g., `tick`). | High |
| **F-10** | Informational | `src/modules/deck_mod.f95` `key_material` | `G0` and `S1` accept any real (zero, negative) without a deck check; `X_R` has no upper bound (F-03). Unphysical values are caught, if at all, by the EOS guards at run time. | Code reading. | Error messages less helpful than the deck reader's usual standard. | Optional: require S1 > 0 (or warn), note the X_R range. | High |
| **F-11** | Informational | `src/modules/lshk_mod.f95` `ls_step` (local-minimum case) | In the local-minimum case P_s is P at the marking step while t_s is set to the previous step; documented ("P_s = P at the step that marks it"). AV's P_s is ~1 % high for strong shocks (post-shock ringing) — measured and documented in the design note. | `study_leadshock.log` (69/69 pass); code. | None beyond the documented 1 %. | None required; consider P at t−dt for consistency in a later version. | High |
| **F-12** | Informational (not in release) | `doc/design/burn_models.md`, CLAUDE section | Design-level observations for the planned CLAUDE model (see §6). | Design text. | None for v1.4.0. | Address when the equation sheet is drafted. | Medium |
| **F-13** | Informational | `src/modules/rand_mod.f95` (10 204 lines), `src/utils/random.f95`, `timestamp.f95` | Compiled into every build but unused by a run (reserved for StochasticIgnite; `timestamp` "not used by the run"). | `objslist`; grep. | Build size/time only. | Leave, or move to the model that uses it. | High |
| **F-14** | Informational | OpenMP regions in `maincode.f95`, `burn_mod.f95`, `temp_mod.f95` | ThreadSanitizer (gfortran 13, uninstrumented libgomp) reports hundreds of false positives (e.g., "races" on variables written only before the parallel region), so TSan is inconclusive here. Determinism rests on the bit-for-bit tests, which I extended to oversubscribed 3/4/8 threads (48/48 pass). | `exp/static/tsan_runs/`; `exp/threads/bw/omp8.log`. | None. | If desired, run with an OMPT-aware TSan (LLVM/Archer) once. | High |
| **F-15** | Informational | `src/modules/mix_mod.f95` lam = 1 branch (`dpdlam`) | At λ = 1 the code (and its 50-digit reference) define dP/dλ by the gas-only form, which differs from the λ → 1⁻ limit of the mixture form by −P_sol + (1−λ)R0G0(e_c+Q). The hydro never uses dP/dλ at λ = 1 (RS's source needs λⁿ⁺¹ > λⁿ), so there is no effect; my interior-state check agrees to 9e-16. | `verify/check_mix.py`. | None. | A comment noting the convention suffices. | High |

No finding was Critical or High. Items the brief singled out — OpenMP data sharing, race conditions, array bounds, uninitialized variables, memory ownership, implicit conversions, error propagation — were examined and are discussed in §4 and §5.5; none produced a defect.

---

## 4. Architectural Review

**Layering.** The architecture after Phase-4 steps 2–4 is clean and the separation the brief asks about is real:

- `eos` (Mie-Grüneisen) and `products` (ideal gas) are stateless, elemental and model-independent. `eos_mod.f95` is byte-identical between v1.3.4 and v1.4.0.
- `mixture` holds the closure (P, c, ϑ, dP/dλ, the "solid held" rule) and nothing model-specific: it takes λ and the per-cell constants as arguments. I confirmed by text comparison that `mix_state`/`mix_pulls` are the former `hvrb_state`/`hvrb_pulls` verbatim (one comment aside).
- `hvrb` and `thermalcascade` are pure rate laws (stateless, elemental). `leadshock` is a pure five-number state machine stepped by the caller.
- `burn_table` is compile-time data (model codes, key names, checks, slot maps). `burn` owns all per-cell burn state (`bmod`, `bpar`, `bst`, `lam`, `qk`, `gamk`, `rhold`, `eshold`, `src`) and is the only module that writes it; `cell_burn` is the single dispatch point (`select case (ib)`).
- The deck reader is table-driven for burn keys; a new model is a table row plus a module plus a `case`, as claimed. The mixed-model deck I ran (HVRB layer beside a ThermalCascade layer, AV and RS) works without special handling.

**Accidental coupling.** I looked for places where a burn model reaches into shared thermodynamics and found none: `av`/`rs` receive a `burn_cell_t` value from `burn` and call `mix_state`; `temperature` receives optional arrays (`lam`, `q`, `rhold`, `eshold`) and knows nothing of models. The only cross-module dependency of note is that `burn` reads `temperature`'s `tk`, `ec`, `cv`, `t0` (protected) and calls `temp_cold_cell` — appropriate, since the closure needs e_S at the new volume before the pressure. The order of operations within a cycle (AV: faces → cells → burn step → states; RS: burn rate/source → predictor → faces → cells with cold step, hold, state) matches the design note and the sheets, and is identical in effect for both methods (my rebuilt histories, §5.4).

**State ownership and memory.** Every allocatable has an alloc/dealloc pair; burn and temperature arrays are allocated only when a deck uses them (inert decks allocate nothing new — hence bit-for-bit inert behavior). `bpar`, `bmod`, `qk`, `gamk` are `protected`, written once by `fill_constants`, passed `intent(in)` to pure/elemental routines, and re-derived and compared bit by bit by `burn_audit` at the run's end. AddressSanitizer with leak detection reports nothing on seven decks (AV/RS, HVRB/TC, spall, temperature, the class deck).

**Determinism and OpenMP.** All loops follow the write-back rule (each place writes only its own slots; neighbors' values read are never those being written in the same loop); reductions are order-independent (min/max/count, ties resolved to the lowest cell); the heartbeat sums and the detector/track passes are serial. `burn_step` is an orphaned `OMP DO` with a `REDUCTION(min)` on a dummy argument bound to a shared host variable — valid. `temp_update` lists optional arguments that may be absent in `SHARED` — explicitly permitted by the OpenMP 5.x specification (an absent optional argument in a data-sharing clause has no effect) and accepted by gfortran 8–13 (CI). Results are bit-identical at 1, 2, 3, 4 and 8 threads (the last three oversubscribed on 2 cores, which stresses scheduling) for all twelve OpenMP test decks.

**Numerical integration and time step.** The burn is operator-split at fixed (ρ, e) inside the cycle, so energy conservation is the hydro's own (verified: round-off for both methods). The CFL step uses the frozen-λ mixture sound speed; there is no Δλ-per-step or reaction-energy limiter — a known, documented limitation (TODO §3) that shows up as the 25-zones/mm difference, not as an instability. HVRB's topology is integrated exactly; its only error is the first-order quadrature of Φ(Pⁿ). ThermalCascade's exact first-order-in-(1−λ) step is unconditionally stable (no stiffness), with the rate first order in Δt (F-04). My stiff test (`GT = 0`, `HT = 1000 /µs`, TC = 0: a cell burns out in one step once marked) and an "instant" HVRB (τ₀ = 10⁻⁶ µs) run to completion with energy error 10⁻¹⁶ in both methods.

**Error handling.** EOS/closure failures return status codes and signaling NaNs; the time loop stops with the cell, layer, cycle and reason, closes every output file with the reason, and exits with status 1. The heartbeat's finite check backs up the traps in the release build. Deck errors are collected and reported together (199 deck tests). I found no path where a failure is silently ignored; in `cell_pressure` a burning cell whose gas has no sound speed is treated as void, by design.

**Verdict:** internally consistent, extensible and maintainable for its size; the one maintainability gap is the implicit interfaces in the picture code (F-06).

---

## 5. Scientific and Regression Verification

### 5.1 Equations checked independently

| Item | Method | Result |
|---|---|---|
| U_S(η) root of U_S = C₀ + s₁u_p + (s₂/C₀)u_p², dU_S/dη, dP_H/dV, de_H/dV identity, φ′, c² = V²(ρ₀Γ₀P − φ′) | sympy, generic | all identities exact |
| Expansion cubic a₁, a₂, a₃: φ and three derivatives continuous at V₀; φ′ form; "a₂ uses K₀′ = 4s₁−1" | sympy | exact (C³ as claimed) |
| P and c, four class materials, η ∈ [−0.6, 0.6], e ∈ [−0.2, 4] | 50-digit reference from the sheet (derivatives numerical) vs `mg_eos`, 160 states | max |ΔP|/K₀ 5.7e-16; max |Δc|/c 2.2e-14; every reference c² ≤ 0 state is flagged `eos_bad_soundspeed` by the code |
| Closure: ϑ = e − (1−λ)e_c + λQ solves the T-linear energy line; λ = 0 → P_sol(ρ,e); λ = 1 → (γ−1)ρ(e+Q) | sympy | exact |
| c² at fixed λ: solid-in (−λ(1−λ)(ρ₀Γ₀/ρ − γ + 1)²ϑ correction), dropped, held-pushing, held-dropped; dP/dλ both forms | sympy for generic Π, e_S | all four closed forms exact |
| `mix_state` P, c², ϑ, dP/dλ, 120 random states incl. 40 % held | 40-digit finite differences of my own closure | ≤ 1.2e-15, 3.6e-15, 7.4e-16, 8.6e-16 (interior λ) |
| HVRB λ(φ), Φ(P), ThermalCascade r, 1−e^{−x}, step | 50 digits, 324 + 40 + 40 + 14 + 30 points | ≤ 9e-16 except X_R ≥ 40 (F-03) |
| D_CJ, P_CJ, u_CJ, constant-volume burn | mpmath from γ = 2.60, Q = 4.8828 kJ/g, ρ₀ = 1.60 | 7.4999904 km/s, 24.999936 GPa, 2.0833307 km/s, 12.499968 GPa — the sheet's and the dataset's values |
| Temperature model: T = T₀e^{Γ₀η} + (e − e_c)/C_V, cold curve ODE, closure T = ϑ/C_V | derivation | consistent (ρΓ constant ⇒ (∂P/∂T)_V = ρ₀Γ₀C_V) |
| Lead-shock function ℋ = e − ½(V₀−V)P; ℋ = ½q(V₀−V) on a steady Rayleigh line; ℋ ≤ 0 on an isentrope from rest | derivation | consistent with the sheet |

Dimensional consistency (mm, µs, g/cm³, km/s, GPa, kJ/g, K) holds throughout; H_T's unit 1/(µs K^{G_T}) is correct; (1 + P_s/P_R)^{N_S} is always a positive base (P_s floored at 0, P_R > 0).

### 5.2 Regression: v1.3.4 → v1.4.0, bit for bit

v1.3.4 was built here from the nanoHUB clone's `git archive v1.3.4 src/bitwhiz` (debug and release; its own `make release` tests pass, 10/10). Comparison, with clock/build lines removed exactly as `tests/run_omp_tests.sh` does:

- **43 decks** (11 `input/` examples except the ThermalCascade one; 32 `ok_*.deck`), debug builds: **43 identical** (screen results, heartbeat, tracer rows, history body, every bitmap; the resolved decks' text too).
- **Verification decks**, release builds: `hvrb/g2_react.deck` (G2, 100 zones/mm, 11 758 cycles), `hvrb/g3_poplt.deck` (7 679), `inert_gauges/g1_inert.deck` (11 030), `leadshock/decay.deck`, `av_study/burn_release.deck` (5 017), `av_study/fs_square.deck`: **144 of 144 output files identical**.
- Gold data integrity: `hvrb/SHA256SUMS` 15/15 OK, `inert_gauges/SHA256SUMS` 5/5 OK.

Source-level: `eos_mod.f95` unchanged; `av_mod`, `rs_mod`, `temp_mod`, `prod_mod` differ only in `use mixture` and comments; `hvrb_mod` lost the closure and kept the rate law verbatim; `mix_state` and `mix_pulls` are the moved code character for character (one comment aside).

### 5.3 Reference comparisons (project scripts, re-run here)

| Script | Result | Notes |
|---|---|---|
| `gold.py` | 77/77 | reproduces the dataset README's tables; 50-digit self-test of e_c and T_H (4.4e-16) |
| `compare_g1.py` (inert, AV, 100 zones/mm) | 40/40 | first shock within 0.001 % of the exact impedance match; arrivals within -0.1 to +4.4 ns; TK the formula's at bitwhiz's own state to 1.9e-11 K; Material X TK 0.9–4.6 K below the reference (a known property of the reference's cold energy) |
| `compare_hvrb.py` AV | 36/36 | run distances equal to the reference's (G3 at 2.00 km/s one tracer spacing early), arrivals −0.2 to +4.8 ns, **energy drift 0.00000 %**, G4 D = 7.5150/7.5230/7.5118 km/s (+0.20/+0.31/+0.16 %), G5 PDV arrival converges to the reference's within 0.1 ns from 100 zones/mm |
| `compare_hvrb.py --rs` | 31/31 | G4 D = 7.5000/7.4941/7.5027 km/s (0.000/−0.079/+0.036 %); energy to round-off |
| `study_leadshock.py` | 69/69 | P_s within −0.37 … +1.09 % of exact Hugoniot pressures, 0.75–78 GPa, AV and RS, 25–200 zones/mm; ramp foot marked at P_s → 0 with the mesh (documented decision) |
| `study_tcas.py` | 16/16 | the detector inside the hydro equals its replay to 3e-16; TC's D within 0.07 % (AV) / 0.09 % (RS) of HVRB's on the same mesh; run distance 3.30 → 3.00 mm (F-04) |
| `study_av.py` | see Addendum A | 52 runs, 15 min; results appended when complete |

### 5.4 In-situ verification of the burn integration (independent)

Both example decks were run with tracer rows every cycle (`tracer_dt = 0`), AV and RS order 2, with tracers at 0.2, 0.5, 0.8 of Material X and at the PDV node.

- **HVRB:** φⁿ⁺¹ = min(φⁿ + Φ(Pⁿ)Δtⁿ, φ_end), λ = 1 − (1 − φ^{M_R}/X_R)^{X_R}, re-integrated in Python from each tracer's own pressure column: max |λ_rebuilt − XRN| = **2.2e-16** over ~2 000–2 700 rows at all four Material X tracers, both methods. (The Al-side "impact" tracer, inert, correctly shows no burn.)
- **ThermalCascade:** an independently written lead-shock detector (from the design note's rules, not from `lshk_mod`) replayed on each tracer's (ρ, e, P) rows gives the mark row and P_s; λ re-integrated with 1−λ ← (1−λ)e^{−r(Tⁿ, P_s)Δtⁿ} from the run's own TK column, starting the cycle after the mark: max |λ_rebuilt − XRN| = **1.1e-16** at every tracer, AV and RS. This confirms, inside the hydrocode: the gate's timing, the use of Tⁿ and the frozen P_s, the exact step, and the detector's rule set as documented.

### 5.5 Numerical robustness

- **Time step (CFL 0.6 → 0.3 → 0.15, RS2, 35 zones/mm):** HVRB PDV arrival 1.52579/1.52491/1.52541 µs (spread 0.9 ns), λ = 0.5 at mid-sample 0.87211/0.87144/0.87068 µs; ThermalCascade 1.50650/1.50504/1.50467 µs (1.8 ns) and 0.85552/0.85369/0.85175 µs (3.8 ns, monotone — the first-order rate). Both small compared with the mesh effects.
- **Mesh:** HVRB's G5 PDV arrival converges to the reference's within 0.1 ns from 100 zones/mm; AV's D is 3 % fast at 25 zones/mm and within 0.03 % from 200 (`av_study.md`, re-measured in Addendum A); ThermalCascade's run distance 3.30 → 3.00 mm, 25 → 200 zones/mm (F-04).
- **Stiffness and extremes:** `GT = 0, HT = 1000 /µs, TC = 0` (one-step burn-out once marked), HVRB `τ₀ = 10⁻⁶ µs` (one-step burn-out above P_I), and a mixed HVRB + ThermalCascade stack, AV and RS: all run to t_end, mass error 0, energy error ≤ 8e-16, no guard sound speeds, no voids. A weak shock (u_fly = 0.50 km/s) with ThermalCascade: no cell reacts (T < T_C), as intended.
- **Initialization/restart:** t = 0 checks (eight setup audits) pass on every deck; `plots_only` re-draws from files (history tests). There is no checkpoint/restart capability (not claimed).
- **Builds:** -O0 debug, -O2 release, -O1 sanitized, serial (no OpenMP): identical heartbeats and tracer rows on the decks tried. ASan+UBSan+LSan: clean on seven decks.
- **Exceptional states:** the EOS guards (`eos_too_compressed`, `eos_bad_soundspeed`, `eos_bad_density`) agree with the 50-digit reference's c² ≤ 0 states; a burning cell with no gas sound speed becomes void; `eos_too_compressed` for a partly burnt cell stops the run as documented (unit test).

### 5.6 Deck compatibility

Every pre-1.4.0 deck's syntax is accepted unchanged; the 147 `bad_*` decks produce their expected messages (199 deck tests); the resolved decks round-trip. New keys (`HT`, `TC`, `GT`, `NS`, `burn = thermalcascade`) collide with no existing key (`test_btab` rule 3), and a model takes only its own keys (reachable error now tested by `bad_hvrb_tcas_key`/`bad_tcas_hvrb_key`).

---

## 6. The Planned Models (design-level only; not in v1.4.0)

FlashFire, StochasticIgnite, HALO and CLAUDE exist only in `doc/design/burn_models.md`. They are out of the release scope and do not affect its readiness; the brief asked for independent scrutiny of CLAUDE's formulation, so these remarks are offered for the equation sheet to come (F-12):

1. **w and entropy.** w += max(Δe + PΔv, 0) accumulates **dissipated energy** ∫T ds (kJ/g, the unit of `W0`), not entropy. Both are admissible activation measures and both desensitize a double shock, but the note's phrase "the cell's entropy production" conflates them; the sheet should pick one. For a steady AV shock the discrete sum does converge to the area between the Rayleigh line and the shock path (a function of the end states and the EOS), as claimed. **Under RS**, where a shock is captured in 1–2 cells and O(1) steps regardless of mesh, the left-point quadrature Σ(Δe + PⁿΔv) is a fixed-fraction error of the exact integral and does **not** converge by refinement alone; a trapezoidal P̄ and the planned test "w across a shock against the exact entropy jump" (run on both methods and several meshes) are needed before the claim "w converges with the mesh" is accepted.
2. **Continuous nucleation and moments.** The moment ODEs M₀′ = ṅ, M₁′ = GM₀, M₂′ = 2GM₁, M₃′ = 3GM₂ and λ = 1 − exp(−(4π/3)M₃) are Avrami's extended volume exactly for Poisson-distributed centers; the binomial update for constant G is exact for growth, while new centers added at the end of the step make the nucleation timing first order in Δt (acceptable if stated). The sheet must say whether N_MAX and the M_j are per unit **initial** or **current** volume: in a Lagrangian cell compressing by ρ/ρ₀ ≈ 1.4–2, the extended volume fraction with radii grown in current space needs the ρ/ρ₀ factor.
3. **Growth law.** G = D₀(max(P,0)/P_R)^{n_g} with radii in mm and G in mm/µs is dimensionally consistent; "quench" is deferred, as the note says.
4. **HALO's activation measure** √(max(Δe,0)·max(−Δv,0)) is O(Δt) per step and so mesh/Δt-independent to first order for a smooth compression, as revised.

None of this bears on v1.4.0.

---

## 7. Release Readiness

| Requirement (brief §3–§7) | Status | Evidence |
|---|---|---|
| All 43 existing decks functional | **PASS** | 43 run and are bit-identical to v1.3.4 (§5.2) |
| `test_hvrb` passes | **PASS** | 14/14 (and all 179 unit checks) |
| Existing deck syntax/behavior compatible | **PASS** | 199 deck tests; resolved decks identical to v1.3.4's |
| Inert-material calculations unchanged | **PASS** | G1 inert deck and 11 inert examples bit-identical to v1.3.4; `ok_tcas_inert*` reproduce the inert run (hist tests) |
| Single-thread and multithread deterministic | **PASS** | 12/12 at 2 threads; 48/48 at 2/3/4/8 threads (uncapped test build, oversubscribed) |
| No unintended changes in shared hydro/thermo routines | **PASS** | `eos_mod` unchanged; av/rs/temp/prod diffs are renames/comments; outputs bit-identical |
| HVRB numerically bit-for-bit unchanged | **PASS** | §5.2 (debug and release builds) |
| 50-digit unit/reference tests | **PASS** | project's 7 programs pass; my independent EOS/closure/rate checks agree to ≤ 2e-14 |
| Closed-form limiting cases (λ → 0, 1; inert; constant-volume burn; D_CJ) | **PASS** | §5.1; `test_hvrb` checks 2, 6, 7; `study_tcas` |
| Dimensional consistency | **PASS** | §5.1 |
| Positivity/boundedness (λ ∈ [0,1], P ≥ 0 for burning cells, ϑ handling) | **PASS** | by construction (exact topology/exponential step); closure floors; hist test "XRN never falling" |
| AV and Riemann-solver configurations | **PASS** | all studies both methods |
| Mesh convergence | **PASS** (HVRB) / **PASS with caveat** (ThermalCascade run distance, F-04) | G5; study_tcas; Addendum A |
| Material X D_CJ = 7.4999904 km/s | **PASS** | analytic; G4 within 0.31 % (AV), 0.08 % (RS) |
| Inert and shock-propagation regressions | **PASS** | compare_g1 40/40; bit-for-bit vs v1.3.4 |
| Governing equations independently derived | **PASS** | §5.1 |
| Parameter interpretation and units | **PASS** | units table consistent with code and README; one documentation gap (F-02) |
| Integration accuracy and Δt sensitivity | **PASS** | §5.5 |
| Extreme/physically meaningful conditions | **PASS** | §5.5 stiff/instant/mixed/weak cases |
| Continuity across model transitions | **PASS** | mixed-model deck runs; closure continuous at ρ = ρ_hold and λ = 0 (verified algebraically) |
| Floating-point sensitivity | **PASS** | -O0/-O1/-O2/serial identical; `-ffp-contract=off` policy; one precision edge (F-03) |
| Initialization and restart | **PASS** / **NOT APPLICABLE** (no restart feature) | setup audits |
| Documentation ↔ code consistency | **PASS with conditions** | F-01, F-02, F-08 |
| Reproducibility by an external user | **PASS** | all documented calculations reproduced here from the repository alone, with the stated tools |
| Build/installation instructions | **PASS** | followed verbatim on a fresh machine; gfortran 8 **NOT VERIFIED** locally (CI) |
| Code quality: bounds, uninitialized, memory, conversions, races, dead code, portability | **PASS** | `-fcheck=all`, `-finit-real=snan` debug; ASan/UBSan/LSan clean; `-Wconversion-extra` shows only intended int kind conversions; no `-Wmaybe-uninitialized` at -O2; dead code only in unused utility modules (F-13) |

---

## 8. Recommended Actions

**1. Must fix before release** — none that touch source. Documentation:
- F-01: record the AV sheet's free-surface deviation in `doc/README.md` (and an erratum/"bitwhiz:" line on the next sheet version).

**2. Should fix before release (or in 1.4.1's docs):**
- F-02: complete the ThermalCascade sheet's "one cycle" box (exact step, Tⁿ/P_s evaluation and its first-order nature, the gate's timing, P_s < 0 → 0) and parameter table; until then, point to `doc/design/burn_models.md` step 5 from the sheet's header.
- F-08: refresh the stale energy-drift numbers (materials.md, README Status).
- F-05(a): make the "Cells burnt out" diagnostic model-independent (λ ≥ 1 − 10⁻¹², or report the count above 0.999).

**3. Recommended future improvements:**
- F-04: extend ThermalCascade's mesh study to 400 zones/mm; consider a predictor temperature for the rate (second order in Δt); document the first-order property.
- F-03/F-10: guard or document X_R's range; optional deck checks on S1, G0.
- F-05(b): decide the 1−λ cutoff in the closure on evidence when a reactant with S2 ≥ 0 is burned.
- F-06: explicit interfaces for the drawing/colormap externals.
- F-07: keep history on audit branches; consider golden-output hashes for a few HVRB decks in `make test`.
- F-12: for CLAUDE's sheet, settle w's definition (dissipated energy vs entropy), the quadrature under RS, and the per-volume convention of the moments.
- A Δλ-per-step (or reaction-energy) time-step limiter as a documented deck key, if the 25-zones/mm difference is ever to be closed (TODO §3).

**4. Acceptable known limitations (documented):**
- AV's weak detonation on coarse meshes, free-surface overshoot and end-cell temperature (`av_study.md`, `input/README.md`).
- The smooth-ramp foot marks the lead shock at P_s → 0 (decision (a), Nov 7).
- P_s from AV is ~1 % high for strong shocks (post-shock ringing).
- A burning cell holds no tension and its solid is held where it first pulls — a modeling choice beyond the HVRB sheet, recorded in `materials.md` and `doc/README.md`.
- No reaction-based time-step control; first-order quadrature of Φ(Pⁿ) and r(Tⁿ).
- Ideal-gas products only; one C_V for both phases.

---

## 9. Final Recommendation

**APPROVE WITH CONDITIONS.**

The v1.4.0 code is scientifically defensible and numerically reliable for what it claims: every governing relation I derived independently matches the implementation to round-off; the two burn models integrate inside the hydrocode exactly as their documented rules say; HVRB and the inert code are bit-for-bit what v1.3.4 produced; results are deterministic across 1–8 threads, debug/release/serial builds and sanitizer builds; reference comparisons (G1–G5, the detector study, the ThermalCascade study) pass with the margins the documentation states. The conditions are documentation corrections (F-01 foremost, then F-02/F-08/F-05a) that keep the project's central promise — "each method follows an equation sheet kept in `doc/`, frozen" — accurate for the AV free surface and complete for ThermalCascade. No source change is required for 1.4.0; the Low findings are suitable for the 1.4.x/1.5 line.

---

## 10. Reproducibility of this Review

All review artifacts are in the connected folder beside the repository, under `audit_artifacts/` (not inside the source tree):

- `verify/sym_closure.py`, `verify/sym_eos.py` — symbolic derivations (sympy).
- `verify/check_eos.py`, `verify/check_mix.py`, `verify/check_burn.py` + `exp/drv_eos.f95`, `exp/drv_mix.f95`, `exp/drv_burn.f95` — 50-digit checks against drivers linked to the repository's compiled modules.
- `verify/rebuild_hvrb.py`, `verify/rebuild_tcas.py` — in-situ λ(t) rebuilds (the latter with the independent detector); decks in `exp/rebuild/`.
- `exp/bitwise_134_vs_140.sh` and its logs — the v1.3.4/v1.4.0 comparison (v1.3.4 obtained via `git archive v1.3.4 src/bitwhiz` from the nanoHUB clone).
- `exp/threads/omp8.log` — OpenMP tests at 2/3/4/8 threads with the one-line uncapped test build (patch shown in the log header).
- `exp/robust/`, `exp/cfl/` — robustness and time-step decks and screens.
- `verif_logs/` — the project's verification scripts' outputs; `make_test.log`, `make_release.log`, `build_warn.log` (extended warnings), sanitizer logs.

Temporary archives created during the audit in the connected folder (`bitwhiz_snapshot.tgz`, `bitwhiz_v1.3.4_export.tar`, `bitwhiz_v1.4.0_export.tar`) can be deleted.

---

## Addendum A — `study_av.py` (mesh convergence of method AV)

`study_av.py`: **9/9 passed** (52 runs, 12 m 49 s). The numbers match `doc/design/av_study.md`:

| Set | AV | RS order 2 |
|---|---|---|
| A, G4 (3.00 km/s), D over 10–20 mm vs D_CJ | +3.02 % (25 z/mm), +0.38 (50), +0.21 (100), **+0.027 (200), +0.020 (400)**; the plateau deficit behind the spike 5.0 → 0.35 GPa, its width 1.4 → 0.0 mm | 0.000, +0.017, +0.020, +0.014, +0.021 % at 25–400 z/mm |
| A, class deck, D over 5–9.6 mm | +3.0 % (25) → **+0.70 % (400)**; the remaining +0.7 % is the Ta reshock's overdrive, which RS2 shows too | +0.69 to +0.71 % on every mesh |
| B, square shock Al/Al, u_p = 1 km/s, free-surface velocity (exact 2.0062468 km/s) | peak +5.9…+6.3 % on every mesh for ~2.5 cells' transit; plateau within 0.01 % from 100 z/mm; the overshoot's integral halves with each refinement (first order) | peak +0.36…0.39 %; plateau within 0.01 % from 100 z/mm; integral halves |
| C, Material X struck at 1.00 km/s, released at a free surface | the coldest cell is the end cell on every mesh (−950 to −1460 K, λ ≤ 2.6e-3, 1 273–20 913 guard cell-steps): AV's free-surface bookkeeping, documented | T > 8.6 K everywhere, no guard, every mesh |

Interpretation: method AV's detonation speed converges to D_CJ (within 0.03 % from 200 zones/mm) and its weak-detonation plateau vanishes with refinement, as the design note states; method RS order 2 is at D_CJ on every mesh. The class deck's +0.7 % on both methods is not a numerical error but the drive (overdriven by the second shock), consistent across methods and meshes. The one unconverged AV artifact — the free-surface end cell's temperature — is a known, documented limitation of the AV energy update at a vanishing-mass cell, affects one cell, and does not touch pressures, velocities or the burn.

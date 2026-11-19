# bitwhiz v1.9.0: post-release assessment and development roadmap

Claude Fable 5.2 (Anthropic), for D. E. Kittell. Nov 18, 2026. Assessed at
`f473134` (`main`, one commit past `v1.9.0`).

**What this is, and is not.** A planning assessment: where the code stands
after 1.9.0, how `TODO.md` compares with the repository, and what is worth
doing next. It is not an independent review. It was written inside the working
session in which earlier Claude models helped build releases 1.7.0 to 1.9.0,
with that session's context. The independent review of this code is
`audits/v1.4.0_fable-5.1/`. No file was changed in making it.

**Public edition.** A private list of new-capability proposals was read with
`TODO.md`. This edition gives each proposal one line and leaves out its
details.

Findings carry the IDs G-01 to G-08; `audits/README.md` tracks them.

## 1. Executive assessment

bitwhiz 1.9.0 is a small, carefully verified 1D code whose implementation has
outrun its manual and its automated physics checks. The next cycle should
consolidate, with one low-risk prototype beside it. No finding here calls for
a change to the numerics.

**State of the repository.** One branch, `main` at `f473134`, one commit past
`v1.9.0`, clean. 146 commits (64 in October, 81 in November 2026), 20 tags.
Since 1.6.0: three burn models (StochasticIgnite, HALO, CLAUDE), 77 files,
about 8,350 lines added.

**What was run, Nov 18, at `f473134`** (gfortran 13.3, 2 cores; logs in
`audit_artifacts/`):

| Check | Result |
|---|---|
| `make test` (debug build) | Passed in 5 min 45 s: 11 unit-test programs (216 checks), 247 deck tests, 20 OpenMP tests, 52 history-file tests, the manual's check |
| The ten verification scripts in `tests/verification/` (quick modes) | 300 checks, all passed, about 4 minutes in total |
| Class deck, release build, no pictures | 945 cells, 3,432 cycles, 0.32 s; energy error 1.2e-16 |
| Class deck at 20 times its resolution | 18,900 cells: 103 s on 1 thread, 67 s on 2 (1.54 times faster) |

**What the release accomplished.** All six burn models of the plan run under
both methods, from one parameter table. Adding HALO touched three source files
(`btab_mod`, `burn_mod`, its own module); the deck reader, both hydro methods
and the main program were untouched. That is the architecture working as
designed.

**Maturity, in one line each**

- **Numerics:** mature for its scope; energy conserved to round-off under
  both methods.
- **Verification:** strong, but the physics comparisons run by hand, outside
  `make test` and CI.
- **Documentation:** the weakest part. The manual covers the burn (chapters 6
  and 7); chapters 2 to 5 and 8 are placeholders of 5 to 8 lines.
- **Performance:** not a constraint. About 70 to 80 ns per cell per cycle.
- **Scientific credibility:** verified, not yet validated. Material X is a
  class material, and five of the six burn models have example parameters,
  not calibrated ones.

**What could not be established**

- GitHub's issue, pull-request and download counts (no GitHub API access in
  the session).
- Results under gfortran 8, and on more than 2 threads; CI covers both, and
  its last run passed (DK, Nov 17).
- The full-length verification studies; their `--quick` modes were run.
- The nanoHUB tool's state beyond its clone, which is at 1.6.0.
- A line-by-line read of every source file. The module headers, the
  structure and the parts named below were read.

## 2. Technical inventory

The source is 43,800 lines of Fortran, of which about 27,300 are data tables
(the random table and eight colormaps) and about 16,400 are code.

**By component**

| Component | Where | State | Evidence and notes |
|---|---|---|---|
| Method AV (von Neumann-Richtmyer) | `av_mod.f95`, `maincode.f95` section 7 | Mature | Energy to round-off since 1.3.2; its free-surface overshoot (6 %) and end-cell temperature are measured and documented (`doc/design/av_study.md`), not fixed |
| Method RS (Godunov, acoustic Riemann solver, order 1 or 2) | `rs_mod.f95` | Mature for condensed matter | The acoustic solver suits solids at these pressures; it is not built for strong shocks in a gas |
| Inert EOS | `eos_mod.f95`, `temp_mod.f95` | Mature, but one model | Mie-Grüneisen only, called directly from the hydro's cell routines; there is no EOS dispatch, so a second inert EOS touches the hot path |
| Burn framework | `btab_mod.f95`, `burn_mod.f95`, `mix_mod.f95`, `lshk_mod.f95` | Mature; the best-factored part | A new model touches the table, the dispatcher and its own module |
| Six burn models | `hvrb_mod`, `tcas_mod`, `ffire_mod`, `sign_mod`, `halo_mod`, `claude_mod` | Built and verified; uncalibrated | Each has a 50-digit unit test and a run study; only HVRB has independent reference data (G2 to G5) |
| Products | `prod_mod.f95` | Minimal by design | Ideal gas with the solid's C_V; no JWL |
| Boundaries | `maincode.f95` | Incomplete (G-08) | Both ends are free surfaces. No wall, piston or inflow boundary was found in the source |
| Deck reader | `deck_mod.f95` (2,771 lines) | Mature | 175 of the 227 test decks are rejections with a checked message |
| Outputs and pictures | `trace_mod`, `hist_mod`, `pics_mod`, `src/drawings/` | Mature | Machine-readable tracer and history files; pictures have no axis names or units yet |
| Main program | `maincode.f95` (2,138 lines) | Works; the hardest file to change | A 1,566-line main body with two near-parallel OpenMP regions (AV at line 1187, RS at 1695) |
| Build and CI | `Makefile`, `.github/workflows/tests.yml` | Mature | gfortran 8, 13 and latest on every push to `main`; strict flags; debug and release must agree bit for bit |
| Manual | `doc/manual/` | Incomplete (G-06) | Chapters 6 and 7 are written (1,438 lines); chapters 2, 3, 4, 5 and 8 are placeholders |

**Maturity by dimension**

| Dimension | Working well | Incomplete or fragile | Inherent to the scope | Cheapest large improvement |
|---|---|---|---|---|
| Numerics and physical fidelity | Two independent methods that agree; exact conservation; measured AV artifacts | No measured order of accuracy (G-07); ThermalCascade's run distance still moving with mesh (F-04) | 1D planar; no strength; free surfaces only; ideal-gas products | An order-of-accuracy test on a smooth problem |
| Architecture and maintainability | The burn table; per-model modules; state kept out of the database | The main program's size; no EOS dispatch; 23 unchecked external calls (F-06) | One file per module, no abstractions: a strength here | Explicit interfaces for the picture routines |
| Verification and validation | 50-digit unit tests; exact impedance matches; G1 to G5; replay tests of each model | The 300 run-level checks are outside `make test` and CI (G-05); no validation against experiment | Material X is fictitious | A `make verify` target and a CI job for the quick studies |
| Parallelism and reproducibility | Bit for bit on 1 to 8 threads, debug against release | Scaling measured only here, on 2 cores; no golden hashes (deferred by DK, with reason) | A 1D mesh rarely needs threads | None needed now |
| Usability and teaching value | nanoHUB tool; deck reference; example decks; movies | nanoHUB is three models behind; README counts stale | Fortran and decks, not a scripting interface | The 1.9.0 nanoHUB export |
| Credibility and publication | Zenodo DOIs; audits kept in the repo; open design record | The manual's method chapters; no calibrated comparison of the six models | A single author, with AI assistance, to be declared for JOSS | The calibration study (step 10), with no Fortran change |

**Where documents and code disagree**

- **G-01, README, Test section:** it describes 4 unit tests (there are 11
  programs besides `test_hist`), "about 150 test decks" (227), "nine test
  decks" under OpenMP (20), and "about 4 minutes" (5 min 45 s here; 7 to 15
  on CI).
- **G-02, README, Status table:** the Pictures row has a doubled column
  separator, and the heartbeat row still says "cycle lines come with the time
  loop".
- **G-03, `TODO.md`:** the Priorities list reads as of Nov 4; section 6
  leaves HVRB and "Phase 4" unticked though both are released; section 9's
  heading carries a stray line from F-10; SCCM's dates differ from the GCCM
  page (June 20 to 25, 2027).
- **G-04, `audits/README.md`:** F-02 is marked open, but chapter 7 now states
  ThermalCascade's exact step and its first-order rate
  (`ch7_burn_models.tex`, lines 43 to 52 and 310 to 313).
- **Not a finding:** `doc/design/manual.md` says the frozen equation sheets
  leave `doc/`; they are still there, correctly, because chapters 2 to 4 that
  replace them are not written.

## 3. Existing roadmap reconciliation

`TODO.md` has 47 open boxes; about a third are done, superseded or not worth
keeping.

**Existing commitments worth preserving**

| Existing item | Current status | Recommendation |
|---|---|---|
| Step 10, the calibration study (TODO Priorities 9) | Outstanding | Retain; the highest-value physics result available without new Fortran |
| The manual's chapters 2 to 5 and 8 (`doc/design/manual.md`, M2) | Outstanding | Retain; then retire the frozen sheets from `doc/`, as that note decided |
| Order of accuracy, and the acoustic check, as tests (TODO 8) | Outstanding; the acoustic check was done by hand once (Nov 1) | Retain; consolidate into one item |
| nanoHUB export of 1.9.0 (RELEASING) | Outstanding; the clone is at 1.6.0 | Retain; an afternoon |
| JOSS: the public trail, the paper, evidence of use (TODO 9) | Outstanding; submission after May 5, 2027 | Retain; move new work to issues and pull requests now |
| SCCM 2027 abstract (TODO 9) | Outstanding; dates need correcting | Retain; it depends on step 10 |
| F-06, explicit interfaces (audit) | Outstanding | Retain; low effort, a real compiler-checking gap |
| F-04, ThermalCascade to 400 zones/mm (audit) | Outstanding | Retain; one run of `study_tcas.py`, then a sentence in the manual |
| JWL products (TODO 3 and 6) | Outstanding | Retain; the gate to any real explosive |
| Graded materials, and the t = 0 mesh file (TODO 7) | Outstanding; the burn table was built ready for it | Retain; DK's stated research line |
| Copyright holder (TODO 2) | Outstanding (ask OTC) | Retain; needed before JOSS |

**Existing items worth reconsidering**

| Existing item | Current status | Recommendation |
|---|---|---|
| TODO Priorities 1 to 8 | Stale (written Nov 4) | Revise: rewrite the list from this assessment |
| TODO 6: "HVRB" and "Phase 4" boxes | Complete (1.3.0 to 1.9.0) | Remove, with a line of history |
| F-02 (audit) | Complete in chapter 7 | Close in `audits/README.md` |
| F-11, F-14, F-15 (audit) | Proposed "accept", waiting for DK | Accept; each is documented and none affects results |
| F-13: `random.f95`, `timestamp.f95` | Unused by a run | Remove from the build; F-06 shrinks with them |
| F-05(b), a 1 - lam cutoff | Outstanding, "on evidence" | Defer until a deck shows the failure |
| F-07, golden hashes | Deferred by DK, with a sound reason | Keep deferred; a CI job over the verification scripts does the job better |
| The temperature's cost, 6 times per cycle (TODO 8) | Outstanding | Defer; the absolute cost is small (the class deck runs in 0.3 s) |
| Pictures cost more than the physics; colormap lookup (TODO 8) | Outstanding | Remove; it would change picture bytes for a second saved |
| Performance budget in commit messages (TODO 8) | Never practiced | Revise: one timing line in the CI log is enough |
| Faster deck tests (TODO 8) | Partial | Defer; revisit only if CI passes 20 minutes |
| Velocity and density movies; later distributions (TODO 4, 1) | Outstanding | Remove; nothing asks for them |
| Notebook items: Stop button, frame download, movie timing, lock file (TODO 2) | Outstanding | Consolidate into one nanoHUB release, after the 1.9.0 export |
| The arrival offset; the 25 zones/mm difference (TODO 3) | Outstanding; both within tolerance | Defer; one G1 rerun settles the first when convenient |
| Noh wall heating at the impact plane (TODO 8) | Outstanding | Defer until there is a wall boundary to test against |
| Strength; the spall "knocking" (TODO 6) | Outstanding | Defer; strength changes the scheme's stress and is the largest physics item on the list |
| A broken cell's temperature (TODO 5) | Outstanding | Defer to the strength or damage work |
| Ramp decks that stay in compression; ramp verification (TODO 1) | Outstanding | Fold into the order-of-accuracy test |
| Far-out ideas: 2D, cylindrical and spherical geometry, PNG, Bayesian calibration (TODO Ideas) | Concept | Keep as a parked list; none belongs in the next cycle |

**New-capability proposals (from the private list, one line each)**

| Proposal | Current status | Recommendation |
|---|---|---|
| A synthetic RF diagnostic | Concept | Retain, as a post-processor of the history file first |
| A gas-dynamics surrogate, needing an inert gas EOS | Concept | Revise and defer: prototype outside bitwhiz first |
| A survey of programming languages | Concept | Reconsider: a short written note at most; a port would cost months and risk the verified code |
| Coupling to calibration software | Concept | Retain, as the thin Python driver step 10 needs anyway |

**New opportunities from this review**

| Item | Why it matters | Recommendation |
|---|---|---|
| The verification scripts in CI (G-05) | 300 run-level checks pass today but nothing reruns them; a change could break G1 to G5 agreement and `make test` would stay green | Add `make verify` and a CI job; about 4 minutes in quick mode |
| Boundary conditions: a rigid wall and a prescribed-velocity piston (G-08) | Sustained shocks without thick flyers, the Noh test, cheaper Pop-plot runs | A good candidate for the cycle after next |
| Validation against an open-literature explosive | Verification shows the equations are solved right; no result yet compares with an experiment | After JWL products; pick one material with published Pop-plot data |
| An EOS dispatch for inert materials | Any second inert EOS changes the hydro's cell routines | Design it once, before the first new EOS, with every existing deck bit for bit |
| A doc-sync pass after each release | The README and the trackers drifted in two weeks | Add one line to `RELEASING.md`'s checklist |

**Dependencies worth stating**

- **The SCCM abstract** depends on step 10's results.
- **Validation against a real explosive** depends on JWL products.
- **Any second inert EOS** depends on an EOS dispatch, and a gas beside a
  solid on a study of the acoustic Riemann solver at a strong gas shock.
  Method AV would carry it first.
- **The synthetic RF diagnostic** as a post-processor depends only on the
  history file.
- **The Noh test** depends on a wall boundary.
- **Retiring the frozen sheets** depends on manual chapters 2 to 4.

## 4. Next baby steps

Eight increments, ranked. The first six change no numerical result; the last
two do add Fortran, and can wait a cycle.

| Rank | Step | Motivation | Complexity | Verification | Dependencies and risks | Next cycle? |
|---|---|---|---|---|---|---|
| 1 | **Doc sync and tracker hygiene:** README's test section and Status table, a rewritten `TODO.md`, the audit tracker (F-02 closed; F-11, F-14, F-15 accepted), SCCM's dates | Three documents contradict the code today; cheap now, costly at JOSS review | Low | `make test` unchanged; `manual_check.py` | None | Yes, first |
| 2 | **`make verify` and a CI job** for the ten verification scripts in quick mode | 300 checks guard G1 to G5, the replays and the mesh studies, and nothing reruns them | Low | The job itself; break one tolerance on a branch to see it fail | Python 3, NumPy and mpmath in the gcc:13 container; run it on one compiler, not three | Yes |
| 3 | **Order of accuracy as a test:** a smooth small-amplitude wave at 4 or 5 meshes, AV and RS orders 1 and 2, with the acoustic check | The one standard verification result bitwhiz lacks; chapter 8 needs the numbers | Low to medium | Exact linear acoustics; expected L1 slopes near 1 and 2 | Runs must stay short for the test budget | Yes |
| 4 | **Manual chapters 2 to 5 and 8** (methods AV and RS, materials, verification) | The hydro is the oldest and least documented part; the frozen sheets no longer match the code in places | Medium (writing) | `manual_check.py`'s trace tags; each number cited with its commit | Slow to get right; do one chapter per commit | Yes, the cycle's largest item |
| 5 | **Step 10, the calibration study:** each model fitted to HVRB's Material X Pop plot, then compared on double shocks | Turns six example decks into one comparable result; the SCCM abstract's content | Medium | The fit's residuals; mesh convergence of each fitted model; AV against RS | Needs a small Python driver (fill a deck, run, read) | Yes |
| 6 | **The synthetic RF diagnostic as a post-processor** of the history file (Python) | Tests the proposal with no risk to the Fortran, and tells whether a Fortran version is worth it | Low to medium | Closed-form results for layered media and a moving reflector | Needs a material-property assumption per material; snapshot spacing must resolve the signal | Yes, after step 5 or beside it |
| 7 | **Boundary conditions:** a rigid wall and a prescribed-velocity piston, by deck key | Sustained shocks, the Noh test, shorter Pop-plot runs | Medium | An exact piston-driven shock; a wall as a symmetry plane against the two-sided run; every existing deck bit for bit | Touches the end faces of both methods and the energy balance | The cycle after |
| 8 | **JWL products** | The gate to a real explosive and to validation | Medium | 50-digit unit test; CJ state against the closed form; HVRB bit for bit when off | The closure assumes a shared C_V; JWL needs that revisited | The cycle after |

**Worth doing now:** steps 1 to 6. Together they add no physics and change no
existing result.

**Can wait:** steps 7 and 8; the nanoHUB notebook items (one release, after
the 1.9.0 export); graded materials, until step 10 shows which parameters
matter.

**The gas-dynamics surrogate should wait, and start outside bitwhiz.** It
needs an EOS dispatch, a new gas-solid closure (the burn's closure, one
density and one temperature with a shared C_V, does not suit a gas beside a
metal), and a 1D stand-in for a 2D flow whose accuracy is unproven. A
standalone prototype, checked against a published correlation, would show in
a few sessions whether the approach holds. Only then is the Fortran worth
designing.

**Probably avoid**

- **Porting to another language.** The verified Fortran is the asset; a
  written comparison is enough for a scoping study.
- **Performance work.** The class deck runs in 0.3 s and a 20 times finer
  mesh in under 2 minutes.
- **Refactoring `maincode.f95` for its own sake.** Split it only when a
  feature (boundaries, EOS dispatch) forces the cut.
- **Strength, 2D.** Each is a different code's worth of work.

## 5. Alternative development paths

Three paths, each a different use of the next cycle. A performance path was
considered and dropped: the measurements above give it no case, and the
research line `TODO.md` already names is the stronger third option. Efforts
are rough, in working sessions (an evening each).

**Path A: consolidation and credibility**

- **Objective:** make what exists documented, automatically guarded and
  citable, and produce the first comparable physics result.
- **Steps:** (1) doc sync and trackers; (2) `make verify` in CI; (3) the
  order-of-accuracy test; (4) manual chapters 2 to 5 and 8, then the frozen
  sheets retired; (5) step 10, the calibration study, with the nanoHUB 1.9.0
  export.
- **Benefits:** a complete manual, a regression net over the physics, an SCCM
  abstract, and a steady public trail of small pull requests through spring,
  which JOSS checks.
- **Risks and costs:** the writing is slow and less exciting; new
  capabilities wait, apart from the RF diagnostic's script.
- **Effort:** about 8 to 12 sessions.
- **Afterwards:** the same physics, fully written up, with a calibrated
  six-model comparison and nothing claimed that CI does not rerun.

**Path B: new diagnostics and physics**

- **Objective:** widen what bitwhiz can address: the synthetic RF diagnostic
  and the gas-dynamics surrogate.
- **Steps:** (1) the RF diagnostic as a post-processor, then in Fortran; (2)
  an EOS dispatch and an inert ideal gas; (3) wall and piston boundaries; (4)
  the surrogate's standalone prototype; (5) the surrogate in bitwhiz, if the
  prototype holds.
- **Benefits:** two capabilities a teaching hydrocode does not usually have.
- **Risks and costs:** the surrogate is research with an uncertain outcome,
  and it opens the hydro's hot path and the conservation checks. The manual
  and CI gaps grow while new code lands on them.
- **Effort:** about 15 to 25 sessions, most of it the surrogate.
- **Afterwards:** a broader code with two new features, the hydro still
  undocumented in the manual, and a larger surface to verify.

**Path C: the research platform (calibration, graded materials, real
explosives)**

- **Objective:** move from a class material toward publishable reactive-burn
  research.
- **Steps:** (1) step 10 with the Python driver; (2) JWL products; (3) one
  open-literature explosive, calibrated and validated against its Pop plot;
  (4) constants graded through a layer, with the t = 0 mesh file; (5)
  ensembles for uncertainty quantification.
- **Benefits:** the strongest scientific result: validated models and DK's
  graded-materials line.
- **Risks and costs:** JWL reopens the closure's shared-C_V assumption;
  grading changes the per-cell layout; the same documentation debt as Path B.
- **Effort:** about 12 to 18 sessions.
- **Afterwards:** a research code with one validated explosive and graded
  layers, and a second SCCM abstract in reach.

**Compared**

| | Path A | Path B | Path C |
|---|---|---|---|
| New Fortran physics | None | Much | Moderate |
| Risk to verified behavior | None | High (hot path, conservation) | Medium (closure, layout) |
| Serves JOSS (May 2027) | Directly | Little | Partly |
| Serves SCCM 2027 | Yes, through step 10 | Not in time, likely | Yes, more strongly but later |
| Serves the new-capability proposals | The RF diagnostic's script only | Fully | The calibration coupling |
| Effort (sessions) | 8 to 12 | 15 to 25 | 12 to 18 |

## 6. Recommendation

Take Path A now, with the RF diagnostic's post-processor as its one new
capability, and make Path C the cycle after. Path B's surrogate should be
tested as a standalone prototype before any of it enters bitwhiz.

**Why Path A**

- **The code is ahead of its record.** Six burn models in two weeks is fast;
  the manual has no hydro chapters, and the physics comparisons are not rerun
  automatically. Each new feature added now raises the cost of catching up.
- **It serves both dated goals.** JOSS wants a documented code and steady
  public activity to May 2027; SCCM wants a result, which step 10 supplies
  from the code as it stands.
- **It risks nothing.** No step changes an existing number, so every
  bit-for-bit guarantee carries through.
- **It makes Paths B and C cheaper.** A CI job over the verification studies
  is what makes JWL, boundaries or an EOS dispatch safe to attempt.

**The first three steps**

1. **Doc sync, in one or two small pull requests.** README's Test section and
   Status table; `TODO.md` rewritten around this assessment's tables;
   `audits/README.md` (F-02 closed; F-11, F-14 and F-15 for DK to accept);
   SCCM's dates. Starting with pull requests begins the public trail JOSS
   looks for.
2. **`make verify`, then a CI job.** A Makefile target that builds the
   release program and `ls_replay` and runs the ten scripts with `--quick`; a
   second job in `tests.yml` on gcc:13 with Python 3, NumPy and mpmath. Check
   that it fails when a tolerance is broken on a branch.
3. **The order-of-accuracy test.** One smooth deck at four meshes, AV and RS
   orders 1 and 2, against exact linear acoustics, with the measured slopes
   kept as a test and reported in chapter 8.

Then chapter 3 (method AV) of the manual, the 1.9.0 nanoHUB export, and
step 10.

**Decisions for DK before starting**

- Path A, or another path.
- F-11, F-14 and F-15: accept as documented?
- `random.f95` and `timestamp.f95`: drop from the build?
- Pull requests for new work from here on, or direct pushes as before?

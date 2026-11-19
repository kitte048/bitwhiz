# audits

Independent reviews of bitwhiz releases, kept with the code so that each one
can be read against the release it reviewed and its findings followed to
where they were fixed. A review is an archived record: it is copied here as
the reviewer delivered it and never edited. What became of each finding is
tracked in this file, not in the review.

## Layout

One folder per review, named for the release and the reviewer:

    audits/
      README.md                  this file: the index and the finding tracker
      v<version>_<reviewer>/
        README.md                where the review came from, and how to read
                                 its paths here
        <the review, as delivered>
        <its artifacts, as delivered: scripts, decks, logs>

A second review of the same release gets its own folder (another reviewer,
or `_2`). Logs are kept (`audits/.gitignore` overrides the top-level rule
that drops `*.log`). Large scratch, such as copies of the source tree or
export archives, is not kept: the release's tag is the source.

## Reviews

| Folder | Release reviewed | Reviewer | Date | Verdict |
|---|---|---|---|---|
| `v1.4.0_fable-5.1/` | v1.4.0, `cf0eab0` | Claude Fable 5.1 (Anthropic), independent review | Nov 7-8, 2026 | Approve with conditions (documentation only; no Critical or High finding) |
| `v1.9.0_fable-5.2/` | v1.9.0, at `f473134` | Claude Fable 5.2 (Anthropic), post-release assessment; not independent (written in the working session, with its context) | Nov 18, 2026 | Consolidate next: no finding calls for a change to the numerics |

## Findings: v1.4.0 (Fable 5.1)

Status: **open** (not yet done or decided), **fixed** (with the release),
**accepted** (DK's call: a known limitation, documented; no change). The last
column says where a fix was made, or where an open finding is to go.

| ID | Severity | In short | Status | Where |
|---|---|---|---|---|
| F-01 | Moderate | The frozen AV sheet says the end face carries q/2 "and what bitwhiz does"; since 1.3.2 it does not | fixed, 1.4.1 | recorded in `doc/README.md`, "Where the code has moved past a sheet" (the sheet stays frozen); the manual states what the code does |
| F-02 | Low | The ThermalCascade sheet has the rate law only (not the exact step, T at the step's start, the gate's timing, P_s < 0 as 0, the parameters) | fixed, 1.5.0 | the manual, chapter 7, ThermalCascade: the rate at the step's start (T and P_s), the exact step, the lead shock's gate, P_s < 0 taken as 0, the keys (found closed by the v1.9.0 assessment, G-04) |
| F-03 | Low | `hvrb_lambda`'s series loses precision for X_R above about 40 (6.7e-6 at 80) | fixed, 1.4.1 (documented); 1.6.1 (guarded) | the range stated in `input/README.md` (re-measured: 7e-16 or better to X_R = 25, 1e-14 at 30); from 1.6.1 the deck refuses XR above 25 (`bkey_max`, module `burn_table`) |
| F-04 | Low | ThermalCascade's run distance moves with the mesh (3.30 to 3.00 mm, 25 to 200 zones/mm); first order in dt | open | `TODO.md`, section 8: E2 to 400 zones/mm; a predictor temperature later |
| F-05 | Low | ThermalCascade's lam never reaches 1: "Cells burnt out" reads ~0; the solid EOS is always evaluated | (a) fixed, 1.6.1; (b) open | (a) the count is lam >= 1 - 1e-12 for every model (`maincode`); (b) a 1 - lam cutoff in the closure, on evidence (`TODO.md`, section 8) |
| F-06 | Low | 23 calls to external procedures through implicit interfaces | open | `TODO.md`, section 8 |
| F-07 | Info | The audit branch had no history, so "bit for bit against the commit before" could not be rechecked from it | open (DK) | give future reviews the full history. Golden-output hashes left outstanding by DK (Nov 12): bits are only guaranteed debug against release on one machine, not across platforms' math libraries, and chasing them is not worth it now (`TODO.md`, section 8) |
| F-08 | Info | Stale pre-1.3.2 energy-drift numbers in `doc/design/materials.md` | fixed, 1.4.1 | annotated, not rewritten: `doc/design/materials.md`, `TODO.md` (section 3), `tests/verification/inert_gauges/README.md` |
| F-09 | Info | A local `tk` shadows the temperature array `tk` in two procedures | fixed, 1.6.1 | renamed `ticks` (`maincode`) |
| F-10 | Info | `G0`, `S1` and `X_R` have no deck checks | fixed, 1.6.1 | S1 > 0, G0 >= 0, XR <= 25 (module `deck`; decks `bad_s1_zero`, `bad_g0_neg`, `bad_hvrb_xr_big`) |
| F-11 | Info | The lead shock's P_s and t_s at a local minimum; AV's P_s ~1 % high | accepted | (DK, Nov 19) documented in `doc/design/burn_models.md`, step 4 |
| F-12 | Info | Design remarks on the planned CLAUDE model | fixed, 1.9.0 | all three answered as built (`doc/design/burn_models.md`, step 9; the manual's CLAUDE section): w is entropy, a state function from the cell's state, not a sum (the sum could not converge under RS: a one-step shock's De + P Dv is fixed by the jump conditions, whatever its dissipation); measured within 0.3 % of the Hugoniot's entropy, AV and RS, 25 to 200 zones/mm; everything per initial volume; new centers born through the step, exact |
| F-13 | Info | `rand_mod`, `random`, `timestamp` compiled in, unused by a run | fixed, 1.7.0 (`rand_mod`); `random`, `timestamp` open | from 1.7.0 StochasticIgnite starts each bin's noise from `rand_mod`'s table (module `stochignite`, `si_z0`); `src/utils/random.f95` (`r8_uniform_01`) and `timestamp.f95` stay unused by a run, small; for DK to keep or drop |
| F-14 | Info | ThreadSanitizer inconclusive (false positives); determinism rests on the bit-for-bit thread tests | accepted | (DK, Nov 19) no action |
| F-15 | Info | dP/dlam at lam = 1 is the gas-only form, not the limit from below; never used by the hydro | fixed (a comment), Nov 19 | (DK, Nov 19) `src/modules/mix_mod.f95`, `mix_state`, the burnt branch (lam = 1): a comment says dpdlam there is the gas-only form, not its limit from below, and that no caller uses it; the code and every result unchanged |

Opened Nov 8, 2026, from the review's finding register (section 3) and
recommended actions (section 8). F-01, F-03 and F-08 answered in 1.4.1's
docs (Nov 8); F-05(a), F-09 and F-10 fixed, and F-03 guarded, in 1.6.1
(Nov 12); F-02 found answered by the manual's chapter 7 (1.5.0), closed
Nov 19; F-07 left open by DK; F-11 and F-14 accepted by DK, and F-15
fixed by a comment in `mix_mod.f95`, Nov 19. F-13's `rand_mod` used by StochasticIgnite, 1.7.0 (Nov
12). F-12 answered by CLAUDE as built, 1.9.0 (Nov 14).

## Findings: v1.9.0 (Fable 5.2, post-release assessment)

Opened Nov 18, 2026, from the assessment's sections 2 and 3. A planning
assessment, so most of these are gaps in the record, not defects in the code.
Status as above: **open**, **fixed**, **accepted**.

| ID | Severity | In short | Status | Where |
|---|---|---|---|---|
| G-01 | Low | README's Test section is stale: 4 unit tests described (11 programs), "about 150 test decks" (227), "nine test decks" under OpenMP (20), "about 4 minutes" (5 min 45 s on 2 cores) | fixed, Nov 19 (doc sync) | `README.md` |
| G-02 | Info | README's Status table: a doubled column separator in the Pictures row; the heartbeat row's "cycle lines come with the time loop" | fixed, Nov 19 (doc sync) | `README.md` |
| G-03 | Low | `TODO.md`: Priorities as of Nov 4; HVRB and "Phase 4" unticked though released; a stray line in section 9's heading; SCCM 2027's dates | fixed, Nov 19 (doc sync) | `TODO.md` |
| G-04 | Info | F-02 is marked open, but the manual's chapter 7 answers it | fixed, Nov 19 (doc sync) | the tracker above |
| G-05 | Moderate | The ten verification scripts (300 checks in quick mode, about 4 minutes) are outside `make test` and CI | open | a `make verify` target and a CI job |
| G-06 | Moderate | The manual's chapters 2 to 5 and 8 are placeholders | open | `doc/manual/` (`doc/design/manual.md`, M2) |
| G-07 | Low | No measured order of accuracy; the acoustic check was done by hand once | open | a test (`TODO.md`, section 8) |
| G-08 | Info | Both ends are free surfaces: no wall or piston boundary | open | a limitation; a candidate for a later cycle |

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

## Findings: v1.4.0 (Fable 5.1)

Status: **open** (not yet done or decided), **fixed** (with the release),
**accepted** (DK's call: a known limitation, documented; no change). The last
column says where a fix was made, or where an open finding is to go.

| ID | Severity | In short | Status | Where |
|---|---|---|---|---|
| F-01 | Moderate | The frozen AV sheet says the end face carries q/2 "and what bitwhiz does"; since 1.3.2 it does not | fixed, 1.4.1 | recorded in `doc/README.md`, "Where the code has moved past a sheet" (the sheet stays frozen); the manual states what the code does |
| F-02 | Low | The ThermalCascade sheet has the rate law only (not the exact step, T at the step's start, the gate's timing, P_s < 0 as 0, the parameters) | open | the manual's burn-model chapter, 1.5.0 (`doc/design/manual.md`) |
| F-03 | Low | `hvrb_lambda`'s series loses precision for X_R above about 40 (6.7e-6 at 80) | fixed, 1.4.1 (documented); 1.6.1 (guarded) | the range stated in `input/README.md` (re-measured: 7e-16 or better to X_R = 25, 1e-14 at 30); from 1.6.1 the deck refuses XR above 25 (`bkey_max`, module `burn_table`) |
| F-04 | Low | ThermalCascade's run distance moves with the mesh (3.30 to 3.00 mm, 25 to 200 zones/mm); first order in dt | open | `TODO.md`, section 8: E2 to 400 zones/mm; a predictor temperature later |
| F-05 | Low | ThermalCascade's lam never reaches 1: "Cells burnt out" reads ~0; the solid EOS is always evaluated | (a) fixed, 1.6.1; (b) open | (a) the count is lam >= 1 - 1e-12 for every model (`maincode`); (b) a 1 - lam cutoff in the closure, on evidence (`TODO.md`, section 8) |
| F-06 | Low | 23 calls to external procedures through implicit interfaces | open | `TODO.md`, section 8 |
| F-07 | Info | The audit branch had no history, so "bit for bit against the commit before" could not be rechecked from it | open (DK) | give future reviews the full history. Golden-output hashes left outstanding by DK (Nov 12): bits are only guaranteed debug against release on one machine, not across platforms' math libraries, and chasing them is not worth it now (`TODO.md`, section 8) |
| F-08 | Info | Stale pre-1.3.2 energy-drift numbers in `doc/design/materials.md` | fixed, 1.4.1 | annotated, not rewritten: `doc/design/materials.md`, `TODO.md` (section 3), `tests/verification/inert_gauges/README.md` |
| F-09 | Info | A local `tk` shadows the temperature array `tk` in two procedures | fixed, 1.6.1 | renamed `ticks` (`maincode`) |
| F-10 | Info | `G0`, `S1` and `X_R` have no deck checks | fixed, 1.6.1 | S1 > 0, G0 >= 0, XR <= 25 (module `deck`; decks `bad_s1_zero`, `bad_g0_neg`, `bad_hvrb_xr_big`) |
| F-11 | Info | The lead shock's P_s and t_s at a local minimum; AV's P_s ~1 % high | open | accept: documented in `doc/design/burn_models.md`, step 4 |
| F-12 | Info | Design remarks on the planned CLAUDE model | open | its three questions recorded in `doc/design/burn_models.md` (CLAUDE); settled in the manual's CLAUDE section, 1.5.0 |
| F-13 | Info | `rand_mod`, `random`, `timestamp` compiled in, unused by a run | open | accept: reserved for StochasticIgnite |
| F-14 | Info | ThreadSanitizer inconclusive (false positives); determinism rests on the bit-for-bit thread tests | open | accept: no action |
| F-15 | Info | dP/dlam at lam = 1 is the gas-only form, not the limit from below; never used by the hydro | open | accept: no action |

Opened Nov 8, 2026, from the review's finding register (section 3) and
recommended actions (section 8). F-01, F-03 and F-08 answered in 1.4.1's
docs (Nov 8); F-05(a), F-09 and F-10 fixed, and F-03 guarded, in 1.6.1
(Nov 12); F-07 left open by DK; the "accept" proposals (F-11, F-13 to
F-15) wait for DK.

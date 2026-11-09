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

Status: **open** (not yet decided), **fixed** (with the commit),
**accepted** (DK's call: a known limitation, documented; no change). The last
column is where each finding is proposed to go until DK decides.

| ID | Severity | In short | Status | Proposed |
|---|---|---|---|---|
| F-01 | Moderate | The frozen AV sheet says the end face carries q/2 "and what bitwhiz does"; since 1.3.2 it does not | open | 1.4.1 docs (`doc/README.md`); the manual states what the code does (`doc/design/manual.md`) |
| F-02 | Low | The ThermalCascade sheet has the rate law only (not the exact step, T at the step's start, the gate's timing, P_s < 0 as 0, the parameters) | open | the manual's burn-model chapter (`doc/design/manual.md`) |
| F-03 | Low | `hvrb_lambda`'s series loses precision for X_R above about 40 (6.7e-6 at 80) | open | 1.4.1 docs (the X_R range in `input/README.md`); a guard later (with F-10) |
| F-04 | Low | ThermalCascade's run distance moves with the mesh (3.30 to 3.00 mm, 25 to 200 zones/mm); first order in dt | open | `TODO.md`: E2 to 400 zones/mm; a predictor temperature later |
| F-05 | Low | ThermalCascade's lam never reaches 1: "Cells burnt out" reads ~0; the solid EOS is always evaluated | open | `TODO.md`: a model-independent burnt-out count; a 1 - lam cutoff on evidence |
| F-06 | Low | 23 calls to external procedures through implicit interfaces | open | `TODO.md` |
| F-07 | Info | The audit branch had no history, so "bit for bit against the commit before" could not be rechecked from it | open | give future reviews the full history; golden-output hashes in `make test` (`TODO.md`) |
| F-08 | Info | Stale pre-1.3.2 energy-drift numbers in `doc/design/materials.md` | open | 1.4.1 docs (annotated, not rewritten) |
| F-09 | Info | A local `tk` shadows the temperature array `tk` in two procedures | open | `TODO.md` |
| F-10 | Info | `G0`, `S1` and `X_R` have no deck checks | open | `TODO.md` (with F-03) |
| F-11 | Info | The lead shock's P_s and t_s at a local minimum; AV's P_s ~1 % high | open | accept: documented in `doc/design/burn_models.md`, step 4 |
| F-12 | Info | Design remarks on the planned CLAUDE model | open | `doc/design/burn_models.md`, when its sheet is drafted |
| F-13 | Info | `rand_mod`, `random`, `timestamp` compiled in, unused by a run | open | accept: reserved for StochasticIgnite |
| F-14 | Info | ThreadSanitizer inconclusive (false positives); determinism rests on the bit-for-bit thread tests | open | accept: no action |
| F-15 | Info | dP/dlam at lam = 1 is the gas-only form, not the limit from below; never used by the hydro | open | accept: no action |

Opened Nov 8, 2026, from the review's finding register (section 3) and
recommended actions (section 8). Nothing above has been fixed yet.

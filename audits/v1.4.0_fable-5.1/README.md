# v1.4.0, reviewed by Claude Fable 5.1

An independent engineering and scientific review of bitwhiz v1.4.0 (tag
`v1.4.0`, commit `cf0eab0`), run overnight Nov 7-8, 2026 by Claude Fable 5.1
(Anthropic) at DK's request, in a session separate from the one that wrote
the code. The reviewer worked on a snapshot of the repository and changed
nothing in it. Verdict: **approve with conditions** (documentation only).

## What is here

| File | What it is |
|---|---|
| `bitwhiz_v1.4.0_Engineering_Review.md` | the review, as delivered (SHA-256 `0ab8f0c17d868b6ac75d742d2ced316b7fc990ab1116c2284fe96b104a9dcb28`) |
| `audit_artifacts/verify/` | the reviewer's own checks: symbolic derivations (sympy) and 50-digit comparisons (mpmath), and the in-situ lam(t) rebuilds |
| `audit_artifacts/exp/` | the Fortran drivers those checks link against, the v1.3.4/v1.4.0 bit-for-bit script and log, and the decks and screens of the robustness, time-step, rebuild and thread runs, sanitizer logs |
| `audit_artifacts/verif_logs/` | the outputs of the project's own verification scripts, re-run by the reviewer |
| `audit_artifacts/build_logs/` | the build and `make test` logs |

The review and its 69 artifact files are byte-for-byte copies of what the reviewer delivered
(checked by SHA-256 when they were copied here, Nov 8, 2026).

## Reading its paths here

- The review's section 10 says the artifacts are "in the connected folder
  beside the repository, under `audit_artifacts/`": here, they are this
  folder's `audit_artifacts/`.
- Paths under `/home/claude/audit/` in the logs and scripts are the
  reviewer's machine: `repo/bitwhiz` was this repository at `cf0eab0`,
  `ref134/v134/src/bitwhiz` was v1.3.4 (from the nanoHUB clone's tag).
- The review names its branch `Fable-Audit-2026-Nov-7`: a one-commit,
  history-free copy of `cf0eab0` made for the review (its finding F-07).
- Not kept: the snapshot of the source tree and the export archives the
  reviewer made (about 56 MB); the tags `v1.3.4` and `v1.4.0` are the same
  source.

## What became of its findings

Tracked in `../README.md`, not here: the review stays as delivered.

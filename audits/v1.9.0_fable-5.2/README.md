# v1.9.0, Claude Fable 5.2: post-release assessment

`bitwhiz_v1.9.0_Post_Release_Assessment.md` is a planning assessment of
bitwhiz at `f473134` (`main`, one commit past `v1.9.0`), written Nov 18, 2026
by Claude Fable 5.2 (Anthropic) at D. E. Kittell's request: the state of the
code, `TODO.md` reconciled against it, the next steps, three development
paths and a recommendation. It is archived as delivered.

**Not an independent review.** It was written inside the working session in
which earlier Claude models helped build releases 1.7.0 to 1.9.0, with that
session's context. The independent review is `../v1.4.0_fable-5.1/`.

**Public edition.** A private list of new-capability proposals was read with
`TODO.md`; this edition gives each proposal one line and leaves out its
details.

## Artifacts

`audit_artifacts/`, as the runs wrote them (gfortran 13.3, Ubuntu 24.04, 2
cores; Python 3 with NumPy 2.5.3 and mpmath 1.3.0), all at `f473134`:

| File | What |
|---|---|
| `make_test.log` | `make test`, debug build: passed, 5 min 45 s |
| `verify_gold.log` | `gold.py`: 77 passed |
| `verify_compare_g1.log` | `compare_g1.py`: 40 passed |
| `verify_compare_hvrb.log` | `compare_hvrb.py --quick`: 31 passed |
| `verify_study_av.log` | `study_av.py --quick`: 9 passed |
| `verify_study_leadshock.log` | `study_leadshock.py --quick`: 43 passed |
| `verify_study_tcas.log` | `study_tcas.py --quick`: 16 passed |
| `verify_study_ffire.log` | `study_ffire.py --quick`: 16 passed |
| `verify_study_sign.log` | `study_sign.py --quick`: 30 passed |
| `verify_study_halo.log` | `study_halo.py --quick`: 18 passed |
| `verify_study_claude.log` | `study_claude.py --quick`: 20 passed |

Paths in the logs (`/home/claude/man`) are the session's clone of the
repository. The timing runs of section 1 (the class deck, and the same deck at
`resolution = 700`, on 1 and 2 threads, pictures off) were not kept: any build
of `f473134` repeats them.

What became of findings G-01 to G-08 is tracked in `../README.md`.

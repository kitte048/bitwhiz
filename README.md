# bitwhiz
A one-dimensional, planar, Lagrangian hydrocode in Fortran (F2018), written for
the ME 697 class project: a Ta-backed Al flyer impacts Material X behind a PMMA
window, and the code predicts the PDV velocity at the Material X/PMMA interface.

## Status
| Part | State |
|---|---|
| Build system, strict compiler flags, OpenMP | done |
| Input deck: syntax spec, reader, ~100 test decks | done (`input/README.md`) |
| Database layout, material/layer/tracer tables | done (`src/modules/shock_mod.f95`) |
| Heartbeat file (opened and closed) | done; cycle lines come with the time loop |
| Mesh setup at t = 0, with a setup audit | done (maincode sections 5-6) |
| Equation of state (Mie-Gruneisen), with unit test | done (`src/modules/eos_mod.f95`) |
| Artificial viscosity time loop, OpenMP (bit-for-bit with serial) | done (`src/modules/av_mod.f95`, maincode section 7) |
| Expansion EOS (cubic, smooth through V0) and spall (`spall_strength`) | done (`eos_mod`, `av_mod`; see `input/README.md`) |
| Tracer file (`<title>.tracers.csv`, `tracer_dt`) | done (`src/modules/trace_mod.f95`; see `input/README.md`) |
| Second method, `method = RS` (Godunov's method, acoustic Riemann solver), in the same code; `order = 2` (MUSCL-Hancock, Van Leer, the default) or `1` | done (`src/modules/rs_mod.f95`, maincode section 7; equation sheet `doc/Hydrocode_RS_Eqns_v4`) |
| Snapshot output (bitmaps, t-x diagrams) | next |
| Comparison with reference data | data in `tests/verification/` |

## Build
Needs gfortran and make.
```
make            # bin/bitwhiz, debug build with strict flags and -fopenmp
make test       # build if needed, then run the unit and deck tests (see Test)
make tidy       # remove run outputs (heartbeats, tracer files, bitmaps); keep the build
make clean      # tidy, plus objects, module files and the executable
make bmpclean   # remove bitmaps in this folder (kept by the two above)
make OMPFLAGS=  # a serial build from the same source
```
The root `Makefile` is the only build; there are no Makefiles under `src/`.
After changing compiler flags, run `make clean` first.

Every `make` also writes `src/modules/build_mod.f95` (generated, not in git):
the build date and the git version from `git describe --tags --always --dirty`,
e.g. `v0.3-12-g9f2c1ab-dirty`. The banner and the heartbeat print it, so every
run records which build made it. Tag releases (`git tag v0.3`) to give the
version a readable name; `-dirty` marks a build with uncommitted changes.

## Run
```
./bin/bitwhiz input/me697_double_shock_2p00.deck
```
The command line takes only the deck. Everything else (threads, solver,
materials, geometry, output) is in the deck; see `input/README.md`. A run
writes `<title>.heartbeat` in the current folder, one line per cycle (time
step and the cell that set it, largest pressure, mass and energy errors, total
momentum); watch it with `tail -f`. The heartbeat also records the first cell
to go tensile, the first cell to break (spall: its pressure fell below
`-spall_strength`, set per material), and the first void cell, if any. A deck
with tracers also writes `<title>.tracers.csv`: one row per `tracer_dt`, laid
out like the verification data in `tests/verification/`.

## Test
```
make test
```
Three kinds of test, all run by `make test`, which stops at the first failure:

- **Unit tests**, one program each, `tests/test_*.f95`, exit status 0 = pass.
  `test_eos` checks the equation of state against 45 states computed
  independently at 50 digits (`tests/eos_reference.py`), plus its error codes.
- **Deck tests**, `tests/run_deck_tests.sh` (also runnable on its own): every
  deck in `tests/decks/` is accepted, or rejected with the expected message,
  and every accepted deck round-trips and passes the setup audit; bad command
  lines (no deck, a missing file, a folder, an empty file) stop cleanly.
- **OpenMP tests**, `tests/run_omp_tests.sh`: the class deck and four test
  decks (two impact faces; a plate that spalls; method RS at order 2 and at
  order 1) run on 1 thread and on 2, 3, 4 and 8
  threads, as many as the machine has processors for. Everything printed from
  t = 0 on, every heartbeat line and every tracer row must be identical to the 1-thread run
  (clock times aside). Any difference means a race condition. A serial build
  (`make OMPFLAGS=`) skips them.

Run it before every commit.

## Layout
| Folder | What |
|---|---|
| `src/main` | `maincode.f95` (the run, section by section), `bmpmaker.f95` |
| `src/modules` | `shock_mod` (database and input tables), `deck_mod` (deck reader), `eos_mod` (Mie-Gruneisen P and c), `av_mod` (the artificial viscosity method, one place at a time), `rs_mod` (the Riemann solver method), `trace_mod` (the tracer file), `bit_mod` (kinds and constants), colormap data |
| `src/colormaps`, `src/drawings` | bitmap colormaps; `draw_colormaps` (demo, kept in the build) |
| `src/utils` | `make_build_info.sh` (writes the build record), `timestamp` (not used by the run), `random` |
| `input` | decks and the deck syntax spec |
| `tests` | unit tests (`test_*.f95`), deck tests, `verification/` reference tracer data |
| `bin` | the executable |
| `doc` | the equation sheets the code is checked against, frozen copies (`doc/README.md`) |

## Acknowledgements
`bitwhiz` was designed and written by D. E. Kittell with the assistance of
Claude Opus 5.5 (Anthropic), an AI model, run at its medium effort setting and
used interactively in the Claude desktop app (Cowork) from October 2026. The
instructor set the code's architecture (the interleaved database, the chunk
and write-back rules), its numerical methods, its physics models (including
the expansion branch of the equation of state and the spall and damage rule),
its conventions and its style, and supplied the equation sheets and the
independent verification data it is checked against. Claude drafted much of
the source written since October 8, 2026, the test suites and the
documentation, under that direction, and carried out numerical checks and
studies on request (thread timing, the round-off review, prototypes of new
methods). Every change was reviewed, built and tested by the instructor before
it was committed, and the instructor is responsible for all of the content.
The equations and material data come from the open literature, as cited.

AI models change quickly, so this record is dated: it describes the model and
the way of working used for this version of the code, not a general claim
about what such tools can or cannot do.

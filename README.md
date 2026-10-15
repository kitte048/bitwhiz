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
| Artificial viscosity time loop | next |
| Tracer and snapshot output | to do |
| Comparison with reference data | data in `tests/verification/` |

## Build
Needs gfortran and make.
```
make            # bin/bitwhiz, debug build with strict flags and -fopenmp
make test       # build if needed, then run the unit and deck tests (see Test)
make cleanrun   # remove run outputs (heartbeats, bitmaps in input/); keep the build
make clean      # cleanrun, plus objects, module files and the executable
make cleanbmp   # remove bitmaps in this folder (kept by the two above)
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
writes `<title>.heartbeat` in the current folder; watch it with `tail -f`.

## Test
```
make test
```
Two kinds of test, both run by `make test`, which stops at the first failure:

- **Unit tests**, one program each, `tests/test_*.f95`, exit status 0 = pass.
  `test_eos` checks the equation of state against 45 states computed
  independently at 50 digits (`tests/eos_reference.py`), plus its error codes.
- **Deck tests**, `tests/run_deck_tests.sh` (also runnable on its own): every
  deck in `tests/decks/` is accepted, or rejected with the expected message,
  and every accepted deck round-trips and passes the setup audit; bad command
  lines (no deck, a missing file, a folder, an empty file) stop cleanly.

Run it before every commit.

## Layout
| Folder | What |
|---|---|
| `src/main` | `maincode.f95` (the run, section by section), `bmpmaker.f95` |
| `src/modules` | `shock_mod` (database and input tables), `deck_mod` (deck reader), `eos_mod` (Mie-Gruneisen P and c), `bit_mod` (kinds and constants), colormap data |
| `src/colormaps`, `src/drawings` | bitmap colormaps; `draw_colormaps` (demo, kept in the build) |
| `src/utils` | `make_build_info.sh` (writes the build record), `timestamp` (not used by the run), `random` |
| `input` | decks and the deck syntax spec |
| `tests` | unit tests (`test_*.f95`), deck tests, `verification/` reference tracer data |
| `bin` | the executable |

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
| Mesh setup at t = 0 | next |
| Equation of state, artificial viscosity time loop | to do |
| Tracer and snapshot output | to do |
| Comparison with reference data | data in `tests/verification/` |

## Build
Needs gfortran and make.
```
make            # bin/bitwhiz, debug build with strict flags and -fopenmp
make clean      # remove objects, module files and the executable
make OMPFLAGS=  # a serial build from the same source
```
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
./tests/run_deck_tests.sh
```
Reads every deck in `tests/decks/` and checks that it is accepted, or rejected
with the expected message, and that every accepted deck round-trips.

## Layout
| Folder | What |
|---|---|
| `src/main` | `maincode.f95` (the run, section by section), `bmpmaker.f95` |
| `src/modules` | `shock_mod` (database and input tables), `deck_mod` (deck reader), `bit_mod`, colormap data |
| `src/colormaps`, `src/drawings` | bitmap colormaps; `draw_colormaps` (demo, kept in the build) |
| `src/utils` | `timestamp`, `random` |
| `input` | decks and the deck syntax spec |
| `tests` | deck tests; `verification/` reference tracer data |
| `bin` | the executable |

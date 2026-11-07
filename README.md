# bitwhiz
[![tests](https://github.com/kitte048/bitwhiz/actions/workflows/tests.yml/badge.svg)](https://github.com/kitte048/bitwhiz/actions/workflows/tests.yml)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23999297.svg)](https://doi.org/10.5281/zenodo.23999297)

A one-dimensional, planar, Lagrangian hydrocode in Fortran (F2018), written for
the ME 697 class project: a Ta-backed Al flyer impacts Material X behind a PMMA
window, and the code predicts the PDV velocity at the Material X/PMMA interface.

bitwhiz is the reference hydrocode for ME 697, Intermediate Shock and
Detonation Theory (Purdue, Fall 2026). It has two solution methods in one
code (artificial viscosity, and Godunov's method with an acoustic Riemann
solver at first or second order), the Mie-Grüneisen equation of state with
temperature, the History Variable Reactive Burn (HVRB) with ideal-gas
products, starting-velocity profiles, spall, tracers, a history file of the
whole mesh, and pictures (t-x diagrams, tracer plots, pressure movies). Each
method follows an equation sheet kept in `doc/`, and the code is checked
against 50-digit references, exact solutions and independent reference data.

**Try it in a browser**, with nothing to install:
https://nanohub.org/tools/bitwhiz (nanoHUB).

**Quick start** (gfortran 8 or newer, and make):
```
make                                               # bin/bitwhiz
./bin/bitwhiz input/me697_double_shock_2p00.deck   # the class problem
make test                                          # every test, about 4 minutes
```

| Where | What |
|---|---|
| `input/README.md` | the input deck: its syntax, every block and key, and the files a run writes |
| `doc/` | the equation sheets the code follows (frozen copies) |
| `doc/design/` | design notes and studies: velocity profiles, materials and the burn, five more burn models (draft), method AV |
| `tests/verification/README.md` | the reference data, and the scripts that compare bitwhiz with it |
| `CONTRIBUTING.md`, `RELEASING.md` | reporting issues and contributing; how a version is released |

## Status
| Part | State |
|---|---|
| Build system, strict compiler flags, OpenMP | done |
| Input deck: syntax spec, reader, about 150 test decks | done (`input/README.md`) |
| Database layout, material/layer/tracer tables | done (`src/modules/shock_mod.f95`) |
| Heartbeat file (opened and closed) | done; cycle lines come with the time loop |
| Mesh setup at t = 0, with a setup audit | done (maincode sections 5-6) |
| Equation of state (Mie-Gruneisen), with unit test | done (`src/modules/eos_mod.f95`) |
| Artificial viscosity time loop, OpenMP (bit-for-bit with serial) | done (`src/modules/av_mod.f95`, maincode section 7) |
| Expansion EOS (cubic, smooth through V0) and spall (`spall_strength`) | done (`eos_mod`, `av_mod`; see `input/README.md`) |
| Tracer file (`<title>.tracers.csv`, `tracer_dt`) | done (`src/modules/trace_mod.f95`; see `input/README.md`) |
| Second method, `method = RS` (Godunov's method, acoustic Riemann solver), in the same code; `order = 2` (MUSCL-Hancock, Van Leer, the default) or `1` | done (`src/modules/rs_mod.f95`, maincode section 7; equation sheet `doc/Hydrocode_RS_Eqns_v4`) |
| History file `<title>.hist`: x, u, P and damage on the whole mesh, one frame per snapshot (`plot_every`, `plot_dt`) | done (`src/modules/hist_mod.f95`; format in `input/README.md`, section 9) |
| Pictures: t-x diagrams of u and P, one plot per tracer, a pressure movie, P against x (`movie_frames`, 2 to 50); `plots_only = yes` re-draws them without running || done: both t-x diagrams (lab frame; white outside the material and in open spall, and in P where no wave has reached) and the tracer plots (velocity against time); each framed and titled (BITWHIZ PRESSURE, VELOCITY and SCOPE VIEW), the t-x diagrams with a color bar, all anti-aliased; the axis ends printed as numbers, each axis rounded out to clean ends, and the color bar labeled with its window (1.2.0; axis names and units next) (`src/modules/pics_mod.f95`, `src/drawings/draw_tx.f95`, `draw_trace.f95`, `draw_profile.f95`, `src/modules/strk_mod.f95`; `input/README.md` section 9b) |
| Velocity profiles: a layer's starting velocity shaped by a probability density (`xvel_profile`, `xvel_amplitude`; uniform, linear, beta, normal, split normal, sinh-arcsinh, Cauchy), momentum exact | done, 1.1.0 (`src/modules/dist_mod.f95`, with unit test; `input/README.md`, Layer block; design `doc/design/distributions.md`; example decks `input/ramp_*.deck`, `input/pulse_split_normal.deck`, checked against exact linear acoustics) |
| Material models: `eos = mie_gruneisen` (the default) or `mie_gruneisen_t`, the same P and c plus each cell's temperature (`CV`, `T0`; the cold curve carried cell by cell), `TK` in the tracer and history files, the T range and hottest cell (intact cells) in the log | done, 1.2.0 (`src/modules/temp_mod.f95`, with unit test; `input/README.md`, Material block; design `doc/design/materials.md`; checked against G1's temperatures by `compare_g1.py`) |
| Reactive burn: `burn = hvrb` with `products = ideal_gas` (HVRB, the HVRB equation sheet), each cell's extent of reaction lam, `XRN` in the tracer and history files, the first cell to react and the cells burnt out in the log | done for both methods, RS with the reaction's source in its predictor (`src/modules/burn_mod.f95`, `hvrb_mod.f95`, `mix_mod.f95`, `prod_mod.f95`, with unit test; `input/README.md`, Material block; design `doc/design/materials.md`, phase 3); checked against the gold-standard reactive data G2-G5 by `tests/verification/compare_hvrb.py` (run distances, arrivals within 5 ns, D within 0.5 % of D_CJ, mesh convergence); example deck `input/me697_hvrb_2p00.deck` |
| Comparison with reference data | data in `tests/verification/` (the class problem; gold-standard sets G1, inert, and G2-G5, HVRB); `tests/verification/gold.py` reads it and reproduces the gold standard's published results; bitwhiz against G1 (inert): `tests/verification/compare_g1.py`, all pass (P, u, rho at 1 mm within 0.001 % of exact; arrivals within 5 ns; TK the formula's at bitwhiz's own state to 1e-11 K, and within 0.011 % of the exact Hugoniot rise at 1 mm); bitwhiz against G2-G5 (HVRB): `tests/verification/compare_hvrb.py`, all pass (run distances equal to the reference's but one, a tracer spacing early; arrivals within 5 ns in G2 and G3; D within 0.31 % of D_CJ; the mesh study converging to the reference's PDV arrival to 0.0 ns); what method AV does at a detonation and a free surface, against mesh: `tests/verification/study_av.py` (`doc/design/av_study.md`) |

## Build
Needs gfortran (version 8 or newer) and make. Python 3 with NumPy and mpmath
is needed only for the scripts in `tests/verification/` and the 50-digit
reference generators (`tests/*_reference.py`), not for `make test`.
```
make            # bin/bitwhiz, debug build with strict flags and -fopenmp
make test       # build if needed, then run the unit and deck tests (see Test)
make release    # bin/bitwhiz_release, optimized (-O2), checked against the debug build
make runs       # run every deck in input/ (release build), each into runs/<deck>/
make tidy       # remove run outputs (heartbeats, tracer and history files, pictures, runs/); keep the build
make clean      # tidy, plus objects, module files and both executables
make bmpclean   # remove any other bitmaps in this folder (kept by the two above)
make OMPFLAGS=  # a serial build from the same source
```
The root `Makefile` is the only build; there are no Makefiles under `src/`.
After changing compiler flags, run `make clean` first.

`make release` is the executable to hand out or host: about 3 times faster on
the class problem, with the run-time checks and floating-point traps left out
(a NaN still stops the run, through the heartbeat's finite check). It builds
in `build/release/`, so the debug build is never touched, and then runs the
deck and OpenMP tests on it, plus `tests/run_release_tests.sh`: the class deck
and nine test decks must give the debug build's results, heartbeat and
tracer rows bit for bit. Develop and run `make test` with the debug build;
run `make release` before handing an executable out.

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
writes `<title>.resolved` in the current folder (the deck with every default
filled in: `bitwhiz <title>.resolved` repeats the run), and
`<title>.heartbeat`, one line per cycle (time step and the cell that set it,
largest pressure, mass and energy errors, total momentum); watch it with
`tail -f`. The heartbeat also records the first cell
to go tensile, the first cell to break (spall: its pressure fell below
`-spall_strength`, set per material), and the first void cell, if any. A deck
with tracers also writes `<title>.tracers.csv`: one row per `tracer_dt`, laid
out like the verification data in `tests/verification/`. A deck with snapshots
(`plot_dt` or `plot_every`) also writes `<title>.hist`, the whole mesh over
time, and every run ends by drawing its pictures: t-x diagrams of u and P
(`<title>.tx_u.bmp`, `.tx_p.bmp`), one plot per tracer
(`<title>.tr_<name>.bmp`) and, with `movie_frames`, the frames of a
pressure movie (`<title>.mv_p_<cycle>.bmp`); see `input/README.md`,
section 9b. The screen says what it is doing in sections 2 to 9 (about 130
lines for the class deck), and section 8 lists every file the run wrote,
with its size.

## A typical session
From the bitwhiz folder, starting cold:
```
make                 # debug build, bin/bitwhiz
make test            # every test; about 4 minutes on 2 cores
make release         # bin/bitwhiz_release, checked against the debug build
make tidy            # clear the tests' leftover run files
cd input
../bin/bitwhiz_release me697_double_shock_2p00.deck
```
The run's files land beside the deck, in `input/`. The two builds give the
same answers bit for bit; the release build is about 3 times faster, so it is
the one to drive, and the debug build (`../bin/bitwhiz`) the one to develop
with.

To look at every example after a code change, `make runs` (from the bitwhiz
folder) builds the release executable if needed and runs each deck in
`input/` in its own folder, `runs/<deck>/`, beside a copy of the deck, with
its screen in `screen.txt` and every file it writes: about 20 s and 410 MB
for the eleven decks. One line per deck says how it ended, its wall time, and
its files' count and size. Each `make runs` starts fresh; `make tidy` removes
`runs/`. `make runs RUN_EXE=./bin/bitwhiz` uses the debug build instead.

On a Mac, close Preview's windows on `runs/` (or quit Preview) before `make
runs` or `make tidy`: both delete the files and write them anew under the
same names, and a Preview that still holds the old ones can then refuse the
new ones ("you don't have permission to view"), whatever is in them, until
it is quit and opened again (Nov 4, 2026; the files were fine).

To tune the pictures without running again, add `plots_only = yes` to the
Run block and change `colormap` or the color windows (`plot_u_lo`,
`plot_u_hi`, `plot_p_lo`, `plot_p_hi`) in the Output block; each re-draw
takes about a second. Set it back to `no` (or delete the line) for a real
run. The class deck ends with a reference of every key, its default and its
options, the colormap names among them. `make tidy` (from the bitwhiz
folder) clears the run's files from `input/` too.

## Test
```
make test
```
Four kinds of test, all run by `make test`, which stops at the first failure:

- **Unit tests**, one program each, `tests/test_*.f95`, exit status 0 = pass.
  `test_eos` checks the equation of state against 45 states computed
  independently at 50 digits (`tests/eos_reference.py`), plus its error codes.
  `test_dist` checks the distributions (module `distributions`) against
  values computed at 50 digits (`tests/dist_reference.py`), plus identities
  and its parameter checks. `test_temp` checks the temperature model's cold
  energy and Hugoniot temperatures (module `temperature`) against values
  computed at 50 digits by direct quadrature (`tests/temp_reference.py`).
  `test_hvrb` checks the burn (modules `hvrb` and `products`: the rate
  law, the topology, the closure, its sound speed and dP/dlam) against
  values computed at 50 digits from the HVRB equation sheet's definitions
  (`tests/hvrb_reference.py`), plus the D^2 law, the constant-volume burn
  and the guards.
- **Deck tests**, `tests/run_deck_tests.sh` (also runnable on its own): every
  deck in `tests/decks/` is accepted, or rejected with the expected message,
  and every accepted deck round-trips and passes the setup audit; bad command
  lines (no deck, a missing file, a folder, an empty file) stop cleanly.
- **OpenMP tests**, `tests/run_omp_tests.sh`: the class deck and nine test
  decks (two impact faces; a plate that spalls; method RS at order 2 and at
  order 1; velocity profiles; temperature, AV and RS; a burn, AV and RS)
  run on 1 thread and on 2, 3, 4 and 8 threads, as many as the machine has
  processors for, so the count of these tests depends on the machine: 40
  with 8 or more processors, 30 with 4 to 7, 20 with 3, 10 with 2.
  Everything printed from
  t = 0 on, every heartbeat line and every tracer row must be identical to the 1-thread run
  (clock times aside). Any difference means a race condition. A serial build
  (`make OMPFLAGS=`) skips them. The history file must match too, byte for
  byte (apart from its text block, which names the build).
- **History file tests**, `tests/run_hist_tests.sh`: `bin/test_hist` checks
  each run's `<title>.hist` against its format (`input/README.md`,
  section 9), and against the tracer file at the same cycles, for both
  methods; plus velocity profiles (frame 1's velocities against the
  profiles, computed again in the test), `plot_every`, a run stopped by
  `cycle_max`, a deck without snapshots, and `plots_only` (same ranges
  as the run, the run's
  files untouched, an error for another mesh or missing files); a burn
  (`XRN` in the file: 0 at t = 0, 0 to 1, never falling, and the tracer
  file's) and the inert limit (a burn that never starts gives the inert
  run's heartbeat, tracer rows and frames, bit for bit). Every run
  must write exactly its pictures, by name and size, and the class run's
  t-x diagrams are checked pixel by pixel at known places; the OpenMP and
  release tests also require the pictures to be identical, byte for byte.

`make release` runs the deck and OpenMP tests again on the optimized build, and
a fourth kind, the **release tests** (`tests/run_release_tests.sh`): both builds
must print the same results, bit for bit (see Build).

Run it before every commit. On GitHub, every push to `main` and every pull
request runs `make test` and `make release` with gfortran 8 (nanoHUB's
series) and 13, and with the newest gfortran as a warning only
(`.github/workflows/tests.yml`).

## nanoHUB
bitwhiz runs on nanoHUB as the tool **bitwhiz**
(https://nanohub.org/tools/bitwhiz): a Jupyter notebook in front of the
optimized executable, with the decks of `input/` in its picker, so it runs in
a browser with nothing to install. The tool's wiki there has an "Inspect
source code" button. How a version reaches nanoHUB (the one-way rule, tags,
the export, nanoHUB's gfortran 8.3) is in `RELEASING.md`.

## Layout
| Folder | What |
|---|---|
| `src/main` | `maincode.f95` (the run, section by section), `bmpmaker.f95` |
| `src/modules` | `shock_mod` (database and input tables), `deck_mod` (deck reader), `eos_mod` (Mie-Gruneisen P and c), `temp_mod` (module `temperature`: each cell's cold energy and temperature, for `mie_gruneisen_t`), `burn_mod` (module `burn`: each burning cell's phi and lam, and the burn's step in the time loop), `hvrb_mod`, `mix_mod` and `prod_mod` (the HVRB rate law, the closure of a burning cell, module `mixture`, and the products' EOS: stateless), `av_mod` (the artificial viscosity method, one place at a time), `rs_mod` (the Riemann solver method), `trace_mod` (the tracer file), `hist_mod` (the history file), `pics_mod` (the pictures), `strk_mod` (the pictures' frame and font), `dist_mod` (probability distributions, self-contained), `bit_mod` (kinds and constants), colormap data |
| `src/colormaps`, `src/drawings` | bitmap colormaps; `draw_tx`, `draw_trace` and `draw_profile` (a run's pictures; `draw_profile` draws a movie frame, and a tracer plot for `draw_trace`), `draw_colormaps` (demo, kept in the build) |
| `src/utils` | `make_build_info.sh` (writes the build record), `export_nanohub.sh` (copies a tag into the nanoHUB clone), `run_decks.sh` (`make runs`), `timestamp` (not used by the run), `random` |
| `input` | decks and the deck syntax spec |
| `tests` | unit tests (`test_*.f95`, with their 50-digit references `*_reference.py`), deck, OpenMP, history file and release tests, `verification/` reference tracer data, its reader (`gold.py`), the comparisons with it (`compare_g1.py`, `compare_hvrb.py`) and the study of method AV (`study_av.py`) |
| `bin` | the executables: `bitwhiz` (debug), `bitwhiz_release` (optimized) |
| `build/release` | the release build's objects and module files (made by `make release`, not in git) |
| `doc` | the equation sheets the code is checked against, frozen copies (`doc/README.md`) |

## Citing
If you use bitwhiz, cite the version you used: `CITATION.cff` has the
details (GitHub's "Cite this repository" reads it). Every release is archived
on Zenodo; doi:10.5281/zenodo.23999297 stands for all versions and resolves to
the newest, and each version's own DOI is on its Zenodo page.

## Contributing
Questions, bug reports and contributions are welcome: see `CONTRIBUTING.md`.

## License
Apache License 2.0 (`LICENSE`).

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

### Colormaps
The pictures' colormaps are tables from Kenneth Moreland's color advice
(https://www.kennethmoreland.com/color-advice/; K. D. Moreland, "Why We Use
Bad Color Maps and What You Can Do About It", SAND2015-11068C, Sandia
National Laboratories, 2015). Their origins and terms, as that page gives
them: smooth cool-warm and bent cool-warm are Moreland's (K. Moreland,
"Diverging Color Maps for Scientific Visualization", 2009), from ParaView,
under its BSD license; viridis, plasma and inferno are matplotlib's (Stéfan
van der Walt and Nathaniel Smith; the page also credits Eric Firing), under
matplotlib's BSD-compatible license; kindlmann is from G. Kindlmann, E.
Reinhard and S. Creem, IEEE Visualization 2002 (doi:10.1109/VISUAL.2002.1183788),
and extended kindlmann derives from it; black body has appeared in the
literature since at least 1983. Moreland releases his own maps as CC0, and
the page knows of no one claiming the kindlmann and black body colors.

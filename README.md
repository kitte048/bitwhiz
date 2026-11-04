# bitwhiz
A one-dimensional, planar, Lagrangian hydrocode in Fortran (F2018), written for
the ME 697 class project: a Ta-backed Al flyer impacts Material X behind a PMMA
window, and the code predicts the PDV velocity at the Material X/PMMA interface.

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
| Comparison with reference data | data in `tests/verification/` (the class problem; gold-standard sets G1, inert, and G2-G5, HVRB); `tests/verification/gold.py` reads it and reproduces the gold standard's published results; bitwhiz against G1 (inert): `tests/verification/compare_g1.py`, all pass (P, u, rho at 1 mm within 0.001 % of exact; arrivals within 5 ns; TK the formula's at bitwhiz's own state to 1e-11 K, and within 0.011 % of the exact Hugoniot rise at 1 mm) |

## Build
Needs gfortran and make.
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
and seven test decks must give the debug build's results, heartbeat and
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
make test            # every test; about 3 minutes on 2 cores
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
its screen in `screen.txt` and every file it writes: about 10 s and 240 MB
for the ten decks. One line per deck says how it ended, its wall time, and
its files' count and size. Each `make runs` starts fresh; `make tidy` removes
`runs/`. `make runs RUN_EXE=./bin/bitwhiz` uses the debug build instead.

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
- **OpenMP tests**, `tests/run_omp_tests.sh`: the class deck and seven test
  decks (two impact faces; a plate that spalls; method RS at order 2 and at
  order 1; velocity profiles; temperature, AV and RS) run on 1 thread and on
  2, 3, 4 and 8 threads, as many as the machine has processors for, so the
  count of these tests depends on the machine: 32 with 8 or more
  processors, 24 with 4 to 7, 16 with 3, 8 with 2.
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
  files untouched, an error for another mesh or missing files). Every run
  must write exactly its pictures, by name and size, and the class run's
  t-x diagrams are checked pixel by pixel at known places; the OpenMP and
  release tests also require the pictures to be identical, byte for byte.

`make release` runs the deck and OpenMP tests again on the optimized build, and
a fourth kind, the **release tests** (`tests/run_release_tests.sh`): both builds
must print the same results, bit for bit (see Build).

Run it before every commit.

## Releases and nanoHUB
bitwhiz runs on nanoHUB as the tool **bitwhiz**
(https://nanohub.org/tools/bitwhiz): a Jupyter notebook in front of the
optimized executable. The tool has its own git repository on nanoHUB (cloned
here as `~/Documents/Academic/bitwhiz`), with the notebook, the
`middleware/invoke` script that starts it, and a small `src/Makefile` around a
copy of this code in `src/bitwhiz/`.

**The rule: changes flow one way.** Code is changed here, never in the nanoHUB
copy:
```
fix on shock  ->  make test, make release  ->  tag vX.Y.Z  ->  export to the
nanoHUB clone  ->  one push  ->  nanoHUB installs it  ->  test and approve
```
- **Branches.** `shock` is the release line: every tag, and so every nanoHUB
  version, is a commit on it. New work goes on its own branch (as the velocity
  profiles did on `distributions`, released in 1.1.0), which takes fixes from
  `shock` by `git merge shock`, goes back into `shock` when it is finished, and
  is then deleted.
- **Tags** are `vMAJOR.MINOR.PATCH`: PATCH for fixes (v1.0.2), MINOR for new
  features (v1.1.0). The banner prints the tag: here through `git describe`,
  on nanoHUB through the `VERSION` file the export writes.
- **Export** with `sh src/utils/export_nanohub.sh vX.Y.Z
  ~/Documents/Academic/bitwhiz`: it copies exactly that tag into the clone's
  `src/bitwhiz/` (no `doc/`, and none of the gold-standard data in
  `tests/verification/inert_gauges/` and `hvrb/`), writes `src/bitwhiz/VERSION` with the tag, copies
  the decks and `input/README.md` into the clone's `examples/` and `VERSION`
  into its `bin/` (an installed tool's `src/` is not readable by its users),
  lists files the tag no longer has, and prints the commands to commit, tag and
  push. Then, in the clone, run those commands.
- **Push once.** nanoHUB has blocked this machine's address for hours after git
  pushes (support ticket open, Oct 2026), so send the commit and its tag in one
  `git push origin master vX.Y.Z`, with git's credential helper set
  (`git config --global credential.helper osxkeychain`).
- **Install.** On the tool's status page, follow the link **"Wait! I've made
  more changes"** (for a tool already installed or approved; it tells nanoHUB
  that new code is in the repository), or mark the code uploaded (status
  Uploaded) with a short note; nanoHUB's staff run `make install` in the tool's
  `src/` and set it to Installed. Check what was installed from a notebook cell,
  `!ls -la /apps/bitwhiz/dev /apps/bitwhiz/dev/bin` (`dev` points to the
  newest revision, e.g. `r5`; its `bin/` must hold `bitwhiz`), then launch the
  tool fresh and test it: Run, Redraw pictures only, the movie (it plays,
  and Files lists the .mp4, not its frames), an error on purpose, the
  history plot. Approve it on the status page when it works.

**nanoHUB's compiler is gfortran 8.3** (Debian 10). Keep the code to what
gfortran 8 accepts; Fortran 2018 features it lacks, and their replacements
here, are:

| Not in gfortran 8 | Use instead |
|---|---|
| zero-width `ES`/`EN` edit descriptors (`es0.16e3`) | a fixed width, leading blanks dropped (`trace_mod`, `num17`) |
| `stop code, quiet=.true.` | `call quit(code)` (module bits) |
| `random_init` | `random_seed` with a fixed seed (`draw_colormaps`) |

To check before a release, build with gfortran 8 if you can (`make clean;
make FC=gfortran-8 test`); v1.0.2 was tested with gfortran 8.4, 9, 10, 12
and 13; v1.1.0 with 13 and 15.2, and v1.2.0 with 9, 13 and 15.2, their
gfortran 8 checks left to nanoHUB's install (8.3).

**How the tool runs** (for the notebook, `bitwhiz.ipynb` in the clone):
nanoHUB copies the notebook into the session's results folder and starts it
there, so it finds the installed tool through the `TOOLDIR` environment variable
(`/apps/bitwhiz/dev`), not through its own folder. It starts in App Mode
(`start_jupyter -A` in `middleware/invoke`): every cell runs, the code is
hidden, and the user sees the text, the deck picker and the editor; "Edit App"
shows the code. Since every cell runs at launch, none may fail before a run.
The picker offers the decks in the tool's `examples/`, which the export fills
from `input/`, so a deck added to `input/` here reaches nanoHUB with the next
export. (The installed tool's `src/` is `drwxr-s---`: users cannot read it.) Runs are written to
`~/bitwhiz_runs/<title>`. After a run that draws movie frames, the notebook
makes them one `<title>.mv_p.mp4` with ffmpeg (the recipe in
`input/README.md`, section 9b) and removes them, so the frames' names,
`<title>.mv_p_*.bmp`, are part of what the notebook relies on. A session
sees 24 processors with no CPU limit, shared with other users:
`num_threads = 1` for class decks, 4 to 8 for large meshes.

## Layout
| Folder | What |
|---|---|
| `src/main` | `maincode.f95` (the run, section by section), `bmpmaker.f95` |
| `src/modules` | `shock_mod` (database and input tables), `deck_mod` (deck reader), `eos_mod` (Mie-Gruneisen P and c), `temp_mod` (module `temperature`: each cell's cold energy and temperature, for `mie_gruneisen_t`), `hvrb_mod` and `prod_mod` (the HVRB burn and its products' EOS, built and tested, not yet in the time loop), `av_mod` (the artificial viscosity method, one place at a time), `rs_mod` (the Riemann solver method), `trace_mod` (the tracer file), `hist_mod` (the history file), `pics_mod` (the pictures), `strk_mod` (the pictures' frame and font), `dist_mod` (probability distributions, self-contained), `bit_mod` (kinds and constants), colormap data |
| `src/colormaps`, `src/drawings` | bitmap colormaps; `draw_tx`, `draw_trace` and `draw_profile` (a run's pictures; `draw_profile` draws a movie frame, and a tracer plot for `draw_trace`), `draw_colormaps` (demo, kept in the build) |
| `src/utils` | `make_build_info.sh` (writes the build record), `export_nanohub.sh` (copies a tag into the nanoHUB clone), `run_decks.sh` (`make runs`), `timestamp` (not used by the run), `random` |
| `input` | decks and the deck syntax spec |
| `tests` | unit tests (`test_*.f95`, with their 50-digit references `*_reference.py`), deck, OpenMP, history file and release tests, `verification/` reference tracer data, its reader (`gold.py`) and the G1 comparison (`compare_g1.py`) |
| `bin` | the executables: `bitwhiz` (debug), `bitwhiz_release` (optimized) |
| `build/release` | the release build's objects and module files (made by `make release`, not in git) |
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

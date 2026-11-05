# TODO

Plans and open questions for bitwhiz. Items move out of this file when they
are done (the commit that does one says so). Release steps themselves are in
README.md, "Releases and nanoHUB".

Started Oct 23, 2026, the day bitwhiz 1.0.2 was approved for publication on
nanoHUB. Reordered Oct 31, 2026, after 1.0.3, from a brainstorm: one branch
again, the nanoHUB tool, gold-standard data, movies, HVRB, graded materials.
Reordered again Nov 2, 2026, after 1.1.0 (velocity profiles and the new
nanoHUB notebook, published) and the gold-standard data and its reader.
1.2.0 cut Nov 3, 2026: Mie-Grüneisen with temperature, the axis ends on
every picture, the shorter screen, `make runs`, movies in the class deck.
1.2.0 published on nanoHUB Nov 4, 2026 (with the notebook's MP4 movie),
and beta testing begun; the priorities reordered that day, from a roadmap
of next steps out to research. 1.3.0 cut Nov 4, 2026: HVRB (both methods,
verified against G2-G5) and its example deck.

## Priorities
Next, an afternoon each, little risk:
1. Housekeeping (section 2, open questions): `shock` as GitHub's default
   branch, the missing v1.0.1 tag, and a follow-up on ticket #516409 (IP
   blocks) before beta testers use the tool heavily.
2. The notebook (section 2), its changes collected into one nanoHUB
   release while beta testing runs: the Stop button first (testers will
   feel it), then a movie frame download, the movie step's timing, a
   scripting cell, `num_threads` notes in the decks; more example decks
   (wave overtake, spall, AV against RS) and gauges at the gold-standard
   depths in place of `mid_x`.
3. The history file size, said at the start of a run (section 8).
4. The arrival offset (section 3): G1 with RS order 2 and at 200 zones/mm.
   A cheap study.

Near term, verification and correctness, toward 1.3:
5. Order of accuracy and the acoustic check as tests (section 8).
6. Noh wall heating at the impact plane (section 8).
7. AV energy at a free surface (section 8).
8. Pictures: axis names and units, after lower case and mu in the stroke
   font (Ideas); a colormap table lookup, maybe (section 8).

Medium term, the reactive physics:
9. HVRB, checked against G2-G5 (sections 3 and 6): the v8 equation sheet
   frozen in `doc/` and G2-G5's inputs checked against it (Nov 4); the
   design (`doc/design/materials.md`, phase 3), steps 2 to 5 done Nov 4:
   both methods, all of G2-G5, an example deck; 1.3.0. Next for the burn:
   JWL products, the 25 zones/mm difference (section 3).
10. With it or after: a broken cell's temperature (section 5); strength,
    the spall "knocking", the 2025 survey's burn models (section 6).

Far out, research:
11. Graded materials (section 7): the path to publishing; the per-cell
    e_c of 1.2.0 was chosen for it. Sampling and ensembles (section 1),
    Bayesian calibration and a ramp drive fitted by inverse problem,
    cylindrical and spherical geometry, 2D, PNG (Ideas).

Throughout: no bloat. Cost per cycle stays the same or improves, and
`make test` stays a few minutes.

## 1. Velocity profiles (released in 1.1.0)
Design and status: `doc/design/distributions.md`.

- [ ] **Ramp decks that stay in compression,** as experiments are
      designed: realistic spall strengths, and a stack that never puts
      either layer in tension before `t_end` (a thicker window, an earlier
      `t_end`, a backing behind A). The four decks now turn spall off
      instead; `pulse_split_normal` cannot be fixed this way (its tension
      starts at t = 0).
- [ ] Verification: a linear compression ramp against the shock formation
      time from characteristics (derive it first, acoustic limit).
- [ ] Phase 2: sampling, `dist_inv_cdf`, and random velocity draws per cell
      (ensembles for uncertainty quantification).
- [ ] Later distributions: gamma, Weibull, log-normal.

## 2. nanoHUB tool (after 1.1.0)
These change the tool's notebook (`bitwhiz.ipynb` in the nanoHUB clone) and
the export; the Fortran is unchanged. 1.0.3 brought App Mode, the deck
picker, the Plot history button and the VERSION file. 1.1.0 brought every
release deck in the picker and the version in the banner (the export now
puts them in `examples/` and `bin/`: an installed tool's `src/` is
`drwxr-s---`), Upload a deck, Deck reference, captioned pictures (title,
run time, build; a file name under each), a run's old files cleared before
it runs, Files (a run, a kind, a file: Download, pictures as PNG; or the
run zipped), and plain messages for an empty deck, a bad title, a failed
run and an error inside a button (tests/test_notebook.py in the clone).
1.2.0 (published Nov 4) brought the pressure movie: after a run or a
redraw with frames, ffmpeg makes them one `<title>.mv_p.mp4`, played on
the page in an ipywidgets player, and the frames are removed (kept, and
listed under Pictures, if ffmpeg is missing or fails); a Movie kind in
Files; `<title>.resolved` under Deck; `steepening_hump` in the picker; a
run's old `.resolved`, frames and movie cleared before it runs (57 checks
in test_notebook.py). Notebook changes are best collected into one
release: each costs a push and an install.

- [ ] **More example decks** in the picker, each with a one-line label at
      the top of its comment box: a spall deck, AV against RS, later an
      HVRB deck (the U6 and velocity-profile decks are in, 1.1.0). And
      **wave overtake**: the class stack with a much thicker Ta backing and
      a thick Al target in place of Material X, so the reshock from the Ta
      overtakes the first shock in the Al: one stronger shock goes on, with
      a contact and a weak reflected rarefaction behind it (third order in
      shock strength: RS order 2 on a fine mesh, tracers through the Al).
- [ ] **Scripting example:** a cell showing that `bitwhiz` is on the path
      (`!bitwhiz my.deck`), and a short `%%bash` or Python sweep over
      `define u_fly` values.
- [ ] **A Stop button:** a run holds the notebook's kernel until it ends,
      so a button cannot stop it. Run bitwhiz in a thread (or poll the
      process) so Stop can kill it; until then a long run must finish.
      The first of these for beta testers.
- [ ] **A movie frame to download** (asked Nov 4): the frames are gone
      once the MP4 is made. Choices: a "keep the frames" box by Run (they
      stay under Pictures); a time box under Files, Movie, that pulls one
      frame from the MP4 as a PNG (`ffmpeg -ss <t> -frames:v 1`; cheap,
      slightly softened by the compression); or a slider under the movie
      with Save (the most code; needs the frames). The time box fits
      best: a report wants one time. Wait for the testers.
- [ ] **The movie step's time:** the class deck felt slower end to end on
      nanoHUB than steepening_hump (3,432 cycles, 1,001 snapshots and 35
      frames against 2,023, 351 and 25; the encode itself well under a
      second here). Time the run, the encode and the page's movie apart,
      and say "movie made in X s" if the encode is the slow part.
- [ ] **Two sessions, one title:** two browser tabs running decks with the
      same title write the same folder. Rare; a lock file would catch it.
- [ ] **num_threads note** in the example decks' comments: 1 for class
      problems; 4 to 8 for large meshes on nanoHUB (24 shared processors, no
      CPU limit).
- [ ] **The mid-sample tracer** (`tracer = mid_x MatX@0.5` in the class
      deck) gives a scope view of limited use. Keep it, or trade it for
      gauges at the gold-standard positions (1, 2, ..., 9 mm into
      Material X, section 3), so the tracer plots compare directly with
      the reference data.

### Open questions (nanoHUB and Purdue)
- [ ] **IP blocks:** support ticket #516409. The block followed git pushes
      (Oct 22 evening, Oct 23 morning) and also repeated page visits (Oct 23
      afternoon, no git). Follow up with the browsing case before sending
      testers; ask what triggers it and how to push without tripping it.
      No block during the 1.1.0 release (Nov 1-2: one push of two commits
      and a tag, the install, one test session, approval): one push per
      release, with its tag, seems to be safe.
- [ ] **Copyright holder** on the license line (Apache 2.0, "custom" on
      nanoHUB): David E. Kittell, or the Purdue Research Foundation? Ask OTC.
- [ ] **Export control:** a written determination from Purdue's export
      control office, now that the tool is public. KO, pyko and CAV_KO are
      precedents for public 1D teaching hydrocodes.
- [ ] **GitHub's default branch is `main`**, at the year-old commit this
      clone's history starts from: a new clone lands there, not on
      `shock`. Make `shock` the default in the repository's settings.
- [ ] **Tag v1.0.1** is in the nanoHUB clone but not here (v1.0, v1.0.2
      and v1.0.3 are in both). Find the commit it names and tag it here, or
      record why there is none.

## 3. Verification: the gold-standard data
In the repository since Nov 2, 2026, byte for byte with `SHA256SUMS`, and left
out of the nanoHUB export: `tests/verification/inert_gauges/` (G1, inert) and
`tests/verification/hvrb/` (G2-G5), each with a README (provenance, tracers,
format, trust windows, suggested tolerances). From DK's independent Eulerian
code, Oct 30, 2026; the originals and the derived results are in the course
folder's `Equation_Sheets/HVRB_rev-0/verification/`. The format is that of
`tests/verification/`, with more per tracer: DENS, TK (temperature), XRN3
(reaction progress, lambda); MJKG is written but empty. (Thinning the rows was
tried and dropped: the reactive files keep 94-100 % of their rows, and git
stores the twenty files compressed, about 7 MB.)

The reader, `tests/verification/gold.py` (Python 3, NumPy), reads every file
in `tests/verification/` (the five `ME697_*.dat` too) and computes the
derived quantities with the dataset README's definitions: arrival, shock
speed fit, run distance, first-shock state, trust window, energy drift, and
the exact impedance match. `python3 tests/verification/gold.py` reproduces
that README's published tables (76 checks, Nov 2, 2026). (That README's G5
energy drift at 100 zones/mm read 0.004 %, 0.00346 rounded twice; corrected
to 0.0035 % there, Nov 2.)

bitwhiz against G1 (Nov 2, 2026): `inert_gauges/g1_inert.deck`, run and
checked by `tests/verification/compare_g1.py` at the five velocities, AV, 100
zones/mm: 25 checks, all pass. The first shock at 1 mm (P, u, rho) within
0.001 % of the exact impedance match; arrivals within 5 ns; energy drift
0.0011-0.0017 %, half the reference's. Results in `inert_gauges/README.md`.

- [ ] **The arrival offset:** bitwhiz's arrivals are 0 to 4.4 ns later than
      the reference's at every gauge and velocity, never earlier (within
      the 5 ns tolerance and the output spacing). Likely how each code
      spreads the shock's foot, which the 0.05 km/s threshold reads. Rerun
      with RS order 2 and at 200 zones/mm: does the offset follow the
      method, the mesh, or neither?
- [x] **Temperature at the G1 gauges** (Nov 3, with MG+T, section 5):
      `compare_g1.py`, 40 checks, all pass. bitwhiz's TK is the formula's
      at its own state to 1e-11 K, and within 0.03 K of the exact
      Hugoniot temperature at 1 mm; the formula at the reference's own
      state agrees with its TK for PMMA to 0.004 K. Material X: the
      reference is 0.9-4.6 K hotter (growing with the shock, the same at
      every depth, and after the Ta reshock too: 788 K vs 784 K).
- [x] **How the reference's EOS tool computes T and e_c** (Nov 3): one
      query of the tool (`inert_gauges/eos_tool/`). Its pressure is
      bitwhiz's; its Material X cold energy is not the integral of that
      pressure (PMMA's is), which is G1's 0.9-4.6 K, to 0.006 K; its
      pressure's zero at 298.0014 K is G1's start. Not pursued further:
      bitwhiz has its own temperature standard (T1-T5,
      `doc/design/materials.md`), and G1's TK is reported, not checked.
- [x] **G2-G5 (reactive), with HVRB** (Nov 4): `hvrb/g2_react.deck` (class
      stack) and `hvrb/g3_poplt.deck` (thick flyer), compared with
      `hvrb/README.md`'s tolerances by `compare_hvrb.py`: 36 checks, all
      pass (`doc/design/materials.md`, phase 3, step 5, the table).
- [ ] **The 25 zones/mm difference:** bitwhiz AV's PDV arrival is 13 ns
      early at 25 zones/mm against the reference's 25 zones/mm run (RS
      order 2 about 7; from 50 zones/mm up within 1 ns), where the reaction
      zone spans 3 to 4 cells. Which part of the scheme (AV's q in the
      reaction zone, the burn's first-order quadrature of Phi over a long
      dt, the closure's sound speed) sets it, and does a burn time-step
      limit (Delta lam per step) close it?
- [x] Check that the data's HVRB inputs match the equation sheet bitwhiz
      will follow (Nov 4): the dataset's README cites `HVRB_Eqns_v3.tex`;
      the sheet's model and constants are the same in v3 and v8, frozen
      as `doc/HVRB_Eqns_v8` (`doc/README.md`).

## 4. Movies: profiles along x
Done Nov 2-3, 2026: `movie_frames = N` (Output block; 0 or absent = none; 2
to 50, so no deck can flood its folder) draws a pressure movie from the
history file: P against x, one frame from the snapshot nearest each of N
times spread evenly from 0 to the last snapshot (a subset of the snapshot
times; plots_only redraws it). Files `<title>.mv_p_<cycle>.bmp`, the cycle
in six digits; frames titled PRESSURE AT TIME = +1.234 US (new glyphs in the
stroke font); axes fixed for the whole movie (x as the t-x diagrams', y by
the plot_range rule). About 0.08 s a frame in the release build. Drawn by
draw_profile, now under draw_trace too (tracer plots unchanged, byte for
byte). input/README.md, section 9b; the class deck's key reference; deck
tests and a history-file test (the frames worked out again in awk;
plots_only byte for byte). The first version (Nov 2: `movie_dt`, three
movies, P, u and density) gave no bound on the number of pictures; a
small movie_dt made hundreds. A movie is a preview: figures come from the
history file.

- [x] **The nanoHUB notebook** (1.2.0, published Nov 4): the frames made
      one MP4 with ffmpeg and played on the page, then removed; a Movie
      kind in Files (section 2).
- [ ] **Velocity or density movies,** if wanted later: re-engineer them
      then (velocity at the faces; density as R0 dx0/dx, the history file
      has none; for density, rho/rho0 or eta reads better across materials
      as different as Ta and PMMA). Removed Nov 3 to keep the code small.

## 5. Material models: the architecture
Design note `doc/design/materials.md`, approved Nov 3, 2026: one equation of
state per material, `eos = mie_gruneisen` (the default: read and computed
exactly as now, every existing deck bit for bit) or `eos =
mie_gruneisen_t` (the same P and c, plus temperature: `CV`, `T0`); add-ons
later in the same pattern (`burn = hvrb`). The model is chosen once per
layer, never per cell per cycle. Extra state (here e_c and T) lives in
the model's own module (`src/modules/temp_mod.f95`, arrays by cell, the
database untouched), allocated only when a deck uses the model, and goes
to the tracer and history files when present. Each cell carries its own
cold energy e_c ("plan C"), so constants graded cell by cell (section 7)
need no tables.

- [x] **Phase 2: Mie-Grüneisen with temperature** (Nov 3): keys, the
      temperature module, the per-step update, `TK` in the tracer and
      history files, T range and hottest cell (intact cells) in the log,
      the six tests;
      every old deck bit for bit; G1's temperatures checked
      (`compare_g1.py`, 40 checks). Notes on the build in the design note.
- [x] **Release 1.2.0** (Nov 3; on nanoHUB Nov 4): MG+T and its
      verification (T1-T5);
      the axis ends on every picture; bitmaps a row at a time; the
      screen (132 lines, `<title>.resolved`, section 8's file sizes);
      `make runs`; pressure movies in the class deck,
      `pulse_split_normal` and the new `steepening_hump`. Tagged on
      `shock`; the nanoHUB tool with it, with the notebook's MP4 movie,
      the `.resolved` download and `steepening_hump` in the picker
      (section 2), approved and published Nov 4; beta testing begun.
- [ ] **Release 1.3.0** (Nov 4): HVRB with ideal-gas products (both
      methods, verified against G2-G5), `XRN` outputs, the example deck
      `me697_hvrb_2p00.deck` in the nanoHUB picker. Tagged on `shock`, the
      nanoHUB tool with it; then test and approve.
- [ ] **A broken cell's temperature:** written as computed, it falls as
      the cell opens (P floored at 0, e_c following V): -4,693 K in G1's
      spalled PMMA at 2.00 km/s. The log skips broken cells. Decide what
      a broken cell should carry (freeze e_c at the break? report 0?)
      with HVRB or a damage model.
- [ ] **Constants per cell** for grading (section 7): the database's
      layout for them, when grading starts.

## 6. Material models: new ones
Each one checked against the commercial reference code on a small set of
decks.

- [x] **Mie-Grüneisen with temperature** (Nov 3): section 5, phase 2,
      and `doc/design/materials.md`. HVRB needs it: its closure puts
      reactant and products at one density and one temperature.
- [ ] **Strength:** elastic-perfectly-plastic, von Mises yield, with thermal
      softening (needs T from the model above): deviatoric stress and
      plasticity.
- [ ] **Spall: is the knocking physical?** With spall on, the profile
      decks break the aluminum in many cells, and the broken pieces knock
      against each other: a sawtooth in the tracer velocities (period about
      0.07 us at 25 zones/mm). Find whether it is physical (scabs
      colliding) or numerical (broken cells reopening and closing): mesh
      and method dependence, and a comparison with a damage model.
- [ ] **History-variable reactive burn (HVRB)**, following the equation
      sheet (`Equation_Sheets/HVRB_rev-0/HVRB_Eqns_v8.tex`, published as
      `Class_Project/HVRB_Eqns_rev-0.pdf`; frozen as `doc/HVRB_Eqns_v8`,
      Nov 4, 2026): reactant Mie-Grüneisen with the energy shift
      Q, ideal-gas products, density-temperature equilibrium, the HVRB rate
      (P_R, Z_R, M_R, X_R, P_I, tau_0). Checked against G2-G5 (section 3):
      run distance, the Pop plot, D_CJ = 7.500 km/s within 0.5 %, the mesh
      study. Then with a JWL products EOS. Design: `doc/design/materials.md`,
      phase 3 (approved Nov 4). Step 2 done Nov 4: modules `hvrb` and
      `products` and `test_hvrb` (11 checks, 50 digits). Step 3a done Nov
      4: the deck keys, module `burn`, method AV, `XRN` in the tracer and
      history files, the inert limit bit for bit; G2 at 2.00 km/s already
      within 5 ns at every gauge. Steps 3b and 4 done Nov 4: method RS,
      with the reaction's source in its order-2 predictor (per cell, per
      step); AV, RS order 2 and order 1 all within 5 ns of G2 at every
      gauge at 2.00 km/s, and AV and RS order 2 at 1.50. Step 5 done Nov
      4: G2-G5 all pass (section 3); the example deck
      `input/me697_hvrb_2p00.deck`, exported to nanoHUB with the others
      (decided Nov 4: the model in action, for students who do not use
      Fortran). Released in 1.3.0.
- [ ] **The burn models from the 2025 survey:** FlashFire,
      StochasticIgnite and ThermalCascade, from D. E. Kittell et al., "A
      Short Survey of Current Reactive Burn Model Capabilities as of
      Mid-Year 2025", SAND2025-09228, Sandia National Laboratories (July
      2025), doi:10.2172/2585504.

## 7. Graded materials (research)
- [ ] **Constants graded through a layer** by a profile, as `xvel_profile`
      grades velocity, with the `distributions` module (so after the merge,
      section 1): for example Gamma_0, or P_R in an HVRB material. Deck keys
      parallel to the velocity profile's.
- [ ] **Physics before code:** which constants can vary on their own and
      which must move together (rho_0 with c_0, s_1; the product
      Gamma rho = Gamma_0 rho_0), and the state each cell starts in.
- [ ] **Verification:** a step in a constant reproduces a two-layer stack;
      a smooth gradient converges with the mesh; a literature search on
      shocks in graded (functionally graded) materials for comparison
      cases.
- [ ] The goal: take bitwhiz from a teaching tool into current research on
      shocks in graded materials, and publish there.

## 8. Development and performance
- [ ] **Performance budget:** time a fixed set of decks (cycles per second,
      1 and 4 threads) before and after each material-model change, and
      keep the numbers in the commit message. A change that slows the
      default Mie-Grüneisen path needs a reason.
- [x] **Bitmaps written a row at a time** (Nov 3): `bmpmaker` packed
      each row and its padding, one write per row instead of per pixel.
      Every bitmap byte for byte the same (103 pictures, debug and
      release); the class run 1.5-1.8 s to 1.17 s, `plots_only` 1.40 s
      to 1.06 s (release, 2-core Linux).
- [ ] **Pictures still cost more than the physics:** the class run's
      time loop is 0.29 s of its 1.17 s. The colormaps search the table
      by bisection for every subsample of every pixel (`cmap_viridis`,
      38 % of the profile, then `draw_tx`, 22 %); a table lookup would be
      faster but may move a color by one level, so the picture tests'
      expected values would change on purpose.
- [x] **The screen, for an impatient reader** (Nov 3): 250 lines down
      to 132 for the class deck. The resolved deck goes to
      `<title>.resolved` (not `.deck`, so `input/*.deck`, the tests and
      the nanoHUB picker never take it for a deck; `plots_only` keeps
      the run's), and section 2 names it; deck errors print under
      section 2's heading; one rule between sections; section 8 lists
      the files written with their sizes (the history file's frames
      too); times and wall time per cycle as plain numbers; the command
      line is read before the banner, so a usage error prints alone.
      Every heartbeat, tracer row, history frame and picture the same.
- [x] **nanoHUB, with 1.2.0** (published Nov 4): `<title>.resolved`
      among the notebook's downloads (Files, Deck), the run log read
      there at about 130 lines, and `steepening_hump.deck` in the picker
      with its movie.
- [x] **nanoHUB: the movie as a movie** (1.2.0, published Nov 4): after
      a run or redraw with `<title>.mv_p_*.bmp`, the notebook encodes
      them with ffmpeg (nanoHUB's has libx264: `-framerate 7
      -pattern_type glob -c:v libx264 -pix_fmt yuv420p -crf 20`,
      input/README.md section 9b), shows `<title>.mv_p.mp4` on the page
      in an ipywidgets player (`ipywidgets.Video`; a `<video>` tag on
      older ipywidgets), lists the .mp4 under Files (Movie) and not the
      frames, and deletes them once the movie is written (kept if the
      encode fails). steepening_hump's 25 frames, 35 MB of bitmaps, make
      a 66 KB movie; the class deck's 35, about 100 KB.
- [ ] **The temperature's cost** (found Nov 4): carrying T (`eos =
      mie_gruneisen_t`) makes a cycle about 6 times as long (G1's deck,
      2,700 cells, release: 1,203 against 207 us). Per cell per cycle,
      three Pi evaluations and three exponentials (the Gauss points), one
      more for T, and a burning cell does it twice (its cold step before
      the pressure, then temp_update's of zero length). Profile first;
      then, e.g., the growth factors from one exponential, the zero-length
      step skipped, a burnt-out cell's (lam = 1) cold curve not carried at
      all (nothing uses it). Bit for bit where possible; where not, the
      test values stay within T1-T5.
- [ ] **History file size:** 12.3 MB for the class deck, 123 MB at 10
      times its resolution (plot_dt = 0.005 us, 1001 frames). Section 8
      now reports it at the end (Nov 3); still to do: say it at the
      start, or warn above some size, before a student fills a nanoHUB
      quota.
- [x] **`make runs`** (Nov 3): every deck in `input/` (release build)
      into `runs/<deck>/` with its screen and files, one line per deck;
      `make tidy` removes `runs/`. About 10 s, 240 MB for ten decks.
- [ ] **Test-time budget:** `make test` stays a few minutes (about 4.5
      on 2 cores, Nov 3; 2.8 after the deck tests' change below; over 10
      would be too long). A new model
      brings unit tests and one or two short decks, not long runs.
- [ ] **Measure the order of accuracy:** a refinement study on a smooth
      problem (a small-amplitude sine wave, or a gentle ramp before the
      shock forms) at 4 or 5 resolutions, AV and RS order 1 and 2. Expect an
      L1 slope near 2 for RS order 2 and near 1 for order 1; L-infinity
      lower for order 2, where Van Leer clips the slopes at extrema. Keep it
      as a test, and use it with the ramp verification for 1.1.0.
- [ ] **The impact plane: Noh wall heating, or more.** W. F. Noh, "Errors
      for calculations of strong shocks using an artificial viscosity and
      an artificial heat flux," J. Comput. Phys. 72, 78-120 (1987): where
      an AV shock forms (a wall, an impact plane) the first cells take too
      much entropy as it starts, and in a Lagrangian code without heat
      conduction they keep it: T (and a density dip) wrong for the rest of
      the run, P right (W. J. Rider revisited it, J. Comput. Phys., 2000).
      TK shows it in G1 at 2.00 km/s, t = 1.0 us, against plateaus of 383 K
      (Al) and 736 K (Material X): the Al cells next to the impact plane
      +25 to +47 K (wall heating), but the last Al cell -19 K and the first
      Material X cell -173 K, which pure wall heating does not do (the
      momentum-weighted impact face splitting the first step's energy?).
      The `impact` tracer reports that last Al cell. Study: mesh (does it
      stay a few cells wide?), AV against RS, BL and BQ, and Noh's
      artificial heat flux as a possible cure.
- [ ] **AV energy at a free surface:** with AV, the energy error jumps
      when a shock reaches a free surface (ramp_linear: -6.8e-4 at 25
      zones/mm, first order, -4.3e-5 at 400), and is flat otherwise; RS
      conserves energy to round-off. Find which term does it (the
      free-surface face, q in the last cell) and whether it can be made
      conservative.
- [ ] **Acoustic verification as a test:** the four profile decks at 1e-4
      of their amplitude against exact linear acoustics (invariants
      p +/- Z u, impedance matching at the contact, p = 0 at the free
      surfaces) matched in L1 to 0.01-0.5 % with AV and RS2 at 200
      zones/mm (Nov 1, 2026). Keep it as a test; it also measures the
      order of accuracy on smooth parts of the solution.
- [ ] **Faster deck tests:** every clean deck ran three times (the run and
      the resolved-deck round trip); since Nov 3 twice, the round trip
      using the `<title>.resolved` the first run wrote (deck tests 160 s
      to 105 s on 2 cores), each in its own scratch folder. The second run
      could be a reading check without a full run: about 30 s more.

## Ideas (further out)
- **Values and units on every plot:** the axes' ends (xmin, xmax, ymin,
  ymax) written on the t-x diagrams, tracer plots and movie frames, the
  bitmaps kept at their size and the plot area shrunk to make room.
  - [x] Tracer plots and movie frames (Nov 3): the box's left, right and
    bottom sides moved in (100, 60, 70 pixels; the top and the title as
    before), the four ends printed in 12-pixel figures (`axis_text`,
    module strokes), each axis rounded out to clean ends first
    (`nice_ends`: two significant figures of the span), in bitwhiz's own
    units, no unit or axis name yet.
  - [x] The t-x diagrams (Nov 3): the box's left, right and bottom sides
    moved in (100, 60, 105 pixels), x and t rounded out to clean ends and
    printed as on the tracer plots, the color bar labeled with the
    window's ends (3 significant figures; the window itself not rounded,
    decided Nov 3).
  - [ ] Axis names and units, with the unit chosen to fit (decided Nov 3:
    with the labels, not before, so no scaled number appears without its
    unit). Lengths in the unit that keeps them under 1000 without
    exponents (Angstrom, nm, um, mm, cm, m, km), anything beyond that
    flagged and not plotted; pressure in GPa (or Pa with a prefix). The
    stroke font needs lower case for units, and mu.
- **PNG pictures** (distant future): bitmaps can not be truly see-through
  (a 32-bit BMP has alpha, but most viewers ignore it), so a "glass" look,
  or any picture laid over something else, needs PNG: zlib-deflated rows
  and CRCs (or stored, uncompressed blocks: simple, but as large as the
  BMPs). Also about 10 times smaller files.
- **Z-machine ramp drive by inverse problem:** fit a velocity profile's
  parameters (sinh-arcsinh, say) so the drive at an interface matches a
  measured ramp-wave drive.
- **Bayesian calibration** of equation-of-state parameters (C0, S1, G0) from
  velocity traces: thousands of fast, deterministic runs.
- **1D cylindrical and spherical geometry:** one exponent (alpha = 1, 2, 3)
  in cell volumes and face areas; the same database. Opens Sedov, Guderley
  and Noh in all three geometries.
- **2D:** a separate fork (`bitwhiz2d`, RZ Lagrangian with ALE), with 1D
  bitwhiz kept as its reference solution.

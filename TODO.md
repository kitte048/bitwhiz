# TODO

Plans and open questions for bitwhiz. Items move out of this file when they
are done (the commit that does one says so). Release steps themselves are in
README.md, "Releases and nanoHUB".

Started Oct 23, 2026, the day bitwhiz 1.0.2 was approved for publication on
nanoHUB. Reordered Oct 31, 2026, after 1.0.3, from a brainstorm: one branch
again, the nanoHUB tool, gold-standard data, movies, HVRB, graded materials.
Reordered again Nov 2, 2026, after 1.1.0 (velocity profiles and the new
nanoHUB notebook, published) and the gold-standard data and its reader.

## Priorities
1. Material models: the architecture, design note first. A default model
   with add-ons (burn, rate law), and constants that can vary cell by cell;
   Mie-Grüneisen kept as the default (section 5). Its first case:
   Mie-Grüneisen with temperature, a separate model (section 6), so G1's
   temperatures can be compared too (talk through the T calculation first).
2. HVRB, checked against the gold-standard reactive data (G2-G5); then the
   burn models from the 2025 survey (section 6).
3. Graded materials: constants (Gamma_0, P_R, ...) graded through a layer,
   as velocity is now. Research, toward publication (section 7).
4. In the background, between releases: the nanoHUB tool (section 2) and
   the velocity profiles' next steps (section 1), the movie's (section 4).
5. Throughout: no bloat. Cost per cycle stays the same or improves, and
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
- [ ] **Movies in the notebook** (section 4): clear, list and show them.
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
- [ ] **G2-G5 (reactive), with HVRB** (section 6): decks for the class stack
      and the thick-flyer stack, compared with `hvrb/README.md`'s tolerances.
- [ ] Check that the data's HVRB inputs match the equation sheet bitwhiz
      will follow: the dataset's README cites `HVRB_Eqns_v3.tex`; the sheet
      is now at v8, published as `Class_Project/HVRB_Eqns_rev-0.pdf`.

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

- [ ] **The nanoHUB notebook:** clear `<title>.mv_*.bmp` with a run's other
      outputs before Run; a "Movie" kind in Files; and the movie shown as
      one thing, not up to 50 pictures: an MP4 from the frames with ffmpeg
      (nanoHUB has it, anaconda-7) or a slider over them.
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
- [ ] **Release 1.2.0** (MG+T), with the nanoHUB tool.
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
      `Class_Project/HVRB_Eqns_rev-0.pdf`; a frozen copy into `doc/`, as
      for the other sheets): reactant Mie-Grüneisen with the energy shift
      Q, ideal-gas products, density-temperature equilibrium, the HVRB rate
      (P_R, Z_R, M_R, X_R, P_I, tau_0). Checked against G2-G5 (section 3):
      run distance, the Pop plot, D_CJ = 7.500 km/s within 0.5 %, the mesh
      study. Then with a JWL products EOS.
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
- [ ] **nanoHUB:** list `<title>.resolved` among the notebook's
      downloads, and check that its run log reads well at 132 lines
      (with the next release); add `steepening_hump.deck` (shock
      formation, Nov 3) to the picker, with its movie.
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

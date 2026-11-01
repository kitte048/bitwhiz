# TODO

Plans and open questions for bitwhiz. Items move out of this file when they
are done (the commit that does one says so). Release steps themselves are in
README.md, "Releases and nanoHUB".

Started Oct 23, 2026, the day bitwhiz 1.0.2 was approved for publication on
nanoHUB. Reordered Oct 31, 2026, after 1.0.3, from a brainstorm: one branch
again, the nanoHUB tool, gold-standard data, movies, HVRB, graded materials.

## Priorities
1. Velocity profiles: finish branch `distributions` and merge it into
   `shock` (1.1.0), so there is one branch to maintain again.
2. The nanoHUB tool: a smoother, harder-to-break user experience.
3. Verification: the gold-standard inert data (G1) in the repository and
   compared, before any change to the material models.
4. Movies: a third kind of output, profiles along x at their own interval.
5. Material models: the architecture, design note first. A default model
   with add-ons (burn, rate law), and constants that can vary cell by cell;
   Mie-Grüneisen kept as the default.
6. HVRB, checked against the gold-standard reactive data (G2-G5); then the
   burn models from the 2025 survey.
7. Graded materials: constants (Gamma_0, P_R, ...) graded through a layer,
   as velocity is now. Research, toward publication.
8. Throughout: no bloat. Cost per cycle stays the same or improves, and
   `make test` stays a few minutes.

## 1. Velocity profiles (branch `distributions`, toward 1.1.0)
Design and status: `doc/design/distributions.md` (on that branch).

- [ ] **Bring the branch up to date first:** `git merge shock` into
      `distributions` (8 commits behind on Oct 31: v1.0.3, the U6 decks,
      `plot_range`, the tests' report format), then `make test` and
      `make release`.
- [ ] **Ringing in the tracer data:** a sawtooth-like noise on the tracer
      velocities when the initial condition is a velocity profile. Find
      whether it comes from the method or from how the profile is put on
      the mesh: run one profile deck with AV, RS order 1 and RS order 2, at
      two or three mesh sizes, and see whether the noise changes with the
      method, scales with the cell size, or follows the cells' initial
      velocities (faces are set momentum-weighted from the cells).
- [ ] **Late launch at the free surface:** the t-x diagrams show the free
      surface sending something off late in the run (spalled or damaged
      material, debris?). Find out what it is (damage, density and pressure
      in the history file at those cells) and whether it is physical.
      Decide whether it holds up the merge or is recorded as known.
- [ ] Merge `distributions` into `shock` when the ringing and the late
      launch are understood and phase 1 is settled; release as 1.1.0, with
      the four example decks (`input/ramp_*.deck`,
      `input/pulse_split_normal.deck`) in the nanoHUB examples. Then delete
      `distributions` (here and on GitHub): `shock` is the one branch, and
      new work branches from it and comes back.
- [ ] Verification: a linear compression ramp against the shock formation
      time from characteristics (derive it first, acoustic limit).
- [ ] Phase 2: sampling, `dist_inv_cdf`, and random velocity draws per cell
      (ensembles for uncertainty quantification).
- [ ] Later distributions: gamma, Weibull, log-normal.

## 2. nanoHUB tool (after 1.0.3)
These change the tool's notebook (`bitwhiz.ipynb` in the nanoHUB clone) and
the export; the Fortran is unchanged. 1.0.3 brought App Mode, the deck
picker, the Plot history button and the VERSION file.

- [ ] **Bug: the deck picker offers only the class deck.** The notebook
      lists `$TOOLDIR/src/bitwhiz/input/*.deck`, then `$TOOLDIR/examples/`;
      1.0.3 has the four U6 decks in `input/`, yet only the class deck (the
      one in `examples/`) shows. Likely the installed tool
      (`/apps/bitwhiz/dev`) has no `src/`. Check from a notebook cell:
      `!ls -R /apps/bitwhiz/dev | head -40`. Fix it so it cannot come back:
      the export copies `input/*.deck` into the clone's `examples/`, and the
      notebook offers the decks from there.
- [ ] **More example decks** in the picker, each with a one-line label at
      the top of its comment box: the U6 decks, the velocity-profile decks
      (1.1.0), a spall deck, AV against RS, later an HVRB deck.
- [ ] **Old pictures outlive their run.** Run, then turn outputs down or
      change the deck and run again: the earlier run's files stay beside the
      new ones. Before each Run (not before Redraw pictures only), clear the
      run's outputs from its folder (pictures, tracer CSV, history,
      heartbeat), and show only the files this run wrote.
- [ ] **Say which run a picture is from.** With little text in the
      figures, an old picture passes for a new one. Put the deck title and
      the run's date and time with every picture: in the notebook, a
      caption above each; in the pictures themselves (`pics_mod`), only if
      the pixel tests are updated with it.
- [ ] **Pick one file and download it:** a dropdown of the files in the run
      folder (newest first, filtered by kind: pictures, tracer CSV,
      history, deck, heartbeat) and a Download button. It must stay usable
      with hundreds of files (the movie frames, section 4).
- [ ] **Upload your own deck:** an upload button (ipywidgets `FileUpload`)
      that loads a `.deck` file from the user's computer into the editor.
- [ ] **Download this run:** a link under the pictures to the run's folder,
      zipped (deck, pictures, tracer CSV, history file). Until then: Jupyter's
      file browser, `bitwhiz_runs/<title>/`, tick the files, Download.
- [ ] **Scripting example:** a cell showing that `bitwhiz` is on the path
      (`!bitwhiz my.deck`), and a short `%%bash` or Python sweep over
      `define u_fly` values.
- [ ] **Hardening:** try to break the notebook the way a new user would (an
      empty deck, a deck with no `title`, a title with spaces or slashes, a
      run stopped halfway, two runs started at once, Run All on a fresh
      session) and make each one end in a plain message, not a traceback.
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
- [ ] **Copyright holder** on the license line (Apache 2.0, "custom" on
      nanoHUB): David E. Kittell, or the Purdue Research Foundation? Ask OTC.
- [ ] **Export control:** a written determination from Purdue's export
      control office, now that the tool is public. KO, pyko and CAV_KO are
      precedents for public 1D teaching hydrocodes.
- [ ] **Description page:** check it on the live tool page once published
      (version 1.0.2, license, references 1-9, screenshots).
- [ ] **Tag v1.0.1** is in the nanoHUB clone but not here (v1.0, v1.0.2
      and v1.0.3 are in both). Find the commit it names and tag it here, or
      record why there is none.

## 3. Verification: the gold-standard data
Source: `Equation_Sheets/HVRB_rev-0/verification/` in the course folder
(20 files and a README; run plan in `../GOLD_STANDARD_DATASET.md`), from
DK's independent Eulerian code, Oct 30, 2026. The format is that of
`tests/verification/`, with more per tracer: DENS, TK (temperature), XRN3
(reaction progress, lambda); MJKG is written but empty. Its README, section
6, proposes how bitwhiz uses it.

- [ ] **Size first:** 35 MB in all (1.6 to 3.1 MB per file, a row every
      5 ns). Decide what goes into git: every file as delivered, a thinned
      copy (fewer rows, fewer columns), compressed, or a README that says
      where to get them. Files that are copied stay byte for byte as
      delivered, with a README for their provenance (reference code
      unnamed, as in `tests/verification/`; Material X parameters
      notional).
- [ ] **G1 now (inert):** five sweeps, 1.00 to 2.00 km/s, the class stack,
      eleven gauges in Material X with T and density, into
      `tests/verification/inert_gauges/`. A deck with tracers at the G1
      positions, and a comparison of derived quantities at 100 zones/mm
      with the README's tolerances: first-shock P and u at 1 mm within
      0.1 %; arrivals before the Ta reshock and PDV arrival within 5 ns;
      total energy drift within 0.01 % before outflow. A comparison, not a
      regression test: the codes differ (Eulerian against Lagrangian, a
      P >= 0 floor against spall). Temperature waits for bitwhiz to compute
      T (section 6).
- [ ] **One reader:** a small Python reader for this format, serving both
      sets, with the derived-quantity definitions of the README's section 4
      used unchanged.
- [ ] **G2-G5 (reactive), with HVRB** (section 6): into
      `tests/verification/hvrb/`, with decks for the class stack and the
      thick-flyer stack.
- [ ] Check that the data's HVRB inputs match the equation sheet bitwhiz
      will follow: the dataset's README cites `HVRB_Eqns_v3.tex`; the sheet
      is now at v8, published as `Class_Project/HVRB_Eqns_rev-0.pdf`.

## 4. Movies: profiles along x
- [ ] **A third kind of output:** plot-over-line frames, a quantity against
      x over the whole stack at one time; P and u first. One numbered
      picture per frame, made into a movie in the notebook (an animation,
      or an MP4 or GIF if nanoHUB has ffmpeg).
- [ ] **Its own interval, coarser than the t-x snapshots** (`plot_dt`,
      `plot_every`). New deck keys with descriptive names, settled before
      any code, unmistakable beside `plot_dt`, `plot_every` and `tracer_dt`
      (to propose: e.g. `movie_frame_dt`, `movie_fields = P u`); in
      `input/README.md` and the key reference at the end of the class deck.
- [ ] **Design question first:** the history file already holds x, u and P
      on the whole mesh at every snapshot. Can the frames be drawn from it
      (every Nth snapshot, also with `plots_only = yes`), so a movie needs
      no new output during the run? If the frame interval must then be a
      multiple of `plot_dt`, the deck reader says so.
- [ ] Axes fixed across frames (x over the whole stack in the lab frame;
      the value range from the run, by the `plot_range` rule), each frame
      titled with its time and the deck title.
- [ ] Tests: the frame count and names, and pixels at known places, as for
      the t-x diagrams.

## 5. Material models: the architecture
- [ ] **A default model, and add-ons.** Each material has one equation of
      state, Mie-Grüneisen unless a key in `Begin Material` / `End
      Material` changes it (name to settle: `eos`, `swap_eos` or
      `change_eos`), and optional add-ons on top of it: a burn
      (`add_burn =`) and its rate law (`add_rate_law =`), later strength.
      Without these keys, the material is Mie-Grüneisen, read and computed
      exactly as now, so every existing deck gives the same results, bit
      for bit. With them, the parser reads that model's own parameter keys,
      and the cell update calls that model's driver.
- [ ] Keep the choice out of the inner loop: dispatch once per layer (or
      per material), not per cell per cycle, so the default runs no slower.
- [ ] **Constants per cell.** Plan the database so that any material
      constant can vary from cell to cell (section 7), while a material
      with uniform constants costs no more than now.
- [ ] Extra state per model (temperature, plastic strain, reaction
      progress) as optional database rows, allocated only when a deck uses
      that model, and written to the history file when present.
- [ ] Write the design note first (`doc/design/materials.md`), as for the
      velocity profiles: deck keys, database rows, the driver interface,
      per-cell constants, and the tests that keep old decks unchanged.

## 6. Material models: new ones
Each one checked against the commercial reference code on a small set of
decks.

- [ ] **Mie-Grüneisen with temperature:** adds T as a variable (a specific
      heat, and a reference temperature). HVRB needs it: its closure puts
      reactant and products at one density and one temperature.
- [ ] **Strength:** elastic-perfectly-plastic, von Mises yield, with thermal
      softening (needs T from the model above): deviatoric stress and
      plasticity.
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
- [ ] **Test-time budget:** `make test` stays a few minutes. A new model
      brings unit tests and one or two short decks, not long runs.
- [ ] **Measure the order of accuracy:** a refinement study on a smooth
      problem (a small-amplitude sine wave, or a gentle ramp before the
      shock forms) at 4 or 5 resolutions, AV and RS order 1 and 2. Expect an
      L1 slope near 2 for RS order 2 and near 1 for order 1; L-infinity
      lower for order 2, where Van Leer clips the slopes at extrema. Keep it
      as a test, and use it with the ramp verification for 1.1.0.
- [ ] **Faster deck tests:** every deck in `input/` runs three times (the run
      and the resolved-deck round trip). Make the round trip a reading check
      (read the deck back, compare the resolved statements) without a full
      run: about 30 s off `make test`.

## Ideas (further out)
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

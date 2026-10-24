# TODO

Plans and open questions for bitwhiz. Items move out of this file when they
are done (the commit that does one says so). Release steps themselves are in
README.md, "Releases and nanoHUB".

Started Oct 23, 2026, the day bitwhiz 1.0.2 was approved for publication on
nanoHUB.

## Priorities
1. The nanoHUB tool: a smoother, harder-to-break user experience.
2. Velocity profiles: the ringing in tracer data, and what the free surface
   launches late in the run.
3. Material models: room in the code for more than one equation of state,
   with Mie-Grüneisen kept as the default.
4. New material models, each checked against the commercial reference code.
5. Throughout: no bloat. Cost per cycle stays the same or improves, and
   `make test` stays a few minutes.

## 1. nanoHUB tool (next release: 1.0.3)
These change the tool's notebook (`bitwhiz.ipynb` in the nanoHUB clone) and
the export; the Fortran is unchanged.

- [ ] **History-plot cell:** when no run has made a history file yet, print
      "No run yet: press Run above, then run this cell" instead of a
      FileNotFoundError (it happens on Run All, before Run is pressed).
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
- [ ] **Version on nanoHUB:** the banner says `version: unknown` there (the
      install folder is not a git checkout). Have `export_nanohub.sh` write a
      `VERSION` file with the tag, and `make_build_info.sh` read it when
      `git describe` finds nothing.
- [ ] **README release steps:** name the status page's "Wait! I've made more
      changes" link, which tells nanoHUB that new code is ready to install
      (we could not find it on Oct 23).
- [ ] **num_threads note** in the example decks' comments: 1 for class
      problems; 4 to 8 for large meshes on nanoHUB (24 shared processors, no
      CPU limit).

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

## 2. Velocity profiles (branch `distributions`, toward 1.1.0)
Design and status: `doc/design/distributions.md`.

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
- [ ] Merge `distributions` into `shock` when the two items above and phase
      1 are settled; release as 1.1.0, with the four example decks
      (`input/ramp_*.deck`, `input/pulse_split_normal.deck`) in the nanoHUB
      examples.
- [ ] Verification: a linear compression ramp against the shock formation
      time from characteristics (derive it first, acoustic limit).
- [ ] Phase 2: sampling, `dist_inv_cdf`, and random velocity draws per cell
      (ensembles for uncertainty quantification).
- [ ] Later distributions: gamma, Weibull, log-normal.

## 3. Material models: the architecture
- [ ] **A choice of model per material.** A new key in `Begin Material` /
      `End Material` names the model (name to settle: `eos`, `swap_eos` or
      `change_eos`). Without it, the material is Mie-Grüneisen, read and
      computed exactly as now, so every existing deck gives the same
      results, bit for bit. With it, the parser reads that model's own
      parameter keys, and the cell update calls that model's driver.
- [ ] Keep the choice out of the inner loop: dispatch once per layer (or
      per material), not per cell per cycle, so the default runs no slower.
- [ ] Extra state per model (temperature, plastic strain, reaction
      progress) as optional database rows, allocated only when a deck uses
      that model, and written to the history file when present.
- [ ] Write the design note first (`doc/design/materials.md`), as for the
      velocity profiles: deck keys, database rows, the driver interface, and
      the tests that keep old decks unchanged.

## 4. Material models: new ones
Each one checked against the commercial reference code on a small set of
decks.

- [ ] **Mie-Grüneisen with temperature:** adds T as a variable (a specific
      heat, and a reference temperature).
- [ ] **Strength:** elastic-perfectly-plastic, von Mises yield, with thermal
      softening (needs T from the model above): deviatoric stress and
      plasticity.
- [ ] **History-variable reactive burn**, with an ideal-gas products EOS,
      then with a JWL products EOS.
- [ ] **The burn models from the 2025 survey:** FlashFire,
      StochasticIgnite and ThermalCascade, from D. E. Kittell et al., "A
      Short Survey of Current Reactive Burn Model Capabilities as of
      Mid-Year 2025", SAND2025-09228, Sandia National Laboratories (July
      2025), doi:10.2172/2585504.

## 5. Development and performance
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

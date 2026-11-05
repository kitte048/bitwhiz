# input
This folder contains the input decks for bitwhiz, and this file is the deck
syntax specification (deck_version 1). The parser is written to this page; if
the two ever disagree, fix one of them on purpose.

**Status:** implemented by `src/modules/deck_mod.f95` (module `deck`).
`tests/run_deck_tests.sh` checks it against about 100 test decks.

---

## 1. Running a deck
```
./bin/bitwhiz input/<name>.deck
```
The command line takes only the deck name. Everything about a run (threads,
solver, materials, geometry, tracers, output) is in the deck, so the deck is the
complete record of what was run. The run writes, in the folder it starts
from: `<title>.resolved` (the deck with every default filled in, section 10),
`<title>.heartbeat`, and, when the deck asks for them, the tracer file
(section 8), the history file (section 9) and the pictures (section 9b).
`make tidy` removes them all.

---

## 2. The shape of a deck
```
Begin bitwhiz
 deck_version = 1
 define u_fly = 2.00

 Begin Run       ... End Run          # what to run: time, threads
 Begin Output    ... End Output       # what to write: tracers, snapshots
 Begin Solver    ... End Solver       # method and its knobs
 Begin Material Ta ... End Material   # one block per material
 Begin Stack                          # geometry, left to right
  Begin Layer ... End Layer           # one block per layer
 End Stack
End bitwhiz

Anything after "End bitwhiz" is ignored: free space for notes.
```
- Blocks at the top level may come in any order. Layers are read in order,
  left to right.
- `Material` blocks carry a name on the `Begin` line: `Begin Material Ta`.
- Every `End` must name the block it closes (`End Layer`, not just `End`).
  `End Material` may also repeat the material's name (`End Material Ta`).

---

## 3. Lines
- One `key = value` per line. Spaces around `=` don't matter.
- `#` starts a comment, on its own line or at the end of one.
- Blank lines are fine. There are no continuation lines.
- Lines are limited to 200 characters (`nline` in bits).
- Tabs count as spaces, and Windows line endings (`\r`) are stripped.

---

## 4. Values
| Type | Rule | Examples |
|---|---|---|
| number | optional sign, digits, optional decimal point, optional exponent with `e` or `E` | `35`, `35.`, `-0.10`, `+3.1415e9`, `12E+10` |
| integer | digits only | `945` |
| name | starts with a letter; then letters, digits or `_`; at most 32 characters | `MatX`, `pdv`, `Al_back` |
| define | a name made with `define`, used wherever a number goes | `xvel = u_fly` |
| location | see section 7 | `MatX:PMMA`, `MatX@0.25`, `12.345` |

Rejected numbers include `+-99`, `23..67`, `23.1.5e5`, `77.5e+-5`,
`2.22e11e11`, `2323cv5`, `"cat"`, and `1.0d0` (Fortran `d` exponents are not
accepted, to keep one spelling).

`define name = number` is allowed at the top level only, and must come before
its first use. A define cannot be redefined.

---

## 5. Upper and lower case
**Decision: nothing in a deck is case sensitive.** Keys, block names, material
and layer names, tracer names and locations all match regardless of case.
`R0 = 16.65` and `r0 = 16.65` are the same line, and `Al:MatX`, `al:matx`
and `AL:MATX` are the same interface.

Names are **displayed** exactly as first written (`MatX` stays `MatX` in the
log and in output headers). Because matching ignores case, two names that
differ only by case (`MatX` and `matx`) are a duplicate and an error.

Why: Fortran itself ignores case, the deck keys already do, and a rule where
`MatX` and `Matx` are two different layers only ever produces confusing
errors. Making everything insensitive gives one rule to remember.

---

## 6. Blocks and keys
Units: mm, us, g/cm^3, km/s, GPa. Nothing is converted inside the code.

### Top level
| Key | Type | Default | Notes |
|---|---|---|---|
| `deck_version` | integer | required | must be `1` |
| `define` | name = number | | see section 4 |

### `Run`
| Key | Type | Default | Notes |
|---|---|---|---|
| `title` | name | deck file name | names the run's files, e.g. `<title>.heartbeat` |
| `t_end` | number, us | required | termination time |
| `cycle_max` | integer | 1000000 | backstop against a stalled time step |
| `num_threads` | integer | 1 | `0` means all processors; capped at the processor count |
| `omp_min_zones` | integer | 2000 | a mesh with fewer cells runs the time loop on one thread, whatever `num_threads` says (threads cost more than they save on small 1-D meshes); `0` = always use the threads |
| `plots_only` | `yes` or `no` | `no` | `yes`: no run; only re-draw the pictures from the files an earlier run of this deck left (section 9b) |

### `Output`
**Nothing given means nothing is written.** The only files every run writes are
the heartbeat (`<title>.heartbeat`, one line per cycle) and, later, the run log.
A deck with tracers also writes the tracer file, `<title>.tracers.csv`
(section 8), and a deck with snapshots the history file, `<title>.hist`
(section 9), and every run that finishes draws its pictures (section 9b). The
whole block may be left out.

| Key | Type | Default | Notes |
|---|---|---|---|
| `tracer` | name location | none | repeatable; see section 8 |
| `tracer_dt` | number, us | 0 (every cycle) | time between rows of the tracer file |
| `plot_every` | integer | 0 (off) | write a snapshot (a frame of the history file, section 9) every N cycles |
| `plot_dt` | number, us | 0 (off) | also write a snapshot every plot_dt |
| `movie_frames` | integer, 2 to 50 | 0 (off) | the pressure movie: P against x, one frame from the snapshot nearest each of N times spread evenly over the run (needs snapshots; section 9b) |
| `colormap` | name | `viridis` | for bitmap pictures: `grayscale`, `viridis`, `plasma`, `inferno`, `blackbody`, `kindlmann`, `extendedkindlmann`, `smoothcoolwarm`, `bentcoolwarm` |
| `plot_range` | `robust` or `full` | `robust` | each t-x diagram's color range: `full` is the data's min to its max; `robust` the min to the top the run held for 50 cycles, when the max is a spike above that (section 9b) |
| `plot_u_lo`, `plot_u_hi` | number, 0 to 1 | 0, 1 | the u t-x diagram's color window, as fractions of its color range (lo below hi; section 9b) |
| `plot_p_lo`, `plot_p_hi` | number, 0 to 1 | 0, 1 | the same for the P t-x diagram |

When snapshots are on, a snapshot is written whenever either `plot_every` or
`plot_dt` says so, and the first and last cycles are always included.

### `Solver`
| Key | Type | Default | Notes |
|---|---|---|---|
| `method` | `AV` or `RS` | `AV` | `AV`: artificial viscosity. `RS`: Godunov's method with the acoustic Riemann solver of U7 (no `q`; conserves mass, momentum and energy to round-off) |
| `BL` | number | 0.1 | linear viscosity coefficient (AV only) |
| `BQ` | number | 2.0 | quadratic viscosity coefficient (AV only) |
| `CFL` | number | 0.6 | Courant safety factor, 0 < CFL <= 1 |
| `order` | `1` or `2` | `2` | RS only: `2` is second order (MUSCL-Hancock with a Van Leer limiter), `1` is first-order Godunov (the project's Option B). AV ignores it |

The artificial viscosity is the equation sheet's, with its default
coefficients: q = BL ρ c |Δu| + BQ ρ (Δu)², applied only while the cell is
being compressed (Δu > 0 and ρ increasing), and q = 0 otherwise.

**A free surface with AV** jumps about 6 % above its true velocity when a
shock reaches it, for about 2.5 cells' transit of the shock (16 ns at 25
zones/mm, 1 ns at 400), on every mesh, then settles on the right value: read
the plateau, not the peak (RS at order 2: 0.4 %). The end cell of a burning
material blown off a free surface can show a temperature far below 0 K (the
sheet's cell-centered kinetic energy, in one cell); the log's T range
includes it. Both are measured, against mesh and an exact answer, in
`doc/design/av_study.md`.

### `Material <name>`
Mie-Gruneisen, referenced to the principal Hugoniot (project rev-0, Eq. 4).
| Key | Units | Default |
|---|---|---|
| `eos` | `mie_gruneisen` or `mie_gruneisen_t` | `mie_gruneisen` |
| `R0` | g/cm^3 | required |
| `C0` | km/s | required |
| `S1` | - | required |
| `S2` | - | 0.0 |
| `G0` | - | required |
| `spall_strength` | GPa | 0.01 |
| `CV` | J/(g K) | required with `mie_gruneisen_t`; not allowed without it |
| `T0` | K | required with `mie_gruneisen_t`; not allowed without it |
| `burn` | `hvrb` | none (inert) |
| `PR`, `ZR`, `MR`, `XR`, `PI`, `TAU0` | GPa, -, -, -, GPa, us | each required with `burn = hvrb`; not allowed without it |
| `products` | `ideal_gas` | none: required with `burn` (no default) |
| `GAMMA`, `Q` | -, kJ/g (= MJ/kg) | each required with `products = ideal_gas`; not allowed without it |

A material that no layer uses gets a warning, not an error.

**Temperature (`eos = mie_gruneisen_t`).** The same Mie-Gruneisen, the same
pressure and sound speed to the last bit, plus each cell's temperature:

    T = T0 exp(G0 eta) + (e - e_c(V))/C_V,      eta = 1 - R0 V

with `CV` the constant specific heat (J/(g K), as the literature gives it) and
`T0` the temperature at R0 and e = 0, the state every cell starts in. e_c is
the cold curve, the isentrope through (V0, e = 0); each cell carries its own,
from step to step (`doc/design/materials.md` has the method and its checks).
T does not change P in this model: it is written to the tracer file (`TK`,
section 8) and the history file (`TK`, section 9), and the run log gives the
T range and the hottest cell over the run, among intact cells. (A broken
cell's T is written as computed, but means nothing: its pressure is floored
at 0, so opening it does no work, while its cold energy keeps following its
volume, and its T falls, below 0 K if it opens far.) The resolved deck writes every
material's `eos`, so the model is always on record. Example, the
gold-standard data's values for every material:

    eos = mie_gruneisen_t
    CV  = 1.1633418          # J/(g K): 1.35e11 erg/(g eV) / 11604.5 K/eV
    T0  = 298.0              # K

**Burning (`burn = hvrb`).** The History Variable Reactive Burn of the HVRB
equation sheet (`doc/HVRB_Eqns_v8`): the material above is the unreacted solid
(so it needs `eos = mie_gruneisen_t`), the `products` are the reaction's gas,
and each cell carries its extent of reaction, lam, from 0 (unreacted) to 1
(burnt out). The rate law, a pressure history:

    Phi = (1/TAU0) ((P - PI)/PR)^ZR    while P > PI (else 0)
    phi = integral of Phi dt,  lam = 1 - (1 - phi^MR/XR)^XR,  to lam = 1

and the mixture at one density and one temperature (one `CV` for both
phases), `P = (1 - lam) P_solid + lam P_gas`, with the ideal-gas products
`P_gas = (GAMMA - 1) rho CV T` and `Q` the heat of reaction (`products =
ideal_gas`; HVRB is usually paired with a JWL or tabular products EOS, and
the ideal gas is the first one here: the deck says which, as `products` has
no default). `ZR = 0` is a burn on a clock: above PI, `Phi = 1/TAU0` and PR
has no effect; with `MR = 1` it is a d^n law, lam = 1 - (1 - t/t_b)^(3/n) with
`XR = 3/n` and burn-out at `t_b = XR TAU0` (the D^2 law: `XR = 1.5`). A cell
that has started to burn holds no tension (P >= 0: the gas fills the cracks of
a reacting solid) and never spalls; a cell at lam = 0 is the inert material,
bit for bit. Burning changes lam at fixed rho and e, so energy is conserved
(the heartbeat's energy error is the check). The tracer file gets `XRN`
(lam) per tracer, the history file an `XRN` variable, and the run log the
first cell to react and the cells burnt out. Both methods: with RS at order
2 the reaction is also a source in the predictor's pressure (`doc/design/
materials.md`, phase 3).

**Resolution, with AV.** AV burns inside its smeared shock, and on a coarse
mesh that makes a weak detonation: the front runs fast, and once an overdrive
has decayed a plateau below P_CJ opens behind the spike and widens. It goes
away as the mesh refines. For Material X (a reaction zone of about 0.14 mm):
D is 3 % fast at 25 zones/mm, 0.4 % at 50, 0.2 % at 100 and within 0.03 % from
200 (about 28 cells across the reaction zone); the class deck, at 35, runs
1.6 % ahead of RS from about 0.85 us. RS at order 2 gets D right from 25
zones/mm. Measured by `tests/verification/study_av.py` (`doc/design/
av_study.md`).
Example, the HVRB sheet's Material X set (`doc/design/materials.md`, phase 3):

    eos = mie_gruneisen_t
    CV  = 1.1633418          # J/(g K), both phases
    T0  = 298.0
    burn = hvrb
    PR = 7.0                 # GPa
    ZR = 3.0
    MR = 1.5
    XR = 2.5
    PI = 1.0                 # GPa
    TAU0 = 1.0               # us
    products = ideal_gas
    GAMMA = 2.60
    Q = 4.8828               # kJ/g

**Expansion and spall (bitwhiz's own rules).** U_S-u_p data exist only in
compression. For expansion (V > V0) bitwhiz continues the Hugoniot form with a
cubic in rho - R0, matched to it through the third derivative at V0, so
pressure and sound speed stay smooth through the initial state; nothing to set.
`spall_strength` is how much tension the material holds, as a positive number
in GPa: a cell breaks when its pressure falls below `-spall_strength`, and from
then on it can not hold tension again (its pressure is floored at 0), though
it can still be compressed and shocked. Give the **dynamic** spall strength
(e.g. from a PDV pullback), not the quasi-static ultimate tensile strength,
which is several times smaller (aluminum: about 0.3 GPa UTS, 1-1.5 GPa spall).
`spall_strength = 0` breaks a cell at the first sign of tension, the project's
P >= 0 rule; the default, 0.01 GPa, is that rule with a little room.

### `Stack`
| Key | Type | Default | Notes |
|---|---|---|---|
| `resolution` | number, zones/mm | none | applies to every layer unless the layer overrides it |
| `origin` | named location | | x = 0 at this location (section 7) |
| `x_left` | number, mm | 0.0 | x of the stack's left face |

`origin` and `x_left` may not both be given. With neither, x = 0 is the left
face of the first layer.

### `Layer` (inside `Stack`, listed left to right; all layers are in contact)
| Key | Type | Default | Notes |
|---|---|---|---|
| `material` | name | required | a `Material` block's name |
| `name` | name | the material's name | **required** if that material is used by more than one layer |
| `width` | number, mm | required | |
| `xvel` | number or define, km/s | 0.0 | initial velocity, + is to the right; with `xvel_profile`, the layer's mean velocity |
| `xvel_profile` | a distribution's name, then its parameters (numbers or defines) | uniform | the shape of the initial velocity across the layer; see below |
| `xvel_amplitude` | number or define, km/s | `xvel` | how strongly the shape varies the velocity; only with an `xvel_profile` |
| `zones` | integer | | zone count for this layer |
| `resolution` | number, zones/mm | the Stack's | overrides the Stack value |

Each layer must end up with a zone count from `zones`, its own `resolution`, or
the Stack's `resolution`. If `zones` and a `resolution` both apply, `zones` wins
and the log says so. If `width * resolution` is not a whole number, it is
rounded and the log warns (a silently uneven mesh is worse than a warning).
The width is always kept exact, so interfaces stay where the deck puts them;
rounding only changes that layer's dx = width / zones slightly.

**Velocity profiles.** By default a layer starts at one velocity, `xvel`.
With `xvel_profile` the velocity varies across the layer with the shape of a
probability density f, and `xvel_amplitude` (du) sets how strongly:

    u(xi) = xvel + du * ( f(xi) - 1 ),    xi = 0 at the layer's left face, 1 at its right

Because f integrates to 1, the layer's momentum is still R0 × width × xvel, for
any shape and any du: `xvel` is the layer's mean velocity. Without
`xvel_amplitude`, du = `xvel`, so u = xvel × f. With `xvel = 0` and an
amplitude, a layer at rest on average can still stretch or squeeze. The
distributions (positions and spreads in layer widths; module
`distributions`, `src/modules/dist_mod.f95`):

| `xvel_profile =` | Parameters | Shape |
|---|---|---|
| `uniform` | none | flat (the same as no profile) |
| `linear s` | slope s, −1 to 1 | f = 1 + s(2 xi − 1): s > 0 faster at the right, s < 0 at the left |
| `beta a b` | a, b > 0 | on [0, 1]; a < b leans left, a > b right, a = b symmetric |
| `normal mu sigma` | center, spread > 0 | the Gaussian |
| `split_normal m sl sr` | peak, left spread, right spread | a normal on each side of the peak; leans toward the wider side |
| `sinh_arcsinh loc scale eps delta` | center, spread, skewness, tail weight | eps = 0 symmetric, either sign leans; delta = 1 normal-like, below 1 heavier tails |
| `cauchy x0 gamma` | center, spread | heavy tails |

Each is truncated to the layer, xi from 0 to 1, and renormalized there; a
profile that puts almost nothing on the layer (less than 1e-12, say a normal
centered far outside it) is an error. Each cell starts at the profile's mean
over the cell, so the momentum is exact to round-off, and the setup checks
(section 6 of a run) confirm it on every run. Examples:

    xvel           = 2.0
    xvel_profile   = beta 2 5         # faster near the left face
    xvel_profile   = linear 1.0       # with xvel = 0 and xvel_amplitude = 0.2:
                                      # -0.2 km/s at the left face, +0.2 at the right

The screen's section 5 gives each profile's velocity range. The design, and
what is planned next (random draws), is in `doc/design/distributions.md`.

**Example decks** in this folder, each a layer A (aluminum, 4 mm) with a
velocity profile against a layer B (PMMA, 10 mm) at rest, with tracers at the
interface (`drive`), halfway through B and at B's free surface:

| Deck | Profile | What B feels |
|---|---|---|
| `ramp_linear.deck` | `linear -1`: 2.0 km/s at A's back, 0 at the contact | a linear ramp, about 0.5 us |
| `ramp_beta.deck` | `beta 1 3`: 3.0 km/s at the back, 0 with zero slope at the contact | a ramp with a soft foot and a steep top |
| `ramp_sinh_arcsinh.deck` | `sinh_arcsinh -0.1 0.25 1.0 1.0`: a long tail toward the contact | a small shock (the foot), then a ramp |
| `pulse_split_normal.deck` | `split_normal 0.75 0.05 0.25`, `xvel = 0`, amplitude 0.6: a bump in a layer at rest on average | a compression pulse; A goes into tension at once |

The three ramp decks give A the same momentum (a uniform 1.0 km/s flyer's)
and differ only in its shape, so their drives (the `drive` scope view) can
be compared directly.

Spall is off in all four (`spall_strength = 100` for both materials): they
are wave demos, not fracture studies. They pull the aluminum to 5 to 11 GPa
of tension and the PMMA to about 1.1 GPa, far beyond what either holds
(about 1 to 2 GPa and 0.16 GPa), so at realistic strengths both break and
the broken pieces knock against each other, ringing in the tracer data.

**Shock formation,** `steepening_hump.deck`: three layers of aluminum, A
(6 mm), B (4 mm) and C (20 mm), at rest but for a Gaussian hump of velocity
in B (`normal 0.5 0.125`, `xvel = 0.3133`: 1.0 km/s at its top, 0 at its
feet). The hump splits into a compression pulse running right (about
0.5 km/s, 8 GPa) and a tension pulse running left; the compression pulse's
front steepens into a shock within about 0.6 us (3 mm), and the pulse turns
into a triangle that decays as it crosses C. A pressure movie (25 frames)
and scope views at 1, 3, 6, 10 and 15 mm into C are built in; spall is off,
as above.

**A detonation,** `me697_hvrb_2p00.deck`: the class problem with Material X
burning (`burn = hvrb`, `products = ideal_gas`, the HVRB equation sheet's
Material X constants; Material block, "Burning"). At 2.00 km/s the shock
grows into a detonation about 3.5 mm into Material X and runs at D_CJ =
7.5 km/s, a von Neumann spike at its front and the products' Taylor wave
behind; the P t-x diagram and the pressure movie (35 frames) show it, and
each tracer's `XRN` column is its cell's extent of reaction. Change `define
u_fly` for the Pop plot's trend (1.75 and 1.50 km/s detonate later, 1.25 and
1.00 not within 10 mm). Checked against the gold-standard reactive data by
`tests/verification/compare_hvrb.py`. About 3 s (release build).

**Keep the origin near the problem.** Positions are stored as plain numbers, so
round-off in x grows with the size of x: a cell's width is the difference of
its two face positions. With the origin in or near the stack (the usual
`origin = A:B`), round-off is around 1e-13 mm. Moving the whole problem to
x = 1000 mm costs about 3 digits (1e-8 km/s in velocities), and to 100 m about
5 (1e-6 km/s); still small, but for nothing.

---

## 7. Locations
One grammar, used by `tracer` and `origin`. Locations refer to **layer** names.

| Form | Meaning | Example |
|---|---|---|
| `A:B` | the interface between neighboring layers A and B (an exact node) | `MatX:PMMA` (or `PMMA:MatX`) |
| `A@f` | fraction f across layer A, 0 = left face, 1 = right face | `MatX@0.25` |
| number | an x position in the final frame, mm | `12.345` |

- `A:B` requires A and B to be neighbors; either order is accepted, since it
  is the same interface.
- `A@0` and `A@1` are the layer's faces, the same nodes as the neighboring
  interfaces.
- `origin` accepts only the named forms (`A:B`, `A@f`). For a specific number,
  use `x_left` instead, which says plainly what the number means.
- Numeric tracer locations are in the **final** frame, after `origin` or
  `x_left` is applied, so the number in the deck matches the plots.

---

## 8. Tracers
Tracers go in the `Output` block:
```
Begin Output
 tracer = pdv      MatX:PMMA
 tracer = quarter  MatX@0.25
End Output
```
- **Every tracer has a name,** unique (ignoring case), and the name ends each
  of its column names in the tracer file: `KMPS.pdv`, `GPA.pdv`, ...
- Tracers are also numbered 1, 2, 3, ... in deck order, for bookkeeping.
- **A tracer follows a material point.** An interface tracer is an exact node.
  An interior tracer keeps a fixed mass fraction between its two bracketing
  nodes; u and x are interpolated, and the cell values come from the cell that
  holds it. That way the same material point is followed at 35, 17.5 and 8.75
  zones/mm, which the convergence study needs.
- **A tracer on a node reports its own layer's cell.** Cell values are never
  averaged across a node (density, energy and sound speed jump at an
  interface). `A:B` reports the cell on A's side, the left one; `A@0` reports
  the first cell of A; any other node, the cell to its left. So `MatX:PMMA`
  gives MatX's pressure and density, and `PMMA@0` (the same node) gives
  PMMA's. The resolved deck says which cell each tracer reports.

### The tracer file, `<title>.tracers.csv`
Written in the folder the run starts from, laid out like the verification data
(`tests/verification/`), so one reader handles both:
- **Line 1:** short column names. **Line 2:** long names with units.
- **Then one row per output time,** comma-separated, 17 significant digits:
  - `TIME` (us), `CYCLE`, `DTIME` (the step just taken, us), and the
    whole-problem totals per unit area: `MTOT` (g/cm^3*mm), `ETOT`, `EK`,
    `EINT` (GPa*mm), `XMOM` (g/cm^3*mm*km/s);
  - then, for each tracer in deck order: `XPOS` (mm), `KMPS` (velocity,
    km/s), `GPA` (pressure), `RHO` (g/cm^3), `SIE` (specific internal energy,
    kJ/g), `Q` (artificial viscosity, GPa), `CS` (sound speed, km/s), `DMG`
    (damage: 0 intact, 1 broken), and, when some material carries T
    (`eos = mie_gruneisen_t`), `TK` (temperature, K; 0 for a tracer whose
    cell's material has no temperature model), and, when some material burns
    (`burn = hvrb`), `XRN` (extent of reaction, lam, 0 to 1; 0 where the
    cell's material does not burn).
- **When:** cycle 0, then the first cycle at or after each multiple of
  `tracer_dt`, at that cycle's own time (nothing is interpolated), and always
  the last cycle. `tracer_dt = 0` writes every cycle: about 1 KB per row with
  five tracers, so about 3.5 MB per run for the class problem; at 10 times the
  resolution (10 times the cycles too), set `tracer_dt`.
- `KMPS` is the velocity the method carries, at the half step before `TIME`;
  everything else is at `TIME`.
- **Both methods write the same columns,** with the same names and meanings,
  so one script reads either. `KMPS` is the face velocity u for `AV` and the
  Riemann solution u★ for `RS`. A column a method does not have is written
  `NaN`: `Q` under `RS`, which has no artificial viscosity (its dissipation is
  inside the Riemann solution). The trailer names the method.
- **The trailer.** After the last row comes `# ===== end of data =====` and
  then `#` lines: deck, title, start and end times and how the run ended,
  version, compiler and flags, cycles, conservation errors, cells broken, the
  output rule, and where each tracer sits on the mesh. numpy (`loadtxt`,
  `genfromtxt`) and pandas (`comment='#'`) skip those lines. Every way out of
  a run that bitwhiz controls writes the trailer, so a file without the
  end-of-data line is from a run that crashed.
- **Reading it** (Python):
  ```
  import numpy as np
  f = 'double_shock_2p00.tracers.csv'
  names = [n.strip() for n in open(f).readline().split(',')]
  d = np.genfromtxt(f, delimiter=',', skip_header=2, comments='#')
  col = {n: i for i, n in enumerate(names)}
  t, u = d[:, col['TIME']], d[:, col['KMPS.pdv']]
  ```
  Find columns by name, not by number: new columns are only ever added at the
  end of each tracer's group, but that still moves the columns of the tracers
  after it.

---

## 9. The history file, `<title>.hist`
> Format version 1, written by bitwhiz since Oct 20, 2026 (module `hist`;
> `DMG` and the variable `type` field were added the same day, compatibly).
> The screen's section 4 names the file, and the end-of-run report gives
> the number of frames written.

The history file is the run's record of the whole mesh over time, for
pictures: bitwhiz's own t-x diagrams (section 9b), and publication figures
with matplotlib or any other tool. It is binary, so a reader loads it in a
fraction of a second.

- **When it is written:** whenever snapshots are on (`plot_every` or
  `plot_dt`, section 6, `Output`). No snapshot keys, no file.
- **Where:** in the folder the run starts from, like the heartbeat.
- **When a frame is written:** cycle 0, then the first cycle at or after each
  multiple of `plot_dt`, and every `plot_every` cycles, at that cycle's own
  time (nothing is interpolated); always the last cycle.
- **What a frame holds: x, u, P and D.** Each is stored where the method
  keeps it, as in the tracer file (section 8):

  | Name | Unit | Where | Type | Values per frame | Method AV | Method RS |
  |---|---|---|---|---|---|---|
  | `XPOS` | mm | faces | real32 | k_max + 1 | x | x |
  | `KMPS` | km/s | faces | real32 | k_max + 1 | face velocity u | Riemann u★ |
  | `GPA` | GPa | cells | real32 | k_max | P | P |
  | `DMG` | - | cells | int8 | k_max | damage: 0 intact, 1 broken | the same |

  Faces are numbered 1 to k_max + 1 from the left free surface; face k is the
  left face of cell k. x and P are at the frame's time; u is at the half step
  before it, the velocity the method carries (as `KMPS` in the tracer file).
  Ghost cells are not stored. `DMG` is 1 wherever the cell's damage is above
  0 (bitwhiz's damage is only ever 0 or 1); a continuous damage model would
  get a new real32 variable instead.
  When some material carries T (`eos = mie_gruneisen_t`), a fifth variable
  follows: `TK`, K, cells, real32, k_max values (0 in a cell whose material
  has no temperature model). A run without T writes the four, byte for byte
  as before. When some material burns (`burn = hvrb`), a sixth follows it:
  `XRN`, -, cells, real32 (lam, 0 to 1; 0 in a cell that does not burn).
- **Size:** 13 k_max + 24 bytes per frame (17 k_max + 24 with `TK`, 21
  k_max + 24 with `XRN` too). The
  class problem (945 cells, `plot_dt = 0.01` to 5 us, 501 frames) writes
  6.2 MB.

### Layout
Little-endian on every machine (bitwhiz is compiled with
`-fconvert=little-endian`). Fortran stream access: plain bytes, no record
markers. `int8` is 1 byte, `int32` and `real32` 4, `real64` 8; text is ASCII,
padded with spaces, not null-terminated. Nothing is padded for alignment, so
a frame may be any number of bytes long.

**Header,** `header_bytes` long, in four parts:

1. **Fixed part, 64 bytes:**

   | Offset | Type | Field | Notes |
   |---|---|---|---|
   | 0 | 8 chars | `magic` | `BWHIST` and two spaces: this is a bitwhiz history file |
   | 8 | int32 | `version` | 1. A change a version-1 reader cannot follow raises it |
   | 12 | int32 | `header_bytes` | where frame 1 starts |
   | 16 | int32 | `frame_bytes` | the length of every frame |
   | 20 | int32 | `nframes` | frames written; 0 until the run ends (see Ending) |
   | 24 | int32 | `status` | how the run ended: 0 not ended (or crashed), 1 reached `t_end`, 2 reached `cycle_max`, 3 stopped by an error |
   | 28 | int32 | `kmax` | cells |
   | 32 | int32 | `nvar` | variables per frame (4; 5 with `TK`) |
   | 36 | int32 | `nlayer` | layers |
   | 40 | 8 chars | `method` | `AV` or `RS` |
   | 48 | int32 | `order` | 1 or 2 for `RS`; 0 for `AV` |
   | 52 | int32 | `text_bytes` | length of part 4 (2048) |
   | 56 | 2 int32 | spare | 0 |

2. **Variables,** `nvar` entries of 32 bytes, in the order they appear in each
   frame: `name` (8 chars), `unit` (16 chars), `where` (int32: 0 faces,
   1 cells), `type` (int32: 0 real32, 1 int8). Files written before `DMG`
   was added have 3 variables, all with `type` 0.
3. **Layers,** `nlayer` entries of 72 bytes, left to right: `name`
   (32 chars), `material` (32 chars), first and last cell (2 int32).
4. **Text,** `text_bytes` long: `key : value` lines, as in the heartbeat's
   header (deck, title, method, started, version, built, flags), then
   `plot_dt` and `plot_every` as the run's deck set them; each ends in a
   newline, and spaces pad the rest.

So `header_bytes` = 64 + 32 `nvar` + 72 `nlayer` + `text_bytes`.

**Frames,** `frame_bytes` each, one after another to the end of the file:

| Type | Field |
|---|---|
| real64 | `time` (us) |
| int32 | `cycle` |
| int32 | `frame`, 1, 2, 3, ... |
| real32 or int8 × (k_max + 1, or k_max) | each variable in turn, in the order of part 2 |

**Ending.** Frames are written and flushed as the run goes. Every way out of a
run that bitwhiz controls then fills in `nframes` and `status`. A file with
`nframes` = 0 is from a run that crashed or is still going; its whole frames
are still good (count them from the file size, as the reader below does).

**Comparing two files.** The text part names the build and the clock time, so
it differs between any two runs. Everything else (the fixed part, variables,
layers and every frame) depends only on the deck: the OpenMP and release tests
require it to be identical, byte for byte.

### Reading it (Python)
```
import numpy as np
b = open('double_shock_2p00.hist', 'rb').read()
H = np.frombuffer(b, count=1, dtype=[('magic', 'S8'), ('version', '<i4'),
    ('header_bytes', '<i4'), ('frame_bytes', '<i4'), ('nframes', '<i4'),
    ('status', '<i4'), ('kmax', '<i4'), ('nvar', '<i4'), ('nlayer', '<i4'),
    ('method', 'S8'), ('order', '<i4'), ('text_bytes', '<i4'),
    ('spare', '<i4', 2)])[0]
V = np.frombuffer(b, count=H['nvar'], offset=64, dtype=[('name', 'S8'),
    ('unit', 'S16'), ('where', '<i4'), ('type', '<i4')])
k = H['kmax']
fr = np.dtype([('time', '<f8'), ('cycle', '<i4'), ('frame', '<i4')] +
    [(v['name'].decode().strip(), '<f4' if v['type'] == 0 else 'i1',
      k + 1 - v['where']) for v in V])
n = (len(b) - H['header_bytes']) // fr.itemsize   # whole frames on disk
F = np.frombuffer(b, dtype=fr, count=n, offset=H['header_bytes'])
t, x, u, P, D = F['time'], F['XPOS'], F['KMPS'], F['GPA'], F['DMG']
```
`x[j, :]` is frame j's face positions and `P[j, :]` its cell pressures. A
quick Lagrangian t-x look is `plt.imshow(P, origin='lower', aspect='auto')`
(cell index across, frame up); an Eulerian one puts each cell at its center,
`xc = 0.5*(x[:, 1:] + x[:, :-1])`, then
`plt.pcolormesh(xc, np.broadcast_to(t[:, None], xc.shape), P, shading='nearest')`.
Find variables by name, not by position: new
variables are only ever added at the end of part 2.

### 9b. Pictures
At the end of a run, and in a `plots_only` run, bitwhiz reports (section 9 of
the screen) and writes, in the folder the run starts from:

| File | What | Size (pixels) | Needs |
|---|---|---|---|
| `<title>.tx_u.bmp` | t-x diagram of the velocity u | 1200 × 900 | snapshots (`plot_every` or `plot_dt`) |
| `<title>.tx_p.bmp` | t-x diagram of the pressure P | 1200 × 900 | snapshots |
| `<title>.tr_<name>.bmp` | one tracer's velocity against time, one per tracer | 800 × 600 | tracers |
| `<title>.mv_p_<cycle>.bmp` | a frame of the pressure movie: P against x | 800 × 600 | `movie_frames` (and snapshots) |

The pictures are 24-bit Windows bitmaps (`.bmp`), drawn by
`src/drawings/draw_tx.f95`, `draw_trace.f95` and `draw_profile.f95` and written
by `src/main/bmpmaker.f95`. `make tidy` removes them with the run's other files.

- **The pressure movie** (`movie_frames`, Output block): N frames of P
  against x, drawn from the history file like the t-x diagrams, so it needs
  snapshots (`plot_dt` or `plot_every`) and its times are a subset of theirs.
  The N movie times are spread evenly from 0 to the last snapshot's,
  t_m = m·t_last/(N − 1), and each frame is the snapshot nearest one (the
  earlier of two equally near; a snapshot two times share is drawn once, so
  a run with fewer snapshots than N gets fewer frames). N is 2 to 50: a movie
  is a preview, at most 50 pictures, so no deck can flood its folder; a
  figure for a paper is better made from the history file itself (section
  9). P is drawn at the cells' centers. Files are named by the snapshot's
  cycle in six digits (`<title>.mv_p_000142.bmp`; past cycle 999999 the
  count rolls over), so they sort in time order, and each is titled with its
  time, PRESSURE AT TIME = +1.000 US. The axes hold for the whole movie: x as
  the t-x diagrams' (the run's smallest to largest face position, lab
  frame), y from min − 5% to top + 5% of the run's P, the top as for the P
  t-x diagram (`plot_range`), each axis's ends rounded out to clean numbers
  (as the tracer plots'); a value above the top is drawn at the box's edge.
  Each frame prints its axis ends, as a tracer plot does, and the screen
  gives both axes. A frame costs about as much as a tracer plot
  (a tenth of a second in the release build); 20 to 25 frames make a good
  preview. Make a movie from them with any tool that takes a sequence of
  pictures; with ffmpeg (nanoHUB has it, with libx264), from the folder the
  run wrote them in:

      ffmpeg -y -framerate 7 -pattern_type glob -i '<title>.mv_p_*.bmp' \
             -c:v libx264 -pix_fmt yuv420p -crf 20 <title>.mv_p.mp4

  (7 frames a second: 35 frames make 5 s; `yuv420p` so browsers play it).
  The class deck, `pulse_split_normal.deck`, `steepening_hump.deck` and
  `me697_hvrb_2p00.deck` make movies (35, 35, 25 and 35 frames).

- **Read from the files, never from memory.** The t-x diagrams come from
  `<title>.hist` and the tracer plots from `<title>.tracers.csv`, so a picture
  made after a run and the same picture from a `plots_only` run are made from
  the same numbers.
- **t-x diagrams, lab frame:** x across, from the smallest to the largest face
  position of the whole run; t up, from 0 to the last frame. The colors are the deck's `colormap` over a window of
  the data: from min + lo·(top − min) to min + hi·(top − min), with lo and hi
  from `plot_u_lo`, `plot_u_hi` (or `plot_p_lo`, `plot_p_hi`), 0 and 1 by
  default. Values beyond the window take its end colors.
- **The top of the color range** (`plot_range`). `full`: the data's max.
  `robust` (the default): the largest value the run *held*. Frame by frame,
  take the largest value on the mesh; the top is the highest level those
  reach for at least 50 cycles in all, if the max is more than 2% of the range
  above it, and the max if not. So a start-up spike, the few tens of cycles of
  overshoot where two slabs meet at an impact (6% at the RS impact of
  `u6_boundary_boundary`), does not set the colors, a state that lasts does,
  and a run without a spike keeps its full range. The screen names what lies
  above the top (how high, where and when, for how many cycles); it is drawn
  in the top color. The bottom is always the data's min: tension, the spall
  signal, is never trimmed. **White:** everything
  outside the material, and open spall (a broken cell, D = 1, at P = 0; closed
  again, it carries pressure and is colored), in both; in P also material no
  wave has reached yet. A cell counts as reached once its |P| exceeds 10⁻³ of
  the run's largest |P| in any frame so far; material a release has brought
  back to about zero pressure stays colored. In u, untouched material is
  colored too: a moving flyer has its velocity, material at rest u = 0. (Why not "P = 0 exactly": in the
  lab frame a moving flyer's faces move every step, so its untouched cells pick
  up round-off pressures of about 10⁻¹⁴ GPa. And why 10⁻³: ahead of a shock an
  explicit scheme leaves a foot of tiny pressures, falling about 4 times per
  cell; at 10⁻⁶ its first few cells were colored, at the colormap's dark end,
  and looked like a precursor. A wave weaker than 10⁻³ of the largest |P|
  stays white until a stronger one arrives.)
- **How a t-x diagram is drawn** (`src/drawings/draw_tx.f95`): like the
  mixed cells of an Eulerian hydrocode. Each pixel row is 4 sub-rows, each at
  its own time. The face positions are interpolated in time between the two
  frames around it, so material moves smoothly between frames; each cell's
  state comes from the nearer frame; each cell is laid between its two faces,
  and a pixel takes the length-weighted mean of the colored cells over it and
  its **coverage**, the fraction of its width they fill (white cells add
  nothing). Its color in a sub-row is coverage × colormap(mean) +
  (1 − coverage) × white, and the pixel is the average of its sub-rows. So a
  free surface or a spall plane that cuts a pixel shades it by how much of it
  is material, and lines of any slope are smooth, not stair-stepped: area
  coverage, exact across and sampled 4 times up. P is the same across a cell;
  u, stored at the faces, runs linearly across it. A face is a curve of slope
  dx/dt = u, and a shock front's slope is the shock velocity. With the class
  deck's 501 frames for 775 rows, halving `plot_dt` changes fewer than 0.3% of
  the pixels by more than 16 of 255 levels.
- **The t-x picture** has the tracer plots' look (below; the frame, the font
  and the slate are shared, `src/modules/strk_mod.f95`): the plot area inside
  a box with rounded corners and ticks at tenths, the box 40 pixels from the
  top, 100 from the left, 60 from the right and 105 from the bottom; the title
  **BITWHIZ PRESSURE VIEW** or **BITWHIZ VELOCITY VIEW** engraved above it,
  centered on the page; the axis ends as numbers, as on the tracer plots, x
  (mm) under the box's bottom corners and t (us) left of its left side, each
  axis rounded out to clean ends first (the class deck: −7 to 25 mm, 0 to 5
  us; a top rounded past the last frame is white); and below it a **color
  bar**, the colormap from the color window's low end (left) to its high end
  (right), outlined in slate and labeled with the window's ends in data
  units, to 3 significant figures of the larger (−2.6 and 18.7 GPa for the
  class deck). The colors are the window's exactly: its ends are not rounded,
  only written short, and the screen gives them in full.
- **Tracer plots** (`src/drawings/draw_trace.f95`): the tracer's velocity
  (`KMPS`) against time, a line through every row of the tracer file, 3.0
  pixels wide, in Okabe-Ito vermilion (#D55E00). x runs from the first to the
  last time, y from the smallest to the largest velocity, widened by 5% of the
  range at each end; then each axis's ends are rounded out to clean numbers,
  two significant figures of the axis's span (the class deck's pdv: data 0 to
  1.9921 km/s, axis −0.1 to 2.1; time 0 to 5 us stays 0 to 5). The text: the
  title **BITWHIZ SCOPE VIEW**, engraved in slate in the margin above the box,
  16-pixel capitals in bitwhiz's own stroke font (each letter a few straight
  strokes and elliptical arcs; only the titles' letters, the digits and
  `. = + - E` are defined), drawn and anti-aliased like the curve; and the
  four axis ends in 12-pixel figures, x's under the box's bottom corners and
  y's left of its left side, at the plot area's bottom and top, in the
  axis's own units (us, km/s; for a movie mm, GPa) and with no unit or axis
  name printed (yet). A number too large or small to read in plain figures is
  written with a power of ten, `2.62E4`. The frame: slate (#2C3E50, the
  sheets' ink) spines 2.5 pixels wide, the box 40 pixels from the top (the
  title's margin), 100 from the left, 60 from the right and 70 from the
  bottom (room for the numbers), outside corners rounded to a 12-pixel radius, and
  tick marks at tenths of each axis pointing in; where the curve meets a
  spine, the spine is on top. The colors follow the equation sheets' figures
  (the Okabe-Ito palette, which colorblind readers can tell apart). Everything
  is anti-aliased: drawn at 4 × 4 samples per pixel and averaged, so each
  pixel takes the shade of how much of it each ink covers (Russ and Neal,
  *The Image Processing Handbook*, ch. 4, neighborhood averaging). Curves and
  corners are smooth, not stair-stepped, and a line does not jump from ink to
  white within one pixel.
- **The screen gives every range** (x, t, the data, each color window and
  each tracer's y axis), with the axes' names and units the pictures do not
  print yet.

**`plots_only = yes`** (Run block) re-draws the pictures without running: a
new `colormap` or color window takes about a second. It reads the deck as
usual, skips sections 3 to 8 of the run, and writes nothing but the pictures,
so the heartbeat, tracer and history files it reads are never touched.
- The history file must have been made by this deck: its method, order, cell
  count and layers (names, materials, cells) are checked against the deck's.
  A mismatch, or a missing file, stops the run with an error (exit status 1).
- The frames in the file decide the t-x diagrams. The deck's `plot_dt` and
  `plot_every` only say whether there is a history file to read; if they
  differ from the run's (recorded in the file's text), the screen says they
  are not used.
- Every tracer in the deck must be in the tracer file.
- It writes the same pictures a run would, by the same names, replacing the
  old ones. Movie frames are named by cycle, so frames an earlier run left at
  other cycles stay until `make tidy` clears them.

---

## 10. Errors and the log
- **Fatal, with file name and line number:**
  - an unknown key or block (a real key in the wrong block says where it
    belongs, e.g. "tracer belongs in the Output block, not the Run block");
  - a duplicate key, name or define;
  - a bad number, name or location;
  - an `End` that doesn't match its `Begin`, or a missing `End bitwhiz`;
  - a layer naming a missing material;
  - an interface whose layers aren't neighbors;
  - a tracer missing its name or its location (the message shows the
    form `tracer = <name> <location>`);
  - a fraction outside [0, 1];
  - a number outside the stack;
  - both `origin` and `x_left`.
- **All errors are collected, then reported together,** so one run lists every
  problem (for example, all of the missing required keys), not just the first.
- **Warnings:** unused materials, rounded zone counts, and `zones` overriding a
  resolution.
- **The resolved deck is written to `<title>.resolved`,** in the folder the
  run starts from: every key with its final value (defaults filled in,
  defines substituted), and every tracer's resolved x. `bitwhiz
  <title>.resolved` repeats the run exactly. The screen names the file
  (section 2), and at the end lists every file the run wrote with its size
  (section 8). The name does not end in `.deck`, so nothing that looks for
  decks takes it for one. A `plots_only` run writes none: it keeps the run's.
- **Notes** (not warnings) say when `zones` overrides a resolution.

---

## 11. Where values land in the code
| Deck | Code (`src/modules/shock_mod.f95`) |
|---|---|
| `Layer` keys `width`, `xvel`, `zones`, `resolution`, `name` | `layer(l)%...` (same names) |
| `xvel_profile`, `xvel_amplitude` | `layer(l)%prof_name`, `prof_np`, `prof_par`; `xamp`, `have_amp` |
| `Material` keys `R0`, `C0`, `S1`, `S2`, `G0` | copied into `layer(l)%...`, then into each cell's slots `jr0 ... jg0` |
| `Material` keys `eos`, `CV`, `T0` | `material(m)%eos` (`eos_mie_gruneisen`, `eos_mie_gruneisen_t`), `CV` (J/(g K)), `T0`; copied into `layer(l)%eos`, `cv` (kJ/(g K): `CV`/1000), `T0`, then into module `temperature` (`src/modules/temp_mod.f95`), cell by cell |
| `Material` keys `burn`, `products`, `PR` ... `TAU0`, `GAMMA`, `Q` | `material(m)%burn` (`burn_hvrb`), `products` (`products_ideal_gas`), the constants by their names; copied into `layer(l)%...`, then into module `burn` (`src/modules/burn_mod.f95`), cell by cell; the physics in module `hvrb` (`hvrb_mod.f95`) and `products` (`prod_mod.f95`) |
| `num_threads` | `nproc` |
| `Run`, `Output`, `Solver`, `Stack` keys | module variables of the same name (`t_end`, `plot_dt`, `colormap`, `CFL`, `stack_resolution`, ...) |
| `tracer` | `tracer(n)%...`: name, location, `x0`, `kface`, `w`, `kcell` |

---

## 12. Tests
```
make
./tests/run_deck_tests.sh
```
Each deck in `tests/decks/` begins with `# expect: ok` (it must read cleanly)
or `# expect: <part of the message>` (it must fail with that message). Clean
decks, and every deck in this folder, are also round-tripped: the resolved
deck the run writes (`<title>.resolved`) must run and resolve to the same
statements. Each run is in its own scratch folder. To add a case, drop in a deck
with an `# expect:` line.

The history file (section 9) has its own tests, `tests/run_hist_tests.sh`,
also run by `make test`. `bin/test_hist` reads each run's file the way
section 9 says to and checks every part of it; then, with `tracer_dt` set
equal to `plot_dt`, an interface tracer's x, u and P must be the file's values
at its face and cell, frame for frame. Other cases: frames every 7th cycle
(`plot_every`, where the last frame's broken cells must also be the run's
count), a run stopped by `cycle_max` (status 2), a deck without snapshots (no
file), and `plots_only`: with a new colormap, window and `plot_dt` it must
report the run's own ranges and leave the run's files untouched, and a deck
with another mesh, or a folder without the files, must stop it with an
error. Every finished run must write exactly its pictures, by name and size
(tracer plots only, for a deck with tracers but no snapshots), and a
`plots_only` run with another colormap must change the t-x diagrams and not
the tracer plots. In the class run's P t-x diagram, pixels at known places
must be white (the untouched flyer and PMMA at t = 0, no material at
x = −7 mm by t_end) or colored (the impact plane just after t = 0, the PMMA at
x = 15 mm near t_end), which checks the lab frame, the time direction and the
white rule; in its u t-x diagram the moving flyer and the PMMA at rest must be
colored at t = 0, and the places with no material white. The P t-x diagram's
frame, title and color bar are checked at known pixels too. With velocity
profiles, frame 1's face velocities must be the profiles' cell averages, from
the textbook F computed again in the test, to single precision.

With materials that carry T (`tests/decks/ok_temperature.deck`), the file
has `TK` after `DMG`, and the tracer's `TK` in it is the tracer file's, to
single precision, 298 K (T0) at t = 0.

The temperature (module `temperature`) has a unit test, `bin/test_temp`, also
run by `make test`: the cold energy against 50-digit values from
`tests/temp_reference.py` (mpmath, the integral from V0 by its own
quadrature), in one step and in 997, along a 2,000-step path through a shock,
ringing and release into tension and back, and out to 21 V0 and back (on the
curve to 1e-13 every time); temperatures on the Hugoniot; and the units, from
the deck's `CV` in J/(g K) to 100 K by hand. The G1 comparison
(`tests/verification/compare_g1.py`) checks every material's `TK` against the
formula at bitwhiz's own state, every row, to 1e-6 K, and the first shock's
against the exact Hugoniot temperature, to 0.1 % of the rise: bitwhiz's own
temperature standard (`doc/design/materials.md`, "Temperature
verification").

The distributions themselves (module `distributions`) have a unit test,
`bin/test_dist`, also run by `make test`: f, F and 1 − F at 42 points against
50-digit values from `tests/dist_reference.py` (mpmath), and identities that
need no reference values (F + (1 − F) = 1, F never decreasing, F's
differences against a numerical integral of f, the special cases that reduce
to the normal or the uniform, and the parameter checks).

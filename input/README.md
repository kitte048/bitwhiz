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
complete record of what was run.

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
| `colormap` | name | `viridis` | for bitmap pictures: `grayscale`, `viridis`, `plasma`, `inferno`, `blackbody`, `kindlmann`, `extendedkindlmann`, `smoothcoolwarm`, `bentcoolwarm` |
| `plot_u_lo`, `plot_u_hi` | number, 0 to 1 | 0, 1 | the u t-x diagram's color window, as fractions of the data's range (lo below hi; section 9b) |
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

### `Material <name>`
Mie-Gruneisen, referenced to the principal Hugoniot (project rev-0, Eq. 4).
| Key | Units | Default |
|---|---|---|
| `R0` | g/cm^3 | required |
| `C0` | km/s | required |
| `S1` | - | required |
| `S2` | - | 0.0 |
| `G0` | - | required |
| `spall_strength` | GPa | 0.01 |

A material that no layer uses gets a warning, not an error.

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
| `pulse_split_normal.deck` | `split_normal 0.75 0.05 0.25`, `xvel = 0`, amplitude 0.6: a bump in a layer at rest on average | a compression pulse; A spalls at once |

The three ramp decks give A the same momentum (a uniform 1.0 km/s flyer's)
and differ only in its shape, so their drives (the `drive` scope view) can
be compared directly.

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
    (damage: 0 intact, 1 broken).
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
- **Size:** 13 k_max + 24 bytes per frame. The class problem (945 cells,
  `plot_dt = 0.01` to 5 us, 501 frames) writes 6.2 MB.

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
   | 32 | int32 | `nvar` | variables per frame (4) |
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

The pictures are 24-bit Windows bitmaps (`.bmp`), drawn by
`src/drawings/draw_tx.f95` and `draw_trace.f95` and written by
`src/main/bmpmaker.f95`. `make tidy` removes them with the run's other files.

- **Read from the files, never from memory.** The t-x diagrams come from
  `<title>.hist` and the tracer plots from `<title>.tracers.csv`, so a picture
  made after a run and the same picture from a `plots_only` run are made from
  the same numbers.
- **t-x diagrams, lab frame:** x across, from the smallest to the largest face
  position of the whole run; t up, from 0 to the last frame. The colors are the deck's `colormap` over a window of
  the data: from min + lo·(max − min) to min + hi·(max − min), with lo and hi
  from `plot_u_lo`, `plot_u_hi` (or `plot_p_lo`, `plot_p_hi`), 0 and 1 by
  default. Values beyond the window take its end colors. **White:** everything
  outside the material, and open spall (a broken cell, D = 1, at P = 0; closed
  again, it carries pressure and is colored), in both; in P also material no
  wave has reached yet. A cell counts as reached once its |P| exceeds 10⁻⁶ of
  the run's largest |P| in any frame so far; material a release has brought
  back to about zero pressure stays colored. In u, untouched material is
  colored too: a moving flyer has its velocity, material at rest u = 0. (Why not "P = 0 exactly": in the
  lab frame a moving flyer's faces move every step, so its untouched cells pick
  up round-off pressures of about 10⁻¹⁴ GPa.)
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
  a box with rounded corners and ticks at tenths, 40-pixel margins left, right
  and above; the title **BITWHIZ PRESSURE VIEW** or **BITWHIZ VELOCITY VIEW**
  engraved above the box; and below it a **color bar**, the colormap from 0
  (the color window's low end, left) to 1 (its high end, right), outlined in
  slate and labeled 0 and 1. The screen gives the window in data units.
- **Tracer plots** (`src/drawings/draw_trace.f95`): the tracer's velocity
  (`KMPS`) against time, a line through every row of the tracer file, 3.0
  pixels wide, in Okabe-Ito vermilion (#D55E00). x runs from the first to the
  last time, y from the smallest to the largest velocity, widened by 5% of the
  range at each end. The only text is the title **BITWHIZ SCOPE VIEW**,
  engraved in slate in the margin above the box: 16-pixel capitals in
  bitwhiz's own stroke font (each letter a few straight strokes and elliptical
  arcs; only the titles' letters and the color bar's 0 and 1 are defined),
  drawn and anti-aliased like the curve. The frame: slate (#2C3E50, the sheets' ink) spines 2.5 pixels wide
  around a 40-pixel margin, outside corners rounded to a 12-pixel radius, and
  tick marks at tenths of each axis pointing in; where the curve meets a
  spine, the spine is on top. The colors follow the equation sheets' figures
  (the Okabe-Ito palette, which colorblind readers can tell apart). Everything
  is anti-aliased: drawn at 4 × 4 samples per pixel and averaged, so each
  pixel takes the shade of how much of it each ink covers (Russ and Neal,
  *The Image Processing Handbook*, ch. 4, neighborhood averaging). Curves and
  corners are smooth, not stair-stepped, and a line does not jump from ink to
  white within one pixel.
- **The screen gives every range** (x, t, the data, each color window and
  each tracer's y axis), so the pictures can be read without text on them.

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
  old ones.

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
- **The resolved deck is echoed to the log:** every key with its final value
  (defaults filled in, defines substituted), and every tracer's resolved x.
  Re-running the echo reproduces the run. Until the run log exists, it is
  printed to the terminal.
- **Notes** (not warnings) say when `zones` overrides a resolution.

---

## 11. Where values land in the code
| Deck | Code (`src/modules/shock_mod.f95`) |
|---|---|
| `Layer` keys `width`, `xvel`, `zones`, `resolution`, `name` | `layer(l)%...` (same names) |
| `xvel_profile`, `xvel_amplitude` | `layer(l)%prof_name`, `prof_np`, `prof_par`; `xamp`, `have_amp` |
| `Material` keys `R0`, `C0`, `S1`, `S2`, `G0` | copied into `layer(l)%...`, then into each cell's slots `jr0 ... jg0` |
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
deck must read back to the same statements. To add a case, drop in a deck
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

The distributions themselves (module `distributions`) have a unit test,
`bin/test_dist`, also run by `make test`: f, F and 1 − F at 42 points against
50-digit values from `tests/dist_reference.py` (mpmath), and identities that
need no reference values (F + (1 − F) = 1, F never decreasing, F's
differences against a numerical integral of f, the special cases that reduce
to the normal or the uniform, and the parameter checks).

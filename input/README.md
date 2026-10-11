# input
This folder contains the input decks for bitwhiz, and this file is the deck
syntax specification (deck_version 1). The parser is written to this page; if
the two ever disagree, fix one of them on purpose.

**Status:** specification only. Today the code reads `-np N` and nothing else.

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

 Begin Run       ... End Run          # time, threads, output, tracers
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
| `title` | name | deck file name | names the run's output folder |
| `t_end` | number, us | required | termination time |
| `cycle_max` | integer | 1000000 | backstop against a stalled time step |
| `num_threads` | integer | 1 | `0` means all processors; capped at the processor count |
| `plot_every` | integer | 0 (off) | write a snapshot every N cycles |
| `plot_dt` | number, us | 0 (off) | also write a snapshot every plot_dt |
| `tracer` | name location | none | repeatable; see section 8 |

The first and last cycles are always written. A snapshot is written whenever
either `plot_every` or `plot_dt` says so.

### `Solver`
| Key | Type | Default | Notes |
|---|---|---|---|
| `method` | `AV` | `AV` | other methods arrive on their own branch |
| `BL` | number | 0.3 | linear viscosity coefficient |
| `BQ` | number | 2.2 | quadratic viscosity coefficient |
| `CFL` | number | 0.6 | Courant safety factor, 0 < CFL <= 1 |

### `Material <name>`
Mie-Gruneisen, referenced to the principal Hugoniot (project rev-0, Eq. 4).
| Key | Units | Default |
|---|---|---|
| `R0` | g/cm^3 | required |
| `C0` | km/s | required |
| `S1` | - | required |
| `S2` | - | 0.0 |
| `G0` | - | required |

A material that no layer uses gets a warning, not an error.

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
| `xvel` | number or define, km/s | 0.0 | initial velocity, + is to the right |
| `zones` | integer | | zone count for this layer |
| `resolution` | number, zones/mm | the Stack's | overrides the Stack value |

Each layer must end up with a zone count from `zones`, its own `resolution`, or
the Stack's `resolution`. If `zones` and a `resolution` both apply, `zones` wins
and the log says so. If `width * resolution` is not a whole number, it is
rounded and the log warns (a silently uneven mesh is worse than a warning).
The width is always kept exact, so interfaces stay where the deck puts them;
rounding only changes that layer's dx = width / zones slightly.

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
```
tracer = pdv      MatX:PMMA
tracer = quarter  MatX@0.25
```
- **Every tracer has a name,** unique (ignoring case), and the name heads its
  columns in the tracer output: `t, pdv_u, pdv_x, ...`.
- Tracers are also numbered 1, 2, 3, ... in deck order, for bookkeeping.
- The tracer file header lists, for each tracer: number, name, the location as
  written, the resolved initial x, its layer, and its node or cell index.
- **A tracer follows a material point.** An interface tracer is an exact node.
  An interior tracer keeps a fixed mass fraction between its two bracketing
  nodes; u and x are interpolated, and p, rho, e, q come from the cell that
  holds it. That way the same material point is followed at 35, 17.5 and 8.75
  zones/mm, which the convergence study needs. The log also reports the
  nearest node.

---

## 9. Errors and the log
- **Fatal, with file name and line number:**
  - an unknown key or block;
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
  Re-running the echo reproduces the run.

---

## 10. Where values land in the code
| Deck | Code (`src/modules/shock_mod.f95`) |
|---|---|
| `Layer` keys `width`, `xvel`, `zones`, `resolution`, `name` | `layer(l)%...` (same names) |
| `Material` keys `R0`, `C0`, `S1`, `S2`, `G0` | copied into `layer(l)%...`, then into each cell's slots `jr0 ... jg0` |
| `num_threads` | `nproc` |

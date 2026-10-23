# Distributions: design note

Branch `distributions`, started from `v1.0` (108762f), Oct 22, 2026.
Status: **design**, no code yet. This note records the plan so that the idea
survives even if the branch sits for a while.

## The idea

Today a layer starts at one velocity, `xvel`. This branch lets the velocity
vary across the layer with a shape taken from a probability distribution:

    u(xi) = ubar + du * ( f(xi) - 1 ),    xi = (x - x_left) / width,  0 <= xi <= 1

where `ubar` is the deck's `xvel`, `du` the deck's `xvel_amplitude` (km/s;
`du = ubar` when absent), and `f` a probability density on [0, 1] (it
integrates to 1). With `du = ubar` this is simply `u = ubar * f`.

Because `f` integrates to 1, `f - 1` averages to zero, and:

- **Momentum is unchanged, for any du.** Every shape gives the layer the
  momentum of the uniform layer, `R0 * width * xvel`. A shape only
  redistributes it, and `xvel` keeps its meaning: the layer's mean velocity.
- **Energy splits cleanly** into the mean motion and the spread about it:
  the layer's kinetic energy is `(1/2) R0 width ( ubar^2 + du^2 ( I2 - 1 ) )`,
  with `I2` the integral of f^2, which is at least 1 (Cauchy-Schwarz; equal
  only for the uniform shape). There is no cross term.
- **Mean and shape are independent.** 1D hydrodynamics does not change under
  a constant shift in velocity, so this split is the natural one. A layer at
  rest on average (`xvel = 0`) can still stretch or squeeze, the velocity may
  cross zero inside a layer, and the strain rate is set by `du`, not tied to
  the mean.
- **The existing setup check verifies it.** Section 6, check (6), already
  requires the total momentum at t = 0 to equal the sum of
  `R0 * width * xvel` to round-off. If the cell velocities use cell averages
  of `f` (below), the new feature passes that check by construction, on every
  run, with no new check.

Why a velocity profile is physics and not decoration:

- **Compression gradients** (the rear faster than the front): characteristics
  converge, and a smooth ramp steepens into a shock at a predictable time and
  distance.
- **Tension gradients** (the front faster than the rear): the layer stretches
  at a known strain rate, the setting of dynamic fragmentation theory, and a
  controlled test of bitwhiz's spall model. With `xvel = 0` the layer's
  center stays put while its ends move apart.
- **Realistic flyers:** laser- and explosively-driven flyers are not uniform.
- **Later, random draws:** sampling each cell's velocity from a distribution
  gives ensembles for uncertainty quantification (phase 2, below).

## Names

| What | Name | Why |
|---|---|---|
| The library (math only) | module `distributions`, file `src/modules/dist_mod.f95` | general; reusable in other codes (an EM solver, a kinetic code) |
| Its unit test | `tests/test_dist.f95` | math identities only, so it travels with the module |
| The deck keys | `xvel_profile`, `xvel_amplitude`, in a Layer block | the words a shock physicist expects |
| The branch | `distributions` | its lasting product is the library; profiles are its first user |

## Architecture

**Two layers, kept apart.**

1. **`distributions`**, the library. Densities, cumulative distributions and
   interval means, and nothing about bitwhiz: no layers, no velocities, no
   deck. It must be **self-contained**: its kinds come from
   `iso_fortran_env` (`real64`, `int32`), not from bitwhiz's module `bits`,
   so the file and its unit test can be copied into another code unchanged.
2. **bitwhiz's use of it.** The deck reads `xvel_profile` and
   `xvel_amplitude`; initialization (maincode section 5) maps each layer onto
   [0, 1] and asks the library for each cell's average of `f`.

**The library's interface** (pure or elemental, so it is safe under OpenMP and
works on whole arrays):

| Routine | Returns |
|---|---|
| `dist_set( d, name, params, ierr, msg )` | a `dist_t` from a name and its parameters; checks them |
| `dist_pdf( d, x )` | the density f(x) |
| `dist_cdf( d, x )` | the cumulative distribution F(x) |
| `dist_mean( d, a, b )` | the average of f over [a, b], `( F(b) - F(a) ) / ( b - a )` |
| `dist_support( d, lo, hi )` | where f lives: [0, 1] or (-inf, inf) |

`dist_t` holds an integer id and up to four real parameters. A new
distribution is a new `case` in each routine, as glyphs (module `strokes`) and
colormaps already are in bitwhiz. No class hierarchy: it would cost
readability for flexibility nobody has asked for.

**Random numbers stay out of the library.** Sampling (phase 2) will be
`dist_inv_cdf( d, p )`, which takes a uniform deviate `p` from the caller.
bitwhiz would pass draws from its own module `random`; another code passes its
own. Runs stay reproducible and the library stays generator-agnostic.

## The catalogue, first round

Every distribution is used through its cumulative distribution, F, never by
integrating f numerically. That matters: a beta density with a < 1 or b < 1
is infinite at an end of [0, 1], but its F is finite and smooth, so cell
averages from F differences are exact and finite.

**Every shape can lean either way through its own parameters,** so no
"reverse" option is needed:

| Name | Deck parameters | Support | Leans | Lean the other way by |
|---|---|---|---|---|
| `uniform` | (none) | [0, 1] | no | |
| `linear` | `s`, slope, -1 to 1 | [0, 1] | either way | changing the sign of s |
| `beta` | `a`, `b` > 0 | [0, 1] | either way | swapping a and b |
| `normal` | `mu`, `sigma` > 0 | (-inf, inf) | symmetric | |
| `split_normal` | `m` (peak), `sigma_left`, `sigma_right` > 0 | (-inf, inf) | either way | swapping the two spreads |
| `sinh_arcsinh` | `loc`, `scale` > 0, `eps`, `delta` > 0 | (-inf, inf) | either way, and tail weight | changing the sign of eps |
| `cauchy` | `x0` (location), `gamma` (scale) > 0 | (-inf, inf) | symmetric, heavy tails | |

**Formulas.** Phi is the standard normal cumulative distribution,
`Phi(z) = (1/2) erfc( -z / sqrt 2 )`, and phi its density,
`exp( -z^2/2 ) / sqrt( 2 pi )`.

| Name | f(x) | F(x) | F computed by |
|---|---|---|---|
| `uniform` | 1 | x | closed form |
| `linear` | 1 + s(2x - 1) | x + s(x^2 - x) | closed form |
| `beta` | x^(a-1) (1-x)^(b-1) / B(a,b) | I_x(a, b), the regularized incomplete beta function | continued fraction (Abramowitz and Stegun, ch. 26); `log_gamma` (Fortran 2008) for B |
| `normal` | phi(z) / sigma, z = (x - mu)/sigma | Phi(z) | `erfc` (Fortran 2008) |
| `split_normal` | A exp( -(x-m)^2 / (2 s^2) ), s = sigma_left for x < m, sigma_right for x >= m; A = sqrt(2/pi) / (sigma_left + sigma_right) | x < m: 2 sigma_left Phi((x-m)/sigma_left) / (sigma_left + sigma_right); x >= m: ( sigma_left - sigma_right + 2 sigma_right Phi((x-m)/sigma_right) ) / (sigma_left + sigma_right) | `erfc` |
| `sinh_arcsinh` | delta cosh(w) phi(z) / ( scale sqrt(1 + y^2) ), y = (x - loc)/scale, w = delta asinh(y) - eps, z = sinh(w) | Phi(z) | `asinh`, `erfc` (Fortran 2008) |
| `cauchy` | 1 / ( pi gamma (1 + ((x - x0)/gamma)^2) ) | 1/2 + atan( (x - x0)/gamma ) / pi | closed form |

Notes on the two skewed families:

- **Split normal** (two-piece normal): a normal on each side of the peak `m`,
  with its own spread, joined so the density is continuous. The wider side is
  the way it leans; equal spreads give `normal`. It is the easiest shape to
  picture in layer units: `split_normal 0.3 0.05 0.2` peaks at 0.3 of the
  width, falls off fast to the left and slowly to the right.
- **Sinh-arcsinh** (Jones and Pewsey, *Biometrika* 96, 2009): `eps` sets the
  skewness (0 symmetric, either sign leans either way), `delta` the tail
  weight (below 1 heavy, Cauchy-like; above 1 light). `eps = 0, delta = 1` is
  exactly `normal`. The one family with an explicit, signed skewness
  parameter.

Only one special function is needed, the incomplete beta. Everything else is
`erfc`, `asinh`, `atan` and `log_gamma`, all Fortran intrinsics.

**Later candidates,** each a new `case`: gamma, Weibull and log-normal
(set aside for this round: the two skewed families above cover their shapes,
and dropping gamma removes the incomplete gamma function), exponential,
truncated normal, Maxwellian, Planck.

## Using a distribution on a layer

**One rule for all of them: truncate to [0, 1] and renormalize.** The layer's
coordinate xi runs from 0 at its left face to 1 at its right, and the shape is
the distribution's density on [0, 1] divided by the probability it puts
there:

    f_layer(xi) = f(xi) / ( F(1) - F(0) )

For uniform, linear and beta the support is already [0, 1], so this changes
nothing. For the others, positions and spreads are in units of the layer's
width: `normal 0.5 0.1` is centered on the layer with a spread of a tenth of
its width.

A cell from xi_l to xi_r gets

    fbar = ( F(xi_r) - F(xi_l) ) / ( ( F(1) - F(0) ) * ( xi_r - xi_l ) )
    u_cell = ubar + du * ( fbar - 1 )

The differences of F telescope, so the cells' momenta add up to
`R0 * width * ubar` to round-off. F(0) and F(1) are coded exactly for the
[0, 1] distributions (0 and 1, not computed), so nothing drifts.

**Deck syntax,** two optional keys in a Layer block:

    xvel           = 2.0              # km/s: the layer's mean velocity
    xvel_profile   = beta 2 5         # the shape (uniform when absent)
    xvel_amplitude = 0.5              # km/s: du (xvel when absent)

    xvel_profile = linear 0.5
    xvel_profile = normal 0.5 0.15
    xvel_profile = split_normal 0.3 0.05 0.2
    xvel_profile = sinh_arcsinh 0.5 0.2 -0.8 1.0
    xvel_profile = cauchy 0.5 0.1

A stretching layer at rest on average, ends moving apart at 0.2 km/s:

    xvel           = 0.0
    xvel_profile   = linear 1.0       # f = 2 xi
    xvel_amplitude = 0.2              # u = 0.2 (2 xi - 1): -0.2 km/s at the
                                      # left face, +0.2 at the right

(With `xvel = 0` and no `xvel_amplitude`, du = 0 and the layer is at rest:
the shape needs an amplitude to act.)

The resolved deck prints both keys only for a non-uniform layer, so every
existing deck's screen output stays the same, byte for byte.

**Faces.** AV keeps its velocities at the faces. Each face gets the
momentum-weighted average of its two neighbor cells,

    u_face = ( M_left * u_left + M_right * u_right ) / ( M_left + M_right )

which is today's impact-face formula, applied everywhere a velocity changes.
It keeps `sum m_face * u_face = sum M_cell * u_cell` exact. Where both cells
have the same velocity, the face takes it directly (today's branch), so a
uniform layer gives exactly today's numbers. The impact-face count looks only
at faces between layers.

RS keeps its velocities in the cells: `u_cell` above goes straight into the
cell's slot. (To check while coding: the comment near maincode's section 5
says RS's starting averages are "the layer's xvel"; nothing in RS may assume
a uniform layer.)

**What does not change.** The time loop, both solvers, the EOS, spall, the
history file and the pictures. The 125 deck tests and the bit-for-bit OpenMP
and release tests must pass unchanged, which proves it.

## Checks and errors (deck errors, with the deck's line number)

- An unknown name, or the wrong number of parameters for the name.
- A parameter out of range: a, b, sigma, sigma_left, sigma_right, scale,
  delta, gamma must be > 0; |s| <= 1 (so f >= 0, a true density).
- `xvel_amplitude` without a non-uniform `xvel_profile` (it would do
  nothing).
- Too little probability on the layer: if F(1) - F(0) is below about 1e-12
  (a normal centered far off the layer, say), stop with "this profile puts
  almost nothing on the layer" rather than divide by it.

## Tests

**Unit test, `tests/test_dist.f95`** (math only, so it travels with the
module):

- Every distribution: F is 0 and 1 at the ends of its support (to round-off),
  F never decreases, and F(b) - F(a) matches a fine numerical integral of f
  wherever f is finite.
- Known values:
  - beta(1, 1) is uniform; beta(2, 1) has F = x^2; I_(1/2)(a, a) = 1/2.
  - normal: F(mu) = 1/2, F(mu + sigma) = 0.8413447460685429...
  - split_normal with equal spreads is normal; F(m) =
    sigma_left / (sigma_left + sigma_right).
  - sinh_arcsinh with eps = 0, delta = 1 is normal (location loc, spread
    scale); with eps = 0, F(loc) = 1/2 for any delta; changing the sign of
    eps mirrors it: F(loc + y; eps) = 1 - F(loc - y; -eps).
  - cauchy: F(x0) = 1/2, F(x0 + gamma) = 3/4.
  - linear: f(1/2) = 1 for every s.
- The kinetic-energy factor I2, the integral of f^2:
  - linear: 1 + s^2 / 3;
  - beta: B(2a - 1, 2b - 1) / B(a, b)^2 (for a, b > 1/2).
- dist_set rejects bad parameters.

**Deck tests:** each name read and echoed; each error above stops the run with
its message.

**History test:** a run with a non-uniform layer passes setup (so momentum is
exact), and frame 1's velocities match the analytic cell averages; the same
for a layer with `xvel = 0` and an amplitude (the stretching layer).

**Later, verification:** a linear compression ramp, against the shock
formation time from characteristics (to derive first, for the acoustic limit).

## Phases

1. **This round:** the module with all seven distributions (pdf, cdf, mean,
   support), the unit test, `xvel_profile` and `xvel_amplitude`,
   initialization, deck and history tests, and the documentation
   (input/README.md, the key reference block in the class deck).
2. **Next:** `dist_inv_cdf` for sampling. Closed forms for uniform, linear and
   Cauchy; the inverse normal cumulative distribution (one routine) gives
   normal, split normal and sinh-arcsinh in closed form; beta by Newton's
   method with bisection. Then random velocity draws.
3. **Later:** more distributions, and other uses (a density or energy
   profile, which would conserve mass or energy the same way).

## Decisions (Oct 22, 2026)

- **No `reverse` option.** Every shape in the catalogue leans either way
  through its own parameters.
- **Gamma, Weibull and log-normal wait** for a later round; split normal and
  sinh-arcsinh, whose skewness is a parameter of either sign, take their
  place.
- **Mean plus shape:** `u = ubar + du ( f - 1 )`, with `du` defaulting to
  `ubar`. Momentum stays exact for any `du`; a layer may be at rest on
  average and still stretch or squeeze; velocities may cross zero.

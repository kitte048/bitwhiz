# Method AV at a detonation and at a free surface (Nov 5, 2026)

What method AV does, measured against mesh, beside method RS (order 2) and
exact answers where there are any, so that its behavior is known rather than
removed. The script is `tests/verification/study_av.py` (its docstring
lists what it measures; about 15 minutes on 2 cores, `--quick` about 2), with
two decks of its own in `tests/verification/av_study/`.

## The standard (DK)

A burn model adding energy during the viscous work at the shock front is not
unusual; the production code shows similar behavior. So the question is not
"how do we remove the feature?" but "this is what the code does, imperfect
as it may be": what it does, how large, and whether it goes away as the mesh
refines. Burn controls (a threshold on the AV pressure, a shock counter)
would be deck keys, documented and verified like any other, so none without
strong cause. What is acceptable:

1. The code does what the equation sheet and the deck say, and nothing else.
2. The test is convergence, not perfection: the right answer as the mesh
   refines, with a measured error on a coarse mesh.
3. An error that is known is documented (here, `input/README.md`), not
   engineered away.
4. A code change only if AV fails to converge, or is plainly inconsistent.

All three studies below converge in that sense: no code change.

## A. The detonation: a weak detonation on a coarse mesh

Material X (the HVRB sheet): D_CJ = 7.49999 km/s, P_CJ = 25.0 GPa, the von
Neumann point P_VN = 35.7 GPa (the unreacted Hugoniot at D_CJ). Its steady
reaction zone is about 0.14 mm of initial coordinate (the sheet; measured
here, front to the first burnt-out cell at 400 zones/mm, 0.096 mm of the
compressed material, both methods): 3.5 cells at 25 zones/mm, 5 at the class
deck's 35, 7 at 50, 14 at 100, 28 at 200.

**G4's thick flyer at 3.00 km/s** (`hvrb/g3_poplt.deck`; a detonation that
runs near CJ to 20 mm). D fitted to the front (where P crosses P_CJ/2) over
10-20 mm; the plateau where P falls more than 0.5 GPa below RS2's profile at
400 zones/mm, within 2 mm behind the front, the front at 18 mm:

| Method | zones/mm | D (km/s) | D - D_CJ | deepest deficit | plateau width | spike |
|---|---|---|---|---|---|---|
| AV | 25 | 7.7268 | +3.02 % | 5.0 GPa | 1.40 mm | 39.0 GPa |
| AV | 50 | 7.5281 | +0.38 % | 2.2 | 0.33 | 38.1 |
| AV | 100 | 7.5156 | +0.21 % | 1.8 | 0.20 | 37.8 |
| AV | 200 | 7.5020 | +0.03 % | 0.8 | 0.01 | 37.2 |
| AV | 400 | 7.5015 | +0.02 % | 0.4 | 0 | 37.0 |
| RS2 | 25 | 7.5000 | 0.00 % | | 0 | 38.5 |
| RS2 | 50 to 400 | 7.5010-7.5016 | +0.01 to +0.02 % | | 0 | 36.9-38.6 |

(The +0.02 % both methods share is the fit, and the last of the flyer's
overdrive.) The class deck (`input/me697_hvrb_2p00.deck`), D over 5-9.6 mm,
decaying from its overdrive: AV 7.7267 km/s at 25 zones/mm, 7.5599 at 50,
7.5535 at 100, 7.5525 at 200, 7.5521 at 400; RS2 7.5516 to 7.5531 at every
mesh. AV's plateau, 0.29 mm at 25 zones/mm, is gone by 400.

**What it is.** In the class deck at its own 35 zones/mm (DK's observation):
the spike starts out attached to the release wave; from about 0.85 us a
plateau near 21 GPa, below P_CJ, opens a few cells behind AV's spike and
widens (3 cells, then 5, then 8 by 1.45 us); lam reaches 1 within 2-3 cells,
inside AV's smeared shock. AV's front runs at 7.68 km/s over 0.8-1.5 us
(RS2: 7.56), and the weak branch at 7.68 km/s (the Rayleigh line on the
products' Hugoniot) is 20.5 GPa: AV's plateau, 20.6-20.9 GPa. A weak
detonation: the flow leaves the reaction zone faster than sound in the
front's frame, so the release wave falls behind and the plateau widens.
The likely mechanism is the energy released inside the viscous shock, so
the material never passes the von Neumann point; spurious weak detonations
and wrong front speeds from stiff reactions on a coarse mesh are a known
property of shock-capturing schemes (to cite after checking: Colella, Majda
and Roytburd, 1986; LeVeque and Yee, 1990). RS's shock is 1-2 cells sharp,
and its burn follows it.

**The spike** (the largest P at the front) is above P_VN on every mesh, in
both methods, and falls toward it as the mesh refines (AV 39.0 to 37.0 GPa,
25 to 400 zones/mm): the reaction zone's start, resolved by a few cells.
Reported, not studied further.

**So:** AV converges to CJ. Its error on a coarse mesh is a fast front on a
weak detonation: +3 % at 3.5 cells across the reaction zone, +0.4 % at 7,
+0.2 % at 14, within 0.03 % from 28 (200 zones/mm). RS2 gets D right on
every mesh tried, from 3.5 cells.

## B. The free surface: a transient of fixed height and vanishing width

**The square shock** (`av_study/fs_square.deck`): an Al flyer at 2.00 km/s on
an Al target, u_p = 1.00 km/s exactly. Exact free-surface velocity, u_p plus
the release along the isentrope from the shocked state (40 digits, in
`study_av.py`): **2.0062468 km/s**.

| Method | zones/mm | peak | above exact | plateau error | time above +1 % | its integral |
|---|---|---|---|---|---|---|
| AV | 25 | 2.1268 | 6.0 % | -0.0053 % | 15.7 ns | 1.4e-3 mm |
| AV | 100 | 2.1328 | 6.3 % | -0.0009 % | 4.6 ns | 3.5e-4 mm |
| AV | 400 | 2.1246 | 5.9 % | -0.0001 % | 1.0 ns | 8.7e-5 mm |
| AV | 1600 | 2.1269 | 6.0 % | 0.0000 % | 0.24 ns | 2.2e-5 mm |
| RS2 | 25 | 2.0140 | 0.39 % | +0.0089 % | 0 | 2.6e-4 mm |
| RS2 | 1600 | 2.0136 | 0.37 % | 0.0000 % | 0 | 4.0e-6 mm |

AV's free surface overshoots exact by 6 % on every mesh, for a time that
halves with each refinement (about 2.5 cells' shock transit): the integral,
the extra travel, is first order (ratios 0.49-0.51 per halving), and the
plateau converges to exact. RS2 does the same at 0.37 %. The end node has
half a cell's mass and takes the end cell's full P + q: it rings once on
the reflection. **The ramp** (`input/ramp_linear.deck`): the same transient,
on a shock the ramp has steepened into. The free surface's peak, written
every cycle, is AV 2.2825 / 2.2946 / 2.2962 / 2.2985 km/s at 25 / 100 / 400
/ 1600 zones/mm and RS2 2.0889 / 2.1126 / 2.1187 / 2.1202: two limits, 8 %
apart, in a window that shrinks to nothing (its rise 22 ns at 25 zones/mm,
0.3 ns at 1600), with the velocities after it the same to 1e-4 km/s.
RS2's, less its own 0.37 %, is the physical peak.

**So:** AV's free-surface peak is not a measurement, at any mesh; its
plateau, and everything after the transient, is. The transient lasts
about 2.5 cells' transit: 16 ns at 25 zones/mm, which a velocimeter would
see; 1 ns at 400.

## C. The end cell: the sheet's kinetic energy at a blow-off

`av_study/burn_release.deck`: the class stack at 1.00 km/s with no window,
so Material X, partly burnt, releases at a free surface:

| Method | zones/mm | T min | guard cell-steps | the coldest cell |
|---|---|---|---|---|
| AV | 25 | -1465 K | 1273 | the end cell (lam 2.6e-3) |
| AV | 50 | -968 K | 2575 | the end cell (lam 8.8e-4) |
| AV | 100 | -953 K | 5189 | the end cell (lam 3.2e-4) |
| AV | 200 | -1092 K | 10426 | the end cell (lam 1.4e-4) |
| AV | 400 | -1186 K | 20913 | the end cell (lam 5.8e-5) |
| RS2 | 25 to 400 | 8.6 to 9.4 K | 0 | interior, burnt |

On every mesh, AV's coldest cell is the free-surface end cell, barely burnt
and blown off (to 1/500 of its density at 50 zones/mm), near -1000 K, and
every guard step is that one cell. Its own -P dv is about 0, yet its e falls:
the neighbor's face work (+8.12 kJ/g after 3.39 us, 50 zones/mm) is outrun
by the growth of its cell-centered kinetic energy, (1/2) ubar^2 (-9.51),
which the sheet's energy update takes from e (the form that conserves total
energy exactly; v1.3.2 makes it exact at a free surface). It does not
shrink with the mesh, but it is one cell, whose mass is 1/N of the layer's.
Total energy is conserved to round-off throughout.

**So:** a property of the sheet's energy update at an extreme blow-off, in
one cell: documented. A compatible energy update (each cell charged exactly
-(P + q) dV; Caramana et al., J. Comput. Phys. 146, 1998) would remove it,
but changes the class sheet's scheme: not now.

## Decided (Nov 5)

- No code change. AV is the sheet's scheme, and it converges.
- `input/README.md` says what to expect: the resolution AV needs across a
  reaction zone, and that a free-surface peak with AV is a transient.
- `study_av.py` keeps this as a regression guard: its checks are of
  convergence, their tolerances set from these runs (two of them restated
  at fixed meshes after a first run, so they mean the same with
  `--quick`); the artifacts' sizes are reported.
- Revisit if a check fails, if AV ever stops converging, or if the
  students' sheet changes its energy update.

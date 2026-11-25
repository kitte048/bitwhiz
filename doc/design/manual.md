# The bitwhiz manual (approved Nov 8, 2026)

Status: **approved** (DK, Nov 8, 2026). Decisions marked **DK** are
David's; the rest were proposals, approved with the note.

## The decision (DK)

- bitwhiz gets its own manual: one document that says what the code
  computes and why, for anyone who finds the repository, written to its own
  standard rather than to the course's.
- The text-to-equation ratio targets for the course's equation sheets are
  dropped. The sheets stay as they are: terse reference sheets for the
  course.
- The course's equation sheets go back to the course folders. The repository
  stops carrying frozen copies of them in `doc/` (when: see "The equation
  sheets leave `doc/`" below).
- Release 1.5.0 is the manual's. It writes up the equations of all six burn
  models in `burn_models.md`: HVRB and ThermalCascade (with the lead shock)
  as built, and FlashFire, StochasticIgnite, HALO and CLAUDE from the design
  note, each marked **under development**. FlashFire, the next model built,
  moves to 1.6.0.

## Why

bitwhiz has outgrown the class project ("open source burn models"). Its
description is spread over five frozen sheets, four design notes, the input
README and the module headers, and only the people who wrote them know how
they fit together. The v1.4.0 review (`audits/v1.4.0_fable-5.1/`) found its
two main documentation problems in that spread: a frozen sheet that says the
code does something it stopped doing in 1.3.2 (F-01), and stale numbers in a
design note (F-08). A frozen course sheet is the wrong place for the code's
current behavior, and a reference sheet is too terse to be its only
description (F-02).

## Who owns what

Each fact has one owner. Everything else points to it instead of repeating
it.

| Document | Owns | Changes |
|---|---|---|
| The manual (`doc/manual/`) | what the code computes and why: the equations as built, their assumptions, the numerical methods, the verification standard | with every release that changes what the code computes |
| Design notes (`doc/design/`) | the record of decisions: options weighed, what DK chose, the "as built" logs, measured studies | appended as work happens; not rewritten |
| `input/README.md` | the deck: every key, its default, its checks, examples | with every key |
| Module headers | the routine: its interface, its numerics, its NOTEs | with the code |
| `audits/` | independent reviews, archived as delivered, and what became of their findings | with each review |
| Course `Equation_Sheets/` | the course's reference sheets | the course's business, not the repository's |

Two rules follow:

1. **The manual does not copy the deck reference.** Each chapter ends with a
   table from its symbols to their deck keys, pointing to `input/README.md`.
2. **The manual gives a measured number only with the commit it was measured
   at** ("D within 0.08 % of D_CJ at 200 zones/mm, `cf0eab0`"), or points to
   the study that measures it. That is how F-08 happened.

## Form

- LaTeX, in the repository: `doc/manual/bitwhiz_manual.tex`, one `.tex` per
  chapter, figures in `doc/manual/figures/` (TikZ, as the sheets' are; the
  sheets' figure sources can be reused here, since the manual owns its
  copies).
- Built by `make manual`. The PDF is attached to each GitHub release and to
  the nanoHUB release, named for the version (`bitwhiz_manual_1.5.0.pdf`).
  It is not committed (a build product, like the sheets' `.aux`).
- Its own notation, chosen for the code: symbols follow the deck and the
  modules where they can (`lam`, `P_s`, `HT`). An appendix maps it to the
  course sheets' notation, for students who know those.
- Written for students and the public: full sentences, derivations where they
  help, no ratio targets. Open literature only, as everything in the
  repository is; lab-restricted models are not named.

## Keeping it true to the code

- **Trace tags.** Every numbered equation that the code implements carries a
  tag naming its routine and its test, such as `tcas_mod.f95: tc_rate;
  test_tcas 1`. A short script (`tests/manual_check.py`) checks that each
  tagged routine and test still exists, and runs in `make test`. It catches
  a renamed or deleted routine, not a wrong equation.
- **Checked against.** Each chapter's first page names the commit its
  equations were last checked against, as `doc/README.md` does for the
  sheets now. The checking is the same as for the sheets: equations
  verified by script (sympy or mpmath), the 50-digit reference scripts
  pointing to manual sections.
- **Done means documented.** `CONTRIBUTING.md` gains one line: a change to
  what the code computes is not done until its manual section is. That
  includes each new burn model. `RELEASING.md` gains: build the manual, check
  its "checked against" commits, attach the PDF.

## Outline (about 40 to 80 pages when complete)

1. Overview: what bitwhiz is, what it is for, a first run
2. The Lagrangian equations and the mesh
3. Method AV: artificial viscosity, boundaries, the time step (absorbs the AV
   sheet; closes F-01)
4. Method RS: the acoustic Riemann solver, first and second order (absorbs
   the RS sheet)
5. Materials: Mie-Grüneisen, the cold curve and temperature, ideal-gas
   products
6. The burning cell: the mixture closure, the solid held where it pulls,
   how a burn model plugs in (the burn table)
7. Burn models, a section each: HVRB (absorbs the HVRB sheet), the lead
   shock, ThermalCascade (absorbs both sheets; closes F-02); then FlashFire,
   StochasticIgnite, HALO and CLAUDE, under development (DK), each section
   completed as its model is built
8. Verification: the standard (bit for bit, 50 digits, convergence), what
   each test and study shows, pointing to `tests/` and the studies for the
   numbers

Appendices: notation (with the map to the course sheets), symbols to deck
keys, references, version history.

## Milestones

| | What | With |
|---|---|---|
| M0 | this note approved | now |
| M1 | the skeleton builds (`make manual`, `manual_check.py`); chapters 6 and 7 complete, chapter 7 with all six burn models (four under development) | 1.5.0 (DK) |
| M2 | chapters 2 to 5 complete; the frozen sheets leave `doc/` (below) | a release after 1.5.0 |
| M3 | chapters 1 and 8 and the appendices: manual 1.0 | before the JOSS submission |

After M3, each release updates the chapters it touches.

## The equation sheets leave `doc/`

The sheets already live in the course's `Equation_Sheets/`, their source of
record; leaving means removing the frozen copies (and their figures) from
`doc/`, and `doc/README.md` with them. Old tags keep them.

Proposed: they leave at M2, when the manual covers what they cover, not
before. Until then:

- The ThermalCascade and Lead Shock sheets are published only in this
  repository (`doc/README.md`); removed now, the public would have no
  description of those models but the design note.
- Code and tests cite the sheets as their definitions: `tests/
  hvrb_reference.py`, `tests/test_hvrb.f95`, `tests/verification/
  compare_hvrb.py` (`doc/HVRB_Eqns_v8`), and comments in `burn_mod`,
  `hvrb_mod`, `mix_mod` and `prod_mod`, and in four decks
  (`input/me697_hvrb_2p00.deck`, `tests/verification/av_study/
  burn_release.deck`, `tests/verification/hvrb/g2_react.deck` and
  `g3_poplt.deck`). Each is repointed to its manual section as the sheets
  leave, so no test is left citing a file that is gone.
- `README.md`, `TODO.md`, `input/README.md` and `doc/design/` mention them
  too, and are repointed the same way.

The gold-standard data's README (`tests/verification/hvrb/README.md`) cites
the HVRB sheet's v3, as the data was computed from it. That is history and
stays.

## Open questions for DK

1. The title: "bitwhiz: Theory and Verification Manual", or another? Okay (DK)
2. The license for the manual's text: the code's Apache 2.0, or CC BY 4.0
   (the usual license for documentation)? Apache 2.0 (DK)
3. When the sheets leave `doc/`: at M2 (proposed), or now? M2 (DK)
4. Should CI build the PDF on every push (it then never breaks, but CI
   installs TeX, a few minutes each run), or only `make manual` at release?
   At release only (DK)
5. Authors: D. E. Kittell (with Claude), as the code's headers have it? 
   Yes (DK)

## As built: M1, the skeleton and the burn chapters (Nov 9, 2026)

`doc/manual/` (its `README.md` has the conventions): `bitwhiz_manual.tex`
and a file per chapter, chapters 6 (the burning cell) and 7 (the six burn
models) written and the rest outlined (`\tocome`); the figure of HVRB's
topology as the manual's own copy; `checks/ch6_closure.py` and
`checks/ch7_models.py`, every closed form of the two chapters derived from
its definitions (sympy, mpmath). `make manual` builds the PDF (31 pages);
`tests/manual_check.py` checks its trace tags (26 so far) and runs in
`make test`. `CONTRIBUTING.md` (done means documented) and `RELEASING.md`
(the PDF with each release) gained their lines. Read against the code by an
independent reviewer before release: two errors (the hold's place in the
cycle, a test described wrongly) and two unsupported statements fixed, the
rest clarified.

## Revised outline (DK, Nov 19, 2026)

After 1.9.0 and the v1.9.0 assessment (`audits/v1.9.0_fable-5.2/`), DK
widened the manual (Nov 19): the theory first, drawn from the ME 697 course
(its units, equation sheets and TikZ figures, DK's own), and the numerical
methods derived from it, step by step; and the Hugoniot data for the
elements as an appendix to write decks from. The code is still the truth:
the theory chapters derive, the method chapters state what the code does,
with trace tags.

| | Chapter | Drawn from |
|---|---|---|
| 1 | Overview | |
| 2 | One-dimensional continuum mechanics: uniaxial strain, hydrodynamics only, the balance laws, the mass coordinate, entropy, small disturbances, interfaces and boundaries, the mesh at t = 0, units | Units 3 and 4 |
| 3 | Shock waves: the shock of finite thickness, the jump conditions, Rayleigh line and Hugoniot, the entropy inside the front, impedance matching, and the step to the numerics | Units 3 to 6 |
| 4 | Method AV, derived from chapters 2 and 3 (absorbs the AV sheet) | the AV sheet, the Lecture 19 addendum |
| 5 | Method RS, from the Riemann problem (absorbs the RS sheet) | Units 7 and 8, the RS sheet |
| 6 | Materials, with choosing a material's constants | the Hugoniot data sheet |
| 7 | The burning cell (chapter 6 until now) | as written |
| 8 | Burn models (chapter 7 until now) | as written |
| 9 | Verification | |
| A-D | Notation; deck keys of the burn; the history of this manual; Hugoniot data for the elements | the course's Hugoniot database |

Chapters 6 and 7 became 7 and 8 (files and check scripts renamed with
them: `checks/ch7_closure.py`, `checks/ch8_models.py`); labels are by name,
so cross-references did not move. Where the code, the README and the
module headers cited "chapter 7", they now cite chapter 8. The records
above (M1, the design notes' "as built" logs) keep the numbers of their
day.

**Working rhythm (DK).** About 10 pages of polished text per round, the
proofreading budget; stubs (`\tocome`) do not count. Each round: the
chapter drafted, its derivations checked by a script in `checks/`, the PDF
read page by page, then DK's read. An independent read against the code
before a release, as M1 had.

**Out of scope for good (DK, Nov 19): strength.** The manual says so in
chapter 2 (`TODO.md`, Priorities).

Round 1 (Nov 19): chapter 2 written (7 pages,
`checks/ch2_continuum.py`), chapter 1's plan of the book, the stubs of
chapter 3 and appendix D, the notation of chapter 2 in appendix A.
Approved by DK with his comments applied (open source burn models defined,
the diffusion argument by time scales, `% SCOPE:` markers), `63ebbdc`.

Round 2 (Nov 19): chapter 3, shock waves (6 pages,
`checks/ch3_shocks.py`): the steady front by the transport theorem, the
jump conditions, the Rayleigh line and the Hugoniot (bitwhiz's
U_s(eta)), the entropy inside the front, shock impedance, impedance
matching on the class problem (the gold standard's 10.736 GPa), and the
front's inside as the step to the numerics. Figures: the course's RTT and
Rayleigh figures, and a new P-u figure of the class problem.
Approved by DK with eleven comments applied (the opening, mean free
paths, mass flux as mdot'' as in the course, no defined-as signs), `11ecf43`.

Round 3 (Nov 19): chapter 4, method AV (6 pages, `checks/ch4_av.py`):
the staggered mesh and the leapfrog, momentum and the moving mesh, the
energy update and its exact conservation (checked in rational
arithmetic), its split into -(P + q) dV and a remainder that explains
`av_study.md`'s end-cell temperature, the viscosity as a numerical shock
width (measured: 2.1 to 3.2 cells at BQ = 2), the time step, one cycle,
and what AV does at a free surface and a detonation. Figures: the Hydrocode
sheet's three.
DK's read of chapters 1 to 4 from the start (Nov 24): wording and style
only, nothing substantive; applied with round 3 (fewer colons, more
semicolons with a transition, run-on sentences split, the Lagrangian
equations behind eqs. 4.3 and 4.4 shown).

Round 4 (Nov 24): chapter 5, method RS (8 pages, `checks/ch5_rs.py`):
the equations as fluxes in h and the finite-volume update; the pressure
equation, the acoustic system's eigenvalues and Riemann invariants; the
Riemann problem and its acoustic solution (equal impedances as a built-in
linear viscosity, B_L = 1/2 with no switch; the impact as the acoustic
impedance match, 6.29 against 10.74 GPa on the class problem's first step;
why conservation still gives the right jumps); contacts, free surfaces and
zero impedance; first order (exact conservation in rational arithmetic;
measured: 3.7 to 8.8 cells, wider for weaker shocks); MUSCL-Hancock with
Van Leer's limiter (1.5 to 2.6 cells); the time step M/Z; one cycle; what
RS does, measured. Figures: the Unit 7 sheet's Riemann schematic, and a
new one of the order-2 reconstruction. References: Godunov (1959), van
Leer (1979). Written in DK's style from chapter 5 on (semicolons with a
transition, no run-ons, each word's referent named).
DK's read (Nov 25): style and one figure; applied. The sheet's path
dropped from the chapter's opening (the manual supersedes the sheets);
the flyer's velocity u_0; the reconstruction's sentence on V and the
cycle's list reworded; Fig. 5.1 redrawn for the manual with W as the
state and the star states as the text writes them, panel (a) with dashed
wedges (a wave whose type is not yet known) and panel (b) with the single
lines of the acoustic problem, and a three-entry legend. The middle
relation of eq. 5.7, dP + Z^2 dV = 0, checked: dP = -(rho c)^2 dV, or
dP = c^2 drho (also chapter 2's eq. 2.20).

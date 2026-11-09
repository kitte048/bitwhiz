# The bitwhiz manual (proposed Nov 8, 2026)

Status: **proposed.** Decisions marked **DK** are David's (Nov 8, 2026);
the rest are proposals for his approval.

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
   shock, ThermalCascade (absorbs both sheets; closes F-02), then one per
   new model
8. Verification: the standard (bit for bit, 50 digits, convergence), what
   each test and study shows, pointing to `tests/` and the studies for the
   numbers

Appendices: notation (with the map to the course sheets), symbols to deck
keys, references, version history.

## Milestones

| | What | With |
|---|---|---|
| M0 | this note approved | now |
| M1 | the skeleton builds (`make manual`, `manual_check.py`); chapters 6 and 7 complete (the burn models, the newest and least documented) | 1.5.0 |
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

# Contributing to bitwhiz

Thank you for your interest. bitwhiz is maintained by D. E. Kittell; it is the
reference hydrocode for a course, so it changes carefully, and every change is
reviewed, built and tested before it is merged.

## Questions and bug reports

Open an issue on GitHub (https://github.com/kitte048/bitwhiz/issues). For a
bug, please include:

- the version line from the run's banner (or `git describe --tags --dirty`),
  your compiler (`gfortran --version`) and your operating system;
- the deck that shows it (or the smallest one you can make), and what you
  expected to see;
- what happened: the screen's last lines, and the heartbeat file if the run
  stopped.

For the nanoHUB tool (https://nanohub.org/tools/bitwhiz), use nanoHUB's own
support for the tool page, or open an issue here if the problem is in the code.

## Contributing a change

Please open an issue first for anything beyond a small fix, so the approach
can be agreed before the work. Then, on a branch of your own:

1. **Keep `make test` passing** (unit, deck, OpenMP and history-file tests,
   about 4 minutes on 2 cores), and `make release` (the optimized build must
   give the debug build's results bit for bit). Both builds compile with zero
   warnings under the strict flags in the `Makefile`; keep it that way.
2. **Physics and numerics follow a written source.** Each method follows a
   frozen equation sheet in `doc/`, and larger changes start with a design note
   in `doc/design/`, agreed before the code. A change to the physics comes
   with a check: a unit test against an independent reference (the
   `tests/*_reference.py` scripts compute theirs at 50 digits), an exact
   solution, or the reference data in `tests/verification/`.
   **A change to what the code computes is not done until its manual
   section is** (`doc/manual/`, `doc/manual/README.md`): the equations as
   built, their trace tags (`tests/manual_check.py`), and the chapter's
   "checked against" line.
3. **Results stay bit for bit** with any number of OpenMP threads, and a deck
   that does not use a new feature gives the same bits as before it.
4. **Follow the code's style:** Fortran 2018 with `implicit none`, the house
   layout and comments (each file's header says what it does and keeps a
   record of revisions, dated, with a line for the change), and American
   spelling. A new deck key is documented in `input/README.md`, with a test
   deck in `tests/decks/` for its errors.
5. **Say how the change was made.** If you used AI tools (code, tests or text),
   say which and for what in the pull request, as the README's
   Acknowledgements do for bitwhiz itself.

### Contributing a burn model

bitwhiz hosts **open source burn models** (README, "Open source burn models").
A new model is welcome if its definition comes from the open literature or is
your own, and is neither proprietary nor export-controlled: anything that can
not be published openly does not belong here. It joins the others the way
ThermalCascade did (`doc/design/burn_models.md`, steps 3 to 5): an equation
sheet first; a row in the burn table (`src/modules/btab_mod.f95`: its name,
its deck keys, one meaning each, and its per-cell slots) and a module of its
own for its rate; the shared closure, products and, if it needs one, the lead
shock; its section in the manual's burn-model chapter (`doc/manual/`); and
its tests: a unit test against a 50-digit reference, its inert
limit, decks for its errors, and a study of its detonation against mesh, AV
and RS.

Contributions are made under the project's license, the Apache License 2.0
(`LICENSE`, section 5).

## Releases

Versions are tagged `vMAJOR.MINOR.PATCH` on `main` and exported to nanoHUB by
the maintainer; `RELEASING.md` has the process.

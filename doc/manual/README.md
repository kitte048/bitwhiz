# doc/manual

The bitwhiz manual: what the code computes and why, for anyone who finds
the repository. The plan, what owns what, and the milestones are in
`doc/design/manual.md` (approved Nov 8, 2026).

## Build

From the repository's top folder:

    make manual

writes `doc/manual/bitwhiz_manual.pdf` (pdflatex: the figures first, then
three passes), with `git describe` on every page. Needs a TeX distribution
with `tcolorbox`, `pgfplots`, `xurl` and `cleveref` (TeX Live and MacTeX have
them). The PDF is not kept in git; it is attached to each release
(`RELEASING.md`).

## Layout

| Path | What |
|---|---|
| `bitwhiz_manual.tex` | the preamble, the macros below, the title page, the chapter list |
| `chapters/ch*.tex`, `chapters/app*.tex` | one file per chapter and appendix; `references.tex` the bibliography |
| `figures/*.tex` | each figure's source (standalone TikZ/pgfplots), built to PDF by `make manual` |
| `checks/*.py` | the manual's closed forms derived from their definitions (sympy, mpmath): `python3 doc/manual/checks/ch6_closure.py` prints `ok` per check |

## Writing here

- **Trace tags.** Under every equation the code computes, put
  `\trace{file}{routines}{tests}`: the source file under `src/`, the
  routines that compute it, the tests that check it (comma-separated; a
  test is a file under `tests/`, `test_x` meaning `tests/test_x.f95`).
  `tests/manual_check.py` (in `make test`, and first in `make manual`)
  fails if a routine or a test named in a tag is gone. It checks names, not
  equations: the equations are checked by `checks/` and by the tests.
- **Checked against.** A finished chapter opens with
  `\checkedagainst{version (commit)}{how}`. Change it when the chapter is
  checked against a newer commit.
- **Numbers.** A measured number goes with the commit it was measured at,
  or points to the study that measures it.
- **Not yet built.** A planned model or feature goes in its section with
  the `underdev` box at the top, and no trace tags (there is no code to
  point at). A chapter still to be written is a `\tocome{...}` box.
- **Owners.** The manual does not copy the deck reference
  (`input/README.md`) or the design notes' records; it points to them.
- **Style.** Student-facing and complete: full sentences, derivations where
  they help, American spelling, bitwhiz's units. Open literature only.
- **Symbols.** Defined once in the preamble where they recur (`\thv` for
  vartheta, `\Ps`, `\Pg`, ...) and listed in Appendix A.

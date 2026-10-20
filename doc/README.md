# doc

The equation sheets that bitwhiz is checked against, one per solution method.
These are **frozen copies**. The source of record is the course's
`Equation_Sheets/` folder, where the sheets are drafted and versioned; a sheet
is copied here only once it has been checked against the code, and the copy is
never edited here. A newer sheet arrives as a new file with a higher version
number.

| Sheet | Method | Status | Checked against |
|---|---|---|---|
| `Hydrocode_Eqns_v4` (`.pdf`, `.tex`) | AV, artificial viscosity (`method = AV`) | frozen, Oct 19, 2026 | bitwhiz `311bf6d` (solver source unchanged through `12e5d9f`) |
| Method RS sheet | RS, Riemann solver (`method = RS`) | in draft, not here yet | |

## What each file is for
- **`.pdf`**: to read. This is the published look, the same file as in
  `Equation_Sheets/Hydrocode_rev-1/`.
- **`.tex`**: to search, diff and quote exactly. The equations are plain text
  here, so a person or an AI tool can read them without the errors that come
  from pulling math out of a PDF.
- **`hc_*_v1.tex` and `.pdf`**: the sheet's three figures (TikZ sources and
  the PDFs the sheet includes), so the sheet builds in this folder:

      pdflatex Hydrocode_Eqns_v4.tex     (twice, for the figure numbers)

  The `.aux`, `.log` and `.synctex.gz` files that writes are ignored by git.

## Reading a sheet next to the code
Plain boxes are the class project's rules. Boxes titled **bitwhiz:** say what
the code does beyond them. The last box, "Where This Lives in the Code", maps
each step to its routine and each symbol to its database slot. The code's
comments cite the sheet by step ("equation sheet, Step 1").

# doc

The equation sheets that bitwhiz is checked against: one per solution method,
one per material model that has a sheet, and the lead shock that some burn
models share. These are **frozen copies**. The
source of record is the course's `Equation_Sheets/` folder, where the sheets
are drafted and versioned; a sheet is copied here once it has been checked
against the code (or, for a model still to be built, as the reference the code
will follow), and the copy is never edited here. A newer sheet arrives as a new
file with a higher version number.

| Sheet | Method | Status | Checked against |
|---|---|---|---|
| `Hydrocode_Eqns_v4` (`.pdf`, `.tex`) | AV, artificial viscosity (`method = AV`) | frozen, Oct 19, 2026 | bitwhiz `311bf6d` (solver source unchanged through `12e5d9f`) |
| `Hydrocode_RS_Eqns_v4` (`.pdf`, `.tex`) | RS, Riemann solver (`method = RS`, `order = 1` or `2`) | frozen, Oct 20, 2026 | bitwhiz `f16485c` |
| `HVRB_Eqns_v8` (`.pdf`, `.tex`) | HVRB reactive burn: rate law, Mie-Grüneisen reactant, ideal-gas products, density-temperature closure (`burn = hvrb`) | frozen, Nov 4, 2026, ahead of the code | bitwhiz `eeb3cf7` (1.3.0), and the gold-standard reactive data G2-G5 (`tests/verification/compare_hvrb.py`); the solid held where it first pulls (1.3.3) goes beyond the sheet (`design/materials.md`) |
| `ThermalCascade_Eqns_v2` (`.pdf`, `.tex`) | ThermalCascade reactive burn: the rate law as proposed and as repaired, gated by the lead shock (`burn = thermalcascade`); its products and closure are HVRB's | frozen, Nov 7, 2026 | bitwhiz `58a5392` (1.4.0's code): the rate and its repairs in `src/modules/tcas_mod.f95`, the gate in `burn_mod.f95` (`cell_burn`) |
| `LeadShock_Eqns_v1` (`.pdf`, `.tex`) | the lead shock (Menikoff and Shaw's detector): what it adds, the Hugoniot function and its behavior in a smeared shock | frozen, Nov 7, 2026 | bitwhiz `58a5392`: the Hugoniot function in `src/modules/lshk_mod.f95` (`ls_h`; `tests/test_lshk.f95`, check 1); the rules for finding the shock on a mesh are in `design/burn_models.md`, "As built: step 4" |

The ThermalCascade and Lead Shock sheets are not class-project sheets (their
headers read **bitwhiz:**): the burn models after HVRB are for this public
repository, written for students who find them. They are published only here,
and both are early versions (the rate law and the Hugoniot function so far;
the rest, from the design note, to come in later versions).

The HVRB sheet is the one published to the class as
`Class_Project/HVRB_Eqns_rev-0.pdf` (the same file as `HVRB_Eqns_v8.pdf`).
The gold-standard reactive data (`tests/verification/hvrb/`, sets G2-G5) was
computed with these inputs: its README cites the sheet's v3, and the
Material X parameters (P_R, Z_R, M_R, X_R, P_I, tau_0, C_V, T_0), gamma =
2.60 and Q = 4.8828 MJ/kg are the same in v3 and v8 (v4 to v8 changed
wording, citations, the T-free form of the closure and the sound-speed box,
not the model or its constants).

## What each file is for
- **`.pdf`**: to read. This is the published look, the same file as in
  `Equation_Sheets/Hydrocode_rev-1/` (AV),
  `Equation_Sheets/Hydrocode_RS_rev-0/` (RS),
  `Equation_Sheets/HVRB_rev-0/` (HVRB),
  `Equation_Sheets/ThermalCascade_rev-0/` (ThermalCascade) or
  `Equation_Sheets/LeadShock_rev-0/` (the lead shock).
- **`.tex`**: to search, diff and quote exactly. The equations are plain text
  here, so a person or an AI tool can read them without the errors that come
  from pulling math out of a PDF.
- **`hc_*_v1.tex` and `.pdf`**: the AV sheet's three figures (TikZ sources
  and the PDFs the sheet includes); **`riemann_schematic_v5.tex` and `.pdf`**:
  the RS sheet's one figure; **`hvrb_topology_v1.tex` and `.pdf`**: the
  HVRB sheet's one figure. So every sheet builds in this folder:

      pdflatex Hydrocode_Eqns_v4.tex     (twice, for the figure numbers)
      pdflatex Hydrocode_RS_Eqns_v4.tex
      pdflatex HVRB_Eqns_v8.tex          (twice, for the citations)
      pdflatex ThermalCascade_Eqns_v2.tex (twice, for the citations)
      pdflatex LeadShock_Eqns_v1.tex     (twice, for the citations)

  The `.aux`, `.log` and `.synctex.gz` files that writes are ignored by git.

## Reading a sheet next to the code
In the class project's sheets, plain boxes are the project's rules, and boxes
titled **bitwhiz:** say what the code does beyond them; the sheets headed
**bitwhiz:** are the code's own throughout. The last box, "Where This Lives in
the Code", maps each step to its routine and each symbol to its database slot.
The code's comments cite the sheet by step ("equation sheet, Step 1").

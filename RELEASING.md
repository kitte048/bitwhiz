# Releasing bitwhiz

How a version of bitwhiz is made and reaches nanoHUB: the maintainer's
process (moved here from the README, Nov 5, 2026, unchanged but for the
note on the tool's source at the end).

bitwhiz runs on nanoHUB as the tool **bitwhiz**
(https://nanohub.org/tools/bitwhiz): a Jupyter notebook in front of the
optimized executable. The tool has its own git repository on nanoHUB (cloned
here as `~/Documents/Academic/bitwhiz`), with the notebook, the
`middleware/invoke` script that starts it, and a small `src/Makefile` around a
copy of this code in `src/bitwhiz/`.

**The rule: changes flow one way.** Code is changed here, never in the nanoHUB
copy:
```
fix on main  ->  make test, make release  ->  tag vX.Y.Z  ->  export to the
nanoHUB clone  ->  one push  ->  nanoHUB installs it  ->  test and approve
```
- **Branches.** `main` is the release line: every tag, and so every nanoHUB
  version, is a commit on it (the line was `shock` until Nov 5, 2026, when
  `main` was brought up to it). New work goes on its own branch (as the
  velocity profiles did on `distributions`, released in 1.1.0), which takes
  fixes from `main` by `git merge main`, goes back into `main` when it is
  finished, and is then deleted.
- **Tags** are `vMAJOR.MINOR.PATCH`: PATCH for fixes (v1.0.2), MINOR for new
  features (v1.1.0). The banner prints the tag: here through `git describe`,
  on nanoHUB through the `VERSION` file the export writes. There is no
  v1.0.1 here: it was a build fix made in the nanoHUB clone during the first
  install (Oct 23, 2026), never published, and folded into v1.0.2 the same
  day; it is why changes now flow one way. The versions published on
  nanoHUB are 1.0.2, 1.0.3, 1.1.0, 1.2.0, 1.3.0, 1.3.4 (approved Nov 6,
  2026; 1.3.1 to 1.3.3 reached nanoHUB in it) and 1.4.0 (published Nov 9,
  2026).
- **Export** with `sh src/utils/export_nanohub.sh vX.Y.Z
  ~/Documents/Academic/bitwhiz`: it copies exactly that tag into the clone's
  `src/bitwhiz/` (no `doc/`, and none of the gold-standard data in
  `tests/verification/inert_gauges/` and `hvrb/`), writes `src/bitwhiz/VERSION` with the tag, copies
  the decks and `input/README.md` into the clone's `examples/` and `VERSION`
  into its `bin/` (an installed tool's `src/` is not readable by its users),
  lists files the tag no longer has, and prints the commands to commit, tag and
  push. Then, in the clone, run those commands.
- **Push once.** Send the commit and its tag in one
  `git push origin master vX.Y.Z`, with git's credential helper set
  (`git config --global credential.helper osxkeychain`). In Oct 2026
  nanoHUB blocked this machine's address for hours after git pushes
  (ticket #516409): its server logged each push first as refused (Apache's
  AH01797) and then allowed it by another rule, and its fail2ban read the
  refusal as an attack. nanoHUB corrected fail2ban (Nov 10, 2026), so pushes
  should no longer be blocked; one push per release, with its tag, stays the
  habit.
- **Install.** On the tool's status page, follow the link **"Wait! I've made
  more changes"** (for a tool already installed or approved; it tells nanoHUB
  that new code is in the repository), or mark the code uploaded (status
  Uploaded) with a short note; nanoHUB's staff run `make install` in the tool's
  `src/` and set it to Installed. Check what was installed from a notebook cell,
  `!ls -la /apps/bitwhiz/dev /apps/bitwhiz/dev/bin` (`dev` points to the
  newest revision, e.g. `r5`; its `bin/` must hold `bitwhiz`), then launch the
  tool fresh and test it: Run, Redraw pictures only, the movie (it plays,
  and Files lists the .mp4, not its frames), an error on purpose, the
  history plot. Approve it on the status page when it works.
- **The manual.** Before tagging, check the "checked against" line of
  every chapter the release touches (`doc/manual/README.md`), then, at the
  tag, `make manual` and attach `doc/manual/bitwhiz_manual.pdf` to the
  GitHub release as `bitwhiz_manual_X.Y.Z.pdf` (and to nanoHUB's page as a
  supporting document, replacing the last one).
- **GitHub release and Zenodo.** A pushed tag is not a release: on GitHub,
  Releases, "Draft a new release" (or Tags, the tag's menu, "Create release"),
  choose the tag, title it "bitwhiz X.Y.Z: a few words" (e.g. "bitwhiz 1.4.1:
  documentation and audit"), paste the release notes, and publish. Zenodo
  archives each published release (not a bare tag) within minutes, with its
  metadata from `CITATION.cff`, so bump `version` and `date-released` there
  before tagging. Check the new version on Zenodo (title, authors, version,
  license) and add its DOI below. doi:10.5281/zenodo.23999297 stands for all
  versions and resolves to the newest; the archive starts at 1.3.4:

  | Version | Zenodo DOI | Archived |
  |---|---|---|
  | 1.3.4 | 10.5281/zenodo.23999298 | Nov 6, 2026 |
  | 1.4.0 | 10.5281/zenodo.24048196 | Nov 8, 2026 |
  | 1.4.1 | 10.5281/zenodo.24092238 | Nov 9, 2026 |
  | 1.5.0 | 10.5281/zenodo.24169923 | Nov 12, 2026 |

**nanoHUB's compiler is gfortran 8.3** (Debian 10). Keep the code to what
gfortran 8 accepts; Fortran 2018 features it lacks, and their replacements
here, are:

| Not in gfortran 8 | Use instead |
|---|---|
| zero-width `ES`/`EN` edit descriptors (`es0.16e3`) | a fixed width, leading blanks dropped (`trace_mod`, `num17`) |
| `stop code, quiet=.true.` | `call quit(code)` (module bits) |
| `random_init` | `random_seed` with a fixed seed (`draw_colormaps`) |

To check before a release, build with gfortran 8 if you can (`make clean;
make FC=gfortran-8 test`); v1.0.2 was tested with gfortran 8.4, 9, 10, 12
and 13; v1.1.0 with 13 and 15.2, v1.2.0 with 9, 13 and 15.2, and v1.3.0
with 9 and 13, their gfortran 8 checks left to nanoHUB's install (8.3);
from v1.3.4, CI tests every push with gfortran 8, 13 and the newest
(`.github/workflows/tests.yml`).

**How the tool runs** (for the notebook, `bitwhiz.ipynb` in the clone):
nanoHUB copies the notebook into the session's results folder and starts it
there, so it finds the installed tool through the `TOOLDIR` environment variable
(`/apps/bitwhiz/dev`), not through its own folder. It starts in App Mode
(`start_jupyter -A` in `middleware/invoke`): every cell runs, the code is
hidden, and the user sees the text, the deck picker and the editor; "Edit App"
shows the code. Since every cell runs at launch, none may fail before a run.
The picker offers the decks in the tool's `examples/`, which the export fills
from `input/`, so a deck added to `input/` here reaches nanoHUB with the next
export. (The installed tool's `src/` is `drwxr-s---`: users cannot read it.) Runs are written to
`~/bitwhiz_runs/<title>`. After a run that draws movie frames, the notebook
makes them one `<title>.mv_p.mp4` with ffmpeg (the recipe in
`input/README.md`, section 9b) and removes them, so the frames' names,
`<title>.mv_p_*.bmp`, are part of what the notebook relies on. A session
sees 24 processors with no CPU limit, shared with other users:
`num_threads = 1` for class decks, 4 to 8 for large meshes.

**The tool's source is public on nanoHUB** after all (found Nov 5, 2026):
the installed copy above is not readable, but the tool's wiki on nanoHUB has
an "Inspect source code" button, which shows the tool's repository.

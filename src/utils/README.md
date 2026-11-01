# utils
This folder contains the utility functions.

- `make_build_info.sh`: writes `src/modules/build_mod.f95` (build date and git
  version) on every `make`. A `VERSION` file at the top of the tree, which
  `export_nanohub.sh` writes into an export, gives the version instead.
- `export_nanohub.sh`: copies a tagged release into the nanoHUB tool's clone, as
  its `src/bitwhiz/` folder, with a `VERSION` file holding the tag; also the
  decks and the deck reference into the clone's `examples/` and `VERSION` into
  its `bin/`, where the installed tool's users can read them (its `src/` they
  cannot). Usage: `sh src/utils/export_nanohub.sh v1.1.0
  ~/Documents/Academic/bitwhiz` (details at the top of the script).
- `random.f95`, `timestamp.f95`: small routines kept in the build.

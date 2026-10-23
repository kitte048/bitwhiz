# utils
This folder contains the utility functions.

- `make_build_info.sh`: writes `src/modules/build_mod.f95` (build date and git
  version) on every `make`.
- `export_nanohub.sh`: copies a tagged release into the nanoHUB tool's clone, as
  its `src/bitwhiz/` folder. Usage: `sh src/utils/export_nanohub.sh v1.0.2
  ~/Documents/Academic/bitwhiz` (details at the top of the script).
- `random.f95`, `timestamp.f95`: small routines kept in the build.

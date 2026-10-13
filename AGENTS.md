# ReSketch update rules

- Bump the app version for every completed update and add a brief entry under that version in `CHANGELOG.txt`.
- Very large updates: increment the major version (+1.0.0), resetting minor and patch to zero.
- Large updates: increment the minor version (+0.1.0), resetting patch to zero.
- Bug fixes and very minor changes: increment the patch version (+0.0.1).
- Keep `CMakeLists.txt` and the version prefix in `packaging/arch/PKGBUILD` in sync.
- Show the build's actual Git commit in About and `--version`; rebuild after committing so the installed app identifies that commit.
- Do not edit `README.md` unless the user explicitly requests it.
- Build and reopen the app after completing changes.

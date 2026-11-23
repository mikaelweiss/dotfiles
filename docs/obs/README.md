# OBS menu bar icon crash

On macOS 27, OBS crashes when you click its menu bar icon. The bug is in Qt 6.11.1, which OBS bundles. Qt fixed it in [6192d9edd0](https://github.com/qt/qtbase/commit/6192d9edd00caa14ed6b67c32c0cd8cfe95cf815), first released in Qt 6.11.3.

`libqcocoa.dylib` here is OBS's Qt plugin rebuilt with that fix. Every OBS update overwrites it. Run `fix-obs` to put it back.

## When fix-obs refuses

`fix-obs` installs the plugin only when OBS still bundles the exact Qt build it was compiled against. When OBS bundles a different build:

- If OBS ships Qt 6.11.3 or later, the fix is already in. Delete this folder and `terminal/bin/fix-obs`.
- Otherwise, rebuild the plugin against the new Qt.

## Rebuilding

1. Read the Qt version and the obs-deps release in OBS's `CMakePresets.json` (`qt6.version`) for the installed OBS tag.
2. Download that qtbase source tarball, then apply OBS's own Qt patches from `deps.qt/patches/Qt6/mac/` in obs-deps at that release, then `qcocoa-tray-fix.patch` from qtbase's root.
3. Configure with the flags in obs-deps `deps.qt/qt6.zsh` (Release, `-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0`, `-DCMAKE_OSX_ARCHITECTURES=arm64`), then build only `plugins/platforms/libqcocoa.dylib` with Ninja.
4. Check that every Qt symbol the new plugin imports exists in OBS's QtCore and QtGui (`nm -m` against `nm -gU`).
5. `strip -S` it, swap it into the arm64 slice of OBS's plugin with `lipo -replace arm64`, and ad-hoc sign it with `codesign -f -s -`.
6. Replace `libqcocoa.dylib` here, and set `expected_qtcore_uuid` in `fix-obs` to the new QtCore's arm64 UUID (`dwarfdump --uuid`).

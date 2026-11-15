# BatteryTime

A menu bar clone of Apple's battery menu (macOS 27) with one addition: the estimated time
remaining (or time until full) on the right of the "Power Source" line, under the percentage.
Hide Apple's own battery item (System Settings → Control Center → Battery) and use this instead.

Everything else is Apple's menu: the same glyph in the menu bar (yellow in Low Power Mode, red
at 10 % or less on battery, bolt when charging, plug on the adapter), the Energy Mode rows with
their circular badges, the significant-energy list, and Battery Settings…. Apple's menu has no
Quit item, so neither does this one: hold Option while opening the menu to get "Quit BatteryTime".

## Build and install

```sh
./build.sh          # swiftc + ad-hoc codesign → ./BatteryTime.app (Command Line Tools only)
./install.sh        # LaunchAgent ~/Library/LaunchAgents/local.batterytime.plist, starts it now
```

The project lives under `~/Documents`, which macOS guards, so the LaunchAgent starts the app with
`/usr/bin/open -g …/BatteryTime.app` rather than running the binary directly.
`./install.sh --dry-run` prints the LaunchAgent without installing it.

Uninstall: `launchctl bootout gui/$(id -u)/local.batterytime; rm ~/Library/LaunchAgents/local.batterytime.plist`

## Energy mode needs root

Clicking Automatic / Low Power / High Power runs `pmset -b powermode N` (on battery) or
`pmset -c powermode N` (on the adapter). BatteryTime first tries `sudo -n`, and if that isn't
allowed it shows the standard administrator password prompt. To skip the prompt, run
`./install-sudoers.sh` once: it installs `/etc/sudoers.d/batterytime` allowing only those six
`pmset` commands (rule in `Resources/sudoers-batterytime`, checked with `visudo`).

## Where the numbers live

- `Sources/MenuStyle.swift`: menu layout (308 pt width, 14 pt insets, row heights, baselines),
  fonts and colours, all measured from Apple's menu in `../_reference`.
- `Sources/BatteryGlyph.swift`: menu bar icon geometry, opacities, `criticalPercent` (10),
  the 43 pt status item width.
- `Sources/MenuViews.swift` (`EnergyBadge`): badge glyph geometry.
- `Sources/EnergyUsage.swift`: "significant energy" `threshold` (20, Activity Monitor's energy
  impact summed per app), `maxApps`, sampling intervals. Apple's own list is private; this samples
  `top -o power`.

## Developer flags

- `BatteryTime.app/Contents/MacOS/BatteryTime --dump`: battery state, the line-2 text, energy
  mode, the exact commands a mode click would run (not executed), significant-energy apps.
- `--snapshot DIR`: renders the menu (dark, light, hover, charging with apps) and every menu bar
  glyph state to PNGs.
- `--self-test [DIR]`: launches, opens its own menu, moves the highlight with the keyboard, checks
  the menu is 308 × 257 pt with every row in place, optionally saves the live rows, then quits.

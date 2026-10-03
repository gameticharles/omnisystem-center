# Architecture

OmniSystem Center is an Omarchy shell plugin of two kinds: a `service`
(`Service.qml`, one instance, `keepLoaded`) and a `bar-widget` (`Panel.qml`,
one per bar, so one per monitor). The manifest's `omarchy.clonedFrom:
"omarchy.power"` makes Omarchy put it where the built-in Power widget was.

## Pieces

| File | Role |
|---|---|
| `Service.qml` | All state and every action: battery readings from UPower and `omarchy-battery-status`, the probe, warnings and the critical countdown, charge care, profiles, keep awake, the sleep timer, lid hold, keyboard backlight, history, gadgets, the system monitor, IPC, the saved state |
| `Panel.qml` | The bar button, tabs, the power row at the bottom, the confirmation dialog. Binds the service with `bar.shell.serviceFor("omnisystem-center")` and pushes its settings into it |
| `views/*.qml` | One file per tab; they render the service and call its functions |
| `components/*.qml` | Small shared pieces: `Section`, `SwitchRow`, `Stat`, `InfoRow` (a fact that copies on click), `Meter`, `Graph`, `SeriesTile`, `Card`, and `Runner` (one process with a callback) |
| `lib/Model.js` | Every decision that can be a pure function: icons, labels, warnings, the critical action, history, profiles, power actions, the sleep timer, gadget merging and alerts, the charge-limit backend and target, heat hold, top-up, sailing, unplug reminder, low-battery profile, calibration, daily totals, sessions, health log, tips, CPU and memory maths, the report. Tested in `tests/model.test.js` |
| `bin/omnisystem-center-probe` | Read-only: capabilities as JSON (battery files without the serial number, threshold files and whether they are writable, UPower's threshold properties, the keyboard LED, the lid); `system` for one CPU, memory, load, clock, disk, swap, temperature, fan and RAPL sample; `device` for what the machine is (DMI without serials, CPU topology and caches, the root disk through LUKS/LVM, PCI devices named from hwdata's `pci.ids`, USB devices). It never reads PCI configuration space, which would wake a runtime-suspended GPU |
| `bin/omnisystem-center-procs` | `watch` samples /proc every 2 s while the Processes tab is open (CPU % from tick deltas, like top; GPU % and memory from each own process's DRM fdinfo, and NVML for NVIDIA while awake); `signal-tree` signals a process's descendants deepest first, then the process; `detail` reads a process's folder, program, I/O and open files; `signal` and `renice` act only on a PID whose start time still matches, own processes only, never PID 1 or the shell's own chain, through a pidfd where available |
| `bin/omnisystem-center-ports` | `scan` reads `ss -ltnup` and /proc: project root and stack per listener, reach per bind address, well-known names for unreadable sockets, Docker/Podman published ports; `stop-container` checks the container is running first |
| `bin/omnisystem-center-plugins` | `local` (omarchy plugin list + manifests + git state), `catalog` (plugins.omarchy.org, conditional GET, reduced, cached), `thumbs` (HTTPS from that host only, size-capped), `updates` (`git ls-remote` per plugin, 15 min cache), `changes` (GitHub's compare API: the commits and files an update brings), `stats` (hearts, views and installs), `preview` (the full-size image), `job` (install pinned: added off, `git fetch --depth 1` of the reviewed commit, checked out and verified, then enabled; otherwise removed again) (detached `omarchy plugin` change, progress in $XDG_RUNTIME_DIR/omnisystem-center/job.json, then summons the panel again) |
| `bin/omnisystem-center-energy` | The energy meter. `run` is started by the service and stops with it (it also exits when its parent goes); it holds a lock so a reload never runs two. Every 2 s it reads the battery and every awake discrete GPU and prints a `tick` line; every 10 s it reads RAPL, stores one row in SQLite (`energy.db`: `samples` for 30 days, `daily` forever) and prints a `live` line. The CLI (`now`, `report`, `chart`, `panel`, `status`, `config`, `currencies`) answers the Energy tab and the terminal. Tested in `tests/energy_test.py` |
| `bin/omnisystem-center-ctl` | The only writes outside the plugin's own files: `limit`, `apple-limit`, `upower-limit`. Validates every value, writes only files the user may already write, exit codes 2 bad input, 3 unsupported, 4 not permitted |
| `bin/omnisystem-center-gadgets`, `collectors.d/`, `sources/` | Gadget sources ported from Gadget Batteries |

## Capability detection

The probe runs at start, every five minutes (every 15 s while the panel is
open) and after plug events. `Model.chargeLimitBackend` turns its output into
one of `sysfs`, `apple`, `upower`, `locked` or `none`, and the Care tab is
built from that. Heat protection needs a temperature (sysfs `temp` or
UPower's `Temperature`); lid hold needs `/proc/acpi/button/lid`; keyboard
backlight needs a `*kbd_backlight*` LED; hibernate needs
`omarchy-hibernation-available`; suspend needs Omarchy's `suspend-off`
toggle to be off.

## Charge care

`Model.desiredLimit` decides the target from the care settings, strongest
first: heat (hold at the current level while hot), top-up or calibration
(100%), the limit, off (100%). `applyCare()` compares it with what the
hardware holds and calls the control script only when they differ. Nothing
is written until the user has used a care control (`care.managed`), so a
limit set elsewhere survives installing the plugin.

## Warnings

Low and critical warnings use `Model.batteryWarnings` (each once, re-armed
three points above). The low warning goes through `omarchy-battery-low`, so
Omarchy's notification and `battery-low` hooks run. While Omarchy's own
Battery service is enabled (read from `shell.json`'s `disabledPlugins`) the
low warning and the plug-in profile switch are left to it.

## Saved state

`~/.local/state/omnisystem-center/state.json`, written 1.5 s after the last
change: care settings, keyboard levels, lid hold, the sleep timer, the
low-battery profile, calibration, warning flags, six hours of samples, 14
days of totals, 20 sessions, a year of daily health, gadget renames, the
last tab.

## IPC

`omnisystem-center`: `open`, `close`, `toggle`, `show <tab>`,
`togglePercentage`, `status`, `action <key>`, `sleepTimer <minutes> <action>`, `cancelTimer`, `keepAwake on|off|toggle`, `profile <name>`, `topUp`, `report`, `cycleLabel`, `energy`, `energySettings`, `energyPeriod day|week|month|year|custom`. `show` takes every tab: overview, care, insights, energy, system, processes, ports, plugins, controls.
`omarchy.power`: the built-in widget's `open`, `close`, `show`, `hide`,
`toggle`, `togglePercentage`.

## The energy meter

Only measured energy is stored: per interval the CPU package's RAPL delta,
the discrete GPUs' integrated power, or (on battery) the energy that left the
battery, with the seconds it covers. `baseline_w`, `psu_efficiency` and the
price are applied when a number is shown, so a settings change reprices all
history. An interval is dropped, and counted as untracked, when the machine
slept, the source changed mid-interval, the battery reading failed, or (on AC)
the RAPL counter was unreadable or jumped. Integrated graphics are inside the
RAPL package and are never added. NVIDIA cards are read through NVML only
while their PCI runtime status is `active`; on battery at most every 10 s.
With `--ports SECONDS` the sampler also runs the ports helper's scan (imported, not spawned) and prints a `ports` line, so the bar's dev-server count costs no extra process. NVML is opened once while an NVIDIA card is awake and closed when it sleeps. The service reads the sampler's lines with a `SplitParser`; the bar uses the
2 s `tick` (battery draw, GPU state) and the 10 s `live` (socket draw, today,
this month). The Energy tab runs `panel <period>` every 10 s while open.

## Settings, keys and state

The Settings tab and each plugin's bar settings are drawn by
`components/SettingsForm.qml` from a manifest's `barWidget.schema`. Each
list tab exposes `handleMove`, `handleActivate` and `handleKey` to the
panel's key catcher, a `header` component the panel freezes above the
scrolling list, and `loadMore` for lazy loading. View state (search,
filters, sort, what is open) and each tab's scroll position are saved in
`state.json` under `ui`.

## Sleep readiness

`omnisystem-center-probe` reports `sleep`: Omarchy's hibernation
conditions, `resume=` on the kernel command line, and for NVIDIA whether
`PreserveVideoMemoryAllocations` is on while `nvidia-suspend`,
`nvidia-hibernate` or `nvidia-resume` is not wanted by the sleep targets
(read from `/etc/systemd/system/*.wants/`). Issues are shown, never acted on.


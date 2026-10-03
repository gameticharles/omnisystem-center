# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-03

First release. Replaces Omarchy's Power widget (`omarchy.power`) and can take
over its Battery service's warnings. Developed as OmniBattery Power until the
panel had outgrown the battery; never released under that name.

### Added

- Battery: level, state, time left or to full, power in or out, health,
  cycles, size, temperature and drain rate where reported.
- Charge care, offered by what the hardware allows: an exact charge limit,
  sailing mode, a one-time top-up, heat protection and calibration on
  laptops whose kernel or Apple SMC threshold files the user may write;
  UPower's own limit on supporting systems; an unplug reminder everywhere
  else.
- Low battery warning through Omarchy's own command and hooks, a critical
  action (hibernate or suspend) after a 60-second countdown that can be
  cancelled from the notification or the panel (and carries on across a
  shell reload), and a power-saver switch at a chosen level that undoes
  itself once charging.
- A power profile remembered per power source, chosen for either source
  from the panel.
- Keep awake (shared with Omarchy's stay-awake toggle), a sleep timer that
  survives a shell restart, lid hold, keyboard backlight per power source.
- Insights: health and wear rate over time, the last six hours, the last
  seven days, sessions on battery, tips and a Markdown report.
- Energy meter: the draw at the socket now, split into CPU, GPU and the
  rest with the measured share; energy and cost per day, week, month, year
  or any number of days, with a hover graph and the tracked share of every
  period; price, currency (55 built in) and the two estimates set in the
  panel and applied to all history; calibration against a wall meter. On
  battery the whole machine is measured. Untracked time never counts as zero.
- Every GPU: discrete NVIDIA (NVML, per card, with how busy it is), AMD and
  Intel Arc cards are measured and added; integrated graphics are shown
  inside the CPU figure. A sleeping GPU is never woken to read it.
- The bar shows the machine's draw beside the battery and a GPU icon with its
  draw while a discrete GPU is awake; right-click steps through draw, charge,
  today's energy and nothing; the icon can turn red above a chosen draw.
- System tab: clock speed, load, fastest core, disk space, swap and zram,
  every temperature and fan sensor, and what the machine is: processor,
  caches and scaling, memory and storage, model, board, firmware and EC,
  Omarchy version and kernel, graphics, network, audio and USB hardware.
  Click to copy any fact, or copy everything; a btop button.
- Processes tab: every process with CPU (per sample), memory, user and
  command; sort, search, mine only, tree; details with disk I/O, open files,
  folder and program; end, kill, pause, resume, interrupt, reload and lower
  priority, each checked against the process's start time and sent through
  a pidfd, ending and killing on a second click.
- Ports tab: listeners named by project and stack, reach (local, containers,
  VPN, network), dev / mine / exposed / all, grouped by project; open, copy,
  terminal, stop and force-kill, and container stop. A notification when a
  dev server becomes reachable from the network; the number of dev servers
  in the bar.
- Plugins tab: installed plugins with on/off, update checks, update and
  remove; the marketplace with previews, stars, categories, sorting and
  search, and install. Changes run detached through `omarchy plugin` and
  the panel comes back after the shell's rescan. Previews enlarge over the
  panel on a click; ports, installed plugins and marketplace cards are
  three-line tiles whose details open inside the tile.
- Every graph sits in a card (System, Insights, Energy). The dev-server
  count has its own bar button, switched from the Ports tab: shown at 0 too,
  in the bar's urgent colour while any dev server runs, opening the Ports tab.
- The panel remembers: it reopens on the tab you left (now the default),
  every tab where you scrolled it, and the Processes, Ports and Plugins tabs
  their search, filters, sort and what was open, across closing the panel
  and shell restarts.
- Plugin tiles carry the id and author (installed) or views, installs and
  last update (marketplace) where the cut-off description was; the full
  description is in the details. Hearts, views and installs come from the
  marketplace's stats, with Loved and Installs sorts. Verified is blue and
  update green (the theme's own when it has a real blue or green).
- Frozen headers: the Processes summary, search and column headers, the
  Ports chips and search, and the Plugins tabs, filters, count and sort stay
  in place while the list scrolls; the panel grows to 860 px to fit them.
- Lazy loading: the marketplace appends its next cards (and Processes its
  next rows) as you near the end, without rebuilding what is on screen.
- Settings tab: every widget setting, grouped, built from the manifest.
- Plugins: a Bar view to reorder widgets or move them between sections, and
  to put enabled widgets that are in no section into one; another widget's
  bar settings edited in place (`omarchy bar set`); What's new before an
  update (commits and files from GitHub's compare API); installs pinned to
  the commit the marketplace reviewed (added off, checked out, verified,
  then enabled), with the newest code as a separate, labelled choice.
- Processes: per-process GPU use and memory (DRM fdinfo; NVML while the card
  is awake) as a sortable column; End tree and Kill tree.
- Energy: a monthly budget with a bar and notifications at 80% and 100%;
  CSV export of every recorded day.
- Ports: your own dev rules (ports or ranges, programs that always or never
  count), from Settings or a button on each row; a command-line stack counts
  as dev, so an editor's Node service is seen as Omaports sees it.
- Keyboard: a cursor in the Processes, Ports and Plugins lists with action
  keys, `/` to search.
- Sleep readiness: hibernation set up, a resume target, and an NVIDIA driver
  keeping video memory over sleep without its sleep services, shown on the
  Controls and Care tabs and the Suspend and Hibernate buttons
  (docs/sleep.md).
- Acer health mode (acer-wmi-battery) as a charge-limit backend.
- System → Hardware: each GPU's memory (AMD VRAM and use from sysfs; NVIDIA
  total and use from NVML while awake, the total remembered for when it
  sleeps, and the driver version; integrated Intel as shared memory with its
  top clock).
- The background ports scan runs inside the energy sampler, and NVML stays
  open only while the NVIDIA card is awake: the sampler's cost fell from
  about 560 ms to about 150 ms of CPU a minute, the port scans included.
- The panel is wider (560 px by default), the tabs sit fixed above the
  content, with the open tab named in its own theme colour and the others
  as icons, and colours (graphs, meters, the power buttons) follow the
  current Omarchy theme.
- Bar: the battery percentage as its own switch, the GPU readout for the
  discrete GPU, integrated graphics or both, as usage, watts or both.
- A system monitor: CPU, memory, CPU temperature and package power, sampled
  only while its tab is open.
- Gadget batteries from UPower, headsetcontrol, Galaxy Buds, Fast Pair
  earbuds, AirPods, Logitech receivers, an external JSON file and your own
  collector scripts, with low and charged notifications and renaming.
- Lock, logout, suspend, hibernate, reboot and shutdown at the bottom of
  every tab, with confirmation for the ones that end the session.
- IPC targets `omnisystem-center` and `omarchy.power`.

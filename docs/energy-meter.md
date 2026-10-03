# The energy meter

The Energy tab answers "what does this computer cost to run?" without a
smart plug. It keeps a permanent record per day, and shows week, month and
year totals, the cost at your electricity price, and how much of every number
is measured rather than estimated.

## What is measured and what is estimated

| Part | Source | Measured? |
|---|---|---|
| The whole machine, on battery | The battery's own power reading (`power_now`, or `current_now` × `voltage_now`) | **Yes.** Everything the laptop uses leaves the battery |
| CPU package, on AC | RAPL `package-*` energy counter (`/sys/class/powercap/intel-rapl:N`) | **Yes.** A true energy counter |
| Discrete GPUs | NVIDIA: NVML, per card. AMD: amdgpu `power1_average`. Intel Arc: the card's hwmon energy counter | **Yes**, while the card is awake. A sleeping card counts as 0 W and is never woken to ask |
| Integrated graphics | Intel UHD/Iris/Xe and AMD Radeon APUs draw from the CPU package | Already inside the CPU figure, so **never added again**. On Intel the package's `uncore` counter shows their share |
| Memory, disk, screen, fans, chipset, on AC | `baseline_w` (12 W laptop, 32 W desktop) | **Estimated.** No sensor exists |
| Charger or power-supply loss | `psu_efficiency` (0.88 laptop, 0.89 desktop) | **Estimated** |

Every watt and kWh is shown at the wall socket: each part is divided by the
efficiency. On battery the energy is what has to be put back through the
charger.

The database stores only the measured microjoules and how long they were
measured over. The baseline, the efficiency and the price are applied when a
number is shown, so changing them in the settings reprices the whole history
at once. That means you can enter your price after a month and get a correct
month.

## Tracked time

The sampler starts and stops with the shell. Time the shell was not running,
the machine slept, or (on AC) the CPU counter could not be read is
**untracked**. It never counts as zero use. Each row on the Energy tab shows
how much of the period was tracked, and averages are "while tracked".

## The CPU counter on AC

RAPL's energy counter is readable by root only on most systems, a response to
[CVE-2020-8694](https://nvd.nist.gov/vuln/detail/CVE-2020-8694) ("PLATYPUS":
sampled very fast, the counter is a power side channel). Without it a laptop
is measured on battery only, and a desktop not at all. The Energy tab says so.

This one-time rule lets the `wheel` group (your Omarchy user is in it)
**read** the package counter. It grants no write access, and it does not
cover the `core` sub-zone, which is the finer-grained one for side channels.

Check that the counter exists:

```bash
ls -l /sys/class/powercap/intel-rapl:*/energy_uj
```

Create the rule (the only step that needs root):

```bash
sudo tee /etc/udev/rules.d/90-omnisystem-center-energy.rules >/dev/null <<'RULE'
ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", ATTR{name}=="package-*", RUN+="/usr/bin/chgrp wheel /sys%p/energy_uj", RUN+="/usr/bin/chmod 0440 /sys%p/energy_uj"
RULE
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=powercap --action=add
```

The meter notices on its next interval; nothing needs restarting. Remove the
file to take the permission back. It stays until the next reboot or until the
device is recreated.

What this changes: any program running as you can read the package counter
at any rate, without asking for a password. On a single-user laptop that is
usually an acceptable trade. If it is not acceptable for you, skip the rule.
The meter then records time on battery only.

To also see the Intel integrated GPU's share, add the same rule for
`ATTR{name}=="uncore"`. The same side-channel reasoning applies.

## Calibrating the estimate

With a wall meter or smart plug, let the machine idle on AC, open the
settings on the Energy tab, type what the meter reads and press **Use**. The
rest of the machine is then

    baseline = metered watts × efficiency − (CPU + GPU)

Your whole history is corrected with it. Out of the box, AC figures are
usually within 15–20% of a wall meter. Battery figures are measured, apart
from the charger loss.

## From the terminal

The sampler is also a command-line tool. Every subcommand takes `--json`:

```bash
~/.config/omarchy/plugins/omnisystem-center/bin/omnisystem-center-energy now
~/.config/omarchy/plugins/omnisystem-center/bin/omnisystem-center-energy report day
~/.config/omarchy/plugins/omnisystem-center/bin/omnisystem-center-energy report month -n 12
~/.config/omarchy/plugins/omnisystem-center/bin/omnisystem-center-energy status
~/.config/omarchy/plugins/omnisystem-center/bin/omnisystem-center-energy config tariff=1.94 currency=GHS
```

| Setting | Default | |
|---|---|---|
| `tariff` | 0 (no cost shown) | Price per kWh: the part of the bill that grows with use. Reprices history |
| `currency` | USD | ISO code; sets the symbol and decimals (`GH₵1.94`, `¥180`, `Rp 2,041`). Reprices history |
| `currency_symbol` | automatic | Your own symbol |
| `cost_decimals` | auto | 0–4 |
| `baseline_w` | 12 laptop / 32 desktop | The unmeasured rest on AC. Reprices history |
| `psu_efficiency` | 0.88 / 0.89 | Charger or power-supply efficiency. Reprices history |
| `interval_s` | 10 | Seconds per stored sample |
| `gpu_interval_s` | 2 | GPU and battery sub-samples (on battery NVIDIA is read at most every 10 s) |
| `raw_retention_days` | 30 | Per-sample rows kept for graphs; daily totals are kept forever |
| `sanity_max_cpu_w` | 1000 | A package reading above this is a counter reset and is dropped |
| `gpu_source` | auto | `auto` (every discrete GPU), `nvidia`, `amdgpu`, `intel` or `off` |

Files: `~/.local/state/omnisystem-center/energy.db` (SQLite) and
`~/.config/omnisystem-center/energy.json`, both private to you. Removing the
plugin leaves them; delete them to forget the history.

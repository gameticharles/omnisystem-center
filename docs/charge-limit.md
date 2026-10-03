# Letting your user set the charge limit

Many laptop drivers expose a charge limit in
`/sys/class/power_supply/BAT*/charge_control_end_threshold` (and often
`charge_control_start_threshold`): ThinkPads, ASUS, Dell, Huawei, Samsung,
LG, MSI, Framework and others. Apple T2 Macs have
`/sys/bus/acpi/devices/APP0001:00/battery_charge_limit`.

The kernel makes these files writable by root only. OmniSystem Center never
asks for root, so the Care tab shows **Root only** until your user may write
them. This one-time rule hands them to the `wheel` group (your Omarchy user
is in it) every time the battery appears.

Check that your laptop has the files:

```bash
ls /sys/class/power_supply/BAT*/charge_control_* /sys/bus/acpi/devices/APP0001:00/battery_charge_limit 2>/dev/null
```

Create the rule (this is the only step that needs root):

```bash
sudo tee /etc/udev/rules.d/90-omnisystem-center.rules >/dev/null <<'RULE'
ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT*", TEST=="charge_control_end_threshold", RUN+="/bin/chgrp wheel /sys%p/charge_control_end_threshold", RUN+="/bin/chmod g+w /sys%p/charge_control_end_threshold"
ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT*", TEST=="charge_control_start_threshold", RUN+="/bin/chgrp wheel /sys%p/charge_control_start_threshold", RUN+="/bin/chmod g+w /sys%p/charge_control_start_threshold"
ACTION=="add|change", SUBSYSTEM=="acpi", KERNEL=="APP0001:00", TEST=="battery_charge_limit", RUN+="/bin/chgrp wheel /sys%p/battery_charge_limit", RUN+="/bin/chmod g+w /sys%p/battery_charge_limit"
RULE
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=power_supply --subsystem-match=acpi
```

Open the panel again: the Care tab now shows **Kernel** (or **Apple SMC**)
with an exact limit, and sailing mode when the start file exists too.

To undo it:

```bash
sudo rm /etc/udev/rules.d/90-omnisystem-center.rules
sudo udevadm control --reload
```

The files go back to root at the next boot.

## Without the rule

Recent UPower (1.90 and later) offers its own charge limit on supported
drivers and lets the active session switch it on and off without root.
OmniSystem Center uses it when the probe reports it (**UPower** on the Care
tab); the levels are the firmware's, or what you set in
`/etc/UPower/UPower.conf`.

On a laptop with neither, the unplug reminder tells you when to take the
charger out.

## Acer laptops (Nitro, Aspire, Swift, Predator)

Many Acer laptops keep the charge at 80% in "health mode", but the kernel
only exposes it through the out-of-tree `acer-wmi-battery` driver
(https://github.com/frederik-h/acer-wmi-battery). On Arch and Omarchy it is
packaged in the AUR as `acer-wmi-battery-dkms`:

```bash
yay -S acer-wmi-battery-dkms
sudo modprobe acer_wmi_battery
echo acer_wmi_battery | sudo tee /etc/modules-load.d/acer-wmi-battery.conf
```

Check that it found your laptop:

```bash
cat /sys/bus/wmi/drivers/acer-wmi-battery/health_mode
```

Then let your user switch it, with this rule (once):

```bash
sudo tee /etc/udev/rules.d/90-omnisystem-center-acer.rules >/dev/null <<'RULE'
ACTION=="add|bind", SUBSYSTEM=="wmi", DRIVER=="acer-wmi-battery", RUN+="/bin/chgrp wheel /sys/bus/wmi/drivers/acer-wmi-battery/health_mode", RUN+="/bin/chmod g+w /sys/bus/wmi/drivers/acer-wmi-battery/health_mode"
RULE
sudo udevadm control --reload
sudo modprobe -r acer_wmi_battery && sudo modprobe acer_wmi_battery
```

`health_mode` belongs to the driver rather than to a device, hence the fixed
path. The Care tab then shows **Acer health mode** with a switch. (Written
against the driver's documentation; not yet tried on a machine with it.)

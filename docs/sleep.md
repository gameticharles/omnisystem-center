# When suspend or hibernate does not come back

OmniSystem Center checks a few files when it starts and warns on the
Controls and Care tabs (and on the Suspend and Hibernate buttons) when sleep
is likely to fail. Nothing here needs root to read; the fixes below do.

## NVIDIA: video memory kept, but its sleep steps are off

The NVIDIA driver can save the GPU's memory when the machine sleeps
(`NVreg_PreserveVideoMemoryAllocations=1`). Some packages switch that on, for
example gpu-screen-recorder through `/usr/lib/modprobe.d/gsr-nvidia.conf`.
The saving and restoring is then done by three small services from the
driver package, and if they are not enabled the GPU comes back without its
memory: the screen stays black after suspend, and a hibernation image fails
to load ("PM: hibernation: Failed to load image", "resume failed (-5)") so
the session is lost.

Check it:

```bash
grep PreserveVideoMemoryAllocations /proc/driver/nvidia/params
systemctl is-enabled nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
```

Fix it (once):

```bash
sudo systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service
```

Then suspend and resume once while nothing important is open, before you
rely on hibernate. The warning goes away the next time the shell starts.

The other fix is to switch video-memory preservation off again (remove or
edit the modprobe file that sets it and rebuild the initramfs), at the cost of
whatever wanted it.

## Hibernation set up, but no resume target

Omarchy's `omarchy-hibernation-setup` adds `resume=` to the kernel command
line. If it is missing (`cat /proc/cmdline`), the hibernation image is
written but never read back. Run `omarchy-hibernation-setup --force` again.

## While it is not fixed

Choose **suspend** or **none** as the critical action on the Care tab, so a
running-out battery does not end in an image that will not load.

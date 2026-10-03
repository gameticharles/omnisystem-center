"""Tests for bin/omnisystem-center-probe and bin/omnisystem-center-ctl
against a fake sysfs tree. Run: python3 -m unittest discover -s tests -p '*_test.py'
"""
import json
import os
import stat
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.path.dirname(HERE), "bin")


def put(root, rel, text, mode=0o644):
    file = os.path.join(root, rel)
    os.makedirs(os.path.dirname(file), exist_ok=True)
    with open(file, "w") as handle:
        handle.write(text)
    os.chmod(file, mode)
    return file


def run(tool, root, *args):
    env = dict(os.environ, OMNISYSTEM_SYSFS_ROOT=root)
    return subprocess.run([os.path.join(BIN, tool), *args], capture_output=True, text=True, env=env)


class Fake(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        bat = "sys/class/power_supply/BAT0/"
        put(self.root, bat + "type", "Battery\n")
        put(self.root, bat + "energy_full", "45000000\n")
        put(self.root, bat + "energy_full_design", "50000000\n")
        put(self.root, bat + "cycle_count", "120\n")
        put(self.root, bat + "temp", "312\n")
        put(self.root, bat + "serial_number", "SECRET\n")
        put(self.root, "sys/class/power_supply/hidpp_battery_0/type", "Battery\n")
        put(self.root, "sys/class/power_supply/hidpp_battery_0/scope", "Device\n")
        put(self.root, "sys/class/power_supply/AC/type", "Mains\n")
        self.bat = os.path.join(self.root, bat)

    def tearDown(self):
        self.tmp.cleanup()

    def thresholds(self, end=100, start=0, mode=0o644):
        self.end = put(self.root, "sys/class/power_supply/BAT0/charge_control_end_threshold", f"{end}\n", mode)
        self.start = put(self.root, "sys/class/power_supply/BAT0/charge_control_start_threshold", f"{start}\n", mode)

    def read(self, file):
        with open(file) as handle:
            return handle.read().strip()


class ProbeTest(Fake):
    def probe(self):
        result = run("omnisystem-center-probe", self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_picks_the_system_battery_not_a_peripheral(self):
        caps = self.probe()
        self.assertEqual(caps["battery"]["name"], "BAT0")
        self.assertEqual(caps["battery"]["files"]["temp"], "312")

    def test_never_reports_the_serial_number(self):
        self.assertNotIn("serial_number", self.probe()["battery"]["files"])

    def test_no_thresholds_no_keyboard_no_lid(self):
        caps = self.probe()
        self.assertEqual(caps["threshold"]["sysfs"], {})
        self.assertIsNone(caps["keyboard"])
        self.assertIsNone(caps["lid"])
        self.assertFalse(caps["threshold"]["upower"]["supported"])

    def test_threshold_files_and_writability(self):
        self.thresholds(80, 75)
        sysfs = self.probe()["threshold"]["sysfs"]
        self.assertEqual(sysfs["end"]["value"], 80)
        self.assertEqual(sysfs["start"]["value"], 75)
        if os.getuid() != 0:
            os.chmod(self.end, 0o444)
            self.assertFalse(self.probe()["threshold"]["sysfs"]["end"]["writable"])

    def test_apple_limit(self):
        put(self.root, "sys/bus/acpi/devices/APP0001:00/battery_charge_limit", "100\n")
        self.assertEqual(self.probe()["threshold"]["sysfs"]["apple"]["value"], 100)

    def test_keyboard_and_lid(self):
        put(self.root, "sys/class/leds/tpacpi::kbd_backlight/max_brightness", "2\n")
        put(self.root, "sys/class/leds/tpacpi::kbd_backlight/brightness", "1\n")
        put(self.root, "proc/acpi/button/lid/LID0/state", "state:      open\n")
        caps = self.probe()
        self.assertEqual(caps["keyboard"]["device"], "tpacpi::kbd_backlight")
        self.assertEqual(caps["keyboard"]["max"], 2)
        self.assertEqual(caps["lid"]["state"], "open")

    def test_system_sample(self):
        put(self.root, "proc/stat", "cpu  10 0 5 100 0 0 0 0 0 0\ncpu0 1 0 1 1\n")
        put(self.root, "proc/meminfo", "MemTotal: 1000 kB\nMemAvailable: 400 kB\n")
        put(self.root, "sys/class/hwmon/hwmon3/name", "coretemp\n")
        put(self.root, "sys/class/hwmon/hwmon3/temp1_label", "Package id 0\n")
        put(self.root, "sys/class/hwmon/hwmon3/temp1_input", "54000\n")
        result = run("omnisystem-center-probe", self.root, "system")
        sample = json.loads(result.stdout)
        self.assertEqual(sample["cpu"][:4], [10, 0, 5, 100])
        self.assertEqual(sample["memory"]["MemTotal"], 1024000)
        self.assertEqual(sample["cpuTemp"], 54.0)


class DeviceTest(Fake):
    def setUp(self):
        super().setUp()
        put(self.root, "sys/class/dmi/id/sys_vendor", "Acer\n")
        put(self.root, "sys/class/dmi/id/product_name", "Nitro AN515-57\n")
        put(self.root, "sys/class/dmi/id/product_family", "Nitro 5\n")
        put(self.root, "sys/class/dmi/id/board_vendor", "To be filled by O.E.M.\n")
        put(self.root, "sys/class/dmi/id/chassis_type", "10\n")
        put(self.root, "sys/class/dmi/id/product_serial", "NXQ-SECRET\n")
        put(self.root, "proc/cpuinfo", "processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: 11th Gen Intel(R) Core(TM) i5-11400H\n"
                                    "physical id\t: 0\ncore id\t: 0\n\nprocessor\t: 1\nphysical id\t: 0\ncore id\t: 0\n\n"
                                    "processor\t: 2\nphysical id\t: 0\ncore id\t: 1\n")
        put(self.root, "sys/devices/system/cpu/cpu0/cache/index3/level", "3\n")
        put(self.root, "sys/devices/system/cpu/cpu0/cache/index3/type", "Unified\n")
        put(self.root, "sys/devices/system/cpu/cpu0/cache/index3/size", "12288K\n")
        put(self.root, "usr/share/hwdata/pci.ids", "10de  NVIDIA Corporation\n\t2520  GA106M [GeForce RTX 3060 Mobile / Max-Q]\n"
                                                    "10ec  Realtek Semiconductor Co., Ltd.\n\t3000  Killer E3000 2.5GbE Controller\n")
        gpu = "sys/bus/pci/devices/0000:01:00.0/"
        put(self.root, gpu + "vendor", "0x10de\n")
        put(self.root, gpu + "device", "0x2520\n")
        put(self.root, gpu + "class", "0x030000\n")
        put(self.root, gpu + "power/runtime_status", "suspended\n")
        # Reading config space wakes a sleeping GPU: the probe must not.
        self.config = put(self.root, gpu + "config", "", mode=0o000)
        nic = "sys/bus/pci/devices/0000:03:00.0/"
        put(self.root, nic + "vendor", "0x10ec\n")
        put(self.root, nic + "device", "0x3000\n")
        put(self.root, nic + "class", "0x020000\n")
        put(self.root, "sys/bus/usb/devices/3-9/product", "HD User Facing\n")
        put(self.root, "sys/bus/usb/devices/3-9/manufacturer", "SunplusIT Inc\n")
        put(self.root, "sys/bus/usb/devices/usb3/product", "xHCI Host Controller\n")
        put(self.root, "sys/bus/usb/devices/3-1/product", "4-Port Hub\n")
        put(self.root, "sys/bus/usb/devices/3-1/bDeviceClass", "09\n")

    def device(self):
        result = run("omnisystem-center-probe", self.root, "device")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_machine_and_cpu(self):
        d = self.device()
        self.assertEqual(d["machine"]["vendor"], "Acer")
        self.assertEqual(d["machine"]["product"], "Nitro AN515-57")
        self.assertEqual(d["machine"]["family"], "Nitro 5")
        self.assertEqual(d["machine"]["board"], "", "placeholder text is dropped")
        self.assertEqual(d["machine"]["chassis"], "Notebook")
        self.assertEqual(d["cpu"]["model"], "11th Gen Intel Core i5-11400H")
        self.assertEqual(d["cpu"]["vendor"], "Intel")
        self.assertEqual(d["cpu"]["cores"], 2)
        self.assertEqual(d["cpu"]["caches"], {"L3": "12288K"})

    def test_never_reports_serials(self):
        self.assertNotIn("SECRET", run("omnisystem-center-probe", self.root, "device").stdout)

    def test_pci_names_without_waking_the_gpu(self):
        d = self.device()
        names = {x["kind"]: x for x in d["pci"]}
        self.assertEqual(names["Graphics"]["name"], "NVIDIA GeForce RTX 3060 Mobile / Max-Q")
        self.assertTrue(names["Graphics"]["asleep"])
        self.assertEqual(names["Ethernet"]["name"], "Realtek Killer E3000 2.5GbE Controller")

    def test_gpu_memory(self):
        put(self.root, "usr/share/hwdata/pci.ids", "1002  Advanced Micro Devices, Inc. [AMD/ATI]\n\t73bf  Navi 21 [Radeon RX 6800]\n"
                                                    "8086  Intel Corporation\n\t9a68  TigerLake-H GT1 [UHD Graphics]\n")
        amd = "sys/bus/pci/devices/0000:03:00.0/"
        put(self.root, amd + "vendor", "0x1002\n")
        put(self.root, amd + "device", "0x73bf\n")
        put(self.root, amd + "class", "0x030000\n")
        put(self.root, amd + "mem_info_vram_total", str(16 * 1024 ** 3) + "\n")
        put(self.root, amd + "mem_info_vram_used", str(2 * 1024 ** 3) + "\n")
        igpu = "sys/bus/pci/devices/0000:00:02.0/"
        put(self.root, igpu + "vendor", "0x8086\n")
        put(self.root, igpu + "device", "0x9a68\n")
        put(self.root, igpu + "class", "0x030000\n")
        put(self.root, igpu + "drm/card0/gt_max_freq_mhz", "1450\n")
        gpus = {g["name"].split()[0]: g for g in self.device()["pci"] if g["kind"] == "Graphics"}
        self.assertEqual(gpus["AMD"]["memory"], {"total": 16 * 1024 ** 3, "used": 2 * 1024 ** 3, "shared": False, "gtt": 0})
        self.assertFalse(gpus["AMD"]["integrated"])
        self.assertEqual(gpus["Intel"]["memory"], {"total": 0, "used": None, "shared": True, "maxMHz": 1450})
        self.assertTrue(gpus["Intel"]["integrated"])

    def test_usb_skips_hubs_and_controllers(self):
        self.assertEqual([u["name"] for u in self.device()["usb"]], ["SunplusIT Inc HD User Facing"])

    def test_temperatures_and_fans(self):
        put(self.root, "sys/class/hwmon/hwmon1/name", "coretemp\n")
        put(self.root, "sys/class/hwmon/hwmon1/temp1_label", "Package id 0\n")
        put(self.root, "sys/class/hwmon/hwmon1/temp1_input", "61000\n")
        put(self.root, "sys/class/hwmon/hwmon1/temp2_label", "Core 0\n")
        put(self.root, "sys/class/hwmon/hwmon1/temp2_input", "64000\n")
        put(self.root, "sys/class/hwmon/hwmon2/name", "nvme\n")
        put(self.root, "sys/class/hwmon/hwmon2/temp1_label", "Composite\n")
        put(self.root, "sys/class/hwmon/hwmon2/temp1_input", "38850\n")
        put(self.root, "sys/class/hwmon/hwmon3/name", "thinkpad\n")
        put(self.root, "sys/class/hwmon/hwmon3/fan1_input", "2900\n")
        result = run("omnisystem-center-probe", self.root, "system")
        data = json.loads(result.stdout)
        temps = {t["group"]: t for t in data["temps"]}
        self.assertEqual(temps["CPU"]["c"], 61.0)
        self.assertEqual(temps["CPU"]["detail"], "hottest core 64 °C")
        self.assertEqual(temps["SSD"]["c"], 38.9)
        self.assertEqual(data["fans"], [{"label": "Fan 1", "rpm": 2900}])


class SleepTest(Fake):
    def caps(self):
        return json.loads(run("omnisystem-center-probe", self.root).stdout)["sleep"]

    def test_nvidia_without_its_sleep_steps(self):
        put(self.root, "proc/driver/nvidia/params", "PreserveVideoMemoryAllocations: 1\n")
        sleep = self.caps()
        self.assertEqual([i["id"] for i in sleep["issues"]], ["nvidia-sleep"])
        self.assertIn("suspend, hibernate, resume steps are off", sleep["issues"][0]["text"])

    def test_nvidia_with_its_sleep_steps(self):
        put(self.root, "proc/driver/nvidia/params", "PreserveVideoMemoryAllocations: 1\n")
        for target, unit in (("systemd-suspend.service", "nvidia-suspend.service"), ("systemd-hibernate.service", "nvidia-hibernate.service"),
                             ("systemd-suspend.service", "nvidia-resume.service")):
            put(self.root, f"etc/systemd/system/{target}.wants/{unit}", "")
        self.assertEqual(self.caps()["issues"], [])

    def test_hibernation_without_resume(self):
        put(self.root, "sys/power/image_size", "1000\n")
        put(self.root, "proc/swaps", "Filename Type Size Used Priority\n/swap/swapfile file 4096 0 0\n")
        put(self.root, "etc/mkinitcpio.conf.d/omarchy_resume.conf", "")
        put(self.root, "proc/cmdline", "quiet splash\n")
        sleep = self.caps()
        self.assertTrue(sleep["hibernation"])
        self.assertEqual([i["id"] for i in sleep["issues"]], ["no-resume"])


class AcerTest(Fake):
    def test_probe_and_write_health_mode(self):
        health = put(self.root, "sys/bus/wmi/drivers/acer-wmi-battery/health_mode", "0\n")
        result = run("omnisystem-center-probe", self.root)
        node = json.loads(result.stdout)["threshold"]["sysfs"]["acer"]
        self.assertEqual((node["value"], node["writable"]), (0, True))
        self.assertEqual(run("omnisystem-center-ctl", self.root, "acer-health", "on").returncode, 0)
        self.assertEqual(self.read(health), "1")
        self.assertEqual(run("omnisystem-center-ctl", self.root, "acer-health", "maybe").returncode, 2)

    def test_missing_driver(self):
        self.assertEqual(run("omnisystem-center-ctl", self.root, "acer-health", "on").returncode, 3)


class CtlTest(Fake):
    def ctl(self, *args):
        return run("omnisystem-center-ctl", self.root, *args)

    def test_rejects_bad_values(self):
        self.thresholds()
        for args in (["limit"], ["limit", "40"], ["limit", "101"], ["limit", "80", "80"],
                     ["limit", "80;rm"], ["limit", "80", "-1"], ["apple-limit", "5"], ["upower-limit", "maybe"], ["nope"]):
            self.assertEqual(self.ctl(*args).returncode, 2, args)
        self.assertEqual(self.read(self.end), "100")

    def test_no_threshold_is_not_supported(self):
        self.assertEqual(self.ctl("limit", "80").returncode, 3)
        self.assertEqual(self.ctl("apple-limit", "80").returncode, 3)

    def test_writes_end_only(self):
        self.thresholds()
        self.assertEqual(self.ctl("limit", "80").returncode, 0)
        self.assertEqual(self.read(self.end), "80")
        self.assertEqual(self.read(self.start), "0")

    def test_writes_start_and_end_in_a_safe_order(self):
        self.thresholds(60, 40)
        self.assertEqual(self.ctl("limit", "90", "85").returncode, 0)
        self.assertEqual((self.read(self.start), self.read(self.end)), ("85", "90"))
        self.assertEqual(self.ctl("limit", "70", "50").returncode, 0)
        self.assertEqual((self.read(self.start), self.read(self.end)), ("50", "70"))

    @unittest.skipIf(os.getuid() == 0, "root can write read-only files")
    def test_read_only_is_not_permitted(self):
        self.thresholds(100, 0, 0o444)
        self.assertEqual(self.ctl("limit", "80").returncode, 4)
        self.assertEqual(self.read(self.end), "100")

    def test_apple_limit(self):
        file = put(self.root, "sys/bus/acpi/devices/APP0001:00/battery_charge_limit", "100\n")
        self.assertEqual(self.ctl("apple-limit", "80").returncode, 0)
        self.assertEqual(self.read(file), "80")


if __name__ == "__main__":
    unittest.main()

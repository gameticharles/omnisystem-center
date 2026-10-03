"""Tests for bin/omnisystem-center-energy: counter maths, storage, the
retroactive pricing and the fake-sysfs sensor discovery.
Run: python3 -m unittest discover -s tests -p '*_test.py'
"""
import datetime
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(HERE), "bin", "omnisystem-center-energy")


def load():
    loader = importlib.machinery.SourceFileLoader("omnienergy", SOURCE)
    spec = importlib.util.spec_from_loader("omnienergy", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def put(root, rel, text):
    file = os.path.join(root, rel)
    os.makedirs(os.path.dirname(file), exist_ok=True)
    with open(file, "w") as handle:
        handle.write(text)
    return file


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "sys-root")
        os.makedirs(self.root)
        self.E = load()
        self.E.ROOT = self.root
        self.E.STATE_DIR = os.path.join(self.tmp.name, "state")
        self.E.CONFIG_DIR = os.path.join(self.tmp.name, "config")
        self.E.DB_PATH = os.path.join(self.E.STATE_DIR, "energy.db")
        self.E.CONFIG_PATH = os.path.join(self.E.CONFIG_DIR, "energy.json")
        self.config = dict(self.E.defaults(), baseline_w=10.0, psu_efficiency=0.8, tariff=0.5, currency="EUR")

    def tearDown(self):
        self.tmp.cleanup()

    def connect(self):
        db = self.E.connect()
        self.addCleanup(db.close)
        return db

    def ms(self, *when):
        return int(datetime.datetime(*when).timestamp() * 1000)


class Counters(Base):
    def test_wrap_is_taken_modulo_the_range(self):
        before = {"z": (2 ** 32 - 1_000_000, 2 ** 32)}
        after = {"z": (4_000_000, 2 ** 32)}
        self.assertEqual(self.E.rapl_delta(before, after, 10, 1000), 5_000_000)

    def test_a_reset_is_dropped(self):
        top = 262_143_328_850  # a typical Intel package range, about 262 kJ
        before = {"z": (900_000_000, top)}
        after = {"z": (100, top)}
        self.assertIsNone(self.E.rapl_delta(before, after, 10, 1000))

    def test_sockets_are_summed(self):
        before = {"a": (0, 10 ** 12), "b": (0, 10 ** 12)}
        after = {"a": (100_000_000, 10 ** 12), "b": (50_000_000, 10 ** 12)}
        self.assertEqual(self.E.rapl_delta(before, after, 10, 1000), 150_000_000)


class Storage(Base):
    def test_ac_day_adds_the_estimate_and_the_supply_loss(self):
        db = self.connect()
        ts = self.ms(2026, 10, 1, 12)
        # 3600 s on AC: CPU 20 W, GPU 10 W, measured.
        self.E.record(db, {"ts": ts, "dt": 3600, "src": "ac", "cpu_uj": 20 * 3600 * 10 ** 6, "gpu_uj": 10 * 3600 * 10 ** 6})
        now = datetime.datetime(2026, 10, 2, 9)
        day = self.E.report(db, self.config, "day", 2, now)["buckets"][0]
        # (20 + 10 + 10 baseline) W for an hour = 40 Wh DC, / 0.8 = 50 Wh at the socket.
        self.assertAlmostEqual(day["kwh"], 0.05, places=4)
        self.assertAlmostEqual(day["cost"], 0.025, places=6)
        self.assertEqual(day["cost_text"], "€0.03")
        self.assertAlmostEqual(day["measured_share"], 0.75, places=3)
        self.assertAlmostEqual(day["avg_w"], 50.0, places=1)
        self.assertAlmostEqual(day["max_w"], 50.0, places=1)
        self.assertAlmostEqual(day["coverage"], round(3600 / 86400, 3))

    def test_battery_time_is_all_measured(self):
        db = self.connect()
        self.E.record(db, {"ts": self.ms(2026, 10, 2, 8), "dt": 1800, "src": "battery", "batt_uj": 16 * 1800 * 10 ** 6,
                           "cpu_uj": 5 * 1800 * 10 ** 6})
        t = self.E.report(db, self.config, "day", 1, datetime.datetime(2026, 10, 2, 9))["buckets"][0]
        self.assertEqual(t["measured_share"], 1.0)
        self.assertAlmostEqual(t["kwh"], 16 * 0.5 / 0.8 / 1000, places=4)
        self.assertEqual(t["battery_share"], 1.0)
        # Today is clipped to the time elapsed (9 h).
        self.assertAlmostEqual(t["coverage"], round(1800 / (9 * 3600), 3))

    def test_settings_reprice_the_whole_history(self):
        db = self.connect()
        self.E.record(db, {"ts": self.ms(2026, 9, 1, 12), "dt": 3600, "src": "ac", "cpu_uj": 30 * 3600 * 10 ** 6})
        now = datetime.datetime(2026, 10, 2)
        first = self.E.report(db, self.config, "month", 2, now)["buckets"][0]
        dearer = self.E.report(db, dict(self.config, tariff=1.0, baseline_w=30.0), "month", 2, now)["buckets"][0]
        self.assertAlmostEqual(dearer["kwh"], 0.075, places=4)
        self.assertAlmostEqual(dearer["cost"], 0.075, places=6)
        self.assertLess(first["kwh"], dearer["kwh"])

    def test_no_price_means_no_cost(self):
        db = self.connect()
        self.E.record(db, {"ts": self.ms(2026, 10, 1, 12), "dt": 60, "src": "ac", "cpu_uj": 10 ** 8})
        t = self.E.report(db, dict(self.config, tariff=0.0), "day", 1, datetime.datetime(2026, 10, 1, 13))["total"]
        self.assertIsNone(t["cost"])
        self.assertEqual(t["cost_text"], "")

    def test_weeks_months_years(self):
        now = datetime.datetime(2026, 10, 3, 12)
        self.assertEqual(self.E.recent_keys("week", 3, now), ["2026-W38", "2026-W39", "2026-W40"])
        self.assertEqual(self.E.recent_keys("month", 3, now), ["2026-08", "2026-09", "2026-10"])
        self.assertEqual(self.E.recent_keys("year", 2, now), ["2025", "2026"])
        self.assertEqual(self.E.bucket_key("2026-01-01", "week"), "2026-W01")
        self.assertEqual(self.E.bucket_key("2027-01-01", "week"), "2026-W53")

    def test_an_empty_bucket_before_history_is_marked(self):
        db = self.connect()
        self.E.record(db, {"ts": self.ms(2026, 10, 3, 10), "dt": 60, "src": "ac", "cpu_uj": 10 ** 8})
        days = self.E.report(db, self.config, "day", 3, datetime.datetime(2026, 10, 3, 12))["buckets"]
        self.assertEqual([d["before_history"] for d in days], [True, True, False])
        empty = self.E.report(None, self.config, "day", 2, datetime.datetime(2026, 10, 3, 12))["buckets"]
        self.assertEqual([d["before_history"] for d in empty], [False, False], "nothing recorded yet is not 'before'")
        self.assertEqual(days[-1]["label"], "Today")
        self.assertEqual(days[-2]["label"], "Yesterday")

    def test_chart_leaves_gaps_and_uses_days_beyond_retention(self):
        db = self.connect()
        now = self.ms(2026, 10, 3, 12)
        for minutes in range(0, 60):
            self.E.record(db, {"ts": now - (120 - minutes) * 60000, "dt": 60, "src": "ac", "cpu_uj": 20 * 60 * 10 ** 6})
        raw = self.E.chart(db, self.config, 1, now, points=12)
        self.assertEqual(raw["source"], "samples")
        values = [p[1] for p in raw["points"]]
        self.assertTrue(any(v is None for v in values), "the last hour was not tracked")
        self.assertAlmostEqual([v for v in values if v][0], (20 + 10) / 0.8, places=1)
        daily = self.E.chart(db, dict(self.config, raw_retention_days=7), 30, now)
        self.assertEqual(daily["source"], "daily")
        self.assertEqual(len(daily["points"]), 1, "starts at the first recorded day")

    def test_latest_is_only_live_while_fresh(self):
        db = self.connect()
        ts = self.ms(2026, 10, 3, 12)
        self.E.record(db, {"ts": ts, "dt": 10, "src": "ac", "cpu_uj": 200_000_000, "gpu_uj": 0})
        now = self.E.latest(db, self.config, ts + 5000)
        self.assertAlmostEqual(now["watts"], (20 + 10) / 0.8, places=1)
        self.assertEqual(now["measured_share"], round(20 / 30, 3))
        self.assertIsNone(self.E.latest(db, self.config, ts + 120000))


class Budget(Base):
    def test_alerts_once_per_level_per_month(self):
        db = self.connect()
        sent = []
        self.E.emit = lambda data: sent.append(data)
        now = datetime.datetime.now()
        ts = int(now.timestamp() * 1000)
        config = dict(self.config, tariff=1.0, monthly_budget=0.05)   # 50 Wh at €1/kWh
        self.E.record(db, {"ts": ts, "dt": 3600, "src": "ac", "cpu_uj": 20 * 3600 * 10 ** 6})  # 0.0375 kWh at the socket
        self.E.budget_check(db, config)
        self.assertEqual([d["level"] for d in sent], [])
        self.E.record(db, {"ts": ts + 1000, "dt": 3600, "src": "ac", "cpu_uj": 10 * 3600 * 10 ** 6})
        self.E.budget_check(db, config)
        self.E.budget_check(db, config)
        self.assertEqual([d["level"] for d in sent], [100], "past 100%: one alert, the higher level")
        self.E.budget_check(db, dict(config, monthly_budget=0))
        self.assertEqual(len(sent), 1)

    def test_export(self):
        db = self.connect()
        self.E.record(db, {"ts": self.ms(2026, 10, 1, 12), "dt": 3600, "src": "ac", "cpu_uj": 20 * 3600 * 10 ** 6})
        target = os.path.join(self.tmp.name, "out.csv")
        result = self.E.export_csv(db, dict(self.config, currency="GHS"), target)
        self.assertEqual(result["days"], 1)
        with open(target) as handle:
            lines = handle.read().splitlines()
        self.assertTrue(lines[0].startswith("date,kwh,cost,currency"))
        self.assertTrue(lines[1].startswith("2026-10-01,0.0375,0.0187,GHS"), lines[1])


class Settings(Base):
    def test_validation(self):
        v = self.E.validate
        self.assertEqual(v("tariff", "0.42"), 0.42)
        self.assertEqual(v("currency", "ghs"), "GHS")
        self.assertEqual(v("cost_decimals", "auto"), "auto")
        self.assertEqual(v("interval_s", "15"), 15)
        for key, bad in (("tariff", "-1"), ("tariff", "nan"), ("currency", "€"), ("interval_s", "2.5"),
                         ("psu_efficiency", "1.5"), ("gpu_source", "matrox"), ("nope", "1")):
            with self.assertRaises(ValueError, msg=f"{key}={bad}"):
                v(key, bad)

    def test_money(self):
        f = self.E.format_cost
        self.assertEqual(f(1234.5, dict(self.config, currency="JPY", tariff=30)), "¥1,234")
        self.assertEqual(f(12.345, dict(self.config, currency="GHS", tariff=2)), "GH₵12.35")
        self.assertEqual(f(9.99, dict(self.config, currency="CHF")), "CHF 9.99")
        self.assertEqual(f(2041, dict(self.config, currency="IDR", tariff=1444.7)), "Rp 2,041")
        self.assertEqual(f(1, dict(self.config, currency="EUR", cost_decimals=3)), "€1.000")

    def test_config_round_trip_keeps_only_changes(self):
        config = self.E.load_config()
        config["tariff"] = 1.5
        self.E.save_config(config)
        self.assertEqual(self.E.load_config()["tariff"], 1.5)
        with open(self.E.CONFIG_PATH) as handle:
            self.assertEqual(handle.read().strip(), '{\n  "tariff": 1.5\n}')
        self.assertEqual(os.stat(self.E.CONFIG_PATH).st_mode & 0o777, 0o600)

    def test_a_planted_link_is_refused(self):
        os.makedirs(self.E.CONFIG_DIR)
        os.symlink("/etc/hostname", self.E.CONFIG_PATH)
        with self.assertRaises(self.E.RefusedPath):
            self.E.load_config()


class Sensors(Base):
    def test_battery_watts_from_current_and_voltage(self):
        bat = "sys/class/power_supply/BAT1/"
        put(self.root, bat + "type", "Battery\n")
        put(self.root, bat + "status", "Discharging\n")
        put(self.root, bat + "current_now", "1500000\n")
        put(self.root, bat + "voltage_now", "15000000\n")
        put(self.root, "sys/class/power_supply/ACAD/type", "Mains\n")
        put(self.root, "sys/class/power_supply/ACAD/online", "0\n")
        self.assertAlmostEqual(self.E.battery_watts(), 22.5)
        self.assertFalse(self.E.on_ac())
        put(self.root, "sys/class/power_supply/ACAD/online", "1\n")
        put(self.root, bat + "status", "Charging\n")
        self.assertTrue(self.E.on_ac())
        self.assertIsNone(self.E.battery_watts())

    def test_a_desktop_is_on_ac(self):
        self.assertTrue(self.E.on_ac())

    def test_only_package_zones_are_used(self):
        for zone, name in (("intel-rapl:0", "package-0"), ("intel-rapl:0:0", "core"), ("intel-rapl:1", "psys"),
                           ("intel-rapl-mmio:0", "package-0")):
            put(self.root, f"sys/class/powercap/{zone}/name", name + "\n")
            put(self.root, f"sys/class/powercap/{zone}/energy_uj", "1000\n")
        used, unreadable, unused = self.E.rapl_zones()
        self.assertEqual([os.path.basename(z) for z in used], ["intel-rapl:0"])
        self.assertEqual(unused, ["psys"])

    def gpu(self, bdf, vendor, awake=True, hwmon=None, extra=None):
        dev = f"sys/bus/pci/devices/{bdf}/"
        put(self.root, dev + "vendor", vendor + "\n")
        put(self.root, dev + "class", "0x030000\n")
        put(self.root, dev + "power/runtime_status", ("active" if awake else "suspended") + "\n")
        for name, value in (hwmon or {}).items():
            put(self.root, dev + "hwmon/hwmon9/" + name, value + "\n")
        for name, value in (extra or {}).items():
            put(self.root, dev + name, value + "\n")
        return dev

    def fake_nvml(self, watts=35.0, busy=40, temp=61):
        calls = []

        class FakeNvml:
            def __init__(self):
                self.lib, self.failed = object(), None

            def read(self, bus_ids):
                calls.append(list(bus_ids))
                return {b: (watts, busy, temp) for b in bus_ids}

            def close(self):
                pass

        self.E.Nvml = FakeNvml
        return calls

    def test_integrated_radeon_is_shown_not_added(self):
        put(self.root, "proc/cpuinfo", "model name\t: AMD Ryzen 7 7840U w/ Radeon 780M Graphics\n")
        self.gpu("0000:c5:00.0", "0x1002", hwmon={"power1_average": "9000000"}, extra={"mem_info_vram_total": str(512 * 1024 ** 2)})
        gpu = self.E.Gpu("auto")
        watts, state, devices = gpu.read()
        self.assertIsNone(gpu.kind)
        self.assertIsNone(watts, "nothing discrete to add")
        self.assertEqual(devices[0]["state"], "in-package")
        self.assertEqual(devices[0]["watts"], 9.0)

    def test_every_discrete_gpu_is_added(self):
        put(self.root, "proc/cpuinfo", "model name\t: AMD Ryzen 9 5950X\n")
        self.gpu("0000:03:00.0", "0x1002", hwmon={"power1_average": "120000000"}, extra={"gpu_busy_percent": "57"})
        self.gpu("0000:04:00.0", "0x10de")
        calls = self.fake_nvml(35.0, 12)
        gpu = self.E.Gpu("auto")
        self.assertEqual(gpu.kind, "amd,nvidia")
        watts, state, devices = gpu.read()
        self.assertEqual(watts, 155.0)
        self.assertEqual(state, "awake")
        self.assertEqual([(d["vendor"], d["watts"], d["busy"]) for d in devices], [("AMD", 120.0, 57), ("NVIDIA", 35.0, 12)])
        self.assertEqual(devices[1]["temp"], 61)
        self.assertEqual(calls, [["0000:04:00.0"]])

    def test_intel_igpu_and_arc_card(self):
        self.gpu("0000:00:02.0", "0x8086")
        self.gpu("0000:03:00.0", "0x8086", hwmon={"energy1_input": "1000000"})
        gpu = self.E.Gpu("auto")
        self.assertEqual(gpu.kind, "intel")
        first = gpu.read(now=100.0)
        self.assertIsNone(first[0], "a counter needs two readings")
        put(self.root, "sys/bus/pci/devices/0000:03:00.0/hwmon/hwmon9/energy1_input", "21000000\n")
        watts, state, devices = gpu.read(now=102.0)
        self.assertEqual(watts, 10.0)
        self.assertEqual(devices[0]["state"], "in-package")
        self.assertTrue(devices[0]["integrated"])

    def test_a_sleeping_nvidia_gpu_is_not_woken(self):
        dev = self.gpu("0000:01:00.0", "0x10de", awake=False)
        self.gpu("0000:00:02.0", "0x8086")
        calls = self.fake_nvml()
        gpu = self.E.Gpu("auto")
        self.assertEqual(gpu.kind, "nvidia")
        watts, state, _ = gpu.read()
        self.assertEqual((watts, state), (0.0, "asleep"))
        self.assertEqual(calls, [], "NVML was not asked while the GPU slept")
        put(self.root, dev + "power/runtime_status", "active\n")
        self.assertEqual(gpu.read()[:2], (35.0, "awake"))

    def test_on_battery_nvidia_is_read_at_most_every_10_s(self):
        self.gpu("0000:01:00.0", "0x10de")
        calls = self.fake_nvml()
        gpu = self.E.Gpu("auto")
        for t in (0.0, 2.0, 4.0, 11.0):
            gpu.read(on_battery=True, now=t)
        self.assertEqual(len(calls), 2)
        gpu.read(on_battery=False, now=12.0)
        self.assertEqual(len(calls), 3)

    def test_intel_usage_from_idle_time_and_card_temperatures(self):
        self.gpu("0000:00:02.0", "0x8086")
        put(self.root, "sys/bus/pci/devices/0000:00:02.0/drm/card0/gt/gt0/rc6_residency_ms", "10000\n")
        self.gpu("0000:03:00.0", "0x1002", hwmon={"power1_average": "30000000", "temp1_input": "48000"},
                 extra={"gpu_busy_percent": "9"})
        put(self.root, "proc/cpuinfo", "model name\t: Intel Core i7\n")
        gpu = self.E.Gpu("auto")
        gpu.read(now=10.0)
        put(self.root, "sys/bus/pci/devices/0000:00:02.0/drm/card0/gt/gt0/rc6_residency_ms", "11500\n")
        _, _, devices = gpu.read(now=12.0)
        intel, amd = devices
        self.assertEqual(intel["busy"], 25, "idle 1.5 s of 2 s")
        self.assertIsNone(intel["temp"], "no CPU sensor in this fake tree")
        self.assertEqual((amd["busy"], amd["temp"]), (9, 48.0))

    def test_integrated_intel_takes_the_cpu_package_temperature(self):
        self.gpu("0000:00:02.0", "0x8086")
        put(self.root, "sys/class/hwmon/hwmon0/name", "coretemp\n")
        put(self.root, "sys/class/hwmon/hwmon0/temp1_label", "Package id 0\n")
        put(self.root, "sys/class/hwmon/hwmon0/temp1_input", "61000\n")
        _, _, devices = self.E.Gpu("auto").read(now=1.0)
        self.assertEqual((devices[0]["temp"], devices[0]["tempShared"]), (61.0, True))

    def test_one_vendor_or_off(self):
        self.gpu("0000:03:00.0", "0x1002", hwmon={"power1_average": "50000000"})
        self.gpu("0000:04:00.0", "0x10de")
        self.fake_nvml()
        self.assertEqual(self.E.Gpu("amdgpu").read()[0], 50.0)
        self.assertEqual(self.E.Gpu("nvidia").read()[0], 35.0)
        off = self.E.Gpu("off")
        self.assertIsNone(off.kind)
        self.assertEqual(off.read()[2], [])


if __name__ == "__main__":
    unittest.main()

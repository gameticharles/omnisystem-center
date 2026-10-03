// Tests for lib/Model.js. Run with: node tests/model.test.js
//
// Model.js is a QML JavaScript resource (`.pragma library`, no exports), so it
// is loaded as source and every top-level name is returned from a function.

const fs = require("fs")
const path = require("path")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "..", "lib", "Model.js"), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const names = [
  ...source.matchAll(/^function ([A-Za-z_$][\w$]*)/gm),
  ...source.matchAll(/^var ([A-Za-z_$][\w$]*)/gm)
].map((m) => m[1])
const M = new Function(source + "\nreturn {" + names.map((n) => `${n}: ${n}`).join(",") + "};")()

let failures = 0
function test(name, fn) {
  try {
    fn()
    console.log("  ok   " + name)
  } catch (error) {
    failures++
    console.log("  FAIL " + name)
    console.log("       " + String(error.message).split("\n").join("\n       "))
  }
}

const S = { Charging: 1, Discharging: 2, FullyCharged: 4, PendingCharge: 5 }

// ------------------------------------------------------------------ battery

test("battery icon follows level and charging", () => {
  assert.strictEqual(M.batteryIcon({ isPresent: true, percentage: 0.55, state: S.Discharging }, true, S), "󰁿")
  assert.strictEqual(M.batteryIcon({ isPresent: true, percentage: 0.55, state: S.Charging, changeRate: 20 }, false, S), "󰂉")
  assert.strictEqual(M.batteryIcon({ isPresent: true, percentage: 1, state: S.FullyCharged }, false, S), "󰂅")
  assert.strictEqual(M.batteryIcon({ isPresent: false }, true, S), "")
})

test("a charge limit is recognised, not shown as charging", () => {
  const held = { isPresent: true, percentage: 0.8, state: S.FullyCharged }
  assert.strictEqual(M.chargeThresholdActive(held, false, S), true)
  assert.strictEqual(M.modeLabel(held, false, S), "Holding at charge limit")
  assert.strictEqual(M.chargeThresholdActive({ isPresent: true, percentage: 0.8, state: S.Charging, changeRate: 25 }, false, S), false)
})

test("durations and watts read naturally", () => {
  assert.strictEqual(M.formatDuration(3960), "1h 6m")
  assert.strictEqual(M.formatDuration(2520), "42m")
  assert.strictEqual(M.formatDuration(7200), "2h")
  assert.strictEqual(M.formatDuration(0), "")
  assert.strictEqual(M.formatWatts(32.4), "32 W")
  assert.strictEqual(M.formatWatts(-7.25), "7.3 W")
  assert.strictEqual(M.formatWatts(0.01), "")
})

test("health from energy, and from charge when energy is missing", () => {
  const e = M.parseSysfsBattery("energy_full\t37000000\nenergy_full_design\t40000000\ncycle_count\t67\nmanufacturer\tLGC\nmodel_name\tAP18E8M\ntechnology\tLi-ion\n")
  assert.deepStrictEqual([e.full, e.design, e.unit, e.health, e.wear, e.cycles, e.maker], [37, 40, "Wh", 93, 7, 67, "LGC"])
  const c = M.parseSysfsBattery("charge_full\t4100000\ncharge_full_design\t5000000\ncharge_control_end_threshold\t80\n")
  assert.deepStrictEqual([c.unit, c.health, c.chargeLimit], ["Ah", 82, 80])
  assert.strictEqual(M.parseSysfsBattery("").health, -1)
  assert.strictEqual(M.parseSysfsBattery("charge_control_end_threshold\t100\n").chargeLimit, -1, "100% is no limit")
  assert.deepStrictEqual([M.healthLabel(93), M.healthLabel(80), M.healthLabel(60), M.healthLabel(40), M.healthLabel(-1)],
    ["Good", "Fair", "Worn", "Replace soon", ""])
})

test("low and critical warn once each, critical supersedes low", () => {
  let n = { low: false, critical: false }
  let r = M.batteryWarnings(10, true, 10, 5, n)
  assert.deepStrictEqual([r.notifyLow, r.notifyCritical], [true, false])
  n = r.notified
  r = M.batteryWarnings(9, true, 10, 5, n)
  assert.deepStrictEqual([r.notifyLow, r.notifyCritical], [false, false], "not again")
  r = M.batteryWarnings(5, true, 10, 5, r.notified)
  assert.deepStrictEqual([r.notifyLow, r.notifyCritical], [false, true])
  r = M.batteryWarnings(4, true, 10, 5, r.notified)
  assert.deepStrictEqual([r.notifyLow, r.notifyCritical], [false, false])
  // Charging re-arms both.
  r = M.batteryWarnings(6, false, 10, 5, r.notified)
  assert.deepStrictEqual(r.notified, { low: false, critical: false })
  // Straight to critical: only the critical warning.
  r = M.batteryWarnings(3, true, 10, 5, { low: false, critical: false })
  assert.deepStrictEqual([r.notifyLow, r.notifyCritical], [false, true])
  // A threshold of 0 turns that warning off.
  r = M.batteryWarnings(3, true, 0, 0, { low: false, critical: false })
  assert.deepStrictEqual([r.notifyLow, r.notifyCritical], [false, false])
})

test("warnings re-arm only a few points above the threshold", () => {
  let r = M.batteryWarnings(10, true, 10, 5, { low: false, critical: false })
  r = M.batteryWarnings(12, true, 10, 5, r.notified)
  assert.strictEqual(r.notified.low, true, "jitter does not re-arm")
  r = M.batteryWarnings(14, true, 10, 5, r.notified)
  assert.strictEqual(r.notified.low, false)
})

test("the critical action falls back when it is not available", () => {
  assert.strictEqual(M.resolveCriticalAction("hibernate", true, true), "hibernate")
  assert.strictEqual(M.resolveCriticalAction("hibernate", false, true), "suspend")
  assert.strictEqual(M.resolveCriticalAction("hibernate", false, false), "none")
  assert.strictEqual(M.resolveCriticalAction("suspend", true, false), "none", "suspend turned off in Omarchy")
  assert.strictEqual(M.resolveCriticalAction("none", true, true), "none")
  assert.strictEqual(M.resolveCriticalAction("rm -rf", true, true), "none")
})

test("history keeps six hours, one sample a minute, and breaks at gaps", () => {
  const t0 = 1_000_000_000_000
  let h = []
  for (let i = 0; i < 400; i++) h = M.addSample(h, t0 + i * 60000, 100 - i * 0.2, 9.5)
  assert.strictEqual(h.length, 361, "six hours at one a minute")
  const last = h[h.length - 1]
  const again = M.addSample(h, last[0] + 10000, 50, 9)
  assert.deepStrictEqual(again[again.length - 1], last, "a second trigger within the minute is dropped")
  const gap = M.addSample(h, last[0] + 30 * 60000, 40, 0)
  const segs = M.historySegments(gap, last[0] + 30 * 60000, 600, 100)
  assert.strictEqual(segs.length, 2, "asleep for half an hour")
  const first = segs[0][0]
  assert.ok(first[0] >= 0 && first[1] >= 0 && first[1] <= 100)
})

test("drain rate comes from the last hour of falling samples", () => {
  const t0 = 2_000_000_000_000
  let h = []
  for (let i = 0; i <= 60; i += 10) h = M.addSample(h, t0 + i * 60000, 80 - i / 6, 10)
  assert.strictEqual(M.drainPerHour(h, t0 + 60 * 60000), 10)
  assert.strictEqual(M.drainPerHour(h.slice(0, 2), t0 + 60 * 60000), 0, "not enough data")
})

// -------------------------------------------------------------------- power

test("profiles parse with the active one marked", () => {
  const p = M.parseProfiles("performance\t0\nbalanced\t1\npower-saver\t0\n", 9)
  assert.deepStrictEqual([p.profiles, p.activeProfile, p.profileIndex], [["performance", "balanced", "power-saver"], "balanced", 2])
  assert.strictEqual(M.profileLabel("power-saver"), "Power saver")
})

test("a profile for the other power source is remembered, not applied", () => {
  assert.strictEqual(M.profileChange("battery", true), "apply")
  assert.strictEqual(M.profileChange("ac", true), "remember")
  assert.strictEqual(M.profileChange("ac", false), "apply")
  const list = ["performance", "balanced", "power-saver"]
  assert.strictEqual(M.rememberedProfile("power-saver\n", "battery", list), "power-saver")
  assert.strictEqual(M.rememberedProfile("", "ac", list), "performance", "Omarchy's AC default")
  assert.strictEqual(M.rememberedProfile("turbo", "battery", list), "balanced", "unknown falls back")
})

test("power actions follow what the machine allows", () => {
  assert.deepStrictEqual(M.powerActions(true, false).map((a) => a.key), ["lock", "logout", "suspend", "reboot", "shutdown"])
  assert.deepStrictEqual(M.powerActions(false, true).map((a) => a.key), ["lock", "logout", "hibernate", "reboot", "shutdown"])
  assert.deepStrictEqual(M.powerAction("suspend").command, ["loginctl", "suspend"])
  assert.strictEqual(M.powerAction("format-disk"), null)
  assert.ok(M.POWER_ACTIONS.every((a) => a.command.join(" ").indexOf("systemctl") < 0))
})

test("the sleep timer counts down and survives only a short absence", () => {
  const now = 3_000_000_000_000
  assert.strictEqual(M.timerRemaining(now + 90500, now), 91)
  assert.strictEqual(M.timerRemaining(now - 1, now), 0)
  assert.strictEqual(M.formatCountdown(3725), "1:02:05")
  assert.strictEqual(M.formatCountdown(65), "1:05")
  assert.deepStrictEqual(M.restoreTimer({ endsAt: now + 60000, action: "suspend", minutes: 30 }, now),
    { endsAt: now + 60000, action: "suspend", minutes: 30 })
  assert.strictEqual(M.restoreTimer({ endsAt: now - 10 * 60000, action: "suspend" }, now), null, "ran out while away")
  assert.strictEqual(M.restoreTimer({ endsAt: now + 1, action: "reboot-into-bios" }, now), null)
  assert.strictEqual(M.restoreTimer(null, now), null)
})

test("a critical countdown carries on across a reload", () => {
  const now = 1_000_000
  assert.strictEqual(M.resumeCritical({ endsAt: now + 45000 }, now, true, 4, 5), now + 45000)
  assert.strictEqual(M.resumeCritical({ endsAt: now + 5000 }, now, true, 4, 5), now + 30000, "at least 30 s left")
  assert.strictEqual(M.resumeCritical({ endsAt: now - 120000 }, now, true, 3, 5), now + 30000, "ran out during the reload")
  assert.strictEqual(M.resumeCritical({ endsAt: now + 45000 }, now, false, 4, 5), 0, "plugged in meanwhile")
  assert.strictEqual(M.resumeCritical({ endsAt: now + 45000 }, now, true, 30, 5), 0, "charged meanwhile")
  assert.strictEqual(M.resumeCritical({ endsAt: now + 45000 }, now, true, 4, 0), 0, "critical action turned off")
  assert.strictEqual(M.resumeCritical(null, now, true, 4, 5), 0)
  assert.strictEqual(M.resumeCritical({ endsAt: "x" }, now, true, 4, 5), 0)
})

test("gadgets lead on a desktop, sit in the middle on a laptop, power is last", () => {
  assert.deepStrictEqual(M.sectionOrder(true), ["battery", "gadgets", "profiles", "awake", "power"])
  assert.deepStrictEqual(M.sectionOrder(false), ["gadgets", "profiles", "awake", "power"])
})

test("the bar shows the battery, else the lowest gadget, else power", () => {
  assert.strictEqual(M.barIcon(true, "󰁿", { kind: "mouse" }), "󰁿")
  assert.strictEqual(M.barIcon(false, "", { kind: "mouse" }), M.kindIcon("mouse"))
  assert.strictEqual(M.barIcon(false, "", null), M.POWER_ICON)
})

// ------------------------------------------------------------------ gadgets

test("external JSON: TTL turns entries offline, parts become the detail", () => {
  const ext = M.fromExternal(JSON.stringify([
    { id: "a", name: "Speaker", kind: "speaker", pct: 64, ts: 900, ttl: 900 },
    { id: "b", name: "Watch", kind: "watch", pct: 5, ts: 0, ttl: 60 },
    { id: "c", name: "Pods", kind: "earbuds", pct: 40, left: 40, right: 70 },
    { name: "no level" }
  ]), 1000)
  assert.deepStrictEqual(ext.map((d) => [d.name, d.kind, d.level, d.offline]),
    [["Speaker", "speaker", 64, false], ["Watch", "watch", 5, true], ["Pods", "earbuds", 40, false]])
  assert.strictEqual(ext[2].detail, "L 40% · R 70%")
})

test("HeadsetControl skips headsets whose battery cannot be read", () => {
  const hs = M.fromHeadsetControl(JSON.stringify({ devices: [
    { device: "G522", battery: { status: "BATTERY_AVAILABLE", level: 59 } },
    { device: "Off", battery: { status: "BATTERY_UNAVAILABLE", level: -1 } }
  ] }))
  assert.deepStrictEqual(hs.map((d) => [d.name, d.level]), [["G522", 59]])
})

test("Galaxy Buds: the lowest earbud, the case only in the detail", () => {
  const buds = M.fromBudsStatus(JSON.stringify({ connected: true, device_name: "Buds", battery: {
    left: { available: true, level: 80 }, right: { available: true, level: 12, charging: true },
    case: { available: true, level: 5 } } }))
  assert.deepStrictEqual([buds[0].level, buds[0].charging, buds[0].detail], [12, true, "L 80% · R 12% · Case 5%"])
  assert.deepStrictEqual(M.fromBudsStatus("{\"connected\": false}"), [])
})

test("UPower gadgets, not laptop batteries or chargers", () => {
  const states = [1, 0]
  const g = M.fromUPower({ isPresent: true, percentage: 0.42, state: 0, model: "BoomPop2", nativePath: "/x" },
    "Headset", states[0], states[1])
  assert.deepStrictEqual([g.name, g.kind, g.level, g.charging], ["BoomPop2", "headset", 42, null])
  assert.strictEqual(M.fromUPower({ isPresent: true, percentage: 0.5, isLaptopBattery: true }, "Battery", 1, 0), null)
  assert.strictEqual(M.fromUPower({ isPresent: true, percentage: 1, powerSupply: true }, "LinePower", 1, 0), null)
})

test("merging drops duplicates, offline last, lowest first", () => {
  const merged = M.mergeDevices([
    [{ key: "a", name: "Logitech G502 X PLUS", level: 50 }],
    [{ key: "b", name: "G502 X PLUS", level: 51 }, { key: "c", name: "Pods", level: 20, offline: true },
     { key: "d", name: "Keys", level: 30 }]
  ])
  assert.deepStrictEqual(merged.map((d) => d.key), ["d", "a", "c"])
  assert.strictEqual(M.lowestGadget(merged).key, "d")
})

test("gadget low alerts once, re-arm when charging", () => {
  let r = M.gadgetLowAlerts([{ key: "m", level: 10, charging: false }], 15, {})
  assert.strictEqual(r.alerts.length, 1)
  r = M.gadgetLowAlerts([{ key: "m", level: 9, charging: false }], 15, r.notified)
  assert.strictEqual(r.alerts.length, 0)
  r = M.gadgetLowAlerts([{ key: "m", level: 9, charging: true }], 15, r.notified)
  assert.deepStrictEqual(r.notified, {})
  assert.strictEqual(M.gadgetLowAlerts([{ key: "m", level: 1, charging: false }], 0, {}).alerts.length, 0, "0 = off")
})

test("gadget full alert once per charge", () => {
  let r = M.gadgetFullAlerts([{ key: "m", level: 100, charging: true }], {})
  assert.strictEqual(r.alerts.length, 1)
  r = M.gadgetFullAlerts([{ key: "m", level: 100, charging: true }], r.notified)
  assert.strictEqual(r.alerts.length, 0)
  r = M.gadgetFullAlerts([{ key: "m", level: 90, charging: false }], r.notified)
  assert.deepStrictEqual(r.notified, {})
})

test("charging is estimated from a rising level, never against the source", () => {
  let t = M.applyTrends([{ key: "m", name: "Mouse", level: 50, charging: null }], {}, 0)
  t = M.applyTrends([{ key: "m", name: "Mouse", level: 51, charging: null }], t.trends, 60)
  assert.strictEqual(t.devices[0].chargingEstimated, false, "one point is jitter")
  t = M.applyTrends([{ key: "m", name: "Mouse", level: 52, charging: null }], t.trends, 120)
  assert.deepStrictEqual([t.devices[0].charging, t.devices[0].chargingEstimated], [true, true])
  const known = M.applyTrends([{ key: "k", name: "K", level: 60, charging: false }], { k: { level: 40, samples: [[0, 40]], riseTs: 0 } }, 60)
  assert.strictEqual(known.devices[0].charging, false)
})

test("gadgets can be renamed", () => {
  const out = M.applyNames([{ name: "M87 keyboard (2.4G)" }, { name: "Mouse" }], { "M87 keyboard (2.4G)": "Attack Shark" })
  assert.deepStrictEqual(out.map((d) => d.name), ["Attack Shark", "Mouse"])
  assert.deepStrictEqual(out.map((d) => d.reportedName), ["M87 keyboard (2.4G)", "Mouse"])
  assert.strictEqual(M.applyNames([{ name: "A" }], null)[0].reportedName, "A")
})

// ------------------------------------------------------------------- bar

test("bar label shows percent, watts or both", () => {
  assert.strictEqual(M.barLabel("percent", 87.4, 12, true), "87%")
  assert.strictEqual(M.barLabel("watts", 87, 12.3, true), "12 W")
  assert.strictEqual(M.barLabel("both", 87, 6.25, true), "87% 6.3 W")
  assert.strictEqual(M.barLabel("both", 100, 0, false), "100%")
  assert.strictEqual(M.barLabel("none", 50, 10, true), "")
  const e = { draw: 23.4, todayKwh: 0.4213, todayCost: "GH₵0.84" }
  assert.strictEqual(M.barLabel("draw", 87, 12, true, e), "23 W")
  assert.strictEqual(M.barLabel("draw", 87, 12, true, e, true), "87% 23 W", "percentage switched on")
  assert.strictEqual(M.barLabel("none", 87, 12, true, e, true), "87%")
  assert.strictEqual(M.barLabel("draw", -1, 0, false, e, true), "23 W", "a desktop has no percentage")
  assert.strictEqual(M.barLabel("percent-draw", 87, 12, true, e), "87% 23 W", "old value still works")
  assert.strictEqual(M.barLabel("draw", 87, 12, true, { draw: -1 }), "", "no reading, no number")
  assert.strictEqual(M.barLabel("today", -1, 0, false, e), "0.421 kWh")
  assert.strictEqual(M.barLabel("cost", -1, 0, false, e), "GH₵0.84")
  assert.strictEqual(M.barLabel("cost", -1, 0, false, { todayKwh: 12.34 }), "12.3 kWh", "no price: energy instead")
  assert.strictEqual(M.nextBarLabel("draw"), "today")
  assert.strictEqual(M.nextBarLabel("none"), "draw")
  assert.strictEqual(M.nextBarLabel("percent-draw"), "today")
  assert.strictEqual(M.barGpuSetting(true), "discrete")
  assert.strictEqual(M.barGpuSetting(false), "off")
  assert.strictEqual(M.barGpuSetting("both"), "both")
  const gpus = [
    { vendor: "Intel", integrated: true, state: "in-package", watts: null, busy: 72 },
    { vendor: "NVIDIA", integrated: false, state: "awake", watts: 11.8, busy: 3, temp: 53 }
  ]
  assert.strictEqual(M.gpuBadges(gpus, "discrete", "usage"), "󰢮 3%")
  assert.strictEqual(M.gpuBadges(gpus, "discrete", "both"), "󰢮 3% 12 W")
  assert.strictEqual(M.gpuBadges(gpus, "integrated", "usage"), "󰘚 72%")
  assert.strictEqual(M.gpuBadges(gpus, "both", "usage"), "󰘚 72%  󰢮 3%")
  assert.strictEqual(M.gpuBadges(gpus, "integrated", "watts"), "", "no iGPU watts: nothing to show")
  assert.strictEqual(M.gpuBadges([{ integrated: false, state: "asleep", watts: 0 }], "both", "usage"), "", "a sleeping GPU shows nothing")
  assert.strictEqual(M.gpuBadges(gpus, "off", "both"), "")
  assert.strictEqual(M.gpuLine(gpus[1]), "NVIDIA GPU awake · 12 W · 3% busy · 53 °C")
  assert.strictEqual(M.gpuLine({ vendor: "NVIDIA", integrated: false, state: "asleep", watts: 0 }), "NVIDIA GPU asleep")
  assert.strictEqual(M.gpuLine({ vendor: "Intel", integrated: true, state: "in-package", watts: null }), "")
  assert.strictEqual(M.gpuLine(gpus[0]), "Intel graphics · 72% busy")
  assert.strictEqual(M.gpuLine({ vendor: "Intel", integrated: true, state: "in-package", watts: 2.4 }), "Intel graphics · 2.4 W (in the CPU figure)")
})

// ------------------------------------------------------------------- care

const caps = (sysfs, upower) => ({ threshold: { sysfs: sysfs || {}, upower: upower || { supported: false } } })

test("charge limit backend picks the best available", () => {
  assert.strictEqual(M.chargeLimitBackend(caps()).kind, "none")
  assert.strictEqual(M.chargeLimitBackend(null).kind, "none")
  const sysfs = M.chargeLimitBackend(caps({ end: { value: 80, writable: true }, start: { value: 75, writable: true } }))
  assert.deepStrictEqual([sysfs.kind, sysfs.exact, sysfs.sailing, sysfs.end, sysfs.start], ["sysfs", true, true, 80, 75])
  assert.strictEqual(M.chargeLimitBackend(caps({ end: { value: 80, writable: true } })).sailing, false)
  assert.strictEqual(M.chargeLimitBackend(caps({ apple: { value: 100, writable: true } })).kind, "apple")
  const up = M.chargeLimitBackend(caps({ end: { value: 100, writable: false } }, { supported: true, enabled: true, start: 75, end: 80 }))
  assert.deepStrictEqual([up.kind, up.enabled, up.end], ["upower", true, 80])
  assert.strictEqual(M.chargeLimitBackend(caps({ end: { value: 100, writable: false } })).kind, "locked")
})

test("desired limit: off, limit, sailing, top-up, heat", () => {
  const exact = { kind: "sysfs", exact: true, sailing: true }
  assert.strictEqual(M.desiredLimit({ backend: { kind: "none" }, enabled: true, limit: 80 }), null)
  assert.deepStrictEqual(M.desiredLimit({ backend: exact, enabled: false }), { end: 100, start: 0, reason: "off" })
  assert.deepStrictEqual(M.desiredLimit({ backend: exact, enabled: true, limit: 80 }), { end: 80, start: 78, reason: "limit" })
  assert.deepStrictEqual(M.desiredLimit({ backend: exact, enabled: true, limit: 80, sailing: true, sailStart: 70 }), { end: 80, start: 70, reason: "limit" })
  assert.deepStrictEqual(M.desiredLimit({ backend: exact, enabled: true, limit: 80, sailing: true, sailStart: 95 }), { end: 80, start: 78, reason: "limit" })
  assert.strictEqual(M.desiredLimit({ backend: exact, enabled: true, limit: 20 }).end, 50)
  assert.deepStrictEqual(M.desiredLimit({ backend: exact, enabled: true, limit: 80, topUp: true }), { end: 100, start: 0, reason: "topup" })
  assert.deepStrictEqual(M.desiredLimit({ backend: exact, enabled: true, limit: 80, topUp: true, heatHolding: true, level: 64.7 }), { end: 64, start: 62, reason: "heat" })
  const end = M.desiredLimit({ backend: { kind: "apple", exact: true, sailing: false }, enabled: true, limit: 85 })
  assert.deepStrictEqual(end, { end: 85, start: -1, reason: "limit" })
  const up = { kind: "upower", exact: false }
  assert.strictEqual(M.upowerWanted(M.desiredLimit({ backend: up, enabled: true })), true)
  assert.strictEqual(M.upowerWanted(M.desiredLimit({ backend: up, enabled: true, topUp: true })), false)
  assert.strictEqual(M.upowerWanted(M.desiredLimit({ backend: up, enabled: false, heatHolding: true, topUp: true })), true)
  assert.strictEqual(M.upowerWanted(M.desiredLimit({ backend: up, enabled: false })), false)
})

test("limit matches skips pointless writes", () => {
  assert.ok(M.limitMatches({ end: 80, start: -1 }, { end: 80, start: 40 }))
  assert.ok(!M.limitMatches({ end: 80, start: 75 }, { end: 80, start: 40 }))
  assert.ok(!M.limitMatches({ end: 90, start: -1 }, { end: 80, start: -1 }))
})

test("heat hold has hysteresis", () => {
  assert.strictEqual(M.heatHold(-1, false, 40, 37), false)
  assert.strictEqual(M.heatHold(39.9, false, 40, 37), false)
  assert.strictEqual(M.heatHold(40, false, 40, 37), true)
  assert.strictEqual(M.heatHold(38, true, 40, 37), true)
  assert.strictEqual(M.heatHold(37, true, 40, 37), false)
})

test("unplug reminder fires once per charge", () => {
  let r = M.unplugReminder(79, true, 80, false)
  assert.deepStrictEqual(r, { notify: false, notified: false })
  r = M.unplugReminder(80, true, 80, false)
  assert.deepStrictEqual(r, { notify: true, notified: true })
  r = M.unplugReminder(82, true, 80, true)
  assert.strictEqual(r.notify, false)
  r = M.unplugReminder(78, true, 80, true)
  assert.strictEqual(r.notified, true)
  assert.strictEqual(M.unplugReminder(82, false, 80, true).notified, false)
  assert.strictEqual(M.unplugReminder(100, true, 100, false).notify, false)
})

test("low battery profile switches and restores", () => {
  const list = ["power-saver", "balanced", "performance"]
  let r = M.lowBatteryProfile(25, true, 20, null, "balanced", list)
  assert.strictEqual(r.apply, "")
  r = M.lowBatteryProfile(20, true, 20, null, "balanced", list)
  assert.deepStrictEqual(r, { apply: "power-saver", active: true, previous: "balanced" })
  assert.deepStrictEqual(M.lowBatteryProfile(22, true, 20, r, "power-saver", list), { apply: "", active: true, previous: "balanced" })
  assert.deepStrictEqual(M.lowBatteryProfile(24, true, 20, r, "power-saver", list), { apply: "balanced", active: false, previous: "" })
  assert.deepStrictEqual(M.lowBatteryProfile(21, false, 20, r, "power-saver", list), { apply: "", active: false, previous: "" })
  assert.strictEqual(M.lowBatteryProfile(10, true, 20, null, "balanced", ["balanced"]).apply, "")
  assert.strictEqual(M.lowBatteryProfile(10, true, 0, null, "balanced", list).apply, "")
  assert.strictEqual(M.lowBatteryProfile(10, true, 20, null, "power-saver", list).active, false)
})

test("keyboard level per source", () => {
  assert.strictEqual(M.keyboardLevel({ ac: 100, battery: 0 }, true, 3), 0)
  assert.strictEqual(M.keyboardLevel({ ac: 100, battery: 50 }, false, 3), 3)
  assert.strictEqual(M.keyboardLevel({ ac: 100, battery: 50 }, true, 255), 128)
  assert.strictEqual(M.keyboardLevel({ ac: -1 }, false, 3), -1)
  assert.strictEqual(M.keyboardLevel({ ac: 50 }, false, 0), -1)
})

test("calibration walks its phases", () => {
  const t0 = 1e12
  let s = { phase: "charge", startedAt: t0 }
  s = M.calibrationStep(s, 90, false, t0 + 1000)
  assert.strictEqual(s.phase, "charge")
  s = M.calibrationStep(s, 100, false, t0 + 2000)
  assert.strictEqual(s.phase, "hold")
  assert.strictEqual(s.startedAt, t0 + 2000)
  assert.strictEqual(M.calibrationStep(s, 100, false, t0 + 2000 + 30 * 60000).phase, "hold")
  assert.strictEqual(M.calibrationStep(s, 100, true, t0 + 3000).phase, "charge")
  s = M.calibrationStep(s, 100, false, t0 + 2000 + 60 * 60000)
  assert.strictEqual(s.phase, "drain")
  assert.match(s.message, /Unplug/)
  s = M.calibrationStep(s, 15, true, t0 + 1e7)
  assert.strictEqual(s.phase, "recharge")
  s = M.calibrationStep(s, 16, false, t0 + 1e7 + 1)
  assert.strictEqual(s.phase, "idle")
  assert.strictEqual(M.calibrationStep(null, 50, true, t0).phase, "idle")
})

// --------------------------------------------------------------- insights

test("daily totals accumulate and roll over", () => {
  const day = new Date(2026, 9, 3, 12).getTime()
  let days = M.accumulateDay({}, day, 1, true, 0.5, 0.2)
  days = M.accumulateDay(days, day + 60000, 1, false, 0, 0)
  assert.deepStrictEqual(days["2026-10-03"], { bat: 1, ac: 1, drained: 0.5, wh: 0.2 })
  for (let i = 1; i <= 20; i++) days = M.accumulateDay(days, day + i * 86400000, 1, true, 1, 1)
  assert.strictEqual(Object.keys(days).length, M.DAYS_KEPT)
  assert.ok(!days["2026-10-03"])
  const recent = M.recentDays({ "2026-10-03": { bat: 5, ac: 1, drained: 2, wh: 1 } }, day, 7)
  assert.strictEqual(recent.length, 7)
  assert.strictEqual(recent[6].key, "2026-10-03")
  assert.strictEqual(recent[6].label, "Sat")
  assert.strictEqual(recent[0].bat, 0)
})

test("discharge sessions start on unplug and close on plug-in", () => {
  let st = M.sessionUpdate(null, [], true, 1000, 90)
  assert.deepStrictEqual(st.current, { start: 1000, from: 90 })
  st = M.sessionUpdate(st.current, st.sessions, true, 5000, 85)
  assert.strictEqual(st.current.start, 1000)
  st = M.sessionUpdate(st.current, st.sessions, false, 1000 + 2 * 3600000, 50)
  assert.strictEqual(st.current, null)
  assert.deepStrictEqual(st.sessions[0], { start: 1000, end: 1000 + 2 * 3600000, from: 90, to: 50 })
  assert.strictEqual(M.sessionLine(st.sessions[0]), "2h · 90% → 50% · 20%/h")
  const short = M.sessionUpdate({ start: 0, from: 90 }, [], false, 60000, 89)
  assert.strictEqual(short.sessions.length, 0)
})

test("health log keeps one entry per day and a wear rate", () => {
  let log = M.recordHealth([], new Date(2026, 0, 1).getTime(), 80, 10)
  log = M.recordHealth(log, new Date(2026, 0, 1, 20).getTime(), 79, 11)
  assert.strictEqual(log.length, 1)
  assert.strictEqual(M.wearRate(log), -1)
  log = M.recordHealth(log, new Date(2026, 5, 1).getTime(), 74, 111)
  assert.strictEqual(M.wearRate(log), 5)
  assert.strictEqual(M.recordHealth(log, 0, -1, 0), log)
})

test("care tips follow the readings", () => {
  const tips = M.careTips({ health: 70, backend: "none", onAcShare: 0.9, temperature: 42 })
  assert.strictEqual(tips.length, 3)
  assert.deepStrictEqual(M.careTips({ health: 95, backend: "sysfs", temperature: -1 }), [])
  assert.match(M.careTips({ backend: "locked" })[0], /charge-limit\.md/)
})

// ----------------------------------------------------------------- system

test("system numbers", () => {
  assert.strictEqual(M.cpuUsage([0, 0, 0, 100, 0], [50, 0, 0, 150, 0]), 50)
  assert.strictEqual(M.cpuUsage(null, [1, 2, 3, 4]), -1)
  assert.deepStrictEqual(M.memoryUsage({ MemTotal: 1000, MemAvailable: 250 }), { used: 750, total: 1000, pct: 75 })
  assert.strictEqual(M.memoryUsage({}).pct, -1)
  assert.strictEqual(M.raplWatts(1e6, 0, 13e6, 2000), 6)
  assert.strictEqual(M.raplWatts(13e6, 0, 1e6, 2000), -1)
  assert.strictEqual(M.raplWatts(null, 0, 1, 1), -1)
  assert.strictEqual(M.formatBytes(68719476736), "64.0 GB")
  assert.deepStrictEqual(M.pushSeries([1, 2, 3], 4, 3), [2, 3, 4])
  const pts = M.seriesPoints([0, 100], 100, 50, 3)
  assert.deepStrictEqual(pts, [[50, 50], [100, 0]])
})

test("sysfs battery from the probe object, with temperature", () => {
  const b = M.parseSysfsBattery({ energy_full: "45000000", energy_full_design: "50000000", temp: "312", voltage_now: "14166000" })
  assert.strictEqual(b.health, 90)
  assert.strictEqual(b.temperature, 31.2)
  assert.strictEqual(b.voltage, 14.17)
  assert.strictEqual(M.parseSysfsBattery({}).temperature, -1)
})

test("report is markdown without private details", () => {
  const md = M.reportMarkdown({
    generated: "2026-10-03 12:00",
    battery: { maker: "LGC", model: "AP18E8M", technology: "Li-ion", health: 70, full: 40.3, design: 57.5, unit: "Wh", cycles: 67, temperature: -1, voltage: 14.2 },
    level: 87, limit: "", wearRate: -1,
    days: [{ key: "2026-10-03", bat: 90, ac: 30, drained: 40, wh: 20 }],
    sessions: [{ start: Date.UTC(2026, 9, 3, 8), end: Date.UTC(2026, 9, 3, 10), from: 90, to: 50 }],
    gadgets: [{ name: "Mouse", level: 40, charging: false }],
    tips: ["Tip"]
  })
  assert.match(md, /^# Battery report/)
  assert.match(md, /\| Health \| 70% \(Worn\) \|/)
  assert.match(md, /\| 2026-10-03 \| 1h 30m \| 30m \| 40% \| 20\.0 Wh \|/)
  assert.match(md, /- Mouse: 40%/)
  assert.ok(!/Temperature/.test(md))
  assert.match(M.reportMarkdown({}), /desktop/)
})

test("energy graph helpers", () => {
  assert.strictEqual(M.niceCeil(7), 10)
  assert.strictEqual(M.niceCeil(18), 20)
  assert.strictEqual(M.niceCeil(23), 25)
  assert.strictEqual(M.niceCeil(160), 200)
  assert.strictEqual(M.energyPeak([[0, 40], [1, null], [2, 12]]), 50)
  const segs = M.energySegments([[0, 10], [10, 20], [20, null], [30, 5]], 0, 40, 400, 100, 20)
  assert.deepStrictEqual(segs, [[[0, 50], [100, 0]], [[300, 75]]])
  assert.strictEqual(M.nearestPoint([[0, 1], [10, 2], [20, 3]], 0, 20, 200, 120), 1)
  assert.strictEqual(M.energyTimeLabel(new Date(2026, 9, 3, 9, 5).getTime(), 1), "09:05")
  assert.strictEqual(M.energyTimeLabel(new Date(2026, 9, 3, 9, 5).getTime(), 7), "Sat 3 Oct 09:05")
  assert.strictEqual(M.energyTimeLabel(new Date(2026, 9, 3).getTime(), 365), "3 Oct 2026")
  assert.strictEqual(M.percentText(0.756, "measured"), "76% measured")
  assert.strictEqual(M.formatKwh(0.0421), "0.042 kWh")
  assert.strictEqual(M.formatKwh(1.944), "1.94 kWh")
})

test("energy draw shares and calibration", () => {
  assert.deepStrictEqual(M.drawShares({ watts: 40, cpu_w: 20, gpu_w: 10, rest_w: 10 }), { cpu: 0.5, gpu: 0.25, rest: 0.25 })
  assert.strictEqual(M.drawShares({ watts: 40, cpu_w: null }), null)
  assert.strictEqual(M.calibratedBaseline(105, 0.89, 41, 15), 37.5)
  assert.strictEqual(M.calibratedBaseline(20, 0.89, 41, 15), -1, "below the measured parts")
  assert.strictEqual(M.calibratedBaseline("", 0.89, 41, 15), -1)
  assert.ok(M.untrackedText("cpu-counter-unreadable", false).indexOf("root") > 0)
})

test("device info text", () => {
  assert.strictEqual(M.formatUptime(90061), "1d 1h")
  assert.strictEqual(M.formatUptime(3720), "1h 2m")
  assert.strictEqual(M.formatMHz(4500), "4.50 GHz")
  assert.strictEqual(M.formatMHz(800), "800 MHz")
  assert.strictEqual(M.formatGB(352368590848), "328 GB")
  assert.strictEqual(M.formatGB(2000398934016), "1.8 TB")
  assert.strictEqual(M.cacheText({ L1d: "48K", L1i: "32K", L2: "1280K", L3: "12288K" }), "L1 48K + 32K · L2 1.25M · L3 12M")
  assert.strictEqual(M.swapText([{ kind: "zram", used: 0, size: 8 * 1073741824 }]), "zram 0 KB / 8.0 GB")
  const dev = {
    machine: { vendor: "Acer", product: "Nitro AN515-57", family: "Nitro 5", chassis: "Notebook", bios: "Insyde Corp. V1.20", biosDate: "07/06/2023", ec: "1.20" },
    os: { name: "Omarchy", kernel: "7.2.5", omarchy: "4.0.4-1" },
    cpu: { model: "Intel Core i5-11400H", cores: 6, threads: 12, minMHz: 800, maxMHz: 4500, caches: { L3: "12288K" } },
    memory: { total: 64 * 1073741824 },
    storage: { model: "SAMSUNG MZVLQ512", disk: "nvme0n1", size: 512110190592, fs: "btrfs", encrypted: true },
    pci: [{ kind: "Graphics", name: "NVIDIA GeForce RTX 3060 Mobile / Max-Q" }],
    usb: [{ name: "HD User Facing" }],
    battery: { maker: "LGC", model: "AP18E8M", chemistry: "Li-ion" }
  }
  const text = M.deviceSummary(dev, { uptime: 7200 })
  assert.match(text, /^Machine: Acer Nitro AN515-57 \(Nitro 5\)$/m)
  assert.match(text, /^Firmware: Insyde Corp. V1.20, 07\/06\/2023 · EC 1.20$/m)
  assert.match(text, /^System: Omarchy 4.0.4-1$/m)
  assert.strictEqual(M.osText({ name: "Arch Linux", omarchy: "4.0.4-1" }), "Arch Linux · Omarchy 4.0.4-1")
  assert.match(text, /^Clock: 800 MHz – 4.50 GHz$/m)
  assert.match(text, /^Disk: SAMSUNG MZVLQ512 · 476.9 GB$/m)
  assert.match(text, /^Root: btrfs, encrypted$/m)
  assert.match(text, /^Graphics: NVIDIA GeForce RTX 3060 Mobile \/ Max-Q$/m)
  assert.match(text, /^Uptime: 2h 0m$/m)
  assert.strictEqual(M.deviceSummary(null), "")
})

test("theme colours", () => {
  const toml = 'accent = "#e68e0d"\nbackground = "#121212"\nforeground = "#bebebe"\nred = "#D35F5F"\nyellow = "#b91c1c"\n' +
    'green = "#FFC107"\ncyan = "#bebebe"\nblue = "#e68e0d"\nmagenta = "#D35F5F"\n'
  const p = M.parseThemeColors(toml, "#cacccc", "#a55555")
  assert.strictEqual(p.accent, "#e68e0d")
  assert.strictEqual(p.red, "#d35f5f")
  const old = M.parseThemeColors('color1 = "#ff0000"\ncolor4 = "#0000ff"', "#123456", "#a55555")
  assert.strictEqual(old.red, "#ff0000")
  assert.strictEqual(old.blue, "#0000ff")
  assert.strictEqual(old.accent, "#123456")
  const s = M.seriesColors(p, 3, p.background)
  assert.strictEqual(s[0], "#e68e0d", "accent first")
  assert.strictEqual(new Set(s).size, 3)
  assert.ok(M.colorDistance(s[1], s[0]) >= 25 && M.colorDistance(s[2], s[1]) >= 25)
  assert.strictEqual(M.actionColor("shutdown", p), "#d35f5f")
  assert.strictEqual(M.actionColor("lock", p), "#e68e0d")
  assert.strictEqual(M.actionColor("reboot", p), "#b91c1c", "no orange in this theme: its yellow")
  assert.strictEqual(M.actionColor("reboot", {}, "#ffffff"), "#ffffff")
})

test("graph series helpers", () => {
  assert.deepStrictEqual(M.rangePoints([20, -1, 100], 100, 50, 3, 20, 100), [[0, 50], [100, 0]])
  let m = M.pushKeyed({}, { a: 10, b: 50 }, 3)
  m = M.pushKeyed(m, { a: 20 }, 3)
  assert.deepStrictEqual(m, { a: [10, 20], b: [50, -1] })
  m = M.pushKeyed(m, {}, 2)
  m = M.pushKeyed(m, {}, 2)
  assert.deepStrictEqual(m, {}, "gone once only gaps remain")
})

test("tabs", () => {
  assert.strictEqual(M.tabMeta("energy").label, "Energy")
  assert.strictEqual(M.tabMeta("nope").label, "nope")
  const p = { accent: "#e68e0d", green: "#ffc107", cyan: "#121212" }
  assert.strictEqual(M.tabTint("care", p, "#121212"), "#ffc107")
  assert.strictEqual(M.tabTint("insights", p, "#121212"), "#e68e0d", "too close to the background: the accent")
  assert.strictEqual(M.tabTint("unknown", p), "#e68e0d")
})

test("process rows", () => {
  const procs = [
    { pid: 1, ppid: 0, name: "systemd", cmd: "/sbin/init", user: "root", mine: false, cpu: 0.1, rss: 10, kernel: false },
    { pid: 900, ppid: 1, name: "Hyprland", cmd: "Hyprland", user: "me", mine: true, cpu: 3, rss: 200, kernel: false },
    { pid: 950, ppid: 900, name: "ghostty", cmd: "/usr/bin/ghostty", user: "me", mine: true, cpu: 9, rss: 150, kernel: false },
    { pid: 951, ppid: 950, name: "bash", cmd: "bash", user: "me", mine: true, cpu: 0, rss: 5, kernel: false },
    { pid: 2, ppid: 0, name: "kthreadd", cmd: "[kthreadd]", user: "root", mine: false, cpu: 0, rss: 0, kernel: true }
  ]
  assert.deepStrictEqual(M.processRows(procs, {}).map(p => p.pid), [950, 900, 1, 951])
  assert.deepStrictEqual(M.processRows(procs, { kernel: true }).map(p => p.pid).length, 5)
  assert.deepStrictEqual(M.processRows(procs, { mine: true, sort: "name" }).map(p => p.name), ["bash", "ghostty", "Hyprland"])
  assert.deepStrictEqual(M.processRows(procs, { sort: "mem" }).map(p => p.pid), [900, 950, 1, 951])
  const withGpu = procs.map(p => Object.assign({}, p, { gpu: p.pid === 951 ? 40 : (p.pid === 900 ? 2 : undefined) }))
  assert.deepStrictEqual(M.processRows(withGpu, { sort: "gpu" }).map(p => p.pid).slice(0, 2), [951, 900])
  assert.deepStrictEqual(M.processRows(procs, { sort: "pid", desc: true }).map(p => p.pid), [951, 950, 900, 1])
  assert.deepStrictEqual(M.processRows(procs, { query: "ghost" }).map(p => p.pid), [950])
  assert.deepStrictEqual(M.processRows(procs, { query: "951" }).map(p => p.pid), [951])
  const tree = M.processRows(procs, { tree: true })
  assert.deepStrictEqual(tree.map(p => [p.pid, p.depth]), [[1, 0], [900, 1], [950, 2], [951, 3]])
  assert.strictEqual(tree[0].children, 1)
  assert.strictEqual(M.procState("Z"), "zombie")
  assert.strictEqual(M.formatCpu(250.4), "250%")
  assert.strictEqual(M.formatCpu(3.25), "3.3%")
  assert.strictEqual(M.sinceText(1000, 1000 * 1000 + 7500 * 1000), "2h 05m")
})

test("ports", () => {
  const L = [
    { port: 5173, name: "Vite", dev: true, mine: true, reach: "local", owner: "mine", project: "shop", projectPath: "/w/shop", process: "node", cmd: "vite" },
    { port: 8000, name: "Django", dev: true, mine: true, reach: "network", owner: "mine", project: "api", projectPath: "/w/api", process: "python3", cmd: "manage.py runserver" },
    { port: 5432, name: "postgres", dev: true, mine: false, reach: "local", owner: "container", project: "api", projectPath: "", process: "", cmd: "", container: { id: "abc" } },
    { port: 631, name: "CUPS printing", dev: false, mine: false, reach: "local", owner: "system", project: "", projectPath: "", process: "", cmd: "" },
    { port: 41000, name: "Syncthing", dev: false, mine: true, reach: "network", owner: "mine", project: "", projectPath: "", process: "syncthing", cmd: "syncthing" }
  ]
  assert.deepStrictEqual(M.portCounts(L), { dev: 3, mine: 3, exposed: 2, all: 5, devExposed: 1 })
  assert.deepStrictEqual(M.portGroups(L, "dev").map(g => g.label), ["api", "shop", "api"])
  assert.deepStrictEqual(M.portGroups(L, "dev").map(g => g.rank), [0, 0, 1])
  assert.deepStrictEqual(M.portGroups(L, "all").map(g => g.label), ["api", "shop", "api", "Your other sockets", "System"])
  assert.deepStrictEqual(M.portGroups(L, "exposed").map(g => g.rows.map(r => r.port)), [[8000], [41000]])
  assert.deepStrictEqual(M.portGroups(L, "all", "51").map(g => g.rows[0].port), [5173])
  assert.deepStrictEqual(M.portGroups(L, "all", "django").map(g => g.rows[0].port), [8000])
  assert.strictEqual(M.reachLabel("vpn"), "VPN")
  assert.deepStrictEqual(M.portsBadge(L, true), { text: "󰒍 3 󰀪", active: true })
  assert.deepStrictEqual(M.portsBadge(L.filter(r => r.reach === "local"), true), { text: "󰒍 2", active: true })
  assert.deepStrictEqual(M.portsBadge([L[3]], true), { text: "󰒍 0", active: false }, "shown at 0 too, not red")
  assert.deepStrictEqual(M.portsBadge(L, false), { text: "", active: false })
  assert.strictEqual(M.portUrl({ port: 3000 }), "http://localhost:3000")
})

test("plugins", () => {
  const installed = [
    { id: "omarchy.clock", name: "Clock", author: "", description: "", enabled: true, firstParty: true },
    { id: "aurora-pulse", name: "AuroraPulse", author: "Charles", description: "radio", enabled: true, firstParty: false },
    { id: "x.y", name: "Old thing", author: "", description: "", enabled: false, firstParty: false }
  ]
  const updates = { plugins: { "aurora-pulse": { update: true } } }
  assert.deepStrictEqual(M.installedCounts(installed, updates), { all: 3, enabled: 2, disabled: 1, third: 2, updates: 1 })
  assert.deepStrictEqual(M.installedRows(installed, "updates", "", updates).map(p => p.id), ["aurora-pulse"])
  assert.deepStrictEqual(M.installedRows(installed, "third", "radio", updates).map(p => [p.id, p.update]), [["aurora-pulse", true]])
  assert.deepStrictEqual(M.installedRows(installed, "disabled", "").map(p => p.id), ["x.y"])
  const cat = [
    { id: "a", name: "Battery Pro", description: "", stars: 5, category: "Hardware", installAvailable: true, repositoryUpdatedAt: "2026-01-01", tags: [] },
    { id: "b", name: "Battery", description: "", stars: 1, category: "Hardware", installAvailable: true, repositoryUpdatedAt: "2026-09-01", tags: [] },
    { id: "c", name: "Clock", description: "shows battery too", stars: 900, category: "Widgets", installAvailable: false, repositoryUpdatedAt: "2026-05-01", tags: [] }
  ]
  assert.deepStrictEqual(M.catalogRows(cat, { query: "battery" }).map(p => p.id), ["b", "a", "c"], "exact, prefix, description")
  assert.deepStrictEqual(M.catalogRows(cat, {}).map(p => p.id), ["c", "a", "b"])
  assert.deepStrictEqual(M.catalogRows(cat, { sort: "recent" }).map(p => p.id), ["b", "c", "a"])
  assert.deepStrictEqual(M.catalogRows(cat, { category: "Hardware", sort: "name" }).map(p => p.id), ["b", "a"])
  assert.deepStrictEqual(M.catalogRows(cat, { installable: true }).map(p => p.id), ["a", "b"])
  assert.strictEqual(M.catalogRows(cat, { installed: { a: true } }).filter(p => p.installed).length, 1)
  assert.strictEqual(M.movedSinceReview({ upstreamValidatedCommit: "aaa", upstreamObservedCommit: "bbb" }), true)
  assert.strictEqual(M.movedSinceReview({ upstreamValidatedCommit: "aaa", upstreamObservedCommit: "aaa" }), false)
  assert.strictEqual(M.reviewedCommit({ upstreamValidatedCommit: "a".repeat(40) }), "a".repeat(40))
  assert.strictEqual(M.reviewedCommit({ listingValidatedCommit: "abc" }), "", "not a full commit")
  assert.strictEqual(M.formatStars(1234), "1.2k")
  assert.strictEqual(M.formatStars(2000), "2k")
})

test("marketplace stats and true hues", () => {
  const cat = [
    { id: "a", name: "A", stars: 5, installAvailable: true, tags: [] },
    { id: "b", name: "B", stars: 50, installAvailable: true, tags: [] }
  ]
  const stats = { a: { hearts: 9, views: 100, installs: 3 }, b: { hearts: 1, views: 10, installs: 30 } }
  assert.deepStrictEqual(M.catalogRows(cat, { sort: "hearts", stats }).map(p => p.id), ["a", "b"])
  assert.deepStrictEqual(M.catalogRows(cat, { sort: "installs", stats }).map(p => p.id), ["b", "a"])
  assert.strictEqual(M.catalogRows(cat, { stats })[1].hearts, 9)
  assert.strictEqual(M.catalogRows(cat, {})[0].hearts, 0)
  const orangeTheme = { blue: "#e68e0d", green: "#ffc107", accent: "#e68e0d" }
  assert.strictEqual(M.hueTint(orangeTheme, "blue"), "#4a9eff", "no real blue: a plain one")
  assert.strictEqual(M.hueTint(orangeTheme, "green"), "#4caf50")
  assert.strictEqual(M.hueTint({ blue: "#7aa2f7", green: "#9ece6a" }, "blue"), "#7aa2f7", "Tokyo Night's blue")
  assert.strictEqual(M.hueTint({ blue: "#7aa2f7", green: "#9ece6a" }, "green"), "#9ece6a")
  assert.strictEqual(M.formatCount(6902), "6.9k")
  assert.strictEqual(M.formatCount(25000), "25k")
})

test("settings sections", () => {
  const schema = [{ key: "barLabel" }, { key: "lowLevel" }, { key: "showPercentage" }, { key: "brandNew" }]
  const out = M.settingSections(schema)
  assert.deepStrictEqual(out.map(g => g.title), ["BAR", "BATTERY AND WARNINGS", "OTHER"])
  assert.deepStrictEqual(out[0].schema.map(e => e.key), ["showPercentage", "barLabel"], "group order, not schema order")
  assert.deepStrictEqual(out[2].schema.map(e => e.key), ["brandNew"])
})

test("bar layout", () => {
  const list = [
    { id: "clock", kinds: ["bar-widget"], enabled: true, bar: { section: "center", index: 0 } },
    { id: "net", kinds: ["bar-widget"], enabled: true, bar: { section: "right", index: 2 } },
    { id: "audio", kinds: ["bar-widget"], enabled: true, bar: { section: "right", index: 1 } },
    { id: "spare", kinds: ["bar-widget"], enabled: true, bar: null },
    { id: "off", kinds: ["bar-widget"], enabled: false, bar: null },
    { id: "svc", kinds: ["service"], enabled: true, bar: null }
  ]
  const b = M.barLayout(list)
  assert.deepStrictEqual(b.right.map(p => p.id), ["audio", "net"])
  assert.deepStrictEqual(b.center.map(p => p.id), ["clock"])
  assert.deepStrictEqual(b.unplaced.map(p => p.id), ["spare"])
  assert.deepStrictEqual(b.left, [])
})

test("acer health mode", () => {
  const b = M.chargeLimitBackend({ threshold: { sysfs: { acer: { value: 0, writable: true } }, upower: {} } })
  assert.deepStrictEqual([b.kind, b.enabled, b.end, b.exact], ["acer", false, 80, false])
  assert.strictEqual(M.chargeLimitBackend({ threshold: { sysfs: { acer: { value: 1, writable: false } }, upower: {} } }).kind, "locked")
  const want = M.desiredLimit({ backend: b, enabled: true, limit: 80 })
  assert.strictEqual(M.upowerWanted(want), true)
  assert.strictEqual(M.upowerWanted(M.desiredLimit({ backend: b, enabled: false })), false)
  assert.strictEqual(M.upowerWanted(M.desiredLimit({ backend: b, enabled: true, topUp: true })), false, "top-up lifts it")
})

test("dev rules", () => {
  assert.deepStrictEqual(M.parsePortRanges("33000-34000, 8787;bad 70000 5-3"), [[33000, 34000], [8787, 8787]])
  const data = { listeners: [
    { port: 33489, proto: "tcp", process: "antigravity-ide", mine: true, pid: 1, dev: false, http: false },
    { port: 22000, proto: "tcp", process: "syncthing", mine: true, pid: 2, dev: true, http: true },
    { port: 9999, proto: "udp", process: "", mine: false, pid: null, dev: false, http: false }
  ] }
  const ruled = M.withDevRules(data, { ports: "9999", dev: "Antigravity-IDE", notDev: "syncthing" }).listeners
  assert.deepStrictEqual(ruled.map(r => [r.dev, !!r.ruled]), [[true, true], [false, true], [true, true]])
  assert.strictEqual(ruled[0].http, true)
  assert.strictEqual(ruled[2].http, false, "udp is never opened in a browser")
  assert.strictEqual(M.withDevRules(data, {}).listeners[0], data.listeners[0], "no rules, rows untouched")
  assert.deepStrictEqual(M.toggleDevProgram({ dev: "a, b", notDev: "c" }, "C", true), { devPrograms: "a, b, c", notDevPrograms: "" })
  assert.deepStrictEqual(M.toggleDevProgram({ dev: "a, b", notDev: "" }, "a", false), { devPrograms: "b", notDevPrograms: "a" })
})

console.log(failures === 0 ? "\nAll tests passed." : `\n${failures} test(s) failed.`)
process.exit(failures === 0 ? 0 : 1)

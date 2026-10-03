.pragma library

// Pure helpers for OmniSystem Center. No QML types, no processes: everything here
// takes plain values and returns plain values, so tests/model.test.js can run
// it under node.
//
// Three parts:
//   1. The laptop battery: icon, mode, charge threshold, stats, health,
//      history, warnings and the critical action. Ported from Omarchy's own
//      Power widget (MIT) and extended.
//   2. Power: profiles (one remembered per power source), keep awake, the
//      sleep timer and the power actions (from Power Menu, MIT).
//   3. Gadget batteries: every source normalised to one shape, merged,
//      charging estimated, notifications. Ported from Gadget Batteries (MIT).

// ===================================================== 1. the laptop battery

function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

// A laptop that holds its charge below 100% (a charge limit) reports odd
// states; this says when that is what is happening.
function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))

  if (chargeThresholdActive(d, onBattery, states)) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""
  if (chargeThresholdActive(d, onBattery, states)) return "Holding at charge limit"
  if (onBattery) return "On battery"
  if (d.percentage >= 1) return "Fully charged"
  return "Charging"
}

// `omarchy-battery-status --shell` and `omarchy-system-stats` print
// "key<TAB>value" lines.
function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

// "1h 6m", "42m", "3h". Seconds in; "" for nothing sensible.
function formatDuration(seconds) {
  var s = Math.round(Number(seconds))
  if (!isFinite(s) || s <= 0) return ""
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (m === 60) { h += 1; m = 0 }
  if (h > 0 && m > 0) return h + "h " + m + "m"
  if (h > 0) return h + "h"
  return Math.max(1, m) + "m"
}

function formatWatts(watts) {
  var w = Math.abs(Number(watts))
  if (!isFinite(w) || w < 0.05) return ""
  return (w >= 10 ? w.toFixed(0) : w.toFixed(1)) + " W"
}

// The battery's own numbers from /sys/class/power_supply/BAT*/, printed as
// "file<TAB>value" lines. Capacity is reported as energy (µWh) or as charge
// (µAh); either gives health as "full now / full when new".
function parseSysfsBattery(raw) {
  // Either those lines or the probe's { file: value } object.
  var kv = raw && typeof raw === "object" ? raw : parseKeyValue(raw)
  function num(key) {
    var n = Number(kv[key])
    return isFinite(n) && n > 0 ? n : 0
  }
  var full = num("energy_full"), design = num("energy_full_design"), unit = "Wh"
  if (!full || !design) {
    full = num("charge_full")
    design = num("charge_full_design")
    unit = "Ah"
  }
  var health = full && design ? Math.max(0, Math.min(100, Math.round(full / design * 100))) : -1
  var limit = Number(kv.charge_control_end_threshold)
  var temp = Number(kv.temp)
  var volts = Number(kv.voltage_now)
  return {
    // Tenths of a degree in sysfs; -1 when the battery reports none.
    temperature: isFinite(temp) && temp > 0 ? Math.round(temp) / 10 : -1,
    voltage: isFinite(volts) && volts > 0 ? Math.round(volts / 1e4) / 100 : 0,
    full: full ? full / 1e6 : 0,
    design: design ? design / 1e6 : 0,
    unit: full && design ? unit : "",
    health: health,
    wear: health >= 0 ? 100 - health : -1,
    cycles: num("cycle_count"),
    chargeLimit: isFinite(limit) && limit > 0 && limit < 100 ? Math.round(limit) : -1,
    maker: String(kv.manufacturer || "").trim(),
    model: String(kv.model_name || "").trim(),
    technology: String(kv.technology || "").trim()
  }
}

function healthLabel(health) {
  if (health < 0) return ""
  if (health >= 90) return "Good"
  if (health >= 75) return "Fair"
  if (health >= 50) return "Worn"
  return "Replace soon"
}

// Low and critical warnings while discharging, each once until the battery
// charges or climbs a few points back above the threshold. `notified` is
// { low: bool, critical: bool }; returns what to do and the updated flags.
var REARM_MARGIN = 3

function batteryWarnings(level, discharging, low, critical, notified) {
  var was = notified || {}
  var out = { notifyLow: false, notifyCritical: false, notified: { low: false, critical: false } }
  if (level < 0) return out
  var isLow = discharging && low > 0 && level <= low
  var isCritical = discharging && critical > 0 && level <= critical
  out.notifyCritical = isCritical && !was.critical
  // Critical supersedes low: no separate low warning in the same moment.
  out.notifyLow = isLow && !isCritical && !was.low && !was.critical
  out.notified.low = isLow || (!!was.low && discharging && level <= low + REARM_MARGIN)
  out.notified.critical = isCritical || (!!was.critical && discharging && level <= critical + REARM_MARGIN)
  return out
}

// The critical action actually taken: hibernate needs hibernation set up,
// suspend can be turned off in Omarchy; then fall back, or do nothing.
function resolveCriticalAction(setting, hibernateAvailable, suspendAvailable) {
  var want = String(setting || "none")
  if (want === "hibernate") return hibernateAvailable ? "hibernate" : (suspendAvailable ? "suspend" : "none")
  if (want === "suspend") return suspendAvailable ? "suspend" : "none"
  return "none"
}

// A critical countdown that was running when the shell reloaded. It carries on
// while the battery is still draining and low, with at least `CRITICAL_MIN_RESUME`
// left so the warning is seen again; otherwise it is dropped. Returns the new
// end time, or 0.
var CRITICAL_MIN_RESUME = 30000

function resumeCritical(saved, nowMs, discharging, level, critical) {
  if (!saved || typeof saved !== "object") return 0
  var endsAt = Number(saved.endsAt)
  if (!isFinite(endsAt) || endsAt <= 0) return 0
  if (!discharging || level < 0 || critical <= 0 || level > critical + REARM_MARGIN) return 0
  return Math.max(endsAt, nowMs + CRITICAL_MIN_RESUME)
}

// Charge history: one sample a minute, the last `maxAgeMs` kept.
// A sample is [timeMs, percent, watts]; a gap longer than a few minutes (the
// machine was asleep or off) is kept, and the graph draws it as a break.
var HISTORY_MAX_AGE = 6 * 60 * 60 * 1000

function addSample(history, nowMs, percent, watts, maxAgeMs) {
  var keep = maxAgeMs || HISTORY_MAX_AGE
  var list = (history || []).filter(function (s) {
    return Array.isArray(s) && s.length >= 2 && nowMs - s[0] <= keep && s[0] <= nowMs
  })
  if (percent >= 0) {
    var last = list.length ? list[list.length - 1] : null
    // Faster than once every 50 s is a duplicate (several triggers at once).
    if (!last || nowMs - last[0] >= 50000) list.push([nowMs, Math.round(percent), Math.round(Number(watts || 0) * 10) / 10])
  }
  return list
}

// Points for the history graph in a w x h box, oldest left, newest right, as
// segments split at gaps. The x axis is the full window, so a short history
// sits at the right instead of being stretched.
var HISTORY_GAP = 5 * 60 * 1000

function historySegments(history, nowMs, w, h, maxAgeMs) {
  var span = maxAgeMs || HISTORY_MAX_AGE
  var start = nowMs - span
  var segments = []
  var current = []
  var prevT = null
  for (var i = 0; i < (history || []).length; i++) {
    var s = history[i]
    if (s[0] < start) continue
    if (prevT !== null && s[0] - prevT > HISTORY_GAP && current.length) {
      segments.push(current)
      current = []
    }
    current.push([(s[0] - start) / span * w, h - Math.max(0, Math.min(100, s[1])) / 100 * h])
    prevT = s[0]
  }
  if (current.length) segments.push(current)
  return segments
}

// Average discharge over the recent history, %/hour, from the steepest
// continuous run of falling samples in the last hour (0 when not enough data).
function drainPerHour(history, nowMs) {
  var recent = (history || []).filter(function (s) { return nowMs - s[0] <= 60 * 60 * 1000 })
  if (recent.length < 3) return 0
  var first = recent[0], last = recent[recent.length - 1]
  var hours = (last[0] - first[0]) / 3600000
  if (hours < 0.1 || last[1] >= first[1]) return 0
  return Math.round((first[1] - last[1]) / hours * 10) / 10
}

// ================================================================= 2. power

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return { profiles: list, activeProfile: active, profileIndex: clampIndex(previousIndex || 0, list.length) }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function profileLabel(name) {
  var s = String(name || "")
  if (s === "power-saver") return "Power saver"
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : ""
}

// Omarchy remembers one profile for AC and one for battery. Choosing for the
// power source in use applies it (omarchy-powerprofiles-set does both);
// choosing for the other source only records it, so plugging in later
// applies it, without switching the profile now.
function profileChange(source, onBattery) {
  var current = onBattery ? "battery" : "ac"
  return source === current ? "apply" : "remember"
}

// Omarchy's defaults when nothing is remembered: performance on AC when
// offered, balanced otherwise.
function rememberedProfile(saved, source, profiles) {
  var list = profiles || []
  var value = String(saved || "").trim()
  if (value && list.indexOf(value) >= 0) return value
  if (source === "ac" && list.indexOf("performance") >= 0) return "performance"
  return list.indexOf("balanced") >= 0 ? "balanced" : (list[0] || "")
}

// The power actions, Power Menu's six, with Omarchy's own commands. Suspend
// and hibernate go through logind (loginctl), which is what systemctl hands
// them to as well.
var POWER_ACTIONS = [
  { key: "lock", icon: "󰌾", label: "Lock", command: ["omarchy-system-lock"], confirm: false },
  { key: "logout", icon: "󰍃", label: "Logout", command: ["omarchy-system-logout"], confirm: true },
  { key: "suspend", icon: "󰒲", label: "Suspend", command: ["loginctl", "suspend"], confirm: false },
  { key: "hibernate", icon: "󰤁", label: "Hibernate", command: ["loginctl", "hibernate"], confirm: false },
  { key: "reboot", icon: "󰜉", label: "Reboot", command: ["omarchy-system-reboot"], confirm: true },
  { key: "shutdown", icon: "󰐥", label: "Shutdown", command: ["omarchy-system-shutdown"], confirm: true }
]

function powerActions(suspendAvailable, hibernateAvailable) {
  return POWER_ACTIONS.filter(function (a) {
    if (a.key === "suspend") return !!suspendAvailable
    if (a.key === "hibernate") return !!hibernateAvailable
    return true
  })
}

function powerAction(key) {
  for (var i = 0; i < POWER_ACTIONS.length; i++) if (POWER_ACTIONS[i].key === key) return POWER_ACTIONS[i]
  return null
}

// The sleep timer: suspend or shut down after a delay. Saved so a shell
// restart keeps it; one that ran out while the shell was down is dropped
// rather than firing by surprise.
var TIMER_ACTIONS = ["suspend", "hibernate", "shutdown"]
var TIMER_PRESETS = [15, 30, 45, 60, 90, 120]
var TIMER_GRACE = 2 * 60 * 1000

function timerRemaining(endsAt, nowMs) {
  var left = Math.ceil((Number(endsAt) - nowMs) / 1000)
  return isFinite(left) && left > 0 ? left : 0
}

function formatCountdown(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  function two(n) { return n < 10 ? "0" + n : String(n) }
  return h > 0 ? h + ":" + two(m) + ":" + two(sec) : m + ":" + two(sec)
}

function restoreTimer(saved, nowMs) {
  if (!saved || typeof saved !== "object") return null
  var endsAt = Number(saved.endsAt)
  if (!isFinite(endsAt) || TIMER_ACTIONS.indexOf(saved.action) < 0) return null
  if (endsAt < nowMs - TIMER_GRACE) return null
  return { endsAt: endsAt, action: saved.action, minutes: Number(saved.minutes) || 0 }
}

// The order of the panel's sections: on a laptop the battery leads and the
// gadgets sit in the middle; on a desktop (no battery) the gadgets lead.
// The power controls are always last, at the bottom.
function sectionOrder(hasBattery) {
  return hasBattery
    ? ["battery", "gadgets", "profiles", "awake", "power"]
    : ["gadgets", "profiles", "awake", "power"]
}

// ======================================================= 3. gadget batteries

// Every source is normalised to
//   { key, name, kind, level (0-100), charging, detail, offline }
// `charging` is true or false when the source knows, and null when it cannot
// tell (then applyTrends estimates).

var KIND_ICONS = {
  mouse: "\u{F037D}",     // nf-md-mouse
  keyboard: "\u{F030C}",  // nf-md-keyboard
  headset: "\u{F02CE}",   // nf-md-headset
  earbuds: "\u{F184F}",   // nf-md-earbuds
  gamepad: "\u{F0297}",   // nf-md-gamepad_variant
  speaker: "\u{F04C3}",   // nf-md-speaker
  phone: "\u{F011C}",     // nf-md-cellphone
  tablet: "\u{F04F6}",    // nf-md-tablet
  watch: "\u{F0589}",     // nf-md-watch
  other: "\u{F0FB0}"      // nf-md-devices
}

// External/collector kinds (theleif/omarchy-peripheral-batteries vocabulary)
// folded onto the icons above.
var EXTERNAL_KINDS = {
  mouse: "mouse", touchpad: "mouse", pen: "mouse",
  keyboard: "keyboard",
  headset: "headset", headphones: "headset", earbuds: "earbuds",
  gamepad: "gamepad", speaker: "speaker",
  phone: "phone", tablet: "tablet", watch: "watch"
}

// Kinds UPower reports for things that are not peripherals.
var IGNORED_UPOWER_TYPES = ["unknown", "linepower", "battery", "ups", "monitor", "computer"]

function kindIcon(kind) {
  return KIND_ICONS[kind] || KIND_ICONS.other
}

function gadgetBatteryIcon(level, charging) {
  if (level < 0) return "\u{F0091}" // nf-md-battery_unknown
  if (charging) return "\u{F0084}"  // nf-md-battery_charging
  if (level <= 5) return "\u{F0083}" // nf-md-battery_alert
  if (level >= 95) return "\u{F0079}" // nf-md-battery
  // nf-md-battery_10 .. battery_90 are consecutive code points.
  var step = Math.max(1, Math.min(9, Math.round(level / 10)))
  return String.fromCodePoint(0xF007A + step - 1)
}

function kindFromUPowerType(typeName) {
  var t = String(typeName || "").toLowerCase()
  if (t === "mouse" || t === "touchpad" || t === "pen") return "mouse"
  if (t === "keyboard") return "keyboard"
  if (t === "headset" || t === "headphones") return "headset"
  if (t === "speakers") return "speaker"
  if (t === "gaminginput") return "gamepad"
  if (t === "phone") return "phone"
  if (t === "tablet") return "tablet"
  return "other"
}

// UPower's "unknown" state (a Logitech mouse on its charging cable) is
// reported as null so applyTrends can estimate; every other state is known.
function fromUPower(device, typeName, chargingState, unknownState) {
  if (!device || !device.isPresent || device.powerSupply || device.isLaptopBattery) return null
  if (IGNORED_UPOWER_TYPES.indexOf(String(typeName || "").toLowerCase()) >= 0) return null
  var level = Math.round(Math.max(0, Math.min(1, device.percentage)) * 100)
  return {
    key: "upower:" + device.nativePath,
    name: device.model || typeName || "Device",
    kind: kindFromUPowerType(typeName),
    level: level,
    charging: device.state === unknownState ? null : device.state === chargingState,
    detail: ""
  }
}

// `headsetcontrol -o json` output. Headsets whose battery cannot be read
// right now (powered off, asleep) are skipped instead of shown as 0%.
function fromHeadsetControl(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return [] }
  var devices = parsed && Array.isArray(parsed.devices) ? parsed.devices : []
  var out = []
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i] || {}
    var battery = d.battery || {}
    var status = String(battery.status || "")
    if (status !== "BATTERY_AVAILABLE" && status !== "BATTERY_CHARGING") continue
    var level = Number(battery.level)
    if (!isFinite(level) || level < 0) continue
    out.push({
      key: "headsetcontrol:" + (d.id_vendor || "") + ":" + (d.id_product || "") + ":" + i,
      name: d.device || d.product || "Headset",
      kind: "headset",
      level: Math.min(100, Math.round(level)),
      charging: status === "BATTERY_CHARGING",
      detail: ""
    })
  }
  return out
}

// omarchy-buds status.json (written by GalaxyBudsClient's hook).
function fromBudsStatus(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (e) { return [] }
  if (!parsed || parsed.connected !== true) return []
  var battery = parsed.battery || {}
  var parts = []
  var levels = []
  var charging = false
  var sides = [["left", "L"], ["right", "R"], ["case", "Case"]]
  for (var i = 0; i < sides.length; i++) {
    var b = battery[sides[i][0]]
    if (!b || b.available !== true || b.level < 0) continue
    parts.push(sides[i][1] + " " + b.level + "%")
    // The case level is informative; the earbuds are what run out.
    if (sides[i][0] !== "case") {
      levels.push(b.level)
      charging = charging || b.charging === true
    }
  }
  if (levels.length === 0) return []
  return [{
    key: "buds:" + (parsed.address || ""),
    name: parsed.device_name || "Galaxy Buds",
    kind: "earbuds",
    level: Math.min.apply(null, levels),
    charging: charging,
    detail: parts.join(" · ")
  }]
}

function partsDetail(left, right, caseLevel) {
  var parts = []
  if (left >= 0) parts.push("L " + left + "%")
  if (right >= 0) parts.push("R " + right + "%")
  if (caseLevel >= 0) parts.push("Case " + caseLevel + "%")
  return parts.join(" · ")
}

function clampLevel(value) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? Math.min(100, Math.round(n)) : -1
}

// External JSON file and collectors.d output, one entry per device:
//   { id, name, kind, pct, charging, ts, ttl, left?, right?, case?, transport? }
// Entries past ts + ttl stay listed as offline instead of showing a stale level.
function fromExternal(raw, nowSec) {
  var list
  try { list = typeof raw === "string" ? JSON.parse(raw || "[]") : raw } catch (e) { return [] }
  if (!Array.isArray(list)) return []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!e || typeof e !== "object" || !e.name) continue
    var level = clampLevel(e.pct)
    if (level < 0) continue
    var ts = Number(e.ts), ttl = Number(e.ttl)
    out.push({
      key: "external:" + (e.id || e.name),
      name: String(e.name),
      kind: EXTERNAL_KINDS[String(e.kind || "").toLowerCase()] || "other",
      level: level,
      // A missing or non-boolean field means the source does not know.
      charging: typeof e.charging === "boolean" ? e.charging : null,
      detail: partsDetail(clampLevel(e.left), clampLevel(e.right), clampLevel(e["case"])),
      offline: isFinite(ts) && isFinite(ttl) && ttl > 0 && nowSec > ts + ttl
    })
  }
  return out
}

// Sources name the same gadget slightly differently ("G502 X PLUS" vs
// "Logitech G502 X PLUS", "G522 LIGHTSPEED - Wireless Mode" / "- USB Mode").
function sameDeviceKey(name) {
  return String(name).toLowerCase()
    .replace(/\s*-\s*(wireless|usb) mode$/, "")
    .replace(/^logitech\s+/, "")
    .replace(/[^a-z0-9]/g, "")
}

// Merge sources, dropping later duplicates by name, lowest battery first.
// Pass the most detailed source first (Buds before UPower).
function mergeDevices(lists) {
  var seen = {}
  var out = []
  for (var i = 0; i < lists.length; i++) {
    var list = lists[i] || []
    for (var j = 0; j < list.length; j++) {
      var d = list[j]
      if (!d) continue
      var name = sameDeviceKey(d.name)
      if (seen[name]) continue
      seen[name] = true
      out.push(d)
    }
  }
  // Offline entries last, then lowest battery first.
  out.sort(function (a, b) {
    if (!!a.offline !== !!b.offline) return a.offline ? 1 : -1
    return a.level - b.level
  })
  return out
}

// Gadgets that just crossed below `threshold` while not charging, and the
// updated set of already-notified keys. A gadget re-arms once it is charging
// or back above threshold + 5.
function gadgetLowAlerts(devices, threshold, notified) {
  var next = {}
  var alerts = []
  if (!(threshold > 0)) return { alerts: alerts, notified: next }
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i]
    if (d.offline) continue
    var low = !d.charging && d.level <= threshold
    var wasNotified = notified && notified[d.key] === true
    if (low && !wasNotified) alerts.push(d)
    if (low || (wasNotified && !d.charging && d.level <= threshold + 5)) next[d.key] = true
  }
  return { alerts: alerts, notified: next }
}

// Once per charge: a gadget charging that reaches 100%. It re-arms when it
// stops charging and drops below 95%.
function gadgetFullAlerts(devices, notified) {
  var next = {}
  var alerts = []
  for (var i = 0; i < devices.length; i++) {
    var g = devices[i]
    if (g.offline) continue
    var wasFull = notified && notified[g.key] === true
    if (g.charging && g.level >= 100 && !wasFull) alerts.push(g)
    if ((g.charging || wasFull) && g.level >= 95) next[g.key] = g.level >= 100 || wasFull
  }
  return { alerts: alerts, notified: next }
}

// Infer charging for gadgets that cannot tell (charging === null), such as a
// Logitech mouse on its cable (UPower "unknown"). It is never inferred against
// an explicit true/false. Levels from such sources jitter by about 1 point,
// so charging is only estimated once the level is MIN_RISE points above the
// lowest level seen within RISE_WINDOW seconds. Any drop restarts the window
// and does not become its baseline (a jitter dip like 66 -> 65 must not turn
// the next 67 into a 2-point rise). The estimate lasts RISE_WINDOW seconds
// after the last such rise. `trends` is key -> {level, samples, riseTs}.
var RISE_WINDOW = 1200
var MIN_RISE = 2

function applyTrends(devices, trends, nowSec) {
  var next = {}
  var out = []
  for (var i = 0; i < devices.length; i++) {
    var d = Object.assign({}, devices[i])
    var prev = trends ? trends[d.key] : null
    var samples = prev && prev.samples ? prev.samples.slice() : []
    var riseTs = prev ? prev.riseTs || 0 : 0
    var level = d.offline && prev ? prev.level : d.level
    if (!d.offline) {
      if (prev && d.level < prev.level) {
        samples = []
        riseTs = 0
      } else {
        samples = samples.filter(function (s) { return nowSec - s[0] <= RISE_WINDOW })
        if (samples.length === 0 || samples[samples.length - 1][1] !== d.level) samples.push([nowSec, d.level])
        var lowest = Math.min.apply(null, samples.map(function (s) { return s[1] }))
        var rose = !prev || d.level > prev.level
        if (rose && d.level - lowest >= MIN_RISE) riseTs = nowSec
      }
    }
    if (riseTs && nowSec - riseTs > RISE_WINDOW) riseTs = 0
    d.chargingEstimated = d.charging === null && !d.offline && riseTs > 0
    if (d.charging === null) d.charging = d.chargingEstimated
    next[d.key] = { level: level, samples: samples, riseTs: riseTs }
    out.push(d)
  }
  return { devices: out, trends: next }
}

// The `names` setting renames gadgets: { "Reported name": "Your name" }.
// Every gadget keeps the name it reported as `reportedName`, so a rename can
// be changed or undone later.
function applyNames(devices, names) {
  var map = names && typeof names === "object" ? names : {}
  return devices.map(function (d) {
    var name = map[d.name]
    var out = Object.assign({}, d, { reportedName: d.name })
    if (typeof name === "string" && name !== "") out.name = name
    return out
  })
}

function lowestGadget(devices) {
  for (var i = 0; i < (devices || []).length; i++) if (!devices[i].offline) return devices[i]
  return devices && devices.length ? devices[0] : null
}

function gadgetLine(d) {
  if (!d) return ""
  if (d.offline) return d.name + ": offline"
  return d.name + ": " + d.level + "%" + (d.charging ? " (charging)" : "")
}

// ================================================================== the bar

// The bar icon: the battery on a laptop; on a desktop, the lowest gadget's
// kind when one reports a battery, otherwise the power symbol.
var POWER_ICON = "󰐥"

function barIcon(hasBattery, batteryGlyph, lowest) {
  if (hasBattery) return batteryGlyph
  return lowest ? kindIcon(lowest.kind) : POWER_ICON
}

// The text beside the bar icon: the percentage, the watts, both, or nothing.
// Watts only while current flows (none when full or holding).
// Text beside the bar icon. `mode` picks the value (draw, battery in/out,
// today's energy or cost); `showPercent` adds the battery percentage in
// front. Old values that included the percentage (percent, both,
// percent-draw) still work. `energy` is { draw, todayKwh, todayCost }.
var BAR_LABELS = ["none", "draw", "watts", "today", "cost", "percent", "both", "percent-draw"]
var BAR_CYCLE = ["draw", "today", "cost", "watts", "none"]

function barLabel(mode, percent, watts, flowing, energy, showPercent) {
  var e = energy || {}
  var parts = []
  var withPercent = showPercent === true || mode === "percent" || mode === "both" || mode === "percent-draw"
  if (withPercent && percent >= 0) parts.push(Math.round(percent) + "%")
  if ((mode === "watts" || mode === "both") && flowing) {
    var w = formatWatts(watts)
    if (w) parts.push(w)
  }
  if ((mode === "draw" || mode === "percent-draw") && typeof e.draw === "number" && e.draw >= 0) {
    var d = formatWatts(e.draw)
    if (d) parts.push(d)
  }
  if ((mode === "today" || (mode === "cost" && !e.todayCost)) && typeof e.todayKwh === "number") parts.push(formatKwh(e.todayKwh))
  if (mode === "cost" && e.todayCost) parts.push(e.todayCost)
  return parts.join(" ")
}

// Right-click on the bar icon steps through the values.
function nextBarLabel(mode) {
  var base = { percent: "none", both: "watts", "percent-draw": "draw" }[mode] || mode
  var i = BAR_CYCLE.indexOf(base)
  return BAR_CYCLE[(i + 1) % BAR_CYCLE.length]
}

function usesEnergy(mode) {
  return mode === "draw" || mode === "percent-draw" || mode === "today" || mode === "cost"
}

// GPUs in the bar: a card icon for a discrete GPU (while it is awake), a chip
// for integrated graphics, each with its usage, its draw or both.
var GPU_ICON = "󰢮"
var IGPU_ICON = "󰘚"
var BAR_GPU = ["discrete", "integrated", "both", "off"]
var BAR_GPU_VALUE = ["usage", "watts", "both"]

function barGpuSetting(value) {
  if (value === true) return "discrete"
  if (value === false) return "off"
  return BAR_GPU.indexOf(value) >= 0 ? value : "discrete"
}

function gpuBadges(gpus, which, value) {
  if (which === "off") return ""
  var out = []
  for (var i = 0; i < (gpus || []).length; i++) {
    var g = gpus[i]
    if (g.integrated && which !== "integrated" && which !== "both") continue
    if (!g.integrated && which === "integrated") continue
    if (!g.integrated && g.state !== "awake") continue
    var parts = [g.integrated ? IGPU_ICON : GPU_ICON]
    if ((value === "usage" || value === "both") && typeof g.busy === "number") parts.push(g.busy + "%")
    if ((value === "watts" || value === "both" || (value === "usage" && typeof g.busy !== "number")) && typeof g.watts === "number" && g.watts >= 0)
      parts.push(formatWatts(g.watts) || "0 W")
    if (parts.length > 1 || !g.integrated) out.push(parts.join(" "))
  }
  return out.join("  ")
}

// A GPU's short name for legends: "NVIDIA", "Intel iGPU".
function gpuShortName(g) {
  return g ? g.vendor + (g.integrated ? " iGPU" : "") : ""
}

// One GPU in the tooltip: "NVIDIA GPU awake · 12 W · 3% busy · 53 °C".
function gpuLine(g) {
  if (!g) return ""
  var name = g.vendor + (g.integrated ? " graphics" : " GPU")
  if (g.state === "asleep") return name + " asleep"
  var parts = [g.state === "in-package" ? name : name + " awake"]
  if (typeof g.watts === "number") parts.push((formatWatts(g.watts) || "0 W") + (g.integrated ? " (in the CPU figure)" : ""))
  if (typeof g.busy === "number") parts.push(g.busy + "% busy")
  if (typeof g.temp === "number") parts.push(Math.round(g.temp) + " °C")
  return parts.length > 1 ? parts.join(" · ") : (g.integrated ? "" : parts[0])
}

function formatKwh(kwh) {
  var k = Number(kwh)
  if (!isFinite(k) || k < 0) return ""
  if (k >= 100) return k.toFixed(0) + " kWh"
  if (k >= 10) return k.toFixed(1) + " kWh"
  if (k >= 1) return k.toFixed(2) + " kWh"
  return k.toFixed(3) + " kWh"
}

// ============================================================ 4. battery care

// How this machine can hold its charge below 100%, best first:
//   sysfs   kernel threshold files this user may write: exact limit, and a
//           start threshold too (sailing) when there is one
//   apple   the Apple SMC limit (T2 Macs), exact
//   upower  UPower's own limit (recent UPower and a supporting driver): on or
//           off, the levels are the firmware's or the system's
//   acer    Acer health mode (acer-wmi-battery driver): on holds at 80%
//   locked  threshold files exist but are root-only (see docs/charge-limit.md)
//   none    no hardware limit; the unplug reminder stands in for one
function chargeLimitBackend(caps) {
  var t = caps && caps.threshold ? caps.threshold : {}
  var sysfs = t.sysfs || {}
  var up = t.upower || {}
  if (sysfs.end && sysfs.end.writable)
    return { kind: "sysfs", exact: true, sailing: !!(sysfs.start && sysfs.start.writable),
             end: sysfs.end.value, start: sysfs.start ? sysfs.start.value : -1 }
  if (sysfs.apple && sysfs.apple.writable)
    return { kind: "apple", exact: true, sailing: false, end: sysfs.apple.value, start: -1 }
  if (up.supported)
    return { kind: "upower", exact: false, sailing: false, enabled: !!up.enabled,
             end: Number(up.end) || 0, start: Number(up.start) || 0 }
  if (sysfs.acer && sysfs.acer.writable)
    return { kind: "acer", exact: false, sailing: false, enabled: sysfs.acer.value === 1, end: 80, start: -1 }
  if (sysfs.end || sysfs.apple || sysfs.acer)
    return { kind: "locked", exact: false, sailing: false, end: (sysfs.end || sysfs.apple || sysfs.acer).value, start: -1 }
  return { kind: "none", exact: false, sailing: false, end: -1, start: -1 }
}

var LIMIT_MIN = 50
var LIMIT_MAX = 100
var SAIL_GAP_MIN = 2

function clampLimit(value) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return 80
  return Math.max(LIMIT_MIN, Math.min(LIMIT_MAX, n))
}

// Heat protection: stop charging once the battery is hot, resume once it has
// cooled a few degrees (hysteresis, so it does not flap).
function heatHold(temp, wasHolding, limit, resume) {
  if (!(temp > 0)) return false
  if (wasHolding) return temp > resume
  return temp >= limit
}

function topUpActive(until, nowMs) {
  return Number(until) > nowMs
}

// What the hardware limit should be right now, from the care settings:
//   { end, start, reason }   start -1 leaves the start threshold alone
// Reasons, strongest first: topup (one full charge, then back), heat (hold at
// the current level while hot), calibrate, limit, off.
function desiredLimit(o) {
  var opt = o || {}
  var backend = opt.backend || { kind: "none" }
  if (["sysfs", "apple", "upower", "acer"].indexOf(backend.kind) < 0) return null
  if (opt.heatHolding && backend.exact) {
    var hold = Math.max(LIMIT_MIN, Math.min(LIMIT_MAX, Math.floor(Number(opt.level) || LIMIT_MIN)))
    return { end: hold, start: backend.sailing ? Math.max(0, hold - SAIL_GAP_MIN) : -1, reason: "heat" }
  }
  // UPower's and Acer's levels are fixed: switching the limit on is the nearest to a hold.
  if (opt.heatHolding) return { end: 0, start: -1, reason: "heat" }
  if (opt.topUp || opt.calibrating) return { end: 100, start: backend.sailing ? 0 : -1, reason: opt.topUp ? "topup" : "calibrate" }
  if (!opt.enabled) return { end: 100, start: backend.sailing ? 0 : -1, reason: "off" }
  var end = clampLimit(opt.limit)
  var start = -1
  if (backend.sailing) {
    var sail = opt.sailing ? Math.round(Number(opt.sailStart)) : end - SAIL_GAP_MIN
    if (!isFinite(sail)) sail = end - 5
    start = Math.max(0, Math.min(end - SAIL_GAP_MIN, sail))
  }
  return { end: end, start: start, reason: "limit" }
}

// For UPower, whose levels are fixed: the limit is on, or off.
function upowerWanted(want) {
  if (!want) return null
  return want.reason === "limit" || want.reason === "heat"
}

// Whether the kernel already holds what is wanted (skip a pointless write).
function limitMatches(want, current) {
  if (!want || !current) return false
  if (want.end !== current.end) return false
  return want.start < 0 || current.start < 0 || want.start === current.start
}

// Without a hardware limit: a reminder to unplug once the charge reaches the
// chosen level, once per charge (again after unplugging or dropping well below).
function unplugReminder(level, charging, limit, notified) {
  var at = clampLimit(limit)
  if (level < 0 || at >= 100) return { notify: false, notified: false }
  if (!charging) return { notify: false, notified: false }
  if (level >= at) return { notify: !notified, notified: true }
  return { notify: false, notified: !!notified && level >= at - 5 }
}

// Low-battery profile: on battery at or under `threshold`, switch to the
// power saver and remember what was active; put it back on AC or once the
// level is a few points above. Returns { apply, active, previous } where
// apply is a profile to set now, or "".
function lowBatteryProfile(level, discharging, threshold, state, active, profiles) {
  var s = state || { active: false, previous: "" }
  var list = profiles || []
  var saver = list.indexOf("power-saver") >= 0 ? "power-saver" : ""
  if (!saver || threshold <= 0 || level < 0) return { apply: "", active: false, previous: "" }
  if (!s.active) {
    if (discharging && level <= threshold && active !== saver)
      return { apply: saver, active: true, previous: active || "" }
    return { apply: "", active: false, previous: "" }
  }
  if (!discharging || level > threshold + REARM_MARGIN) {
    var back = s.previous && list.indexOf(s.previous) >= 0 ? s.previous : ""
    // On AC the AC profile Omarchy remembers is applied anyway.
    return { apply: discharging ? back : "", active: false, previous: "" }
  }
  return { apply: "", active: true, previous: s.previous }
}

// Keyboard backlight per power source, as a percentage of the LED's range;
// -1 for "leave it". Returns the raw brightness to set.
function keyboardLevel(prefs, onBattery, max) {
  var p = prefs || {}
  var pct = Number(onBattery ? p.battery : p.ac)
  if (!(max > 0) || !isFinite(pct) || pct < 0) return -1
  return Math.round(Math.max(0, Math.min(100, pct)) / 100 * max)
}

// Calibration (from AlDente): charge to 100%, rest there an hour, run down to
// 15% on battery, then charge back to the limit. One step of the state
// machine: { phase, startedAt } in, the next state and what to tell the user.
var CALIBRATION_HOLD = 60 * 60 * 1000
var CALIBRATION_LOW = 15

function calibrationStep(state, level, onBattery, nowMs) {
  var s = state || { phase: "idle", startedAt: 0 }
  function next(phase, message) { return { phase: phase, startedAt: phase === s.phase ? s.startedAt : nowMs, message: message || "" } }
  switch (s.phase) {
  case "charge":
    if (level >= 100 && !onBattery) return next("hold", "Fully charged. Resting at 100% for an hour.")
    return next("charge", onBattery ? "Plug in to charge to 100%." : "")
  case "hold":
    if (onBattery) return next("charge", "Plug back in: the battery has to rest at 100%.")
    if (nowMs - s.startedAt >= CALIBRATION_HOLD) return next("drain", "Unplug now and use the laptop until it reaches " + CALIBRATION_LOW + "%.")
    return next("hold")
  case "drain":
    if (level <= CALIBRATION_LOW) return next("recharge", "Down to " + CALIBRATION_LOW + "%. Plug in to finish.")
    return next("drain", onBattery ? "" : "Unplug to keep calibrating.")
  case "recharge":
    if (!onBattery) return { phase: "idle", startedAt: 0, message: "Calibration done. Your charge limit is back on." }
    return next("recharge")
  default:
    return { phase: "idle", startedAt: 0, message: "" }
  }
}

var CALIBRATION_LABELS = {
  charge: "Charging to 100%",
  hold: "Resting at 100%",
  drain: "Running down to 15%",
  recharge: "Plug in to finish"
}

// ========================================================== 5. insights

function pad2(n) { return n < 10 ? "0" + n : String(n) }

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// Daily totals: minutes on battery and on AC, % drained, Wh used on battery.
// `days` is { "YYYY-MM-DD": { bat, ac, drained, wh } }; DAYS_KEPT kept.
var DAYS_KEPT = 14

function accumulateDay(days, nowMs, minutes, onBattery, drainedPct, wh) {
  var next = {}
  var key = dayKey(nowMs)
  var keys = Object.keys(days || {}).sort()
  for (var i = 0; i < keys.length; i++) next[keys[i]] = days[keys[i]]
  var d = next[key] ? { bat: next[key].bat || 0, ac: next[key].ac || 0, drained: next[key].drained || 0, wh: next[key].wh || 0 }
                    : { bat: 0, ac: 0, drained: 0, wh: 0 }
  var m = Math.max(0, Number(minutes) || 0)
  if (onBattery) d.bat += m
  else d.ac += m
  d.drained += Math.max(0, Number(drainedPct) || 0)
  d.wh = Math.round((d.wh + Math.max(0, Number(wh) || 0)) * 100) / 100
  next[key] = d
  var all = Object.keys(next).sort()
  while (all.length > DAYS_KEPT) delete next[all.shift()]
  return next
}

// The last `count` days, oldest first, with zeros for days without data.
function recentDays(days, nowMs, count) {
  var out = []
  for (var i = count - 1; i >= 0; i--) {
    var key = dayKey(nowMs - i * 86400000)
    var d = (days || {})[key] || { bat: 0, ac: 0, drained: 0, wh: 0 }
    var label = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(nowMs - i * 86400000).getDay()]
    out.push({ key: key, label: label, bat: d.bat, ac: d.ac, drained: d.drained, wh: d.wh })
  }
  return out
}

// Discharge sessions: from unplugging to plugging in. A session shorter than
// a few minutes is dropped. SESSIONS_KEPT kept, newest first.
var SESSIONS_KEPT = 20
var SESSION_MIN = 3 * 60 * 1000

function sessionUpdate(current, sessions, onBattery, nowMs, level) {
  var list = sessions || []
  if (onBattery) {
    if (current) return { current: current, sessions: list }
    return { current: { start: nowMs, from: level }, sessions: list }
  }
  if (!current) return { current: null, sessions: list }
  if (nowMs - current.start < SESSION_MIN) return { current: null, sessions: list }
  var done = { start: current.start, end: nowMs, from: current.from, to: level }
  return { current: null, sessions: [done].concat(list).slice(0, SESSIONS_KEPT) }
}

function sessionLine(s) {
  var used = s.from - s.to
  var hours = (s.end - s.start) / 3600000
  var rate = hours > 0 && used > 0 ? Math.round(used / hours) : 0
  return formatDuration((s.end - s.start) / 1000) + " · " + s.from + "% → " + s.to + "%" + (rate ? " · " + rate + "%/h" : "")
}

// Health once a day: [dayKey, health %, cycles]; a year kept.
function recordHealth(log, nowMs, health, cycles) {
  if (!(health >= 0)) return log || []
  var key = dayKey(nowMs)
  var list = (log || []).filter(function (e) { return Array.isArray(e) && e[0] !== key })
  list.push([key, health, cycles || 0])
  list.sort(function (a, b) { return a[0] < b[0] ? -1 : 1 })
  return list.slice(-365)
}

// Health lost per 100 cycles, from the oldest and newest entries: -1 when
// there is too little to say.
function wearRate(log) {
  var list = log || []
  if (list.length < 2) return -1
  var a = list[0], b = list[list.length - 1]
  var cycles = b[2] - a[2]
  if (cycles < 10) return -1
  return Math.round((a[1] - b[1]) / cycles * 1000) / 10
}

// Plain advice from the readings, most useful first.
function careTips(o) {
  var t = []
  var opt = o || {}
  if (opt.health >= 0 && opt.health < 80)
    t.push("The battery holds " + opt.health + "% of its design capacity; a charge limit slows further wear.")
  if (opt.backend === "none" && opt.onAcShare > 0.7)
    t.push("This laptop is on AC most of the time; unplugging around 80% helps the battery last.")
  if (opt.backend === "locked")
    t.push("The charge limit files are root-only; docs/charge-limit.md shows a one-time rule to allow them.")
  if (opt.temperature >= 40)
    t.push("The battery is warm (" + opt.temperature + " °C). Heat ages it faster than anything else.")
  if (opt.limitEnabled && opt.limit <= 85 && opt.backend !== "none")
    t.push("Charge limit at " + opt.limit + "%: good for a laptop that stays plugged in.")
  return t
}

// ============================================================ 6. system

// CPU use between two /proc/stat "cpu" rows (user nice system idle iowait
// irq softirq steal ...), as a percentage.
function cpuUsage(prev, next) {
  if (!prev || !next || prev.length < 4 || next.length < 4) return -1
  function sum(a) { var s = 0; for (var i = 0; i < Math.min(a.length, 8); i++) s += a[i]; return s }
  var idle = (next[3] + (next[4] || 0)) - (prev[3] + (prev[4] || 0))
  var total = sum(next) - sum(prev)
  if (total <= 0) return -1
  return Math.max(0, Math.min(100, Math.round((1 - idle / total) * 100)))
}

function memoryUsage(mem) {
  var m = mem || {}
  var total = Number(m.MemTotal) || 0
  var avail = Number(m.MemAvailable) || 0
  if (total <= 0) return { used: 0, total: 0, pct: -1 }
  return { used: total - avail, total: total, pct: Math.round((total - avail) / total * 100) }
}

// Package power from two RAPL energy readings (µJ) and their times (ms); the
// counter wraps, so a drop is skipped.
function raplWatts(prevEnergy, prevMs, energy, nowMs) {
  if (prevEnergy === null || prevEnergy === undefined || energy === null || energy === undefined) return -1
  var dt = (nowMs - prevMs) / 1000
  var de = energy - prevEnergy
  if (dt <= 0 || de < 0) return -1
  return Math.round(de / 1e6 / dt * 10) / 10
}

function formatBytes(bytes) {
  var b = Number(bytes) || 0
  if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
  if (b >= 1048576) return Math.round(b / 1048576) + " MB"
  return Math.round(b / 1024) + " KB"
}

// A rolling series for the small graphs: the newest value appended, at most
// `max` kept.
function pushSeries(series, value, max) {
  var list = (series || []).slice()
  list.push(value)
  while (list.length > (max || 60)) list.shift()
  return list
}

// Points for a series between `lo` and `hi` in a w x h box, right-aligned;
// a missing value (-1 or null) leaves a gap at that spot.
function rangePoints(series, w, h, slots, lo, hi) {
  var list = series || []
  var n = Math.max(2, slots || list.length)
  var span = Math.max(1, hi - lo)
  var pts = []
  var offset = n - list.length
  for (var i = 0; i < list.length; i++) {
    if (typeof list[i] !== "number" || list[i] < 0) continue
    var v = Math.max(lo, Math.min(hi, list[i]))
    pts.push([(offset + i) / (n - 1) * w, h - (v - lo) / span * h])
  }
  return pts
}

// One rolling series per key (a GPU's id): the newest value appended to each
// key in `values`, keys no longer reported dropped once they are all gaps.
function pushKeyed(map, values, max) {
  var out = {}
  var keys = Object.keys(map || {}).concat(Object.keys(values || {}))
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    if (out[k]) continue
    var v = values && typeof values[k] === "number" ? values[k] : -1
    var list = pushSeries((map || {})[k], v, max)
    var any = false
    for (var j = 0; j < list.length; j++) if (list[j] >= 0) any = true
    if (any) out[k] = list
  }
  return out
}

// Points for a 0-100 (or 0-`top`) series in a w x h box, right-aligned.
function seriesPoints(series, w, h, slots, top) {
  var list = series || []
  var n = Math.max(2, slots || list.length)
  var hi = top || 100
  var pts = []
  var offset = n - list.length
  for (var i = 0; i < list.length; i++) {
    if (!(list[i] >= 0)) continue
    pts.push([(offset + i) / (n - 1) * w, h - Math.min(hi, list[i]) / hi * h])
  }
  return pts
}

// ============================================================ 7. the report

// A Markdown health report, from plain values. Nothing personal: no serial
// number, no host name.
function reportMarkdown(r) {
  var o = r || {}
  var lines = ["# Battery report", "", "Generated " + (o.generated || "") + " by OmniSystem Center.", ""]
  if (o.battery) {
    var b = o.battery
    lines.push("## Battery", "")
    lines.push("| | |", "|---|---|")
    if (b.maker || b.model) lines.push("| Model | " + [b.maker, b.model].filter(Boolean).join(" ") + " |")
    if (b.technology) lines.push("| Chemistry | " + b.technology + " |")
    if (b.health >= 0) lines.push("| Health | " + b.health + "% (" + healthLabel(b.health) + ") |")
    if (b.full) lines.push("| Full charge | " + b.full.toFixed(1) + " " + b.unit + " of " + b.design.toFixed(1) + " " + b.unit + " design |")
    if (b.cycles) lines.push("| Charge cycles | " + b.cycles + " |")
    if (b.temperature > 0) lines.push("| Temperature | " + b.temperature + " °C |")
    if (b.voltage) lines.push("| Voltage | " + b.voltage + " V |")
    if (o.level >= 0) lines.push("| Charge now | " + o.level + "% |")
    if (o.limit) lines.push("| Charge limit | " + o.limit + " |")
    if (o.wearRate >= 0) lines.push("| Wear | " + o.wearRate + "% per 100 cycles |")
    lines.push("")
  } else {
    lines.push("No laptop battery: this is a desktop.", "")
  }
  if (o.days && o.days.length) {
    lines.push("## Last " + o.days.length + " days", "", "| Day | On battery | On AC | Drained | Used |", "|---|---|---|---|---|")
    for (var i = 0; i < o.days.length; i++) {
      var d = o.days[i]
      lines.push("| " + d.key + " | " + (formatDuration(d.bat * 60) || "–") + " | " + (formatDuration(d.ac * 60) || "–") +
                 " | " + (d.drained ? Math.round(d.drained) + "%" : "–") + " | " + (d.wh ? d.wh.toFixed(1) + " Wh" : "–") + " |")
    }
    lines.push("")
  }
  if (o.sessions && o.sessions.length) {
    lines.push("## Recent sessions on battery", "")
    for (var k = 0; k < o.sessions.length; k++) {
      var s = o.sessions[k]
      lines.push("- " + new Date(s.start).toISOString().slice(0, 16).replace("T", " ") + ": " + sessionLine(s))
    }
    lines.push("")
  }
  if (o.healthLog && o.healthLog.length > 1) {
    lines.push("## Health over time", "", "| Day | Health | Cycles |", "|---|---|---|")
    var step = Math.max(1, Math.floor(o.healthLog.length / 12))
    for (var h = 0; h < o.healthLog.length; h += step) {
      var e = o.healthLog[h]
      lines.push("| " + e[0] + " | " + e[1] + "% | " + e[2] + " |")
    }
    lines.push("")
  }
  if (o.gadgets && o.gadgets.length) {
    lines.push("## Gadgets", "")
    for (var g = 0; g < o.gadgets.length; g++) lines.push("- " + gadgetLine(o.gadgets[g]))
    lines.push("")
  }
  if (o.tips && o.tips.length) {
    lines.push("## Tips", "")
    for (var t = 0; t < o.tips.length; t++) lines.push("- " + o.tips[t])
    lines.push("")
  }
  return lines.join("\n")
}


// ============================================================ energy meter

// A round ceiling for the graph's scale: 10, 20, 25, 50, 100, ...
function niceCeil(value) {
  var v = Math.max(1, Number(value) || 0)
  var power = Math.pow(10, Math.floor(Math.log(v) / Math.LN10))
  var steps = [1, 2, 2.5, 5, 10]
  for (var i = 0; i < steps.length; i++) if (v <= steps[i] * power) return steps[i] * power
  return 10 * power
}

function energyPeak(points) {
  var m = 0
  for (var i = 0; i < (points || []).length; i++) if (points[i][1] !== null && points[i][1] > m) m = points[i][1]
  return niceCeil(m * 1.1)
}

// [time, watts|null] points to graph segments, split where nothing was tracked.
function energySegments(points, start, end, w, h, peak) {
  var span = Math.max(1, end - start)
  var segments = []
  var current = []
  for (var i = 0; i < (points || []).length; i++) {
    var p = points[i]
    if (p[1] === null || p[1] === undefined) {
      if (current.length) segments.push(current)
      current = []
      continue
    }
    var x = Math.max(0, Math.min(w, (p[0] - start) / span * w))
    var y = h - Math.max(0, Math.min(1, p[1] / peak)) * h
    current.push([x, y])
  }
  if (current.length) segments.push(current)
  return segments
}

// The point nearest a pointer x, or -1.
function nearestPoint(points, start, end, w, x) {
  var best = -1, bestDx = Infinity
  var span = Math.max(1, end - start)
  for (var i = 0; i < (points || []).length; i++) {
    var dx = Math.abs((points[i][0] - start) / span * w - x)
    if (dx < bestDx) { bestDx = dx; best = i }
  }
  return best
}

var DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTH_NAMES = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function pad2(n) { return (n < 10 ? "0" : "") + n }

// A time on the graph: the clock for a day, day and clock for a week or a
// month, the date beyond that.
function energyTimeLabel(ms, days) {
  var d = new Date(ms)
  var clock = pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  if (days <= 1) return clock
  if (days <= 31) return DAY_NAMES[d.getDay()] + " " + d.getDate() + " " + MONTH_NAMES[d.getMonth()] + " " + clock
  return d.getDate() + " " + MONTH_NAMES[d.getMonth()] + " " + d.getFullYear()
}

function percentText(share, word) {
  return typeof share === "number" ? Math.round(share * 100) + "% " + word : ""
}

// Why the meter has no number right now, in words.
function untrackedText(reason, onBattery) {
  switch (reason) {
  case "cpu-counter-unreadable": return "On AC this machine's CPU energy counter is readable by root only, so AC time is not recorded yet."
  case "cpu-counter-reset": return "The CPU counter jumped; that interval was left out."
  case "slept": return "The machine slept; that time is not counted."
  case "switched": return onBattery ? "Just unplugged: the next reading comes in 10 s." : "Just plugged in: the next reading comes in 10 s."
  case "battery-unreadable": return "The battery does not report its power right now."
  }
  return ""
}

// Widths of the CPU / GPU / rest bar, as fractions summing to 1.
function drawShares(now) {
  if (!now || typeof now.watts !== "number" || now.watts <= 0 || typeof now.cpu_w !== "number") return null
  var cpu = Math.max(0, now.cpu_w), gpu = Math.max(0, now.gpu_w || 0), rest = Math.max(0, now.rest_w || 0)
  var total = cpu + gpu + rest
  if (total <= 0) return null
  return { cpu: cpu / total, gpu: gpu / total, rest: rest / total }
}

// Baseline from a wall meter at idle: metered × efficiency − measured parts.
function calibratedBaseline(meteredW, efficiency, cpuDcW, gpuDcW) {
  var m = Number(meteredW), e = Number(efficiency)
  if (!(m > 0) || !(e > 0) || typeof cpuDcW !== "number") return -1
  var b = m * e - cpuDcW - (gpuDcW || 0)
  return b >= 0 && b <= 500 ? Math.round(b * 10) / 10 : -1
}


// ============================================================ device info

function formatUptime(seconds) {
  var s = Math.floor(Number(seconds) || 0)
  if (s <= 0) return ""
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  return Math.max(1, m) + "m"
}

// Whole gigabytes for disk sizes: "328 GB", "1.8 TB".
function formatGB(bytes) {
  var b = Number(bytes) || 0
  if (b >= 1e12 * 0.9995) return (b / 1099511627776).toFixed(1) + " TB"
  return Math.round(b / 1073741824) + " GB"
}

function formatMHz(mhz) {
  var m = Number(mhz)
  if (!(m > 0)) return ""
  return m >= 1000 ? (m / 1000).toFixed(2) + " GHz" : Math.round(m) + " MHz"
}

// "L1 48K + 32K · L2 1.25M · L3 12M"
function cacheText(caches) {
  if (!caches) return ""
  function size(t) {
    var m = /^(\d+)K$/.exec(String(t))
    if (!m) return String(t)
    var k = Number(m[1])
    return k >= 1024 ? (Math.round(k / 1024 * 100) / 100) + "M" : k + "K"
  }
  var parts = []
  if (caches.L1d || caches.L1i) parts.push("L1 " + [caches.L1d, caches.L1i].filter(function(x) { return x }).map(size).join(" + "))
  if (caches.L1) parts.push("L1 " + size(caches.L1))
  if (caches.L2) parts.push("L2 " + size(caches.L2))
  if (caches.L3) parts.push("L3 " + size(caches.L3))
  return parts.join(" · ")
}

function osText(o) {
  if (!o) return ""
  if (!o.omarchy) return o.name || ""
  return o.name && o.name !== "Omarchy" ? o.name + " · Omarchy " + o.omarchy : "Omarchy " + o.omarchy
}

function machineName(m) {
  if (!m) return ""
  return [m.vendor, m.product].filter(function(x) { return x }).join(" ")
}

function diskText(storage) {
  if (!storage || !storage.disk) return ""
  var size = storage.size ? formatBytes(storage.size).replace(".0 GB", " GB") : ""
  return [storage.model || storage.disk, size].filter(function(x) { return x }).join(" · ")
}

function swapText(swaps) {
  var parts = []
  for (var i = 0; i < (swaps || []).length; i++) {
    var w = swaps[i]
    parts.push((w.kind === "zram" ? "zram" : "swap") + " " + formatBytes(w.used) + " / " + formatBytes(w.size))
  }
  return parts.join(" · ")
}

// A GPU's memory in a few words: "6 GB VRAM · 344 MB used", "Shares system
// memory · up to 1.45 GHz", "512 MB reserved + shared".
function gpuMemoryText(mem) {
  if (!mem) return ""
  function gb(b) { return b >= 1073741824 ? (Math.round(b / 1073741824 * 10) / 10) + " GB" : Math.round(b / 1048576) + " MB" }
  var parts = []
  if (mem.total > 0 && mem.shared) parts.push(gb(mem.total) + " reserved + shared")
  else if (mem.total > 0) parts.push(gb(mem.total) + " VRAM")
  else if (mem.shared) parts.push("Shares system memory")
  if (typeof mem.used === "number" && mem.used >= 0 && mem.total > 0) parts.push(gb(mem.used) + " used")
  if (mem.maxMHz) parts.push("up to " + formatMHz(mem.maxMHz))
  if (mem.driver) parts.push("driver " + mem.driver)
  return parts.join(" · ")
}

// Everything on the System tab as plain text, for "Copy all". No serial
// numbers are ever read, so none can end up here.
function deviceSummary(dev, live) {
  if (!dev) return ""
  var l = live || {}
  var lines = []
  function add(label, value) { if (value) lines.push(label + ": " + value) }
  var m = dev.machine || {}
  add("Machine", machineName(m) + (m.family ? " (" + m.family + ")" : ""))
  add("Type", m.chassis)
  add("Board", m.board)
  add("Firmware", [m.bios, m.biosDate].filter(function(x) { return x }).join(", ") + (m.ec ? " · EC " + m.ec : ""))
  var o = dev.os || {}
  add("System", osText(o))
  add("Kernel", o.kernel)
  var c = dev.cpu || {}
  add("CPU", c.model)
  add("Cores", c.cores ? c.cores + " cores, " + c.threads + " threads" : "")
  add("Clock", c.minMHz && c.maxMHz ? formatMHz(c.minMHz) + " – " + formatMHz(c.maxMHz) : "")
  add("Cache", cacheText(c.caches))
  add("Scaling", [c.driver, c.governor, c.epp].filter(function(x) { return x }).join(" · "))
  add("Memory", dev.memory && dev.memory.total ? formatBytes(dev.memory.total) : "")
  add("Disk", diskText(dev.storage))
  if (dev.storage && dev.storage.fs) add("Root", dev.storage.fs + (dev.storage.encrypted ? ", encrypted" : ""))
  for (var i = 0; i < (dev.pci || []).length; i++) {
    var mem = gpuMemoryText(dev.pci[i].memory)
    add(dev.pci[i].kind, dev.pci[i].name + (mem ? " (" + mem + ")" : ""))
  }
  for (var j = 0; j < (dev.usb || []).length; j++) add("USB", dev.usb[j].name)
  if (dev.battery) add("Battery", [dev.battery.maker, dev.battery.model, dev.battery.chemistry].filter(function(x) { return x }).join(" "))
  add("Uptime", formatUptime(l.uptime))
  return lines.join("\n")
}


// ================================================================== theme

// The named colours of the current Omarchy theme (colors.toml): accent and
// the terminal palette. Missing names fall back to the shell's accent/urgent.
var THEME_KEYS = ["accent", "foreground", "background", "red", "yellow", "orange", "green", "cyan", "blue", "magenta",
                  "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]

function parseThemeColors(text, accent, urgent) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^\s*([a-z_]+[0-9]*)\s*=\s*"?(#[0-9a-fA-F]{6})"?/.exec(lines[i])
    if (m) out[m[1]] = m[2].toLowerCase()
  }
  // Older themes use color0..color15.
  var numbered = { red: "color1", green: "color2", yellow: "color3", blue: "color4", magenta: "color5", cyan: "color6" }
  for (var k in numbered) if (!out[k] && out[numbered[k]]) out[k] = out[numbered[k]]
  if (!out.accent) out.accent = accent || out.blue || "#cacccc"
  if (!out.red) out.red = urgent || "#a55555"
  return out
}

function hexRgb(hex) {
  var h = String(hex || "").replace("#", "")
  if (h.length === 8) h = h.slice(2)
  if (h.length !== 6) return null
  return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
}

function colorDistance(a, b) {
  var x = hexRgb(a), y = hexRgb(b)
  if (!x || !y) return 0
  return Math.sqrt(Math.pow(x[0] - y[0], 2) + Math.pow(x[1] - y[1], 2) + Math.pow(x[2] - y[2], 2))
}

// `n` colours for graph lines: the accent first, then theme colours that are
// clearly different from those already taken and from the background.
function seriesColors(palette, n, background) {
  var p = palette || {}
  var order = ["accent", "cyan", "green", "magenta", "blue", "yellow", "orange", "bright_cyan", "bright_green",
               "bright_magenta", "bright_blue", "foreground", "red"]
  var out = []
  for (var pass = 0; pass < 2 && out.length < n; pass++) {
    var minDistance = pass === 0 ? 90 : 25
    for (var i = 0; i < order.length && out.length < n; i++) {
      var c = p[order[i]]
      if (!c || out.indexOf(c) >= 0) continue
      if (background && colorDistance(c, background) < 80) continue
      var far = true
      for (var j = 0; j < out.length; j++) if (colorDistance(c, out[j]) < minDistance) far = false
      if (far) out.push(c)
    }
  }
  while (out.length < n) out.push(p.foreground || "#cacccc")
  return out
}

// The power buttons: shutdown red, reboot orange or yellow, hibernate blue,
// suspend cyan, logout magenta, lock the accent. A theme without one of these
// falls back to the next, then to the text colour.
function actionColor(key, palette, fallback) {
  var p = palette || {}
  var wants = {
    shutdown: ["red", "bright_red"],
    reboot: ["orange", "yellow", "bright_yellow"],
    hibernate: ["blue", "bright_blue", "cyan"],
    suspend: ["cyan", "bright_cyan", "blue"],
    logout: ["magenta", "bright_magenta", "yellow"],
    lock: ["accent"]
  }[key] || []
  for (var i = 0; i < wants.length; i++) if (p[wants[i]]) return p[wants[i]]
  return fallback || p.foreground || "#cacccc"
}


// ================================================================== tabs

// Every tab: its icon, its name, and the theme colour it wears while open
// (AuroraPulse's tab strip: the open tab says its name in its colour, the
// others are icons).
var TABS = {
  overview: { icon: "󰁹", label: "Overview", tint: ["accent"] },
  care: { icon: "󰂏", label: "Care", tint: ["green", "bright_green", "accent"] },
  insights: { icon: "󰄨", label: "Insights", tint: ["cyan", "bright_cyan", "accent"] },
  energy: { icon: "󱐋", label: "Energy", tint: ["yellow", "bright_yellow", "accent"] },
  system: { icon: "󰊚", label: "System", tint: ["blue", "bright_blue", "accent"] },
  processes: { icon: "󰍛", label: "Processes", tint: ["magenta", "bright_magenta", "accent"] },
  ports: { icon: "󰒍", label: "Ports", tint: ["orange", "red", "accent"] },
  plugins: { icon: "󰐱", label: "Plugins", tint: ["bright_blue", "blue", "accent"] },
  controls: { icon: "󰔡", label: "Controls", tint: ["bright_cyan", "cyan", "accent"] },
  settings: { icon: "󰒓", label: "Settings", tint: ["accent"] }
}

function tabMeta(value) {
  var t = TABS[value]
  return t ? { value: value, icon: t.icon, label: t.label } : { value: value, icon: "", label: value }
}

// A tab's colour from the theme: the first of its wanted names the theme has
// that stands out from the background, else the accent.
function tabTint(value, palette, background) {
  var p = palette || {}
  var wants = (TABS[value] || { tint: ["accent"] }).tint
  for (var i = 0; i < wants.length; i++) {
    var c = p[wants[i]]
    if (c && (!background || colorDistance(c, background) >= 80)) return c
  }
  return p.accent || "#cacccc"
}


// ============================================================= processes

// The rows the Processes tab shows: filtered by `query` (name, command, user
// or PID) and `mine`, sorted by `sort` (cpu, mem, pid, name, user), and in
// `tree` mode each child under its parent with its depth. Kernel threads are
// hidden unless `kernel` is on.
function processRows(procs, opts) {
  var o = opts || {}
  var q = String(o.query || "").toLowerCase().trim()
  var list = (procs || []).filter(function(p) {
    if (o.mine && !p.mine) return false
    if (!o.kernel && p.kernel) return false
    if (!q) return true
    return String(p.pid) === q || p.name.toLowerCase().indexOf(q) >= 0 || p.cmd.toLowerCase().indexOf(q) >= 0
      || p.user.toLowerCase().indexOf(q) >= 0
  })
  var key = o.sort || "cpu"
  var desc = o.desc !== undefined ? o.desc : (key === "cpu" || key === "mem" || key === "gpu")
  function cmp(a, b) {
    var x, y
    if (key === "name" || key === "user") { x = a[key].toLowerCase(); y = b[key].toLowerCase() }
    else if (key === "mem") { x = a.rss; y = b.rss }
    else if (key === "gpu") { x = a.gpu || 0; y = b.gpu || 0 }
    else { x = a[key]; y = b[key] }
    if (x < y) return desc ? 1 : -1
    if (x > y) return desc ? -1 : 1
    return a.pid - b.pid
  }
  if (!o.tree || q) {
    list.sort(cmp)
    return list.map(function(p) { return Object.assign({ depth: 0 }, p) })
  }
  var byPid = {}, kids = {}
  for (var i = 0; i < list.length; i++) byPid[list[i].pid] = list[i]
  var roots = []
  for (var j = 0; j < list.length; j++) {
    var p = list[j]
    if (byPid[p.ppid] && p.ppid !== p.pid) (kids[p.ppid] = kids[p.ppid] || []).push(p)
    else roots.push(p)
  }
  var out = []
  function walk(node, depth) {
    out.push(Object.assign({ depth: depth, children: (kids[node.pid] || []).length }, node))
    var c = (kids[node.pid] || []).slice().sort(cmp)
    for (var k = 0; k < c.length; k++) walk(c[k], depth + 1)
  }
  roots.sort(cmp)
  for (var r = 0; r < roots.length; r++) walk(roots[r], 0)
  return out
}

var PROC_STATES = { R: "running", S: "sleeping", D: "waiting on disk", Z: "zombie", T: "stopped", t: "traced",
                    I: "idle", X: "dead" }

function procState(code) { return PROC_STATES[code] || code }

function formatCpu(pct) {
  var p = Number(pct) || 0
  return p >= 100 ? Math.round(p) + "%" : p.toFixed(1) + "%"
}

// "3m", "2h 05m", "4d 3h" since a process started.
function sinceText(startedSec, nowMs) {
  var s = Math.max(0, Math.floor(nowMs / 1000 - startedSec))
  if (s < 60) return s + "s"
  if (s < 3600) return Math.floor(s / 60) + "m"
  if (s < 86400) return Math.floor(s / 3600) + "h " + pad2(Math.floor((s % 3600) / 60)) + "m"
  return Math.floor(s / 86400) + "d " + Math.floor((s % 86400) / 3600) + "h"
}


// ================================================================== ports

var PORT_FILTERS = ["dev", "mine", "exposed", "all"]

function portExposed(r) { return r.reach === "network" }

function portMatches(r, filter) {
  if (filter === "dev") return r.dev
  if (filter === "mine") return r.mine
  if (filter === "exposed") return portExposed(r)
  return true
}

function portCounts(listeners) {
  var out = { dev: 0, mine: 0, exposed: 0, all: 0, devExposed: 0 }
  for (var i = 0; i < (listeners || []).length; i++) {
    var r = listeners[i]
    out.all++
    if (r.dev) out.dev++
    if (r.mine) out.mine++
    if (portExposed(r)) out.exposed++
    if (r.dev && portExposed(r)) out.devExposed++
  }
  return out
}

// Listeners for the Ports tab, filtered and grouped: a project's servers
// together (by the checkout they run from), containers by Compose project,
// then your other sockets, then the system's.
function portGroups(listeners, filter, query) {
  var q = String(query || "").toLowerCase().trim()
  var groups = {}, order = []
  for (var i = 0; i < (listeners || []).length; i++) {
    var r = listeners[i]
    if (!portMatches(r, filter || "dev")) continue
    if (q && String(r.port).indexOf(q) !== 0 && (r.name + " " + r.project + " " + r.process + " " + r.cmd).toLowerCase().indexOf(q) < 0) continue
    var key, label, rank
    if (r.owner === "container") { key = "c:" + (r.project || r.name); label = r.project || "Containers"; rank = 1 }
    else if (r.project) { key = "p:" + r.projectPath; label = r.project; rank = 0 }
    else if (r.mine) { key = "mine"; label = "Your other sockets"; rank = 2 }
    else { key = "system"; label = "System"; rank = 3 }
    if (!groups[key]) { groups[key] = { key: key, label: label, path: r.projectPath || "", rank: rank, rows: [] }; order.push(key) }
    groups[key].rows.push(r)
  }
  var out = order.map(function(k) { return groups[k] })
  out.sort(function(a, b) { return a.rank - b.rank || a.label.localeCompare(b.label) })
  return out
}

// Your own dev rules on top of the scanner's guess: ports or ranges
// ("3000-3999, 8787"), programs that are always dev servers, and programs that
// never are. A rule beats the guess either way.
function parsePortRanges(text) {
  var out = []
  var parts = String(text || "").split(/[\s,;]+/)
  for (var i = 0; i < parts.length; i++) {
    var m = /^(\d{1,5})(?:-(\d{1,5}))?$/.exec(parts[i])
    if (!m) continue
    var lo = Number(m[1]), hi = Number(m[2] || m[1])
    if (lo >= 1 && hi <= 65535 && lo <= hi) out.push([lo, hi])
  }
  return out
}

function nameList(text) {
  return String(text || "").split(/[\s,;]+/).map(function(x) { return x.trim().toLowerCase() }).filter(function(x) { return x })
}

function withDevRules(data, rules) {
  if (!data) return data
  var r = rules || {}
  var ranges = parsePortRanges(r.ports)
  var dev = nameList(r.dev), never = nameList(r.notDev)
  var listeners = (data.listeners || []).map(function(row) {
    var name = String(row.process || "").toLowerCase()
    var inRange = false
    for (var i = 0; i < ranges.length; i++) if (row.port >= ranges[i][0] && row.port <= ranges[i][1]) inRange = true
    var verdict = row.dev
    if (name && never.indexOf(name) >= 0) verdict = false
    else if ((name && dev.indexOf(name) >= 0) || (inRange && (row.mine || !row.pid))) verdict = true
    if (verdict === row.dev) return row
    return Object.assign({}, row, { dev: verdict, http: row.proto === "tcp" && (verdict || row.http), ruled: true })
  })
  return Object.assign({}, data, { listeners: listeners })
}

// A program added to (or taken off) one list and off the other.
function toggleDevProgram(rules, program, dev) {
  var name = String(program || "").toLowerCase()
  var on = nameList(rules.dev).filter(function(x) { return x !== name })
  var off = nameList(rules.notDev).filter(function(x) { return x !== name })
  if (dev) on.push(name); else off.push(name)
  return { devPrograms: on.join(", "), notDevPrograms: off.join(", ") }
}

// The bar: a port icon and how many dev servers run (0 too, while the
// switch is on), with a warning mark while one is open to the network.
// `active` (drawn in the bar's urgent colour) while any dev server runs.
var PORTS_ICON = "󰒍"

function portsBadge(listeners, show) {
  if (!show) return { text: "", active: false }
  var c = portCounts(listeners)
  return { text: PORTS_ICON + " " + c.dev + (c.devExposed > 0 ? " 󰀪" : ""), active: c.dev > 0 }
}

function reachLabel(reach) {
  return { local: "this machine", "local-link": "link-local", containers: "containers", vpn: "VPN", network: "network" }[reach] || reach
}

// The address to open or copy: loopback for anything this machine can reach.
function portUrl(r) {
  return "http://localhost:" + r.port
}


// ================================================================ plugins

var PLUGIN_FILTERS = ["all", "enabled", "disabled", "third", "updates"]

function pluginHasUpdate(p, updates) {
  var u = updates && updates.plugins ? updates.plugins[p.id] : null
  return !!(u && u.update)
}

// Installed plugins: filtered, searched, with the plugin's update state.
function installedRows(list, filter, query, updates) {
  var q = String(query || "").toLowerCase().trim()
  return (list || []).filter(function(p) {
    if (filter === "enabled" && !p.enabled) return false
    if (filter === "disabled" && p.enabled) return false
    if (filter === "third" && p.firstParty) return false
    if (filter === "updates" && !pluginHasUpdate(p, updates)) return false
    if (!q) return true
    return (p.name + " " + p.id + " " + p.author + " " + p.description).toLowerCase().indexOf(q) >= 0
  }).map(function(p) { return Object.assign({ update: pluginHasUpdate(p, updates) }, p) })
}

function installedCounts(list, updates) {
  var out = { all: 0, enabled: 0, disabled: 0, third: 0, updates: 0 }
  for (var i = 0; i < (list || []).length; i++) {
    var p = list[i]
    out.all++
    if (p.enabled) out.enabled++; else out.disabled++
    if (!p.firstParty) out.third++
    if (pluginHasUpdate(p, updates)) out.updates++
  }
  return out
}

// How well a catalog entry matches a search: an exact name first, then a
// name that starts with it, a name or id that holds it, then the description.
function pluginRelevance(p, q) {
  var name = String(p.name || "").toLowerCase(), id = String(p.id || "").toLowerCase()
  if (name === q || id === q) return 4
  if (name.indexOf(q) === 0) return 3
  if (name.indexOf(q) >= 0 || id.indexOf(q) >= 0) return 2
  if ((String(p.description || "") + " " + (p.tags || []).join(" ") + " " + p.author).toLowerCase().indexOf(q) >= 0) return 1
  return 0
}

// The marketplace: searched (relevance leads while searching, the chosen sort
// orders the rest), by category, sorted by stars, newest or name.
function catalogRows(catalog, opts) {
  var o = opts || {}
  var q = String(o.query || "").toLowerCase().trim()
  var installed = o.installed || {}
  var rows = []
  for (var i = 0; i < (catalog || []).length; i++) {
    var p = catalog[i]
    if (o.category && o.category !== "All" && p.category !== o.category) continue
    if (o.installable && !p.installAvailable) continue
    var rel = q ? pluginRelevance(p, q) : 0
    if (q && rel === 0) continue
    var st = (o.stats || {})[p.id] || {}
    rows.push(Object.assign({ relevance: rel, installed: !!installed[p.id], hearts: st.hearts || 0,
                              views: st.views || 0, installs: st.installs || 0 }, p))
  }
  var sort = o.sort || "stars"
  rows.sort(function(a, b) {
    if (a.relevance !== b.relevance) return b.relevance - a.relevance
    if (sort === "recent") return String(b.repositoryUpdatedAt || b.addedAt || "").localeCompare(String(a.repositoryUpdatedAt || a.addedAt || ""))
    if (sort === "name") return String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase())
    if (sort === "hearts") return (b.hearts - a.hearts) || ((b.stars || 0) - (a.stars || 0))
    if (sort === "installs") return (b.installs - a.installs) || ((b.stars || 0) - (a.stars || 0))
    return (b.stars || 0) - (a.stars || 0)
  })
  return rows
}

var CATALOG_CATEGORIES = ["All", "Widgets", "Productivity", "System", "Hardware", "Desktop", "Appearance", "Developer Tools", "Other"]

// The repository moved on since the marketplace last checked it: what
// `omarchy plugin add` installs is newer than what was reviewed.
function movedSinceReview(p) {
  var reviewed = p.upstreamValidatedCommit || p.listingValidatedCommit || ""
  var now = p.upstreamObservedCommit || ""
  return !!(reviewed && now && reviewed !== now)
}

function shortSha(sha) { return String(sha || "").slice(0, 7) }

// The commit the marketplace reviewed, full length, or "" when it has none.
function reviewedCommit(p) {
  var sha = String((p && (p.upstreamValidatedCommit || p.listingValidatedCommit)) || "")
  return /^[0-9a-f]{40}$/.test(sha) ? sha : ""
}

function formatStars(n) {
  var v = Number(n) || 0
  return v >= 1000 ? (v / 1000).toFixed(1).replace(/\.0$/, "") + "k" : String(v)
}


// A theme colour that really is the hue asked for (a theme's "blue" can be
// orange), else a plain one: blue for verified, green for an update.
var HUES = { blue: [190, 250, "#4a9eff"], green: [85, 160, "#4caf50"] }

function hexHsl(hex) {
  var rgb = hexRgb(hex)
  if (!rgb) return null
  var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, h = 0, sat = 0
  if (max !== min) {
    var d = max - min
    sat = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
  }
  return [h, sat, l]
}

function hueTint(palette, name) {
  var want = HUES[name]
  if (!want) return "#cacccc"
  var p = palette || {}
  var keys = ["blue", "bright_blue", "cyan", "bright_cyan", "green", "bright_green", "accent", "magenta"]
  for (var i = 0; i < keys.length; i++) {
    var hsl = hexHsl(p[keys[i]])
    if (hsl && hsl[0] >= want[0] && hsl[0] <= want[1] && hsl[1] >= 0.3 && hsl[2] >= 0.3 && hsl[2] <= 0.8) return p[keys[i]]
  }
  return want[2]
}

function formatCount(n) {
  var v = Number(n) || 0
  return v >= 10000 ? Math.round(v / 1000) + "k" : (v >= 1000 ? (v / 1000).toFixed(1).replace(/\.0$/, "") + "k" : String(v))
}


// ============================================================== settings

// The Settings tab's sections, in order; a key not listed goes to "Other".
var SETTING_GROUPS = [
  { title: "BAR", keys: ["showPercentage", "barLabel", "barGpu", "barGpuValue", "barPorts", "highWattThreshold"] },
  { title: "PANEL AND TABS", keys: ["panelWidth", "startTab", "systemMonitor", "energyMeter", "processesTab", "portsTab", "pluginsTab"] },
  { title: "BATTERY AND WARNINGS", keys: ["lowLevel", "criticalLevel", "criticalAction", "lowBatteryProfile", "autoProfiles", "notifications"] },
  { title: "GADGETS", keys: ["gadgetLowLevel", "gadgetFullAlert", "externalPath", "names"] },
  { title: "PORTS", keys: ["portWatch", "devPorts", "devPrograms", "notDevPrograms"] }
]

function settingSections(schema) {
  var byKey = {}, used = {}
  for (var i = 0; i < (schema || []).length; i++) byKey[schema[i].key] = schema[i]
  var out = []
  for (var g = 0; g < SETTING_GROUPS.length; g++) {
    var entries = []
    for (var k = 0; k < SETTING_GROUPS[g].keys.length; k++) {
      var e = byKey[SETTING_GROUPS[g].keys[k]]
      if (e) { entries.push(e); used[e.key] = true }
    }
    if (entries.length) out.push({ title: SETTING_GROUPS[g].title, schema: entries })
  }
  var rest = (schema || []).filter(function(e) { return !used[e.key] })
  if (rest.length) out.push({ title: "OTHER", schema: rest })
  return out
}


// ============================================================ bar layout

// The bar as laid out, from the installed plugins' bar positions: each
// section in order, then the enabled bar widgets that are in no section.
function barLayout(installed) {
  var out = { left: [], center: [], right: [], unplaced: [] }
  for (var i = 0; i < (installed || []).length; i++) {
    var p = installed[i]
    var isWidget = (p.kinds || []).indexOf("bar-widget") >= 0
    if (p.bar && out[p.bar.section]) out[p.bar.section].push(p)
    else if (isWidget && p.enabled) out.unplaced.push(p)
  }
  function byIndex(a, b) { return a.bar.index - b.bar.index }
  out.left.sort(byIndex); out.center.sort(byIndex); out.right.sort(byIndex)
  return out
}


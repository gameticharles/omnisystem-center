import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import "lib/Model.js" as Model
import "components"

// OmniSystem Center's one instance. Omarchy builds a bar, and so a widget,
// per monitor; everything that must exist once lives here: the battery and
// what the hardware can do (bin/omnisystem-center-probe), warnings and the
// critical action, charge care, profiles, keep awake, the sleep timer, lid
// hold, keyboard backlight, history, gadgets, the system monitor, the IPC
// targets and the saved state. The widgets only render this and call it.
//
// Every feature is offered only when this machine supports it, and nothing
// here asks for more rights than the session already has.
Item {
  id: root
  width: 0
  height: 0
  visible: false

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "omnisystem-center"
  readonly property string appName: "OmniSystem Center"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string probeCmd: pluginDir + "/bin/omnisystem-center-probe"
  readonly property string ctlCmd: pluginDir + "/bin/omnisystem-center-ctl"
  readonly property string gadgetsCmd: pluginDir + "/bin/omnisystem-center-gadgets"
  readonly property string energyCmd: pluginDir + "/bin/omnisystem-center-energy"
  readonly property string procsCmd: pluginDir + "/bin/omnisystem-center-procs"
  readonly property string portsCmd: pluginDir + "/bin/omnisystem-center-ports"
  readonly property string pluginsCmd: pluginDir + "/bin/omnisystem-center-plugins"
  readonly property string docsUrl: "https://github.com/gameticharles/omnisystem-center/blob/master/docs"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || home + "/.cache"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
  readonly property string stateDir: stateHome + "/omnisystem-center"
  readonly property string cacheDir: cacheHome + "/omnisystem-center"
  readonly property string profilesDir: Quickshell.env("OMARCHY_POWERPROFILES_STATE_DIR") || stateHome + "/omarchy/powerprofiles"

  // ------------------------------------------------------------- settings
  // Pushed by the bar widget from its shell.json entry (see manifest schema).

  property var settings: ({})
  property string barLabelMode: "none"
  property int panelWidth: 560
  property string startTab: "last"
  property int lowLevel: 10
  property int criticalLevel: 5
  property string criticalSetting: "hibernate"
  property int lowProfileLevel: 20
  property bool autoProfiles: true
  property int gadgetLowLevel: 15
  property bool gadgetFullAlert: true
  property string externalPathSetting: ""
  property var nameSetting: ({})
  property bool systemMonitorEnabled: true
  property bool notifications: true
  property bool energyMeterEnabled: true
  property bool processesTab: true
  property bool portsTab: true
  property bool pluginsTab: true
  property bool portWatch: true
  property bool barPorts: true
  property int highWattThreshold: 0
  property bool showPercent: true
  property string barGpu: "discrete"
  property string barGpuValue: "usage"

  function applySettings(s) {
    settings = s || {}
    function get(k, d) { return s && s[k] !== undefined && s[k] !== null ? s[k] : d }
    function num(k, d, lo, hi) {
      var n = Math.round(Number(get(k, d)))
      return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : d
    }
    var label = String(get("barLabel", "draw"))
    if (Model.BAR_LABELS.indexOf(label) < 0) label = "draw"
    barLabelMode = label
    // Omarchy's Power widget's own switch, kept under the same key.
    showPercent = get("showPercentage", true) !== false
    panelWidth = ({ compact: 460, comfortable: 560, wide: 680 })[get("panelWidth", "comfortable")] || 560
    startTab = String(get("startTab", "last"))
    lowLevel = num("lowLevel", 10, 0, 50)
    criticalLevel = num("criticalLevel", 5, 0, 25)
    var action = String(get("criticalAction", "hibernate"))
    criticalSetting = ["hibernate", "suspend", "none"].indexOf(action) >= 0 ? action : "hibernate"
    lowProfileLevel = num("lowBatteryProfile", 20, 0, 50)
    autoProfiles = get("autoProfiles", true) !== false
    gadgetLowLevel = num("gadgetLowLevel", 15, 0, 50)
    gadgetFullAlert = get("gadgetFullAlert", true) !== false
    externalPathSetting = String(get("externalPath", "") || "")
    var names = get("names", {})
    nameSetting = names && typeof names === "object" ? names : {}
    systemMonitorEnabled = get("systemMonitor", true) !== false
    notifications = get("notifications", true) !== false
    energyMeterEnabled = get("energyMeter", true) !== false
    processesTab = get("processesTab", true) !== false
    portsTab = get("portsTab", true) !== false
    pluginsTab = get("pluginsTab", true) !== false
    portWatch = get("portWatch", true) !== false
    barPorts = get("barPorts", true) !== false
    highWattThreshold = num("highWattThreshold", 0, 0, 5000)
    barGpu = Model.barGpuSetting(get("barGpu", "discrete"))
    var gv = String(get("barGpuValue", "usage"))
    barGpuValue = Model.BAR_GPU_VALUE.indexOf(gv) >= 0 ? gv : "usage"
  }

  // A bar setting changed from the panel or the icon, written back to shell.json.
  function updateBarSettings(patch) {
    var next = Object.assign({}, settings, patch)
    applySettings(next)
    if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline(pluginId, next)
  }

  // Omarchy's IPC command: the percentage on or off.
  function togglePercentage() { updateBarSettings({ showPercentage: !showPercent }) }

  // Right-click on the icon: the draw, today's energy, today's cost, the
  // battery in or out, nothing (the percentage stays as it is).
  function cycleBarLabel() { updateBarSettings({ barLabel: Model.nextBarLabel(barLabelMode) }) }

  // ------------------------------------------------------------ helpers

  Component {
    id: runnerComponent
    Runner {}
  }

  function run(argv, input, callback) {
    var p = runnerComponent.createObject(root, {
      command: argv,
      input: input === undefined || input === null ? "" : String(input),
      hasInput: input !== undefined && input !== null,
      callback: callback || null
    })
    if (p) p.running = true
    return p
  }

  function notify(title, body, urgency, icon) {
    Quickshell.execDetached(["notify-send", "-a", appName, "-u", urgency || "normal",
      "-i", icon || "battery", title, body || ""])
  }

  // Optional notes: the user can switch them off.
  function note(title, body) {
    if (notifications) notify(title, body, "normal")
  }

  property var messages: []

  function say(level, text) {
    if (!text) return
    messages = [{ level: level, text: String(text) }].concat(messages).slice(0, 4)
  }

  function clearMessages() { messages = [] }

  // ------------------------------------------------------------- panels

  property int panelsOpen: 0
  readonly property bool panelOpen: panelsOpen > 0
  property string currentTab: "overview"
  property bool systemViewOpen: false
  property bool energyViewOpen: false
  property bool processesViewOpen: false
  property bool portsViewOpen: false
  property bool pluginsViewOpen: false

  function panelOpened() {
    panelsOpen++
    refreshNow()
  }

  function panelClosed() {
    panelsOpen = Math.max(0, panelsOpen - 1)
    if (panelsOpen === 0) lightbox = null
    if (panelsOpen === 0) { systemViewOpen = false; energyViewOpen = false; processesViewOpen = false; portsViewOpen = false; pluginsViewOpen = false }
  }

  // Through the scoped shell API when it answers, else through Omarchy's own
  // IPC (some shell versions do not let a service summon its bar widget).
  function shellPanel(method) {
    var ok = false
    try {
      if (shell && typeof shell[method] === "function")
        ok = method === "hide" ? shell.hide(pluginId) === true : shell[method](pluginId, "{}") === true
    } catch (e) {}
    if (!ok) Quickshell.execDetached(method === "hide"
      ? ["omarchy-shell", "-q", "shell", "hide", pluginId]
      : ["omarchy-shell", "-q", "shell", method, pluginId, "{}"])
  }

  function togglePanel() { shellPanel(panelsOpen > 0 ? "hide" : "summon") }
  function openPanel() { if (panelsOpen === 0) shellPanel("summon") }
  function closePanel() { if (panelsOpen > 0) shellPanel("hide") }

  property string requestedTab: ""
  property int tabRequest: 0

  property bool tabRequestPending: false

  function showTab(tab) {
    requestedTab = String(tab || "overview")
    tabRequestPending = panelsOpen === 0
    tabRequest++
    openPanel()
  }

  function uiState() {
    var ui = store.ui && typeof store.ui === "object" ? store.ui : {}
    return { views: Object.assign({}, ui.views || {}), scroll: Object.assign({}, ui.scroll || {}) }
  }

  function viewStateFor(key) {
    var v = uiState().views[key]
    return v && typeof v === "object" ? v : ({})
  }

  function saveViewState(key, state) {
    var ui = uiState()
    ui.views[key] = state
    updateState({ ui: ui })
  }

  function scrollFor(tab) {
    var y = Number(uiState().scroll[tab])
    return isFinite(y) && y > 0 ? y : 0
  }

  function saveScroll(tab, y) {
    var ui = uiState()
    if (Math.round(ui.scroll[tab] || 0) === Math.round(y || 0)) return
    ui.scroll[tab] = Math.max(0, Math.round(y || 0))
    updateState({ ui: ui })
  }

  function initialTab() {
    if (startTab === "last") return store.lastTab || "overview"
    return startTab
  }

  function rememberTab(tab) {
    currentTab = tab
    if (store.lastTab !== tab) updateState({ lastTab: tab })
  }

  function refreshNow() {
    refreshBatteryInfo()
    refreshProfiles()
    refreshIdle()
    probe()
    refreshHeadsets()
    refreshCollectors()
  }

  // ------------------------------------------------------------ battery

  readonly property var device: UPower.displayDevice
  readonly property bool hasBattery: !!(device && device.isPresent)
  readonly property bool onBattery: UPower.onBattery
  readonly property var upowerStates: ({
    Charging: UPowerDeviceState.Charging,
    Discharging: UPowerDeviceState.Discharging,
    FullyCharged: UPowerDeviceState.FullyCharged,
    PendingCharge: UPowerDeviceState.PendingCharge
  })
  readonly property real fraction: Model.batteryFraction(device)
  readonly property int level: hasBattery ? Math.round(fraction * 100) : -1
  readonly property bool discharging: hasBattery && onBattery
  readonly property bool thresholdActive: Model.chargeThresholdActive(device, onBattery, upowerStates)
  readonly property bool fullyCharged: hasBattery && device.state === UPowerDeviceState.FullyCharged && !thresholdActive
  readonly property bool batteryFull: fullyCharged || (!discharging && fraction >= 1)
  readonly property bool flowIdle: batteryFull || thresholdActive
  readonly property bool charging: hasBattery && !onBattery && !flowIdle
  readonly property real watts: hasBattery ? Math.abs(Number(device.changeRate || 0)) : 0
  readonly property bool flowing: hasBattery && !flowIdle && watts >= 0.05
  readonly property string batteryGlyph: Model.batteryIcon(device, onBattery, upowerStates)
  readonly property string mode: Model.modeLabel(device, onBattery, upowerStates)
  readonly property string timeText: {
    if (!hasBattery || flowIdle) return ""
    return Model.formatDuration(onBattery ? device.timeToEmpty : device.timeToFull)
  }
  readonly property bool isLow: discharging && lowLevel > 0 && level >= 0 && level <= lowLevel

  property var batteryInfo: ({})

  function refreshBatteryInfo() {
    if (!hasBattery || batteryProc.running) return
    batteryProc.running = true
  }

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseKeyValue(text)
        // Keep the last good reading across the empty ones around plug events.
        if (Object.keys(next).length) root.batteryInfo = next
      }
    }
  }

  // ------------------------------------------------- what the machine can do

  property var caps: ({})
  property bool probed: false
  readonly property var backend: Model.chargeLimitBackend(caps)
  readonly property bool limitCapable: ["sysfs", "apple", "upower", "acer"].indexOf(backend.kind) >= 0
  readonly property var sysfsBattery: Model.parseSysfsBattery(caps.battery ? caps.battery.files : {})
  readonly property real temperature: {
    if (sysfsBattery.temperature > 0) return sysfsBattery.temperature
    var up = caps.threshold && caps.threshold.upower ? Number(caps.threshold.upower.temperature) : 0
    return up > 0 ? Math.round(up * 10) / 10 : -1
  }
  readonly property var keyboard: caps.keyboard || null
  // What may stop suspend or hibernate from coming back (see docs/sleep.md).
  readonly property var sleepIssues: caps.sleep && caps.sleep.issues ? caps.sleep.issues : []
  function sleepRisk(action) {
    for (var i = 0; i < sleepIssues.length; i++) if (sleepIssues[i].affects.indexOf(action) >= 0) return sleepIssues[i].text
    return ""
  }
  readonly property bool lidPresent: !!caps.lid
  property bool suspendAvailable: true
  property bool hibernateAvailable: false
  readonly property var powerActions: Model.powerActions(suspendAvailable, hibernateAvailable)
  readonly property string criticalAction: Model.resolveCriticalAction(criticalSetting, hibernateAvailable, suspendAvailable)

  function probe() {
    if (probeProc.running) return
    probeProc.running = true
  }

  Process {
    id: probeProc
    command: [root.probeCmd]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.caps = JSON.parse(text)
        } catch (e) {
          return
        }
        root.probed = true
        root.applyCare()
        root.recordHealthToday()
      }
    }
  }

  function probePowerActions() {
    run(["omarchy-toggle-enabled", "suspend-off"], null, function(code) { root.suspendAvailable = code !== 0 })
    run(["omarchy-hibernation-available"], null, function(code) { root.hibernateAvailable = code === 0 })
  }

  // ---------------------------------------------------------- saved state

  readonly property var defaultState: ({
    care: { managed: false, enabled: false, limit: 80, sailing: false, sailStart: 75, heatGuard: true,
            heatLimit: 40, heatResume: 36, unplugReminder: true, topUpUntil: 0 },
    keyboard: { enabled: false, ac: 100, battery: 30 },
    lidHold: false,
    timer: null,
    critical: null,
    lowProfile: { active: false, previous: "" },
    calibration: { phase: "idle", startedAt: 0 },
    notified: { low: false, critical: false },
    unplugNotified: false,
    heatHolding: false,
    history: [],
    days: ({}),
    sessions: [],
    session: null,
    healthLog: [],
    gadgetNames: ({}),
    lastTab: "overview",
    // Each tab's view state (search, filters, sort, what is open) and scroll
    // position, so closing the panel or switching tabs loses nothing.
    ui: ({ views: {}, scroll: {} }),
    lastTick: 0,
    lastLevel: -1
  })

  property var store: defaultState
  property bool stateLoaded: false

  function mergedState(saved) {
    var out = {}
    for (var k in defaultState) out[k] = saved && saved[k] !== undefined ? saved[k] : defaultState[k]
    out.care = Object.assign({}, defaultState.care, saved && saved.care ? saved.care : {})
    out.keyboard = Object.assign({}, defaultState.keyboard, saved && saved.keyboard ? saved.keyboard : {})
    return out
  }

  function updateState(patch) {
    store = Object.assign({}, store, patch)
    saveSoon()
  }

  function updateCare(patch) {
    updateState({ care: Object.assign({}, store.care, patch) })
    applyCare()
  }

  function saveSoon() {
    if (stateLoaded) saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 1500
    onTriggered: stateFile.setText(JSON.stringify(root.store) + "\n")
  }

  FileView {
    id: stateFile
    // Set once the folder exists (Component.onCompleted).
    printErrors: false
    atomicWrites: true
    onLoaded: {
      var saved = null
      try { saved = JSON.parse(text()) } catch (e) { saved = null }
      root.store = root.mergedState(saved)
      root.stateLoaded = true
      root.afterLoad()
    }
    onLoadFailed: {
      root.store = root.mergedState(null)
      root.stateLoaded = true
      root.afterLoad()
    }
  }

  function afterLoad() {
    restoreSleepTimer()
    currentTab = initialTab()
    applyCare()
    tick()
  }

  // --------------------------------------------- warnings and the critical action

  // Omarchy's own battery service sends a fixed 10% warning and applies the
  // remembered profile on plug events. While it is on, OmniSystem Center
  // leaves those two to it, so nothing is sent twice.
  property bool omarchyBatteryOn: true

  FileView {
    path: root.configHome + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var config = JSON.parse(text())
        var disabled = Array.isArray(config.disabledPlugins) ? config.disabledPlugins : []
        root.omarchyBatteryOn = disabled.indexOf("omarchy.battery") < 0
      } catch (e) {}
    }
  }

  function takeOverBatteryService() {
    run(["omarchy-plugin-disable", "omarchy.battery"], null, function(code, out, err) {
      if (code === 0) say("info", "OmniSystem Center now sends the battery warnings and switches profiles.")
      else say("error", "Could not turn off Omarchy's battery service: " + (err || out).trim())
    })
  }

  function handBackBatteryService() {
    run(["omarchy-plugin-enable", "omarchy.battery"], null, function(code, out, err) {
      if (code !== 0) say("error", "Could not turn Omarchy's battery service back on: " + (err || out).trim())
    })
  }

  property bool criticalPending: false
  property real criticalEndsAt: 0
  property int criticalRemaining: 0
  property var criticalNote: null

  function checkBattery() {
    if (!stateLoaded || !hasBattery) return
    if (store.critical && !criticalPending) resumeCritical()
    var result = Model.batteryWarnings(level, discharging, omarchyBatteryOn ? 0 : lowLevel, criticalLevel, store.notified)
    if (JSON.stringify(result.notified) !== JSON.stringify(store.notified)) updateState({ notified: result.notified })
    if (result.notifyLow) Quickshell.execDetached(["omarchy-battery-low", String(level)])
    if (result.notifyCritical && !criticalPending) startCritical()
    if (criticalPending && !discharging) cancelCritical("Plugged in.")
    checkLowProfile()
    checkUnplug()
  }

  function startCritical(endsAt) {
    var action = criticalAction
    if (action === "none") {
      notify("Battery critical", "Down to " + level + "%. Plug in now.", "critical", "battery-empty")
      return
    }
    // Saved, so a shell or plugin reload carries the countdown on instead of
    // dropping it (the warning flag is saved too and would not start it again).
    criticalEndsAt = endsAt || Date.now() + 60000
    criticalRemaining = Model.timerRemaining(criticalEndsAt, Date.now())
    criticalPending = true
    updateState({ critical: { endsAt: criticalEndsAt } })
    var verb = action === "hibernate" ? "Hibernating" : "Suspending"
    criticalNote = run(["notify-send", "-a", appName, "-u", "critical", "-i", "battery-empty", "-A", "cancel=Cancel", "-w",
      "Battery critical: " + level + "%", verb + " in " + criticalRemaining + " seconds. Plug in, or cancel here."], null, function(code, out) {
        if (String(out).trim() === "cancel") root.cancelCritical("Canceled.")
      })
  }

  function resumeCritical() {
    var endsAt = Model.resumeCritical(store.critical, Date.now(), discharging, level, criticalLevel)
    if (endsAt) startCritical(endsAt)
    else updateState({ critical: null })
  }

  function cancelCritical(reason) {
    if (!criticalPending) return
    criticalPending = false
    updateState({ critical: null })
    if (criticalNote) { try { criticalNote.running = false } catch (e) {} }
    criticalNote = null
    say("info", "Critical action stopped. " + (reason || ""))
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.criticalPending
    onTriggered: {
      root.criticalRemaining = Model.timerRemaining(root.criticalEndsAt, Date.now())
      if (root.criticalRemaining > 0) return
      root.criticalPending = false
      root.updateState({ critical: null })
      if (root.criticalNote) { try { root.criticalNote.running = false } catch (e) {} }
      root.criticalNote = null
      if (root.discharging) root.runPowerAction(root.criticalAction)
    }
  }

  // ------------------------------------------------------------ profiles

  property var profiles: []
  property string activeProfile: ""
  property string savedAc: ""
  property string savedBattery: ""
  readonly property string currentSource: onBattery ? "battery" : "ac"

  function refreshProfiles() {
    if (!profilesProc.running) profilesProc.running = true
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseProfiles(text, 0)
        if (parsed.profiles.length === 0) return
        root.profiles = parsed.profiles
        root.activeProfile = parsed.activeProfile
      }
    }
  }

  FileView {
    id: acProfileFile
    path: root.profilesDir + "/ac"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.savedAc = text().trim()
    onLoadFailed: root.savedAc = ""
  }

  FileView {
    id: batteryProfileFile
    path: root.profilesDir + "/battery"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.savedBattery = text().trim()
    onLoadFailed: root.savedBattery = ""
  }

  function rememberedFor(source) {
    return Model.rememberedProfile(source === "ac" ? savedAc : savedBattery, source, profiles)
  }

  // For the source in use: apply and remember (Omarchy's command does both).
  // For the other one: only remember, so it applies on the next plug event.
  function setProfileFor(source, profile) {
    if (profiles.indexOf(profile) < 0) return
    if (Model.profileChange(source, onBattery) === "apply") {
      run(["omarchy-powerprofiles-set", source, profile], null, function() { root.refreshProfiles() })
      if (store.lowProfile.active) updateState({ lowProfile: { active: false, previous: "" } })
    } else {
      run(["mkdir", "-p", profilesDir], null, function(code) {
        if (code !== 0) return
        var file = source === "ac" ? acProfileFile : batteryProfileFile
        file.setText(profile + "\n")
      })
      if (source === "ac") savedAc = profile
      else savedBattery = profile
    }
  }

  function setProfile(profile) { setProfileFor(currentSource, profile) }

  // Applied without saving: the low-battery switch must not overwrite the
  // profile remembered for battery.
  function applyProfileOnly(profile) {
    run(["powerprofilesctl", "set", profile], null, function() { root.refreshProfiles() })
  }

  function checkLowProfile() {
    var r = Model.lowBatteryProfile(level, discharging, lowProfileLevel, store.lowProfile, activeProfile, profiles)
    if (r.active !== store.lowProfile.active || r.previous !== store.lowProfile.previous)
      updateState({ lowProfile: { active: r.active, previous: r.previous } })
    if (r.apply) {
      applyProfileOnly(r.apply)
      if (r.apply === "power-saver") note("Power saver on", "Battery at " + level + "%. The previous profile comes back once you charge.")
    }
  }

  // ---------------------------------------------------------- keep awake

  property bool keepAwake: false

  function refreshIdle() {
    run(["omarchy-toggle-idle", "--status"], null, function(code, out) {
      try { root.keepAwake = JSON.parse(out).enabled === true } catch (e) {}
    })
  }

  function setKeepAwake(on) {
    keepAwake = !!on
    run(["omarchy-toggle-idle", on ? "stay-awake" : "allow-idle"], null, function() { root.refreshIdle() })
  }

  // --------------------------------------------------------- sleep timer

  property int timerLeft: 0
  readonly property bool timerActive: !!store.timer && timerLeft > 0

  function startSleepTimer(minutes, action) {
    var m = Math.max(1, Math.min(24 * 60, Math.round(Number(minutes) || 0)))
    var a = Model.TIMER_ACTIONS.indexOf(action) >= 0 ? action : "suspend"
    if (a === "hibernate" && !hibernateAvailable) a = "suspend"
    if (a === "suspend" && !suspendAvailable) a = "shutdown"
    updateState({ timer: { endsAt: Date.now() + m * 60000, action: a, minutes: m, warned: false } })
    timerLeft = m * 60
    note("Sleep timer", Model.profileLabel(a) + " in " + Model.formatDuration(m * 60) + ".")
  }

  function extendSleepTimer(minutes) {
    if (!store.timer) return
    var t = Object.assign({}, store.timer)
    t.endsAt = Math.max(Date.now(), t.endsAt) + minutes * 60000
    t.warned = false
    updateState({ timer: t })
    timerLeft = Model.timerRemaining(t.endsAt, Date.now())
  }

  function cancelSleepTimer() {
    updateState({ timer: null })
    timerLeft = 0
  }

  function restoreSleepTimer() {
    var t = Model.restoreTimer(store.timer, Date.now())
    if (!t) { if (store.timer) updateState({ timer: null }); return }
    timerLeft = Math.max(30, Model.timerRemaining(t.endsAt, Date.now()))
  }

  Timer {
    interval: 1000
    repeat: true
    running: !!root.store.timer
    onTriggered: {
      var t = root.store.timer
      if (!t) return
      root.timerLeft = Model.timerRemaining(t.endsAt, Date.now())
      if (root.timerLeft === 60 && !t.warned) {
        root.notify("Sleep timer", Model.profileLabel(t.action) + " in one minute.", "normal", "clock")
        root.updateState({ timer: Object.assign({}, t, { warned: true }) })
      }
      if (root.timerLeft > 0) return
      root.updateState({ timer: null })
      root.runPowerAction(t.action)
    }
  }

  // ------------------------------------------------------- power actions

  function runPowerAction(key) {
    var action = Model.powerAction(key)
    if (!action) return false
    if (key === "suspend" && !suspendAvailable) return false
    if (key === "hibernate" && !hibernateAvailable) return false
    closePanel()
    // Give the panel a moment to close so the lock screen is not covered.
    Qt.callLater(function() { Quickshell.execDetached(action.command) })
    return true
  }

  // ----------------------------------------------------------- lid hold

  // Keeps the machine running with the lid shut (downloads, music) by holding
  // logind's lid switch. Omarchy already ignores the lid while docked.
  readonly property bool lidHoldOn: store.lidHold === true && lidPresent

  Process {
    id: lidProc
    running: root.lidHoldOn
    command: ["systemd-inhibit", "--what=handle-lid-switch", "--who=" + root.appName,
              "--why=Keep running with the lid closed", "--mode=block", "sleep", "infinity"]
    onExited: function(code) {
      if (root.lidHoldOn && code !== 0 && code !== 143 && code !== 15) {
        root.updateState({ lidHold: false })
        root.say("error", "Could not hold the lid switch (systemd-inhibit exited " + code + ").")
      }
    }
  }

  function setLidHold(on) { updateState({ lidHold: !!on }) }

  // -------------------------------------------------- keyboard backlight

  function setKeyboardPrefs(patch) {
    updateState({ keyboard: Object.assign({}, store.keyboard, patch) })
    applyKeyboard()
  }

  function applyKeyboard() {
    if (!keyboard || !store.keyboard.enabled) return
    var value = Model.keyboardLevel(store.keyboard, onBattery, keyboard.max)
    if (value < 0) return
    run(["brightnessctl", "-q", "-d", keyboard.device, "set", String(value)], null, function(code, out, err) {
      if (code !== 0) root.say("error", "Keyboard backlight: " + (err || out).trim())
    })
  }

  // ---------------------------------------------------------- charge care

  readonly property bool topUp: Model.topUpActive(store.care.topUpUntil, nowMs)
  readonly property bool calibrating: store.calibration && store.calibration.phase !== "idle"
  property real nowMs: Date.now()
  property bool careBusy: false

  function startTopUp() { updateCare({ managed: true, topUpUntil: Date.now() + 24 * 3600000 }) }
  function stopTopUp() { updateCare({ topUpUntil: 0 }) }

  function startCalibration() {
    updateState({ calibration: { phase: "charge", startedAt: Date.now() } })
    updateCare({ managed: true })
    note("Calibration started", "Charging to 100%. Keep the charger in until told to unplug.")
  }

  function stopCalibration() {
    updateState({ calibration: { phase: "idle", startedAt: 0 } })
    applyCare()
  }

  readonly property var wantedLimit: Model.desiredLimit({
    backend: backend, enabled: store.care.enabled, limit: store.care.limit, sailing: store.care.sailing,
    sailStart: store.care.sailStart, topUp: topUp, calibrating: calibrating,
    heatHolding: store.heatHolding && store.care.heatGuard, level: level
  })

  // Only once the user has used a care control does OmniSystem Center write
  // the hardware limit, so a limit set by other tools is left alone.
  function applyCare() {
    if (!stateLoaded || !probed || !store.care.managed || careBusy) return
    var want = wantedLimit
    if (!want) return
    var argv = null
    if (backend.kind === "upower" || backend.kind === "acer") {
      var on = Model.upowerWanted(want)
      if (on !== backend.enabled) argv = [ctlCmd, backend.kind === "acer" ? "acer-health" : "upower-limit", on ? "on" : "off"]
    } else if (!Model.limitMatches(want, { end: backend.end, start: backend.start })) {
      argv = backend.kind === "apple" ? [ctlCmd, "apple-limit", String(want.end)]
           : want.start >= 0 ? [ctlCmd, "limit", String(want.end), String(want.start)]
           : [ctlCmd, "limit", String(want.end)]
    }
    if (!argv) return
    careBusy = true
    run(argv, null, function(code, out, err) {
      root.careBusy = false
      if (code !== 0) {
        root.say("error", "Charge limit: " + (err || out).trim())
        if (code === 4) root.updateCare({ managed: false })
      }
      root.probe()
    })
  }

  function checkHeat() {
    if (!store.care.heatGuard || !(temperature > 0)) {
      if (store.heatHolding) { updateState({ heatHolding: false }); applyCare() }
      return
    }
    var hold = Model.heatHold(temperature, store.heatHolding, store.care.heatLimit, store.care.heatResume)
    if (hold === store.heatHolding) return
    updateState({ heatHolding: hold })
    if (hold) note("Battery is hot", temperature + " °C. " + (limitCapable ? "Charging paused until it cools." : "Unplugging lets it cool faster."))
    applyCare()
  }

  function checkUnplug() {
    if (limitCapable || !store.care.unplugReminder) return
    var r = Model.unplugReminder(level, !onBattery && !batteryFull, store.care.limit, store.unplugNotified)
    if (r.notified !== store.unplugNotified) updateState({ unplugNotified: r.notified })
    if (r.notify) notify("Unplug the charger", "The battery is at " + level + "%. Stopping around " + store.care.limit + "% helps it last.", "normal", "battery-full-charging")
  }

  function checkTopUpEnd() {
    // A top-up ends once the battery was full and the charger comes out.
    if (topUp && onBattery && store.lastLevel >= 98) stopTopUp()
  }

  function checkCalibration() {
    if (!calibrating) return
    var s = Model.calibrationStep(store.calibration, level, onBattery, Date.now())
    if (s.phase !== store.calibration.phase) {
      updateState({ calibration: { phase: s.phase, startedAt: s.startedAt } })
      if (s.message) notify("Calibration", s.message, "normal", "battery")
      applyCare()
    }
  }

  // ----------------------------------------------------- history & insights

  readonly property var days7: Model.recentDays(store.days, nowMs, 7)
  readonly property real drainRate: Model.drainPerHour(store.history, nowMs)
  readonly property real wearPer100: Model.wearRate(store.healthLog)
  readonly property real acShare: {
    var bat = 0, ac = 0
    for (var i = 0; i < days7.length; i++) { bat += days7[i].bat; ac += days7[i].ac }
    return bat + ac > 0 ? ac / (bat + ac) : 0
  }
  readonly property var tips: Model.careTips({
    health: sysfsBattery.health, backend: backend.kind, onAcShare: acShare, temperature: temperature,
    limitEnabled: store.care.enabled, limit: store.care.limit
  })

  function recordHealthToday() {
    if (!stateLoaded || sysfsBattery.health < 0) return
    var key = Model.dayKey(Date.now())
    var log = store.healthLog || []
    if (log.length && log[log.length - 1][0] === key) return
    updateState({ healthLog: Model.recordHealth(log, Date.now(), sysfsBattery.health, sysfsBattery.cycles) })
  }

  // Once a minute: history, the day's totals, sessions, care checks.
  function tick() {
    if (!stateLoaded) return
    var now = Date.now()
    nowMs = now
    if (!hasBattery) return
    var patch = {}
    var signed = discharging ? -watts : (flowing ? watts : 0)
    patch.history = Model.addSample(store.history, now, level, signed)
    var minutes = store.lastTick > 0 ? (now - store.lastTick) / 60000 : 0
    // Longer than two minutes means the machine slept: not counted.
    if (minutes > 0 && minutes <= 2) {
      var drained = discharging && store.lastLevel > level ? store.lastLevel - level : 0
      var wh = discharging ? watts * minutes / 60 : 0
      patch.days = Model.accumulateDay(store.days, now, minutes, discharging, drained, wh)
    }
    var s = Model.sessionUpdate(store.session, store.sessions, discharging, now, level)
    patch.session = s.current
    patch.sessions = s.sessions
    patch.lastTick = now
    patch.lastLevel = level
    updateState(patch)
    checkCalibration()
    checkHeat()
    checkTopUpEnd()
  }

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.tick()
  }

  // The battery checks (Omarchy's own service checks every 30 s).
  Timer {
    interval: 30000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.checkBattery()
  }

  // Re-probe now and then: temperature, limits, the keyboard LED.
  Timer {
    interval: root.panelOpen ? 15000 : 300000
    repeat: true
    running: true
    onTriggered: root.probe()
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.panelOpen
    onTriggered: { root.refreshBatteryInfo(); root.refreshProfiles(); root.nowMs = Date.now() }
  }

  onLevelChanged: checkBattery()

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.checkBattery()
      root.tick()
      root.applyKeyboard()
      root.refreshBatteryInfo()
      root.probe()
      if (root.autoProfiles && !root.omarchyBatteryOn)
        root.run(["omarchy-powerprofiles-set", root.onBattery ? "battery" : "ac"], null, function() { root.refreshProfiles() })
      else
        profileRefreshLater.restart()
    }
  }

  Timer {
    id: profileRefreshLater
    interval: 1500
    onTriggered: root.refreshProfiles()
  }

  function exportReport(copy) {
    var r = Model.reportMarkdown({
      generated: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm"),
      battery: hasBattery ? Object.assign({}, sysfsBattery, { temperature: temperature }) : null,
      level: level,
      limit: backend.kind === "none" ? "" : (store.care.enabled ? store.care.limit + "%" : "off"),
      wearRate: wearPer100,
      days: Model.recentDays(store.days, Date.now(), 14).filter(function(d) { return d.bat || d.ac }),
      sessions: (store.sessions || []).slice(0, 10),
      healthLog: store.healthLog,
      gadgets: gadgets,
      tips: tips
    })
    if (copy) {
      run(["wl-copy", "--type", "text/plain"], r, function(code) {
        if (code === 0) root.say("info", "Report copied to the clipboard.")
      })
      return
    }
    var dir = home + "/Documents"
    var file = dir + "/battery-report-" + Model.dayKey(Date.now()) + ".md"
    run(["mkdir", "-p", dir], null, function(code) {
      if (code !== 0) { root.say("error", "Could not create " + dir); return }
      reportFile.path = file
      reportFile.setText(r)
      root.say("info", "Report saved to " + file.replace(root.home, "~"))
      root.run(["notify-send", "-a", root.appName, "-i", "battery", "-A", "open=Open", "-w", "Battery report saved", file.replace(root.home, "~")],
        null, function(c, out) { if (String(out).trim() === "open") Quickshell.execDetached(["xdg-open", file]) })
    })
  }

  FileView {
    id: reportFile
    printErrors: false
    blockLoading: false
  }

  // ------------------------------------------------------------ gadgets

  readonly property string externalPath: externalPathSetting || cacheHome + "/omarchy-accessories/external.json"
  readonly property string budsStatusPath: stateHome + "/omarchy-buds/status.json"

  property var headsetDevices: []
  property var budsDevices: []
  property var collectorDevices: []
  property string externalText: ""
  property string gfpsText: ""
  property var sysfsOnline: ({})
  property real nowSec: Date.now() / 1000
  property var gadgetTrends: ({})
  property var gadgetNotified: ({})
  property var gadgetFullNotified: ({})
  property var tools: ({})

  readonly property var externalDevices: Model.fromExternal(externalText, nowSec)
  readonly property var gfpsDevices: Model.fromExternal(gfpsText, nowSec)

  readonly property var upowerDevices: {
    var list = UPower.devices ? UPower.devices.values : []
    var out = []
    for (var i = 0; i < list.length; i++) {
      var d = list[i]
      var _ = [d.percentage, d.state, d.isPresent, d.model]
      if (root.sysfsOnline[d.nativePath] === false) continue
      var g = Model.fromUPower(d, UPowerDeviceType.toString(d.type), UPowerDeviceState.Charging, UPowerDeviceState.Unknown)
      if (g) out.push(g)
    }
    return out
  }

  readonly property var rawGadgets: Model.mergeDevices([budsDevices, collectorDevices, gfpsDevices,
    headsetDevices, externalDevices, upowerDevices])
  readonly property var gadgetNames: Object.assign({}, nameSetting, store.gadgetNames || {})
  property var gadgets: []
  readonly property var lowestGadget: Model.lowestGadget(gadgets)

  function updateGadgets() {
    var named = Model.applyNames(rawGadgets, gadgetNames)
    var result = Model.applyTrends(named, gadgetTrends, Date.now() / 1000)
    gadgetTrends = result.trends
    gadgets = result.devices
  }

  onRawGadgetsChanged: updateGadgets()
  onGadgetNamesChanged: updateGadgets()
  onGadgetsChanged: checkGadgets()

  function renameGadget(reported, name) {
    var next = Object.assign({}, store.gadgetNames || {})
    var clean = String(name || "").trim().slice(0, 40)
    if (clean && clean !== reported) next[reported] = clean
    else delete next[reported]
    updateState({ gadgetNames: next })
  }

  function checkGadgets() {
    var low = Model.gadgetLowAlerts(gadgets, gadgetLowLevel, gadgetNotified)
    gadgetNotified = low.notified
    for (var i = 0; i < low.alerts.length; i++)
      notify(low.alerts[i].name + " battery low", low.alerts[i].level + "% left.", "critical", "battery-caution")
    var full = Model.gadgetFullAlerts(gadgets, gadgetFullNotified)
    gadgetFullNotified = full.notified
    if (gadgetFullAlert)
      for (var j = 0; j < full.alerts.length; j++)
        notify(full.alerts[j].name + " charged", "It can come off the charger.", "normal", "battery-full-charged")
  }

  // The vendor app behind a gadget row, when it is installed.
  function gadgetApp(d) {
    var command = null
    if (d.key.indexOf("buds:") === 0) command = ["galaxybudsclient", "app", "--activate-window"]
    else if (/^solaar:|^upower:hidpp/.test(d.key) || /^logitech /i.test(d.name)) command = ["solaar"]
    return command && tools[command[0]] === true ? command : null
  }

  function openGadgetApp(d) {
    var command = gadgetApp(d)
    if (command) { closePanel(); Quickshell.execDetached(command) }
  }

  Process {
    running: true
    command: ["sh", "-c", "for t in headsetcontrol solaar galaxybudsclient brightnessctl wl-copy; do command -v \"$t\" >/dev/null && echo \"$t\"; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = {}
        String(text).split("\n").forEach(function(name) { if (name) found[name] = true })
        root.tools = found
        root.refreshHeadsets()
      }
    }
  }

  function refreshHeadsets() {
    if (tools.headsetcontrol === true && !headsetProc.running) headsetProc.running = true
  }

  function refreshCollectors() {
    if (collectorsProc.running) return
    collectorsProc.environment = { "OMNISYSTEM_CENTER_PANEL_OPEN": panelOpen ? "1" : null }
    collectorsProc.running = true
  }

  Process {
    id: headsetProc
    command: ["headsetcontrol", "-o", "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.headsetDevices = Model.fromHeadsetControl(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) { if (code !== 0 && code !== 1) root.headsetDevices = [] }
  }

  Timer {
    interval: root.panelOpen ? 10000 : 60000
    running: true
    repeat: true
    onTriggered: root.refreshHeadsets()
  }

  Process {
    id: onlineProc
    command: ["sh", "-c", "grep -H . /sys/class/power_supply/*/online 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var map = {}
        var lines = String(text).split("\n")
        for (var i = 0; i < lines.length; i++) {
          var m = lines[i].match(/power_supply\/([^/]+)\/online:(\d+)/)
          if (m) map[m[1]] = m[2] !== "0"
        }
        root.sysfsOnline = map
      }
    }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!onlineProc.running) onlineProc.running = true
  }

  Process {
    id: collectorsProc
    command: [root.gadgetsCmd]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.collectorDevices = Model.fromExternal(text, Date.now() / 1000)
    }
    stderr: StdioCollector { waitForEnd: true }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.nowSec = Date.now() / 1000
      root.refreshCollectors()
      root.updateGadgets()
    }
  }

  Process {
    id: gfpsDaemon
    command: [root.pluginDir + "/sources/gfps-daemon"]
    running: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: gfpsRestart.restart()
  }

  Timer {
    id: gfpsRestart
    interval: 30000
    onTriggered: gfpsDaemon.running = true
  }

  FileView {
    path: root.cacheDir + "/gfps.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.gfpsText = text()
    onTextChanged: root.gfpsText = text()
    onLoadFailed: root.gfpsText = ""
  }

  FileView {
    path: root.externalPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.externalText = text()
    onTextChanged: root.externalText = text()
    onLoadFailed: root.externalText = ""
  }

  FileView {
    path: root.budsStatusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.budsDevices = Model.fromBudsStatus(text())
    onTextChanged: root.budsDevices = Model.fromBudsStatus(text())
    onLoadFailed: root.budsDevices = []
  }

  // ------------------------------------------------------- system monitor

  readonly property int seriesLength: 60
  property var cpuSeries: []
  property var memSeries: []
  property var tempSeries: []
  property var wattSeries: []
  property var packageSeries: []
  // Per GPU (by PCI address), from the energy meter's readings.
  property var gpuBusySeries: ({})
  property var gpuTempSeries: ({})
  property int cpuPercent: -1
  property var memory: ({ used: 0, total: 0, pct: -1 })
  property real cpuTemp: -1
  property real packageWatts: -1
  property int cores: 0
  property var load: []
  property int uptime: 0
  property var cpuFreq: null
  property var temps: []
  property var fans: []
  property var swaps: []
  property var disk: null
  property var _prevCpu: null
  property var _prevEnergy: null
  property real _prevEnergyAt: 0

  Process {
    id: systemProc
    command: [root.probeCmd, "system"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var s
        try { s = JSON.parse(text) } catch (e) { return }
        var now = Date.now()
        root.cpuPercent = Model.cpuUsage(root._prevCpu, s.cpu)
        root._prevCpu = s.cpu
        root.memory = Model.memoryUsage(s.memory)
        root.cpuTemp = s.cpuTemp === null || s.cpuTemp === undefined ? -1 : s.cpuTemp
        root.packageWatts = Model.raplWatts(root._prevEnergy, root._prevEnergyAt, s.raplEnergy, now)
        root._prevEnergy = s.raplEnergy
        root._prevEnergyAt = now
        root.cores = s.cores || 0
        root.load = s.load || []
        root.uptime = s.uptime || 0
        root.cpuFreq = s.freq || null
        root.temps = s.temps || []
        root.fans = s.fans || []
        root.swaps = s.swaps || []
        root.disk = s.disk || null
        var n = root.seriesLength
        root.cpuSeries = Model.pushSeries(root.cpuSeries, root.cpuPercent, n)
        root.memSeries = Model.pushSeries(root.memSeries, root.memory.pct, n)
        root.tempSeries = Model.pushSeries(root.tempSeries, root.cpuTemp, n)
        root.wattSeries = Model.pushSeries(root.wattSeries, root.hasBattery ? (root.discharging ? root.watts : -1) : -1, n)
        root.packageSeries = Model.pushSeries(root.packageSeries, root.packageWatts, n)
        var busy = {}, heat = {}
        for (var g = 0; g < root.gpus.length; g++) {
          var gpu = root.gpus[g]
          if (typeof gpu.busy === "number") busy[gpu.id] = gpu.busy
          else if (gpu.state === "asleep") busy[gpu.id] = 0
          if (typeof gpu.temp === "number") heat[gpu.id] = gpu.temp
        }
        root.gpuBusySeries = Model.pushKeyed(root.gpuBusySeries, busy, n)
        root.gpuTempSeries = Model.pushKeyed(root.gpuTempSeries, heat, n)
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.systemViewOpen && root.systemMonitorEnabled
    triggeredOnStart: true
    onTriggered: if (!systemProc.running) systemProc.running = true
  }

  // --------------------------------------------------------------- settings

  // This plugin's own settings list, from its manifest: the Settings tab is
  // built from it, so a new setting shows up there by itself.
  property var ownSchema: []
  FileView {
    path: root.pluginDir + "/manifest.json"
    printErrors: false
    onLoaded: {
      try { root.ownSchema = JSON.parse(text()).barWidget.schema || [] } catch (e) {}
    }
  }

  // ----------------------------------------------------------------- theme

  // The current theme's named colours, so graphs, meters and the power
  // buttons follow the theme. Read again whenever the shell's colours change
  // (a theme switch), since the theme folder itself is swapped, not edited.
  property var palette: Model.parseThemeColors("", String(Color.accent), String(Color.urgent))

  FileView {
    id: themeFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.palette = Model.parseThemeColors(text(), String(Color.accent), String(Color.urgent))
    onLoadFailed: root.palette = Model.parseThemeColors("", String(Color.accent), String(Color.urgent))
  }

  Connections {
    target: Color
    function onAccentChanged() { themeFile.reload() }
    function onForegroundChanged() { themeFile.reload() }
  }

  // ------------------------------------------------------------ device info

  // What the machine is (model, firmware, CPU, storage, graphics, network,
  // audio, USB). Read once when the System tab first opens; it changes only
  // when hardware does, so Refresh reads it again.
  property var deviceInfo: null

  function refreshDevice() {
    run([probeCmd, "device"], null, function(code, out) {
      try { root.deviceInfo = JSON.parse(out) } catch (e) {}
    })
  }

  onSystemViewOpenChanged: if (systemViewOpen && !deviceInfo) refreshDevice()

  // Text to the clipboard through stdin, never argv.
  function copyText(text, what) {
    if (!text) return
    run(["wl-copy"], String(text), function(code) {
      if (code === 0) root.say("info", "Copied " + (what || "it") + ".")
      else root.say("error", "Could not copy: is wl-clipboard installed?")
    })
  }

  function openSystemMonitor() {
    closePanel()
    Quickshell.execDetached(["omarchy-launch-or-focus-tui", "btop"])
  }

  // ----------------------------------------------------------- energy meter

  // The sampler runs while the shell does and stops with it. Each interval
  // (10 s) it prints one line: the draw at the socket, how much of it is
  // measured, and today's and this month's energy and cost.
  property var energyLive: null
  property var energyTick: null
  property var energyPanel: null
  property string energyPeriod: "day"
  property int energyCustomDays: 14
  property bool energySettingsRequested: false
  readonly property real systemWatts: energyLive && typeof energyLive.watts === "number" ? energyLive.watts : -1
  // For the bar: on battery what leaves the battery, refreshed every 2 s (the
  // same figure UPower gives); on AC the meter's socket figure, every 10 s.
  readonly property real drawWatts: {
    if (energyTick && energyTick.source === "battery" && typeof energyTick.battery_w === "number") return energyTick.battery_w
    if (systemWatts >= 0) return systemWatts
    return hasBattery && discharging && watts > 0 ? watts : -1
  }
  // Every GPU: discrete ones are measured while awake; integrated graphics
  // are part of the CPU figure. The bar shows the discrete ones that are awake.
  readonly property var gpus: energyTick && energyTick.gpus ? energyTick.gpus : []
  readonly property bool gpuAwake: !!energyTick && energyTick.gpu_state === "awake"
  readonly property real gpuWatts: gpuAwake && typeof energyTick.gpu_w === "number" ? energyTick.gpu_w : -1
  readonly property bool energyHigh: highWattThreshold > 0 && drawWatts >= highWattThreshold

  // The background ports scan rides along in the sampler (one process).
  readonly property bool portsBackground: barPorts || (portWatch && portsTab)
  Process {
    id: energyProc
    command: [root.energyCmd, "run"].concat(root.portsBackground ? ["--ports", "20"] : [])
    stdout: SplitParser {
      onRead: function(line) {
        var d
        try { d = JSON.parse(line) } catch (e) { return }
        if (d.type === "tick") root.energyTick = d
        else if (d.type === "ports") { if (!root.portsViewOpen) root.takePorts(d) }
        else if (d.type === "budget") root.notify(d.level >= 100 ? "Energy budget reached" : "Energy budget at " + d.level + "%",
          "This month: " + d.cost + " of " + d.budget + " (" + Model.formatKwh(d.kwh) + ").", d.level >= 100 ? "critical" : "normal", "battery-caution")
        else root.energyLive = d
      }
    }
    onExited: {
      root.energyLive = null
      root.energyTick = null
      if (root.energyMeterEnabled) energyRestart.restart()
    }
  }

  Timer {
    id: energyRestart
    interval: 15000
    onTriggered: {
      interval = 15000
      if (root.energyMeterEnabled && !energyProc.running) energyProc.running = true
    }
  }

  // A changed command needs a fresh sampler.
  onPortsBackgroundChanged: if (energyProc.running) { energyProc.running = false; energyRestart.interval = 300; energyRestart.restart() }

  onEnergyMeterEnabledChanged: {
    energyProc.running = energyMeterEnabled
    if (!energyMeterEnabled) { energyLive = null; energyTick = null }
  }

  function refreshEnergy() {
    if (!energyMeterEnabled || energyQuery.running) return
    energyQuery.command = [energyCmd, "panel", energyPeriod, "-n", String(energyCustomDays)]
    energyQuery.running = true
  }

  Process {
    id: energyQuery
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.energyPanel = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.energyViewOpen && root.energyMeterEnabled
    triggeredOnStart: true
    onTriggered: root.refreshEnergy()
  }

  function setEnergyPeriod(period, days) {
    if (days) energyCustomDays = Math.max(1, Math.min(365, Math.round(days)))
    energyPeriod = period
    refreshEnergy()
  }

  // `changes` is {key: text}; the helper validates and writes atomically.
  function setEnergyConfig(changes, done) {
    var argv = [energyCmd, "config"]
    for (var key in changes) argv.push(key + "=" + String(changes[key]))
    argv.push("--json")
    run(argv, null, function(code, out, err) {
      if (code !== 0) {
        root.say("error", String(err || out).trim().replace(/^omnisystem-center-energy: /, ""))
        if (done) done(false)
        return
      }
      root.refreshEnergy()
      if (done) done(true)
    })
  }

  function exportEnergy() {
    run([energyCmd, "export"], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) { r = { ok: false } }
      if (!r.ok) { root.say("error", "Could not export the energy history."); return }
      root.say("info", "Saved " + r.days + " days to " + r.file.replace(root.home, "~") + ".")
    })
  }

  function energyJson() {
    var l = energyLive || {}
    var p = energyPanel && energyPanel.summary ? energyPanel.summary : null
    return {
      watts: systemWatts >= 0 ? systemWatts : null,
      draw: drawWatts >= 0 ? drawWatts : null,
      gpu: gpuAwake ? { watts: gpuWatts >= 0 ? gpuWatts : null } : null,
      source: l.source || null,
      measuredShare: typeof l.measured_share === "number" ? l.measured_share : null,
      untracked: l.untracked || null,
      todayKwh: typeof l.today_kwh === "number" ? l.today_kwh : (p ? p.today.kwh : null),
      todayCost: l.today_cost || (p ? p.today.cost_text : ""),
      monthKwh: typeof l.month_kwh === "number" ? l.month_kwh : (p ? p.month.kwh : null),
      monthCost: l.month_cost || (p ? p.month.cost_text : "")
    }
  }

  // -------------------------------------------------------------- processes

  // Sampled every 2 s from /proc while the Processes tab is open, and not at
  // all otherwise. Signals and nice changes name the process by PID and start
  // time, so a PID reused since the last sample is never hit.
  property var procData: null
  property var procDetail: null

  Process {
    id: procWatch
    command: [root.procsCmd, "watch", "2"]
    running: root.processesViewOpen
    stdout: SplitParser {
      onRead: function(line) {
        try { root.procData = JSON.parse(line) } catch (e) {}
      }
    }
  }

  onProcessesViewOpenChanged: {
    if (!processesViewOpen) { procDetail = null; return }
    if (!procData) run([procsCmd, "once"], null, function(code, out) {
      if (!root.procData) try { root.procData = JSON.parse(out) } catch (e) {}
    })
  }

  function processSignal(proc, name, done) {
    run([procsCmd, "signal", String(proc.pid), String(proc.start), name], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) { r = { ok: false, error: "no answer" } }
      if (!r.ok) root.say("error", "Could not signal " + proc.name + " (" + proc.pid + "): " + r.error + ".")
      else if (name === "TERM" || name === "KILL" || name === "INT" || name === "HUP")
        root.say("info", proc.name + " (" + proc.pid + ") " + (r.ended ? "ended." : "was asked to end and is still running; Kill ends it at once."))
      else root.say("info", proc.name + " (" + proc.pid + ") " + (name === "STOP" ? "paused." : "resumed."))
      if (done) done(r)
    })
  }

  // The process and everything under it, deepest first.
  function processSignalTree(proc, name) {
    run([procsCmd, "signal-tree", String(proc.pid), String(proc.start), name], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) { r = { ok: false, error: "no answer" } }
      if (!r.ok) root.say("error", "Could not signal " + proc.name + " (" + proc.pid + "): " + r.error + ".")
      else root.say("info", proc.name + " (" + proc.pid + ") and " + r.children + " under it were asked to end"
                    + (r.skipped ? "; " + r.skipped + " had already gone or were not yours" : "") + ".")
    })
  }

  function processRenice(proc, value) {
    run([procsCmd, "renice", String(proc.pid), String(proc.start), String(value)], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) { r = { ok: false, error: "no answer" } }
      if (!r.ok) root.say("error", "Could not change the priority of " + proc.name + ": " + r.error + ".")
    })
  }

  function processDetail(proc) {
    procDetail = { pid: proc.pid, loading: true }
    run([procsCmd, "detail", String(proc.pid)], null, function(code, out) {
      try { var r = JSON.parse(out); if (r.ok && root.procDetail && root.procDetail.pid === r.pid) root.procDetail = r } catch (e) {}
    })
  }

  // ------------------------------------------------------------------ ports

  // Scanned every 3 s while the Ports tab is open. With `portWatch` on, once a
  // minute in the background too, to tell you when a dev server of yours
  // becomes reachable from the network (bound to 0.0.0.0 or a LAN address).
  // The scan as it came, and with your dev rules on top (Settings, or the
  // dev button on a port row).
  property var portRaw: null
  readonly property var devRules: ({ ports: String(settings.devPorts || ""), dev: String(settings.devPrograms || ""),
                                     notDev: String(settings.notDevPrograms || "") })
  readonly property var portData: portRaw ? Model.withDevRules(portRaw, devRules) : null
  function takePorts(d) {
    portRaw = d
    checkExposure(Model.withDevRules(d, devRules).listeners || [])
  }
  function setDevProgram(program, dev) {
    if (!program) return
    updateBarSettings(Model.toggleDevProgram(devRules, program, dev))
    say("info", program + (dev ? " now counts as a dev server, on any port." : " no longer counts as a dev server."))
  }
  property var exposedKeys: ({})
  property bool exposedSeeded: false

  function scanPorts() {
    if (portScan.running) return
    portScan.running = true
  }

  Process {
    id: portScan
    command: [root.portsCmd, "scan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var d
        try { d = JSON.parse(text) } catch (e) { return }
        root.takePorts(d)
      }
    }
  }

  function checkExposure(listeners) {
    var now = {}
    for (var i = 0; i < listeners.length; i++) {
      var r = listeners[i]
      if (r.dev && r.mine && Model.portExposed(r)) now[r.port + "/" + r.proto] = r
    }
    if (exposedSeeded && portWatch) {
      for (var key in now) {
        if (exposedKeys[key]) continue
        var p = now[key]
        notify("Port " + p.port + " is open to the network", (p.stack || p.name) + (p.project ? " in " + p.project : "")
               + " listens on " + p.addresses.join(", ") + ": other machines on this network can reach it.", "normal", "network-wired")
      }
    }
    exposedKeys = now
    exposedSeeded = true
  }

  Timer {
    interval: root.portsViewOpen ? 3000 : 20000
    repeat: true
    // In the background the sampler scans; this only stands in while the
    // energy meter (and so the sampler) is off.
    running: root.portsViewOpen || (root.portsBackground && !root.energyMeterEnabled)
    triggeredOnStart: true
    onTriggered: root.scanPorts()
  }

  function portSignal(row, name) {
    if (!row.pid) return
    processSignal({ pid: row.pid, start: row.start, name: (row.stack || row.process) + " on " + row.port }, name, function() { root.scanPorts() })
  }

  function portStopContainer(row) {
    if (!row.container) return
    run([portsCmd, "stop-container", row.container.id], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) { r = { ok: false, error: "no answer" } }
      root.say(r.ok ? "info" : "error", r.ok ? "Stopped the container " + row.container.name + "." : "Could not stop " + row.container.name + ": " + r.error + ".")
      root.scanPorts()
    })
  }

  function openTerminalIn(path) {
    if (!path) return
    closePanel()
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path])
  }

  // ---------------------------------------------------------------- plugins

  // Installed plugins, the marketplace (cached; the first download takes a
  // while), which git plugins have updates, and the running change. Changes
  // run detached through `omarchy plugin`, because its rescan closes every
  // panel; the job writes its progress to a file this follows.
  property var pluginLocal: null
  property var pluginCatalog: []
  property bool catalogLoading: false
  property bool catalogOffline: false
  property var pluginUpdates: null
  property var pluginThumbs: ({})
  property var pluginStats: ({})
  property var pluginJob: null
  readonly property string jobPath: (Quickshell.env("XDG_RUNTIME_DIR") || cacheDir) + "/omnisystem-center/job.json"

  function refreshPlugins(force) {
    run([pluginsCmd, "local"], null, function(code, out) {
      try { root.pluginLocal = JSON.parse(out) } catch (e) {}
    })
    if (force || pluginCatalog.length === 0) {
      catalogLoading = true
      run(force ? [pluginsCmd, "catalog", "--refresh"] : [pluginsCmd, "catalog"], null, function(code, out) {
        root.catalogLoading = false
        try { var d = JSON.parse(out); root.pluginCatalog = d.plugins || []; root.catalogOffline = !!d.offline } catch (e) {}
      })
    }
    run(force ? [pluginsCmd, "stats", "--refresh"] : [pluginsCmd, "stats"], null, function(code, out) {
      try { root.pluginStats = JSON.parse(out) } catch (e) {}
    })
    run(force ? [pluginsCmd, "updates", "--refresh"] : [pluginsCmd, "updates"], null, function(code, out) {
      try { root.pluginUpdates = JSON.parse(out) } catch (e) {}
    })
  }

  onPluginsViewOpenChanged: if (pluginsViewOpen) { refreshPlugins(false); jobFile.reload() }

  property bool thumbsRunning: false
  function requestThumbs(ids) {
    var want = ids.filter(function(id) { return root.pluginThumbs[id] === undefined })
    if (!want.length || thumbsRunning) return
    thumbsRunning = true
    run([pluginsCmd, "thumbs"].concat(want.slice(0, 30)), null, function(code, out) {
      root.thumbsRunning = false
      var got = {}
      try { got = JSON.parse(out) } catch (e) {}
      var next = Object.assign({}, root.pluginThumbs)
      for (var i = 0; i < want.length && i < 30; i++) next[want[i]] = got[want[i]] || ""
      root.pluginThumbs = next
    })
  }

  // `pin`: install exactly this (reviewed) commit; empty installs the newest.
  function runPluginJob(action, id, repo, pin) {
    if (pluginJob && pluginJob.state === "running") { say("error", "Another plugin change is still running."); return }
    pluginJob = { action: action, id: id, state: "running", log: "", started: Date.now() }
    Quickshell.execDetached([pluginsCmd, "job", action, id].concat(repo ? [repo] : []).concat(repo && pin ? [pin] : []))
    jobPoll.restart()
  }

  FileView {
    id: jobFile
    path: root.jobPath
    printErrors: false
    onLoaded: {
      var d
      try { d = JSON.parse(text()) } catch (e) { return }
      var was = root.pluginJob ? root.pluginJob.state : ""
      // A change that ended a while ago is history, not news.
      if (was !== "running" && d.state !== "running" && d.finished && Date.now() - d.finished > 120000) return
      root.pluginJob = d
      if (d.state !== "running" && was === "running") root.refreshPlugins(false)
    }
  }

  Timer {
    id: jobPoll
    interval: 800
    repeat: true
    running: !!root.pluginJob && root.pluginJob.state === "running"
    onTriggered: jobFile.reload()
  }

  function clearPluginJob() { pluginJob = null }

  // Another plugin's bar settings, and where widgets sit in the bar, through
  // `omarchy bar` (which leaves open panels alone).
  function setPluginSetting(id, key, value) {
    run(["omarchy", "bar", "set", id, key, JSON.stringify(value), "--json"], null, function(code, out, err) {
      if (code !== 0) root.say("error", "Could not set " + key + " on " + id + ": " + String(err || out).trim())
      root.refreshPluginsLocal()
    })
  }

  function moveBarWidget(id, section, index) {
    run(["omarchy", "bar", "move", id, "--section", section, "--index", String(Math.max(0, index))], null, function(code, out, err) {
      if (code !== 0) root.say("error", "Could not move " + id + ": " + String(err || out).trim())
      root.refreshPluginsLocal()
    })
  }

  function putBarWidget(id, section) {
    run(["omarchy", "bar", "put", id, "--section", section], null, function(code, out, err) {
      if (code !== 0) root.say("error", "Could not put " + id + " in the bar: " + String(err || out).trim())
      root.refreshPluginsLocal()
    })
  }

  // What an update would bring (commits and files), asked of GitHub on demand.
  property var pluginChanges: ({})
  function loadPluginChanges(id) {
    var next = Object.assign({}, pluginChanges)
    next[id] = { loading: true }
    pluginChanges = next
    run([pluginsCmd, "changes", id], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) { r = { ok: false, error: "no answer" } }
      var after = Object.assign({}, root.pluginChanges)
      after[id] = r
      root.pluginChanges = after
    })
  }

  function refreshPluginsLocal() {
    run([pluginsCmd, "local"], null, function(code, out) {
      try { root.pluginLocal = JSON.parse(out) } catch (e) {}
    })
  }

  // A plugin's preview, enlarged over the panel: the local preview.png for an
  // installed plugin that ships one, else the marketplace's full-size image.
  property var lightbox: null

  function openPreview(id, title, localFile) {
    if (localFile) { lightbox = { title: title, file: localFile }; return }
    lightbox = { title: title, file: pluginThumbs[id] || "", loading: true }
    run([pluginsCmd, "preview", id], null, function(code, out) {
      var r = {}
      try { r = JSON.parse(out) } catch (e) {}
      if (root.lightbox && root.lightbox.title === title)
        root.lightbox = { title: title, file: r.file || root.lightbox.file, loading: false }
    })
  }

  function closePreview() { lightbox = null }

  // ---------------------------------------------------------------- IPC

  function statusJson() {
    return JSON.stringify({
      battery: hasBattery ? {
        level: level, state: mode, onBattery: onBattery, watts: Math.round(watts * 10) / 10,
        time: timeText, health: sysfsBattery.health, cycles: sysfsBattery.cycles,
        temperature: temperature
      } : null,
      critical: criticalPending ? { action: criticalAction, secondsLeft: criticalRemaining } : null,
      energy: energyMeterEnabled ? energyJson() : null,
      chargeLimit: { backend: backend.kind, enabled: store.care.enabled, limit: store.care.limit, topUp: topUp, heatHolding: store.heatHolding },
      profile: activeProfile,
      keepAwake: keepAwake,
      sleepTimer: timerActive ? { action: store.timer.action, secondsLeft: timerLeft } : null,
      lidHold: lidHoldOn,
      gadgets: gadgets.map(function(g) { return { name: g.name, kind: g.kind, level: g.level, charging: g.charging, offline: !!g.offline } })
    })
  }

  IpcHandler {
    target: "omnisystem-center"

    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function toggle(): void { root.togglePanel() }
    function show(tab: string): void { root.showTab(tab) }
    function togglePercentage(): void { root.togglePercentage() }
    function cycleLabel(): string { root.cycleBarLabel(); return root.barLabelMode }
    function status(): string { return root.statusJson() }
    function action(key: string): string { return root.runPowerAction(key) ? "ok" : "unavailable" }
    function sleepTimer(minutes: string, action: string): string {
      if (minutes === "off" || minutes === "0") { root.cancelSleepTimer(); return "off" }
      root.startSleepTimer(Number(minutes), action || "suspend")
      return root.store.timer ? root.store.timer.action + " in " + root.store.timer.minutes + "m" : "error"
    }
    function cancelTimer(): string { root.cancelSleepTimer(); return "off" }
    function keepAwake(mode: string): string {
      root.setKeepAwake(mode === "toggle" ? !root.keepAwake : mode === "on")
      return root.keepAwake ? "on" : "off"
    }
    function profile(name: string): string {
      if (root.profiles.indexOf(name) < 0) return "unknown profile: " + name
      root.setProfile(name)
      return name
    }
    function topUp(): string { root.startTopUp(); return "charging to 100% once" }
    function energy(): string { return JSON.stringify(root.energyJson()) }
    function energySettings(): void { root.energySettingsRequested = true; root.showTab("energy") }
    function energyPeriod(period: string): string {
      if (["day", "week", "month", "year", "custom"].indexOf(period) < 0) return "unknown period: " + period
      root.setEnergyPeriod(period)
      root.showTab("energy")
      return period
    }
    function report(): void { root.exportReport(false) }
  }

  // The built-in widget's target, so existing bindings keep working.
  IpcHandler {
    target: "omarchy.power"

    function open(): void { root.openPanel() }
    function close(): void { root.closePanel() }
    function show(): void { root.openPanel() }
    function hide(): void { root.closePanel() }
    function toggle(): void { root.togglePanel() }
    function togglePercentage(): void { root.togglePercentage() }
  }

  Component.onCompleted: {
    run(["mkdir", "-p", stateDir, cacheDir], null, function() { stateFile.path = root.stateDir + "/state.json" })
    probe()
    probePowerActions()
    refreshProfiles()
    refreshIdle()
    refreshBatteryInfo()
    energyProc.running = energyMeterEnabled
  }
}

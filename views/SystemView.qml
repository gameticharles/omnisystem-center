import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// CPU, memory, temperatures and power, sampled every two seconds only while
// this tab is open, then what the machine is: processor, memory and storage,
// model and firmware, graphics, network, audio and USB. A reading this machine
// does not offer is left out. Click any fact to copy it.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property var dev: s.deviceInfo
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim

  function copy(text) { s.copyText(text, "“" + (text.length > 40 ? text.slice(0, 40) + "…" : text) + "”") }

  spacing: Style.space(14)

  // Colours from the theme: the CPU first (the accent), memory, then one per
  // GPU, the same GPU keeping its colour on both GPU graphs.
  readonly property var colors: Model.seriesColors(panel.palette, 2 + s.gpus.length, String(Color.background))
  function gpuColor(id) {
    for (var i = 0; i < s.gpus.length; i++) if (s.gpus[i].id === id) return colors[2 + i]
    return fg
  }
  function gpuById(id) {
    for (var i = 0; i < s.gpus.length; i++) if (s.gpus[i].id === id) return s.gpus[i]
    return null
  }
  readonly property var tempLines: {
    var out = []
    if (s.tempSeries.some(function(v) { return v > 0 }))
      out.push({ name: "CPU", color: colors[0], series: s.tempSeries, value: s.cpuTemp > 0 ? Math.round(s.cpuTemp) + "°" : "" })
    for (var id in s.gpuTempSeries) {
      var g = gpuById(id)
      if (!g) continue
      out.push({ name: Model.gpuShortName(g) + (g.tempShared ? " (CPU die)" : ""), color: gpuColor(id), series: s.gpuTempSeries[id],
                 value: typeof g.temp === "number" ? Math.round(g.temp) + "°" : (g.state === "asleep" ? "asleep" : "") })
    }
    return out
  }
  readonly property var gpuLines: {
    var out = []
    for (var id in s.gpuBusySeries) {
      var g = gpuById(id)
      if (!g) continue
      out.push({ name: Model.gpuShortName(g), color: gpuColor(id), series: s.gpuBusySeries[id],
                 value: typeof g.busy === "number" ? g.busy + "%" : (g.state === "asleep" ? "asleep" : "") })
    }
    return out
  }

  Section {
    title: "SYSTEM"
    trailing: view.s.uptime > 0 ? "UP " + Model.formatUptime(view.s.uptime).toUpperCase() : ""
    separator: false
    foreground: view.fg
    fontFamily: view.ff

    Grid {
      id: grid
      width: parent.width
      columns: 2
      columnSpacing: Style.space(14)
      rowSpacing: Style.space(14)
      readonly property real cell: (width - columnSpacing) / 2

      SeriesTile {
        foreground: view.fg
        lineColor: view.colors[0]
        fontFamily: view.ff
        slots: view.s.seriesLength
        width: grid.cell
        label: "CPU"
        value: view.s.cpuPercent >= 0 ? view.s.cpuPercent + "%" + (view.s.cpuFreq ? " · " + Model.formatMHz(view.s.cpuFreq.avg) : "") : ""
        series: view.s.cpuSeries
      }
      SeriesTile {
        foreground: view.fg
        lineColor: view.colors[1]
        fontFamily: view.ff
        slots: view.s.seriesLength
        width: grid.cell
        label: "Memory"
        value: view.s.memory.pct >= 0 ? Model.formatBytes(view.s.memory.used) + " · " + view.s.memory.pct + "%" : ""
        series: view.s.memSeries
      }
      MultiSeriesTile {
        foreground: view.fg
        fontFamily: view.ff
        slots: view.s.seriesLength
        width: grid.cell
        label: "Temperatures"
        lines: view.tempLines
        floor: 20
        ceiling: 100
        emptyText: "No sensor reports one"
      }
      MultiSeriesTile {
        foreground: view.fg
        fontFamily: view.ff
        slots: view.s.seriesLength
        width: grid.cell
        label: "GPU usage"
        lines: view.gpuLines
        emptyText: view.s.energyMeterEnabled ? "No GPU reports its usage" : "Needs the energy meter"
      }
      SeriesTile {
        foreground: view.fg
        lineColor: view.colors[0]
        fontFamily: view.ff
        slots: view.s.seriesLength
        width: grid.cell
        shown: view.s.packageWatts >= 0
        label: "CPU power"
        value: view.s.packageWatts >= 0 ? view.s.packageWatts + " W" : ""
        series: view.s.packageSeries
        ceiling: 60
      }
      SeriesTile {
        foreground: view.fg
        lineColor: view.colors[1]
        fontFamily: view.ff
        slots: view.s.seriesLength
        width: grid.cell
        shown: view.s.discharging
        label: "Battery draw"
        value: Model.formatWatts(view.s.watts)
        series: view.s.wattSeries
        ceiling: 60
      }
    }

    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.space(14)
      rowSpacing: Style.space(10)
      readonly property real cell: (width - columnSpacing) / 2

      Stat {
        width: parent.cell
        label: "Load 1 · 5 · 15"
        value: view.s.load.length === 3 ? view.s.load.map(function(x) { return x.toFixed(2) }).join(" · ") : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Fastest core"
        value: view.s.cpuFreq ? Model.formatMHz(view.s.cpuFreq.max) : ""
        foreground: view.fg
        fontFamily: view.ff
      }
    }

    // Disk space as a bar: used of the root file system.
    Column {
      visible: !!view.s.disk && view.s.disk.total > 0
      width: parent.width
      spacing: Style.space(4)
      readonly property real used: view.s.disk ? 1 - view.s.disk.free / Math.max(1, view.s.disk.total) : 0
      readonly property bool tight: view.s.disk && view.s.disk.free / Math.max(1, view.s.disk.total) < 0.1

      Item {
        width: parent.width
        implicitHeight: diskLabel.implicitHeight
        Text {
          id: diskLabel
          textFormat: Text.PlainText
          text: "DISK"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: view.s.disk ? Model.formatGB(view.s.disk.free) + " free of " + Model.formatGB(view.s.disk.total) : ""
          color: parent.parent.tight ? Color.urgent : view.fg
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
        }
      }
      Meter {
        width: parent.width
        implicitHeight: Style.space(6)
        value: parent.used
        color: parent.tight ? Color.urgent : view.colors[0]
      }
    }

    // Swap as bars like the disk: one per device (a swap file, zram).
    Repeater {
      model: view.s.swaps.length
      Column {
        required property int index
        readonly property var sw: view.s.swaps[index] || ({ size: 0, used: 0, kind: "", name: "" })
        readonly property real used: sw.size > 0 ? sw.used / sw.size : 0
        width: parent.width
        spacing: Style.space(4)

        Item {
          width: parent.width
          implicitHeight: swapLabel.implicitHeight
          Text {
            id: swapLabel
            textFormat: Text.PlainText
            text: parent.parent.sw.kind === "zram" ? "ZRAM" : "SWAP" + (view.s.swaps.length > 1 ? " · " + parent.parent.sw.name : "")
            color: view.dim
            font.family: view.ff
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }
          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: Model.formatBytes(parent.parent.sw.used) + " used of " + Model.formatBytes(parent.parent.sw.size)
            color: parent.parent.used > 0.8 ? Color.urgent : view.fg
            font.family: view.ff
            font.pixelSize: Style.font.bodySmall
          }
        }
        Meter {
          width: parent.width
          implicitHeight: Style.space(6)
          value: parent.used
          color: parent.used > 0.8 ? Color.urgent : view.colors[1]
        }
      }
    }
  }

  // ------------------------------------------------------ temperatures, fans

  Section {
    visible: view.s.temps.length > 0 || view.s.fans.length > 0
    title: "SENSORS"
    trailing: view.s.fans.length ? view.s.fans.length + (view.s.fans.length === 1 ? " FAN" : " FANS") : ""
    foreground: view.fg
    fontFamily: view.ff

    Repeater {
      model: view.s.temps
      InfoRow {
        required property var modelData
        label: modelData.group + (modelData.label && modelData.label !== modelData.group ? " · " + modelData.label : "")
        value: Math.round(modelData.c) + " °C"
        detail: modelData.detail
        valueColor: modelData.c >= 90 ? Color.urgent : view.fg
        foreground: view.fg
        fontFamily: view.ff
        onCopyRequested: function(t) { view.copy(label + " " + t) }
      }
    }
    Repeater {
      model: view.s.fans
      InfoRow {
        required property var modelData
        label: modelData.label
        value: modelData.rpm + " rpm"
        foreground: view.fg
        fontFamily: view.ff
        onCopyRequested: function(t) { view.copy(t) }
      }
    }
  }

  // ---------------------------------------------------------------- the CPU

  Section {
    visible: !!view.dev
    title: "PROCESSOR"
    trailing: view.dev && view.dev.cpu.cores ? view.dev.cpu.cores + " CORES · " + view.dev.cpu.threads + " THREADS" : ""
    foreground: view.fg
    fontFamily: view.ff

    InfoRow { label: "Model"; value: view.dev ? view.dev.cpu.model : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) } }
    InfoRow {
      label: "Clock range"
      value: view.dev && view.dev.cpu.minMHz ? Model.formatMHz(view.dev.cpu.minMHz) + " – " + Model.formatMHz(view.dev.cpu.maxMHz) : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
    InfoRow { label: "Cache"; value: view.dev ? Model.cacheText(view.dev.cpu.caches) : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) } }
    InfoRow {
      label: "Scaling"
      value: view.dev ? [view.dev.cpu.driver, view.dev.cpu.governor].filter(function(x) { return x }).join(" · ") : ""
      detail: view.dev && view.dev.cpu.epp ? "energy preference: " + view.dev.cpu.epp.replace(/_/g, " ") : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
  }

  // ------------------------------------------------------ memory and storage

  Section {
    visible: !!view.dev
    title: "MEMORY AND STORAGE"
    foreground: view.fg
    fontFamily: view.ff

    InfoRow {
      label: "Memory"
      value: view.dev && view.dev.memory.total ? Model.formatBytes(view.dev.memory.total) : ""
      detail: view.s.memory.total ? Model.formatBytes(view.s.memory.total - view.s.memory.used) + " available" : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
    InfoRow {
      label: "Disk"
      value: view.dev ? Model.diskText(view.dev.storage) : ""
      detail: view.dev && view.dev.storage.kind ? view.dev.storage.kind : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
    InfoRow {
      label: "Root file system"
      value: view.dev && view.dev.storage.fs ? view.dev.storage.fs + (view.dev.storage.encrypted ? " · encrypted" : "") : ""
      detail: view.s.disk ? Model.formatBytes(view.s.disk.used) + " used" : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
  }

  // ------------------------------------------------------ model and firmware

  Section {
    visible: !!view.dev
    title: "DEVICE"
    trailing: view.dev && view.dev.machine.chassis ? view.dev.machine.chassis.toUpperCase() : ""
    foreground: view.fg
    fontFamily: view.ff

    InfoRow {
      label: "Model"
      value: view.dev ? Model.machineName(view.dev.machine) : ""
      detail: view.dev ? [view.dev.machine.family, view.dev.machine.version].filter(function(x) { return x }).join(" · ") : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
    InfoRow { label: "Board"; value: view.dev ? view.dev.machine.board : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) } }
    InfoRow {
      label: "Firmware"
      value: view.dev ? view.dev.machine.bios : ""
      detail: view.dev ? [view.dev.machine.biosDate, view.dev.machine.ec ? "EC " + view.dev.machine.ec : ""].filter(function(x) { return x }).join(" · ") : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
    InfoRow { label: "System"; value: view.dev ? Model.osText(view.dev.os) : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) } }
    InfoRow { label: "Kernel"; value: view.dev ? view.dev.os.kernel : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) } }
    InfoRow {
      label: "Battery"
      value: view.dev && view.dev.battery ? [view.dev.battery.maker, view.dev.battery.model].filter(function(x) { return x }).join(" ") : ""
      detail: view.dev && view.dev.battery ? view.dev.battery.chemistry : ""
      foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.copy(t) }
    }
  }

  // --------------------------------------------------------------- hardware

  Section {
    visible: !!view.dev && (view.dev.pci.length > 0 || view.dev.usb.length > 0)
    title: "HARDWARE"
    foreground: view.fg
    fontFamily: view.ff

    Repeater {
      model: view.dev ? view.dev.pci : []
      InfoRow {
        required property var modelData
        label: modelData.kind
        value: modelData.name
        detail: [Model.gpuMemoryText(modelData.memory), modelData.memory && modelData.memory.driver ? "" : modelData.driver,
                 modelData.asleep ? "asleep" : ""].filter(function(x) { return x }).join(" · ")
        foreground: view.fg
        fontFamily: view.ff
        onCopyRequested: function(t) { view.copy(t) }
      }
    }
    Repeater {
      model: view.dev ? view.dev.usb : []
      InfoRow {
        required property var modelData
        label: "USB"
        value: modelData.name
        detail: modelData.speed ? (modelData.speed >= 5000 ? (modelData.speed / 1000) + " Gb/s" : modelData.speed + " Mb/s") : ""
        foreground: view.fg
        fontFamily: view.ff
        onCopyRequested: function(t) { view.copy(t) }
      }
    }
  }

  Row {
    spacing: Style.space(6)
    Button {
      visible: !!view.dev
      text: "Copy all"
      iconText: "󰆏"
      fontSize: Style.font.caption
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      tooltipText: "Everything above as text, for a bug report or a forum post (no serial numbers)"
      onClicked: view.s.copyText(Model.deviceSummary(view.dev, { uptime: view.s.uptime }), "the system information")
    }
    Button {
      text: "Refresh"
      iconText: "󰑐"
      fontSize: Style.font.caption
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      tooltipText: "Read the hardware again (after plugging something in)"
      onClicked: view.s.refreshDevice()
    }
    Button {
      text: "btop"
      iconText: "󰄪"
      fontSize: Style.font.caption
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      tooltipText: "Open the full system monitor in a terminal"
      onClicked: view.s.openSystemMonitor()
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    color: view.dim
    font.family: view.ff
    font.pixelSize: Style.font.caption
    text: view.s.discharging && view.s.cpuPercent >= 40
      ? "The CPU is busy and the laptop is on battery: the power saver profile, or closing what runs in the background, stretches the charge."
      : "Sampled every 2 s while this tab is open; nothing runs in the background. Click any fact to copy it."
  }
}

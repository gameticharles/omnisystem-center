import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// The energy meter: what the machine draws now, what it used and cost per
// day, week, month and year, and its settings. Measured and estimated parts
// are always told apart; untracked time is never shown as zero use.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim

  readonly property var pd: s.energyPanel
  readonly property var live: s.energyLive
  readonly property var now: live && typeof live.watts === "number" ? live : (pd ? pd.now : null)
  readonly property var settings: pd ? pd.settings : null
  readonly property var status: pd ? pd.status : null
  readonly property bool priced: !!settings && settings.tariff > 0
  readonly property var today: pd ? pd.summary.today : null
  readonly property var month: pd ? pd.summary.month : null
  property bool settingsOpen: false

  spacing: Style.space(14)

  Connections {
    target: view.s
    function onEnergySettingsRequestedChanged() {
      if (view.s.energySettingsRequested) { view.settingsOpen = true; view.s.energySettingsRequested = false }
    }
  }
  Component.onCompleted: if (s.energySettingsRequested) { settingsOpen = true; s.energySettingsRequested = false }

  // --------------------------------------------------------------------- now

  Section {
    title: "NOW"
    trailing: view.now && view.now.source === "battery" ? "ON BATTERY" : (view.now ? "ON AC" : "")
    separator: false
    foreground: view.fg
    fontFamily: view.ff

    Item {
      width: parent.width
      implicitHeight: Math.max(bigWatts.implicitHeight, nowSide.implicitHeight)

      Text {
        id: bigWatts
        textFormat: Text.PlainText
        text: view.now && typeof view.now.watts === "number" ? Model.formatWatts(view.now.watts) || "0 W" : "–"
        color: view.s.energyHigh ? Color.urgent : view.fg
        font.family: view.ff
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }
      Column {
        id: nowSide
        anchors.left: bigWatts.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: bigWatts.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.body
          text: !view.now ? (view.live && view.live.untracked ? "Not recorded right now" : "Waiting for the first reading")
              : view.now.source === "battery" ? "at the socket, measured at the battery"
              : "at the socket, mean of the last " + Math.round(view.now.interval_s || 10) + " s"
        }
        Text {
          width: parent.width
          visible: text !== ""
          textFormat: Text.PlainText
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          text: {
            var parts = []
            if (view.now) parts.push(Model.percentText(view.now.measured_share, "measured"))
            for (var i = 0; i < view.s.gpus.length; i++)
              if (!view.s.gpus[i].integrated) parts.push(Model.gpuLine(view.s.gpus[i]))
            return parts.filter(function(x) { return x }).join("  ·  ")
          }
        }
      }
    }

    // CPU / GPU / rest, summing to the total.
    Column {
      readonly property var shares: Model.drawShares(view.now)
      visible: shares !== null
      width: parent.width
      spacing: Style.space(6)

      Row {
        width: parent.width
        height: Style.space(8)
        Rectangle { width: parent.width * (parent.parent.shares ? parent.parent.shares.cpu : 0); height: parent.height; color: view.fg; radius: 2 }
        Rectangle { width: parent.width * (parent.parent.shares ? parent.parent.shares.gpu : 0); height: parent.height; color: Color.accent; radius: 2 }
        Rectangle { width: parent.width * (parent.parent.shares ? parent.parent.shares.rest : 0); height: parent.height; color: Util.alpha(view.fg, 0.3); radius: 2 }
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        text: !view.now ? "" : "CPU " + Model.formatWatts(view.now.cpu_w) + "  ·  GPU " + (Model.formatWatts(view.now.gpu_w) || "0 W")
              + "  ·  rest " + Model.formatWatts(view.now.rest_w) + (view.now.rest_measured ? "" : " (estimated)")
      }
    }

    Text {
      width: parent.width
      visible: text !== ""
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
      text: view.live && view.live.untracked ? Model.untrackedText(view.live.untracked, view.s.onBattery) : ""
    }
    Row {
      visible: !!view.live && view.live.untracked === "cpu-counter-unreadable"
      spacing: Style.space(6)
      Button {
        text: "How to fix"
        iconText: "󰋗"
        fontSize: Style.font.caption
        bordered: true
        foreground: view.fg
        fontFamily: view.ff
        tooltipText: "A one-time, read-only rule for the CPU package counter: opens the guide"
        onClicked: { Qt.openUrlExternally(view.s.docsUrl + "/energy-meter.md"); view.s.closePanel() }
      }
    }

    Grid {
      width: parent.width
      columns: 2
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(10)
      readonly property real cell: (width - columnSpacing) / 2

      Stat {
        width: parent.cell
        label: "Today"
        value: view.today ? Model.formatKwh(view.today.kwh) + (view.today.cost_text ? "  ·  " + view.today.cost_text : "") : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "This month"
        value: view.month ? Model.formatKwh(view.month.kwh) + (view.month.cost_text ? "  ·  " + view.month.cost_text : "") : ""
        foreground: view.fg
        fontFamily: view.ff
      }
    }

    // This month against the budget, when one is set.
    Column {
      readonly property real budget: view.settings && view.settings.monthly_budget ? view.settings.monthly_budget : 0
      readonly property real spent: view.month && typeof view.month.cost === "number" ? view.month.cost : 0
      readonly property real share: budget > 0 ? spent / budget : 0
      readonly property color tone: share >= 1 ? Color.urgent : share >= 0.8 ? Model.actionColor("reboot", view.panel.palette, view.fg) : view.panel.palette.accent
      visible: view.priced && budget > 0
      width: parent.width
      spacing: Style.space(4)
      Item {
        width: parent.width
        implicitHeight: budgetLabel.implicitHeight
        Text {
          id: budgetLabel
          textFormat: Text.PlainText
          text: "MONTHLY BUDGET"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: (view.month ? view.month.cost_text || "0" : "0") + " of " + (view.pd ? view.pd.currency.symbol : "") + parent.parent.budget
                + "  ·  " + Math.round(parent.parent.share * 100) + "%"
          color: parent.parent.tone
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
      Meter {
        width: parent.width
        implicitHeight: Style.space(6)
        value: Math.min(1, parent.share)
        color: parent.tone
      }
    }

    Button {
      visible: !!view.settings && !view.priced
      text: "Set your electricity price"
      iconText: "󰄉"
      fontSize: Style.font.caption
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      tooltipText: "Costs appear once a price is set, for all history too"
      onClicked: view.settingsOpen = true
    }
  }

  // ------------------------------------------------------------ the periods

  Section {
    title: "HISTORY"
    trailing: view.pd && view.pd.report.total ? Model.formatKwh(view.pd.report.total.kwh)
              + (view.pd.report.total.cost_text ? " · " + view.pd.report.total.cost_text : "") : ""
    foreground: view.fg
    fontFamily: view.ff

    Row {
      id: periods
      width: parent.width
      spacing: Style.space(6)
      readonly property var options: [
        { value: "day", label: "Day" }, { value: "week", label: "Week" }, { value: "month", label: "Month" },
        { value: "year", label: "Year" }, { value: "custom", label: view.s.energyCustomDays + " d" }
      ]
      readonly property real cell: (width - spacing * (options.length - 1)) / options.length

      Repeater {
        model: periods.options
        Button {
          required property var modelData
          width: periods.cell
          text: modelData.label
          fontSize: Style.font.caption
          bordered: true
          active: view.s.energyPeriod === modelData.value
          foreground: view.fg
          fontFamily: view.ff
          tooltipText: modelData.value === "custom" ? "A number of days of your choice; scroll here to change it"
                       : modelData.value === "day" ? "Today's draw, and the last 14 days"
                       : modelData.value === "week" ? "The last 7 days, and the last 8 weeks"
                       : modelData.value === "month" ? "The last 30 days, and the last 12 months" : "Every day on record, and every year"
          onClicked: view.s.setEnergyPeriod(modelData.value)
          WheelHandler {
            enabled: modelData.value === "custom"
            onWheel: function(event) {
              var step = event.angleDelta.y > 0 ? 1 : -1
              view.s.setEnergyPeriod("custom", view.s.energyCustomDays + step * (view.s.energyCustomDays >= 30 ? 5 : 1))
            }
          }
        }
      }
    }

    // The graph follows the period; hover for a reading.
    ChartCard {
      foreground: view.fg
      Item {
        id: chartBox
        width: parent.width
        height: Style.space(110)
        readonly property var chart: view.pd ? view.pd.chart : null
        readonly property var points: chart ? chart.points : []
        readonly property real start: chart && chart.start ? chart.start : 0
        readonly property real end: chart && chart.end ? chart.end : 1
        readonly property real peak: Model.energyPeak(points)
        property int hover: -1

        Graph {
          id: energyGraph
          anchors.fill: parent
          anchors.bottomMargin: Style.space(14)
          color: view.panel.palette.accent
          segments: Model.energySegments(chartBox.points, chartBox.start, chartBox.end, width, height, chartBox.peak)
        }
        Text {
          anchors.right: parent.right
          anchors.top: parent.top
          visible: chartBox.points.length > 0
          textFormat: Text.PlainText
          text: chartBox.peak + " W"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: chartBox.chart && chartBox.points.length ? Model.energyTimeLabel(chartBox.start, chartBox.chart.days) : ""
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: chartBox.points.length ? "now" : ""
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: !chartBox.points.length || chartBox.points.every(function(p) { return p[1] === null })
          anchors.centerIn: energyGraph
          textFormat: Text.PlainText
          text: view.pd ? "Nothing recorded in this period yet" : "Loading…"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          visible: chartBox.hover >= 0
          x: chartBox.hover >= 0 ? (chartBox.points[chartBox.hover][0] - chartBox.start) / Math.max(1, chartBox.end - chartBox.start) * energyGraph.width : 0
          y: 0
          width: 1
          height: energyGraph.height
          color: Util.alpha(view.fg, 0.5)
        }
        Rectangle {
          visible: chartBox.hover >= 0
          color: Util.alpha(Color.background, 0.85)
          radius: Style.space(4)
          width: readout.implicitWidth + Style.space(12)
          height: readout.implicitHeight + Style.space(6)
          y: 0
          x: {
            if (chartBox.hover < 0) return 0
            var px = (chartBox.points[chartBox.hover][0] - chartBox.start) / Math.max(1, chartBox.end - chartBox.start) * energyGraph.width
            return Math.max(0, Math.min(chartBox.width - width, px + Style.space(6)))
          }
          Text {
            id: readout
            anchors.centerIn: parent
            textFormat: Text.PlainText
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.caption
            text: {
              if (chartBox.hover < 0) return ""
              var p = chartBox.points[chartBox.hover]
              return Model.energyTimeLabel(p[0], chartBox.chart.days) + "  ·  " + (p[1] === null ? "not tracked" : Model.formatWatts(p[1]) || "0 W")
            }
          }
        }
        MouseArea {
          anchors.fill: energyGraph
          hoverEnabled: true
          onPositionChanged: function(mouse) { chartBox.hover = Model.nearestPoint(chartBox.points, chartBox.start, chartBox.end, width, mouse.x) }
          onExited: chartBox.hover = -1
        }
      }
    }

    // The breakdown: one row per bucket.
    Column {
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: headLabel.implicitHeight
        Text { id: headLabel; text: "PERIOD"; color: view.dim; font.family: view.ff; font.pixelSize: Style.font.caption; font.bold: true }
        Text { x: parent.width * 0.38; text: "KWH"; color: view.dim; font.family: view.ff; font.pixelSize: Style.font.caption; font.bold: true }
        Text { x: parent.width * 0.56; visible: view.priced; text: "COST"; color: view.dim; font.family: view.ff; font.pixelSize: Style.font.caption; font.bold: true }
        Text { anchors.right: parent.right; text: "AVG · TRACKED"; color: view.dim; font.family: view.ff; font.pixelSize: Style.font.caption; font.bold: true }
      }

      Repeater {
        model: view.pd ? view.pd.report.buckets.slice().reverse() : []
        Item {
          required property var modelData
          width: parent.width
          implicitHeight: rowLabel.implicitHeight + Style.space(2)
          opacity: modelData.before_history ? 0.45 : 1
          readonly property bool partial: !modelData.before_history && modelData.coverage < 0.95

          Text {
            id: rowLabel
            width: parent.width * 0.36
            textFormat: Text.PlainText
            text: modelData.label
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Text {
            x: parent.width * 0.38
            textFormat: Text.PlainText
            text: modelData.before_history ? "–" : modelData.kwh.toFixed(modelData.kwh >= 10 ? 1 : 3)
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            x: parent.width * 0.56
            visible: view.priced
            textFormat: Text.PlainText
            text: modelData.before_history ? "" : modelData.cost_text
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: modelData.before_history ? "before recording" :
                  (modelData.avg_w !== null ? Math.round(modelData.avg_w) + " W · " : "") + Math.round(modelData.coverage * 100) + "%"
            color: parent.partial ? view.dim : view.fg
            font.family: view.ff
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
          }
          PanelToolTip {
            visible: rowHover.containsMouse && !modelData.before_history && modelData.tracked_s > 0
            text: Model.percentText(modelData.measured_share, "measured") + "  ·  largest sample " + Math.round(modelData.max_w || 0) + " W"
                  + (modelData.battery_share > 0 ? "  ·  " + Math.round(modelData.battery_share * 100) + "% on battery" : "")
                  + "\n" + Model.formatDuration(modelData.tracked_s) + " tracked (" + Math.round(modelData.coverage * 100) + "% of the period)"
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
        text: "Averages are while tracked. A period the shell did not run through, or the machine slept, shows a lower tracked share rather than less energy."
      }

      Button {
        text: "Export CSV"
        iconText: "󰈛"
        tooltipText: "Every recorded day (energy, cost, tracked hours, averages) as a spreadsheet, saved to Downloads"
        bordered: true
        foreground: view.fg
        fontFamily: view.ff
        fontSize: Style.font.caption
        onClicked: view.s.exportEnergy()
      }
    }
  }

  // --------------------------------------------------------------- settings

  Section {
    title: "SETTINGS"
    trailing: view.settingsOpen ? "" : (view.settings ? (view.priced ? view.settings.tariff + " " + view.settings.currency + "/KWH" : "NO PRICE SET") : "")
    foreground: view.fg
    fontFamily: view.ff

    Button {
      visible: !view.settingsOpen
      text: "Price, estimate and sampling"
      iconText: "󰒓"
      fontSize: Style.font.caption
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      onClicked: view.settingsOpen = true
    }

    Column {
      id: form
      visible: view.settingsOpen && !!view.settings
      width: parent.width
      spacing: Style.space(10)

      function field(label, key, hint) { return { label: label, key: key, hint: hint } }
      function save() {
        var changes = {}
        for (var i = 0; i < fields.count; i++) {
          var f = fields.itemAt(i)
          if (f && f.edited) changes[f.key] = f.textValue
        }
        if (currency.value && currency.value !== view.settings.currency) changes.currency = currency.value
        if (decimals.value !== String(view.settings.cost_decimals)) changes.cost_decimals = decimals.value
        if (gpuSource.value !== view.settings.gpu_source) changes.gpu_source = gpuSource.value
        if (Object.keys(changes).length === 0) { view.settingsOpen = false; return }
        view.s.setEnergyConfig(changes, function(ok) {
          if (!ok) return
          var keys = Object.keys(changes)
          var history = keys.some(function(k) { return ["tariff", "currency", "currency_symbol", "cost_decimals", "baseline_w", "psu_efficiency"].indexOf(k) >= 0 })
          view.s.say("info", history ? "Saved. Every recorded day is repriced." : "Saved. Applies to new samples.")
          view.settingsOpen = false
        })
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
        text: "These reprice all history the moment you save: the price per kWh (the part of your bill that grows with use), the currency, and the two estimates."
      }

      SearchableDropdown {
        id: currency
        width: parent.width
        label: "Currency"
        value: view.settings ? view.settings.currency : ""
        options: view.pd ? view.pd.currencies : []
        foreground: view.fg
        fontFamily: view.ff
        onChanged: function(v) { currency.value = v }
      }

      Repeater {
        id: fields
        model: [
          form.field("Price per kWh", "tariff", "e.g. 1.94"),
          form.field("Currency symbol (empty: automatic)", "currency_symbol", "e.g. GH₵"),
          form.field("Rest of the machine (W, estimate)", "baseline_w", "memory, disk, screen, fans: on AC only"),
          form.field("Charger or power supply efficiency (0.5 – 1)", "psu_efficiency", "0.88 is typical for a laptop charger"),
          form.field("Monthly budget, in your currency (0 for none)", "monthly_budget", "a notification at 80% and at 100%")
        ]
        Column {
          required property var modelData
          readonly property string key: modelData.key
          readonly property string original: view.settings ? String(view.settings[modelData.key]) : ""
          readonly property bool edited: input.text !== original
          readonly property string textValue: input.text
          width: form.width
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            text: modelData.label
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: input
            width: parent.width
            text: parent.original
            placeholderText: modelData.hint
            foreground: view.fg
            onActiveFocusChanged: view.panel.textEditing = activeFocus
            onAccepted: form.save()
            Keys.onEscapePressed: view.settingsOpen = false
          }
        }
      }

      Row {
        spacing: Style.space(6)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Decimals"
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Repeater {
          id: decimalsRow
          model: ["auto", "0", "1", "2", "3"]
          Button {
            required property string modelData
            text: modelData
            fontSize: Style.font.caption
            bordered: true
            active: decimals.value === modelData
            foreground: view.fg
            fontFamily: view.ff
            onClicked: decimals.value = modelData
          }
        }
        QtObject { id: decimals; property string value: view.settings ? String(view.settings.cost_decimals) : "auto" }
      }

      // Calibrating the estimate with a wall meter or smart plug.
      Column {
        visible: !!view.now && view.now.source === "ac" && typeof view.now.cpu_dc_w === "number"
        width: parent.width
        spacing: Style.space(4)
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          text: "Have a wall meter or smart plug? Let the machine idle on AC, type what it reads, and the estimate is worked out from it."
        }
        Row {
          spacing: Style.space(6)
          TextField {
            id: metered
            width: Style.space(90)
            placeholderText: "watts"
            foreground: view.fg
            onActiveFocusChanged: view.panel.textEditing = activeFocus
          }
          Button {
            readonly property real result: view.now ? Model.calibratedBaseline(metered.text, view.settings ? view.settings.psu_efficiency : 0.88, view.now.cpu_dc_w, view.now.gpu_dc_w) : -1
            enabled: result >= 0
            text: result >= 0 ? "Use " + result + " W" : "Calibrate"
            fontSize: Style.font.caption
            bordered: true
            foreground: view.fg
            fontFamily: view.ff
            onClicked: view.s.setEnergyConfig({ baseline_w: result }, function(ok) { if (ok) view.s.say("info", "Estimate calibrated; history repriced.") })
          }
        }
      }

      PanelSeparator { foreground: view.fg }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
        text: "Sampling: applies to new samples. auto reads every discrete GPU; integrated graphics are part of the CPU figure. A GPU is only read while it is already awake."
      }
      Row {
        spacing: Style.space(6)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "GPU"
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Repeater {
          model: ["auto", "nvidia", "amdgpu", "intel", "off"]
          Button {
            required property string modelData
            text: modelData
            fontSize: Style.font.caption
            bordered: true
            active: gpuSource.value === modelData
            foreground: view.fg
            fontFamily: view.ff
            onClicked: gpuSource.value = modelData
          }
        }
        QtObject { id: gpuSource; property string value: view.settings ? view.settings.gpu_source : "auto" }
      }

      Row {
        spacing: Style.space(6)
        Button {
          text: "Save"
          iconText: "󰄬"
          fontSize: Style.font.caption
          bordered: true
          foreground: view.fg
          fontFamily: view.ff
          onClicked: form.save()
        }
        Button {
          text: "Cancel"
          fontSize: Style.font.caption
          bordered: true
          foreground: view.fg
          fontFamily: view.ff
          onClicked: view.settingsOpen = false
        }
      }
    }
  }

  // ------------------------------------------------------------- the sensors

  Text {
    width: parent.width
    visible: !!view.status
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    color: view.dim
    font.family: view.ff
    font.pixelSize: Style.font.caption
    text: {
      var st = view.status
      if (!st) return ""
      var parts = []
      if (st.battery.present) parts.push("Battery: measured on battery")
      parts.push("CPU: " + (st.cpu.zones.length ? "RAPL " + st.cpu.zones.join(", ") : st.cpu.root_only.length ? "counter root-only" : "no counter"))
      var g = (st.gpu.devices || []).map(function(d) {
        return d.vendor + (d.integrated ? " integrated (in the CPU figure)" : d.measured ? (d.awake ? " awake" : " asleep, 0 W") : " not read")
      })
      parts.push("GPU: " + (g.length ? g.join(", ") : st.gpu.reason))
      if (st.first_sample) parts.push("Recording since " + Model.energyTimeLabel(st.first_sample, 365))
      if (st.dropped.slept || st.dropped.counter_reset) parts.push((st.dropped.slept + st.dropped.counter_reset) + " intervals left out (sleep or counter reset)")
      return parts.join("  ·  ")
    }
  }
}

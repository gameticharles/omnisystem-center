import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// Battery care, shaped by what the hardware allows (Model.chargeLimitBackend):
// an exact limit with sailing, top-up, heat protection and calibration where
// the kernel or the SMC takes one; UPower's on/off limit where it does not;
// an unplug reminder where there is none. Then the warnings.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property var care: s.store.care
  readonly property var backend: s.backend
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim

  spacing: Style.space(14)

  // ------------------------------------------------------------ charge limit

  Section {
    title: "CHARGE LIMIT"
    trailing: ({ sysfs: "KERNEL", apple: "APPLE SMC", upower: "UPOWER", acer: "ACER HEALTH MODE", locked: "ROOT ONLY", none: "NOT SUPPORTED" })[view.backend.kind] || ""
    separator: false
    foreground: view.fg
    fontFamily: view.ff

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
      text: {
        switch (view.backend.kind) {
        case "sysfs":
        case "apple":
          return "Lithium batteries last longest kept between about 20% and 80%. Stop charging at the level below while plugged in."
        case "upower":
          return "Your firmware sets the levels: charging " + (view.backend.start > 0 ? "starts below " + view.backend.start + "% and " : "") +
                 "stops at " + (view.backend.end || 80) + "%. Switch the limit on or off here."
        case "acer":
          return "Acer's health mode holds the charge at 80% while plugged in (the level is the firmware's). Switch it on or off here."
        case "locked":
          return "This battery has a charge limit, but only root may set it. docs/charge-limit.md in the plugin folder shows a one-time rule that lets your user set it; until then the unplug reminder below stands in."
        default:
          return "This laptop does not let the system cap its charge. The unplug reminder below tells you when to take the charger out instead."
        }
      }
    }

    SwitchRow {
      visible: view.s.limitCapable
      label: "Limit charging"
      hint: view.s.topUp ? "Paused: charging to 100% once" : ""
      checked: view.care.enabled
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.updateCare({ managed: true, enabled: !view.care.enabled })
    }

    // Exact level (kernel, Apple).
    Column {
      visible: view.backend.exact && view.care.enabled
      width: parent.width
      spacing: Style.space(4)

      Item {
        width: parent.width
        implicitHeight: limitLabel.implicitHeight
        Text {
          id: limitLabel
          textFormat: Text.PlainText
          text: "Stop at"
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.body
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: Math.round(limitSlider.liveValue) + "%"
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }
      PanelSlider {
        id: limitSlider
        width: parent.width
        bar: view.panel.bar
        minimum: 50
        maximum: 100
        step: 5
        integer: true
        value: view.care.limit
        onReleased: function(v) { view.s.updateCare({ managed: true, limit: Model.clampLimit(v) }) }
      }
      Row {
        spacing: Style.space(6)
        Repeater {
          model: [60, 70, 80, 90]
          Button {
            required property int modelData
            text: modelData + "%"
            fontSize: Style.font.caption
            bordered: true
            active: view.care.limit === modelData
            foreground: view.fg
            fontFamily: view.ff
            onClicked: view.s.updateCare({ managed: true, limit: modelData })
          }
        }
      }
    }

    // Sailing: let it drift down to a start level before charging again.
    SwitchRow {
      visible: view.backend.sailing && view.care.enabled
      label: "Sailing mode"
      hint: "Charging restarts only below " + Math.min(view.care.sailStart, view.care.limit - 2) + "%, so the battery is not topped up by every small dip."
      checked: view.care.sailing
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.updateCare({ managed: true, sailing: !view.care.sailing })
    }
    PanelSlider {
      visible: view.backend.sailing && view.care.enabled && view.care.sailing
      width: parent.width
      bar: view.panel.bar
      minimum: 40
      maximum: Math.max(42, view.care.limit - 2)
      step: 1
      integer: true
      value: Math.min(view.care.sailStart, view.care.limit - 2)
      onReleased: function(v) { view.s.updateCare({ managed: true, sailStart: Math.round(v) }) }
    }

    // One full charge (a trip ahead), then the limit comes back.
    Row {
      visible: view.s.limitCapable
      spacing: Style.space(8)
      Button {
        iconText: "󰂅"
        text: view.s.topUp ? "Stop top-up" : "Charge to 100% once"
        tooltipText: "The limit comes back once you unplug after a full charge, or after a day"
        fontSize: Style.font.caption
        bordered: true
        active: view.s.topUp
        foreground: view.fg
        fontFamily: view.ff
        onClicked: view.s.topUp ? view.s.stopTopUp() : view.s.startTopUp()
      }
      Button {
        iconText: "󰑓"
        text: view.s.calibrating ? "Stop calibrating" : "Calibrate"
        tooltipText: "Charge to 100%, rest an hour, run down to 15%, charge back: keeps the charge reading honest. Every few months is plenty."
        fontSize: Style.font.caption
        bordered: true
        active: view.s.calibrating
        foreground: view.fg
        fontFamily: view.ff
        onClicked: view.s.calibrating ? view.s.stopCalibration() : view.s.startCalibration()
      }
    }

    Text {
      visible: view.s.calibrating
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Calibration: " + (Model.CALIBRATION_LABELS[view.s.store.calibration.phase] || "")
      color: view.fg
      font.family: view.ff
      font.pixelSize: Style.font.caption
    }

    // Without a usable hardware limit.
    SwitchRow {
      visible: !view.s.limitCapable
      label: "Unplug reminder"
      hint: "A notification when charging reaches " + view.care.limit + "%."
      checked: view.care.unplugReminder
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.updateCare({ unplugReminder: !view.care.unplugReminder })
    }
    PanelSlider {
      visible: !view.s.limitCapable && view.care.unplugReminder
      width: parent.width
      bar: view.panel.bar
      minimum: 50
      maximum: 95
      step: 5
      integer: true
      value: Math.min(95, view.care.limit)
      onReleased: function(v) { view.s.updateCare({ limit: Model.clampLimit(v) }) }
    }
  }

  // ---------------------------------------------------------- heat protection

  Section {
    visible: view.s.temperature > 0
    title: "HEAT PROTECTION"
    trailing: view.s.temperature + " °C"
    foreground: view.fg
    fontFamily: view.ff

    SwitchRow {
      label: view.s.limitCapable ? "Pause charging when hot" : "Warn when hot"
      hint: (view.s.limitCapable ? "Charging stops" : "A notification") + " at " + view.care.heatLimit + " °C and " +
            (view.s.limitCapable ? "resumes" : "re-arms") + " below " + view.care.heatResume + " °C."
      checked: view.care.heatGuard
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.updateCare({ heatGuard: !view.care.heatGuard })
    }
    ButtonGroup {
      visible: view.care.heatGuard
      width: parent.width
      options: [{ value: "38", label: "38 °C" }, { value: "40", label: "40 °C" }, { value: "42", label: "42 °C" }, { value: "45", label: "45 °C" }]
      value: String(view.care.heatLimit)
      foreground: view.fg
      fontFamily: view.ff
      fontSize: Style.font.caption
      onChanged: function(v) { var n = Number(v); view.s.updateCare({ heatLimit: n, heatResume: n - 4 }) }
    }
  }

  // ----------------------------------------------------------------- warnings

  // Suspend or hibernate may not come back on this machine.
  Card {
    visible: view.s.sleepIssues.length > 0
    tint: Color.urgent
    foreground: view.fg
    fontFamily: view.ff
    text: view.s.sleepIssues.map(function(i) { return "󰀪  " + i.text }).join("\n")
    Button {
      text: "How to fix"
      iconText: "󰋗"
      bordered: true
      fontSize: Style.font.caption
      foreground: view.fg
      fontFamily: view.ff
      onClicked: { Qt.openUrlExternally(view.s.docsUrl + "/sleep.md"); view.s.closePanel() }
    }
  }

  Section {
    title: "WARNINGS"
    foreground: view.fg
    fontFamily: view.ff

    Card {
      visible: view.s.omarchyBatteryOn
      tint: Color.accent
      foreground: view.fg
      fontFamily: view.ff
      text: "Omarchy's own battery service is on: it warns once at 10% and switches profiles on plug events. OmniSystem Center leaves those to it for now. Let OmniSystem Center take over for your own levels" +
            (view.s.criticalAction !== "none" ? " (the critical action runs either way)" : "") + "."
      Button {
        text: "Take over"
        bordered: true
        active: true
        fontSize: Style.font.caption
        foreground: view.fg
        fontFamily: view.ff
        onClicked: view.s.takeOverBatteryService()
      }
    }

    Grid {
      width: parent.width
      columns: 3
      columnSpacing: Style.space(12)
      readonly property real cell: (width - columnSpacing * 2) / 3
      Stat {
        width: parent.cell
        label: "Low warning"
        value: view.s.omarchyBatteryOn ? "10% (Omarchy)" : (view.s.lowLevel > 0 ? view.s.lowLevel + "%" : "Off")
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Critical"
        value: view.s.criticalLevel > 0 ? view.s.criticalLevel + "% · " + (view.s.criticalAction === "none" ? "warn" : view.s.criticalAction) : "Off"
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Power saver at"
        value: view.s.lowProfileLevel > 0 && view.s.profiles.indexOf("power-saver") >= 0 ? view.s.lowProfileLevel + "%" : "Off"
        foreground: view.fg
        fontFamily: view.ff
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
      text: (view.s.criticalSetting === "hibernate" && !view.s.hibernateAvailable
              ? "Hibernation is not set up (omarchy-hibernation-setup), so the critical action suspends. " : "") +
            "Change the levels in Omarchy's widget settings for OmniSystem Center."
    }

    Button {
      visible: !view.s.omarchyBatteryOn
      text: "Give warnings back to Omarchy"
      fontSize: Style.font.caption
      bordered: true
      foreground: view.fg
      fontFamily: view.ff
      onClicked: view.s.handBackBatteryService()
    }
  }
}

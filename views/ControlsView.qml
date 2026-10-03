import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// Keep awake, the sleep timer, lid hold and the keyboard backlight per power
// source. Lid hold and the backlight appear only on hardware that has them.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim

  property int timerMinutes: 30
  property string timerAction: s.suspendAvailable ? "suspend" : "shutdown"

  spacing: Style.space(14)

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
    title: "AWAKE"
    separator: false
    foreground: view.fg
    fontFamily: view.ff

    SwitchRow {
      label: "Keep awake"
      hint: "No idle lock, screensaver or sleep until you switch it off. Shared with Omarchy's own stay-awake toggle."
      checked: view.s.keepAwake
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.setKeepAwake(!view.s.keepAwake)
    }

    SwitchRow {
      visible: view.s.lidPresent
      label: "Lid hold"
      hint: "Keeps running with the lid closed (downloads, music, a long build). Omarchy already does this while an external display is connected."
      checked: view.s.lidHoldOn
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.setLidHold(!view.s.lidHoldOn)
    }
  }

  Section {
    title: "SLEEP TIMER"
    trailing: view.s.timerActive ? Model.profileLabel(view.s.store.timer.action).toUpperCase() + " IN " + Model.formatCountdown(view.s.timerLeft) : ""
    foreground: view.fg
    fontFamily: view.ff

    // Running: the countdown with extend and cancel.
    Item {
      visible: view.s.timerActive
      width: parent.width
      implicitHeight: Math.max(countdown.implicitHeight, timerButtons.implicitHeight)

      Text {
        id: countdown
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Model.formatCountdown(view.s.timerLeft)
        color: view.fg
        font.family: view.ff
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }
      Row {
        id: timerButtons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        Button {
          text: "+15 min"
          fontSize: Style.font.caption
          bordered: true
          foreground: view.fg
          fontFamily: view.ff
          onClicked: view.s.extendSleepTimer(15)
        }
        Button {
          text: "Cancel"
          fontSize: Style.font.caption
          bordered: true
          active: true
          foreground: view.fg
          fontFamily: view.ff
          onClicked: view.s.cancelSleepTimer()
        }
      }
    }

    // Not running: what and when.
    ButtonGroup {
      visible: !view.s.timerActive
      width: parent.width
      options: Model.TIMER_ACTIONS.filter(function(a) {
        return (a !== "suspend" || view.s.suspendAvailable) && (a !== "hibernate" || view.s.hibernateAvailable)
      }).map(function(a) { return { value: a, label: Model.profileLabel(a) } })
      value: view.timerAction
      foreground: view.fg
      fontFamily: view.ff
      fontSize: Style.font.caption
      onChanged: function(v) { view.timerAction = v }
    }
    ButtonGroup {
      visible: !view.s.timerActive
      width: parent.width
      options: Model.TIMER_PRESETS.map(function(m) { return { value: String(m), label: m < 60 ? m + "m" : (m / 60) + "h" } })
      value: String(view.timerMinutes)
      foreground: view.fg
      fontFamily: view.ff
      fontSize: Style.font.caption
      onChanged: function(v) { view.timerMinutes = Number(v) }
    }
    Button {
      visible: !view.s.timerActive
      iconText: "󰔛"
      text: "Start: " + Model.profileLabel(view.timerAction).toLowerCase() + " in " + Model.formatDuration(view.timerMinutes * 60)
      fontSize: Style.font.caption
      bordered: true
      active: true
      foreground: view.fg
      fontFamily: view.ff
      onClicked: view.s.startSleepTimer(view.timerMinutes, view.timerAction)
    }
  }

  Section {
    visible: !!view.s.keyboard
    title: "KEYBOARD BACKLIGHT"
    foreground: view.fg
    fontFamily: view.ff

    SwitchRow {
      label: "Per power source"
      hint: "Sets the backlight each time you plug in or unplug."
      checked: view.s.store.keyboard.enabled
      foreground: view.fg
      fontFamily: view.ff
      onToggled: view.s.setKeyboardPrefs({ enabled: !view.s.store.keyboard.enabled })
    }

    Repeater {
      model: view.s.store.keyboard.enabled ? ["ac", "battery"] : []
      Column {
        required property string modelData
        width: view.width
        spacing: Style.space(4)
        Item {
          width: parent.width
          implicitHeight: kbLabel.implicitHeight
          Text {
            id: kbLabel
            textFormat: Text.PlainText
            text: (modelData === "ac" ? "On AC" : "On battery") + (modelData === view.s.currentSource ? "  ·  now" : "")
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.right: parent.right
            textFormat: Text.PlainText
            text: Math.round(kbSlider.liveValue) + "%"
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.body
          }
        }
        PanelSlider {
          id: kbSlider
          width: parent.width
          bar: view.panel.bar
          minimum: 0
          maximum: 100
          step: view.s.keyboard && view.s.keyboard.max <= 10 ? 100 / view.s.keyboard.max : 10
          integer: true
          value: Number(view.s.store.keyboard[modelData]) || 0
          onReleased: function(v) {
            var patch = {}
            patch[modelData] = Math.round(v)
            view.s.setKeyboardPrefs(patch)
          }
        }
      }
    }
  }
}

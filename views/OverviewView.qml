import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// The first tab. Sections follow Model.sectionOrder: battery, gadgets,
// profiles and quick switches on a laptop; gadgets lead on a desktop. The
// power controls are drawn by Panel.qml under every tab.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim

  spacing: Style.space(14)

  Repeater {
    model: Model.sectionOrder(view.s.hasBattery).filter(function(k) { return k !== "power" })
    Loader {
      required property string modelData
      required property int index
      width: view.width
      sourceComponent: ({ battery: batterySection, gadgets: gadgetsSection, profiles: profilesSection, awake: quickSection })[modelData]
      property bool first: index === 0
    }
  }

  // ---------------------------------------------------------------- battery

  Component {
    id: batterySection

    Column {
      width: view.width
      spacing: Style.space(12)

      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          text: view.s.batteryGlyph
          color: view.s.isLow ? Color.urgent : view.fg
          font.family: view.ff
          font.pixelSize: Style.font.display
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: heroPercent.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "Battery"
            color: view.fg
            font.family: view.ff
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: {
              var st = view.s
              var bits = [st.mode]
              if (st.timeText) bits.push(st.timeText + (st.onBattery ? " left" : " to full"))
              return bits.join(" · ").toUpperCase()
            }
            color: view.dim
            font.family: view.ff
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Text {
          id: heroPercent
          textFormat: Text.PlainText
          text: view.s.level >= 0 ? view.s.level + "%" : "—"
          color: view.s.isLow ? Color.urgent : view.fg
          font.family: view.ff
          font.pixelSize: Style.font.displayLarge
          font.bold: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Meter {
        width: parent.width
        value: view.s.fraction
        color: view.s.isLow ? Color.urgent : view.panel.palette.accent
        pulsing: view.s.charging && panel.opened
        marker: view.s.limitCapable && view.s.store.care.enabled && !view.s.topUp ? view.s.store.care.limit / 100
              : (view.s.backend.kind === "none" && view.s.store.care.unplugReminder ? view.s.store.care.limit / 100 : -1)
      }

      // Four across: power, health, cycles and size on the first row.
      Grid {
        width: parent.width
        columns: 4
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(10)
        readonly property real cell: (width - columnSpacing * 3) / 4

        Stat {
          width: parent.cell
          label: view.s.flowing ? (view.s.onBattery ? "Draw" : "Charging at") : "Power"
          value: view.s.flowing ? Model.formatWatts(view.s.watts) : (view.s.thresholdActive ? "Holding" : "Idle")
          foreground: view.fg
          fontFamily: view.ff
        }
        Stat {
          width: parent.cell
          label: "Health"
          value: view.s.sysfsBattery.health >= 0 ? view.s.sysfsBattery.health + "% · " + Model.healthLabel(view.s.sysfsBattery.health) : ""
          valueColor: view.s.sysfsBattery.health >= 0 && view.s.sysfsBattery.health < 50 ? Color.urgent : view.fg
          foreground: view.fg
          fontFamily: view.ff
        }
        Stat {
          width: parent.cell
          label: "Cycles"
          value: view.s.sysfsBattery.cycles ? String(view.s.sysfsBattery.cycles) : (view.s.batteryInfo.cycles || "")
          foreground: view.fg
          fontFamily: view.ff
        }
        Stat {
          width: parent.cell
          label: "Size"
          value: view.s.batteryInfo.size || ""
          foreground: view.fg
          fontFamily: view.ff
        }
        Stat {
          width: parent.cell
          label: "Temperature"
          value: view.s.temperature > 0 ? view.s.temperature + " °C" : ""
          valueColor: view.s.temperature >= 40 ? Color.urgent : view.fg
          foreground: view.fg
          fontFamily: view.ff
        }
        Stat {
          width: parent.cell
          label: "Drain"
          value: view.s.discharging && view.s.drainRate > 0 ? view.s.drainRate + "%/h" : ""
          foreground: view.fg
          fontFamily: view.ff
        }
        Stat {
          width: parent.cell
          label: "Charge limit"
          value: {
            var st = view.s
            if (!st.limitCapable) return ""
            if (st.topUp) return "Top-up to 100%"
            if (st.backend.kind === "upower") return st.backend.enabled ? st.backend.start + "–" + st.backend.end + "%" : "Off"
            if (st.backend.kind === "acer") return st.backend.enabled ? "80% (health mode)" : "Off"
            return st.backend.end > 0 && st.backend.end < 100 ? st.backend.end + "%" : "Off"
          }
          foreground: view.fg
          fontFamily: view.ff
        }
      }

      // What care is doing right now.
      Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
        text: {
          var st = view.s
          var bits = []
          if (st.store.heatHolding && st.store.care.heatGuard) bits.push("Heat protection: charging paused while the battery cools")
          if (st.calibrating) bits.push("Calibrating: " + (Model.CALIBRATION_LABELS[st.store.calibration.phase] || ""))
          if (st.store.lowProfile.active) bits.push("Power saver for low battery")
          return bits.join(" · ")
        }
      }
    }
  }

  // ---------------------------------------------------------------- gadgets

  Component {
    id: gadgetsSection

    Section {
      title: "GADGETS"
      trailing: view.s.gadgets.length ? String(view.s.gadgets.length) : ""
      separator: view.s.hasBattery
      foreground: view.fg
      fontFamily: view.ff
      visible: view.s.gadgets.length > 0 || !view.s.hasBattery

      Text {
        visible: view.s.gadgets.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "No mouse, keyboard, headset or earbuds is reporting a battery right now."
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: view.s.gadgets

        Item {
          id: row
          required property var modelData
          property bool editing: false
          width: view.width
          implicitHeight: Math.max(Style.space(34), rowCol.implicitHeight)

          readonly property bool low: !modelData.offline && !modelData.charging && view.s.gadgetLowLevel > 0 && modelData.level <= view.s.gadgetLowLevel
          readonly property var app: view.s.gadgetApp(modelData)

          Text {
            id: kindIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26)
            textFormat: Text.PlainText
            text: Model.kindIcon(row.modelData.kind)
            color: row.modelData.offline ? view.dim : view.fg
            font.family: view.ff
            font.pixelSize: Style.font.title
          }

          Column {
            id: rowCol
            anchors.left: kindIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: levelText.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              visible: !row.editing
              width: parent.width
              textFormat: Text.PlainText
              text: row.modelData.name + (row.modelData.detail ? "  ·  " + row.modelData.detail : "")
              color: row.modelData.offline ? view.dim : view.fg
              font.family: view.ff
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            TextField {
              id: nameField
              visible: row.editing
              width: parent.width
              text: row.modelData.name
              foreground: view.fg
              onActiveFocusChanged: view.panel.textEditing = activeFocus
              onAccepted: { view.s.renameGadget(row.modelData.reportedName || row.modelData.name, text); row.editing = false }
              Keys.onEscapePressed: row.editing = false
            }

            Meter {
              visible: !row.modelData.offline && !row.editing
              width: parent.width
              implicitHeight: Style.space(5)
              value: row.modelData.level / 100
              color: row.low ? Color.urgent : view.panel.palette.accent
              pulsing: row.modelData.charging === true && view.panel.opened
            }
          }

          Text {
            id: levelText
            anchors.right: actions.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: row.modelData.offline ? "offline" : (row.modelData.charging ? "󱐋 " : "") + row.modelData.level + "%"
            color: row.low ? Color.urgent : (row.modelData.offline ? view.dim : view.fg)
            font.family: view.ff
            font.pixelSize: Style.font.body
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            PanelActionButton {
              iconText: row.editing ? "󰄬" : "󰏫"
              tooltipText: row.editing ? "Save the name" : "Rename"
              foreground: view.fg
              fontFamily: view.ff
              onClicked: {
                if (row.editing) { view.s.renameGadget(row.modelData.reportedName || row.modelData.name, nameField.text); row.editing = false }
                else { row.editing = true; nameField.forceActiveFocus(); nameField.selectAll() }
              }
            }
            PanelActionButton {
              visible: row.app !== null
              iconText: "󰏌"
              tooltipText: "Open " + (row.app ? row.app[0] : "")
              foreground: view.fg
              fontFamily: view.ff
              onClicked: view.s.openGadgetApp(row.modelData)
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- profiles

  Component {
    id: profilesSection

    Section {
      title: "POWER PROFILE"
      trailing: view.s.store.lowProfile.active ? "POWER SAVER · LOW BATTERY" : ""
      foreground: view.fg
      fontFamily: view.ff
      visible: view.s.profiles.length > 0

      Repeater {
        // One row per power source on a laptop; one row on a desktop.
        model: view.s.hasBattery ? ["ac", "battery"] : ["ac"]

        Column {
          id: sourceRow
          required property string modelData
          width: view.width
          spacing: Style.space(6)
          readonly property bool current: modelData === view.s.currentSource
          readonly property string chosen: current ? view.s.activeProfile : view.s.rememberedFor(modelData)

          Text {
            visible: view.s.hasBattery
            textFormat: Text.PlainText
            text: (sourceRow.modelData === "ac" ? "󰚥  On AC" : "󰁹  On battery") + (sourceRow.current ? "  ·  now" : "  ·  remembered")
            color: sourceRow.current ? view.fg : view.dim
            font.family: view.ff
            font.pixelSize: Style.font.caption
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: (width - spacing * (view.s.profiles.length - 1)) / Math.max(1, view.s.profiles.length)

            Repeater {
              model: view.s.profiles
              Button {
                required property var modelData
                width: profileRow.cell
                iconText: Model.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: Model.profileLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: view.fg
                fontFamily: view.ff
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + (sourceRow.current ? Style.space(2) : 0)
                bordered: true
                active: sourceRow.chosen === modelData
                opacity: sourceRow.current ? 1 : 0.8
                tooltipText: sourceRow.current ? "Use now, and remember for " + (sourceRow.modelData === "ac" ? "AC" : "battery")
                                               : "Remember for " + (sourceRow.modelData === "ac" ? "AC" : "battery") + "; applied when you switch"
                onClicked: view.s.setProfileFor(sourceRow.modelData, modelData)
              }
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------- quick switches

  Component {
    id: quickSection

    Section {
      title: "QUICK"
      foreground: view.fg
      fontFamily: view.ff

      Row {
        id: quickRow
        width: view.width
        spacing: Style.space(6)
        readonly property int count: view.s.lidPresent ? 3 : 2
        readonly property real cell: (width - spacing * (count - 1)) / count

        Button {
          width: quickRow.cell
          iconText: view.s.keepAwake ? "󰅶" : "󰾪"
          text: view.s.keepAwake ? "Awake" : "Keep awake"
          tooltipText: "Stop the screen locking and the machine sleeping when idle (A)"
          fontSize: Style.font.bodySmall
          foreground: view.fg
          fontFamily: view.ff
          bordered: true
          active: view.s.keepAwake
          onClicked: view.s.setKeepAwake(!view.s.keepAwake)
        }
        Button {
          width: quickRow.cell
          iconText: "󰔛"
          text: view.s.timerActive ? Model.formatCountdown(view.s.timerLeft) : "Sleep timer"
          tooltipText: view.s.timerActive ? Model.profileLabel(view.s.store.timer.action) + " when this runs out" : "Suspend or shut down after a while"
          fontSize: Style.font.bodySmall
          foreground: view.fg
          fontFamily: view.ff
          bordered: true
          active: view.s.timerActive
          onClicked: view.panel.tab = "controls"
        }
        Button {
          visible: view.s.lidPresent
          width: quickRow.cell
          iconText: "󰛧"
          text: "Lid hold"
          tooltipText: "Keep running with the lid closed"
          fontSize: Style.font.bodySmall
          foreground: view.fg
          fontFamily: view.ff
          bordered: true
          active: view.s.lidHoldOn
          onClicked: view.s.setLidHold(!view.s.lidHoldOn)
        }
      }
    }
  }
}

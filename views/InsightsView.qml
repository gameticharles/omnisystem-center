import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// Battery health, the last six hours, the last seven days, sessions on
// battery, tips, and the report.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property var b: s.sysfsBattery
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim

  spacing: Style.space(14)

  // ------------------------------------------------------------------ health

  Section {
    title: "HEALTH"
    trailing: view.b.health >= 0 ? Model.healthLabel(view.b.health).toUpperCase() : ""
    separator: false
    foreground: view.fg
    fontFamily: view.ff

    Item {
      visible: view.b.health >= 0
      width: parent.width
      implicitHeight: healthBig.implicitHeight

      Text {
        id: healthBig
        textFormat: Text.PlainText
        text: view.b.health + "%"
        color: view.b.health < 50 ? Color.urgent : view.fg
        font.family: view.ff
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }
      Column {
        anchors.left: healthBig.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: healthBig.verticalCenter
        spacing: Style.space(4)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "of its design capacity left"
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.body
        }
        Meter {
          width: parent.width
          implicitHeight: Style.space(6)
          value: view.b.health / 100
          color: view.b.health < 50 ? Color.urgent : view.panel.palette.accent
        }
      }
    }

    Grid {
      width: parent.width
      columns: 3
      columnSpacing: Style.space(12)
      rowSpacing: Style.space(10)
      readonly property real cell: (width - columnSpacing * 2) / 3

      Stat {
        width: parent.cell
        label: "Full now"
        value: view.b.full ? view.b.full.toFixed(1) + " " + view.b.unit : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "When new"
        value: view.b.design ? view.b.design.toFixed(1) + " " + view.b.unit : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Cycles"
        value: view.b.cycles ? String(view.b.cycles) : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Wear rate"
        value: view.s.wearPer100 >= 0 ? view.s.wearPer100 + "% / 100 cycles" : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Voltage"
        value: view.b.voltage ? view.b.voltage.toFixed(2) + " V" : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Temperature"
        value: view.s.temperature > 0 ? view.s.temperature + " °C" : ""
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Chemistry"
        value: view.b.technology
        foreground: view.fg
        fontFamily: view.ff
      }
      Stat {
        width: parent.cell
        label: "Model"
        value: [view.b.maker, view.b.model].filter(function(x) { return x }).join(" ")
        foreground: view.fg
        fontFamily: view.ff
      }
    }
  }

  // ----------------------------------------------------------- last 6 hours

  Section {
    title: "LAST 6 HOURS"
    trailing: view.s.discharging && view.s.drainRate > 0 ? view.s.drainRate + "%/H" : ""
    foreground: view.fg
    fontFamily: view.ff

    ChartCard {
      foreground: view.fg
      Item {
        width: parent.width
        height: Style.space(90)

        Graph {
          id: history
          anchors.fill: parent
          anchors.bottomMargin: Style.space(14)
          color: view.panel.palette.accent
          guideY: view.s.limitCapable && view.s.store.care.enabled ? height - view.s.store.care.limit / 100 * height : -1
          segments: Model.historySegments(view.s.store.history, view.s.nowMs, width, height)
        }
        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: "6 h ago"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: "now"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: (view.s.store.history || []).length < 2
          anchors.centerIn: history
          textFormat: Text.PlainText
          text: "Collecting: one reading a minute"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ------------------------------------------------------------ last 7 days

  Section {
    title: "LAST 7 DAYS"
    trailing: "ON BATTERY"
    foreground: view.fg
    fontFamily: view.ff

    ChartCard {
      foreground: view.fg
      Row {
        id: bars
        width: parent.width
        height: Style.space(96)
        spacing: Style.space(6)
        readonly property real cell: (width - spacing * 6) / 7
        readonly property real peak: {
          var m = 60
          for (var i = 0; i < view.s.days7.length; i++) m = Math.max(m, view.s.days7[i].bat)
          return m
        }

        Repeater {
          model: view.s.days7
          Item {
            required property var modelData
            required property int index
            width: bars.cell
            height: bars.height

            Text {
              id: dayLabel
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: index === 6 ? "Today" : modelData.label
              color: index === 6 ? view.fg : view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Text {
              id: value
              anchors.bottom: bar.top
              anchors.bottomMargin: Style.space(2)
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: modelData.bat >= 1 ? Model.formatDuration(modelData.bat * 60) : ""
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption * 0.9
            }
            Rectangle {
              id: bar
              anchors.bottom: dayLabel.top
              anchors.bottomMargin: Style.space(4)
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Style.space(26))
              radius: Math.min(width / 4, Style.cornerRadius)
              readonly property real room: bars.height - dayLabel.height - value.height - Style.space(10)
              height: Math.max(2, room * modelData.bat / bars.peak)
              color: modelData.bat > 0 ? view.panel.palette.accent : Util.alpha(view.fg, 0.15)
              opacity: index === 6 ? 1 : 0.75
            }
          }
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
      text: {
        var bat = 0, ac = 0, wh = 0
        for (var i = 0; i < view.s.days7.length; i++) { bat += view.s.days7[i].bat; ac += view.s.days7[i].ac; wh += view.s.days7[i].wh }
        if (bat + ac === 0) return "Days fill in as you use the laptop."
        return "This week: " + (Model.formatDuration(bat * 60) || "0m") + " on battery, " + (Model.formatDuration(ac * 60) || "0m") +
               " on AC" + (wh > 0 ? ", " + wh.toFixed(1) + " Wh from the battery" : "") + "."
      }
    }
  }

  // ---------------------------------------------------------------- sessions

  Section {
    visible: (view.s.store.sessions || []).length > 0 || !!view.s.store.session
    title: "ON BATTERY"
    foreground: view.fg
    fontFamily: view.ff

    Text {
      visible: !!view.s.store.session
      width: parent.width
      textFormat: Text.PlainText
      text: view.s.store.session ? "Now: " + (Model.formatDuration((view.s.nowMs - view.s.store.session.start) / 1000) || "just started") +
            " since " + view.s.store.session.from + "%" : ""
      color: view.fg
      font.family: view.ff
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: (view.s.store.sessions || []).slice(0, 5)
      Item {
        required property var modelData
        width: view.width
        implicitHeight: when.implicitHeight
        Text {
          id: when
          textFormat: Text.PlainText
          text: Qt.formatDateTime(new Date(modelData.start), "ddd hh:mm")
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: Model.sessionLine(modelData)
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  // ------------------------------------------------------------- tips, report

  Section {
    title: "TIPS"
    visible: view.s.tips.length > 0
    foreground: view.fg
    fontFamily: view.ff

    Repeater {
      model: view.s.tips
      Text {
        required property string modelData
        width: view.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "•  " + modelData
        color: view.fg
        font.family: view.ff
        font.pixelSize: Style.font.caption
      }
    }
  }

  Section {
    title: "REPORT"
    foreground: view.fg
    fontFamily: view.ff

    Row {
      spacing: Style.space(8)
      Button {
        iconText: "󰈙"
        text: "Save to Documents"
        tooltipText: "A Markdown report: health, the last two weeks, sessions and gadgets"
        fontSize: Style.font.caption
        bordered: true
        foreground: view.fg
        fontFamily: view.ff
        onClicked: view.s.exportReport(false)
      }
      Button {
        visible: view.s.tools["wl-copy"] === true
        iconText: "󰆏"
        text: "Copy"
        fontSize: Style.font.caption
        bordered: true
        foreground: view.fg
        fontFamily: view.ff
        onClicked: view.s.exportReport(true)
      }
    }
  }
}

import QtQuick
import qs.Commons
import "../lib/Model.js" as Model

// Several readings with their recent history on one small graph: a label, a
// legend (colour, name, latest value) and one line per series, on a shared
// scale from `floor` to `ceiling`. `lines` is [{ name, color, series, value }].
Item {
  id: tile

  property string label: ""
  property var lines: []
  property int slots: 60
  property real floor: 0
  property real ceiling: 100
  property bool shown: true
  property string emptyText: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  visible: shown
  // A card: the graph's extent is plain at a glance.
  implicitHeight: body.implicitHeight + Style.space(20)

  Rectangle {
    anchors.fill: parent
    radius: Math.max(Style.space(6), Style.cornerRadius)
    color: Util.alpha(tile.foreground, 0.035)
    border.width: 1
    border.color: Util.alpha(tile.foreground, 0.10)
  }

  Column {
    id: body
    x: Style.space(10)
    y: Style.space(10)
    width: tile.width - Style.space(20)
    spacing: Style.space(4)

    Text {
      width: body.width
      textFormat: Text.PlainText
      text: tile.label.toUpperCase()
      color: Qt.darker(tile.foreground, 1.4)
      font.family: tile.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0.8
    }

    Flow {
      width: body.width
      spacing: Style.space(8)
      // Keyed by count, not by the array: the lines arrive as a new array
      // every sample, and a new model would rebuild (and flicker) every item.
      Repeater {
        model: tile.lines.length
        Row {
          required property int index
          readonly property var modelData: tile.lines[index] || ({})
          spacing: Style.space(4)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: modelData.color
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.name + " " + (modelData.value || "…")
            color: tile.foreground
            font.family: tile.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
      Text {
        visible: tile.lines.length === 0 && tile.emptyText !== ""
        textFormat: Text.PlainText
        text: tile.emptyText
        color: Qt.darker(tile.foreground, 1.4)
        font.family: tile.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      width: body.width
      height: Style.space(54)
      Repeater {
        model: tile.lines.length
        Graph {
          required property int index
          readonly property var modelData: tile.lines[index] || ({})
          anchors.fill: parent
          color: modelData.color
          fill: index === 0
          gridLines: index === 0 ? 1 : 0
          points: Model.rangePoints(modelData.series, width, height, tile.slots, tile.floor, tile.ceiling)
        }
      }
    }
  }
}

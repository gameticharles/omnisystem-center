import QtQuick
import qs.Commons

// A reading with its recent history: label and value over a small graph.
Item {
  id: tile

  property string label: ""
  property string value: ""
  property var series: []
  property int slots: 60
  property real ceiling: 100
  property bool shown: true
  property color foreground: Color.foreground
  property color lineColor: foreground
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

    Item {
      width: body.width
      implicitHeight: tileLabel.implicitHeight
      Text {
        id: tileLabel
        textFormat: Text.PlainText
        text: tile.label.toUpperCase()
        color: Qt.darker(tile.foreground, 1.4)
        font.family: tile.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }
      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: tile.value || "…"
        color: tile.foreground
        font.family: tile.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Graph {
      width: body.width
      height: Style.space(54)
      color: tile.lineColor
      gridLines: 1
      points: {
        var list = tile.series || []
        var n = Math.max(2, tile.slots)
        var pts = []
        var offset = n - list.length
        for (var i = 0; i < list.length; i++) {
          if (!(list[i] >= 0)) continue
          pts.push([(offset + i) / (n - 1) * width, height - Math.min(tile.ceiling, list[i]) / tile.ceiling * height])
        }
        return pts
      }
    }
  }
}

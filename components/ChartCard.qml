import QtQuick
import qs.Commons

// A container for a chart: a rounded surface with a faint border and an
// inner margin, so the graph's extent is plain. The chart is its child.
Item {
  id: card

  property color foreground: Color.foreground
  property real padding: Style.space(10)
  default property alias content: inner.data

  width: parent ? parent.width : implicitWidth
  implicitHeight: inner.childrenRect.height + padding * 2

  Rectangle {
    anchors.fill: parent
    radius: Math.max(Style.space(6), Style.cornerRadius)
    color: Util.alpha(card.foreground, 0.035)
    border.width: 1
    border.color: Util.alpha(card.foreground, 0.10)
  }
  Item {
    id: inner
    x: card.padding
    y: card.padding
    width: card.width - card.padding * 2
    height: childrenRect.height
  }
}

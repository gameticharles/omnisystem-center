import QtQuick
import qs.Commons

// A list tile: rounded, a faint border, a hover wash, and the tint's wash and
// border while selected. The tile's contents are its children; `clicked`
// fires for a click anywhere not taken by a child's own MouseArea.
Item {
  id: tile

  property bool selected: false
  property color tint: Color.accent
  property color foreground: Color.foreground
  property bool alert: false
  // The keyboard cursor: a stronger border in the tint.
  property bool focused: false
  // Only this much of the top takes the click (a tile with details open below).
  property real hitHeight: 0
  readonly property bool hovered: area.containsMouse
  default property alias content: inner.data
  signal clicked()

  Rectangle {
    anchors.fill: parent
    radius: Math.max(Style.space(4), Style.cornerRadius)
    color: tile.selected ? Qt.rgba(tile.tint.r, tile.tint.g, tile.tint.b, 0.10)
         : tile.hovered ? Util.alpha(tile.foreground, 0.05) : Util.alpha(tile.foreground, 0.02)
    border.width: tile.focused ? 1.5 : 1
    border.color: tile.focused ? Qt.rgba(tile.tint.r, tile.tint.g, tile.tint.b, 0.95)
                : tile.selected ? Qt.rgba(tile.tint.r, tile.tint.g, tile.tint.b, 0.55)
                : tile.alert ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.55)
                : Util.alpha(tile.foreground, tile.hovered ? 0.16 : 0.08)
    Behavior on color { ColorAnimation { duration: 120 } }
  }
  // An alert rail on the left edge (a dev server open to the network).
  Rectangle {
    visible: tile.alert
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(6)
    anchors.bottomMargin: Style.space(6)
    width: 3
    radius: 1.5
    color: Color.urgent
  }
  MouseArea {
    id: area
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: tile.hitHeight > 0 ? tile.hitHeight : tile.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: tile.clicked()
  }
  Item {
    id: inner
    anchors.fill: parent
  }
}

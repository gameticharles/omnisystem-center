import QtQuick
import qs.Ui
import qs.Commons

// One fact: a dim label, the value on the right. Clicking copies the value.
Item {
  id: root

  property string label: ""
  property string value: ""
  property string detail: ""
  property color foreground: Color.foreground
  property color valueColor: foreground
  property string fontFamily: Style.font.family
  signal copyRequested(string text)

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(labelText.implicitHeight, valueColumn.implicitHeight) + Style.space(2)
  visible: value !== ""

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.space(2)
    radius: Style.space(3)
    color: hover.containsMouse ? Util.alpha(root.foreground, 0.06) : "transparent"
  }

  Text {
    id: labelText
    width: parent.width * 0.34
    textFormat: Text.PlainText
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  Column {
    id: valueColumn
    anchors.left: labelText.right
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: root.value
      color: root.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideMiddle
    }
    Text {
      width: parent.width
      visible: root.detail !== ""
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: root.detail
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.copyRequested(root.value)
  }
  PanelToolTip {
    visible: hover.containsMouse
    text: "Click to copy"
    fontFamily: root.fontFamily
  }
}

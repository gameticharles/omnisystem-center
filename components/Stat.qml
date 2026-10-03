import QtQuick
import qs.Commons

// One reading: a small dim label over its value.
Column {
  id: root

  property string label: ""
  property string value: ""
  property color valueColor: foreground
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  spacing: Style.space(2)
  visible: value !== ""

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.label.toUpperCase()
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.8
    elide: Text.ElideRight
  }
  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: root.value
    color: root.valueColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }
}

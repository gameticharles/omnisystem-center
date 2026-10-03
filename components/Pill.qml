import QtQuick
import qs.Commons

// A small rounded label: verified, installed, stars, reach, an update.
// `filled` washes it in its colour; otherwise only the outline is coloured.
Rectangle {
  id: pill

  property string text: ""
  property color tint: Color.accent
  property bool filled: false
  property string fontFamily: Style.font.family

  visible: text !== ""
  implicitWidth: label.implicitWidth + Style.space(12)
  implicitHeight: label.implicitHeight + Style.space(4)
  radius: height / 2
  color: filled ? Qt.rgba(tint.r, tint.g, tint.b, 0.18) : "transparent"
  border.width: 1
  border.color: Qt.rgba(tint.r, tint.g, tint.b, filled ? 0.0 : 0.55)

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: pill.text
    color: pill.tint
    font.family: pill.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}

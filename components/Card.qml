import QtQuick
import qs.Ui
import qs.Commons

// A tinted note with optional buttons underneath; the buttons are this
// item's children.
BorderSurface {
  id: root

  property string text: ""
  property color tint: Color.accent
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  default property alias buttons: buttonRow.data

  width: parent ? parent.width : 0
  height: col.implicitHeight + Style.space(16)
  color: Util.alpha(tint, 0.10)
  borderSpec: Border.flat(Util.alpha(tint, 0.6), 1)
  radius: Style.cornerRadius

  Column {
    id: col
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(10)
    spacing: Style.space(8)

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: root.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Row {
      id: buttonRow
      visible: children.length > 0
      anchors.right: parent.right
      spacing: Style.space(8)
    }
  }
}

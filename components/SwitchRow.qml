import QtQuick
import qs.Ui
import qs.Commons

// A setting with a switch: label and optional hint on the left, the switch on
// the right.
Item {
  id: root

  property string label: ""
  property string hint: ""
  property bool checked: false
  property bool interactive: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal toggled()

  width: parent ? parent.width : 0
  implicitHeight: Math.max(labels.implicitHeight, toggle.implicitHeight)
  opacity: interactive ? 1 : 0.5

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: root.hint !== ""
      textFormat: Text.PlainText
      text: root.hint
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    interactive: root.interactive
    foreground: root.foreground
    onToggled: root.toggled()
  }
}

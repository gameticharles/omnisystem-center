import QtQuick
import qs.Commons

// A thin horizontal level bar, 0..1, with an optional marker (e.g. the charge
// limit) and a pulse while `pulsing`.
Item {
  id: root

  property real value: 0
  property real marker: -1
  property color color: Color.foreground
  property color markerColor: Color.accent
  property bool pulsing: false

  implicitHeight: Style.space(8)

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: Util.alpha(root.color, 0.12)
  }

  Rectangle {
    anchors.left: track.left
    anchors.verticalCenter: track.verticalCenter
    height: track.height
    radius: track.radius
    color: root.color
    width: Math.max(track.height, track.width * Math.max(0, Math.min(1, root.value)))

    Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    SequentialAnimation on opacity {
      running: root.pulsing
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
      NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
    }
  }

  Rectangle {
    visible: root.marker > 0 && root.marker < 1
    width: Math.max(2, Style.space(2))
    height: track.height + Style.space(6)
    radius: width / 2
    color: root.markerColor
    x: track.width * root.marker - width / 2
    anchors.verticalCenter: track.verticalCenter
  }
}

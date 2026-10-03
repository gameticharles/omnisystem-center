import QtQuick
import qs.Commons

// A small line graph. Either `segments` (lists of [x, y] already in this
// item's coordinates, split where data is missing) or `points` (one list).
// Optional horizontal guide at `guideY` (a dashed line, e.g. the charge limit).
Item {
  id: root

  property var segments: []
  property var points: []
  property color color: Color.foreground
  property real lineWidth: 1.6
  property bool fill: true
  property real guideY: -1
  property color guideColor: Color.accent
  property color gridColor: Util.alpha(color, 0.10)
  property int gridLines: 3

  onSegmentsChanged: canvas.requestPaint()
  onPointsChanged: canvas.requestPaint()
  onColorChanged: canvas.requestPaint()
  onGuideYChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height
      ctx.strokeStyle = root.gridColor
      ctx.lineWidth = 1
      for (var g = 1; g <= root.gridLines; g++) {
        var gy = Math.round(h * g / (root.gridLines + 1)) + 0.5
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
      }
      var segs = root.segments && root.segments.length ? root.segments : (root.points && root.points.length ? [root.points] : [])
      for (var s = 0; s < segs.length; s++) {
        var pts = segs[s]
        if (!pts.length) continue
        if (root.fill && pts.length > 1) {
          ctx.beginPath()
          ctx.moveTo(pts[0][0], h)
          for (var i = 0; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
          ctx.lineTo(pts[pts.length - 1][0], h)
          ctx.closePath()
          ctx.fillStyle = Util.alpha(root.color, 0.14)
          ctx.fill()
        }
        ctx.beginPath()
        ctx.strokeStyle = root.color
        ctx.lineWidth = root.lineWidth
        ctx.lineJoin = "round"
        ctx.moveTo(pts[0][0], pts[0][1])
        for (var j = 1; j < pts.length; j++) ctx.lineTo(pts[j][0], pts[j][1])
        if (pts.length === 1) ctx.arc(pts[0][0], pts[0][1], 1.5, 0, Math.PI * 2)
        ctx.stroke()
      }
      if (root.guideY >= 0) {
        ctx.strokeStyle = root.guideColor
        ctx.lineWidth = 1
        ctx.setLineDash([4, 4])
        ctx.beginPath(); ctx.moveTo(0, Math.round(root.guideY) + 0.5); ctx.lineTo(w, Math.round(root.guideY) + 0.5); ctx.stroke()
      }
    }
  }
}

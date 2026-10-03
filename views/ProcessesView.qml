import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// Every process, like btop: CPU (share of one core since the last sample),
// memory, user and command, sortable, searchable, as a list or a tree.
// Clicking a row opens its details and actions. Ending, killing and pausing
// are armed by the first click and done by the second, within three seconds.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim
  readonly property color accent: Model.tabTint("processes", panel.palette, String(Color.background))

  property string query: ""
  property bool mine: false
  property bool tree: false
  property bool kernel: false
  property string sortKey: "cpu"
  property bool sortDesc: true
  property int limit: 60
  property int selected: -1
  property string armed: ""

  readonly property var pd: s.procData
  readonly property var rows: pd ? Model.processRows(pd.procs, { query: query, mine: mine, tree: tree, kernel: kernel,
                                                                      sort: sortKey, desc: sortDesc }) : []
  readonly property var shown: rows.slice(0, limit)
  readonly property var selectedProc: {
    for (var i = 0; i < rows.length; i++) if (rows[i].pid === selected) return rows[i]
    return null
  }

  function sortBy(key) {
    if (sortKey === key) sortDesc = !sortDesc
    else { sortKey = key; sortDesc = key === "cpu" || key === "mem" || key === "gpu" }
  }
  function arm(key) { armed = key; armTimer.restart() }
  // ---- keys: ↑↓ or j k move, Enter opens, / searches, x end (twice),
  // X kill (twice), p pause or resume, c copy the command, t tree, m mine.
  property int cursor: -1
  property var searchField: null
  readonly property var cursorProc: cursor >= 0 && cursor < shown.length ? shown[cursor] : null
  function handleMove(dx, dy) {
    if (dy === 0 || shown.length === 0) return false
    cursor = Math.max(0, Math.min(shown.length - 1, cursor < 0 ? 0 : cursor + dy))
    if (cursor >= shown.length - 5) loadMore()
    return true
  }
  function handleActivate() {
    var p = cursorProc
    if (!p) return
    armed = ""
    if (selected === p.pid) { selected = -1; return }
    selected = p.pid
    s.processDetail(p)
  }
  function twice(key, fn) {
    if (armed === key) { armed = ""; fn() } else arm(key)
  }
  function handleKey(t) {
    var p = cursorProc
    if (t === "/") { if (searchField) searchField.forceActiveFocus(); return true }
    if (t === "t") { tree = !tree; return true }
    if (t === "m") { mine = !mine; return true }
    if (!p) return false
    if (t === "x") { twice(p.pid + ":TERM", function() { s.processSignal(p, "TERM") }); return true }
    if (t === "X") { twice(p.pid + ":KILL", function() { s.processSignal(p, "KILL") }); return true }
    if (t === "p") { s.processSignal(p, p.state === "T" ? "CONT" : "STOP"); return true }
    if (t === "c") { s.copyText(p.cmd, "the command"); return true }
    return false
  }

  // The panel calls this near the end of the list: the next 60 rows.
  function loadMore() { if (rows.length > limit) limit += 60 }

  Timer { id: armTimer; interval: 3000; onTriggered: view.armed = "" }

  // Frozen above the list (the panel draws it between the tabs and the
  // scrolling area): the summary, the search and toggles, the column headers.
  readonly property real wPid: Style.space(58)
  readonly property real wUser: Style.space(78)
  readonly property real wMem: Style.space(72)
  readonly property real wCpu: Style.space(62)
  readonly property real wGpu: Style.space(54)
  readonly property real wName: width - wPid - wUser - wMem - wGpu - wCpu
  property Component header: Component {
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(10)
      // ------------------------------------------------------------- summary

      Item {
        width: parent.width
        implicitHeight: summaryText.implicitHeight
        Text {
          id: summaryText
          textFormat: Text.PlainText
          text: view.pd ? view.pd.summary.count + " processes · " + view.pd.summary.threads + " threads · "
                            + view.pd.summary.running + " running" : "Reading processes…"
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.6
        }
        Text {
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: view.pd ? "CPU " + Model.formatCpu(view.pd.summary.cpu) + " of " + view.pd.summary.cores * 100 + "%  ·  "
                            + Model.formatBytes(view.pd.summary.rss) : ""
          color: view.fg
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      // ------------------------------------------------------------- toolbar

      Row {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: search
          width: parent.width - toggles.width - parent.spacing
          placeholderText: "󰍉  Name, command, user or PID"
          foreground: view.fg
          accent: view.accent
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
          Component.onCompleted: { text = view.query; view.searchField = this }
          onTextChanged: if (text !== view.query) { view.query = text; view.limit = 60; view.cursor = -1 }
          Keys.onReturnPressed: view.panel.focusKeys()
          Keys.onDownPressed: { view.panel.focusKeys(); view.handleMove(0, 1) }
          onActiveFocusChanged: view.panel.textEditing = activeFocus
          Keys.onEscapePressed: { if (text) text = ""; else view.panel.focusKeys() }
        }
        Row {
          id: toggles
          spacing: Style.space(4)
          anchors.verticalCenter: search.verticalCenter
          Repeater {
            model: [
              { key: "mine", icon: "󰀄", label: "Mine", tip: "Only your own processes" },
              { key: "tree", icon: "󰙅", label: "Tree", tip: "Children under their parents" },
              { key: "kernel", icon: "󰒋", label: "Kernel", tip: "Kernel threads too" }
            ]
            Button {
              required property var modelData
              readonly property bool on: view[modelData.key]
              iconText: modelData.icon
              text: modelData.label
              tooltipText: modelData.tip
              bordered: true
              foreground: on ? view.accent : view.dim
              background: on ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14) : "transparent"
              accent: view.accent
              fontFamily: view.ff
              fontSize: Style.font.caption
              iconSize: Style.font.bodySmall
              height: search.implicitHeight
              onClicked: view[modelData.key] = !view[modelData.key]
            }
          }
        }
      }

        // Headers sort; a second click reverses.
        Row {
          id: columnHeader
          width: parent.width
          height: Style.space(22)
          Repeater {
            model: [
              { key: "pid", label: "PID", w: "wPid", right: false },
              { key: "name", label: "NAME · COMMAND", w: "wName", right: false },
              { key: "user", label: "USER", w: "wUser", right: false },
              { key: "mem", label: "MEMORY", w: "wMem", right: true },
            { key: "gpu", label: "GPU", w: "wGpu", right: true },
              { key: "cpu", label: "CPU", w: "wCpu", right: true }
            ]
            Item {
              required property var modelData
              width: view[modelData.w]
              height: columnHeader.height
              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: modelData.right ? undefined : parent.left
                anchors.right: modelData.right ? parent.right : undefined
                textFormat: Text.PlainText
                text: modelData.label + (view.sortKey === modelData.key ? (view.sortDesc ? " ▾" : " ▴") : "")
                color: view.sortKey === modelData.key ? view.accent : view.dim
                font.family: view.ff
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 0.6
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: view.sortBy(modelData.key)
              }
            }
          }
        }
    }
  }

  // Kept across tab switches and closing the panel (saved with the plugin's
  // state): what you searched, filtered, sorted and opened.
  readonly property var keptKeys: ["query", "mine", "tree", "kernel", "sortKey", "sortDesc", "limit", "selected"]
  Component.onCompleted: {
    var st = s.viewStateFor("processes")
    for (var i = 0; i < keptKeys.length; i++) if (st[keptKeys[i]] !== undefined) view[keptKeys[i]] = st[keptKeys[i]]
    if (view.selected > 0) {
      for (var j = 0; view.pd && j < view.pd.procs.length; j++) if (view.pd.procs[j].pid === view.selected) s.processDetail(view.pd.procs[j])
    }
  }
  Component.onDestruction: {
    var st = {}
    for (var i = 0; i < keptKeys.length; i++) st[keptKeys[i]] = view[keptKeys[i]]
    s.saveViewState("processes", st)
  }

  spacing: Style.space(10)

  // ----------------------------------------------------------- the table

  Column {
    width: parent.width
    spacing: 0


    Repeater {
      model: view.shown
      Column {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool isCursor: view.cursor === index
        onIsCursorChanged: if (isCursor) view.panel.ensureVisible(rowItem)
        readonly property bool open: view.selected === modelData.pid
        readonly property real share: view.pd ? Math.min(1, modelData.cpu / 100) : 0
        width: parent.width

        Item {
          width: parent.width
          height: Style.space(34)

          Rectangle {
            anchors.fill: parent
            radius: Style.space(3)
            color: rowItem.open ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.12)
                 : rowItem.isCursor ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.07)
                 : rowHover.containsMouse ? Util.alpha(view.fg, 0.05) : "transparent"
            border.width: rowItem.isCursor ? 1 : 0
            border.color: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.5)
          }
          // A faint bar behind the row: how much of one core it uses.
          Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: 2
            width: parent.width * rowItem.share
            color: view.accent
            opacity: 0.55
            visible: rowItem.share > 0.01
          }

          Row {
            anchors.fill: parent
            Text {
              width: view.wPid
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(rowItem.modelData.pid)
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Column {
              width: view.wName - Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Math.min(5, rowItem.modelData.depth) * Style.space(10)
              Text {
                width: parent.width - parent.leftPadding
                textFormat: Text.PlainText
                text: (rowItem.modelData.depth > 0 ? "└ " : "") + rowItem.modelData.name
                      + (rowItem.modelData.state === "T" ? "  󰏤" : "") + (rowItem.modelData.state === "Z" ? "  zombie" : "")
                color: rowItem.modelData.session ? view.accent : view.fg
                font.family: view.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width - parent.leftPadding
                textFormat: Text.PlainText
                text: rowItem.modelData.cmd
                color: view.dim
                font.family: view.ff
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
            Item { width: Style.space(6); height: 1 }
            Text {
              width: view.wUser
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: rowItem.modelData.user
              color: rowItem.modelData.mine ? view.fg : view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: view.wMem
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Model.formatBytes(rowItem.modelData.rss)
              color: view.fg
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Text {
              width: view.wGpu
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: typeof rowItem.modelData.gpu === "number" && rowItem.modelData.gpu > 0 ? Model.formatCpu(rowItem.modelData.gpu)
                    : (rowItem.modelData.gpuMem ? "·" : "")
              color: (rowItem.modelData.gpu || 0) >= 20 ? view.accent : view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Text {
              width: view.wCpu
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              textFormat: Text.PlainText
              text: Model.formatCpu(rowItem.modelData.cpu)
              color: rowItem.modelData.cpu >= 50 ? view.accent : view.fg
              font.family: view.ff
              font.pixelSize: Style.font.caption
              font.bold: rowItem.modelData.cpu >= 10
            }
          }

          MouseArea {
            id: rowHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              view.armed = ""
              if (rowItem.open) { view.selected = -1; return }
              view.selected = rowItem.modelData.pid
              view.s.processDetail(rowItem.modelData)
            }
          }
        }

        // ------------------------------------------------ details, actions
        Loader {
          width: parent.width
          active: rowItem.open
          visible: active
          sourceComponent: Column {
            width: rowItem.width
            spacing: Style.space(8)
            topPadding: Style.space(6)
            bottomPadding: Style.space(10)
            readonly property var p: rowItem.modelData
            readonly property var d: view.s.procDetail && view.s.procDetail.pid === p.pid ? view.s.procDetail : null

            Text {
              width: parent.width
              wrapMode: Text.WrapAnywhere
              textFormat: Text.PlainText
              text: parent.d && parent.d.cmd ? parent.d.cmd : parent.p.cmd
              color: view.fg
              font.family: view.ff
              font.pixelSize: Style.font.caption
              maximumLineCount: 4
              elide: Text.ElideRight
            }

            Grid {
              width: parent.width
              columns: 3
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(6)
              readonly property real cell: (width - columnSpacing * 2) / 3
              Stat { width: parent.cell; label: "State"; value: Model.procState(parent.parent.p.state); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Running for"; value: Model.sinceText(parent.parent.p.started, Date.now()); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Threads · nice"; value: parent.parent.p.threads + " · " + parent.parent.p.nice; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Parent"; value: String(parent.parent.p.ppid); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Memory"; value: Model.formatBytes(parent.parent.p.rss) + " · " + parent.parent.p.mem + "%"; foreground: view.fg; fontFamily: view.ff }
              Stat {
                width: parent.cell
                label: "Disk read · write"
                value: parent.parent.d && parent.parent.d.io ? Model.formatBytes(parent.parent.d.io.read_bytes) + " · " + Model.formatBytes(parent.parent.d.io.write_bytes) : ""
                foreground: view.fg; fontFamily: view.ff
              }
              Stat { width: parent.cell; label: "Open files"; value: parent.parent.d && parent.parent.d.fds !== null ? String(parent.parent.d.fds) : ""; foreground: view.fg; fontFamily: view.ff }
              Stat {
                width: parent.cell
                label: "GPU"
                value: parent.parent.p.gpuMem || parent.parent.p.gpu ? (typeof parent.parent.p.gpu === "number" ? Model.formatCpu(parent.parent.p.gpu) + " · " : "")
                       + Model.formatBytes(parent.parent.p.gpuMem || 0) + (parent.parent.p.gpuDriver ? " · " + parent.parent.p.gpuDriver : "") : ""
                foreground: view.fg; fontFamily: view.ff
              }
            }
            InfoRow { label: "Folder"; value: parent.d ? parent.d.cwd : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.s.copyText(t, "the folder") } }
            InfoRow { label: "Program"; value: parent.d ? parent.d.exe : ""; foreground: view.fg; fontFamily: view.ff; onCopyRequested: function(t) { view.s.copyText(t, "the path") } }

            Text {
              visible: parent.p.session
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "󰀪  Your desktop session depends on " + parent.p.name + ": ending it can close every window or log you out."
              color: Color.urgent
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: !parent.p.mine
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Belongs to " + parent.p.user + ": only its owner (or root) can signal it."
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }

            Flow {
              visible: parent.p.mine
              width: parent.width
              spacing: Style.space(6)
              readonly property var p: parent.p
              Repeater {
                model: [
                  { key: "TERM", icon: "󰅖", label: "End", tip: "Ask it to quit (SIGTERM)", arm: true, color: "orange" },
                  { key: "KILL", icon: "󰚌", label: "Kill", tip: "Stop it at once (SIGKILL); unsaved work is lost", arm: true, color: "red" },
                  { key: parent.p.state === "T" ? "CONT" : "STOP", icon: parent.p.state === "T" ? "󰐊" : "󰏤",
                    label: parent.p.state === "T" ? "Resume" : "Pause", tip: parent.p.state === "T" ? "Let it run again (SIGCONT)" : "Freeze it until resumed (SIGSTOP)",
                    arm: parent.p.state !== "T", color: "blue" },
                  { key: "INT", icon: "󰜺", label: "Interrupt", tip: "As Ctrl+C would (SIGINT)", arm: true, color: "yellow" },
                  { key: "HUP", icon: "󰑓", label: "Reload", tip: "Hang-up (SIGHUP): many daemons reload their settings", arm: true, color: "cyan" }
                ]
                Button {
                  required property var modelData
                  readonly property string armKey: parent.p.pid + ":" + modelData.key
                  readonly property bool isArmed: view.armed === armKey
                  readonly property color tint: Model.actionColor(modelData.key === "KILL" ? "shutdown" : modelData.key === "TERM" ? "reboot" : "hibernate",
                                                                  view.panel.palette, view.fg)
                  iconText: modelData.icon
                  text: isArmed ? modelData.label + "? Click again" : modelData.label
                  tooltipText: modelData.tip
                  bordered: true
                  foreground: isArmed ? Color.urgent : tint
                  background: isArmed ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.14) : "transparent"
                  fontFamily: view.ff
                  fontSize: Style.font.caption
                  iconSize: Style.font.bodySmall
                  verticalPadding: Style.space(4)
                  onClicked: {
                    if (modelData.arm && !isArmed) { view.arm(armKey); return }
                    view.armed = ""
                    view.s.processSignal(parent.p, modelData.key)
                  }
                }
              }
              Button {
                iconText: "󰔶"
                text: "Lower priority"
                tooltipText: "Nice +5 (now " + parent.p.nice + "): it yields the CPU to everything else"
                visible: parent.p.nice < 19
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                iconSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onClicked: view.s.processRenice(parent.p, Math.min(19, parent.p.nice + 5))
              }
              Button {
                iconText: "󰆏"
                text: "Copy"
                tooltipText: "Copy the command"
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                iconSize: Style.font.bodySmall
                verticalPadding: Style.space(4)
                onClicked: view.s.copyText(parent.p.cmd, "the command")
              }
              Repeater {
                model: [{ key: "TERM", icon: "󰙅", label: "End tree" }, { key: "KILL", icon: "󰚌", label: "Kill tree" }]
                Button {
                  required property var modelData
                  readonly property string armKey: parent.p.pid + ":tree:" + modelData.key
                  readonly property bool isArmed: view.armed === armKey
                  iconText: isArmed ? "󰀪" : modelData.icon
                  text: isArmed ? modelData.label + "? Click again" : modelData.label
                  tooltipText: modelData.label + ": this process and everything it started, children first"
                  bordered: true
                  foreground: isArmed ? Color.urgent : Model.actionColor(modelData.key === "KILL" ? "shutdown" : "reboot", view.panel.palette, view.fg)
                  background: isArmed ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.14) : "transparent"
                  fontFamily: view.ff
                  fontSize: Style.font.caption
                  iconSize: Style.font.bodySmall
                  verticalPadding: Style.space(4)
                  onClicked: {
                    if (!isArmed) { view.arm(armKey); return }
                    view.armed = ""
                    view.s.processSignalTree(parent.p, modelData.key)
                  }
                }
              }
            }
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(8)
    }

    Text {
      visible: view.rows.length > view.limit
      textFormat: Text.PlainText
      text: "Loading more… (" + (view.rows.length - view.limit) + " left)"
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
    }
    Text {
      visible: view.pd !== null && view.rows.length === 0
      textFormat: Text.PlainText
      text: "Nothing matches."
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    color: view.dim
    font.family: view.ff
    font.pixelSize: Style.font.caption
    text: "Sampled every 2 s while this tab is open. CPU is the share of one core: 250% is two and a half cores busy."
  }
}

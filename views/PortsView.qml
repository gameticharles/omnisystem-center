import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// What is listening on this machine, named by the project that runs it, with
// how far each port reaches. Dev servers lead; your other sockets and the
// system's follow. Open, copy, open a terminal where it lives, or stop it:
// stopping is armed by the first click and done by the second.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim
  readonly property color accent: Model.tabTint("ports", panel.palette, String(Color.background))

  property string filter: "dev"
  property string query: ""
  property string armed: ""
  property string selectedKey: ""

  readonly property var listeners: s.portData ? s.portData.listeners : []
  readonly property var counts: Model.portCounts(listeners)
  readonly property var groups: Model.portGroups(listeners, filter, query)

  function arm(key) { armed = key; armTimer.restart() }

  // ---- keys: ↑↓ or j k move, Enter or o opens, y copies the address, c the
  // command, t opens a terminal there, x stops (twice), X kills (twice),
  // f steps through the filters, / searches.
  property var searchField: null
  readonly property var flat: {
    var out = []
    for (var i = 0; i < groups.length; i++) out = out.concat(groups[i].rows)
    return out
  }
  function rowKey(r) { return r.proto + r.port + ":" + (r.pid || "") }
  function cursorRow() {
    for (var i = 0; i < flat.length; i++) if (rowKey(flat[i]) === selectedKey) return { row: flat[i], index: i }
    return { row: null, index: -1 }
  }
  function handleMove(dx, dy) {
    if (dy === 0 || flat.length === 0) return false
    var at = cursorRow().index
    var next = Math.max(0, Math.min(flat.length - 1, at < 0 ? 0 : at + dy))
    selectedKey = rowKey(flat[next])
    return true
  }
  function handleActivate() {
    var r = cursorRow().row
    if (r && r.http) { Qt.openUrlExternally(Model.portUrl(r)); s.closePanel() }
  }
  function twice(key, fn) {
    if (armed === key) { armed = ""; fn() } else arm(key)
  }
  function handleKey(t) {
    if (t === "/") { if (searchField) searchField.forceActiveFocus(); return true }
    if (t === "f") {
      var order = Model.PORT_FILTERS
      filter = order[(order.indexOf(filter) + 1) % order.length]
      userChose = true
      return true
    }
    var r = cursorRow().row
    if (!r) return false
    var key = rowKey(r)
    if (t === "o") { handleActivate(); return true }
    if (t === "y") { s.copyText(Model.portUrl(r), Model.portUrl(r)); return true }
    if (t === "c" && r.cmd) { s.copyText(r.cmd, "the command"); return true }
    if (t === "t" && r.cwd) { s.openTerminalIn(r.cwd); return true }
    if (t === "x" && r.mine && r.pid) { twice(key + ":TERM", function() { s.portSignal(r, "TERM") }); return true }
    if (t === "X" && r.mine && r.pid) { twice(key + ":KILL", function() { s.portSignal(r, "KILL") }); return true }
    if (t === "x" && r.container) { twice(key + ":STOP", function() { s.portStopContainer(r) }); return true }
    return false
  }

  // Frozen above the list: the summary, the bar switch, the chips and search.
  property Component header: Component {
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(10)
      Item {
        width: parent.width
        implicitHeight: Math.max(summary.implicitHeight, barSwitch.implicitHeight)
        Text {
          id: summary
          anchors.left: parent.left
          anchors.right: barToggle.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: view.s.portData ? view.counts.all + " listening · " + view.counts.dev + " dev · " + view.counts.exposed + " open to the network"
                                + (view.counts.devExposed > 0 ? "  ·  󰀪 " + view.counts.devExposed + " dev exposed" : "")
                                : "Reading ports…"
          color: view.counts.devExposed > 0 ? Color.urgent : view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.6
          elide: Text.ElideRight
        }
        // The dev-server count in the bar: on shows it always (0 too), red while
        // any dev server runs.
        Row {
          id: barToggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰒍 In the bar"
            color: view.s.barPorts ? view.fg : view.dim
            font.family: view.ff
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          ToggleSwitch {
            id: barSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: view.s.barPorts
            foreground: view.fg
            accent: view.accent
            onToggled: view.s.updateBarSettings({ barPorts: !view.s.barPorts })
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: [
            { key: "dev", label: "Dev", tip: "Servers you run: dev ports, dev runtimes, project checkouts, containers" },
            { key: "mine", label: "Mine", tip: "Every socket of yours" },
            { key: "exposed", label: "Exposed", tip: "Reachable from other machines on the network" },
            { key: "all", label: "All", tip: "Everything listening" }
          ]
          Button {
            required property var modelData
            readonly property bool on: view.filter === modelData.key
            readonly property color tint: modelData.key === "exposed" && view.counts.exposed > 0 ? Color.urgent : view.accent
            text: modelData.label + " " + view.counts[modelData.key]
            tooltipText: modelData.tip
            bordered: true
            foreground: on ? tint : view.dim
            background: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.14) : "transparent"
            accent: tint
            fontFamily: view.ff
            fontSize: Style.font.caption
            height: portSearch.implicitHeight
            onClicked: { view.filter = modelData.key; view.userChose = true }
          }
        }
        TextField {
          id: portSearch
          width: parent.width - x
          placeholderText: "󰍉  Port, project or program"
          foreground: view.fg
          accent: view.accent
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
          Component.onCompleted: { text = view.query; view.searchField = this }
          onTextChanged: if (text !== view.query) view.query = text
          Keys.onReturnPressed: view.panel.focusKeys()
          Keys.onDownPressed: { view.panel.focusKeys(); view.handleMove(0, 1) }
          onActiveFocusChanged: view.panel.textEditing = activeFocus
          Keys.onEscapePressed: { if (text) text = ""; else view.panel.focusKeys() }
        }
      }
    }
  }

  // Kept across tab switches and closing the panel (saved with the plugin's
  // state): what you searched, filtered, sorted and opened.
  readonly property var keptKeys: ["query", "filter", "userChose", "selectedKey"]
  Component.onCompleted: {
    var st = s.viewStateFor("ports")
    for (var i = 0; i < keptKeys.length; i++) if (st[keptKeys[i]] !== undefined) view[keptKeys[i]] = st[keptKeys[i]]
    autoFilter()
  }
  Component.onDestruction: {
    var st = {}
    for (var i = 0; i < keptKeys.length; i++) st[keptKeys[i]] = view[keptKeys[i]]
    s.saveViewState("ports", st)
  }
  Timer { id: armTimer; interval: 3000; onTriggered: view.armed = "" }

  // Until you pick a chip: Dev when a dev server runs, else All, rather than
  // an empty list.
  property bool userChose: false
  function autoFilter() { if (!userChose && s.portData) filter = counts.dev > 0 ? "dev" : "all" }
  Connections {
    target: view.s
    function onPortDataChanged() { view.autoFilter() }
  }

  spacing: Style.space(10)

  Repeater {
    model: view.groups
    Column {
      id: group
      required property var modelData
      width: view.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: Math.max(groupTitle.implicitHeight, termButton.implicitHeight)
        Text {
          id: groupTitle
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - termButton.width - Style.space(8)
          textFormat: Text.PlainText
          text: group.modelData.label.toUpperCase() + (group.modelData.path ? "   " + group.modelData.path.replace(/^\/home\/[^/]+/, "~") : "")
          color: group.modelData.rank === 0 ? view.accent : view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.6
          elide: Text.ElideMiddle
        }
        PanelActionButton {
          id: termButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: group.modelData.path !== ""
          iconText: "󰆍"
          tooltipText: "Open a terminal in " + group.modelData.label
          foreground: view.fg
          fontFamily: view.ff
          onClicked: view.s.openTerminalIn(group.modelData.path)
        }
      }

      Repeater {
        model: group.modelData.rows
        // Three lines: the port and what it is (with its reach), who runs it
        // and for how long, then where it listens and the command.
        Tile {
          id: row
          required property var modelData
          readonly property var r: modelData
          readonly property bool exposed: Model.portExposed(r)
          readonly property string key: r.proto + r.port + ":" + (r.pid || "")
          readonly property color reachTint: r.reach === "network" ? (r.dev ? Color.urgent : Model.actionColor("reboot", view.panel.palette, view.fg))
                                           : r.reach === "vpn" ? Model.actionColor("hibernate", view.panel.palette, view.accent)
                                           : r.reach === "containers" ? Model.actionColor("suspend", view.panel.palette, view.accent) : view.dim
          width: group.width
          height: Style.space(66)
          selected: view.selectedKey === key
          onSelectedChanged: if (selected) view.panel.ensureVisible(row)
          alert: exposed && r.dev
          tint: view.accent
          foreground: view.fg
          onClicked: view.selectedKey = selected ? "" : key

          Text {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: row.r.icon
            color: row.alert ? Color.urgent : (row.r.dev ? view.accent : view.dim)
            font.family: view.ff
            font.pixelSize: Style.font.title * 1.2
          }

          Column {
            anchors.left: icon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: actions.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              width: parent.width
              spacing: Style.space(6)
              Text {
                id: portText
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(row.r.port)
                color: row.r.dev ? view.accent : view.fg
                font.family: view.ff
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - portText.width - reachPill.width - protoPill.width - parent.spacing * 3)
                textFormat: Text.PlainText
                text: row.r.name + (row.r.guess ? "?" : "")
                color: view.fg
                font.family: view.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Pill {
                id: reachPill
                anchors.verticalCenter: parent.verticalCenter
                text: Model.reachLabel(row.r.reach)
                tint: row.reachTint
                filled: row.r.reach === "network"
                fontFamily: view.ff
              }
              Pill {
                id: protoPill
                anchors.verticalCenter: parent.verticalCenter
                text: row.r.proto === "udp" ? "UDP" : ""
                tint: view.dim
                fontFamily: view.ff
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                var parts = []
                if (row.r.project && row.r.owner !== "container") parts.push(row.r.project)
                if (row.r.container) parts.push(row.r.container.name + " · " + row.r.container.image)
                if (row.r.pid) parts.push(row.r.process + " " + row.r.pid + (row.r.user && !row.r.mine ? " · " + row.r.user : ""))
                if (row.r.started) parts.push("up " + Model.sinceText(row.r.started, Date.now()))
                if (!row.r.pid && !row.r.container) parts.push(row.r.guess ? "owner hidden: usually " + row.r.name : "owner hidden (root's socket)")
                return parts.join("  ·  ")
              }
              color: row.r.project ? view.fg : view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: row.r.addresses.join(", ") + (row.r.cmd ? "   " + row.r.cmd : "")
              maximumLineCount: 1
              color: row.alert ? Color.urgent : view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            opacity: row.hovered || row.selected || view.armed.indexOf(row.key) === 0 ? 1 : 0.5

            PanelActionButton {
              visible: row.r.http
              iconText: "󰖟"
              tooltipText: "Open " + Model.portUrl(row.r)
              foreground: view.fg
              fontFamily: view.ff
              onClicked: { Qt.openUrlExternally(Model.portUrl(row.r)); view.s.closePanel() }
            }
            PanelActionButton {
              iconText: "󰆏"
              tooltipText: "Copy " + Model.portUrl(row.r)
              foreground: view.fg
              fontFamily: view.ff
              onClicked: view.s.copyText(Model.portUrl(row.r), Model.portUrl(row.r))
            }
            // Teach it: this program is (or is not) a dev server, from now on.
            PanelActionButton {
              visible: !!row.r.process
              iconText: row.r.dev ? "󰅙" : "󰅩"
              tooltipText: row.r.dev ? "Not a dev server: never count " + row.r.process + " as one" : "A dev server: always count " + row.r.process + " as one"
              foreground: row.r.dev ? view.dim : view.accent
              fontFamily: view.ff
              onClicked: view.s.setDevProgram(row.r.process, !row.r.dev)
            }
            PanelActionButton {
              visible: row.r.cmd !== ""
              iconText: "󰘍"
              tooltipText: "Copy the command"
              foreground: view.fg
              fontFamily: view.ff
              onClicked: view.s.copyText(row.r.cmd, "the command")
            }
            PanelActionButton {
              visible: row.r.cwd !== ""
              iconText: "󰆍"
              tooltipText: "Open a terminal in " + row.r.cwd
              foreground: view.fg
              fontFamily: view.ff
              onClicked: view.s.openTerminalIn(row.r.cwd)
            }
            PanelActionButton {
              visible: row.r.mine && !!row.r.pid
              readonly property bool isArmed: view.armed === row.key + ":TERM"
              iconText: isArmed ? "󰀪" : "󰓛"
              tooltipText: isArmed ? "Click again to stop " + row.r.port : "Stop (SIGTERM): click twice"
              foreground: isArmed ? Color.urgent : Model.actionColor("reboot", view.panel.palette, view.fg)
              fontFamily: view.ff
              onClicked: {
                if (!isArmed) { view.arm(row.key + ":TERM"); return }
                view.armed = ""
                view.s.portSignal(row.r, "TERM")
              }
            }
            PanelActionButton {
              visible: row.r.mine && !!row.r.pid
              readonly property bool isArmed: view.armed === row.key + ":KILL"
              iconText: isArmed ? "󰀪" : "󰚌"
              tooltipText: isArmed ? "Click again to kill " + row.r.port : "Force kill (SIGKILL): click twice"
              foreground: isArmed ? Color.urgent : Model.actionColor("shutdown", view.panel.palette, view.fg)
              fontFamily: view.ff
              onClicked: {
                if (!isArmed) { view.arm(row.key + ":KILL"); return }
                view.armed = ""
                view.s.portSignal(row.r, "KILL")
              }
            }
            PanelActionButton {
              visible: !!row.r.container
              readonly property bool isArmed: view.armed === row.key + ":STOP"
              iconText: isArmed ? "󰀪" : "󰓛"
              tooltipText: isArmed ? "Click again to stop the container" : "Stop the container " + (row.r.container ? row.r.container.name : "") + ": click twice"
              foreground: isArmed ? Color.urgent : Model.actionColor("reboot", view.panel.palette, view.fg)
              fontFamily: view.ff
              onClicked: {
                if (!isArmed) { view.arm(row.key + ":STOP"); return }
                view.armed = ""
                view.s.portStopContainer(row.r)
              }
            }
          }
        }
      }
    }
  }

  Text {
    visible: !!view.s.portData && view.groups.length === 0
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: view.filter === "dev" ? "No dev servers running. All shows everything that listens." : "Nothing matches."
    color: view.dim
    font.family: view.ff
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    color: view.dim
    font.family: view.ff
    font.pixelSize: Style.font.caption
    text: "Refreshed every 3 s while this tab is open. A name with ? is the service that usually uses that port: as a normal user the owner of root's sockets cannot be seen."
  }
}

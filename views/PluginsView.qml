import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Model.js" as Model
import "../components"

// Omarchy plugins: what is installed (switch on or off, update, remove) and
// the marketplace (search, browse by category, install). Every change goes
// through `omarchy plugin`, run detached because its rescan closes this
// panel; a strip at the top follows it, and the panel comes back after.
Column {
  id: view

  property var panel: null
  readonly property var s: panel.service
  readonly property color fg: panel.foreground
  readonly property string ff: panel.fontFamily
  readonly property color dim: panel.dim
  readonly property color accent: Model.tabTint("plugins", panel.palette, String(Color.background))

  property string mode: "installed"
  property string filter: "all"
  property string query: ""
  property string category: "All"
  property string sort: "stars"
  property bool installableOnly: true
  property int limit: 30
  property string expanded: ""
  property string armed: ""

  readonly property var installed: s.pluginLocal || []
  readonly property var installedIds: {
    var m = {}
    for (var i = 0; i < installed.length; i++) m[installed[i].id] = true
    return m
  }
  readonly property var counts: Model.installedCounts(installed, s.pluginUpdates)
  readonly property var installedList: Model.installedRows(installed, filter, query, s.pluginUpdates)
  readonly property var catalogList: mode === "browse"
    ? Model.catalogRows(s.pluginCatalog, { query: query, category: category, sort: sort, installed: installedIds,
                                           installable: installableOnly, stats: s.pluginStats })
    : []
  readonly property var shownCatalog: catalogList.slice(0, limit)
  readonly property bool busy: !!s.pluginJob && s.pluginJob.state === "running"
  // Blue for verified, green for an update: the theme's own when it has a
  // real blue or green, else a plain one.
  readonly property color blue: Model.hueTint(panel.palette, "blue")
  readonly property color green: Model.hueTint(panel.palette, "green")

  // The marketplace rows, AuroraPulse's way: each row is only its position,
  // the entry is read from `shownItems`. Rows are only appended while the
  // list grows (the next page lands under the cards on screen, nothing is
  // rebuilt) and cleared when it becomes a different list.
  ListModel { id: catalogRows }
  property var shownIds: []
  property var shownItems: []
  function syncCatalog() {
    var next = shownCatalog
    var old = shownIds
    var grows = next.length >= old.length
    for (var i = 0; grows && i < old.length; i++) if (next[i].id !== old[i]) grows = false
    if (!grows) catalogRows.clear()
    shownItems = next
    var added = []
    for (var j = grows ? old.length : 0; j < next.length; j++) added.push({ n: j })
    if (added.length) catalogRows.append(added)
    shownIds = next.map(function(p) { return p.id })
  }
  onShownCatalogChanged: {
    syncCatalog()
    s.requestThumbs(shownCatalog.map(function(p) { return p.id }))
  }
  // ---- keys: ↑↓ or j k move, Enter opens the details, / searches, v steps
  // through Installed, Marketplace and Bar. Installed: e on or off, u update,
  // d remove (twice). Marketplace: i install (twice), p the preview large.
  // Bar: J and K move the widget down and up.
  property string cursorId: ""
  property var searchField: null
  readonly property var barFlat: {
    var b = Model.barLayout(installed)
    return b.left.concat(b.center, b.right, b.unplaced)
  }
  readonly property var keyRows: mode === "installed" ? installedList : mode === "browse" ? shownItems : barFlat
  function cursorAt() {
    for (var i = 0; i < keyRows.length; i++) if (keyRows[i].id === cursorId) return i
    return -1
  }
  function handleMove(dx, dy) {
    if (dy === 0 || keyRows.length === 0) return false
    var at = cursorAt()
    var next = Math.max(0, Math.min(keyRows.length - 1, at < 0 ? 0 : at + dy))
    cursorId = keyRows[next].id
    if (mode === "browse" && next >= keyRows.length - 4) loadMore()
    return true
  }
  function handleActivate() {
    if (!cursorId || mode === "bar") return
    expanded = expanded === cursorId ? "" : cursorId
  }
  function twice(key, fn) {
    if (armed === key) { armed = ""; fn() } else arm(key)
  }
  function handleKey(t) {
    if (t === "/") { if (searchField) searchField.forceActiveFocus(); return true }
    if (t === "v") {
      var modes = ["installed", "browse", "bar"]
      mode = modes[(modes.indexOf(mode) + 1) % modes.length]
      cursorId = ""
      return true
    }
    var at = cursorAt()
    var p = at >= 0 ? keyRows[at] : null
    if (!p) return false
    if (mode === "installed") {
      if (t === "e" && p.canDisable && !p.self && !busy) { s.runPluginJob(p.enabled ? "disable" : "enable", p.id); return true }
      if (t === "u" && p.update && !busy) { s.runPluginJob("update", p.id); return true }
      if (t === "d" && p.userPlugin && !p.self && !busy) { twice("rm:" + p.id, function() { s.runPluginJob("remove", p.id) }); return true }
    } else if (mode === "browse") {
      if (t === "i" && p.installAvailable && !p.installed && !busy) { twice("in:" + p.id, function() { s.runPluginJob("install", p.id, p.repo, Model.reviewedCommit(p)) }); return true }
      if (t === "p" && s.pluginThumbs[p.id]) { s.openPreview(p.id, p.name, ""); return true }
    } else if (mode === "bar" && p.bar && (t === "J" || t === "K")) {
      s.moveBarWidget(p.id, p.bar.section, p.bar.index + (t === "J" ? 1 : -1))
      return true
    }
    return false
  }

  // The panel calls this near the end of the list.
  function loadMore() {
    if (mode === "browse" && catalogList.length > limit) limit += 30
  }
  function arm(key) { armed = key; armTimer.restart() }
  Timer { id: armTimer; interval: 3000; onTriggered: view.armed = "" }

  // Frozen above the list: the running change, Installed or Marketplace with
  // the search, and the filters (with the count and sort in the marketplace).
  property Component header: Component {
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(10)
      // ------------------------------------------------- the running change
      Rectangle {
        visible: !!view.s.pluginJob
        width: parent.width
        height: jobColumn.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        readonly property var j: view.s.pluginJob || {}
        readonly property color tone: j.state === "failed" ? Color.urgent : view.accent
        color: Qt.rgba(tone.r, tone.g, tone.b, 0.10)
        border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.5)
        border.width: 1

        Column {
          id: jobColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          spacing: Style.space(4)
          property bool showLog: false

          Item {
            width: parent.width
            implicitHeight: jobTitle.implicitHeight
            Text {
              id: jobTitle
              textFormat: Text.PlainText
              readonly property var j: view.s.pluginJob || {}
              text: (j.state === "running" ? "󰑓  " + view.jobVerb(j.action, false) + " " + j.id + "…"
                     : j.state === "done" ? "󰄬  " + view.jobVerb(j.action, true) + " " + j.id
                     : "󰅚  Could not " + j.action + " " + j.id)
              color: j.state === "failed" ? Color.urgent : view.fg
              font.family: view.ff
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Row {
              anchors.right: parent.right
              PanelActionButton {
                iconText: jobColumn.showLog ? "󰅃" : "󰅀"
                tooltipText: jobColumn.showLog ? "Hide the output" : "Show the output"
                foreground: view.fg
                fontFamily: view.ff
                onClicked: jobColumn.showLog = !jobColumn.showLog
              }
              PanelActionButton {
                visible: !view.busy
                iconText: "󰅖"
                tooltipText: "Dismiss"
                foreground: view.fg
                fontFamily: view.ff
                onClicked: view.s.clearPluginJob()
              }
            }
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            readonly property string log: (view.s.pluginJob && view.s.pluginJob.log) || ""
            text: jobColumn.showLog ? log : log.split("\n").filter(function(l) { return l.trim() }).slice(-1).join("")
            color: view.dim
            font.family: view.ff
            font.pixelSize: Style.font.caption
            maximumLineCount: jobColumn.showLog ? 40 : 1
            elide: Text.ElideRight
          }
        }
      }

      // ------------------------------------------------ installed or browse
      Row {
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: [
            { key: "installed", icon: "󰏓", label: "Installed " + view.counts.all },
            { key: "browse", icon: "󰏗", label: "Marketplace" + (view.s.pluginCatalog.length ? " " + view.s.pluginCatalog.length : "") },
            { key: "bar", icon: "󰕮", label: "Bar" }
          ]
          Button {
            required property var modelData
            readonly property bool on: view.mode === modelData.key
            iconText: modelData.icon
            text: modelData.label
            bordered: true
            foreground: on ? view.accent : view.dim
            background: on ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14) : "transparent"
            accent: view.accent
            fontFamily: view.ff
            fontSize: Style.font.caption
            iconSize: Style.font.bodySmall
            height: pluginSearch.implicitHeight
            onClicked: { view.mode = modelData.key; view.expanded = ""; view.limit = 30 }
          }
        }
        TextField {
          id: pluginSearch
          width: parent.width - x - refreshButton.width - parent.spacing
          placeholderText: view.mode === "browse" ? "󰍉  Search the marketplace" : "󰍉  Name, id or author"
          foreground: view.fg
          accent: view.accent
          font.family: view.ff
          font.pixelSize: Style.font.bodySmall
          Component.onCompleted: { text = view.query; view.searchField = this }
          onTextChanged: if (text !== view.query) { view.query = text; view.limit = 30 }
          Keys.onReturnPressed: view.panel.focusKeys()
          Keys.onDownPressed: { view.panel.focusKeys(); view.handleMove(0, 1) }
          onActiveFocusChanged: view.panel.textEditing = activeFocus
          Keys.onEscapePressed: { if (text) text = ""; else view.panel.focusKeys() }
        }
        PanelActionButton {
          id: refreshButton
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰑐"
          tooltipText: "Check again: installed plugins, updates and the marketplace"
          foreground: view.fg
          fontFamily: view.ff
          onClicked: view.s.refreshPlugins(true)
        }
      }

      // ---------------------------------------------------------- installed
      Flow {
        visible: view.mode === "installed"
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: [
            { key: "all", label: "All" }, { key: "enabled", label: "On" }, { key: "disabled", label: "Off" },
            { key: "third", label: "Third-party" }, { key: "updates", label: "Updates" }
          ]
          Button {
            required property var modelData
            readonly property bool on: view.filter === modelData.key
            readonly property color tint: modelData.key === "updates" && view.counts.updates > 0 ? view.green : view.accent
            text: modelData.label + " " + view.counts[modelData.key]
            bordered: true
            foreground: on ? tint : view.dim
            background: on ? Qt.rgba(tint.r, tint.g, tint.b, 0.14) : "transparent"
            accent: tint
            fontFamily: view.ff
            fontSize: Style.font.caption
            verticalPadding: Style.space(3)
            onClicked: view.filter = modelData.key
          }
        }
      }

      Column {
        visible: view.mode === "browse"
        width: parent.width
        spacing: Style.space(8)
        Flow {
          width: parent.width
          spacing: Style.space(4)
          Repeater {
            model: Model.CATALOG_CATEGORIES
            Button {
              required property string modelData
              readonly property bool on: view.category === modelData
              text: modelData
              bordered: true
              foreground: on ? view.accent : view.dim
              background: on ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14) : "transparent"
              accent: view.accent
              fontFamily: view.ff
              fontSize: Style.font.caption
              verticalPadding: Style.space(3)
              onClicked: { view.category = modelData; view.limit = 30 }
            }
          }
        }
        Item {
          width: parent.width
          implicitHeight: sortRow.implicitHeight
          // Only the room left of the sort buttons, so the two never overlap.
          Text {
            anchors.left: parent.left
            anchors.right: sortRow.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: view.s.catalogLoading && !view.s.pluginCatalog.length ? "Loading…"
                  : view.catalogList.length + " plugins" + (view.s.catalogOffline ? " · offline" : "")
            color: view.dim
            font.family: view.ff
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Row {
            id: sortRow
            anchors.right: parent.right
            spacing: Style.space(4)
            Repeater {
              model: [{ key: "stars", label: "★ Stars" }, { key: "hearts", label: "♥ Loved" }, { key: "installs", label: "Installs" },
                      { key: "recent", label: "Newest" }, { key: "name", label: "A–Z" }]
              Button {
                required property var modelData
                readonly property bool on: view.sort === modelData.key
                text: modelData.label
                foreground: on ? view.accent : view.dim
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(2)
                onClicked: view.sort = modelData.key
              }
            }
            Button {
              text: view.installableOnly ? "Installable" : "All"
              tooltipText: view.installableOnly ? "Showing what `omarchy plugin add` can install; click to include manual-setup ones" : "Showing everything; click for installable only"
              foreground: view.dim
              fontFamily: view.ff
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              onClicked: view.installableOnly = !view.installableOnly
            }
          }
        }
      }
    }
  }

  // Kept across tab switches and closing the panel (saved with the plugin's
  // state): what you searched, filtered, sorted and opened.
  readonly property var keptKeys: ["mode", "filter", "query", "category", "sort", "installableOnly", "limit", "expanded"]
  Component.onCompleted: {
    var st = s.viewStateFor("plugins")
    for (var i = 0; i < keptKeys.length; i++) if (st[keptKeys[i]] !== undefined) view[keptKeys[i]] = st[keptKeys[i]]
  }
  Component.onDestruction: {
    var st = {}
    for (var i = 0; i < keptKeys.length; i++) st[keptKeys[i]] = view[keptKeys[i]]
    s.saveViewState("plugins", st)
  }

  function catalogEntry(id) {
    var c = s.pluginCatalog
    for (var i = 0; i < c.length; i++) if (c[i].id === id) return c[i]
    return null
  }
  function kindIcon(kinds) {
    var k = (kinds || []).join(" ").toLowerCase()
    if (k.indexOf("bar-widget") >= 0 || k.indexOf("bar widget") >= 0) return "󰕮"
    if (k.indexOf("panel") >= 0) return "󰕰"
    if (k.indexOf("overlay") >= 0) return "󰍹"
    if (k.indexOf("service") >= 0) return "󰒓"
    return "󰐱"
  }
  function jobVerb(action, done) {
    var v = { install: ["Installing", "Installed"], remove: ["Removing", "Removed"], update: ["Updating", "Updated"],
              enable: ["Turning on", "Turned on"], disable: ["Turning off", "Turned off"] }[action] || [action, action]
    return done ? v[1] : v[0]
  }

  spacing: Style.space(10)

  Repeater {
    model: view.mode === "installed" ? view.installedList : []
    Column {
      id: plug
      required property var modelData
      readonly property var p: modelData
      readonly property bool open: view.expanded === p.id
      width: view.width
      spacing: Style.space(6)

      // Three lines beside a preview: the name with its marks, what it does,
      // then its id, author, kind and commit. The preview enlarges on a click;
      // anywhere else opens the details below.
      Tile {
        width: parent.width
        height: Style.space(76) + (plug.open && plugDetails.item ? plugDetails.item.implicitHeight : 0)
        hitHeight: Style.space(76)
        selected: plug.open
        focused: view.cursorId === plug.p.id
        onFocusedChanged: if (focused) view.panel.ensureVisible(plug)
        tint: view.accent
        foreground: view.fg
        onClicked: { view.cursorId = plug.p.id; view.expanded = plug.open ? "" : plug.p.id }

        Item {
          width: parent.width
          height: Style.space(76)

          Rectangle {
            id: plugThumb
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(100)
            height: Style.space(56)
            radius: Style.space(4)
            color: Util.alpha(view.fg, 0.06)
            border.width: 1
            border.color: Util.alpha(view.fg, 0.10)
            clip: true
            readonly property string file: plug.p.preview || view.s.pluginThumbs[plug.p.id] || ""
            Image {
              anchors.fill: parent
              anchors.margins: 1
              visible: plugThumb.file !== ""
              source: plugThumb.file ? "file://" + plugThumb.file : ""
              sourceSize.width: 220
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            Text {
              visible: plugThumb.file === ""
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: view.kindIcon(plug.p.kinds)
              color: plug.p.enabled ? view.accent : view.dim
              font.family: view.ff
              font.pixelSize: Style.font.title * 1.3
            }
            MouseArea {
              anchors.fill: parent
              enabled: plugThumb.file !== ""
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: view.s.openPreview(plug.p.id, plug.p.name, plug.p.preview)
            }
          }

          Column {
            anchors.left: plugThumb.right
            anchors.leftMargin: Style.space(12)
            anchors.right: plugSwitch.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Row {
              width: parent.width
              spacing: Style.space(6)
              Text {
                id: plugName
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - plugPills.width - parent.spacing)
                textFormat: Text.PlainText
                text: plug.p.name
                color: plug.p.enabled ? view.fg : view.dim
                font.family: view.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Row {
                id: plugPills
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Pill { text: plug.p.version || ""; tint: view.dim; fontFamily: view.ff }
                Pill { text: plug.p.update ? "󰚰 update" : ""; tint: view.green; filled: true; fontFamily: view.ff }
                Pill { text: plug.p.firstParty ? "Omarchy" : ""; tint: view.dim; fontFamily: view.ff }
                Pill { text: plug.p.git && plug.p.git.dirty ? "edited" : ""; tint: Model.actionColor("reboot", view.panel.palette, view.fg); fontFamily: view.ff }
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: [plug.p.id, plug.p.author ? "by " + plug.p.author : ""].filter(function(x) { return x }).join("  ·  ")
              color: view.fg
              opacity: plug.p.enabled ? 0.85 : 0.6
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: [(plug.p.kinds || []).join(", "), plug.p.clonedFrom ? "replaces " + plug.p.clonedFrom : "",
                     plug.p.license, plug.p.git ? plug.p.git.branch + "@" + Model.shortSha(plug.p.git.head) : ""].filter(function(x) { return x }).join("  ·  ")
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          ToggleSwitch {
            id: plugSwitch
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            checked: plug.p.enabled
            busy: view.busy && view.s.pluginJob.id === plug.p.id
            interactive: !view.busy && plug.p.canDisable && !plug.p.self
            foreground: view.fg
            accent: view.accent
            onToggled: view.s.runPluginJob(plug.p.enabled ? "disable" : "enable", plug.p.id)
          }
        }

        Loader {
          id: plugDetails
          y: Style.space(76)
          width: parent.width
          active: plug.open
          visible: active
          sourceComponent: Column {
            width: plug.width
            spacing: Style.space(8)
            leftPadding: Style.space(6)
            rightPadding: Style.space(6)
            bottomPadding: Style.space(8)
            readonly property var p: plug.p
            readonly property var c: view.catalogEntry(p.id)
            property bool showSettings: false

            Text {
              visible: !!parent.p.description
              width: parent.width - parent.leftPadding * 2
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: parent.p.description
              color: view.fg
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Grid {
              width: parent.width - parent.leftPadding * 2
              columns: 3
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(6)
              readonly property real cell: (width - columnSpacing * 2) / 3
              Stat { width: parent.cell; label: "Id"; value: parent.parent.p.id; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Author"; value: parent.parent.p.author; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Kind"; value: (parent.parent.p.kinds || []).join(", "); foreground: view.fg; fontFamily: view.ff }
              Stat {
                width: parent.cell
                label: "Commit"
                value: parent.parent.p.git ? parent.parent.p.git.branch + " · " + Model.shortSha(parent.parent.p.git.head) + (parent.parent.p.git.dirty ? " · edited" : "") : ""
                foreground: view.fg; fontFamily: view.ff
              }
              Stat { width: parent.cell; label: "License"; value: parent.parent.p.license; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Stars"; value: parent.parent.c && parent.parent.c.stars ? "★ " + Model.formatStars(parent.parent.c.stars) : ""; foreground: view.fg; fontFamily: view.ff }
            }
            InfoRow {
              width: parent.width - parent.leftPadding * 2
              label: "Folder"
              value: parent.p.folder.replace(/^\/home\/[^/]+/, "~")
              foreground: view.fg; fontFamily: view.ff
              onCopyRequested: function(t) { view.s.copyText(parent.p.folder, "the folder") }
            }
            Text {
              visible: parent.p.git && parent.p.git.dirty
              width: parent.width - parent.leftPadding * 2
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "This checkout has local edits: an update may refuse to run until they are committed or undone."
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Flow {
              width: parent.width - parent.leftPadding * 2
              spacing: Style.space(6)
              readonly property var p: parent.p
              Button {
                visible: parent.p.update
                iconText: "󰚰"
                text: "Update"
                tooltipText: "omarchy plugin update " + parent.p.id
                enabled: !view.busy
                bordered: true
                foreground: Model.actionColor("suspend", view.panel.palette, view.accent)
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: view.s.runPluginJob("update", parent.p.id)
              }
              Button {
                visible: parent.p.userPlugin && !parent.p.self
                readonly property bool isArmed: view.armed === "rm:" + parent.p.id
                iconText: isArmed ? "󰀪" : "󰆴"
                text: isArmed ? "Remove? Click again" : "Remove"
                tooltipText: "Deletes the plugin's folder (omarchy plugin remove)"
                enabled: !view.busy
                bordered: true
                foreground: isArmed ? Color.urgent : Model.actionColor("shutdown", view.panel.palette, view.fg)
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: {
                  if (!isArmed) { view.arm("rm:" + parent.p.id); return }
                  view.armed = ""
                  view.s.runPluginJob("remove", parent.p.id)
                }
              }
              Button {
                visible: /^https:\/\//.test(parent.p.homepage)
                iconText: "󰊤"
                text: "Repository"
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: { Qt.openUrlExternally(parent.p.homepage.replace(/\.git$/, "")); view.s.closePanel() }
              }
              Button {
                visible: !!parent.parent.c
                iconText: "󰏗"
                text: "Marketplace page"
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: { Qt.openUrlExternally("https://plugins.omarchy.org/plugin.html?id=" + encodeURIComponent(parent.p.id)); view.s.closePanel() }
              }
              Button {
                visible: parent.p.folder !== ""
                iconText: "󰆍"
                text: "Terminal"
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: view.s.openTerminalIn(parent.p.folder)
              }
              Button {
                visible: (parent.p.schema || []).length > 0
                readonly property bool on: parent.parent.showSettings
                iconText: "󰒓"
                text: "Bar settings"
                tooltipText: parent.p.bar ? "This widget's settings, written with omarchy bar set" : "Put it in the bar (Bar view) to change its settings"
                bordered: true
                foreground: on ? view.accent : view.fg
                background: on ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14) : "transparent"
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: parent.parent.showSettings = !parent.parent.showSettings
              }
            }

            // What the update brings, before it is applied.
            Column {
              readonly property var ch: view.s.pluginChanges[parent.p.id]
              visible: parent.p.update
              width: parent.width - parent.leftPadding * 2
              spacing: Style.space(4)
              Button {
                visible: !parent.ch
                iconText: "󰋼"
                text: "What's new in the update"
                tooltipText: "The commits and files it brings, from GitHub; nothing is downloaded into the plugin"
                bordered: true
                foreground: view.green
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: view.s.loadPluginChanges(parent.parent.p.id)
              }
              Text {
                visible: !!parent.ch
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: !parent.ch ? "" : parent.ch.loading ? "Asking GitHub…"
                      : !parent.ch.ok ? "No preview: " + parent.ch.error + "."
                      : parent.ch.behind + " new " + (parent.ch.behind === 1 ? "commit" : "commits") + " (" + parent.ch.from + " → " + parent.ch.to + "), "
                        + parent.ch.files.length + " files changed"
                color: parent.ch && parent.ch.ok === false ? view.dim : view.green
                font.family: view.ff
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Repeater {
                model: parent.ch && parent.ch.ok ? parent.ch.commits.slice(0, 12) : []
                Text {
                  required property var modelData
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.sha + "  " + modelData.date + "  " + modelData.message
                  color: view.fg
                  font.family: view.ff
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
              Text {
                visible: !!parent.ch && parent.ch.ok && parent.ch.files.length > 0
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: !parent.ch || !parent.ch.ok ? "" : "Files: " + parent.ch.files.slice(0, 12).map(function(f) {
                  return f.name + " (+" + f.added + " −" + f.removed + ")" }).join(", ") + (parent.ch.files.length > 12 ? ", …" : "")
                color: view.dim
                font.family: view.ff
                font.pixelSize: Style.font.caption
              }
            }

            // Its bar settings, from its own manifest, written as you change them.
            SettingsForm {
              visible: parent.showSettings
              width: parent.width - parent.leftPadding * 2
              schema: parent.p.schema || []
              values: parent.p.values || ({})
              foreground: view.fg
              accent: view.accent
              fontFamily: view.ff
              panel: view.panel
              enabled: !!parent.p.bar
              opacity: parent.p.bar ? 1 : 0.5
              onChanged: function(key, value) { view.s.setPluginSetting(parent.p.id, key, value) }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ bar layout
  // The bar as it is laid out: each section in order, with up and down to
  // reorder and L / C / R to move a widget to another section; then the
  // enabled widgets that are in no section, to put in one.
  Column {
    visible: view.mode === "bar"
    width: parent.width
    spacing: Style.space(12)
    readonly property var layout: Model.barLayout(view.installed)

    Repeater {
      model: ["left", "center", "right", "unplaced"]
      Column {
        id: barSection
        required property string modelData
        readonly property var items: parent.layout[modelData] || []
        visible: modelData !== "unplaced" || items.length > 0
        width: parent.width
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: (barSection.modelData === "unplaced" ? "ENABLED, NOT IN THE BAR" : barSection.modelData.toUpperCase()) + " · " + barSection.items.length
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.6
        }
        Text {
          visible: barSection.items.length === 0
          textFormat: Text.PlainText
          text: "Nothing here."
          color: view.dim
          font.family: view.ff
          font.pixelSize: Style.font.caption
        }
        Repeater {
          model: barSection.items.length
          Tile {
            id: barRow
            required property int index
            readonly property var p: barSection.items[index] || ({})
            width: barSection.width
            height: Style.space(44)
            tint: view.accent
            foreground: view.fg
            selected: p.self === true
            focused: view.cursorId === p.id
            onFocusedChanged: if (focused) view.panel.ensureVisible(barRow)
            onClicked: { view.mode = "installed"; view.expanded = p.id; view.cursorId = p.id }

            Text {
              id: barIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: barSection.modelData === "unplaced" ? "󰐕" : String((barRow.p.bar ? barRow.p.bar.index : 0) + 1)
              color: view.accent
              font.family: view.ff
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Column {
              anchors.left: barIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: barActions.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: barRow.p.name || barRow.p.id || ""
                color: view.fg
                font.family: view.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: barRow.p.id || ""
                color: view.dim
                font.family: view.ff
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            Row {
              id: barActions
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              PanelActionButton {
                visible: barSection.modelData !== "unplaced" && barRow.index > 0
                iconText: "󰁝"
                tooltipText: "Move up (towards the start of the section)"
                foreground: view.fg
                fontFamily: view.ff
                onClicked: view.s.moveBarWidget(barRow.p.id, barSection.modelData, barRow.index - 1)
              }
              PanelActionButton {
                visible: barSection.modelData !== "unplaced" && barRow.index < barSection.items.length - 1
                iconText: "󰁅"
                tooltipText: "Move down (towards the end of the section)"
                foreground: view.fg
                fontFamily: view.ff
                onClicked: view.s.moveBarWidget(barRow.p.id, barSection.modelData, barRow.index + 1)
              }
              Repeater {
                model: ["left", "center", "right"]
                PanelActionButton {
                  required property string modelData
                  visible: modelData !== barSection.modelData
                  iconText: modelData === "left" ? "L" : modelData === "center" ? "C" : "R"
                  tooltipText: (barSection.modelData === "unplaced" ? "Put it in the " : "Move it to the ") + modelData + " section"
                  foreground: view.fg
                  fontFamily: view.ff
                  onClicked: {
                    if (barSection.modelData === "unplaced") view.s.putBarWidget(barRow.p.id, modelData)
                    else view.s.moveBarWidget(barRow.p.id, modelData, 999)
                  }
                }
              }
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Moves go through omarchy bar move and put; the bar updates at once. Click a widget for its details and settings."
      color: view.dim
      font.family: view.ff
      font.pixelSize: Style.font.caption
    }
  }

  // -------------------------------------------------------- marketplace
  Column {
    visible: view.mode === "browse"
    width: parent.width
    spacing: Style.space(8)

    // While the marketplace downloads for the first time (a few MB, once).
    Column {
      visible: view.s.catalogLoading && view.s.pluginCatalog.length === 0
      width: parent.width
      spacing: Style.space(6)
      topPadding: Style.space(24)
      bottomPadding: Style.space(24)
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: "󰇚  Loading the marketplace…"
        color: view.fg
        font.family: view.ff
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "The first time, a few MB come from plugins.omarchy.org; after that it opens from the copy here and is checked again every ten minutes."
        color: view.dim
        font.family: view.ff
        font.pixelSize: Style.font.caption
      }
    }

    Repeater {
      model: catalogRows
      // A card: a preview (click it to see it large), the name with its
      // marks, who made it and what kind, and what it does. A click anywhere
      // else opens the details inside the same card.
      Tile {
        id: card
        required property int n
        readonly property var p: view.shownItems[n] || ({})
        readonly property bool open: view.expanded === p.id
        readonly property string thumb: view.s.pluginThumbs[p.id] || ""
        width: view.width
        height: cardHead.height + (open && details.item ? details.item.implicitHeight : 0)
        hitHeight: cardHead.height
        selected: open
        focused: view.cursorId === card.p.id
        onFocusedChanged: if (focused) view.panel.ensureVisible(card)
        tint: view.accent
        foreground: view.fg
        onClicked: { view.cursorId = card.p.id; view.expanded = card.open ? "" : card.p.id }

        Item {
          id: cardHead
          width: parent.width
          height: Style.space(96)

          Rectangle {
            id: thumbBox
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(142)
            height: Style.space(80)
            radius: Style.space(4)
            color: Util.alpha(view.fg, 0.06)
            border.width: 1
            border.color: thumbArea.containsMouse ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.7) : Util.alpha(view.fg, 0.10)
            clip: true
            Image {
              anchors.fill: parent
              anchors.margins: 1
              visible: card.thumb !== ""
              source: card.thumb ? "file://" + card.thumb : ""
              sourceSize.width: 300
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
            }
            Text {
              visible: card.thumb === ""
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: (card.p.name || "?").slice(0, 2).toUpperCase()
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Rectangle {
              visible: thumbArea.containsMouse && card.thumb !== ""
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(4)
              width: zoomGlyph.implicitWidth + Style.space(8)
              height: zoomGlyph.implicitHeight + Style.space(2)
              radius: height / 2
              color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.8)
              Text {
                id: zoomGlyph
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰍉"
                color: view.fg
                font.family: view.ff
                font.pixelSize: Style.font.caption
              }
            }
            MouseArea {
              id: thumbArea
              anchors.fill: parent
              enabled: card.thumb !== ""
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: view.s.openPreview(card.p.id, card.p.name, "")
            }
          }

          Column {
            anchors.left: thumbBox.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)

            Row {
              width: parent.width
              spacing: Style.space(6)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - cardPills.width - parent.spacing)
                textFormat: Text.PlainText
                text: card.p.name
                color: view.fg
                font.family: view.ff
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }
              Row {
                id: cardPills
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Pill { text: card.p.stars ? "★ " + Model.formatStars(card.p.stars) : ""; tint: Model.actionColor("reboot", view.panel.palette, view.accent); filled: true; fontFamily: view.ff }
                Pill { text: card.p.hearts ? "♥ " + Model.formatCount(card.p.hearts) : ""; tint: Model.actionColor("shutdown", view.panel.palette, view.accent); filled: true; fontFamily: view.ff }
                Pill { text: card.p.verificationStatus === "verified" ? "󰄬 verified" : ""; tint: view.blue; filled: true; fontFamily: view.ff }
                Pill { text: card.p.installed ? "installed" : ""; tint: view.accent; filled: true; fontFamily: view.ff }
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: [card.p.author, card.p.category, card.p.kind, card.p.version ? "v" + card.p.version : ""].filter(function(x) { return x }).join("  ·  ")
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: [card.p.views ? "󰈈 " + Model.formatCount(card.p.views) + " views" : "",
                     card.p.installs ? "󰇚 " + Model.formatCount(card.p.installs) + " installs" : "",
                     card.p.repositoryUpdatedAt ? "updated " + String(card.p.repositoryUpdatedAt).slice(0, 10) : ""].filter(function(x) { return x }).join("  ·  ")
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Loader {
          id: details
          y: cardHead.height
          width: parent.width
          active: card.open
          visible: active
          sourceComponent: Column {
            width: card.width
            spacing: Style.space(8)
            leftPadding: Style.space(12)
            rightPadding: Style.space(12)
            bottomPadding: Style.space(12)
            readonly property var p: card.p
            readonly property bool moved: Model.movedSinceReview(p)

            Text {
              visible: String(parent.p.description || "") !== ""
              width: parent.width - parent.leftPadding * 2
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: parent.p.description || ""
              color: view.fg
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Grid {
              width: parent.width - parent.leftPadding * 2
              columns: 3
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(6)
              readonly property real cell: (width - columnSpacing * 2) / 3
              Stat { width: parent.cell; label: "Version"; value: parent.parent.p.version || ""; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "License"; value: parent.parent.p.license || ""; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Updated"; value: String(parent.parent.p.repositoryUpdatedAt || parent.parent.p.addedAt || "").slice(0, 10); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Status"; value: (parent.parent.p.status || "") + (parent.parent.p.verificationStatus ? " · " + parent.parent.p.verificationStatus : ""); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Id"; value: parent.parent.p.id; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Reviewed"; value: Model.shortSha(parent.parent.p.upstreamValidatedCommit || parent.parent.p.listingValidatedCommit); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Hearts"; value: "♥ " + parent.parent.p.hearts; foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Views"; value: Model.formatCount(parent.parent.p.views); foreground: view.fg; fontFamily: view.ff }
              Stat { width: parent.cell; label: "Installs"; value: Model.formatCount(parent.parent.p.installs); foreground: view.fg; fontFamily: view.ff }
            }
            Text {
              visible: parent.moved
              width: parent.width - parent.leftPadding * 2
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "󰀪  The repository has moved on since its last review (" + Model.shortSha(parent.p.upstreamValidatedCommit || parent.p.listingValidatedCommit)
                    + " → " + Model.shortSha(parent.p.upstreamObservedCommit) + "). Install takes the reviewed commit; the newest code is a separate choice."
              color: Model.actionColor("reboot", view.panel.palette, view.fg)
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: !parent.p.installAvailable && !!parent.p.installNote
              width: parent.width - parent.leftPadding * 2
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: parent.p.installNote || ""
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: parent.p.installAvailable && !parent.p.installed
              width: parent.width - parent.leftPadding * 2
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "A plugin runs inside the shell with your rights. Read its code before you install it."
              color: view.dim
              font.family: view.ff
              font.pixelSize: Style.font.caption
            }
            Flow {
              width: parent.width - parent.leftPadding * 2
              spacing: Style.space(6)
              readonly property var p: parent.p
              Button {
                visible: parent.p.installAvailable && !parent.p.installed
                readonly property bool isArmed: view.armed === "in:" + parent.p.id
                readonly property string pin: Model.reviewedCommit(parent.p)
                iconText: isArmed ? "󰀪" : "󰇚"
                text: isArmed ? "Install? Click again" : (pin ? "Install reviewed " + Model.shortSha(pin) : "Install")
                tooltipText: pin ? "The exact commit the marketplace reviewed: added off, checked out at " + Model.shortSha(pin) + ", verified, then enabled"
                                 : "omarchy plugin add " + parent.p.repo + " --enable (the marketplace lists no reviewed commit)"
                enabled: !view.busy
                bordered: true
                foreground: isArmed ? view.accent : Model.actionColor("suspend", view.panel.palette, view.accent)
                background: isArmed ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.14) : "transparent"
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: {
                  if (!isArmed) { view.arm("in:" + parent.p.id); return }
                  view.armed = ""
                  view.s.runPluginJob("install", parent.p.id, parent.p.repo, pin)
                }
              }
              // The newest code, past the review: a separate, plain choice.
              Button {
                visible: parent.p.installAvailable && !parent.p.installed && Model.movedSinceReview(parent.p)
                readonly property bool isArmed: view.armed === "new:" + parent.p.id
                iconText: isArmed ? "󰀪" : "󰇚"
                text: isArmed ? "Unreviewed code: click again" : "Install newest (unreviewed)"
                tooltipText: "omarchy plugin add " + parent.p.repo + " --enable: the repository as it is now, " + Model.shortSha(parent.p.upstreamObservedCommit)
                enabled: !view.busy
                bordered: true
                foreground: isArmed ? Color.urgent : view.dim
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: {
                  if (!isArmed) { view.arm("new:" + parent.p.id); return }
                  view.armed = ""
                  view.s.runPluginJob("install", parent.p.id, parent.p.repo, "")
                }
              }
              Button {
                visible: /^https:\/\//.test(parent.p.repo || "")
                iconText: "󰊤"
                text: "Repository"
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: { Qt.openUrlExternally(parent.p.repo); view.s.closePanel() }
              }
              Button {
                iconText: "󰏗"
                text: "Marketplace page"
                bordered: true
                foreground: view.fg
                fontFamily: view.ff
                fontSize: Style.font.caption
                verticalPadding: Style.space(4)
                onClicked: { Qt.openUrlExternally("https://plugins.omarchy.org/plugin.html?id=" + encodeURIComponent(parent.p.id)); view.s.closePanel() }
              }
            }
          }
        }
      }
    }

    Text {
      visible: view.catalogList.length > view.limit
      textFormat: Text.PlainText
      text: "Loading more… (" + (view.catalogList.length - view.limit) + " left)"
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
    text: view.mode === "installed"
      ? "Switching a plugin on or off, updating and removing all go through omarchy plugin; the shell reloads its plugins after each, so this panel closes and comes back."
      : "From plugins.omarchy.org, checked again after ten minutes. Installing runs omarchy plugin add with --enable."
  }
}

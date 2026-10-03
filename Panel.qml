import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Ui
import qs.Commons
import "lib/Model.js" as Model
import "components"
import "views"

// The OmniSystem Center bar widget. Omarchy builds one per monitor, so this
// file only renders: state and every action live in Service.qml, which exists
// once. Replaces the built-in Power widget (manifest clonedFrom), so it also
// answers to `omarchy.power`.
//
// The power controls sit at the bottom of every tab. On a laptop the battery
// leads and the gadgets come second; on a desktop the gadgets lead.
Panel {
  id: root
  manageIpc: false

  // ------------------------------------------------------------- service

  property var service: null

  function bindService() {
    if (service) return
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    var s = host.serviceFor("omnisystem-center")
    if (!s) return
    service = s
    service.applySettings(settings)
  }

  onBarChanged: bindService()
  onSettingsChanged: if (service) service.applySettings(settings)
  Component.onCompleted: bindService()

  Timer {
    interval: 500
    repeat: true
    running: !root.service
    onTriggered: root.bindService()
  }

  readonly property bool ready: !!service
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property bool hasBattery: ready && service.hasBattery
  // The theme's palette (accent, red, yellow, green, blue, …), read by the
  // service from the current theme's colors.toml.
  readonly property var palette: ready ? service.palette : ({ accent: Color.accent, red: Color.urgent })
  function actionColor(key) { return Model.actionColor(key, palette, foreground) }

  // ------------------------------------------------------------------ tabs

  property string tab: "overview"
  readonly property var tabs: {
    var names = ["overview"]
    if (hasBattery) names.push("care", "insights")
    if (!ready || service.energyMeterEnabled) names.push("energy")
    if (!ready || service.systemMonitorEnabled) names.push("system")
    if (!ready || service.processesTab) names.push("processes")
    if (!ready || service.portsTab) names.push("ports")
    if (!ready || service.pluginsTab) names.push("plugins")
    names.push("controls", "settings")
    return names.map(function(n) { return Model.tabMeta(n) })
  }

  function hasTab(value) {
    for (var i = 0; i < tabs.length; i++) if (tabs[i].value === value) return true
    return false
  }

  function selectTab(value) {
    if (hasTab(value)) tab = value
  }

  function cycleTab(direction) {
    var i = 0
    for (var k = 0; k < tabs.length; k++) if (tabs[k].value === tab) i = k
    tab = tabs[(i + direction + tabs.length) % tabs.length].value
  }

  // The view on screen follows `shownTab`, which moves only after the old
  // tab's scroll position is saved, so every tab comes back where you left it.
  property string shownTab: ""

  function rememberScroll() {
    var flick = scrollArea.contentItem
    if (service && shownTab && flick && flick.contentY !== undefined) service.saveScroll(shownTab, flick.contentY)
  }

  function showTab(value) {
    if (shownTab === value) return
    rememberScroll()
    shownTab = value
    scrollRestore.target = service ? service.scrollFor(value) : 0
    scrollRestore.tries = 0
    scrollTo(0)
    if (scrollRestore.target > 0) scrollRestore.restart()
  }

  // Lazy loading: near the end of the list, the tab appends its next rows.
  Connections {
    target: scrollArea.contentItem
    function onContentYChanged() { root.maybeLoadMore() }
    function onContentHeightChanged() { root.maybeLoadMore() }
  }
  function maybeLoadMore() {
    var v = viewLoader.item
    var flick = scrollArea.contentItem
    if (!v || typeof v.loadMore !== "function" || !flick || flick.contentY === undefined) return
    if (flick.contentY + flick.height >= column.implicitHeight - Style.space(320)) v.loadMore()
  }

  // The content grows as its data arrives: try again until it is tall enough.
  Timer {
    id: scrollRestore
    property real target: 0
    property int tries: 0
    interval: 120
    repeat: true
    onTriggered: {
      var flick = scrollArea.contentItem
      var max = flick ? Math.max(0, column.implicitHeight - flick.height) : 0
      root.scrollTo(Math.min(target, max))
      tries++
      if (max >= target || tries >= 20) stop()
    }
  }

  onTabChanged: {
    if (!service) return
    service.systemViewOpen = opened && tab === "system"
    service.energyViewOpen = opened && tab === "energy"
    service.processesViewOpen = opened && tab === "processes"
    service.portsViewOpen = opened && tab === "ports"
    service.pluginsViewOpen = opened && tab === "plugins"
    if (opened) {
      service.rememberTab(tab)
      showTab(tab)
    }
  }

  Connections {
    target: root.service
    function onTabRequestChanged() { root.selectTab(root.service.requestedTab) }
  }

  onOpenedChanged: {
    if (!service) return
    if (opened) {
      // A tab asked for over IPC while the panel was closed wins.
      var start = service.tabRequestPending ? service.requestedTab : service.initialTab()
      service.tabRequestPending = false
      tab = hasTab(start) ? start : "overview"
      service.panelOpened()
      showTab(tab)
      service.systemViewOpen = tab === "system"
      service.energyViewOpen = tab === "energy"
      service.processesViewOpen = tab === "processes"
      service.portsViewOpen = tab === "ports"
      service.pluginsViewOpen = tab === "plugins"
    } else {
      pendingAction = null
      scrollRestore.stop()
      showTab("")
      service.panelClosed()
    }
  }

  // ---------------------------------------------------------------- bar

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property string glyph: {
    if (!service) return Model.POWER_ICON
    if (service.criticalPending) return "󰂃"
    return Model.barIcon(service.hasBattery, service.batteryGlyph, service.lowestGadget)
  }
  readonly property var energyBits: !service ? ({}) : ({
    draw: service.drawWatts,
    todayKwh: service.energyLive ? service.energyLive.today_kwh : undefined,
    todayCost: service.energyLive ? service.energyLive.today_cost : ""
  })
  readonly property string barText: {
    if (!service || vertical) return ""
    if (service.hasBattery || Model.usesEnergy(service.barLabelMode))
      return Model.barLabel(service.barLabelMode, service.hasBattery ? service.level : -1, service.watts, service.flowing,
                            energyBits, service.showPercent)
    var g = service.lowestGadget
    return g && !g.offline && service.barLabelMode !== "none" ? g.level + "%" : ""
  }
  readonly property string gpuText: !service || vertical ? "" : Model.gpuBadges(service.gpus, service.barGpu, service.barGpuValue)
  readonly property var portsBadge: !service || vertical ? ({ text: "", active: false })
    : Model.portsBadge(service.portData ? service.portData.listeners : [], service.barPorts)
  readonly property bool urgent: !!service && (service.criticalPending || service.isLow || service.energyHigh)
  readonly property string tooltip: {
    if (!service) return "Power"
    var s = service
    var lines = []
    if (s.hasBattery) {
      var line = s.level + "% · " + s.mode
      if (s.timeText) line += " · " + s.timeText + (s.onBattery ? " left" : " to full")
      if (s.flowing) line += " · " + Model.formatWatts(s.watts)
      lines.push(line)
    }
    if (s.drawWatts >= 0) lines.push("Drawing " + Model.formatWatts(s.drawWatts) + (s.onBattery ? " from the battery" : " at the socket"))
    for (var g = 0; g < s.gpus.length; g++) {
      var line2 = Model.gpuLine(s.gpus[g])
      if (line2) lines.push(line2)
    }
    if (s.portData) {
      var pc = Model.portCounts(s.portData.listeners)
      if (pc.dev > 0) lines.push(pc.dev + " dev " + (pc.dev === 1 ? "server" : "servers") + " listening"
                                 + (pc.devExposed > 0 ? ", " + pc.devExposed + " open to the network" : ""))
    }
    if (s.energyLive && typeof s.energyLive.today_kwh === "number")
      lines.push("Today " + Model.formatKwh(s.energyLive.today_kwh) + (s.energyLive.today_cost ? " · " + s.energyLive.today_cost : ""))
    if (s.activeProfile) lines.push("Profile: " + Model.profileLabel(s.activeProfile))
    if (s.keepAwake) lines.push("Keeping awake")
    if (s.timerActive) lines.push(Model.profileLabel(s.store.timer.action) + " in " + Model.formatCountdown(s.timerLeft))
    for (var i = 0; i < s.gadgets.length; i++) lines.push(Model.gadgetLine(s.gadgets[i]))
    return lines.join("\n")
  }

  implicitWidth: (button.item ? button.item.implicitWidth : 0) + (portsButton.visible ? portsButton.implicitWidth : 0)
  implicitHeight: button.item ? button.item.implicitHeight : 0

  Loader {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: item ? item.implicitWidth : 0
    sourceComponent: root.barText !== "" || root.gpuText !== "" ? labelledButton : iconButton
  }

  // Dev servers, as their own button: the bar's urgent colour while any run,
  // and a click opens the Ports tab.
  WidgetButton {
    id: portsButton
    visible: root.portsBadge.text !== ""
    anchors.left: button.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: visible ? implicitWidth : 0
    bar: root.bar
    text: root.portsBadge.text
    active: root.portsBadge.active
    tooltipText: root.opened ? "" : (root.portsBadge.active ? "Dev servers listening: open the Ports tab" : "No dev server listening")
    onPressed: function(b) {
      if (!root.service) return
      if (root.opened && root.tab === "ports") root.close()
      else root.service.showTab("ports")
    }
  }

  Component {
    id: iconButton
    BarIconButton {
      anchors.fill: parent
      bar: root.bar
      text: root.glyph
      tooltipText: root.opened ? "" : root.tooltip
      active: root.urgent
      onPressed: function(b) {
        if (b === Qt.RightButton && root.service) root.service.cycleBarLabel()
        else root.toggle()
      }
    }
  }

  Component {
    id: labelledButton
    WidgetButton {
      anchors.fill: parent
      bar: root.bar
      text: (root.barText ? root.barText + " " : "") + root.glyph + (root.gpuText ? "  " + root.gpuText : "")
      tooltipText: root.opened ? "" : root.tooltip
      active: root.urgent
      onPressed: function(b) {
        if (b === Qt.RightButton && root.service) root.service.cycleBarLabel()
        else root.toggle()
      }
    }
  }

  // ------------------------------------------------------- power actions

  property var pendingAction: null

  function requestAction(action) {
    if (!action || !service) return
    if (action.confirm) {
      pendingAction = action
      confirmKeys.forceActiveFocus()
    } else {
      service.runPowerAction(action.key)
    }
  }

  onPendingActionChanged: if (!pendingAction) keyCatcher.forceActiveFocus()

  // ---------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: button.item ? button : root
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.service ? root.service.panelWidth : 560))
    contentHeight: panel.fittedContentHeight(
      (tabBar.visible ? tabBar.height + Style.space(12) : 0) + (stickyHeader.item ? stickyHeader.height + Style.space(10) : 0)
      + column.implicitHeight + powerBar.height + Style.space(12), Style.space(860))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.pendingAction !== null || root.textEditing

      onMoveRequested: function(dx, dy) {
        var v = viewLoader.item
        if (v && typeof v.handleMove === "function" && v.handleMove(dx, dy)) return
        if (dy !== 0) root.scrollBy(dy * Style.space(60))
        else if (dx !== 0) root.cycleTab(dx)
      }
      onActivateRequested: {
        var v = viewLoader.item
        if (v && typeof v.handleActivate === "function") v.handleActivate()
      }
      onCloseRequested: {
        if (root.service && root.service.lightbox) root.service.closePreview()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var n = parseInt(t, 10)
        if (n >= 1 && n <= root.tabs.length) { root.tab = root.tabs[n - 1].value; return }
        // The open tab's own keys (search, actions on the cursor row) first.
        var v = viewLoader.item
        if (v && typeof v.handleKey === "function" && v.handleKey(t)) return
        if (t === "[") { root.cycleTab(-1); return }
        if (t === "]") { root.cycleTab(1); return }
        if (!root.service) return
        if (t === "L") { root.requestAction(Model.powerAction("lock")); return }
        if (t === "S" && root.service.suspendAvailable) { root.requestAction(Model.powerAction("suspend")); return }
        if (t === "R") { root.requestAction(Model.powerAction("reboot")); return }
        if (t === "P") { root.requestAction(Model.powerAction("shutdown")); return }
        if (t === "a") { root.service.setKeepAwake(!root.service.keepAwake); return }
      }

      // ---------- Tabs, fixed at the top like the power row ----------
      // The open tab says its name in its own theme colour; the others are
      // icons with a tooltip, so every tab fits one row at any width.
      RowLayout {
        id: tabBar
        visible: root.ready && root.tabs.length > 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(4)

        Repeater {
          model: root.tabs
          delegate: Button {
            required property var modelData
            required property int index
            readonly property bool open: root.tab === modelData.value
            readonly property color tint: Model.tabTint(modelData.value, root.palette, String(Color.background))
            Layout.fillWidth: open
            Layout.preferredWidth: open ? -1 : Style.space(34)
            text: open ? modelData.label : ""
            iconText: modelData.icon
            tooltipText: open ? "" : modelData.label + "  (" + (index + 1) + ")"
            bordered: open
            foreground: open ? tint : root.dim
            background: open ? Qt.rgba(tint.r, tint.g, tint.b, 0.14) : "transparent"
            accent: tint
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            iconSize: Style.font.body
            verticalPadding: Style.space(4)
            onClicked: root.tab = modelData.value
          }
        }
      }

      // ---------- A tab's own header, frozen above its list ----------
      // (search, filters, column headers): the tab's view hands it over as
      // `header`, a component that keeps the view's scope.
      Loader {
        id: stickyHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: tabBar.visible ? tabBar.bottom : parent.top
        anchors.topMargin: tabBar.visible ? Style.space(12) : 0
        height: item ? item.implicitHeight : 0
        sourceComponent: viewLoader.item && viewLoader.item.header ? viewLoader.item.header : null
      }

      ScrollView {
        id: scrollArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: stickyHeader.item ? stickyHeader.bottom : stickyHeader.top
        anchors.topMargin: stickyHeader.item ? Style.space(10) : 0
        anchors.bottom: powerBar.top
        anchors.bottomMargin: Style.space(12)
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          Text {
            visible: !root.ready
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "The OmniSystem Center service is not running yet. If this stays, run: omarchy restart shell"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // The critical action counting down.
          Card {
            visible: root.ready && root.service.criticalPending
            tint: Color.urgent
            foreground: root.foreground
            fontFamily: root.fontFamily
            text: root.ready ? "Battery critical at " + root.service.level + "%. " +
              (root.service.criticalAction === "hibernate" ? "Hibernating" : "Suspending") + " in " +
              root.service.criticalRemaining + " s unless you plug in." : ""
            Button {
              text: "Cancel"
              bordered: true
              active: true
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.cancelCritical("Canceled.")
            }
          }

          // Notes and errors, newest first, until dismissed.
          Column {
            visible: root.ready && root.service.messages.length > 0
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.ready ? root.service.messages : []
              Text {
                required property var modelData
                width: column.width - Style.space(28)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: modelData.text
                color: modelData.level === "error" ? Color.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            PanelActionButton {
              anchors.right: parent.right
              iconText: "󰅖"
              tooltipText: "Dismiss"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.service.clearMessages()
            }
          }

          Loader {
            id: viewLoader
            width: parent.width
            active: root.ready && root.shownTab !== ""
            sourceComponent: {
              switch (root.shownTab) {
              case "care": return careView
              case "insights": return insightsView
              case "energy": return energyView
              case "system": return systemView
              case "processes": return processesView
              case "ports": return portsView
              case "plugins": return pluginsView
              case "settings": return settingsView
              case "controls": return controlsView
              default: return overviewView
              }
            }
          }
        }
      }

      // ---------- Power controls, pinned at the bottom of every tab ----------
      Column {
        id: powerBar
        visible: root.ready
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Style.space(10)
        height: root.ready ? implicitHeight : 0

        PanelSeparator {
          foreground: root.foreground
        }

        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)
          readonly property var actions: root.ready ? root.service.powerActions : []
          readonly property real cell: actions.length > 0 ? (width - spacing * (actions.length - 1)) / actions.length : 0

          Repeater {
            model: actionRow.actions
            Column {
              required property var modelData
              width: actionRow.cell
              spacing: Style.space(4)

              Button {
                width: parent.width
                iconText: modelData.icon
                iconSize: Style.font.title
                tooltipText: modelData.label + (modelData.confirm ? " (asks first)" : "")
                             + (root.ready && root.service.sleepRisk(modelData.key) ? "\n󰀪 " + root.service.sleepRisk(modelData.key) : "")
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                foreground: root.actionColor(modelData.key)
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.requestAction(modelData)
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: modelData.label
                color: Qt.darker(root.actionColor(modelData.key), 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      // A plugin preview, enlarged over the whole panel; a click or Esc closes it.
      Rectangle {
        id: lightbox
        anchors.fill: parent
        visible: root.ready && !!root.service.lightbox
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.94)
        radius: Style.cornerRadius
        z: 50
        readonly property var box: root.ready ? root.service.lightbox : null

        MouseArea {
          anchors.fill: parent
          onClicked: root.service.closePreview()
        }
        Column {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(8)
          Item {
            width: parent.width
            implicitHeight: boxTitle.implicitHeight
            Text {
              id: boxTitle
              textFormat: Text.PlainText
              text: lightbox.box ? lightbox.box.title : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: lightbox.box && lightbox.box.loading ? "Loading the full size…" : "Click or Esc to close"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Image {
            width: parent.width
            height: parent.height - boxTitle.height - parent.spacing
            source: lightbox.box && lightbox.box.file ? "file://" + lightbox.box.file : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
          }
        }
      }

      // Confirmation for logout, reboot and shutdown, over the whole panel.
      Item {
        id: confirmKeys
        anchors.fill: parent
        visible: root.pendingAction !== null
        Keys.onPressed: function(event) { event.accepted = confirm.handleKey(event) }

        ConfirmDialog {
          id: confirm
          anchors.fill: parent
          opened: root.pendingAction !== null
          message: root.pendingAction ? root.pendingAction.label + " now?" : ""
          confirmText: root.pendingAction ? root.pendingAction.label : "Confirm"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onCanceled: root.pendingAction = null
          onConfirmed: {
            var a = root.pendingAction
            root.pendingAction = null
            if (a && root.service) root.service.runPowerAction(a.key)
          }
        }
      }
    }
  }

  property bool textEditing: false

  function scrollBy(delta) {
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var max = Math.max(0, column.implicitHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(max, flick.contentY + delta))
  }

  // Keep a row (the keyboard cursor) inside the scrolling area.
  function ensureVisible(item) {
    var flick = scrollArea.contentItem
    if (!item || !flick || flick.contentY === undefined) return
    var top = item.mapToItem(column, 0, 0).y
    var margin = Style.space(12)
    if (top < flick.contentY + margin) scrollTo(Math.max(0, top - margin))
    else if (top + item.height > flick.contentY + flick.height - margin)
      scrollTo(Math.min(Math.max(0, column.implicitHeight - flick.height), top + item.height - flick.height + margin))
  }

  // Back to the keys after a search field: Esc or Enter there hands them back.
  function focusKeys() { textEditing = false; keyCatcher.forceActiveFocus() }

  function scrollTo(y) {
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = y
  }

  Component { id: overviewView; OverviewView { panel: root } }
  Component { id: careView; CareView { panel: root } }
  Component { id: insightsView; InsightsView { panel: root } }
  Component { id: energyView; EnergyView { panel: root } }
  Component { id: systemView; SystemView { panel: root } }
  Component { id: processesView; ProcessesView { panel: root } }
  Component { id: portsView; PortsView { panel: root } }
  Component { id: pluginsView; PluginsView { panel: root } }
  Component { id: settingsView; SettingsView { panel: root } }
  Component { id: controlsView; ControlsView { panel: root } }
}

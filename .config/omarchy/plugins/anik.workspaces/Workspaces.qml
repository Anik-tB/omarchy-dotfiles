import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"

// Workspaces in the theme palette: the active one shows its number in the
// accent with a short accent underline that slides between workspaces; other
// workspaces are dots, bright when occupied and muted when empty. Switching
// cross-fades the number and the dot (with a little scale), dots grow on hover,
// and each cell registers as a bar click target so the hand cursor shows.
BarWidget {
  id: root
  moduleName: "anik.workspaces"

  AnikPalette { id: themePalette }

  readonly property int cell: Style.space(24)
  readonly property var ids: workspaceIds()
  // This bar's monitor's workspace, whichever monitor has focus.
  readonly property int activeIndex: ids.indexOf(activeWorkspaceId())

  // Every monitor has workspaces 1-10 of its own, which Hyprland numbers in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }
    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }
  onBarChanged: syncClickRegistration()
  Component.onCompleted: { syncClickRegistration(); refresh() }
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  function modeGlyph(mode) {
    if (mode === "scrolling") return "󰝥"
    if (mode === "floating") return "󰔶"
    return "󱓻"
  }

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
  }

  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() { root.showActiveMode() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  // The bar's overlay only tracks the pointer on press, so its hover test for
  // the hand cursor falls back to the widget itself: the whole widget is a
  // click target too, and a click it receives goes to the hovered cell.
  // (Real clicks normally land on the cell targets first.)
  function triggerPress(button) {
    var i = Math.floor(widgetHover.point.position.x / root.cell)
    if (i >= 0 && i < root.ids.length) root.focusWorkspace(root.ids[i])
  }
  HoverHandler { id: widgetHover; cursorShape: Qt.PointingHandCursor }

  visible: !vertical
  implicitWidth: ids.length * cell
  implicitHeight: barSize

  // sliding underline beneath the active workspace
  Rectangle {
    visible: root.activeIndex >= 0
    width: Math.round(root.cell * 0.55); height: Style.space(2); radius: height / 2
    // just inside the pill's lower edge (pill height = bar height - 10 units)
    y: Math.round(parent.height / 2 + (root.barSize - Style.space(10)) / 2 - Style.space(5))
    x: root.activeIndex * root.cell + (root.cell - width) / 2
    color: themePalette.accent
    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter

    Repeater {
      model: root.ids

      Item {
        id: ws
        required property int modelData
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool focused: shown

        width: root.cell
        height: root.cell

        // The bar's slot overlay picks the cursor and routes left clicks to
        // registered click targets (see anik.resources), so register each cell.
        function triggerPress(button) { root.focusWorkspace(ws.modelData) }
        property var registeredBar: null
        function syncClickRegistration() {
          if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(ws)
          registeredBar = root.bar
          if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(ws)
        }
        Connections { target: root; function onBarChanged() { ws.syncClickRegistration() } }
        Component.onCompleted: syncClickRegistration()
        Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(ws)

        HoverHandler { id: wsHover; cursorShape: Qt.PointingHandCursor }

        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(2) // room for the underline
          opacity: ws.focused ? 1 : 0
          scale: ws.focused ? 1 : 0.6
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
          textFormat: Text.PlainText
          renderType: Text.NativeRendering // like the bar's own labels: no colour fringes
          text: ws.slot === root.slots ? "0" : String(ws.slot)
          color: themePalette.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Rectangle {
          anchors.centerIn: parent
          opacity: ws.focused ? 0 : 1
          scale: ws.focused ? 0.3 : (wsHover.hovered ? 1.35 : 1)
          visible: opacity > 0
          width: ws.occupied ? Style.space(6) : Style.space(4); height: width; radius: width / 2
          // translucent text for empty workspaces: readable on any wallpaper
          color: ws.occupied || wsHover.hovered ? themePalette.text : themePalette.faint
          Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 200 } }
        }

      }
    }
  }
}

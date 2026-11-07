import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "../anik.bar"

// Windows-style recording toolbar at the top centre of the screen:
//   ● 01:23 | ⏸ ■
// On a monitor with a real fullscreen window: always shown while PAUSED;
// while live it is hidden until the pointer touches the top edge (centre),
// so it only lands in the video when you reach for it. Omarchy records the whole output (KMS capture), so
// anything on screen while recording is live ends up in the video; a paused
// recorder captures nothing, so the toolbar never appears in the video.
// Resume hides the toolbar first, then un-pauses the recorder.
Item {
  id: root

  AnikPalette { id: pal }

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  property bool recording: false
  property bool paused: false
  property int elapsed: 0
  property int hyprRevision: 0
  property bool instantHide: false   // resume: vanish without a fade

  readonly property string timeText: {
    const h = Math.floor(elapsed / 3600)
    const m = Math.floor((elapsed % 3600) / 60)
    const s = elapsed % 60
    const pad = n => (n < 10 ? "0" : "") + n
    return (h > 0 ? h + ":" : "") + pad(m) + ":" + pad(s)
  }

  // ---------------------------------------------------------------- state
  // In-process check of Omarchy's pid file (no process spawned while idle).
  FileView {
    id: pidFile
    path: root.runtimeDir + "/omarchy-screenrecord-pid"
    printErrors: false
    onLoaded: if (!root.recording && text().trim() !== "") root.sync()
    onLoadFailed: if (root.recording) root.sync()
  }
  Timer {
    interval: 1500
    repeat: true
    running: true
    onTriggered: pidFile.reload()
  }

  function sync() { if (!statusProc.running) statusProc.running = true }

  Process {
    id: statusProc
    command: ["anik-screenrecord-pause", "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.trim().split(/\s+/)
        if (parts.length >= 2 && parts[0] !== "") {
          root.elapsed = parseInt(parts[0]) || 0
          root.paused = parts[1] === "1"
        }
      }
    }
    onExited: function(exitCode) {
      root.recording = exitCode === 0
      if (!root.recording) { root.paused = false; root.elapsed = 0 }
    }
  }

  // Tick locally; re-sync with the recorder every 5s.
  Timer {
    interval: 1000
    repeat: true
    running: root.recording
    property int ticks: 0
    onTriggered: {
      if (!root.paused) root.elapsed += 1
      if (++ticks % 5 === 0) root.sync()
    }
  }

  signal resumed()

  function hideNow() {
    root.resumed()
    root.instantHide = true
    root.paused = false
    instantReset.restart()
  }
  Timer { id: instantReset; interval: 500; onTriggered: root.instantHide = false }

  function togglePause() {
    if (root.paused) {
      // Hide first; the script waits before un-pausing the recorder.
      root.hideNow()
    } else {
      root.paused = true
    }
    Quickshell.execDetached(["anik-screenrecord-pause", "toggle"])
    syncSoon.restart()
  }

  // Called by anik-screenrecord-pause (keyboard shortcut path).
  IpcHandler {
    target: "anik.recbar"
    function sync(): string { root.sync(); return "ok" }
    function resuming(): string { root.hideNow(); return "ok" }
  }
  function stop() {
    Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"])
    syncSoon.restart()
  }
  Timer { id: syncSoon; interval: 600; onTriggered: root.sync() }

  // ------------------------------------------------------------ fullscreen
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "fullscreen": case "openwindow": case "closewindow": case "movewindowv2":
      case "activewindowv2": case "workspacev2": case "focusedmonv2":
        hyprRefresh.restart()
      }
    }
  }
  Timer { id: hyprRefresh; interval: 100; onTriggered: { Hyprland.refreshToplevels(); hyprSettle.restart() } }
  Timer { id: hyprSettle; interval: 250; onTriggered: root.hyprRevision++ }

  function fullscreenOn(screen) {
    var revision = root.hyprRevision
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    var workspace = monitor ? monitor.activeWorkspace : null
    if (!workspace || !workspace.hasFullscreen) return false
    var windows = workspace.toplevels ? workspace.toplevels.values : []
    for (var i = 0; i < windows.length; i++) {
      var ipc = windows[i].lastIpcObject || {}
      // Maximized also counts as hasFullscreen; only real fullscreen hides the bar.
      if ((Number(ipc.fullscreen) & 2) !== 0) return true
    }
    return false
  }

  // ---------------------------------------------------------------- toolbar
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      // Armed while recording on a monitor with a real fullscreen window.
      // Live: hidden, but pushing the pointer to the top edge (hot strip)
      // drops the toolbar down. Paused: always shown.
      readonly property bool armed: root.recording && root.fullscreenOn(modelData)
      property bool hovered: false
      property bool suppressed: false   // just resumed: stay hidden until re-hovered
      readonly property bool wanted: armed && !suppressed && (root.paused || hovered)

      function updateHover() {
        if (hotArea.containsMouse && !suppressed) { hovered = true; hideTimer.stop() }
        else if (hovered && cardHover.hovered) hideTimer.stop()
        else if (hovered) hideTimer.restart()
      }
      Timer { id: hideTimer; interval: 700; onTriggered: win.hovered = false }
      Timer { id: unsuppress; interval: 1200; onTriggered: win.suppressed = false }
      Connections {
        target: root
        function onResumed() {
          win.suppressed = true
          win.hovered = false
          hideTimer.stop()
          unsuppress.restart()
        }
      }

      visible: armed || card.opacity > 0
      anchors.top: true
      margins.top: 0
      implicitWidth: Math.max(card.width + 20, Style.space(360))
      implicitHeight: Style.space(10) + card.height + 20
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "anik-recbar"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Only the thin top strip takes input until the toolbar is shown.
      mask: Region { item: win.wanted ? inputAll : hotStrip }

      Item {
        id: inputAll
        anchors.fill: parent
        HoverHandler { id: cardHover; onHoveredChanged: win.updateHover() }
      }

      Item {
        id: hotStrip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 3
        MouseArea {
          id: hotArea
          anchors.fill: parent
          hoverEnabled: true
          onContainsMouseChanged: win.updateHover()
        }
      }

      Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: win.wanted ? Style.space(10) : Style.space(2)
        Behavior on y { enabled: !root.instantHide; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        readonly property int pad: Style.space(12)
        height: Style.space(36)
        width: row.implicitWidth + pad * 2
        radius: height / 2
        color: Qt.rgba(pal.deep.r, pal.deep.g, pal.deep.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.09)

        opacity: win.wanted ? 1 : 0
        scale: win.wanted ? 1 : 0.94
        Behavior on opacity { enabled: !root.instantHide; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
          id: row
          anchors.centerIn: parent
          spacing: Style.space(8)

          // Live dot / paused glyph
          Item {
            width: Style.space(14); height: card.height
            Rectangle {
              visible: !root.paused
              anchors.centerIn: parent
              width: Style.space(9); height: width; radius: width / 2
              color: pal.alert
            }
            Text {
              visible: root.paused
              anchors.centerIn: parent
              text: "󰏤"
              color: pal.soft
              font.family: Style.font.family
              font.pixelSize: Style.font.title
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
            color: root.paused ? pal.soft : pal.textBright
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.features: { "tnum": 1 }
            renderType: Text.NativeRendering
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1; height: card.height * 0.45
            color: pal.hairline
          }

          RecButton {
            glyph: root.paused ? "󰐊" : "󰏤"
            tip: root.paused ? "Resume" : "Pause"
            onClicked: root.togglePause()
          }
          RecButton {
            glyph: "󰓛"
            glyphColor: pal.alert
            tip: "Stop"
            onClicked: root.stop()
          }
        }
      }
    }
  }

  component RecButton: Rectangle {
    id: btn
    property string glyph: ""
    property string tip: ""
    property color glyphColor: pal.text
    signal clicked()

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: Style.space(28); height: width; radius: width / 2
    color: area.pressed ? Qt.rgba(1, 1, 1, 0.14) : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: btn.glyphColor
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      scale: area.pressed ? 0.88 : 1
      Behavior on scale { NumberAnimation { duration: 90 } }
    }
    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }
}

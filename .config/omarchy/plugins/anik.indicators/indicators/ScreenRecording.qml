import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Screen recording indicator with a live timer and pause.
// Left click = stop, right click = pause/resume (anik-screenrecord-pause).
BarIndicator {
  id: root

  property bool recording: false
  property bool paused: false
  property int elapsed: 0          // seconds actually recorded (pauses excluded)

  readonly property string timeText: {
    const h = Math.floor(elapsed / 3600)
    const m = Math.floor((elapsed % 3600) / 60)
    const s = elapsed % 60
    const pad = n => (n < 10 ? "0" : "") + n
    return (h > 0 ? h + ":" : "") + pad(m) + ":" + pad(s)
  }

  active: recording
  activeText: paused ? "󰏤" : "󰻂"
  inactiveText: "󰻂"
  labelText: recording && !vertical ? timeText : ""
  activeTooltipText: paused ? "Paused · left click stop · right click resume"
                            : "Recording · left click stop · right click pause"
  inactiveTooltipText: "Screen Recording"

  // Red while live, normal text colour while paused.
  useActiveColor: recording && !paused
  fontSize: recording && !vertical ? Style.font.body : Style.bar.iconFont
  fixedWidth: vertical ? -1
    : (recording ? Math.ceil(canvasSize + timeMetrics.advanceWidth + Style.space(4) + Style.spaceReal(horizontalMargin) * 2)
                 : Style.bar.statusSlot)

  TextMetrics {
    id: timeMetrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    text: root.elapsed >= 3600 ? "0:00:00" : "00:00"
  }

  function refresh() {
    if (!root.bar || statusProc.running) return
    statusProc.running = true
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

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
      if (!root.recording) {
        root.paused = false
        root.elapsed = 0
      }
    }
  }

  // Tick locally every second; re-sync with the recorder every 5s.
  Timer {
    interval: 1000
    repeat: true
    running: root.recording
    property int ticks: 0
    onTriggered: {
      if (!root.paused) root.elapsed += 1
      if (++ticks % 5 === 0) root.refresh()
    }
  }

  onPressed: function(button) {
    if (!root.bar) return
    if (button === Qt.RightButton && root.recording) {
      root.bar.run("anik-screenrecord-pause toggle")
      root.paused = !root.paused   // optimistic; the refresh confirms
      return
    }
    root.bar.run(root.recording ? "omarchy-capture-screenrecording --stop-recording" : "omarchy-menu toggle trigger.capture.screenrecord")
  }
}

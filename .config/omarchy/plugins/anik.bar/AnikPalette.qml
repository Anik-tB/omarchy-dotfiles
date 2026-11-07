import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// The full theme palette for the anik bar and its widgets (anik.workspaces,
// anik.resources import this file). Commons.Color only exposes five base
// colours, so this reads the current theme's colors.toml directly and follows
// theme switches. Defaults are the Anik theme's own values.
QtObject {
  id: palette

  property color background: "#14111e"
  property color surface: "#1e1a2c"       // lighter_background
  property color deep: "#0f0d17"          // dark_background: floating islands
  property color outline: "#2e2842"       // selection: pill hairlines
  property color accent: "#a08ae6"        // active workspace, rings
  property color text: "#c5bfe2"          // foreground
  property color textBright: "#e6e2f7"    // bright_foreground
  property color textDim: "#6b6590"       // dark_foreground
  property color muted: "#485362"         // empty workspaces, ring tracks
  property color alert: "#e2687f"
  property color warn: "#e59a7a"         // orange: busy, not critical

  // One tone scale for everything on the bar, all derived from `text` so the
  // whole strip shares a single hue: primary = text, then these three steps.
  // Accent is reserved for "active/live" (current workspace, visualizer,
  // unread), alert for "needs attention".
  readonly property color soft: Qt.rgba(text.r, text.g, text.b, 0.62)      // labels, paused glyphs
  readonly property color faint: Qt.rgba(text.r, text.g, text.b, 0.4)      // empty workspaces, idle dots
  readonly property color hairline: Qt.rgba(text.r, text.g, text.b, 0.28)  // dividers

  readonly property var keys: ({
    background: "background", lighter_background: "surface", dark_background: "deep", selection: "outline",
    accent: "accent", foreground: "text", bright_foreground: "textBright",
    dark_foreground: "textDim", muted: "muted", red: "alert", orange: "warn"
  })

  function load(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m && keys[m[1]]) palette[keys[m[1]]] = m[2]
    }
  }

  property FileView file: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: palette.load(text())
    onFileChanged: reload()
  }

  // Theme switches replace the theme directory (the file watch goes stale) and
  // reach the shell over IPC, so also re-read whenever the shell's colours move.
  property Timer reloadTimer: Timer { interval: 150; onTriggered: palette.file.reload() }
  property Connections themeChanges: Connections {
    target: Commons.Color
    function onAccentChanged() { palette.reloadTimer.restart() }
    function onBackgroundChanged() { palette.reloadTimer.restart() }
    function onForegroundChanged() { palette.reloadTimer.restart() }
  }
}

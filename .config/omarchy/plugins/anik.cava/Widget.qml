import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "../anik.bar"

// Cava visualizer for the bar: mirrored bars (bass in the middle) in the theme's
// accent with lighter-accent tips (AnikPalette). It slides open while audio is playing and folds away in
// silence, so the bar looks untouched when nothing is on. cava only runs while
// an app has an audio stream open. Left click opens the audio panel.
BarWidget {
  id: root
  moduleName: "anik.cava"

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/anik.cava"

  readonly property int bands: 12 // must match `bars` in cava.conf
  readonly property int barWidth: 3
  readonly property int gap: 2
  readonly property int fullWidth: bands * 2 * (barWidth + gap) - gap

  property var levels: []
  property double lastSoundAt: 0
  property bool audible: false

  // theme palette shared with the anik bar: accent bars with bright tips
  AnikPalette { id: themePalette }
  readonly property color colorMid: themePalette.accent
  readonly property color colorHigh: Qt.lighter(themePalette.accent, 1.25)
  readonly property int margin: Style.space(6)

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property bool playing: {
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && n.isSink) return true
    }
    return false
  }

  visible: !vertical && implicitWidth > 0.5
  implicitHeight: barSize
  implicitWidth: audible ? fullWidth + 2 * margin : 0
  Behavior on implicitWidth { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

  Process {
    command: ["cava", "-p", root.pluginDir + "/cava.conf"]
    running: root.playing
    stdout: SplitParser {
      onRead: function(line) { root.ingest(line) }
    }
    onRunningChanged: if (!running) root.ingest("")
  }

  function ingest(line) {
    var parts = String(line).split(";")
    var out = new Array(bands)
    var sum = 0
    for (var i = 0; i < bands; i++) {
      var v = Number(parts[i]) / 1000
      if (!isFinite(v)) v = 0
      out[i] = v
      sum += v
    }
    levels = out
    if (sum / bands > 0.012) lastSoundAt = Date.now()
    audible = Date.now() - lastSoundAt < 1500
  }

  Timer {
    // keeps `audible` honest once cava stops emitting (stream closed)
    interval: 500
    running: root.audible
    repeat: true
    onTriggered: root.audible = Date.now() - root.lastSoundAt < 1500
  }

  Item {
    id: stage
    anchors.centerIn: parent
    width: root.fullWidth
    height: Math.round(root.barSize * 0.62)
    clip: true
    opacity: root.audible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 300 } }

    Repeater {
      model: root.bands * 2

      Rectangle {
        required property int index
        // left half mirrors the right so the bass band sits in the centre
        readonly property int band: index < root.bands ? root.bands - 1 - index : index - root.bands
        readonly property real level: root.levels.length > band ? root.levels[band] : 0

        x: index * (root.barWidth + root.gap)
        width: root.barWidth
        height: Math.max(2, Math.round(level * stage.height))
        y: (stage.height - height) / 2 // grows both ways from the bar's midline
        radius: width / 2
        antialiasing: true
        Behavior on height { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }

        gradient: Gradient {
          GradientStop { position: 0.0; color: root.colorHigh }
          GradientStop { position: 0.35; color: root.colorMid }
          GradientStop { position: 0.65; color: root.colorMid }
          GradientStop { position: 1.0; color: root.colorHigh }
        }
      }
    }
  }

  // The bar's slot overlay takes the pointer above this widget: it shows the
  // hand and routes left clicks only to registered click targets that have
  // triggerPress, so register like anik.resources does.
  function triggerPress(button) {
    if (root.bar) root.bar.run("omarchy-shell omarchy.audio toggle")
  }
  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }
  onBarChanged: syncClickRegistration()
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

  HoverHandler { cursorShape: Qt.PointingHandCursor }
}

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"

// CPU and RAM usage as compact text ("CPU 12%  RAM 37%"; swap appears only
// when in use), in tabular figures so nothing jumps. Values turn orange from 70% and red from 90%. Reads /proc
// every two seconds. Click opens the system panel (Panel.qml: graphs, temps,
// top processes); right click opens (or focuses) btop.
BarWidget {
  id: root
  moduleName: "anik.resources"

  // theme palette shared with the anik bar (colors.toml)
  AnikPalette { id: themePalette }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property real cpu: 0
  property real ram: 0
  property real swap: 0
  property real memUsed: 0     // KiB
  property real memTotal: 0
  property real memCache: 0    // reclaimable page cache + buffers, KiB
  property real swapUsed: 0
  property real swapTotal: 0
  property real temp: -1       // °C, -1 when no sensor
  property string load: ""
  property real uptime: 0      // seconds
  property int cores: 0
  property var lastCpu: null
  property var lastCores: []
  property var coreUsage: []   // 0..1 per thread

  // Last two minutes of samples, for the panel's graphs.
  readonly property int historyLength: 60
  property var cpuHistory: []
  property var ramHistory: []

  function pushSample(list, value) {
    var next = list.slice(Math.max(0, list.length - historyLength + 1))
    next.push(value)
    return next
  }

  function levelColor(v) {
    return v >= 0.9 ? themePalette.alert : (v >= 0.7 ? themePalette.warn : themePalette.text)
  }

  visible: !vertical
  implicitHeight: barSize
  implicitWidth: row.implicitWidth + Style.space(18)

  // One `cat` every two seconds (no shell, no pipeline): /proc/stat,
  // /proc/meminfo, /proc/loadavg, /proc/uptime and the CPU temperature file,
  // which is looked up once at startup.
  property string tempPath: ""

  function parse(text) {
    var lines = String(text).split("\n"), mem = {}, threads = 0, coreNow = [], coreUse = []
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i], m
      if (l.indexOf("cpu ") === 0) {
        var f = l.trim().split(/\s+/).slice(1).map(Number)
        var idle = f[3] + f[4], total = 0
        for (var j = 0; j < f.length; j++) total += f[j]
        if (lastCpu && total > lastCpu.total)
          cpu = 1 - (idle - lastCpu.idle) / (total - lastCpu.total)
        lastCpu = { idle: idle, total: total }
      } else if (/^cpu\d/.test(l)) {
        var c = l.trim().split(/\s+/).slice(1).map(Number)
        var cIdle = c[3] + c[4], cTotal = 0
        for (var k = 0; k < c.length; k++) cTotal += c[k]
        var prev = lastCores[threads]
        coreUse.push(prev && cTotal > prev.total ? 1 - (cIdle - prev.idle) / (cTotal - prev.total) : 0)
        coreNow.push({ idle: cIdle, total: cTotal })
        threads++
      } else if ((m = l.match(/^(\w+):\s+(\d+)/))) {
        mem[m[1]] = Number(m[2])
      } else if (/^\d+\.\d+ \d+\.\d+ \d+\.\d+ \d+\//.test(l)) {
        load = l.split(" ").slice(0, 3).join("  ")      // /proc/loadavg
      } else if (/^\d+\.\d+ \d+\.\d+$/.test(l)) {
        uptime = Number(l.split(" ")[0]) || 0           // /proc/uptime
      } else if (/^\d+$/.test(l)) {
        temp = Number(l) / 1000                          // millidegrees
      }
    }
    if (threads > 0) { cores = threads; lastCores = coreNow; coreUsage = coreUse }
    if (mem.MemTotal) {
      memTotal = mem.MemTotal
      memUsed = mem.MemTotal - mem.MemAvailable
      ram = memUsed / memTotal
      // page cache that is in use but reclaimable (never more than what's left)
      memCache = Math.max(0, Math.min((mem.Buffers || 0) + (mem.Cached || 0) + (mem.SReclaimable || 0),
                                      memTotal - memUsed - (mem.MemFree || 0)))
    }
    swapTotal = mem.SwapTotal || 0
    swapUsed = swapTotal - (mem.SwapFree || 0)
    swap = swapTotal ? swapUsed / swapTotal : 0
    cpuHistory = pushSample(cpuHistory, cpu)
    ramHistory = pushSample(ramHistory, ram)
  }

  Process {
    id: tempFinder
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in coretemp|k10temp|zenpower)"
      + " echo $h/temp1_input; break;; esac; done"]
    stdout: StdioCollector { onStreamFinished: root.tempPath = String(text).trim() }
  }

  Process {
    id: reader
    command: ["cat", "/proc/stat", "/proc/meminfo", "/proc/loadavg", "/proc/uptime"]
      .concat(root.tempPath !== "" ? [root.tempPath] : [])
    stdout: StdioCollector { onStreamFinished: root.parse(text) }
  }

  Timer {
    interval: 2000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!reader.running) reader.running = true
  }

  // ---- System panel
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = root
    target.hostWidget = root
    target.stats = root
  }
  onBarChanged: { injectPanel(); syncClickRegistration() }

  // Shape contract the bar uses to route and switch popouts (see anik.bell).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Soft pill on hover; an accent wash while the panel is open.
  Rectangle {
    anchors.centerIn: parent
    width: parent.width
    height: Math.min(parent.height - Style.space(8), Style.space(28))
    radius: height / 2
    color: root.opened
      ? Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.10)
      : Qt.rgba(1, 1, 1, hover.hovered ? 0.06 : 0)
        Behavior on color { ColorAnimation { duration: 140 } }
  }

  // One stat: dim label, then the value in tabular figures so the numbers
  // don't shift as they update ("CPU 12%"). Same body size and weight as every other label on the bar;
  // the label differs only by colour.
  component Stat: Item {
    id: stat
    property string label: ""
    property real value: 0
    readonly property color level: root.levelColor(value)
    implicitWidth: statRow.implicitWidth
    implicitHeight: statRow.implicitHeight
    anchors.verticalCenter: parent.verticalCenter

    Row {
      id: statRow
      spacing: Style.space(4)

      Text {
        anchors.baseline: valueText.baseline
        text: stat.label
        // translucent text rather than textDim: stays readable on a bright
        // wallpaper now that the bar is fully transparent
        color: themePalette.soft
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Text {
        id: valueText
        text: Math.round(stat.value * 100) + "%"
        color: stat.value >= 0.7 ? stat.level : themePalette.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.features: { "tnum": 1 }
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: 300 } }
      }
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(12)

    Stat { label: "CPU"; value: root.cpu }
    Stat { label: "RAM"; value: root.ram }
    Stat { label: "SWAP"; value: root.swap; visible: root.swap >= 0.01 }
  }

  // The bar's slot overlay sits above this widget, decides the cursor and
  // routes left clicks: it shows the hand only over registered click targets
  // with triggerPress (see WidgetButton), so register like one.
  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    if (button === Qt.RightButton) {
      if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    } else if (panelLoader.item) {
      panelLoader.item.toggle()
    }
  }
  property var registeredBar: null
  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

  // Right click (the overlay only takes the left button).
  MouseArea {
    id: area
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) { root.triggerPress(mouse.button) }
  }
}

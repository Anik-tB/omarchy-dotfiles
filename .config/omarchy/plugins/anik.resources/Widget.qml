import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"

// CPU and RAM usage as compact text ("CPU 12%  RAM 37%"; swap appears only
// when in use), in tabular figures so nothing jumps. Values turn orange from 70%
// and red from 90%. Reads /proc in-process via FileView every two seconds (no
// subprocess spawns). Click opens the system panel (Panel.qml); right click
// opens (or focuses) btop.
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

  property string tempPath: ""

  function sumCpuFields(parts) {
    var idle = (Number(parts[4]) || 0) + (Number(parts[5]) || 0)
    var total = 0
    for (var i = 1; i < parts.length; i++) total += Number(parts[i]) || 0
    return { idle: idle, total: total }
  }

  function parseStat(text) {
    var lines = String(text || "").split("\n")
    var threads = 0
    var coreNow = []
    var coreUse = []
    var collectCores = root.opened || root.cores === 0

    for (var i = 0; i < lines.length; i++) {
      var l = lines[i]
      if (l.indexOf("cpu ") === 0) {
        var cur = sumCpuFields(l.trim().split(/\s+/))
        if (lastCpu && cur.total > lastCpu.total)
          cpu = Math.max(0, Math.min(1, 1 - (cur.idle - lastCpu.idle) / (cur.total - lastCpu.total)))
        lastCpu = cur
        if (!collectCores) break
      } else if (/^cpu\d/.test(l)) {
        if (root.opened) {
          var c = sumCpuFields(l.trim().split(/\s+/))
          var prev = lastCores[threads]
          coreUse.push(prev && c.total > prev.total
            ? Math.max(0, Math.min(1, 1 - (c.idle - prev.idle) / (c.total - prev.total)))
            : 0)
          coreNow.push(c)
        }
        threads++
      } else if (threads > 0) {
        break
      }
    }

    if (threads > 0 && root.cores !== threads) cores = threads
    if (root.opened && threads > 0) {
      lastCores = coreNow
      coreUsage = coreUse
    }
    cpuHistory = pushSample(cpuHistory, cpu)
  }

  function parseMem(text) {
    var lines = String(text || "").split("\n")
    var mem = {}
    var seen = 0
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^(MemTotal|MemAvailable|MemFree|Buffers|Cached|SReclaimable|SwapTotal|SwapFree):\s+(\d+)/)
      if (!m) continue
      mem[m[1]] = Number(m[2])
      seen++
      if (seen >= 8) break
    }
    if (mem.MemTotal) {
      memTotal = mem.MemTotal
      memUsed = mem.MemTotal - (mem.MemAvailable || 0)
      ram = Math.max(0, Math.min(1, memUsed / memTotal))
      memCache = Math.max(0, Math.min((mem.Buffers || 0) + (mem.Cached || 0) + (mem.SReclaimable || 0),
                                      memTotal - memUsed - (mem.MemFree || 0)))
      ramHistory = pushSample(ramHistory, ram)
    }
    swapTotal = mem.SwapTotal || 0
    swapUsed = Math.max(0, swapTotal - (mem.SwapFree || 0))
    swap = swapTotal ? swapUsed / swapTotal : 0
  }

  function parseLoad(text) {
    var parts = String(text || "").trim().split(/\s+/)
    if (parts.length >= 3) load = parts[0] + "  " + parts[1] + "  " + parts[2]
  }

  function parseUptime(text) {
    var parts = String(text || "").trim().split(/\s+/)
    if (parts.length >= 1) uptime = Number(parts[0]) || 0
  }

  function parseTemp(text) {
    var v = Number(String(text || "").trim())
    if (isFinite(v) && v > 0) temp = v / 1000
  }

  function sampleNow() {
    statFile.reload()
    memFile.reload()
    if (root.opened) {
      if (loadFile.path !== "") loadFile.reload()
      if (uptimeFile.path !== "") uptimeFile.reload()
      if (tempFile.path !== "") tempFile.reload()
    }
  }

  Process {
    id: tempFinder
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name 2>/dev/null) in coretemp|k10temp|zenpower)"
      + " echo $h/temp1_input; break;; esac; done"]
    stdout: StdioCollector { onStreamFinished: root.tempPath = String(text).trim() }
  }

  FileView {
    id: statFile
    path: "/proc/stat"
    watchChanges: false
    printErrors: false
    onLoaded: root.parseStat(text())
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    watchChanges: false
    printErrors: false
    onLoaded: root.parseMem(text())
  }

  FileView {
    id: loadFile
    path: root.opened ? "/proc/loadavg" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.parseLoad(text())
  }

  FileView {
    id: uptimeFile
    path: root.opened ? "/proc/uptime" : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.parseUptime(text())
  }

  FileView {
    id: tempFile
    path: root.opened && root.tempPath !== "" ? root.tempPath : ""
    watchChanges: false
    printErrors: false
    onLoaded: root.parseTemp(text())
  }

  Timer {
    interval: 2000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleNow()
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
  onOpenedChanged: if (opened) sampleNow()
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
    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
  }

  // One stat: dim label, then the value in tabular figures so the numbers
  // don't shift as they update ("CPU 12%").
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
        textFormat: Text.PlainText
        color: themePalette.soft
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Text {
        id: valueText
        text: Math.round(stat.value * 100) + "%"
        textFormat: Text.PlainText
        color: stat.value >= 0.7 ? stat.level : themePalette.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.features: { "tnum": 1 }
        renderType: Text.NativeRendering
        Behavior on color { ColorAnimation { duration: Style.duration(300) } }
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

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"

// System panel: lazy-built on first open via KeyboardPanel.content. Shows
// CPU live GPU-rendered sparkline + per-thread bars, segmented Memory/Swap,
// and the top 5 processes (updated in-place from a single /proc awk pass).
Panel {
  id: root
  moduleName: "anik.resources"
  ipcTarget: "anik.resources"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var stats: null

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  AnikPalette { id: themePalette }

  // "cpu" or "mem" sorting for the Top Processes card.
  property string sortBy: "cpu"
  property var prevProcTicks: ({})
  property double prevTotalTicks: 0
  property double lastSampleAt: 0
  property var lastRawProcs: []
  property real lastMemTotal: 0

  ListModel {
    id: procModel
    ListElement { pid: 0; name: "—"; cpu: -1; mem: 0 }
    ListElement { pid: 0; name: "—"; cpu: -1; mem: 0 }
    ListElement { pid: 0; name: "—"; cpu: -1; mem: 0 }
    ListElement { pid: 0; name: "—"; cpu: -1; mem: 0 }
    ListElement { pid: 0; name: "—"; cpu: -1; mem: 0 }
  }

  function open() {
    if (Date.now() - lastSampleAt > 5000) {
      prevProcTicks = ({})
      prevTotalTicks = 0
    }
    root.controller.show()
    refreshProcesses()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function openBtop() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    root.close()
  }

  function setSort(mode) {
    if (sortBy === mode) return
    sortBy = mode
    applyProcList(lastRawProcs, lastMemTotal)
  }

  function coreAt(index) {
    if (!root.stats || !root.stats.coreUsage || index < 0 || index >= root.stats.coreUsage.length) return 0
    return root.stats.coreUsage[index]
  }

  function peakHistory(points) {
    if (!points || points.length === 0) return 0
    var max = 0
    for (var i = 0; i < points.length; i++) if (points[i] > max) max = points[i]
    return max
  }

  function refreshProcesses() {
    if (!procSampler.running) procSampler.running = true
  }

  function gib(kb) { return (kb / 1048576).toFixed(1) }

  function uptimeText(s) {
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    return "up " + (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m"
  }

  function dim(a) { return Qt.rgba(themePalette.text.r, themePalette.text.g, themePalette.text.b, a) }
  function accent(a) { return Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, a) }

  function applyProcList(entries, memTotal) {
    if (!entries || entries.length === 0) return
    var sorted = entries.slice()
    sorted.sort(function(a, b) {
      if (root.sortBy === "mem") {
        if (b.mem !== a.mem) return b.mem - a.mem
        return b.cpu - a.cpu
      }
      if (a.cpu >= 0 && b.cpu >= 0 && b.cpu !== a.cpu) return b.cpu - a.cpu
      return b.mem - a.mem
    })

    for (var i = 0; i < 5; i++) {
      var item = i < sorted.length ? sorted[i] : { pid: 0, name: "—", cpu: -1, mem: 0 }
      procModel.setProperty(i, "pid", item.pid)
      procModel.setProperty(i, "name", item.name)
      procModel.setProperty(i, "cpu", item.cpu)
      procModel.setProperty(i, "mem", item.mem)
    }
  }

  function parseProcs(text) {
    var lines = String(text || "").split("\n")
    var parsed = []
    var curTotal = 0
    var memTotal = 0

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line) continue
      var cols = line.split("\t")
      if (cols[0] === "META") {
        curTotal = Number(cols[1]) || 0
        memTotal = Number(cols[2]) || 0
        continue
      }
      if (cols.length < 4) continue
      var name = cols[1]
      if (name === "gawk" || name === "sh") continue
      parsed.push({
        pid: Number(cols[0]) || 0,
        name: name,
        ticks: Number(cols[2]) || 0,
        rss: Number(cols[3]) || 0
      })
    }

    var dTotal = curTotal > prevTotalTicks && prevTotalTicks > 0 ? (curTotal - prevTotalTicks) : 0
    var nextTicks = {}
    var entries = []
    var hadDelta = false

    for (var j = 0; j < parsed.length; j++) {
      var p = parsed[j]
      nextTicks[p.pid] = p.ticks
      var cpuPct = -1
      if (dTotal > 0 && prevProcTicks[p.pid] !== undefined) {
        // Total system CPU % (0-100%, Solaris mode) to match the CPU card headline.
        cpuPct = Math.max(0, Math.min(100, ((p.ticks - prevProcTicks[p.pid]) / dTotal) * 100))
        hadDelta = true
      }
      var memPct = memTotal > 0 ? Math.max(0, (p.rss / memTotal) * 100) : 0
      entries.push({ pid: p.pid, name: p.name, cpu: cpuPct, mem: memPct })
    }

    prevProcTicks = nextTicks
    prevTotalTicks = curTotal
    lastSampleAt = Date.now()
    lastRawProcs = entries
    lastMemTotal = memTotal
    applyProcList(entries, memTotal)

    // On the very first open, take one quick delta 250ms later so CPU% fills immediately.
    if (!hadDelta && root.opened && !firstCpuTimer.running)
      firstCpuTimer.restart()
  }

  // Single gawk pass over /proc (exec replaces sh; ~35ms, no top/sleep overhead).
  Process {
    id: procSampler
    command: [
      "sh", "-c",
      "exec gawk 'FILENAME==\"/proc/meminfo\"&&/^MemTotal:/{m=$2;nextfile}"
      + " FILENAME==\"/proc/stat\"&&$1==\"cpu\"{t=$2+$3+$4+$5+$6+$7+$8;nextfile}"
      + " FNR==1{if(match($0,/\\((.*)\\)/,n)){rest=substr($0,RSTART+RLENGTH+1);split(rest,a,\" \");"
      + " if(a[22]>0){p=FILENAME;gsub(/^\\/proc\\/|\\/stat$/,\"\",p);"
      + " print p\"\\t\"n[1]\"\\t\"(a[12]+a[13])\"\\t\"(a[22]*4)}}nextfile}"
      + " END{printf \"META\\t%.0f\\t%.0f\\n\",t,m}' /proc/meminfo /proc/stat /proc/[0-9]*/stat 2>/dev/null"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseProcs(text)
    }
  }

  Timer {
    id: firstCpuTimer
    interval: 250
    repeat: false
    onTriggered: if (root.opened) root.refreshProcesses()
  }

  Timer {
    interval: 2500
    running: root.opened
    repeat: true
    onTriggered: root.refreshProcesses()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(396))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight || Style.space(540), Style.space(660))

    content: Component {
      PanelKeyCatcher {
        id: keyCatcher
        implicitHeight: column.implicitHeight
        onCloseRequested: root.close()
        Component.onCompleted: if (root.opened) forceActiveFocus()

        ColumnLayout {
          id: column
          width: parent.width
          spacing: Style.space(10)

          // ---- Header
          RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Style.space(2)
            Layout.rightMargin: Style.space(2)
            Layout.bottomMargin: Style.space(2)
            spacing: Style.space(10)

            Column {
              Layout.fillWidth: true
              spacing: Style.space(2)

              Text {
                text: "System"
                textFormat: Text.PlainText
                font.family: "Adwaita Sans"
                font.pixelSize: Style.font.heading
                font.weight: Font.Bold
                color: themePalette.textBright
              }

              Row {
                spacing: Style.space(6)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(6); height: width; radius: width / 2
                  color: themePalette.accent
                }

                Text {
                  text: {
                    if (!root.stats) return ""
                    var parts = [root.uptimeText(root.stats.uptime)]
                    if (root.stats.load !== "") parts.push("load " + root.stats.load.split("  ")[0])
                    return parts.join("  ·  ")
                  }
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.features: { "tnum": 1 }
                  color: root.dim(0.58)
                }
              }
            }

            GhostButton {
              Layout.alignment: Qt.AlignVCenter
              icon: "󰄪"
              label: "btop"
              onClicked: root.openBtop()
            }
          }

          // ---- CPU Tile
          Tile {
            id: cpuTile
            Layout.fillWidth: true
            icon: "󰓅"
            title: "CPU"
            value: root.stats ? root.stats.cpu : 0
            badgeText: root.stats && root.stats.cores > 0 ? root.stats.cores + " threads" : ""
            asideChip: root.stats && root.stats.temp >= 0 ? Math.round(root.stats.temp) + "°C" : ""
            asideHot: root.stats && root.stats.temp >= 85 ? 2 : (root.stats && root.stats.temp >= 70 ? 1 : 0)
            subNote: root.stats ? "peak " + Math.round(root.peakHistory(root.stats.cpuHistory) * 100) + "%" : ""

            Graph {
              width: parent.width
              active: root.opened
              points: root.stats ? root.stats.cpuHistory : []
              stroke: cpuTile.level
            }

            // Per-thread activity bars (fixed model count so delegates never rebuild)
            Item {
              width: parent.width
              height: Style.space(22)
              visible: coreRepeater.count > 0

              Row {
                id: coreRow
                anchors.fill: parent
                spacing: Style.space(5)
                readonly property int n: Math.max(1, coreRepeater.count)

                Repeater {
                  id: coreRepeater
                  model: root.stats ? root.stats.cores : 0

                  Rectangle {
                    required property int index
                    readonly property real usage: root.coreAt(index)
                    width: (coreRow.width - coreRow.spacing * (coreRow.n - 1)) / coreRow.n
                    height: coreRow.height
                    radius: Style.space(4)
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.04)
                    clip: true

                    Rectangle {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      radius: Math.max(2, parent.radius - 1)
                      height: Math.max(Style.space(3), parent.height * Math.min(1, usage))
                      color: usage >= 0.9 ? themePalette.alert
                        : (usage >= 0.7 ? themePalette.warn
                        : root.accent(0.45 + 0.55 * Math.min(1, usage * 1.5)))
                      Behavior on height { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
                    }
                  }
                }
              }
            }
          }

          // ---- Memory Tile
          Tile {
            id: memTile
            Layout.fillWidth: true
            icon: "󰍛"
            title: "Memory"
            value: root.stats ? root.stats.ram : 0
            asideText: root.stats && root.stats.memTotal > 0
              ? root.gib(root.stats.memUsed) + " / " + root.gib(root.stats.memTotal) + " GiB" : ""

            readonly property real total: root.stats ? Math.max(1, root.stats.memTotal) : 1
            readonly property real usedFrac: root.stats ? root.stats.memUsed / total : 0
            readonly property real cacheFrac: root.stats ? root.stats.memCache / total : 0
            readonly property bool swapActive: root.stats ? root.stats.swapUsed > 1024 : false

            Rectangle {
              width: parent.width
              height: Style.space(10)
              radius: height / 2
              color: Qt.rgba(1, 1, 1, 0.07)
              clip: true

              Rectangle {
                id: usedSeg
                height: parent.height
                radius: parent.radius
                width: Math.max(height, parent.width * memTile.usedFrac)
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0; color: root.accent(0.75) }
                  GradientStop { position: 1; color: memTile.level }
                }
              }

              Rectangle {
                x: usedSeg.width + 2
                height: parent.height
                radius: parent.radius
                width: Math.max(0, parent.width * memTile.cacheFrac - 2)
                color: root.accent(0.30)
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(12)

              Legend { swatch: memTile.level; label: "Used"; amount: root.stats ? root.gib(root.stats.memUsed) + "G" : "" }
              Legend { swatch: root.accent(0.45); label: "Cache"; amount: root.stats ? root.gib(root.stats.memCache) + "G" : "" }
              Legend {
                swatch: Qt.rgba(1, 1, 1, 0.22); label: "Free"
                amount: root.stats ? root.gib(Math.max(0, root.stats.memTotal - root.stats.memUsed - root.stats.memCache)) + "G" : ""
              }
              Item { Layout.fillWidth: true }
            }

            // Compact inline Swap readout when idle; expand Swap bar only when active.
            Column {
              visible: root.stats ? root.stats.swapTotal > 0 : false
              width: parent.width
              spacing: Style.space(6)

              Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06) }

              RowLayout {
                width: parent.width
                Caption { Layout.fillWidth: true; text: "Swap" }
                Caption {
                  text: root.stats ? root.gib(root.stats.swapUsed) + " / " + root.gib(root.stats.swapTotal) + " GiB" : ""
                  color: memTile.swapActive ? themePalette.text : root.dim(0.55)
                }
              }

              Rectangle {
                visible: memTile.swapActive
                width: parent.width
                height: Style.space(4)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.07)

                Rectangle {
                  readonly property real v: root.stats ? root.stats.swap : 0
                  height: parent.height
                  radius: parent.radius
                  width: Math.max(v > 0 ? height : 0, parent.width * Math.min(1, v))
                  color: v >= 0.7 ? themePalette.warn : root.accent(0.8)
                }
              }
            }
          }

          // ---- Top Processes Card
          CardBox {
            Layout.fillWidth: true

            Column {
              id: procContent
              width: parent.width
              spacing: Style.space(6)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  Layout.fillWidth: true
                  text: "TOP PROCESSES"
                  textFormat: Text.PlainText
                  font.family: "Adwaita Sans"
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                  font.letterSpacing: 1.2
                  color: root.dim(0.58)
                }

                SortHead {
                  label: "CPU"
                  active: root.sortBy === "cpu"
                  onClicked: root.setSort("cpu")
                }

                SortHead {
                  label: "MEM"
                  active: root.sortBy === "mem"
                  onClicked: root.setSort("mem")
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(2)

                Repeater {
                  model: procModel

                  Rectangle {
                    id: procRow
                    required property int pid
                    required property string name
                    required property real cpu
                    required property real mem
                    required property int index

                    readonly property real share: {
                      if (root.sortBy === "mem") {
                        var topMem = procModel.count > 0 ? procModel.get(0).mem : 0
                        return topMem > 0 ? Math.min(1, mem / topMem) : 0
                      }
                      var topCpu = procModel.count > 0 ? procModel.get(0).cpu : 0
                      return topCpu > 0 && cpu >= 0 ? Math.min(1, cpu / topCpu) : 0
                    }

                    width: parent.width
                    height: Style.space(32)
                    radius: Style.space(8)
                    color: Qt.rgba(1, 1, 1, procArea.containsMouse ? 0.06 : 0)
                    Behavior on color { ColorAnimation { duration: Style.duration(110) } }

                    MouseArea {
                      id: procArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openBtop()
                    }

                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(4)
                      spacing: Style.space(8)

                      Rectangle {
                        Layout.preferredWidth: Style.space(22)
                        Layout.preferredHeight: Style.space(22)
                        radius: Style.space(7)
                        color: procRow.index === 0 ? root.accent(0.20) : Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: procRow.index === 0 ? root.accent(0.35) : Qt.rgba(1, 1, 1, 0.07)

                        Text {
                          anchors.centerIn: parent
                          text: procRow.name.length > 0 ? procRow.name.charAt(0).toUpperCase() : "·"
                          textFormat: Text.PlainText
                          font.family: "Adwaita Sans"
                          font.pixelSize: Style.font.bodySmall
                          font.weight: Font.DemiBold
                          color: procRow.index === 0 ? themePalette.accent : root.dim(0.75)
                        }
                      }

                      Text {
                        Layout.fillWidth: true
                        text: procRow.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        color: procRow.pid > 0 ? themePalette.textBright : root.dim(0.4)
                      }

                      Rectangle {
                        Layout.preferredWidth: Style.space(38)
                        Layout.preferredHeight: 3
                        radius: 1.5
                        color: Qt.rgba(1, 1, 1, 0.07)

                        Rectangle {
                          height: parent.height
                          radius: parent.radius
                          width: procRow.share > 0 ? Math.max(height, parent.width * procRow.share) : 0
                          color: procRow.cpu >= 25 ? themePalette.warn : root.accent(0.85)
                        }
                      }

                      Text {
                        Layout.preferredWidth: Style.space(48)
                        horizontalAlignment: Text.AlignRight
                        text: procRow.cpu >= 0 ? procRow.cpu.toFixed(1) + "%" : "—"
                        textFormat: Text.PlainText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.features: { "tnum": 1 }
                        color: procRow.cpu >= 25 ? themePalette.warn : (root.sortBy === "cpu" ? themePalette.textBright : root.dim(0.65))
                      }

                      Text {
                        Layout.preferredWidth: Style.space(48)
                        horizontalAlignment: Text.AlignRight
                        text: procRow.pid > 0 ? procRow.mem.toFixed(1) + "%" : "—"
                        textFormat: Text.PlainText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.features: { "tnum": 1 }
                        color: root.sortBy === "mem" ? themePalette.textBright : root.dim(0.58)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Opaque-tinted dark glass card surface so underlying window text never bleeds through.
  component CardBox: Rectangle {
    id: cardBox
    default property alias content: innerCol.data
    implicitHeight: innerCol.implicitHeight + Style.space(24)
    radius: Style.space(14)
    color: Qt.rgba(themePalette.deep.r, themePalette.deep.g, themePalette.deep.b, 0.94)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    Rectangle {
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: 1
      width: parent.width - parent.radius * 2
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
        GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
      }
    }

    Column {
      id: innerCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(8)
    }
  }

  // Telemetry tile built on CardBox.
  component Tile: CardBox {
    id: tile
    property string icon: ""
    property string title: ""
    property real value: 0
    property string badgeText: ""
    property string asideText: ""
    property string asideChip: ""
    property int asideHot: 0
    property string subNote: ""
    default property alias tileContent: extra.data
    readonly property color level: value >= 0.9 ? themePalette.alert : (value >= 0.7 ? themePalette.warn : themePalette.accent)

    Column {
      width: parent.width
      spacing: Style.space(4)

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: tile.icon
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          color: tile.level
          Behavior on color { ColorAnimation { duration: Style.duration(250) } }
        }

        Text {
          text: tile.title.toUpperCase()
          textFormat: Text.PlainText
          font.family: "Adwaita Sans"
          font.pixelSize: Style.font.caption
          font.weight: Font.DemiBold
          font.letterSpacing: 1.2
          color: root.dim(0.65)
        }

        Rectangle {
          visible: tile.badgeText !== ""
          implicitWidth: badgeLbl.implicitWidth + Style.space(10)
          implicitHeight: Style.space(18)
          radius: height / 2
          color: Qt.rgba(1, 1, 1, 0.06)

          Text {
            id: badgeLbl
            anchors.centerIn: parent
            text: tile.badgeText
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.dim(0.58)
          }
        }

        Item { Layout.fillWidth: true }

        Text {
          visible: tile.asideText !== ""
          text: tile.asideText
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.features: { "tnum": 1 }
          color: root.dim(0.62)
        }

        Rectangle {
          visible: tile.asideChip !== ""
          implicitWidth: chipLbl.implicitWidth + Style.space(12)
          implicitHeight: Style.space(20)
          radius: height / 2
          color: tile.asideHot === 2
            ? Qt.rgba(themePalette.alert.r, themePalette.alert.g, themePalette.alert.b, 0.18)
            : (tile.asideHot === 1
              ? Qt.rgba(themePalette.warn.r, themePalette.warn.g, themePalette.warn.b, 0.16)
              : Qt.rgba(1, 1, 1, 0.06))

          Text {
            id: chipLbl
            anchors.centerIn: parent
            text: tile.asideChip
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
            color: tile.asideHot === 2 ? themePalette.alert
              : (tile.asideHot === 1 ? themePalette.warn : root.dim(0.72))
          }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(4)

        Row {
          spacing: 1
          Text {
            id: bigValue
            text: Math.round(tile.value * 100)
            textFormat: Text.PlainText
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.display
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
            color: tile.value >= 0.7 ? tile.level : themePalette.textBright
            Behavior on color { ColorAnimation { duration: Style.duration(250) } }
          }
          Text {
            anchors.baseline: bigValue.baseline
            text: "%"
            textFormat: Text.PlainText
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
            color: root.dim(0.5)
          }
        }

        Item { Layout.fillWidth: true }

        Text {
          Layout.alignment: Qt.AlignBottom
          Layout.bottomMargin: Style.space(3)
          visible: tile.subNote !== ""
          text: tile.subNote
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
          color: root.dim(0.5)
        }
      }
    }

    Column {
      id: extra
      width: parent.width
      spacing: Style.space(8)
    }
  }

  // GPU-accelerated smooth Bezier area graph (paused when panel is closed).
  component Graph: Item {
    id: graph
    property bool active: false
    property var points: []
    property color stroke: themePalette.accent
    height: Style.space(42)

    readonly property var geometry: {
      if (!active || width <= 0 || height <= 0)
        return { stroke: "", fill: "", endX: -10, endY: -10 }
      var p = points || []
      if (p.length < 2)
        return { stroke: "", fill: "", endX: -10, endY: -10 }
      var n = root.stats ? root.stats.historyLength : 60
      var w = width, h = height
      var step = w / (n - 1)
      var x0 = w - (p.length - 1) * step
      var yOf = function(v) { return 4 + (h - 7) * (1 - Math.max(0, Math.min(1, v))) }
      var sy0 = yOf(p[0]).toFixed(1)
      var d = "M " + x0.toFixed(1) + " " + sy0
      var endX = w, endY = Number(sy0)
      for (var i = 1; i < p.length; i++) {
        var xa = x0 + (i - 1) * step
        var xb = x0 + i * step
        var xm = ((xa + xb) / 2).toFixed(1)
        var ya = yOf(p[i - 1]).toFixed(1)
        var yb = yOf(p[i]).toFixed(1)
        d += " C " + xm + " " + ya + " " + xm + " " + yb + " " + xb.toFixed(1) + " " + yb
        if (i === p.length - 1) { endX = xb; endY = Number(yb) }
      }
      var fill = d + " L " + endX.toFixed(1) + " " + h.toFixed(1) + " L " + x0.toFixed(1) + " " + h.toFixed(1) + " Z"
      return { stroke: d, fill: fill, endX: endX, endY: endY }
    }

    // Subtle horizontal gridlines
    Repeater {
      model: [0.33, 0.67]
      Rectangle {
        required property real modelData
        width: parent.width
        height: 1
        y: Math.round(parent.height * modelData)
        color: Qt.rgba(1, 1, 1, 0.05)
      }
    }

    Shape {
      anchors.fill: parent
      visible: graph.geometry.stroke !== ""
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillGradient: LinearGradient {
          x1: 0; y1: 0; x2: 0; y2: graph.height
          GradientStop { position: 0; color: Qt.rgba(graph.stroke.r, graph.stroke.g, graph.stroke.b, 0.32) }
          GradientStop { position: 1; color: Qt.rgba(graph.stroke.r, graph.stroke.g, graph.stroke.b, 0.0) }
        }
        PathSvg { path: graph.geometry.fill }
      }

      ShapePath {
        strokeWidth: 1.75
        strokeColor: graph.stroke
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: graph.geometry.stroke }
      }
    }

    // Live indicator dot on the newest sample
    Rectangle {
      visible: graph.geometry.stroke !== ""
      x: Math.min(parent.width - width, graph.geometry.endX - width / 2)
      y: graph.geometry.endY - height / 2
      width: Style.space(9); height: width; radius: width / 2
      color: Qt.rgba(graph.stroke.r, graph.stroke.g, graph.stroke.b, 0.25)

      Rectangle {
        anchors.centerIn: parent
        width: Style.space(4); height: width; radius: width / 2
        color: graph.stroke
      }
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.features: { "tnum": 1 }
    color: root.dim(0.55)
  }

  component SortHead: Item {
    id: sortHead
    property string label: ""
    property bool active: false
    signal clicked()

    Layout.preferredWidth: Style.space(48)
    Layout.preferredHeight: Style.space(18)

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: sortHead.label
      textFormat: Text.PlainText
      font.family: "Adwaita Sans"
      font.pixelSize: Style.font.caption
      font.weight: Font.DemiBold
      font.letterSpacing: 1.2
      color: sortHead.active ? themePalette.accent : (sortArea.containsMouse ? themePalette.text : root.dim(0.45))
    }

    Rectangle {
      visible: sortHead.active
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: Style.space(22)
      height: 1.5
      radius: 1
      color: themePalette.accent
    }

    MouseArea {
      id: sortArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sortHead.clicked()
    }
  }

  component Legend: Row {
    property color swatch: themePalette.accent
    property string label: ""
    property string amount: ""
    spacing: Style.space(5)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7); height: width; radius: width / 2
      color: parent.swatch
    }
    Text {
      text: parent.label
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      color: root.dim(0.55)
    }
    Text {
      text: parent.amount
      textFormat: Text.PlainText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.features: { "tnum": 1 }
      color: themePalette.text
    }
  }

  component GhostButton: Rectangle {
    id: ghost
    property string icon: ""
    property string label: ""
    signal clicked()

    implicitWidth: ghostRow.implicitWidth + Style.space(22)
    implicitHeight: Style.space(28)
    radius: height / 2
    color: ghostArea.containsMouse ? root.accent(0.18) : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: ghostArea.containsMouse ? root.accent(0.45) : Qt.rgba(1, 1, 1, 0.10)
    scale: ghostArea.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: Style.duration(140) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(140) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(90) } }

    Row {
      id: ghostRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ghost.icon
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        color: ghostArea.containsMouse ? themePalette.accent : root.dim(0.75)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ghost.label
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        color: ghostArea.containsMouse ? themePalette.accent : themePalette.text
      }
    }

    MouseArea {
      id: ghostArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ghost.clicked()
    }
  }
}

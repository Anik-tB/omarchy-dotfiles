import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"

// System panel: drops down under the resources widget. Header with uptime and
// a btop button; a CPU tile (big figure, smoothed live graph, one bar per
// thread) and a Memory tile (big figure, used / cache / free bar, swap); then
// the five busiest processes, refreshed every three seconds while open. Esc or clicking
// outside closes it. All numbers come from the widget (`stats`), except the
// process list, which only runs while the panel is visible.
Panel {
  id: root
  moduleName: "anik.resources"
  ipcTarget: "anik.resources"
  manageIpc: false

  property var anchorItem: null
  // The bar identifies a panel by the widget in its slot, not this item.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  // The widget itself: cpu, ram, swap, histories, temp, load, uptime...
  property var stats: null

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  AnikPalette { id: themePalette }

  property var processes: []

  function open() { root.controller.show(); refreshProcesses() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function openBtop() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    root.close()
  }

  function refreshProcesses() { if (!top.running) top.running = true }

  function gib(kb) { return (kb / 1048576).toFixed(1) }

  function uptimeText(s) {
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    return "up " + (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m"
  }

  function dim(a) { return Qt.rgba(themePalette.text.r, themePalette.text.g, themePalette.text.b, a) }
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function accent(a) { return Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, a) }

  // top's second frame: per-process CPU over the last half second (the first
  // frame is averaged since each process started).
  Process {
    id: top
    command: ["sh", "-c", "top -b -n2 -d0.5 -o %CPU -w 512 | awk '/^ *PID/{n++} n==2'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        if (lines.length < 2) return
        var head = lines[0].trim().split(/\s+/)
        var ci = head.indexOf("%CPU"), mi = head.indexOf("%MEM"), ni = head.indexOf("COMMAND")
        var list = []
        for (var i = 1; i < lines.length && list.length < 5; i++) {
          var f = lines[i].trim().split(/\s+/)
          if (f.length <= ni) continue
          var name = f.slice(ni).join(" ")
          if (name === "top") continue
          list.push({ name: name, cpu: Number(f[ci]) || 0, mem: Number(f[mi]) || 0 })
        }
        root.processes = list
      }
    }
  }

  Timer {
    interval: 3000
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
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(8)

        // ---- Header
        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Style.space(4)
          Layout.rightMargin: Style.space(2)
          Layout.bottomMargin: Style.space(4)
          spacing: Style.space(10)

          Column {
            Layout.fillWidth: true
            spacing: Style.space(1)

            Text {
              text: "System"
              textFormat: Text.PlainText
              font.family: "Adwaita Sans"
              font.pixelSize: Style.font.title + 2
              font.weight: Font.Bold
              color: themePalette.textBright
            }

            Row {
              spacing: Style.space(6)

              // static: a looping pulse redraws the panel every frame (~35% CPU)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(6); height: width; radius: width / 2
                color: themePalette.accent
              }

              Text {
                text: root.stats ? root.uptimeText(root.stats.uptime) : ""
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.features: { "tnum": 1 }
                color: root.dim(0.5)
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

        // ---- CPU
        Tile {
          id: cpuTile
          Layout.fillWidth: true
          icon: "󰓅"
          title: "CPU"
          value: root.stats ? root.stats.cpu : 0
          aside: {
            if (!root.stats) return ""
            var d = []
            if (root.stats.temp >= 0) d.push(Math.round(root.stats.temp) + "°C")
            if (root.stats.load !== "") d.push("load " + root.stats.load.split("  ")[0])
            return d.join("  ·  ")
          }

          Graph {
            width: parent.width
            points: root.stats ? root.stats.cpuHistory : []
            stroke: cpuTile.level
          }

          // one bar per thread, filling from the bottom
          Item {
            width: parent.width
            height: Style.space(18)
            visible: coreRepeater.count > 0

            Row {
              id: coreRow
              anchors.fill: parent
              spacing: Style.space(4)
              readonly property int n: Math.max(1, coreRepeater.count)

              Repeater {
                id: coreRepeater
                model: root.stats ? root.stats.coreUsage : []

                Rectangle {
                  required property var modelData
                  width: (coreRow.width - coreRow.spacing * (coreRow.n - 1)) / coreRow.n
                  height: coreRow.height
                  radius: Style.space(3)
                  color: Qt.rgba(1, 1, 1, 0.05)
                  clip: true

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    radius: parent.radius
                    height: Math.max(2, parent.height * Math.min(1, modelData))
                    color: modelData >= 0.9 ? themePalette.alert : modelData >= 0.7 ? themePalette.warn : root.accent(0.45 + 0.55 * Math.min(1, modelData * 1.6))
                    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: 300 } }
                  }
                }
              }
            }
          }

          Caption {
            text: root.stats && root.stats.cores > 0 ? root.stats.cores + " threads" : ""
          }
        }

        // ---- Memory
        Tile {
          id: memTile
          Layout.fillWidth: true
          icon: "󰍛"
          title: "Memory"
          value: root.stats ? root.stats.ram : 0
          aside: root.stats && root.stats.memTotal > 0
            ? root.gib(root.stats.memUsed) + " / " + root.gib(root.stats.memTotal) + " GiB" : ""

          readonly property real total: root.stats ? Math.max(1, root.stats.memTotal) : 1
          readonly property real usedFrac: root.stats ? root.stats.memUsed / total : 0
          readonly property real cacheFrac: root.stats ? root.stats.memCache / total : 0

          // used | cache | free (no width Behaviors: animating these kept the
          // panel redrawing, ~9% CPU while open)
          Rectangle {
            width: parent.width
            height: Style.space(10)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.06)
            clip: true

            Rectangle {
              id: usedSeg
              height: parent.height
              radius: parent.radius
              width: Math.max(height, parent.width * memTile.usedFrac)
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.accent(0.7) }
                GradientStop { position: 1; color: memTile.level }
              }
            }

            Rectangle {
              x: usedSeg.width + 2
              height: parent.height
              radius: parent.radius
              width: Math.max(0, parent.width * memTile.cacheFrac - 2)
              color: root.accent(0.28)
            }
          }

          Row {
            spacing: Style.space(14)
            Legend { swatch: memTile.level; label: "Used"; amount: root.stats ? root.gib(root.stats.memUsed) : "" }
            Legend { swatch: root.accent(0.4); label: "Cache"; amount: root.stats ? root.gib(root.stats.memCache) : "" }
            Legend {
              swatch: Qt.rgba(1, 1, 1, 0.18); label: "Free"
              amount: root.stats ? root.gib(Math.max(0, root.stats.memTotal - root.stats.memUsed - root.stats.memCache)) : ""
            }
          }

          Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.06); visible: swapBlock.visible }

          // swap
          Column {
            id: swapBlock
            visible: root.stats ? root.stats.swapTotal > 0 : false
            width: parent.width
            spacing: Style.space(6)

            RowLayout {
              width: parent.width
              Caption { Layout.fillWidth: true; text: "Swap" }
              Caption { text: root.stats ? root.gib(root.stats.swapUsed) + " / " + root.gib(root.stats.swapTotal) + " GiB" : "" }
            }

            Rectangle {
              width: parent.width
              height: 4
              radius: 2
              color: Qt.rgba(1, 1, 1, 0.06)

              Rectangle {
                readonly property real v: root.stats ? root.stats.swap : 0
                height: parent.height
                radius: 2
                width: Math.max(v > 0 ? height : 0, parent.width * Math.min(1, v))
                color: v >= 0.7 ? themePalette.warn : root.accent(0.8)
                Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
              }
            }
          }
        }

        // ---- Top processes
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(4)
          Layout.leftMargin: Style.space(4)
          Layout.rightMargin: Style.space(10)
          spacing: Style.space(10)

          Text {
            Layout.fillWidth: true
            text: "TOP PROCESSES"
            textFormat: Text.PlainText
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: root.dim(0.5)
          }
          ColumnHead { text: "CPU" }
          ColumnHead { text: "MEM" }
        }

        Column {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Repeater {
            model: root.processes

            Rectangle {
              id: procRow
              required property var modelData
              required property int index
              readonly property real share: {
                var top = root.processes.length ? root.processes[0].cpu : 0
                return top > 0 ? Math.min(1, modelData.cpu / top) : 0
              }
              width: parent.width
              height: Style.space(34)
              radius: Style.space(9)
              color: Qt.rgba(1, 1, 1, procArea.containsMouse ? 0.05 : 0)
              Behavior on color { ColorAnimation { duration: 120 } }

              MouseArea { id: procArea; anchors.fill: parent; hoverEnabled: true }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                // monogram chip
                Rectangle {
                  Layout.preferredWidth: Style.space(24)
                  Layout.preferredHeight: Style.space(24)
                  radius: Style.space(8)
                  color: procRow.index === 0 ? root.accent(0.18) : Qt.rgba(1, 1, 1, 0.05)
                  border.width: 1
                  border.color: procRow.index === 0 ? root.accent(0.3) : Qt.rgba(1, 1, 1, 0.06)

                  Text {
                    anchors.centerIn: parent
                    text: procRow.modelData.name.charAt(0).toUpperCase()
                    font.family: "Adwaita Sans"
                    font.pixelSize: Style.font.bodySmall
                    font.weight: Font.DemiBold
                    color: procRow.index === 0 ? themePalette.accent : root.dim(0.7)
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: procRow.modelData.name
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: themePalette.textBright
                }

                // share of the busiest process
                Rectangle {
                  Layout.preferredWidth: Style.space(40)
                  Layout.preferredHeight: 3
                  radius: 1.5
                  color: Qt.rgba(1, 1, 1, 0.06)

                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: Math.max(height, parent.width * procRow.share)
                    color: procRow.modelData.cpu >= 50 ? themePalette.warn : root.accent(0.8)
                    Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                  }
                }

                Text {
                  Layout.preferredWidth: Style.space(48)
                  horizontalAlignment: Text.AlignRight
                  text: procRow.modelData.cpu.toFixed(1) + "%"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.features: { "tnum": 1 }
                  color: procRow.modelData.cpu >= 50 ? themePalette.warn : themePalette.text
                }

                Text {
                  Layout.preferredWidth: Style.space(48)
                  horizontalAlignment: Text.AlignRight
                  text: procRow.modelData.mem.toFixed(1) + "%"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.features: { "tnum": 1 }
                  color: root.dim(0.5)
                }
              }
            }
          }

          Text {
            visible: root.processes.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(10)
            bottomPadding: Style.space(10)
            text: "Reading processes…"
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.dim(0.45)
          }
        }
      }
    }
  }

  // Glass tile: icon + title and a side note on top, the big figure, then
  // whatever the tile holds (graph, bars, legend) stacked below.
  component Tile: Rectangle {
    id: tile
    property string icon: ""
    property string title: ""
    property real value: 0
    property string aside: ""
    default property alias content: extra.data
    readonly property color level: value >= 0.9 ? themePalette.alert : (value >= 0.7 ? themePalette.warn : themePalette.accent)

    implicitHeight: tileColumn.implicitHeight + Style.space(28)
    radius: Style.space(16)
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.055) }
      GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.02) }
    }
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.07)

    // top sheen
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
      id: tileColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      Column {
        width: parent.width
        spacing: Style.space(2)

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: tile.icon
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: tile.level
            Behavior on color { ColorAnimation { duration: 300 } }
          }
          Text {
            Layout.fillWidth: true
            text: tile.title.toUpperCase()
            textFormat: Text.PlainText
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: root.dim(0.6)
          }
          Text {
            text: tile.aside
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.features: { "tnum": 1 }
            color: root.dim(0.55)
          }
        }

        Row {
          spacing: Style.space(2)
          Text {
            id: bigValue
            text: Math.round(tile.value * 100)
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.displayLarge
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: tile.value >= 0.7 ? tile.level : themePalette.textBright
            Behavior on color { ColorAnimation { duration: 300 } }
          }
          Text {
            anchors.baseline: bigValue.baseline
            text: "%"
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.title
            font.weight: Font.Medium
            color: root.dim(0.45)
          }
        }
      }

      Column {
        id: extra
        width: parent.width
        spacing: Style.space(10)
      }
    }
  }

  // Smoothed area graph, newest sample on the right, fading into the tile.
  component Graph: Canvas {
    id: graph
    property var points: []
    property color stroke: themePalette.accent
    height: Style.space(40)
    onPointsChanged: requestPaint()
    onStrokeChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width, h = height, n = root.stats ? root.stats.historyLength : 60
      ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.045)
      ctx.lineWidth = 1
      for (var g = 1; g < 3; g++) {
        var gy = Math.round(h * g / 3) + 0.5
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
      }
      var p = points || []
      if (p.length < 2) return
      var step = w / (n - 1), x0 = w - (p.length - 1) * step
      var yOf = function(v) { return 3 + (h - 5) * (1 - Math.max(0, Math.min(1, v))) }
      var trace = function() {
        ctx.moveTo(x0, yOf(p[0]))
        for (var i = 1; i < p.length; i++) {
          var xa = x0 + (i - 1) * step, xb = x0 + i * step, xm = (xa + xb) / 2
          ctx.bezierCurveTo(xm, yOf(p[i - 1]), xm, yOf(p[i]), xb, yOf(p[i]))
        }
      }

      ctx.beginPath()
      trace()
      ctx.lineTo(w, h); ctx.lineTo(x0, h); ctx.closePath()
      var fill = ctx.createLinearGradient(0, 0, 0, h)
      fill.addColorStop(0, Qt.rgba(stroke.r, stroke.g, stroke.b, 0.32))
      fill.addColorStop(1, Qt.rgba(stroke.r, stroke.g, stroke.b, 0))
      ctx.fillStyle = fill
      ctx.fill()

      ctx.beginPath()
      trace()
      var line = ctx.createLinearGradient(0, 0, w, 0)
      line.addColorStop(0, Qt.rgba(stroke.r, stroke.g, stroke.b, 0.15))
      line.addColorStop(0.35, Qt.rgba(stroke.r, stroke.g, stroke.b, 0.85))
      line.addColorStop(1, stroke)
      ctx.strokeStyle = line
      ctx.lineWidth = 1.75
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.stroke()

      // live dot with a soft halo on the newest sample
      var ly = yOf(p[p.length - 1])
      ctx.beginPath(); ctx.arc(w - 4, ly, 4.5, 0, Math.PI * 2)
      ctx.fillStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, 0.22); ctx.fill()
      ctx.beginPath(); ctx.arc(w - 4, ly, 2.25, 0, Math.PI * 2)
      ctx.fillStyle = stroke; ctx.fill()
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.features: { "tnum": 1 }
    color: root.dim(0.5)
  }

  component ColumnHead: Text {
    Layout.preferredWidth: Style.space(48)
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    font.family: "Adwaita Sans"
    font.pixelSize: Style.font.caption
    font.weight: Font.DemiBold
    font.letterSpacing: 1.2
    color: root.dim(0.4)
  }

  // Swatch, label, amount in GiB.
  component Legend: Row {
    property color swatch: themePalette.accent
    property string label: ""
    property string amount: ""
    spacing: Style.space(6)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7); height: width; radius: width / 2
      color: parent.swatch
    }
    Text {
      text: parent.label
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      color: root.dim(0.5)
    }
    Text {
      text: parent.amount
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.features: { "tnum": 1 }
      color: themePalette.text
    }
  }

  // Quiet header button: glass fill, accent on hover.
  component GhostButton: Rectangle {
    id: ghost
    property string icon: ""
    property string label: ""
    signal clicked()

    implicitWidth: ghostRow.implicitWidth + Style.space(24)
    implicitHeight: Style.space(30)
    radius: height / 2
    color: ghostArea.containsMouse ? root.accent(0.16) : Qt.rgba(1, 1, 1, 0.05)
    border.width: 1
    border.color: ghostArea.containsMouse ? root.accent(0.4) : Qt.rgba(1, 1, 1, 0.09)
    scale: ghostArea.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    Row {
      id: ghostRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ghost.icon
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

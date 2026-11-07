import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"
import "../anik.notifications/Security.js" as Security

// Notification Centre: drops down under the bell. Header with "Notifications",
// a Do Not Disturb pill and Clear; below it the recent notifications as the
// same Apple-style cards the popups use, newest first. ✕ or right click on a
// card removes just that one. Esc or clicking outside closes the panel.
// Deliberately no keyboard shortcut for clearing: the panel holds keyboard
// focus while open, so a stray key must never wipe the history.
Panel {
  id: root
  moduleName: "anik.bell"
  ipcTarget: "anik.bell"
  manageIpc: false

  property var anchorItem: null
  // The bar identifies a panel by the widget in its slot, not this item.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Set by the widget from its own watchers.
  property bool dnd: false
  property int historyCount: 0

  // Omarchy 4.5 keeps history as one JSON array, newest first (anik.notifications).
  readonly property string historyFile: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history.json"

  AnikPalette { id: themePalette }

  property var entries: []

  function open() { root.openedAt = Date.now(); root.clearing = false; root.controller.show(); reload() }

  // Transitions: rows created right after opening fade/slide in one after
  // another; a dismissed row folds away before it leaves the list; Clear fades
  // every row out first. Rebuilt delegates (after a removal) appear at once.
  property double openedAt: 0
  property bool clearing: false

  function animateClear() {
    if (root.entries.length === 0) { root.clearAll(); return }
    root.clearing = true
    clearTimer.restart()
  }

  Timer {
    id: clearTimer
    interval: 220
    onTriggered: { root.clearAll(); root.clearing = false }
  }
  function close() { root.controller.hide() }

  // Clicking a history row does what clicking its popup did: run the toast's
  // own command (e.g. open a screenshot in the editor), otherwise focus the
  // sending app, launching it if it isn't open. Then the row is done.
  function openEntry(data) {
    var argv = Security.parseExecArgv(data.execArgv || "")
    if (argv) {
      Quickshell.execDetached(argv)
    } else {
      Quickshell.execDetached([
        Qt.resolvedUrl("../anik.notifications/open-app.sh").toString().replace("file://", ""),
        String(data.app || ""), String(data.appIcon || "")
      ])
    }
    root.close()
  }

  function copyEntry(text) {
    if (!text) return
    Quickshell.execDetached(["wl-copy", "--", String(text)])
    Quickshell.execDetached(["omarchy-osd", "-m", "Copied to clipboard", "-d", "1200"])
  }
  function toggle() { if (root.opened) root.close(); else root.open() }

  // A change while a read is in flight queues one more read, otherwise the
  // later state is lost (Clear: dismissAll then clear arrive back to back,
  // and the panel kept the pre-clear list).
  property bool reloadPending: false
  function reload() {
    if (reader.running) reloadPending = true
    else reader.running = true
  }
  onHistoryCountChanged: if (root.opened) reload()

  // History is the service's, so entries are removed through its IPC.
  function removeEntry(fileName) {
    var gone = entries.filter(function(e) { return e.fileName === fileName })[0]
    entries = entries.filter(function(e) { return e.fileName !== fileName })
    if (!gone) return
    remover.command = ["omarchy-shell", "notifications", "removeHistory", String(gone.key), String(gone.closed_ts)]
    remover.running = true
  }

  function clearAll() {
    entries = []
    if (root.bar) root.bar.run("sh -c 'omarchy-shell notifications dismissAll; omarchy-shell notifications clearHistory'")
  }

  function toggleDnd() {
    if (root.bar) root.bar.run("omarchy-shell notifications toggleDnd")
  }

  // history.json: [{ key, app, appIcon, summary, body, execArgv, urgency,
  // ts (s), closed_ts (s), ... }]. fileName stays the row id the list uses.
  Process {
    id: reader
    command: ["cat", root.historyFile]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var list = []
        try { list = JSON.parse(String(text || "[]")) } catch (err) { list = [] }
        if (!Array.isArray(list)) list = []
        for (var i = 0; i < list.length; i++) {
          var e = list[i]
          e.fileName = String(e.key) + ":" + String(e.closed_ts)
          e.timestamp = Number(e.ts || e.closed_ts || 0) * 1000
        }
        list.sort(function(a, b) { return (b.closed_ts || 0) - (a.closed_ts || 0) })
        root.entries = list
      }
    }
    onExited: {
      if (root.reloadPending) {
        root.reloadPending = false
        reader.running = true
      }
    }
  }

  Process { id: remover }

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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // ---- Header
        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Style.space(4)
          Layout.rightMargin: Style.space(2)
          Layout.preferredHeight: Style.space(30)
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Notifications"
            textFormat: Text.PlainText
            font.family: "Adwaita Sans"
            font.pixelSize: Style.font.heading
            font.weight: Font.Bold
            color: themePalette.textBright
          }

          PillButton {
            label: root.dnd ? "󰂛  Focus on" : "󰂚  Focus off"
            highlighted: root.dnd
            onClicked: root.toggleDnd()
          }

          PillButton {
            visible: root.entries.length > 0
            label: "Clear"
            onClicked: root.animateClear()
          }
        }

        // Hairline under the header.
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: Qt.rgba(1, 1, 1, 0.08)
        }

        // ---- Empty state: centred icon in a soft circle, title, subtitle.
        Item {
          visible: root.entries.length === 0
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
          Layout.fillWidth: true
          Layout.preferredHeight: emptyColumn.implicitHeight + Style.space(44)

          Column {
            id: emptyColumn
            anchors.centerIn: parent
            spacing: Style.space(6)

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(52)
              height: width
              radius: width / 2
              color: Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.08)
              border.width: 1
              border.color: Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.18)

              Text {
                anchors.centerIn: parent
                text: root.dnd ? "󰂛" : "󰂜"
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.display
                color: Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.75)
              }
            }

            Item { width: 1; height: Style.space(4) }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No Notifications"
              textFormat: Text.PlainText
              font.family: "Adwaita Sans"
              font.pixelSize: Style.font.subtitle
              font.weight: Font.DemiBold
              color: themePalette.text
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.dnd ? "Focus is on — notifications are silenced" : "You're all caught up"
              textFormat: Text.PlainText
              font.family: "Adwaita Sans"
              font.pixelSize: Style.font.bodySmall
              color: Qt.rgba(themePalette.text.r, themePalette.text.g, themePalette.text.b, 0.5)
            }
          }
        }

        // ---- Cards
        Flickable {
          id: scroller
          visible: root.entries.length > 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: cards.implicitHeight
          contentWidth: width
          contentHeight: cards.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: cards
            width: scroller.width
            spacing: 0

            Repeater {
              model: root.entries

              // One flat row per notification, hairline divider underneath
              // (except after the last), like a classic notification list.
              Item {
                id: entry
                required property var modelData
                required property int index
                width: cards.width
                clip: true
                property bool leaving: false
                height: leaving ? 0 : entryColumn.implicitHeight
                opacity: leaving || root.clearing ? 0 : 1
                Behavior on height { enabled: entry.leaving; NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                transform: Translate { id: entryShift }

                function dismiss() {
                  if (leaving) return
                  leaving = true
                  slideOut.start()
                  removeTimer.start()
                }
                NumberAnimation { id: slideOut; target: entryShift; property: "x"; to: Style.space(28); duration: 200; easing.type: Easing.InCubic }
                property real appearAlpha: 1
                Timer { id: removeTimer; interval: 230; onTriggered: root.removeEntry(entry.modelData.fileName) }

                // Fade + rise in when the panel has just opened, staggered.
                Component.onCompleted: {
                  if (Date.now() - root.openedAt < 800 && entry.index < 8) {
                    entry.appearAlpha = 0
                    appearShift.y = Style.space(8)
                    appear.start()
                  }
                }
                SequentialAnimation {
                  id: appear
                  PauseAnimation { duration: 45 * entry.index }
                  ParallelAnimation {
                    NumberAnimation { target: entry; property: "appearAlpha"; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: appearShift; property: "y"; to: 0; duration: 260; easing.type: Easing.OutCubic }
                  }
                }

              Column {
                id: entryColumn
                width: cards.width
                transform: Translate { id: appearShift }
                opacity: entry.appearAlpha

                NotificationCard {
                  width: cards.width
                  implicitWidth: cards.width
                  flat: true
                  app: entry.modelData.app || ""
                  appIcon: entry.modelData.appIcon || ""
                  summary: entry.modelData.summary || ""
                  body: entry.modelData.body || ""
                  image: entry.modelData.image || ""
                  glyph: entry.modelData.glyph || ""
                  urgency: entry.modelData.urgency === undefined ? 1 : entry.modelData.urgency
                  timestamp: entry.modelData.timestamp || 0
                  fontFamily: root.bar ? root.bar.fontFamily : ""
                  onCloseRequested: entry.dismiss()
                  onCardClicked: {
                    root.openEntry(entry.modelData)
                    root.removeEntry(entry.modelData.fileName)
                  }
                  onCopyRequested: function(text) { root.copyEntry(text) }
                }

                Rectangle {
                  visible: entry.index < root.entries.length - 1
                  width: cards.width
                  height: 1
                  color: Qt.rgba(1, 1, 1, 0.08)
                }
              }
              }
            }
          }
        }
      }
    }
  }

  // Small rounded pill used in the header.
  component PillButton: Rectangle {
    id: pill
    property string label: ""
    property bool highlighted: false
    signal clicked()

    implicitWidth: pillText.implicitWidth + Style.space(22)
    implicitHeight: Style.space(26)
    radius: height / 2
    color: highlighted
      ? Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, pillArea.containsMouse ? 0.30 : 0.20)
      : Qt.rgba(1, 1, 1, pillArea.containsMouse ? 0.12 : 0.06)
    border.width: 1
    border.color: highlighted
      ? Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.45)
      : Qt.rgba(1, 1, 1, 0.10)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      id: pillText
      anchors.centerIn: parent
      text: pill.label
      textFormat: Text.PlainText
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      color: pill.highlighted ? themePalette.accent : themePalette.text
    }

    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }
}

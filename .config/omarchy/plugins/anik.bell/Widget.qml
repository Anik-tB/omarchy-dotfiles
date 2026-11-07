import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../anik.bar"

// Notification bell. An accent dot appears when notifications arrived since
// you last opened them. Click opens the Notification Centre panel (Panel.qml),
// right click toggles Do Not Disturb (bell with a slash), middle click clears
// the on-screen cards and the history.
//
// Standalone bar widgets can't reach the notification service object, so this
// reads the service's own state files (one JSON per on-screen card, one per
// history entry, and notifications.json for DND) and acts through its IPC.
BarWidget {
  id: root
  moduleName: "anik.bell"

  AnikPalette { id: themePalette }

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/"

  FolderListModel {
    id: onScreen
    folder: "file://" + root.stateDir + "notifications"
    nameFilters: ["*.json"]
    showDirs: false
  }

  FolderListModel {
    id: history
    folder: "file://" + root.stateDir + "notifications/history"
    nameFilters: ["*.json"]
    showDirs: false
  }

  FileView {
    id: settingsFile
    path: root.stateDir + "notifications.json"
    watchChanges: true
    onFileChanged: reload()
  }
  readonly property bool dnd: {
    try { return JSON.parse(settingsFile.text()).dnd === true } catch (e) { return false }
  }

  // Newest history entry, from its file name ("<ms timestamp>-<n>.json").
  readonly property double newest: {
    var latest = 0
    for (var i = 0; i < history.count; i++) {
      var stamp = parseFloat(String(history.get(i, "fileName")).split("-")[0])
      if (stamp > latest) latest = stamp
    }
    return latest
  }

  // When the bell was last opened. Kept across shell reloads; after a full
  // restart, whatever was already there counts as seen.
  PersistentProperties {
    id: seen
    reloadableId: "anik-bell"
    property double at: 0
  }
  Component.onCompleted: if (seen.at === 0) seen.at = Date.now()

  readonly property bool unread: !dnd && (newest > seen.at || onScreen.count > 0)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- Notification Centre panel
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = root
  }
  onBarChanged: injectPanel()

  // Shape contract the bar uses to route and switch popouts (see anik.weather).
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
    Binding { target: panelLoader.item; property: "dnd"; value: root.dnd; when: panelLoader.item !== null }
    Binding { target: panelLoader.item; property: "historyCount"; value: history.count; when: panelLoader.item !== null }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "󰂛" : (root.unread ? "󰂚" : "󰂜")
    dimmed: root.dnd
    // The panel is the detail view; no tooltip while it is open.
    tooltipText: root.opened ? "" : (root.dnd
      ? "Do Not Disturb is on · right click to turn off"
      : (history.count > 0 ? history.count + " recent notification" + (history.count === 1 ? "" : "s") : "No notifications")
        + " · right click: Do Not Disturb · middle click: clear")
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) {
        root.bar.run("omarchy-shell notifications toggleDnd")
      } else if (b === Qt.MiddleButton) {
        root.bar.run("sh -c 'omarchy-shell notifications dismissAll; omarchy-shell notifications clear'")
        seen.at = Date.now()
      } else {
        if (panelLoader.item) panelLoader.item.toggle()
        seen.at = Date.now()
      }
    }
  }

  // Unread dot, top-right of the glyph.
  Rectangle {
    visible: root.unread
    width: Style.space(6)
    height: width
    radius: width / 2
    color: themePalette.accent
    border.width: 1
    border.color: themePalette.background
    x: parent.width / 2 + Style.space(3)
    y: parent.height / 2 - Style.space(8)
  }
}

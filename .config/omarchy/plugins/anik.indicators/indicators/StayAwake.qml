import QtQuick
import Quickshell
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Ui

// Service is null under anik.bar (see Dnd.qml). The idle service (anik.idle)
// watches ~/.local/state/omarchy/indicators/stay-awake, so the CLI toggle that
// creates/removes it is enough; the folder model watches it for the state.
BarIndicator {
  id: root

  readonly property var idleService: bar?.shell?.firstPartyServiceFor("omarchy.idle")
  property bool pendingState: false
  property bool pending: false
  readonly property bool fileAwake: stateDir.count > 0

  // Anik: falls back to the state file when the bar gives no idle service.
  active: idleService ? idleService.stayAwake : (pending ? pendingState : fileAwake)
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: I18n.t("bar.allowIdleLock")
  inactiveTooltipText: I18n.t("bar.stayAwake")

  onFileAwakeChanged: pending = false

  FolderListModel {
    id: stateDir
    folder: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/indicators"
    nameFilters: ["stay-awake"]
    showDirs: false
    showHidden: true
  }

  Timer {
    id: pendingTimeout
    interval: 3000
    onTriggered: root.pending = false
  }

  function toggle() {
    if (root.idleService) {
      root.idleService.setIdleEnabled(root.active)
      return
    }
    root.pendingState = !root.active
    root.pending = true
    pendingTimeout.restart()
    Quickshell.execDetached(["omarchy-toggle-idle", root.pendingState ? "stay-awake" : "allow-idle"])
  }

  onPressed: function() { root.toggle() }
}

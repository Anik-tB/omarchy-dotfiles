import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The shell only hands the notification service to indicator clones when the
// active bar is the stock omarchy.bar. Under anik.bar it is null, so fall back
// to the CLI and read the state file the service writes.
BarIndicator {
  id: root

  readonly property var notificationService: bar?.shell?.firstPartyServiceFor("omarchy.notifications")
  property bool fileDnd: false
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : fileDnd

  active: dnd
  activeText: "󰂛"
  inactiveText: "󰂛"
  activeTooltipText: "Allow Notifications"
  inactiveTooltipText: "Silence Notifications"

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.fileDnd = JSON.parse(text()).dnd === true } catch (e) {}
    }
  }

  onPressed: function() {
    if (root.notificationService) {
      root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
    } else {
      root.fileDnd = !root.fileDnd
      Quickshell.execDetached(["omarchy-shell", "notifications", "toggleDnd"])
    }
  }
}

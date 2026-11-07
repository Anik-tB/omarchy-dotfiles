import QtQuick
import Quickshell.Io
import qs.Ui

// Service is null under anik.bar (see Dnd.qml); fall back to the CLI.
BarIndicator {
  id: root

  readonly property var nightlightService: bar?.shell?.firstPartyServiceFor("omarchy.nightlight")
  property bool cliEnabled: false

  active: nightlightService ? nightlightService.enabled : cliEnabled
  activeText: "󰔎"
  inactiveText: "󰔎"
  activeTooltipText: "Day Light"
  inactiveTooltipText: "Night Light"

  function refresh() {
    if (!root.nightlightService && !statusProc.running && !toggleProc.running) statusProc.running = true
  }

  function toggle() {
    if (root.nightlightService) {
      root.nightlightService.setNightlight(!root.active)
    } else if (!toggleProc.running) {
      root.cliEnabled = !root.cliEnabled
      toggleProc.running = true
    }
  }

  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  // hyprsunset profiles can change the temperature on their own.
  Timer {
    interval: 30000
    repeat: true
    running: !root.nightlightService
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["omarchy-toggle-nightlight", "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.cliEnabled = JSON.parse(text).enabled === true } catch (e) {}
      }
    }
  }

  Process {
    id: toggleProc
    command: ["omarchy-toggle-nightlight"]
    onExited: root.refresh()
  }

  onPressed: function() { root.toggle() }
}

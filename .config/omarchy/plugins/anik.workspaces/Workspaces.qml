import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../anik.bar"

// Workspaces in the theme palette: the active one shows its number in the
// accent with a short accent underline that slides between workspaces; other
// workspaces are dots, bright when occupied and muted when empty. Switching
// cross-fades the number and the dot (with a little scale), dots grow on hover,
// and each cell registers as a bar click target so the hand cursor shows.
BarWidget {
  id: root
  moduleName: "anik.workspaces"

  AnikPalette { id: themePalette }

  readonly property int cell: Style.space(24)
  readonly property var ids: workspaceIds()
  readonly property int activeIndex: Hyprland.focusedWorkspace ? ids.indexOf(Hyprland.focusedWorkspace.id) : -1

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
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

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // The bar's overlay only tracks the pointer on press, so its hover test for
  // the hand cursor falls back to the widget itself: the whole widget is a
  // click target too, and a click it receives goes to the hovered cell.
  // (Real clicks normally land on the cell targets first.)
  function triggerPress(button) {
    var i = Math.floor(widgetHover.point.position.x / root.cell)
    if (i >= 0 && i < root.ids.length) root.focusWorkspace(root.ids[i])
  }
  HoverHandler { id: widgetHover; cursorShape: Qt.PointingHandCursor }

  visible: !vertical
  implicitWidth: ids.length * cell
  implicitHeight: barSize

  // sliding underline beneath the active workspace
  Rectangle {
    visible: root.activeIndex >= 0
    width: Math.round(root.cell * 0.55); height: Style.space(2); radius: height / 2
    // just inside the pill's lower edge (pill height = bar height - 10 units)
    y: Math.round(parent.height / 2 + (root.barSize - Style.space(10)) / 2 - Style.space(5))
    x: root.activeIndex * root.cell + (root.cell - width) / 2
    color: themePalette.accent
    Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
  }

  Row {
    anchors.verticalCenter: parent.verticalCenter

    Repeater {
      model: root.ids

      Item {
        id: ws
        required property int modelData
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        width: root.cell
        height: root.cell

        // The bar's slot overlay picks the cursor and routes left clicks to
        // registered click targets (see anik.resources), so register each cell.
        function triggerPress(button) { root.focusWorkspace(ws.modelData) }
        property var registeredBar: null
        function syncClickRegistration() {
          if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(ws)
          registeredBar = root.bar
          if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(ws)
        }
        Connections { target: root; function onBarChanged() { ws.syncClickRegistration() } }
        Component.onCompleted: syncClickRegistration()
        Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(ws)

        HoverHandler { id: wsHover; cursorShape: Qt.PointingHandCursor }

        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(2) // room for the underline
          opacity: ws.focused ? 1 : 0
          scale: ws.focused ? 1 : 0.6
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
          textFormat: Text.PlainText
          renderType: Text.NativeRendering // like the bar's own labels: no colour fringes
          text: ws.modelData === 10 ? "0" : String(ws.modelData)
          color: themePalette.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Rectangle {
          anchors.centerIn: parent
          opacity: ws.focused ? 0 : 1
          scale: ws.focused ? 0.3 : (wsHover.hovered ? 1.35 : 1)
          visible: opacity > 0
          width: ws.occupied ? Style.space(6) : Style.space(4); height: width; radius: width / 2
          // translucent text for empty workspaces: readable on any wallpaper
          color: ws.occupied || wsHover.hovered ? themePalette.text : themePalette.faint
          Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 200 } }
        }

      }
    }
  }
}

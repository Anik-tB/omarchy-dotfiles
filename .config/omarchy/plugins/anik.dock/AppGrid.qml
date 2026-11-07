import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Every app on one grid. Type to narrow it, arrows to move, Enter to launch.
Item {
  id: root

  property var appLibrary: null
  property var dock: null

  property bool opened: false
  // While an app is dragged out toward the dock, the grid steps aside so the
  // dock shows through, and the app's icon follows the pointer. The grid keeps
  // the pointer for as long as the button is held, and tells the dock where it
  // is.
  property bool dragging: false
  property var dragEntry: null
  property point dragPoint
  // The app waiting on the user to confirm uninstalling it.
  property var uninstallEntry: null
  // The app whose menu is open, and where it opened.
  property var menuEntry: null
  property point menuPoint
  // Where the pointer last really was, in window coordinates. Hover only takes
  // the selection when the pointer itself moves: apps sliding under a still
  // cursor (scrolling) or the cursor hiding/reappearing while typing must not
  // pull the keyboard selection back.
  property point lastPointer: Qt.point(-100000, -100000)

  function hoverAt(cell, x, y) {
    if (root.dragging) return
    var p = cell.mapToItem(panel.contentItem, x, y)
    if (Math.abs(p.x - root.lastPointer.x) < 1 && Math.abs(p.y - root.lastPointer.y) < 1) return
    root.lastPointer = p
    if (root.selectedIndex !== cell.index) root.selectedIndex = cell.index
  }
  property string filterText: ""
  property int selectedIndex: 0
  property var apps: []

  // Look: a proportional UI font, rounded surfaces, thin border.
  readonly property string uiFont: "Adwaita Sans"
  readonly property int cardRadius: Style.space(18)
  readonly property int tileRadius: Style.space(14)
  readonly property int searchRadius: Style.space(12)

  readonly property int iconSize: Math.round(56 * Style.fontScale)
  readonly property int labelHeight: Math.ceil(labelMetrics.height) * 2
  readonly property int cellGutter: Style.spacing.sm
  readonly property int cellPadding: Style.spacing.lg
  readonly property int cellWidth: Math.round(iconSize * 2.2)
  readonly property int cellHeight: cellPadding * 2 + iconSize + Style.spacing.md + labelHeight
  readonly property int maxColumns: 7
  readonly property int visibleRows: 4
  readonly property int borderWidth: 1
  readonly property int contentMargin: Style.spacing.panelPadding + Style.spacing.sm
  readonly property int inset: contentMargin + borderWidth
  readonly property int headerHeight: Math.max(Style.space(42), Style.font.heading + Style.spacing.controlPaddingY * 2 + Style.space(6))
  readonly property int headerSpacing: Style.spacing.lg
  readonly property int screenMargin: Style.space(40)

  // The selection tile slides between apps, but snaps when the list itself
  // changes (opening, typing) so it never sweeps across the grid.
  property bool glide: false
  function snapSelection() {
    root.glide = false
    Qt.callLater(function() { root.glide = true })
  }

  // 0 → 1 as the grid opens: the card fades in and settles from 97% size.
  property real reveal: 0
  NumberAnimation {
    id: revealAnim
    target: root; property: "reveal"
    from: 0; to: 1
    duration: Style.duration(200)
    easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut
  }

  // The card fits whole columns, and the grid sits centered in it so any
  // leftover width splits evenly on both sides.
  readonly property int cardWidth: Math.min(panel.width - screenMargin * 2, maxColumns * cellWidth + inset * 2)
  readonly property int columns: Math.max(1, Math.floor((cardWidth - inset * 2) / cellWidth))
  readonly property int gridWidth: columns * cellWidth
  readonly property int cardHeight: Math.min(panel.height - screenMargin * 2, inset * 2 + headerHeight + headerSpacing + visibleRows * cellHeight)

  function open() {
    root.snapSelection()
    scrollAnim.stop()
    root.selectedIndex = 0
    if (root.appLibrary) root.appLibrary.refreshIcons()
    // The cells from last time are reused when nothing changed, so the grid
    // opens with its icons already drawn.
    if (root.appsStale || root.filterText !== "" || root.apps.length === 0) {
      root.filterText = ""
      root.rebuild()
    } else {
      grid.positionViewAtBeginning()
    }
    root.reveal = 0
    root.opened = true
    revealAnim.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    if (root.dragging && root.dock) root.dock.endExternalDrag()
    root.opened = false
    root.uninstallEntry = null
    root.dragging = false
    root.dragEntry = null
    root.menuEntry = null
  }

  function dragTo(entry, point) {
    if (!root.dragging) {
      root.menuEntry = null
      root.dragEntry = entry
      root.dragging = true
    }
    root.dragPoint = point
    if (root.dock) root.dock.moveExternalDrag(panel.screen, point.x, point.y)
  }

  function dropDrag() {
    var entry = root.dragEntry
    if (entry && root.dock) root.dock.dropExternalDrag(panel.screen, root.dragPoint.x, root.dragPoint.y, String(entry.id || ""))
    root.close()
  }

  function requestUninstall(entry) {
    if (!entry) return
    root.menuEntry = null
    uninstallConfirm.selectedIndex = 1
    root.uninstallEntry = entry
  }

  function cancelUninstall() {
    root.uninstallEntry = null
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmUninstall() {
    var entry = root.uninstallEntry
    root.uninstallEntry = null
    root.close()
    if (entry && root.appLibrary) root.appLibrary.remove(entry.id, root.appLibrary.entryName(entry))
  }

  function openMenu(entry, point) {
    root.menuEntry = entry
    root.menuPoint = point
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function rebuild() {
    root.snapSelection()
    scrollAnim.stop()
    root.appsStale = false
    var rows = root.appLibrary ? root.appLibrary.sortedEntries(root.filterText) : []
    root.apps = rows.map(function(row) { return row.entry })
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.apps.length - 1))
    grid.positionViewAtBeginning()
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
  }

  function select(delta) {
    if (root.apps.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.apps.length - 1, root.selectedIndex + delta))
    root.scrollToIndex(root.selectedIndex)
  }

  // Up/Down stay in the column. On the top or bottom row there is nowhere to
  // go, so nothing moves; Down into a short last row lands on its last app.
  function selectRow(direction) {
    var count = root.apps.length
    if (count === 0) return
    var cols = Math.max(1, root.columns)
    var row = Math.floor(root.selectedIndex / cols)
    var lastRow = Math.floor((count - 1) / cols)
    var targetRow = row + direction
    if (targetRow < 0 || targetRow > lastRow) return
    root.selectedIndex = Math.min(count - 1, root.selectedIndex + direction * cols)
    root.scrollToIndex(root.selectedIndex)
  }

  // Glide the grid instead of jumping: find where positionViewAtIndex would
  // land, put the view back, and animate there.
  function scrollToIndex(index) {
    var from = grid.contentY
    scrollAnim.stop()
    grid.positionViewAtIndex(index, GridView.Contain)
    var to = grid.contentY
    grid.contentY = from
    root.scrollTo(to)
  }

  function scrollTo(y) {
    var top = grid.originY
    var bottom = grid.originY + Math.max(0, grid.contentHeight - grid.height)
    var target = Math.max(top, Math.min(bottom, y))
    if (Math.abs(target - grid.contentY) < 0.5) return
    scrollAnim.stop()
    scrollAnim.from = grid.contentY
    scrollAnim.to = target
    scrollAnim.start()
  }

  function launch(index) {
    var entry = root.apps[index]
    if (!entry || !root.appLibrary) return
    root.close()
    if (root.dock) root.dock.launchEntry(entry)
    else root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
  }

  FontMetrics {
    id: labelMetrics
    font.family: root.uiFont
    font.pixelSize: Style.font.body
  }

  NumberAnimation {
    id: scrollAnim
    target: grid; property: "contentY"
    duration: Style.duration(220)
    easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut
  }

  // Apps installed or removed while the grid is closed are picked up when it
  // next opens.
  property bool appsStale: false

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.opened) root.rebuild()
      else root.appsStale = true
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-dock-apps"
    Rectangle {
      anchors.fill: parent
      color: Commons.Color.menu.scrim
      property real dragAlpha: root.dragging ? 0 : 1
      opacity: dragAlpha * root.reveal

      Behavior on dragAlpha {
        NumberAnimation { duration: Style.duration(root.dragging ? 100 : 150); easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: {
        if (root.menuEntry) root.menuEntry = null
        else root.close()
      }
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      radius: root.cardRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Util.alpha(Commons.Color.menu.border, 0.55), root.borderWidth)
      padding: root.contentMargin
      property real dragAlpha: root.dragging ? 0 : 1
      opacity: dragAlpha * root.reveal
      scale: 0.97 + 0.03 * root.reveal

      Behavior on dragAlpha {
        NumberAnimation { duration: Style.duration(root.dragging ? 100 : 150); easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.menuEntry = null
      }

      ConfirmDialog {
        id: uninstallConfirm

        anchors.fill: parent
        opened: !!root.uninstallEntry
        z: 10
        message: Commons.I18n.t("common.uninstallConfirm").arg(root.uninstallEntry && root.appLibrary ? root.appLibrary.entryName(root.uninstallEntry) : "")
        confirmText: Commons.I18n.t("common.uninstall")
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Color.menu.scrim
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: root.uiFont
        cornerRadius: root.cardRadius
        onCanceled: root.cancelUninstall()
        onConfirmed: root.confirmUninstall()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.uninstallEntry) {
            if (uninstallConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Delete) {
            root.requestUninstall(root.apps[root.selectedIndex])
          } else if (event.key === Qt.Key_Escape) {
            if (root.menuEntry) root.menuEntry = null
            else if (root.filterText) root.setFilter("")
            else root.close()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (Util.readingKey(event) === Qt.Key_Left) {
            root.select(-1)
          } else if (Util.readingKey(event) === Qt.Key_Right) {
            root.select(1)
          } else if (event.key === Qt.Key_Up) {
            root.selectRow(-1)
          } else if (event.key === Qt.Key_Down) {
            root.selectRow(1)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.launch(root.selectedIndex)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        width: root.gridWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        spacing: root.headerSpacing

        Rectangle {
          id: searchBox
          x: root.cellGutter
          width: parent.width - root.cellGutter * 2
          height: root.headerHeight
          radius: root.searchRadius
          color: Util.alpha(Commons.Color.menu.text, root.filterText ? 0.08 : 0.05)
          border.width: 1
          border.color: Util.alpha(Commons.Color.menu.text, root.filterText ? 0.14 : 0.07)

          Behavior on color { ColorAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }
          Behavior on border.color { ColorAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }

          // Magnifier: a ring and a short handle.
          Item {
            id: glass
            readonly property int size: Math.round(searchBox.height * 0.40)
            width: size; height: size
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.controlPaddingX + Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.filterText ? 0.85 : 0.5

            Rectangle {
              width: Math.round(glass.size * 0.78); height: width
              radius: width / 2
              color: "transparent"
              border.width: Math.max(1.5, Style.space(2))
              border.color: Commons.Color.menu.text
            }
            Rectangle {
              width: Math.round(glass.size * 0.38)
              height: Math.max(1.5, Style.space(2))
              radius: height / 2
              color: Commons.Color.menu.text
              x: glass.size * 0.60; y: glass.size * 0.78
              transformOrigin: Item.Left
              rotation: 45
            }
          }

          Text {
            id: searchText
            anchors.left: glass.right
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.controlPaddingX
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.filterText || Commons.I18n.t("dock.searchApps")
            color: Commons.Color.menu.text
            opacity: root.filterText ? 1 : 0.45
            font.family: root.uiFont
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          // Caret after the typed text, blinking gently.
          Rectangle {
            visible: root.opened && root.filterText !== ""
            x: searchText.x + Math.min(searchText.contentWidth, searchText.width) + Style.space(2)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1.5, Style.space(2))
            height: Math.round(Style.font.heading * 1.15)
            radius: width / 2
            color: Commons.Color.accent
            SequentialAnimation on opacity {
              running: root.opened && root.filterText !== ""
              loops: Animation.Infinite
              NumberAnimation { to: 1; duration: 0 }
              PauseAnimation { duration: 530 }
              NumberAnimation { to: 0; duration: 180; easing.type: Easing.InOutSine }
              PauseAnimation { duration: 350 }
              NumberAnimation { to: 1; duration: 180; easing.type: Easing.InOutSine }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - parent.spacing

          GridView {
            id: grid
            anchors.fill: parent
            model: root.apps
            clip: true
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2500
            maximumFlickVelocity: 4000
            pixelAligned: true

            // One soft tile that slides to whichever app is selected. It lives
            // in the scrolling content, so it moves with the apps.
            Rectangle {
              id: selectionTile
              parent: grid.contentItem
              z: 0
              visible: root.apps.length > 0
              readonly property int col: root.selectedIndex % Math.max(1, root.columns)
              readonly property int row: Math.floor(root.selectedIndex / Math.max(1, root.columns))
              x: col * root.cellWidth + root.cellGutter
              y: row * root.cellHeight + root.cellGutter
              width: root.cellWidth - root.cellGutter * 2
              height: root.cellHeight - root.cellGutter * 2
              radius: root.tileRadius
              color: Util.alpha(Commons.Color.menu.text, 0.08)
              border.width: 1
              border.color: Util.alpha(Commons.Color.menu.text, 0.10)

              Behavior on x { enabled: root.glide; NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
              Behavior on y { enabled: root.glide; NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
            }

            delegate: Item {
              id: cell
              z: 1

              required property int index
              required property var modelData
              readonly property bool selected: index === root.selectedIndex
              property point pressPoint
              // A press that wanders is a drag in the making, not a click.
              property bool moved: false

              width: root.cellWidth
              height: root.cellHeight

              Image {
                id: icon
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.cellPadding
                width: root.iconSize
                height: root.iconSize
                sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                source: root.appLibrary ? root.appLibrary.iconSource(cell.modelData.icon) : ""
                fillMode: Image.PreserveAspectFit
                // Loaded with the cell, from Qt's image cache after the first
                // open, so icons do not pop in after the grid has appeared.
                asynchronous: false
                smooth: true
                mipmap: true
                scale: cell.selected ? 1.06 : 1.0
                Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }
              }

              Text {
                id: label
                anchors.top: icon.bottom
                anchors.topMargin: Style.spacing.md
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - (root.cellGutter + Style.spacing.md) * 2
                textFormat: Text.PlainText
                text: root.appLibrary ? root.appLibrary.entryName(cell.modelData) : ""
                color: Commons.Color.menu.text
                opacity: cell.selected ? 1.0 : 0.78
                Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
                font.family: root.uiFont
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignTop
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                // The grid would otherwise take a dragging press for a scroll.
                preventStealing: true
                onContainsMouseChanged: if (containsMouse) root.hoverAt(cell, mouseX, mouseY)
                onPressed: function(event) {
                  cell.moved = false
                  cell.pressPoint = Qt.point(event.x, event.y)
                }
                onPositionChanged: function(event) {
                  if (!(pressedButtons & Qt.LeftButton)) { root.hoverAt(cell, event.x, event.y); return }
                  if (!cell.moved && Math.hypot(event.x - cell.pressPoint.x, event.y - cell.pressPoint.y) > Style.space(4)) cell.moved = true
                  if (cell.moved) root.dragTo(cell.modelData, cell.mapToItem(panel.contentItem, event.x, event.y))
                }
                onReleased: function(event) {
                  if (root.dragging && event.button === Qt.LeftButton) root.dropDrag()
                }
                onCanceled: if (root.dragging) root.close()
                onClicked: function(event) {
                  if (cell.moved) return
                  if (event.button === Qt.RightButton) {
                    root.openMenu(cell.modelData, cell.mapToItem(panel.contentItem, event.x, event.y))
                    return
                  }
                  root.menuEntry = null
                  root.launch(cell.index)
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.apps.length === 0
            textFormat: Text.PlainText
            text: Commons.I18n.t("dock.noAppsMatch").arg(root.filterText)
            color: Commons.Color.menu.text
            opacity: 0.7
            font.family: root.uiFont
            font.pixelSize: Style.font.title
          }
        }
      }
    }
    // The dragged app's icon, under the pointer.
    Image {
      visible: root.dragging && !!root.dragEntry
      x: root.dragPoint.x - width / 2
      y: root.dragPoint.y - height / 2
      width: root.iconSize
      height: root.iconSize
      sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
      source: root.dragEntry && root.appLibrary ? root.appLibrary.iconSource(root.dragEntry.icon) : ""
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }

    // Right-click on an app: open it, or keep it in the dock or take it out.
    BorderSurface {
      id: menu

      readonly property var entry: root.menuEntry
      readonly property bool pinned: !!entry && !!root.dock && root.dock.isPinned(String(entry.id || ""))

      visible: !!entry && !root.dragging
      width: Math.max(Style.space(160), menuColumn.implicitWidth) + padding * 2
      height: menuColumn.implicitHeight + padding * 2
      // Opens along the reading direction from the pointer.
      x: LayoutMirroring.enabled
        ? Math.max(Style.gapsOut, root.menuPoint.x - width)
        : Math.min(root.menuPoint.x, panel.width - width - Style.gapsOut)
      y: Math.min(root.menuPoint.y, panel.height - height - Style.gapsOut)
      radius: root.searchRadius
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
      padding: Style.spacing.sm

      Column {
        id: menuColumn
        x: menu.contentLeftInset
        y: menu.contentTopInset
        width: menu.width - menu.contentLeftInset - menu.contentRightInset

        MenuRow {
          text: Commons.I18n.t("dock.open")
          onTriggered: {
            var entry = menu.entry
            root.close()
            if (entry && root.dock) root.dock.launchEntry(entry)
            else if (entry && root.appLibrary) root.appLibrary.launch(entry.id, root.appLibrary.entryName(entry))
          }
        }

        MenuRow {
          visible: !!root.dock
          text: menu.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
          onTriggered: {
            if (root.dock && menu.entry) root.dock.setPinned(String(menu.entry.id || ""), !menu.pinned)
            root.menuEntry = null
          }
        }

        MenuRow {
          text: Commons.I18n.t("dock.uninstall")
          onTriggered: root.requestUninstall(menu.entry)
        }
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.space(8)
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.triggered()
    }
  }
}

// Notification card, Apple style. Pure presentational — no service,
// Notification, or ListModel references. The popup container drives lifetime;
// the history panel drives static rendering. Both use the same component.
//
// Layout (macOS Sonoma-like): frosted grey glass with window-matched corners, a
// faint top sheen, a rounded-square app icon on the left, a bold title with a
// relative time ("now", "5m ago") on the right, the body underneath in
// secondary grey, and a small round close button that appears top-left on hover.

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NotificationLogic.js" as NotificationLogic
import "../anik.bar"

BorderSurface {
  id: root

  // Same palette as the bar.
  readonly property AnikPalette themePalette: AnikPalette {}

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // Nerd Font glyph rendered in the icon tile when no real icon is set.
  // Used by omarchy-notification-send so user-action toasts (`Silenced
  // notifications` etc.) show their bell/lock/etc. glyph without leaking
  // into the summary text.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  property int cornerRadius: 0
  // Flat list row (Notification Centre): no glass, border or rounding; the
  // panel draws hairline dividers between rows instead.
  property bool flat: false

  // System monospace font injected by the container (used for glyphs only).
  property string fontFamily: ""
  // Text face: the same clean sans as the bar.
  readonly property string textFamily: "Adwaita Sans"

  readonly property bool hovered: hoverTracker.hovered

  signal closeRequested()
  signal cardClicked()
  // A sender button (not "default", which is the card click itself).
  signal actionRequested(string identifier)
  // Text to put on the clipboard: a detected code, or the whole card on middle click.
  signal copyRequested(string text)

  // JSON [{id, text}] from NotificationLogic.actionsOf; empty for history rows.
  property string actions: ""
  readonly property var actionList: NotificationLogic.parseActions(actions)
  readonly property string code: NotificationLogic.findCode(summary, body)
  readonly property string copyText: {
    var title = summary.length > 0 ? summary : app
    var text = NotificationLogic.plainText(body)
    return text.length > 0 ? title + "\n" + text : title
  }
  readonly property bool hasButtons: actionList.length > 0 || code.length > 0
  // Prefer per-notification media/avatar data, then fall back to the app icon.
  // The `check` flag avoids Qt's missing-texture placeholder for unknown names.
  readonly property string smallIconSource: image.length > 0 ? image : iconSource(appIcon)
  readonly property bool hasGlyph: glyph.length > 0
  readonly property bool hasSmallIcon: smallIconSource.length > 0 && iconImage.status !== Image.Error
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property bool singleLineToast: sanitizedBody.length === 0
  // A summary that already begins with its own glyph needs no tile.
  readonly property bool showTile: !(singleLineToast && !hasGlyph && !hasSmallIcon && summaryStartsWithGlyph)
  readonly property string sanitizedBody: sanitizeBody(body)
  // Blank lines between paragraphs collapse to one break, so the 4 visible
  // lines carry text rather than gaps.
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)
    .replace(/(\s*<br\/>\s*){2,}/g, "<br/>")
    .replace(/^(\s*<br\/>)+|(<br\/>\s*)+$/g, "")

  readonly property color titleColor: themePalette.textBright
  readonly property color bodyColor: Qt.rgba(themePalette.text.r, themePalette.text.g, themePalette.text.b, 0.72)
  readonly property color metaColor: Qt.rgba(themePalette.text.r, themePalette.text.g, themePalette.text.b, 0.45)
  readonly property bool critical: urgency === 2
  // Same border as the calendar and other bar panels (theme [popups] border);
  // critical stays urgent red at that width.
  readonly property var popupBorderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  readonly property var cardBorderSpec: critical
    ? Border.flat(Commons.Color.urgent, Border.uniformWidth(popupBorderSpec))
    : popupBorderSpec

  // Relative time, refreshed every 30s while the card exists.
  property double now: Date.now()
  Timer { interval: 30000; repeat: true; running: root.timestamp > 0; onTriggered: root.now = Date.now() }
  readonly property string timeText: relativeTime(timestamp, now)

  function relativeTime(ts, current) {
    if (!(ts > 0)) return ""
    var s = Math.max(0, Math.floor((current - ts) / 1000))
    if (s < 60) return "now"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m ago"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h ago"
    return Qt.formatDateTime(new Date(ts), "ddd HH:mm")
  }

  function sanitizeBody(s) {
    return NotificationLogic.sanitizeBody(s, app, appIcon)
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  implicitWidth: Style.space(356)
  implicitHeight: content.implicitHeight + Style.space(28) + borderTop + borderBottom
  // Follows Hyprland's decoration:rounding like windows and panels (0 = square).
  radius: flat ? 0 : Style.cornerRadius
  // Apple's dark notification material: a lifted grey glass, not black.
  color: flat
    ? Qt.rgba(1, 1, 1, hovered ? 0.04 : 0)
    : Qt.rgba(themePalette.surface.r, themePalette.surface.g, themePalette.surface.b, 0.78)
  borderSpec: flat ? Border.none() : cardBorderSpec
  Behavior on color { ColorAnimation { duration: 120 } }
  clip: true

  HoverHandler { id: hoverTracker }

  // Faint sheen across the top, like light on glass.
  Rectangle {
    visible: !root.flat
    anchors.fill: parent
    anchors.margins: root.borderTop
    radius: Math.max(0, root.radius - root.borderTop)
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.hovered ? 0.075 : 0.05) }
      GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.0) }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        root.closeRequested()
      } else if (mouse.button === Qt.MiddleButton) {
        root.copyRequested(root.copyText)
      } else {
        root.cardClicked()
      }
    }
  }

  RowLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: root.borderLeft + Style.space(14)
    anchors.rightMargin: root.borderRight + Style.space(16)
    anchors.topMargin: root.borderTop + Style.space(14)
    spacing: Style.space(12)

    // App icon: rounded-square tile.
    Item {
      id: tile
      visible: root.showTile
      Layout.preferredWidth: Style.space(38)
      Layout.preferredHeight: Style.space(38)
      Layout.alignment: root.singleLineToast ? Qt.AlignVCenter : Qt.AlignTop
      readonly property real tileRadius: Style.space(9)

      // Tinted tile behind glyphs or when there is no icon at all.
      Rectangle {
        anchors.fill: parent
        radius: tile.tileRadius
        visible: !root.hasSmallIcon
        color: Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.16)
        border.width: 1
        border.color: Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.22)

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.hasGlyph ? root.glyph : "󰂚"
          color: themePalette.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }
      }

      Image {
        id: iconImage
        anchors.fill: parent
        source: root.smallIconSource
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        // Photos/avatars fill the tile; app icons keep their own shape.
        fillMode: root.image.length > 0 ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        visible: false
      }

      Rectangle {
        id: tileMask
        anchors.fill: parent
        radius: tile.tileRadius
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: iconImage
        source: iconImage
        visible: root.hasSmallIcon && iconImage.status === Image.Ready
        maskEnabled: true
        maskSource: tileMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: root.singleLineToast ? Qt.AlignVCenter : Qt.AlignTop
      spacing: Style.space(2)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          // The spec defines the summary as a single line of plain text, so
          // AutoText could only ever promote a hostile string to rich text.
          // The body below is StyledText on purpose — see Service.qml's
          // bodyMarkupSupported — and is stripped in NotificationLogic.
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: root.summary.length > 0 ? root.summary : root.app
          font.family: root.textFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          color: root.titleColor
          elide: Text.ElideRight
          maximumLineCount: 1
        }

        Text {
          textFormat: Text.PlainText
          visible: root.timeText.length > 0
          text: root.timeText
          font.family: root.textFamily
          font.pixelSize: Style.font.bodySmall
          color: root.metaColor
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.sanitizedBody.length > 0
        text: root.styledBody
        textFormat: Text.StyledText
        font.family: root.textFamily
        font.pixelSize: Style.font.subtitle
        color: root.bodyColor
        lineHeight: 1.08
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 4
      }

      // Sender buttons and "Copy code". Inside the content, which is declared
      // after the card MouseArea, so they take their own clicks.
      Flow {
        Layout.fillWidth: true
        Layout.topMargin: Style.space(6)
        visible: root.hasButtons
        spacing: Style.space(6)

        CardButton {
          visible: root.code.length > 0
          label: "󰆏  Copy " + root.code
          accent: true
          onClicked: root.copyRequested(root.code)
        }

        Repeater {
          model: root.actionList
          CardButton {
            required property var modelData
            label: String(modelData.text)
            onClicked: root.actionRequested(String(modelData.id))
          }
        }
      }
    }
  }

  // Close button: a small round chip at the top-left corner, shown on hover
  // (as on macOS). Declared after the card MouseArea so it takes the click.
  Rectangle {
    id: closeButton
    x: root.borderLeft + Style.space(5)
    y: root.borderTop + Style.space(5)
    width: Style.space(20)
    height: width
    radius: width / 2
    color: closeArea.containsMouse
      ? Qt.rgba(themePalette.text.r, themePalette.text.g, themePalette.text.b, 0.28)
      : Qt.rgba(themePalette.deep.r, themePalette.deep.g, themePalette.deep.b, 0.92)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.16)
    opacity: root.hovered ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }

    // Two drawn strokes rather than a "✕" glyph, whose font metrics sit it
    // off-centre in the button.
    Repeater {
      model: [45, -45]
      Rectangle {
        required property int modelData
        anchors.centerIn: parent
        width: Style.space(8)
        height: Math.max(1, Style.space(1.5))
        radius: height / 2
        rotation: modelData
        antialiasing: true
        color: themePalette.textBright
      }
    }

    MouseArea {
      id: closeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.closeRequested()
    }
  }

  component CardButton: Rectangle {
    id: cardButton
    property string label: ""
    property bool accent: false
    signal clicked()

    implicitWidth: buttonText.implicitWidth + Style.space(20)
    implicitHeight: buttonText.implicitHeight + Style.space(10)
    radius: height / 2
    color: cardButton.accent
      ? Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, buttonArea.containsMouse ? 0.30 : 0.18)
      : Qt.rgba(1, 1, 1, buttonArea.containsMouse ? 0.16 : 0.08)
    border.width: 1
    border.color: cardButton.accent
      ? Qt.rgba(themePalette.accent.r, themePalette.accent.g, themePalette.accent.b, 0.35)
      : Qt.rgba(1, 1, 1, 0.10)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      id: buttonText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: cardButton.label
      font.family: root.textFamily
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.Medium
      color: cardButton.accent ? themePalette.textBright : root.titleColor
    }

    MouseArea {
      id: buttonArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cardButton.clicked()
    }
  }
}

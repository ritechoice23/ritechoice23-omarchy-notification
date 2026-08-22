import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property var entry
  property bool selected: false
  property bool unread: false
  property bool showBody: true
  property bool showPreview: true
  property color foreground: Color.notifications.text
  property string fontFamily: Style.font.family
  property var cleanText
  property var sourceName
  property var iconSource
  property var previewSource
  property var timeAgo
  property var initial

  signal activateRequested()
  signal dismissRequested()

  readonly property bool urgent: Number(entry.urgency || 0) === 2
  readonly property string appLabel: sourceName(entry)
  readonly property string appImage: iconSource(entry)
  readonly property string previewImage: previewSource(entry)
  readonly property color secondaryText: Qt.darker(foreground, 1.35)
  readonly property color tertiaryText: Qt.darker(foreground, 1.8)
  readonly property int cardPadding: Style.space(10)

  width: ListView.view ? ListView.view.width : implicitWidth
  implicitHeight: contentColumn.implicitHeight + cardPadding * 2
  radius: Style.cornerRadius
  clip: true

  color: selected
    ? Style.selectedFillFor(foreground, Color.accent, Color.urgent)
    : pointer.hovered
      ? Style.hoverFillFor(foreground, Color.accent, Color.urgent)
      : Color.notifications.background

  borderSpec: urgent
    ? Border.controlSpec("selected", foreground, Color.urgent, Color.urgent)
    : selected || pointer.hovered
      ? Border.controlSpec("hover-cursor", foreground, Color.accent, Color.urgent)
      : Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(1)))

  Behavior on color { ColorAnimation { duration: 140 } }
  HoverHandler { id: pointer }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activateRequested()
  }

  ColumnLayout {
    id: contentColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: root.cardPadding
    spacing: Style.space(6)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(8)

      Rectangle {
        Layout.preferredWidth: Style.space(30)
        Layout.preferredHeight: Style.space(30)
        Layout.alignment: Qt.AlignVCenter
        radius: Style.cornerRadius > 0 ? Math.min(Style.space(9), Style.cornerRadius) : 0
        color: Style.normalFillFor(root.foreground, Color.accent)
        clip: true

        Image {
          id: appIcon
          anchors.fill: parent
          anchors.margins: Style.space(4)
          source: root.appImage
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }

        Text {
          anchors.centerIn: parent
          visible: root.appImage.length === 0 || appIcon.status === Image.Error
          text: root.initial(root.entry)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: root.unread
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: root.appLabel
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.timeAgo(root.entry.timestamp)
          color: root.tertiaryText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Rectangle {
        Layout.preferredWidth: Style.space(7)
        Layout.preferredHeight: width
        Layout.alignment: Qt.AlignVCenter
        visible: root.unread
        radius: width / 2
        color: Color.accent
      }

      Rectangle {
        id: closeButton
        Layout.preferredWidth: Style.space(24)
        Layout.preferredHeight: Style.space(24)
        Layout.alignment: Qt.AlignTop
        visible: pointer.hovered || root.selected
        radius: Style.cornerRadius > 0 ? width / 2 : 0
        color: closeMouse.containsMouse
          ? Style.hoverFillFor(root.foreground, Color.accent)
          : Style.normalFillFor(root.foreground, Color.accent)
        border.width: 1
        border.color: Style.normalBorderFor(root.foreground, Color.accent)

        Text {
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -1
          text: "×"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: closeMouse
          anchors.fill: parent
          z: 3
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            mouse.accepted = true
            root.dismissRequested()
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: text.length > 0
      text: root.cleanText(root.entry.summary)
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Text {
      Layout.fillWidth: true
      visible: root.showBody && text.length > 0
      text: root.cleanText(root.entry.body)
      textFormat: Text.PlainText
      color: root.secondaryText
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Image {
      Layout.fillWidth: true
      Layout.preferredHeight: visible ? Math.min(implicitHeight, Style.space(120)) : 0
      visible: root.showPreview && root.previewImage.length > 0 && status !== Image.Error
      source: root.previewImage
      sourceSize.width: width * Screen.devicePixelRatio
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      clip: true
    }

    RowLayout {
      Layout.fillWidth: true
      visible: root.pending || root.urgent
      spacing: Style.space(6)

      Rectangle {
        visible: root.urgent
        Layout.preferredWidth: urgentLabel.implicitWidth + Style.space(12)
        Layout.preferredHeight: Style.space(20)
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.14)

        Text {
          id: urgentLabel
          anchors.centerIn: parent
          text: "Critical"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Item { Layout.fillWidth: true }

    }
  }
}

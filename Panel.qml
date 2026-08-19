import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "ritechoice23.omarchy.notification"
  ipcTarget: "ritechoice23.omarchy.notification"
  manageIpc: false

  // -- Settings (configurable via `omarchy bar set`) --

  readonly property int historyLimit: setting("historyLimit", 200)
  readonly property bool showBadge: setting("showBadge", true)

  // -- State --

  property var notifications: []
  property int unreadCount: 0
  property int currentIndex: -1

  // -- Centralized style properties --

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir:
    home + "/.config/omarchy/plugins/ritechoice23.omarchy.notification"

  readonly property color foreground:
    bar ? bar.foreground : Color.foreground
  readonly property color background:
    bar ? bar.background : Color.background
  readonly property string fontFamily:
    bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical:
    bar ? bar.vertical : false
  readonly property color dimForeground:
    Qt.darker(foreground, 1.4)
  readonly property color faintForeground:
    Qt.darker(foreground, 2.0)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // -- Text sanitization --

  function cleanText(value) {
    var text = String(value || "")

    text = text.replace(/<br\s*\/?>/gi, "\n")
    text = text.replace(/<a[^>]*>(.*?)<\/a>/gi, "$1")
    text = text.replace(/<[^>]*>/g, " ")

    text = text.replace(/&amp;/g, "&")
    text = text.replace(/&lt;/g, "<")
    text = text.replace(/&gt;/g, ">")
    text = text.replace(/&quot;/g, "\"")
    text = text.replace(/&#39;/g, "'")
    text = text.replace(/&nbsp;/g, " ")

    text = text.replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")

    var lines = text.split(/\r?\n/)
    var kept = []

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/\s+/g, " ").trim()

      if (!line) continue

      // Browser notifications often put the site origin on the first line.
      // The panel already labels the source, so remove this visual noise.
      if (
        line === "web.whatsapp.com" ||
        line === "mail.google.com" ||
        line === "calendar.google.com" ||
        line === "youtube.com"
      ) continue

      kept.push(line)
    }

    return kept.join("\n").trim()
  }

  function sourceName(entry) {
    if (!entry) return "Notification"

    var body = String(entry.body || "").toLowerCase()

    if (body.indexOf("web.whatsapp.com") >= 0) return "WhatsApp"
    if (body.indexOf("mail.google.com") >= 0) return "Gmail"
    if (body.indexOf("calendar.google.com") >= 0) return "Google Calendar"
    if (body.indexOf("youtube.com") >= 0) return "YouTube"

    var name = String(entry.app || "").trim()
    return name.length > 0 ? name : "Notification"
  }

  function initial(entry) {
    var name = sourceName(entry)
    return name.length > 0 ? name.charAt(0).toUpperCase() : "N"
  }

  function imageSource(entry) {
    if (!entry) return ""

    var candidates = [
      String(entry.image || ""),
      String(entry.appIcon || "")
    ]

    for (var i = 0; i < candidates.length; i++) {
      var source = candidates[i]

      if (
        source.indexOf("file://") === 0 ||
        source.indexOf("/") === 0 ||
        source.indexOf("image://") === 0
      ) {
        return source
      }
    }

    return ""
  }

  function timeAgo(timestamp) {
    var value = Number(timestamp || 0)

    if (!isFinite(value) || value <= 0) return ""

    var seconds = Math.max(
      0,
      Math.floor((Date.now() - value) / 1000)
    )

    if (seconds < 60) return "now"

    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"

    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"

    var days = Math.floor(hours / 24)
    if (days < 7) return days + "d ago"

    return Qt.formatDate(new Date(value), "dd MMM")
  }

  // -- Actions --

  function refresh() {
    if (!dataProc.running) dataProc.running = true
  }

  function markSeen() {
    if (!seenProc.running) seenProc.running = true
  }

  function clearAll() {
    if (!clearProc.running) clearProc.running = true
  }

  function dismissOne(fileName) {
    var value = String(fileName || "")
    if (!value || dismissProc.running) return

    dismissProc.command = [
      "/bin/bash",
      root.pluginDir + "/scripts/dismiss-one",
      value
    ]
    dismissProc.running = true
  }

  function focusApp(appName) {
    var app = String(appName || "").trim()
    if (!app || focusProc.running) return

    focusProc.command = [
      "hyprctl", "dispatch", "focuswindow",
      "class:" + app.toLowerCase()
    ]
    focusProc.running = true
  }

  function dismissCurrent() {
    if (currentIndex < 0 || currentIndex >= notifications.length) return
    var entry = notifications[currentIndex]
    var file = String(entry._ritechoiceFile || "")
    if (file) dismissOne(file)
  }

  function activateCurrent() {
    if (currentIndex < 0 || currentIndex >= notifications.length) return
    var entry = notifications[currentIndex]
    var app = String(entry.app || "").trim()
    if (app) focusApp(app)
    root.close()
  }

  // -- Lifecycle --

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      markSeen()
      currentIndex = -1
    }
  }

  // Badge polling — lightweight, only when panel is closed.
  Timer {
    interval: 15000
    running: !root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // -- IPC Handler --

  IpcHandler {
    target: "ritechoice23.omarchy.notification"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function clear(): void { root.clearAll() }
    function unread(): int { return root.unreadCount }
  }

  // -- Processes --

  Process {
    id: dataProc

    command: [
      "/bin/bash",
      root.pluginDir + "/scripts/notification-data",
      String(root.historyLimit)
    ]

    stdout: StdioCollector {
      waitForEnd: true

      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.notifications = parsed.notifications || []
          root.unreadCount = Number(parsed.unread || 0)
        } catch (error) {
          console.warn(
            "RiteChoice23 Notification: failed to parse data:",
            error
          )
        }
      }
    }
  }

  Process {
    id: seenProc

    command: [
      "/bin/bash",
      root.pluginDir + "/scripts/mark-seen"
    ]

    onExited: root.unreadCount = 0
  }

  Process {
    id: clearProc

    command: [
      "/bin/bash",
      root.pluginDir + "/scripts/clear-all"
    ]

    onExited: {
      root.notifications = []
      root.unreadCount = 0
      root.refresh()
    }
  }

  Process {
    id: dismissProc
    onExited: root.refresh()
  }

  Process {
    id: focusProc
    onExited: root.close()
  }

  // -- Bar icon button --

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar

    text: "\uf0f3"
    active: root.opened

    tooltipText:
      root.unreadCount > 0
        ? "RiteChoice23 Notification (" + root.unreadCount + " new)"
        : "RiteChoice23 Notification"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }

    Rectangle {
      visible: root.showBadge && root.unreadCount > 0

      width: root.unreadCount > 9 ? Style.space(17) : Style.space(13)
      height: Style.space(13)
      radius: height / 2

      color: root.bar ? root.bar.urgent : Color.urgent

      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(1)
      anchors.topMargin: Style.space(1)

      Text {
        anchors.centerIn: parent

        text: root.unreadCount > 9 ? "9+" : String(root.unreadCount)
        color: root.background

        font.family: root.fontFamily
        font.pixelSize: Style.space(7)
        font.bold: true
      }
    }
  }

  // -- Panel --

  KeyboardPanel {
    id: notificationPanel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    contentWidth:
      notificationPanel.fittedContentWidth(Style.space(430))

    contentHeight:
      notificationPanel.fittedContentHeight(
        panelColumn.implicitHeight,
        Style.space(590)
      )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()

      onActivateRequested: root.activateCurrent()

      onDeleteRequested: root.dismissCurrent()

      onTabRequested: function(direction) {
        root.switchPanel(direction)
      }

      onMoveRequested: function(dx, dy) {
        if (root.notifications.length === 0) return

        var next = root.currentIndex + dy
        if (next < 0) next = 0
        if (next >= root.notifications.length)
          next = root.notifications.length - 1

        root.currentIndex = next
      }

      Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: panelColumn
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            foreground: root.foreground
            fontFamily: root.fontFamily
            title: "Notifications"

            meta:
              root.notifications.length === 1
                ? "1 RECENT NOTIFICATION"
                : root.notifications.length + " RECENT NOTIFICATIONS"

            iconComponent: Component {
              Text {
                text: "󰂚"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              Button {
                visible: root.notifications.length > 0
                text: "Clear"
                iconText: "󰎟"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.clearAll()
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // -- Empty state --

          Item {
            visible: root.notifications.length === 0

            width: parent.width
            implicitHeight: Style.space(240)

            Column {
              anchors.centerIn: parent
              spacing: Style.space(10)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: "\uf0f3"
                color: root.faintForeground

                font.family: root.fontFamily
                font.pixelSize: Style.space(28)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: "No notifications"
                color: root.dimForeground

                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter

                text: "New notifications will appear here."
                color: root.faintForeground

                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // -- Notification cards --

          Column {
            visible: root.notifications.length > 0
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.notifications

              BorderSurface {
                id: card

                required property var modelData
                required property int index

                readonly property var notification: modelData

                readonly property string iconSource:
                  root.imageSource(notification)

                readonly property string archiveFile:
                  String(notification._ritechoiceFile || "")

                readonly property bool isSelected:
                  root.currentIndex === index

                readonly property bool isUrgent:
                  Number(notification.urgency || 0) === 2

                width: parent.width

                implicitHeight:
                  notificationRow.implicitHeight + Style.space(20)

                radius: Style.cornerRadius

                color: isSelected
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : cardHover.hovered
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g,
                              root.foreground.b, 0.04)

                borderSpec: isUrgent
                  ? Border.controlSpec(
                      "selected", root.foreground, Color.urgent)
                  : Border.controlSpec(
                      "normal", root.foreground, Color.accent)

                HoverHandler { id: cardHover }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor

                  onClicked: {
                    var app = card.notification.app || ""
                    if (app) root.focusApp(app)
                    root.close()
                  }
                }

                Row {
                  id: notificationRow

                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  // App icon / initial avatar
                  Rectangle {
                    width: Style.space(40)
                    height: width
                    radius: Style.space(9)

                    color: Qt.rgba(
                      root.foreground.r, root.foreground.g,
                      root.foreground.b, 0.09)

                    Image {
                      anchors.fill: parent
                      anchors.margins: Style.space(4)

                      source: card.iconSource
                      visible: card.iconSource.length > 0

                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      visible: card.iconSource.length === 0
                      anchors.centerIn: parent

                      text: root.initial(card.notification)
                      color: root.foreground

                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                    }
                  }

                  // Content column
                  Column {
                    width:
                      notificationRow.width -
                      Style.space(40) -
                      notificationRow.spacing

                    spacing: Style.space(3)

                    // Source + time + dismiss
                    Row {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        width:
                          parent.width -
                          dismissButton.width -
                          parent.spacing

                        text: {
                          var time = root.timeAgo(
                            card.notification.timestamp)
                          var source = root.sourceName(
                            card.notification)

                          return time.length > 0
                            ? source + "  ·  " + time
                            : source
                        }

                        color: root.dimForeground

                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Rectangle {
                        id: dismissButton

                        visible:
                          cardHover.hovered &&
                          card.archiveFile.length > 0

                        width: Style.space(22)
                        height: width
                        radius: width / 2

                        color: dismissArea.containsMouse
                          ? Style.hoverFillFor(
                              root.foreground, Color.accent)
                          : Qt.rgba(
                              root.foreground.r, root.foreground.g,
                              root.foreground.b, 0.07)

                        Text {
                          anchors.centerIn: parent
                          text: "×"
                          color: root.foreground

                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                        }

                        MouseArea {
                          id: dismissArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.dismissOne(
                            card.archiveFile)
                        }
                      }
                    }

                    // Summary
                    Text {
                      width: parent.width
                      visible: text.length > 0

                      text: root.cleanText(
                        card.notification.summary)

                      color: root.foreground

                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true

                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }

                    // Body
                    Text {
                      width: parent.width
                      visible: text.length > 0

                      text: root.cleanText(
                        card.notification.body)

                      color: root.dimForeground

                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body

                      wrapMode: Text.WordWrap
                      maximumLineCount: 4
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }

          // -- Footer --

          PanelSeparator {
            visible: root.notifications.length > 0
            foreground: root.foreground
          }

          Text {
            visible: root.notifications.length > 0

            width: parent.width
            horizontalAlignment: Text.AlignHCenter

            text: "RiteChoice23 Notification"
            color: root.faintForeground

            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}

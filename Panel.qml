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
  property var groupedNotifications: []
  property var expandedGroups: ({})
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

  // -- Data Grouping Engine --

  function computeGroups() {
    var raw = root.notifications || []
    if (raw.length === 0) {
      root.groupedNotifications = []
      return
    }

    var map = new Map()

    for (var i = 0; i < raw.length; i++) {
      var item = raw[i]
      var appName = root.sourceName(item)

      if (!map.has(appName)) {
        map.set(appName, {
          app: appName,
          items: [],
          latestTimestamp: Number(item.timestamp || 0),
          hasUrgent: false
        })
      }

      var g = map.get(appName)
      g.items.push(item)

      var ts = Number(item.timestamp || 0)
      if (ts > g.latestTimestamp) g.latestTimestamp = ts
      if (Number(item.urgency || 0) === 2) g.hasUrgent = true
    }

    var list = Array.from(map.values()).sort(function(a, b) {
      return b.latestTimestamp - a.latestTimestamp
    })

    for (var j = 0; j < list.length; j++) {
      var grp = list[j]
      grp.isExpanded = Boolean(root.expandedGroups[grp.app])
    }

    root.groupedNotifications = list
  }

  function toggleGroup(appName) {
    var cur = Boolean(root.expandedGroups[appName])
    var next = Object.assign({}, root.expandedGroups)
    next[appName] = !cur
    root.expandedGroups = next
    root.computeGroups()
  }

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
      // Remove this visual noise for cleaner display.
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

  function dismissGroup(groupItems) {
    if (!groupItems || groupItems.length === 0) return
    for (var i = 0; i < groupItems.length; i++) {
      var file = String(groupItems[i]._ritechoiceFile || "")
      if (file) dismissOne(file)
    }
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
    if (currentIndex < 0 || currentIndex >= groupedNotifications.length) return
    var grp = groupedNotifications[currentIndex]
    if (grp && grp.items && grp.items.length > 0) {
      dismissGroup(grp.items)
    }
  }

  function activateCurrent() {
    if (currentIndex < 0 || currentIndex >= groupedNotifications.length) return
    var grp = groupedNotifications[currentIndex]
    if (grp && grp.items && grp.items.length > 0) {
      var entry = grp.items[0]
      var app = String(entry.app || "").trim()
      if (app) focusApp(app)
      root.close()
    }
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
          root.computeGroups()
        } catch (error) {
          console.warn(
            "Notification: failed to parse data:",
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
      root.groupedNotifications = []
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
        ? "Notifications (" + root.unreadCount + " new)"
        : "Notifications"

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
        if (root.groupedNotifications.length === 0) return

        if (dx > 0 && root.currentIndex >= 0 && root.currentIndex < root.groupedNotifications.length) {
          var g = root.groupedNotifications[root.currentIndex]
          if (g && g.items && g.items.length > 1 && !g.isExpanded) {
            root.toggleGroup(g.app)
            return
          }
        } else if (dx < 0 && root.currentIndex >= 0 && root.currentIndex < root.groupedNotifications.length) {
          var gr = root.groupedNotifications[root.currentIndex]
          if (gr && gr.isExpanded) {
            root.toggleGroup(gr.app)
            return
          }
        }

        var next = root.currentIndex + dy
        if (next < 0) next = 0
        if (next >= root.groupedNotifications.length)
          next = root.groupedNotifications.length - 1

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

            meta: {
              var n = root.notifications.length
              var g = root.groupedNotifications.length
              if (n === 0) return "ALL CAUGHT UP"
              if (n === 1) return "1 NOTIFICATION"
              return g > 1
                ? n + " NOTIFICATIONS  ·  " + g + " APPS"
                : n + " NOTIFICATIONS"
            }

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

          // -- Grouped Notification Cards --

          Column {
            visible: root.notifications.length > 0
            width: parent.width
            spacing: Style.space(10)

            Repeater {
              model: root.groupedNotifications

              BorderSurface {
                id: groupCard

                required property var modelData
                required property int index

                readonly property var group: modelData
                readonly property var topItem: (group.items && group.items.length > 0) ? group.items[0] : null
                readonly property int itemCount: group.items ? group.items.length : 0
                readonly property bool isExpanded: group.isExpanded || false
                readonly property bool isSelected: root.currentIndex === index
                readonly property bool hasUrgent: Boolean(group.hasUrgent)

                width: parent.width
                radius: Style.space(14)

                // Translucent surface styling with smooth transition
                color: isSelected
                  ? Style.selectedFillFor(root.foreground, Color.accent)
                  : groupHover.hovered
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                borderSpec: hasUrgent
                  ? Border.controlSpec("selected", root.foreground, Color.urgent)
                  : Border.controlSpec(isSelected ? "selected" : "normal", root.foreground, Color.accent)

                Behavior on color { ColorAnimation { duration: 150 } }

                HoverHandler { id: groupHover }

                implicitHeight: cardContentCol.implicitHeight + Style.space(20)

                Behavior on implicitHeight {
                  NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }

                Column {
                  id: cardContentCol

                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(10)
                  spacing: Style.space(8)

                  // ==========================================
                  // 1. APP HEADER & STACK CONTROLS
                  // ==========================================
                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    // App Icon / Squircle Avatar
                    Rectangle {
                      width: Style.space(26)
                      height: width
                      radius: Style.space(7)
                      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)
                      anchors.verticalCenter: parent.verticalCenter

                      Image {
                        anchors.fill: parent
                        anchors.margins: Style.space(3)
                        source: root.imageSource(groupCard.topItem)
                        visible: source.toString().length > 0
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                      }

                      Text {
                        visible: !root.imageSource(groupCard.topItem)
                        anchors.centerIn: parent
                        text: root.initial(groupCard.topItem)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.space(11)
                        font.bold: true
                      }
                    }

                    // App Name & Timestamp Meta
                    Column {
                      width: parent.width - Style.space(26) - (stackBadge.visible ? stackBadge.width + Style.space(8) : 0) - (groupDismissBtn.visible ? groupDismissBtn.width + Style.space(8) : 0) - Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        text: (groupCard.group.app || "Notification").toUpperCase() + "  ·  " + root.timeAgo(groupCard.group.latestTimestamp)
                        color: root.dimForeground
                        font.family: root.fontFamily
                        font.pixelSize: Style.space(10)
                        font.bold: true
                        font.letterSpacing: 0.6
                        elide: Text.ElideRight
                      }
                    }

                    // Stack Pill (e.g. "2 more ⌄" / "Show less ⌃")
                    Rectangle {
                      id: stackBadge
                      visible: groupCard.itemCount > 1
                      anchors.verticalCenter: parent.verticalCenter

                      width: stackLabel.implicitWidth + Style.space(14)
                      height: Style.space(20)
                      radius: height / 2

                      color: stackMouse.containsMouse
                        ? Style.hoverFillFor(root.foreground, Color.accent)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, groupCard.isExpanded ? 0.12 : 0.07)

                      border.width: 1
                      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)

                      Text {
                        id: stackLabel
                        anchors.centerIn: parent
                        text: groupCard.isExpanded
                          ? "Less ⌃"
                          : (groupCard.itemCount - 1) + " more ⌄"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.space(9)
                        font.bold: true
                      }

                      MouseArea {
                        id: stackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleGroup(groupCard.group.app)
                      }
                    }

                    // Group Dismiss Button (Circle Pill on Hover)
                    Rectangle {
                      id: groupDismissBtn
                      visible: groupHover.hovered
                      anchors.verticalCenter: parent.verticalCenter

                      width: Style.space(20)
                      height: width
                      radius: width / 2

                      color: groupDismissMouse.containsMouse
                        ? Style.hoverFillFor(root.foreground, Color.accent)
                        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                      border.width: 1
                      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

                      Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        anchors.verticalCenterOffset: -1
                      }

                      MouseArea {
                        id: groupDismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissGroup(groupCard.group.items)
                      }
                    }
                  }

                  // ==========================================
                  // 2. PRIMARY NOTIFICATION (Top Item)
                  // ==========================================
                  Item {
                    id: primaryItemContainer
                    width: parent.width
                    implicitHeight: primaryCol.implicitHeight

                    Column {
                      id: primaryCol
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        width: parent.width
                        visible: text.length > 0
                        text: root.cleanText(groupCard.topItem ? groupCard.topItem.summary : "")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        visible: text.length > 0
                        text: root.cleanText(groupCard.topItem ? groupCard.topItem.body : "")
                        color: root.dimForeground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                      }

                      // Action Pills (Open App / Dismiss)
                      Row {
                        visible: groupHover.hovered || groupCard.isSelected
                        spacing: Style.space(6)
                        topPadding: Style.space(4)

                        Rectangle {
                          height: Style.space(22)
                          width: openPillLabel.implicitWidth + Style.space(16)
                          radius: height / 2

                          color: openPillMouse.containsMouse
                            ? Style.hoverFillFor(root.foreground, Color.accent)
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.09)

                          border.width: 1
                          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

                          Text {
                            id: openPillLabel
                            anchors.centerIn: parent
                            text: "Open App"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.space(9)
                            font.bold: true
                          }

                          MouseArea {
                            id: openPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              var app = groupCard.topItem ? groupCard.topItem.app : ""
                              if (app) root.focusApp(app)
                              root.close()
                            }
                          }
                        }

                        Rectangle {
                          height: Style.space(22)
                          width: dismissPillLabel.implicitWidth + Style.space(16)
                          radius: height / 2

                          color: dismissPillMouse.containsMouse
                            ? Style.hoverFillFor(root.foreground, Color.accent)
                            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

                          border.width: 1
                          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                          Text {
                            id: dismissPillLabel
                            anchors.centerIn: parent
                            text: "Dismiss"
                            color: root.dimForeground
                            font.family: root.fontFamily
                            font.pixelSize: Style.space(9)
                          }

                          MouseArea {
                            id: dismissPillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              var file = String(groupCard.topItem ? groupCard.topItem._ritechoiceFile : "")
                              if (file) root.dismissOne(file)
                            }
                          }
                        }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      z: -1
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        var app = groupCard.topItem ? groupCard.topItem.app : ""
                        if (app) root.focusApp(app)
                        root.close()
                      }
                    }
                  }

                  // ==========================================
                  // 3. COLLAPSIBLE ACCORDION BODY (Remaining Items)
                  // ==========================================
                  Item {
                    id: accordionContainer
                    width: parent.width
                    clip: true
                    visible: groupCard.itemCount > 1

                    implicitHeight: groupCard.isExpanded ? expandedCol.implicitHeight : 0
                    opacity: groupCard.isExpanded ? 1.0 : 0.0

                    Behavior on implicitHeight {
                      NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                      NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                    }

                    Column {
                      id: expandedCol
                      width: parent.width
                      spacing: Style.space(8)
                      topPadding: Style.space(4)

                      Repeater {
                        model: (groupCard.group.items && groupCard.group.items.length > 1)
                          ? groupCard.group.items.slice(1)
                          : []

                        Column {
                          id: subItemCol
                          required property var modelData
                          required property int index

                          readonly property var subNotif: modelData
                          readonly property string subFile: String(subNotif._ritechoiceFile || "")

                          width: parent.width
                          spacing: Style.space(4)

                          // Subtle divider between stacked notifications
                          Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(6)

                            Text {
                              width: parent.width - subDismissBtn.width - parent.spacing
                              text: root.timeAgo(subItemCol.subNotif.timestamp)
                              color: root.faintForeground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              elide: Text.ElideRight
                            }

                            Rectangle {
                              id: subDismissBtn
                              visible: subItemHover.hovered && subItemCol.subFile.length > 0
                              width: Style.space(18)
                              height: width
                              radius: width / 2

                              color: subDismissMouse.containsMouse
                                ? Style.hoverFillFor(root.foreground, Color.accent)
                                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                              Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.space(10)
                              }

                              MouseArea {
                                id: subDismissMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dismissOne(subItemCol.subFile)
                              }
                            }
                          }

                          Text {
                            width: parent.width
                            visible: text.length > 0
                            text: root.cleanText(subItemCol.subNotif.summary)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                          }

                          Text {
                            width: parent.width
                            visible: text.length > 0
                            text: root.cleanText(subItemCol.subNotif.body)
                            color: root.dimForeground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                          }

                          HoverHandler { id: subItemHover }

                          MouseArea {
                            anchors.fill: parent
                            z: -1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              var app = subItemCol.subNotif.app || ""
                              if (app) root.focusApp(app)
                              root.close()
                            }
                          }
                        }
                      }
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

            text: "Omarchy Notification"
            color: root.faintForeground

            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}

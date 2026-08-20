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

  readonly property int historyLimit: setting("historyLimit", 200)
  readonly property bool showBadge: setting("showBadge", true)

  property var notifications: []
  property int unreadCount: 0
  property int currentIndex: -1
  property int timeRevision: 0
  property bool refreshPending: false
  property var dismissQueue: []
  property var dismissActive: null
  property var pendingDismissals: ({})
  property var activationEntry: null
  property string activationOutput: ""
  property string statusMessage: ""
  property int pendingSeenTimestamp: 0
  property int seenInFlightTimestamp: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: {
    var configured = Quickshell.env("XDG_STATE_HOME")
    return configured ? configured : home + "/.local/state"
  }
  readonly property string omarchyNotificationDir: stateHome + "/omarchy/notifications"
  readonly property string dataScript: localFile("scripts/notification-data")
  readonly property string seenScript: localFile("scripts/mark-seen")
  readonly property string clearScript: localFile("scripts/clear-all")
  readonly property string dismissScript: localFile("scripts/dismiss-one")
  readonly property string activateScript: localFile("scripts/activate-notification")

  readonly property color foreground: Color.notifications.text
  readonly property color background: bar ? bar.background : Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(foreground, 1.35)
  readonly property color faintForeground: Qt.darker(foreground, 1.85)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function localFile(relativePath) {
    var value = String(Qt.resolvedUrl(relativePath))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function validFileName(value) {
    return /^[^/]+\.json$/.test(String(value || ""))
  }

  function cleanText(value) {
    var text = String(value || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<a[^>]*>(.*?)<\/a>/gi, "$1")
      .replace(/<[^>]*>/g, " ")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"")
      .replace(/&#39;/g, "'")
      .replace(/&nbsp;/g, " ")
      .replace(/[\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")

    var lines = text.split(/\r?\n/)
    var kept = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/\s+/g, " ").trim()
      if (!line) continue
      if (kept.length === 0 && /^(?:https?:\/\/)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)+\/?$/i.test(line)) continue
      kept.push(line)
    }
    return kept.join("\n").trim()
  }

  function webOrigin(entry) {
    var body = String(entry && entry.body || "").toLowerCase()
    var match = body.match(/https?:\/\/([^/\"'< >]+)/i)
    return match ? match[1] : ""
  }

  function sourceName(entry) {
    if (!entry) return "Notification"
    var origin = webOrigin(entry)
    if (origin.indexOf("web.whatsapp.com") >= 0) return "WhatsApp"
    if (origin.indexOf("mail.google.com") >= 0) return "Gmail"
    if (origin.indexOf("calendar.google.com") >= 0) return "Google Calendar"
    if (origin.indexOf("youtube.com") >= 0) return "YouTube"
    var name = String(entry.app || "").trim()
    return name || "Notification"
  }

  function initial(entry) {
    var name = sourceName(entry)
    return name ? name.charAt(0).toUpperCase() : "N"
  }

  function usableImage(value) {
    var source = String(value || "")
    if (!source) return ""
    if (source.indexOf("file://") === 0 || source.indexOf("image://") === 0 || source.charAt(0) === "/") return source
    return Quickshell.iconPath(source, true)
  }

  function iconSource(entry) {
    if (!entry) return ""
    return usableImage(entry.appIcon) || usableImage(entry.image)
  }

  function previewSource(entry) {
    if (!entry) return ""
    var image = usableImage(entry.image)
    return image && image !== usableImage(entry.appIcon) ? image : ""
  }

  function numericTimestamp(value) {
    var timestamp = Number(value || 0)
    return isFinite(timestamp) && timestamp > 0 ? timestamp : 0
  }

  function timeAgo(timestamp) {
    var revision = root.timeRevision
    var value = numericTimestamp(timestamp)
    if (!value) return "Unknown time"
    var seconds = Math.max(0, Math.floor((Date.now() - value) / 1000))
    if (seconds < 60) return "Now"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h ago"
    var days = Math.floor(hours / 24)
    if (days < 7) return days + "d ago"
    return Qt.formatDate(new Date(value), "d MMM")
  }

  function dayKey(timestamp) {
    var value = numericTimestamp(timestamp)
    if (!value) return "unknown"
    return Qt.formatDate(new Date(value), "yyyy-MM-dd")
  }

  function dayLabel(timestamp) {
    var value = numericTimestamp(timestamp)
    if (!value) return "Earlier"
    var date = new Date(value)
    var today = new Date()
    var yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
    if (Qt.formatDate(date, "yyyy-MM-dd") === Qt.formatDate(today, "yyyy-MM-dd")) return "Today"
    if (Qt.formatDate(date, "yyyy-MM-dd") === Qt.formatDate(yesterday, "yyyy-MM-dd")) return "Yesterday"
    return Qt.formatDate(date, "dddd, d MMMM")
  }

  function refresh() {
    if (dataProc.running) {
      refreshPending = true
      return
    }
    dataProc.running = true
  }

  function queueSeen(timestamp) {
    var value = numericTimestamp(timestamp)
    if (!value) return
    pendingSeenTimestamp = Math.max(pendingSeenTimestamp, value)
    unreadCount = 0
    runSeen()
  }

  function runSeen() {
    if (seenProc.running || pendingSeenTimestamp <= 0) return
    seenInFlightTimestamp = pendingSeenTimestamp
    pendingSeenTimestamp = 0
    seenProc.command = ["/bin/bash", seenScript, String(seenInFlightTimestamp)]
    seenProc.running = true
  }

  function clearAll() {
    if (clearProc.running) return
    notifications = []
    unreadCount = 0
    currentIndex = -1
    statusMessage = "Clearing notifications…"
    clearProc.running = true
  }

  function removeLocal(fileName) {
    var next = []
    for (var i = 0; i < notifications.length; i++) {
      if (String(notifications[i]._ritechoiceFile || "") !== fileName) next.push(notifications[i])
    }
    notifications = next
    if (currentIndex >= next.length) currentIndex = next.length - 1
  }

  function dismissOne(fileName) {
    var file = String(fileName || "")
    if (!validFileName(file) || pendingDismissals[file]) return
    var pending = Object.assign({}, pendingDismissals)
    pending[file] = true
    pendingDismissals = pending
    dismissQueue = dismissQueue.concat([file])
    removeLocal(file)
    runNextDismissal()
  }

  function runNextDismissal() {
    if (dismissProc.running || dismissQueue.length === 0) return
    dismissActive = dismissQueue[0]
    dismissQueue = dismissQueue.slice(1)
    dismissProc.command = ["/bin/bash", dismissScript, dismissActive]
    dismissProc.running = true
  }

  function dismissCurrent() {
    if (currentIndex < 0 || currentIndex >= notifications.length) return
    dismissOne(notifications[currentIndex]._ritechoiceFile)
  }

  function activateOne(entry) {
    if (!entry || activateProc.running) return
    var file = String(entry._ritechoiceFile || "")
    if (!validFileName(file)) return
    activationEntry = entry
    activationOutput = ""
    statusMessage = "Opening " + sourceName(entry) + "…"
    activateProc.command = ["/bin/bash", activateScript, file]
    activateProc.running = true
  }

  function activateCurrent() {
    if (currentIndex < 0 || currentIndex >= notifications.length) return
    activateOne(notifications[currentIndex])
  }

  function setCurrentIndex(index) {
    if (notifications.length === 0) {
      currentIndex = -1
      return
    }
    currentIndex = Math.max(0, Math.min(notifications.length - 1, index))
    Qt.callLater(function() {
      if (currentIndex >= 0) notificationList.positionViewAtIndex(currentIndex, ListView.Contain)
    })
  }

  Component.onCompleted: {
    refresh()
    notificationWatcher.running = true
  }

  onOpenedChanged: {
    if (opened) {
      statusMessage = ""
      currentIndex = -1
      refresh()
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.timeRevision++
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshDebounce
    interval: 120
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: watcherRestart
    interval: 1500
    repeat: false
    onTriggered: if (!notificationWatcher.running) notificationWatcher.running = true
  }

  Timer {
    id: statusTimer
    interval: 2600
    repeat: false
    onTriggered: root.statusMessage = ""
  }

  IpcHandler {
    target: "ritechoice23.omarchy.notification"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function clear(): void { root.clearAll() }
    function unread(): int { return root.unreadCount }
  }

  Process {
    id: notificationWatcher
    command: ["inotifywait", "-m", "-r", "-q", "-e", "close_write,create,delete,move", "--format", "%e", root.omarchyNotificationDir]
    stdout: SplitParser { onRead: refreshDebounce.restart() }
    onExited: watcherRestart.restart()
  }

  Process {
    id: dataProc
    command: ["/bin/bash", root.dataScript, String(root.historyLimit)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var selectedFile = root.currentIndex >= 0 && root.currentIndex < root.notifications.length
            ? String(root.notifications[root.currentIndex]._ritechoiceFile || "") : ""
          var parsed = JSON.parse(text)
          var incoming = Array.isArray(parsed.notifications) ? parsed.notifications : []
          var visible = []
          for (var itemIndex = 0; itemIndex < incoming.length; itemIndex++) {
            var incomingFile = String(incoming[itemIndex]._ritechoiceFile || "")
            if (!clearProc.running && !root.pendingDismissals[incomingFile]) visible.push(incoming[itemIndex])
          }
          root.notifications = visible
          root.unreadCount = root.opened ? 0 : Math.max(0, Number(parsed.unread || 0))
          if (selectedFile) {
            root.currentIndex = -1
            for (var selectedIndex = 0; selectedIndex < root.notifications.length; selectedIndex++) {
              if (String(root.notifications[selectedIndex]._ritechoiceFile || "") === selectedFile) {
                root.currentIndex = selectedIndex
                break
              }
            }
          }
          if (root.opened) root.queueSeen(parsed.maxTimestamp)
        } catch (error) {
          console.warn("Notification: failed to parse archive:", error)
          root.statusMessage = "Unable to load notifications"
          statusTimer.restart()
        }
      }
    }
    onExited: {
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: seenProc
    onExited: root.runSeen()
  }

  Process {
    id: clearProc
    command: ["/bin/bash", root.clearScript]
    onExited: function(exitCode) {
      root.statusMessage = exitCode === 0 ? "All notifications cleared" : "Unable to clear notifications"
      statusTimer.restart()
      root.refresh()
    }
  }

  Process {
    id: dismissProc
    onExited: function(exitCode) {
      var file = String(root.dismissActive || "")
      var pending = Object.assign({}, root.pendingDismissals)
      delete pending[file]
      root.pendingDismissals = pending
      root.dismissActive = null
      if (exitCode !== 0) {
        root.statusMessage = "Unable to dismiss notification"
        statusTimer.restart()
      }
      root.refresh()
      root.runNextDismissal()
    }
  }

  Process {
    id: activateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.activationOutput = text
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        var result = null
        try { result = JSON.parse(root.activationOutput || "{}") } catch (error) {}
        if (exitCode === 0 && result && result.ok && root.activationEntry) {
          var file = String(root.activationEntry._ritechoiceFile || "")
          root.activationEntry = null
          root.statusMessage = ""
          root.dismissOne(file)
          root.close()
        } else {
          root.activationEntry = null
          root.statusMessage = "App window unavailable"
          statusTimer.restart()
        }
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0f3"
    active: root.opened
    tooltipText: root.unreadCount > 0 ? "Notifications (" + root.unreadCount + " new)" : "Notifications"
    onPressed: function(mouseButton) { if (mouseButton === Qt.LeftButton) root.toggle() }

    Rectangle {
      visible: root.showBadge && root.unreadCount > 0
      width: root.unreadCount > 9 ? Style.space(17) : Style.space(13)
      height: Style.space(13)
      radius: Style.cornerRadius > 0 ? height / 2 : 0
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

  KeyboardPanel {
    id: notificationPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: notificationPanel.fittedContentWidth(Style.space(430))
    contentHeight: notificationPanel.fittedContentHeight(panelColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.activateCurrent()
      onDeleteRequested: root.dismissCurrent()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.setCurrentIndex((root.currentIndex < 0 ? (dy > 0 ? -1 : root.notifications.length) : root.currentIndex) + dy)
      }

      Column {
        id: panelColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(10)

        PanelHero {
          foreground: root.foreground
          fontFamily: root.fontFamily
          title: "Notifications"
          meta: {
            var count = root.notifications.length
            if (count === 0) return "ALL CAUGHT UP"
            return count === 1 ? "1 NOTIFICATION" : count + " NOTIFICATIONS"
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

        Item {
          width: parent.width
          implicitHeight: root.notifications.length === 0
            ? Style.space(240)
            : Math.min(notificationList.contentHeight, Style.space(470))

          Column {
            visible: root.notifications.length === 0
            anchors.centerIn: parent
            spacing: Style.space(9)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "\uf0f3"
              color: root.faintForeground
              font.family: root.fontFamily
              font.pixelSize: Style.space(30)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No notifications"
              color: root.dimForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "You’re all caught up."
              color: root.faintForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          ListView {
            id: notificationList
            visible: root.notifications.length > 0
            anchors.fill: parent
            model: root.notifications
            currentIndex: root.currentIndex
            spacing: Style.space(8)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            add: Transition { NumberAnimation { properties: "opacity,y"; duration: 170; easing.type: Easing.OutCubic } }
            remove: Transition { NumberAnimation { properties: "opacity"; to: 0; duration: 120 } }
            displaced: Transition { NumberAnimation { properties: "y"; duration: 160; easing.type: Easing.OutCubic } }

            delegate: Item {
              id: delegateRoot
              required property var modelData
              required property int index
              readonly property bool startsSection: index === 0 || root.dayKey(modelData.timestamp) !== root.dayKey(root.notifications[index - 1].timestamp)
              width: ListView.view.width
              height: delegateColumn.implicitHeight

              Column {
                id: delegateColumn
                width: parent.width
                spacing: Style.space(6)

                Item {
                  width: parent.width
                  height: delegateRoot.startsSection ? Style.space(24) : 0
                  visible: delegateRoot.startsSection

                  Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Style.space(3)
                    text: root.dayLabel(delegateRoot.modelData.timestamp)
                    color: root.dimForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                NotificationCard {
                  width: parent.width
                  entry: delegateRoot.modelData
                  selected: root.currentIndex === delegateRoot.index
                  pending: root.activationEntry && String(root.activationEntry._ritechoiceFile || "") === String(entry._ritechoiceFile || "")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  cleanText: root.cleanText
                  sourceName: root.sourceName
                  iconSource: root.iconSource
                  previewSource: root.previewSource
                  timeAgo: root.timeAgo
                  initial: root.initial
                  onActivateRequested: root.activateOne(entry)
                  onDismissRequested: root.dismissOne(entry._ritechoiceFile)
                }
              }
            }
          }
        }

        PanelSeparator { visible: root.notifications.length > 0 || root.statusMessage.length > 0; foreground: root.foreground }

        Text {
          visible: root.statusMessage.length > 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: root.statusMessage
          color: root.statusMessage.indexOf("unavailable") >= 0 || root.statusMessage.indexOf("Unable") >= 0 ? Color.urgent : root.faintForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}

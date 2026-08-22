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

  readonly property int historyLimit: setting("historyLimit", 1000)
  readonly property int keepDays: setting("keepDays", 30)
  readonly property string configuredBadge: setting("badge", "")
  readonly property bool legacyShowBadge: setting("showBadge", true)
  readonly property string badge: ["Dot", "Count", "None"].indexOf(configuredBadge) >= 0
    ? configuredBadge : (legacyShowBadge ? "Count" : "None")
  readonly property string clickAction: setting("clickAction", "Auto")
  readonly property bool showBody: setting("showBody", true)
  readonly property bool showPreview: setting("showPreview", true)
  readonly property int panelWidth: setting("panelWidth", 440)

  property var notifications: []
  property int totalCount: 0
  property int unreadCount: 0
  property int lastSeen: 0
  property int readMark: 0
  property int currentIndex: -1
  property int timeRevision: 0
  property bool loaded: false
  property bool refreshPending: false
  property bool searching: false
  property string filter: ""
  property var dismissQueue: []
  property var dismissActive: null
  property var pendingDismissals: ({})
  property var activationEntry: null
  property string activationOutput: ""
  property string statusMessage: ""
  property int pendingSeenTimestamp: 0
  property bool clearArmed: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: {
    var configured = Quickshell.env("XDG_STATE_HOME")
    return configured ? configured : home + "/.local/state"
  }
  readonly property string storeScript: localFile("bin/notification-center")
  readonly property string activateScript: localFile("scripts/activate-notification")
  readonly property color foreground: Color.notifications.text
  readonly property color background: bar ? bar.background : Color.background
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dimForeground: Qt.darker(foreground, 1.35)
  readonly property color faintForeground: Qt.darker(foreground, 1.8)
  readonly property var storeEnvironment: ({
    "RITECHOICE_KEEP_DAYS": String(root.keepDays),
    "RITECHOICE_HISTORY_LIMIT": String(root.historyLimit),
    "RITECHOICE_KEEP_PREVIEWS": root.showPreview ? "1" : "0"
  })

  readonly property var notificationService: {
    var host = bar && bar.shell ? bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return null
    var id = "omarchy.notifications"
    if (host.pluginRegistry && typeof host.pluginRegistry.resolveEnabledId === "function")
      id = host.pluginRegistry.resolveEnabledId(id)
    return host.serviceFor(id)
  }
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  readonly property var visibleNotifications: {
    var needle = root.filter.toLowerCase().trim()
    if (!needle) return root.notifications
    var matches = []
    for (var i = 0; i < root.notifications.length; i++) {
      var entry = root.notifications[i]
      var haystack = (String(entry.app || "") + "\n" + String(entry.summary || "") + "\n" + String(entry.body || "")).toLowerCase()
      if (haystack.indexOf(needle) >= 0) matches.push(entry)
    }
    return matches
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function localFile(relativePath) {
    var value = String(Qt.resolvedUrl(relativePath))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function validFileName(value) { return /^[A-Za-z0-9][A-Za-z0-9._-]*\.json$/.test(String(value || "")) }

  function cleanText(value) {
    var text = String(value || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/<a[^>]*>(.*?)<\/a>/gi, "$1")
      .replace(/<img[^>]*>/gi, "")
      .replace(/<[^>]*>/g, " ")
      .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
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

  function livePopupIndex(entry) {
    var model = notificationService ? notificationService.popupModel : null
    if (!entry || !model || typeof model.get !== "function") return -1
    var originalId = Number(entry.originalId || entry.id || 0)
    var timestamp = numericTimestamp(entry.timestamp)
    for (var i = 0; i < model.count; i++) {
      var row = model.get(i)
      if (row && Number(row.originalId || row.id || 0) === originalId
          && numericTimestamp(row.timestamp) === timestamp) return i
    }
    return -1
  }

  function livePopup(entry) {
    var index = livePopupIndex(entry)
    return index >= 0 ? notificationService.popupModel.get(index) : null
  }

  function invokeLiveDefault(entry) {
    var index = livePopupIndex(entry)
    if (index < 0 || !notificationService) return false
    var row = notificationService.popupModel.get(index)
    if (typeof notificationService.isRestoredRow === "function" && notificationService.isRestoredRow(row)) return false
    var refs = notificationService.liveRefs
    var ref = refs ? refs[row.originalId] : null
    try {
      if (!ref || !ref.actions) return false
      for (var i = 0; i < ref.actions.length; i++) {
        var action = ref.actions[i]
        if (action && action.identifier === "default") {
          notificationService.invokePopupDefault(index)
          return true
        }
      }
    } catch (error) {
      console.warn("RiteChoice23 Notification: live default action unavailable:", error)
    }
    return false
  }

  function iconSource(entry) {
    if (!entry) return ""
    var live = livePopup(entry)
    return usableImage(live && live.image) || usableImage(entry.image) || usableImage(entry.appIcon)
  }
  function previewSource(entry) { return entry && root.showPreview ? (usableImage(entry.preview) || usableImage(entry.image)) : "" }

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
    return Qt.formatDateTime(new Date(value), "HH:mm")
  }

  function dayKey(timestamp) {
    var value = numericTimestamp(timestamp)
    return value ? Qt.formatDate(new Date(value), "yyyy-MM-dd") : "unknown"
  }

  function dayLabel(timestamp) {
    var value = numericTimestamp(timestamp)
    if (!value) return "Earlier"
    var date = new Date(value)
    var today = new Date()
    var midnight = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
    if (value >= midnight) return "Today"
    if (value >= midnight - 86400000) return "Yesterday"
    if (value >= midnight - 6 * 86400000) return Qt.formatDate(date, "dddd")
    if (date.getFullYear() === today.getFullYear()) return Qt.formatDate(date, "d MMMM")
    return Qt.formatDate(date, "d MMMM yyyy")
  }

  function refresh() {
    if (dataProc.running) {
      refreshPending = true
      return
    }
    dataProc.command = [root.storeScript, "list", String(root.historyLimit)]
    dataProc.running = true
  }

  function queueSeen(timestamp) {
    var value = numericTimestamp(timestamp)
    if (!value) return
    pendingSeenTimestamp = Math.max(pendingSeenTimestamp, value)
    lastSeen = Math.max(lastSeen, value)
    unreadCount = 0
    runSeen()
  }

  function runSeen() {
    if (seenProc.running || pendingSeenTimestamp <= 0) return
    var watermark = pendingSeenTimestamp
    pendingSeenTimestamp = 0
    seenProc.command = [root.storeScript, "seen", String(watermark)]
    seenProc.running = true
  }

  function startSearch() {
    searching = true
    Qt.callLater(function() { if (root.searching) searchField.forceActiveFocus() })
  }

  function endSearch() {
    searching = false
    filter = ""
    searchField.text = ""
    currentIndex = -1
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function toggleDnd() {
    if (notificationService) notificationService.setDoNotDisturb(!notificationService.doNotDisturb)
  }

  function armClear() {
    if (clearArmed) {
      clearArmed = false
      clearDisarm.stop()
      clearAll()
    } else {
      clearArmed = true
      clearDisarm.restart()
    }
  }

  function clearAll() {
    if (clearProc.running) return
    notifications = []
    totalCount = 0
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
    totalCount = Math.max(0, totalCount - 1)
    currentIndex = visibleNotifications.length === 0 ? -1 : Math.min(currentIndex, visibleNotifications.length - 1)
  }

  function dismissOne(fileName) {
    var file = String(fileName || "")
    if (!validFileName(file) || pendingDismissals[file]) return
    markPending(file)
    removeLocal(file)
    queueRemoval(file)
  }

  function markPending(file) {
    var pending = Object.assign({}, pendingDismissals)
    pending[file] = true
    pendingDismissals = pending
  }

  function queueRemoval(file) {
    dismissQueue = dismissQueue.concat([file])
    runNextDismissal()
  }

  function runNextDismissal() {
    if (dismissProc.running || dismissQueue.length === 0) return
    dismissActive = dismissQueue[0]
    dismissQueue = dismissQueue.slice(1)
    dismissProc.command = [root.storeScript, "remove", dismissActive]
    dismissProc.running = true
  }

  function dismissCurrent() {
    if (currentIndex >= 0 && currentIndex < visibleNotifications.length)
      dismissOne(visibleNotifications[currentIndex]._ritechoiceFile)
  }

  function activateOne(entry) {
    if (!entry || activationEntry || clickAction === "Nothing") return
    var file = String(entry._ritechoiceFile || "")
    if (!validFileName(file)) return
    activationEntry = entry
    activationOutput = ""
    root.markPending(file)
    root.removeLocal(file)
    root.close()
    if (root.invokeLiveDefault(entry)) {
      root.queueRemoval(file)
      activationEntry = null
      return
    }
    activateProc.command = ["/bin/bash", activateScript, file, clickAction, "Dismiss"]
    activateProc.running = true
  }

  function activateCurrent() {
    if (currentIndex >= 0 && currentIndex < visibleNotifications.length)
      activateOne(visibleNotifications[currentIndex])
  }

  function setCurrentIndex(index) {
    if (visibleNotifications.length === 0) {
      currentIndex = -1
      return
    }
    currentIndex = Math.max(0, Math.min(visibleNotifications.length - 1, index))
    Qt.callLater(function() {
      if (currentIndex >= 0) notificationList.positionViewAtIndex(currentIndex, ListView.Contain)
    })
  }

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (!opened) {
      clearArmed = false
      clearDisarm.stop()
      if (searching) endSearch()
      return
    }
    statusMessage = ""
    currentIndex = -1
    readMark = lastSeen
    refresh()
  }

  onFilterChanged: currentIndex = visibleNotifications.length > 0 ? 0 : -1
  onShowPreviewChanged: refresh()

  Timer { interval: 30000; running: root.opened; repeat: true; triggeredOnStart: true; onTriggered: root.timeRevision++ }
  Timer { interval: 10000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  Timer { id: refreshDebounce; interval: 120; onTriggered: root.refresh() }
  Timer { id: watchRestart; interval: 30000; onTriggered: if (!watchProc.running) watchProc.running = true }
  Timer { id: statusTimer; interval: 2800; onTriggered: root.statusMessage = "" }
  Timer { id: clearDisarm; interval: 4000; onTriggered: root.clearArmed = false }

  Shortcut { sequence: "Ctrl+F"; enabled: root.opened; onActivated: root.startSearch() }

  IpcHandler {
    target: "ritechoice23.omarchy.notification"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function clear(): void { root.clearAll() }
    function unread(): int { return root.unreadCount }
  }

  Process {
    id: watchProc
    command: [root.storeScript, "watch"]
    environment: root.storeEnvironment
    running: true
    stdout: SplitParser { onRead: refreshDebounce.restart() }
    onExited: watchRestart.restart()
  }

  Process {
    id: dataProc
    environment: root.storeEnvironment
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var selectedFile = root.currentIndex >= 0 && root.currentIndex < root.visibleNotifications.length
            ? String(root.visibleNotifications[root.currentIndex]._ritechoiceFile || "") : ""
          var parsed = JSON.parse(text)
          if (!parsed.ok) throw new Error(parsed.error || "store-failed")
          var incoming = Array.isArray(parsed.notifications) ? parsed.notifications : []
          var visible = []
          for (var i = 0; i < incoming.length; i++) {
            var incomingFile = String(incoming[i]._ritechoiceFile || "")
            if (!clearProc.running && !root.pendingDismissals[incomingFile]) visible.push(incoming[i])
          }
          var wasLoaded = root.loaded
          root.notifications = visible
          root.totalCount = Math.max(0, Number(parsed.total || visible.length))
          root.lastSeen = Math.max(root.lastSeen, Number(parsed.lastSeen || 0))
          if (root.opened && !wasLoaded) root.readMark = Number(parsed.lastSeen || 0)
          root.unreadCount = root.opened ? 0 : Math.max(0, Number(parsed.unread || 0))
          root.loaded = true
          root.currentIndex = -1
          if (selectedFile) {
            for (var j = 0; j < root.visibleNotifications.length; j++) {
              if (String(root.visibleNotifications[j]._ritechoiceFile || "") === selectedFile) {
                root.currentIndex = j
                break
              }
            }
          }
          if (root.opened) root.queueSeen(parsed.maxTimestamp)
        } catch (error) {
          console.warn("RiteChoice23 Notification: failed to load archive:", error)
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

  Process { id: seenProc; environment: root.storeEnvironment; onExited: root.runSeen() }

  Process {
    id: clearProc
    command: [root.storeScript, "clear"]
    environment: root.storeEnvironment
    onExited: function(exitCode) {
      root.statusMessage = exitCode === 0 ? "All notifications cleared" : "Unable to clear notifications"
      statusTimer.restart()
      root.refresh()
    }
  }

  Process {
    id: dismissProc
    environment: root.storeEnvironment
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.activationOutput = text }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        var result = null
        var file = root.activationEntry ? String(root.activationEntry._ritechoiceFile || "") : ""
        try { result = JSON.parse(root.activationOutput || "{}") } catch (error) {}
        if (exitCode !== 0 || !result || !result.ok)
          console.warn("RiteChoice23 Notification: background activation failed:", result ? result.error : "invalid-response")
        var pending = Object.assign({}, root.pendingDismissals)
        delete pending[file]
        root.pendingDismissals = pending
        root.activationEntry = null
        root.refresh()
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "\uDB80\uDC9B" : "\uDB80\uDC9A"
    active: root.opened
    dimmed: root.dnd
    tooltipText: root.dnd
      ? (root.unreadCount > 0 ? "Silenced · " + root.unreadCount + " new" : "Notifications silenced")
      : (root.unreadCount > 0 ? root.unreadCount + " new notification" + (root.unreadCount === 1 ? "" : "s") : "Notifications")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleDnd()
      else if (mouseButton === Qt.LeftButton) root.toggle()
    }

    Rectangle {
      visible: root.badge === "Dot" && root.unreadCount > 0
      width: Style.space(6); height: width; radius: width / 2; color: Color.accent
      anchors.right: parent.right; anchors.top: parent.top
      anchors.rightMargin: Style.space(3); anchors.topMargin: Style.space(4)
    }

    Rectangle {
      visible: root.badge === "Count" && root.unreadCount > 0
      width: Math.max(countText.implicitWidth + Style.space(6), Style.space(13))
      height: Style.space(13)
      radius: Style.cornerRadius > 0 ? height / 2 : 0
      color: root.bar ? root.bar.urgent : Color.urgent
      anchors.right: parent.right; anchors.top: parent.top
      anchors.rightMargin: Style.space(1); anchors.topMargin: Style.space(1)

      Text {
        id: countText
        anchors.centerIn: parent
        text: root.unreadCount > 99 ? "99+" : String(root.unreadCount)
        color: root.background
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - Style.space(3))
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
    readonly property real heightLimit: availableCardHeight > 0
      ? Math.round(availableCardHeight * 0.8) : 0
    contentWidth: notificationPanel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: notificationPanel.fittedContentHeight(panelColumn.implicitHeight, heightLimit)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.searching
      onCloseRequested: root.close()
      onActivateRequested: root.activateCurrent()
      onDeleteRequested: root.dismissCurrent()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.setCurrentIndex((root.currentIndex < 0 ? (dy > 0 ? -1 : root.visibleNotifications.length) : root.currentIndex) + dy)
      }
      onTextKey: function(text) { if (text === "/") root.startSearch() }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(8)

        Item {
          id: header
          width: parent.width
          height: Math.max(title.implicitHeight, headerActions.height)

          PanelSectionHeader {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "NOTIFICATIONS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\uDB80\uDF49"
              tooltipText: "Search notifications ( / or Ctrl+F )"
              foreground: root.searching ? Color.accent : root.foreground
              fontFamily: root.fontFamily
              visible: root.totalCount > 0
              onClicked: root.searching ? root.endSearch() : root.startSearch()
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.dnd ? "\uDB80\uDC9B" : "\uDB80\uDC9A"
              tooltipText: root.dnd ? "Allow notifications" : "Silence notifications"
              foreground: root.dnd ? Color.accent : root.foreground
              fontFamily: root.fontFamily
              enabled: root.notificationService !== null
              onClicked: root.toggleDnd()
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: root.clearArmed ? "Sure?" : "Clear"
              foreground: root.clearArmed ? Color.urgent : root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              enabled: root.totalCount > 0 && !clearProc.running
              onClicked: root.armClear()
            }
          }
        }

        TextField {
          id: searchField
          width: parent.width
          visible: root.searching
          placeholderText: "Search app, title, or message"
          foreground: root.foreground
          onTextChanged: root.filter = text
          Keys.onEscapePressed: root.endSearch()
          Keys.onDownPressed: root.setCurrentIndex(root.currentIndex + 1)
          Keys.onUpPressed: root.setCurrentIndex(root.currentIndex - 1)
          Keys.onReturnPressed: root.activateCurrent()
          Keys.onEnterPressed: root.activateCurrent()
        }

        Item {
          width: parent.width
          implicitHeight: {
            if (!root.loaded || root.visibleNotifications.length === 0) return Style.space(190)
            var chrome = header.height + (root.searching ? searchField.implicitHeight : 0) + footer.implicitHeight + panelColumn.spacing * 3
            var panelBudget = notificationPanel.heightLimit > 0
              ? notificationPanel.heightLimit : notificationPanel.availableCardHeight
            var available = Math.max(Style.space(160), panelBudget - notificationPanel.verticalContentInset - chrome)
            return Math.min(notificationList.contentHeight, available)
          }

          Column {
            visible: !root.loaded || root.visibleNotifications.length === 0
            anchors.centerIn: parent
            spacing: Style.space(8)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: !root.loaded ? "\uf110" : (root.filter ? "\uf002" : "\uf0f3")
              color: root.faintForeground; font.family: root.fontFamily; font.pixelSize: Style.space(28)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: !root.loaded ? "Reading archive…" : (root.filter ? "No matches" : "No notifications")
              color: root.dimForeground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.filter ? "Try another app, title, or message." : "You’re all caught up."
              color: root.faintForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
          }

          ListView {
            id: notificationList
            visible: root.loaded && root.visibleNotifications.length > 0
            anchors.fill: parent
            model: root.visibleNotifications
            currentIndex: root.currentIndex
            spacing: Style.space(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            readonly property int scrollbarLane: Style.space(10)
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            add: Transition { NumberAnimation { properties: "opacity,y"; duration: 160; easing.type: Easing.OutCubic } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 110 } }
            displaced: Transition { NumberAnimation { property: "y"; duration: 150; easing.type: Easing.OutCubic } }

            delegate: Item {
              id: delegateRoot
              required property var modelData
              required property int index
              readonly property bool startsSection: index === 0 || root.dayKey(modelData.timestamp) !== root.dayKey(root.visibleNotifications[index - 1].timestamp)
              width: ListView.view.width - notificationList.scrollbarLane
              height: delegateColumn.implicitHeight

              Column {
                id: delegateColumn
                width: parent.width
                spacing: Style.space(5)

                Item {
                  width: parent.width
                  height: delegateRoot.startsSection ? Style.space(23) : 0
                  visible: delegateRoot.startsSection
                  PanelSectionHeader {
                    anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.leftMargin: Style.space(2)
                    text: root.dayLabel(delegateRoot.modelData.timestamp).toUpperCase()
                    foreground: root.foreground; fontFamily: root.fontFamily
                  }
                }

                NotificationCard {
                  width: parent.width
                  entry: delegateRoot.modelData
                  selected: root.currentIndex === delegateRoot.index
                  unread: root.numericTimestamp(entry.timestamp) > root.readMark
                  showBody: root.showBody
                  showPreview: root.showPreview
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

        Text {
          id: footer
          width: parent.width
          visible: root.totalCount > 0 || root.statusMessage.length > 0
          horizontalAlignment: Text.AlignHCenter
          text: root.statusMessage.length > 0
            ? root.statusMessage
            : root.filter
              ? root.visibleNotifications.length + " of " + root.totalCount + " notifications"
              : root.totalCount + " notification" + (root.totalCount === 1 ? "" : "s") + " kept · " + root.keepDays + " days"
          color: root.statusMessage.indexOf("Unable") >= 0 || root.statusMessage.indexOf("unavailable") >= 0 ? Color.urgent : root.faintForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          topPadding: Style.space(2)
        }
      }
    }
  }
}

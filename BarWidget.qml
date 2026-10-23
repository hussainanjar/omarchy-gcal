import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Next Google Calendar event in the bar, with an agenda popup and a setup guide.
// bin/gcal-agenda pulls the agenda from gcalcli into a cache file this widget watches.
Panel {
  id: root
  moduleName: "io.github.hussainanjar.gcal"
  ipcTarget: "io.github.hussainanjar.gcal"
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("bin/gcal-agenda").toString().replace(/^file:\/\//, ""))
  readonly property string cachePath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/omarchy-gcal/agenda.json"
  readonly property var options: {
    const args = ["--days", String(setting("daysAhead", 2)), "--refresh", String(setting("refreshMinutes", 5)),
                  "--lead", String(setting("reminderMinutes", 2))]
    String(setting("calendars", "")).split(",").map(s => s.trim()).filter(Boolean).forEach(c => args.push("--calendar", c))
    if (setting("gcalcliPath", "")) args.push("--gcalcli", setting("gcalcliPath", ""))
    return args
  }

  property var events: []
  property var status: ({ state: "" })
  property date now: new Date()
  property bool guideRequested: false
  readonly property bool needsSetup: status.state === "missing" || status.state === "signed-out"
  readonly property bool showGuide: guideRequested || needsSetup

  // Third-party plugins read theme colors from the bar, not the Color singleton.
  readonly property color fg: bar ? bar.foreground : "#cacccc"
  readonly property color bg: bar ? bar.background : "#101315"
  readonly property color accent: fg
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)

  readonly property var timed: events.filter(e => !e.allDay && new Date(e.end) > now)
  readonly property var next: timed.length > 0 && new Date(timed[0].start) - now < 12 * 3600000 ? timed[0] : null

  function short(title) { return title.length > 24 ? title.slice(0, 23) + "…" : title }
  function hhmm(iso) { return Qt.formatTime(new Date(iso), "HH:mm") }
  function label() {
    if (!next) return "󰃭"
    const mins = Math.round((new Date(next.start) - now) / 60000)
    if (mins <= 0) return "󰃭 " + short(next.title) + " · now"
    if (mins < 60) return "󰃭 " + short(next.title) + " in " + mins + "m"
    return "󰃭 " + hhmm(next.start) + " " + short(next.title)
  }
  function dayLabel(iso) {
    const today = new Date(now)
    today.setHours(0, 0, 0, 0)
    const diff = Math.round((new Date(iso).setHours(0, 0, 0, 0) - today) / 86400000)
    return diff <= 0 ? "TODAY" : diff === 1 ? "TOMORROW" : Qt.formatDate(new Date(iso), "dddd").toUpperCase()
  }
  function openUrl(url) {
    if (/^https?:\/\//i.test(url || "")) Quickshell.execDetached(["xdg-open", url])
  }
  function openCalendar() {
    Quickshell.execDetached(["omarchy-launch-or-focus-webapp", "Google Calendar", "https://calendar.google.com/calendar/r"])
    root.close()
  }
  function inTerminal(command) {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", command])
    root.close()
  }
  function sync() {
    if (!syncer.running) syncer.running = true
  }
  function load(text) {
    try {
      const data = JSON.parse(text)
      events = (data.events || []).filter(e => new Date(e.end) > new Date())
      status = data
    } catch (e) {
      events = []
      status = { state: "" }
    }
  }
  function remind(event) {
    if (setting("reminderStyle", "Popup") === "Popup") return meeting.show(event)
    const cmd = ["omarchy-notification-send", "--app-name", "Google Calendar", "-g", "󰃭", "-u", "critical",
                 event.title, "Starts " + hhmm(event.start)]
    if (event.meet || event.link) cmd.push("--exec", "xdg-open", event.meet || event.link)
    Quickshell.execDetached(cmd)
  }

  onOptionsChanged: sync()
  onOpenedChanged: if (!opened) Qt.callLater(() => guideRequested = false)

  MeetingModal { id: meeting; fg: root.fg; bg: root.bg }
  IpcHandler {
    target: "io.github.hussainanjar.gcal.meeting"
    function remind(payload: string): void {
      try { meeting.show(JSON.parse(payload)) } catch (e) { console.warn("Invalid meeting payload") }
    }
    function preview(): void { if (root.next) meeting.show(root.next) }
    function dismiss(): void { meeting.opened = false }
  }
  IpcHandler {
    target: "io.github.hussainanjar.gcal.setup"
    function open(): void { root.guideRequested = true; root.open() }
  }

  FileView {
    path: root.cachePath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.load(text())
    onLoadFailed: root.load("")
  }
  Process {
    id: ticker
    command: ["python3", root.script, "tick"].concat(root.options)
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { JSON.parse(text).forEach(root.remind) } catch (e) {}
      }
    }
  }
  Process { id: syncer; command: ["python3", root.script, "fetch"].concat(root.options) }
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: {
      root.now = new Date()
      if (!ticker.running) ticker.running = true
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label()
    dimmed: root.needsSetup
    active: root.next !== null && new Date(root.next.start) - root.now < 5 * 60000
    tooltipText: root.needsSetup ? "Click to set up Google Calendar" : (root.status.error || "")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openCalendar()
      else if (b === Qt.MiddleButton) root.sync()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(Style.space(510))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        if (!root.showGuide && agenda.currentItem) { root.close(); meeting.show(agenda.currentItem.modelData) }
      }
      onMoveRequested: function(dx, dy) {
        if (dy > 0) agenda.incrementCurrentIndex()
        else if (dy < 0) agenda.decrementCurrentIndex()
      }

      Column {
        id: heading
        width: parent.width
        spacing: Style.space(10)
        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, actions.implicitHeight)
          Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            text: root.showGuide ? "Set up Google Calendar" : "Agenda"
            color: root.fg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !root.showGuide
              text: Qt.formatDateTime(root.now, "ddd d MMM · HH:mm")
              color: root.accent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
            PanelActionButton {
              iconText: syncer.running ? "󰑓" : "󰑐"
              tooltipText: "Sync now"
              foreground: root.fg
              visible: !root.needsSetup
              onClicked: root.sync()
            }
            PanelActionButton {
              iconText: root.showGuide ? "󰃭" : "󰋗"
              tooltipText: root.showGuide ? "Back to agenda" : "Setup guide"
              foreground: root.fg
              visible: !root.needsSetup
              onClicked: root.guideRequested = !root.guideRequested
            }
          }
        }
        PanelSeparator { foreground: root.fg }
      }

      SetupGuide {
        anchors.top: heading.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: parent.bottom
        width: parent.width
        visible: root.showGuide
        widget: root
      }

      Text {
        anchors.top: heading.bottom
        anchors.topMargin: Style.space(16)
        width: parent.width
        visible: !root.showGuide && root.events.length === 0
        text: root.status.state === "" ? "Syncing your calendar…" : root.status.error || "Nothing in the next " + root.setting("daysAhead", 2) + " days"
        wrapMode: Text.Wrap
        color: root.fg
        font.family: root.bar.fontFamily
      }
      ListView {
        id: agenda
        anchors.top: heading.bottom
        anchors.topMargin: Style.space(10)
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.space(8)
        width: parent.width
        visible: !root.showGuide
        clip: true
        model: root.events
        spacing: Style.space(5)
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        onVisibleChanged: if (visible) positionViewAtBeginning()
        delegate: Column {
          id: entry
          required property var modelData
          required property int index
          readonly property bool current: !modelData.allDay && new Date(modelData.start) <= root.now && new Date(modelData.end) > root.now
          readonly property bool upcoming: !current && root.next !== null && modelData.start === root.next.start && modelData.title === root.next.title
          readonly property bool highlighted: current || upcoming
          width: agenda.width - Style.space(12)
          spacing: Style.space(5)
          PanelSectionHeader {
            visible: index === 0 || root.dayLabel(root.events[index - 1].start) !== root.dayLabel(modelData.start)
            text: root.dayLabel(modelData.start)
            foreground: root.accent
            fontFamily: root.bar.fontFamily
          }
          Rectangle {
            width: parent.width
            height: modelData.allDay ? Style.space(32) : Style.space(65)
            radius: Style.space(4)
            color: entry.highlighted ? Style.selectedFillFor(root.fg, root.accent)
                 : rowMouse.containsMouse ? Style.hoverFillFor(root.fg, root.accent) : "transparent"
            border.width: entry.highlighted || agenda.currentIndex === entry.index ? 1 : 0
            border.color: entry.highlighted ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.close(); meeting.show(modelData) }
            }
            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.right: join.visible ? join.left : parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)
              Text {
                width: parent.width
                text: (modelData.allDay ? "All day · " : "") + modelData.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: modelData.allDay ? root.muted : root.fg
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: entry.highlighted
              }
              Text {
                visible: !modelData.allDay
                width: parent.width
                text: root.hhmm(modelData.start) + "–" + root.hhmm(modelData.end) + (entry.current ? "  ·  NOW" : entry.upcoming ? "  ·  NEXT · in " + Math.max(1, Math.ceil((new Date(modelData.start) - root.now) / 60000)) + "m" : "")
                elide: Text.ElideRight
                color: entry.highlighted ? root.accent : root.muted
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Button {
              id: join
              visible: !!modelData.meet
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "Join"
              bordered: true
              foreground: root.fg
              accent: root.accent
              fontFamily: root.bar.fontFamily
              onClicked: { root.openUrl(modelData.meet); root.close() }
            }
          }
        }
      }
      Text {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        visible: !root.showGuide
        text: root.status.state === "ok" || root.status.state === "" ? "Click a meeting for details · Right-click the bar to open Calendar" : root.status.error
        color: root.status.state === "ok" || root.status.state === "" ? root.muted : root.bar.urgent
        elide: Text.ElideRight
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

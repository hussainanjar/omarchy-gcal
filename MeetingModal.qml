import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Full-screen reminder card with a countdown to the meeting start and a Join button.
Item {
  id: root
  property var meeting: ({})
  property bool opened: false
  property int secondsLeft: 0
  property color fg: "#cacccc"
  property color bg: "#101315"
  readonly property color accent: fg
  readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.6)

  function show(event) {
    meeting = event
    updateCountdown()
    opened = true
    Qt.callLater(function() { dismiss.forceActiveFocus() })
  }
  function updateCountdown() {
    secondsLeft = Math.max(0, Math.ceil((new Date(meeting.start) - Date.now()) / 1000))
  }
  function openUrl(url) {
    if (/^https?:\/\//i.test(url || "")) Quickshell.execDetached(["xdg-open", url])
  }

  Timer {
    interval: 250
    running: root.opened && root.secondsLeft > 0
    repeat: true
    onTriggered: root.updateCountdown()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-gcal-meeting"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle { anchors.fill: parent; color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: root.opened = false }

    Rectangle {
      id: card
      width: Math.min(Style.space(460), panel.width - 40)
      height: Math.min(body.implicitHeight + Style.space(36), panel.height - 40)
      anchors.centerIn: parent
      color: root.bg
      border.color: root.fg
      border.width: 1
      MouseArea { anchors.fill: parent }
      Keys.onEscapePressed: root.opened = false

      Column {
        id: body
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(12)

        Text {
          text: "󰃰  " + (root.secondsLeft > 0 ? "Meeting starting soon" : "Meeting in progress")
          color: root.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }
        Text {
          width: parent.width
          text: root.meeting.title || "Meeting"
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.title * 1.6
          font.bold: true
        }
        Column {
          width: parent.width
          spacing: Style.space(6)
          Text {
            text: root.secondsLeft > 0
              ? "Starts in " + Math.floor(root.secondsLeft / 60) + "m " + (root.secondsLeft % 60) + "s"
              : "Started " + Qt.formatTime(new Date(root.meeting.start), "HH:mm")
            color: root.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          Text {
            width: parent.width
            text: root.meeting.start ? Qt.formatTime(new Date(root.meeting.start), "HH:mm") + " – " + Qt.formatTime(new Date(root.meeting.end), "HH:mm") + (root.meeting.meet ? "  ·  " + (/meet\.google\.com/.test(root.meeting.meet) ? "Google Meet" : "Video meeting") : "") : ""
            wrapMode: Text.Wrap
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
        Text {
          visible: !!root.meeting.location
          width: parent.width
          text: root.meeting.location || ""
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Row {
          spacing: Style.space(8)
          Button {
            text: "󰍫  Join meeting"
            visible: !!root.meeting.meet
            bordered: true
            selected: true
            foreground: root.fg
            accent: root.accent
            onClicked: { root.openUrl(root.meeting.meet); root.opened = false }
          }
          Button {
            text: "󰃭  Details"
            visible: !!root.meeting.link
            bordered: true
            foreground: root.fg
            accent: root.accent
            onClicked: { root.openUrl(root.meeting.link); root.opened = false }
          }
          Button {
            id: dismiss
            text: "Dismiss"
            bordered: true
            focusable: true
            foreground: root.fg
            accent: root.accent
            onClicked: root.opened = false
            Keys.onReturnPressed: root.opened = false
          }
        }
      }
    }
  }
}

import QtQuick
import QtQuick.Controls as Controls
import qs.Ui
import qs.Commons

// Step-by-step Google Calendar setup, ticked off from the state gcal-agenda writes to the cache.
Flickable {
  id: guide
  property var widget
  readonly property var status: widget.status
  readonly property string fontFamily: widget.bar.fontFamily
  readonly property string setupCommand: "python3 '" + widget.script + "' setup" +
    (widget.setting("gcalcliPath", "") ? " --gcalcli '" + widget.setting("gcalcliPath", "") + "'" : "")

  readonly property var steps: [
    {
      title: "Install gcalcli",
      done: !!status.gcalcli,
      body: "gcalcli is the command-line client this widget uses to read your calendar.",
      code: "omarchy pkg aur add gcalcli",
      actions: [{ label: "Install", run: () => widget.inTerminal("omarchy pkg aur add gcalcli") }]
    },
    {
      title: "Create a Google OAuth client",
      done: !!status.signedIn,
      body: "Google requires every gcalcli user to bring their own OAuth client. In Google Cloud Console:\n" +
            "1. Create a project and enable the Google Calendar API.\n" +
            "2. Under Google Auth Platform, set Audience to External and add your Google account as a test user.\n" +
            "3. Create a client with application type Desktop app and keep its ID and secret.\n" +
            "Tip: Publish the app to Production, or the sign-in expires every 7 days.",
      actions: [
        { label: "Enable API", run: () => widget.openUrl("https://console.cloud.google.com/apis/library/calendar-json.googleapis.com") },
        { label: "Create client", run: () => widget.openUrl("https://console.cloud.google.com/auth/clients/create") }
      ]
    },
    {
      title: "Sign in",
      done: !!status.signedIn && status.state !== "signed-out",
      body: status.state === "signed-out" && status.signedIn
        ? "Your Google sign-in expired. Sign in again to resume syncing."
        : "Opens a terminal that runs gcalcli init. Paste the client ID and secret, then approve access in your browser.",
      code: "gcalcli init",
      actions: [{ label: "Sign in", run: () => widget.inTerminal(guide.setupCommand) }]
    },
    {
      title: "Sync",
      done: status.state === "ok",
      body: status.state === "ok"
        ? "All set. The calendar syncs every " + widget.setting("refreshMinutes", 5) + " minutes. Middle-click the bar to sync now."
        : status.state === "error" ? status.error : "Fetch your agenda once everything above is ticked.",
      actions: [{ label: "Sync now", run: () => widget.sync() }]
    }
  ]

  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

  Column {
    id: column
    width: guide.width - Style.space(12)
    spacing: Style.space(16)

    Repeater {
      model: guide.steps
      delegate: Row {
        id: step
        required property var modelData
        required property int index
        width: column.width
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(22)
          height: width
          radius: width / 2
          color: step.modelData.done ? guide.widget.accent : "transparent"
          border.width: 1
          border.color: step.modelData.done ? guide.widget.accent : guide.widget.muted
          Text {
            anchors.centerIn: parent
            text: step.modelData.done ? "󰄬" : String(step.index + 1)
            color: step.modelData.done ? guide.widget.bg : guide.widget.fg
            font.family: guide.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
        Column {
          width: parent.width - Style.space(32)
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: step.modelData.title
            color: step.modelData.done ? guide.widget.muted : guide.widget.fg
            font.family: guide.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            font.strikeout: step.modelData.done && step.index < 3
          }
          Text {
            width: parent.width
            text: step.modelData.body || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            lineHeight: 1.15
            color: guide.widget.muted
            font.family: guide.fontFamily
            font.pixelSize: Style.font.caption
          }
          Rectangle {
            visible: !!step.modelData.code && !step.modelData.done
            width: parent.width
            height: code.implicitHeight + Style.space(10)
            radius: Style.space(3)
            color: Style.normalFillFor(guide.widget.fg, guide.widget.accent)
            Text {
              id: code
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "$ " + (step.modelData.code || "")
              color: guide.widget.accent
              font.family: guide.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Row {
            visible: !step.modelData.done || step.index === 3
            spacing: Style.space(6)
            Repeater {
              model: step.modelData.actions
              delegate: Button {
                required property var modelData
                text: modelData.label
                bordered: true
                foreground: guide.widget.fg
                accent: guide.widget.accent
                fontFamily: guide.fontFamily
                onClicked: modelData.run()
              }
            }
          }
        }
      }
    }
  }
}

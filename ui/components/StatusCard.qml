import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Pane {
    id: card
    property string title: ""
    property string subtitle: ""
    property string state_: "unknown"   // ok | warn | fail | unknown
    property string actionText: ""
    property bool busy: false
    signal action()

    Layout.fillWidth: true
    Layout.preferredHeight: 122
    Layout.minimumHeight: 122
    Material.elevation: 1
    Material.background: Theme.surface
    padding: 16

    contentItem: ColumnLayout {
        spacing: 6
        RowLayout {
            spacing: 10
            Rectangle {   // status chip
                width: 9; height: 9; radius: 4.5
                color: Theme.stateColor(card.state_)
            }
            Label { text: card.title; font.bold: true; font.pixelSize: 14 }
            Item { Layout.fillWidth: true }
        }
        Label {
            text: card.subtitle
            color: Theme.textSecondary; font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Item { Layout.fillHeight: true }   // spacer BEFORE the button:
        Button {                           // text top, action bottom
            visible: card.actionText.length > 0
            text: card.actionText
            highlighted: true
            enabled: !card.busy
            implicitHeight: 36
            Material.elevation: 0
            onClicked: card.action()
        }
    }
}

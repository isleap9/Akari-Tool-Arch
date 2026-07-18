import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Status card: hairline border, hover lift, status badge in the corner.
Rectangle {
    id: card
    property string title: ""
    property string subtitle: ""
    property string state_: "unknown"   // ok | info | warn | fail | unknown
    property string actionText: ""
    property bool busy: false
    signal action()

    Layout.fillWidth: true
    Layout.preferredHeight: 128
    Layout.minimumHeight: 128
    radius: Theme.cardRadius
    color: hover.hovered ? Theme.surfaceHover : Theme.surface
    border.width: 1
    border.color: card.state_ === "warn" || card.state_ === "fail"
                  ? Qt.alpha(Theme.stateColor(card.state_), 0.35)
                  : hover.hovered ? Theme.borderHover : Theme.border
    Behavior on color        { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    HoverHandler { id: hover }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        RowLayout {
            spacing: 10
            Layout.fillWidth: true
            Label {
                text: card.title
                font.bold: true
                font.pixelSize: Theme.fsHeading
                color: Theme.textPrimary
            }
            Item { Layout.fillWidth: true }
            Badge {
                text: Theme.stateLabel(card.state_)
                tint: Theme.stateColor(card.state_)
            }
        }
        Label {
            text: card.subtitle
            color: Theme.textSecondary
            font.pixelSize: Theme.fsCaption
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            Layout.fillWidth: true
        }
        Item { Layout.fillHeight: true }
        Button {
            visible: card.actionText.length > 0
            text: card.actionText
            highlighted: true
            enabled: !card.busy
            implicitHeight: 34
            font.pixelSize: Theme.fsCaption
            Material.elevation: 0
            onClicked: card.action()
        }
    }
}

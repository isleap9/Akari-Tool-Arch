import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ItemDelegate {
    id: nav
    property string glyph: ""
    property string label: ""
    property bool selected: false
    signal navigate()

    Layout.fillWidth: true
    implicitHeight: 36
    padding: 0
    onClicked: navigate()

    contentItem: Item {
        Rectangle {
            id: bar
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 0
            width: 3
            height: nav.selected ? 18 : 0
            radius: 1.5
            color: Theme.accent
            Behavior on height { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }
        Label {
            id: glyphLabel
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 14
            width: 18
            horizontalAlignment: Text.AlignHCenter
            text: nav.glyph
            font.family: Theme.monoFont
            font.pixelSize: 13
            color: nav.selected ? Theme.accent : Theme.textMuted
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: glyphLabel.right
            anchors.leftMargin: 10
            text: nav.label
            color: nav.selected ? Theme.textPrimary
                 : nav.hovered  ? Theme.textSecondary : Theme.textMuted
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsBody
            font.weight: nav.selected ? Font.DemiBold : Font.Medium
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }
    background: Rectangle {
        radius: 6
        color: nav.selected ? Theme.navSelected
             : nav.hovered  ? Theme.navHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}

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
            anchors.leftMargin: 6
            width: 3; height: 18; radius: 1.5
            color: nav.selected ? Theme.accent : "transparent"
        }
        Label {
            id: glyphLabel
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: bar.right
            anchors.leftMargin: 10
            text: nav.glyph
            color: nav.selected ? Theme.textPrimary : "#888"
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: glyphLabel.right
            anchors.leftMargin: 10
            text: nav.label
            color: nav.selected ? Theme.textPrimary : "#999"
            font.pixelSize: 13
        }
    }
    background: Rectangle {
        radius: 6
        color: nav.selected ? Theme.navSelected
             : nav.hovered  ? Theme.navHover : "transparent"
    }
}

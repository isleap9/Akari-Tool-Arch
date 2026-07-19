import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Header HUD chip: mono label + emphasized value, optional glowing dot
Rectangle {
    id: chip
    property string label: ""
    property string value: ""
    property color dotColor: "transparent"

    radius: Theme.btnRadius
    color: Theme.surface
    border.width: 1
    border.color: Theme.border
    implicitHeight: 30
    implicitWidth: row.implicitWidth + 24

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Item {
            visible: chip.dotColor.a > 0
            Layout.preferredWidth: 7
            Layout.preferredHeight: 7
            Rectangle {
                anchors.centerIn: parent
                width: 15; height: 15; radius: 7.5
                color: Qt.alpha(chip.dotColor, 0.25)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 7; height: 7; radius: 3.5
                color: chip.dotColor
            }
        }
        Label {
            text: chip.label
            font.family: Theme.monoFont
            font.pixelSize: Theme.fsLabel
            color: Theme.textSecondary
        }
        Label {
            visible: chip.value.length > 0
            text: chip.value
            font.family: Theme.monoFont
            font.pixelSize: Theme.fsLabel
            font.weight: Font.Bold
            color: Theme.textPrimary
        }
    }
}

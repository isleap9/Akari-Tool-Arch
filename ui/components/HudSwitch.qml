import QtQuick
import QtQuick.Controls

// Mock-spec toggle: 40×22 track (off #34343B / on accent), 16px sliding knob
Switch {
    id: sw
    property string title: ""
    property string description: ""

    leftPadding: 0
    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 22
        radius: 11
        anchors.verticalCenter: parent.verticalCenter
        color: sw.checked ? Theme.accent : Theme.borderHover
        Behavior on color { ColorAnimation { duration: 150 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3
            x: sw.checked ? 21 : 3
            color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Column {
        leftPadding: sw.indicator.width + 14
        spacing: 2
        Label {
            text: sw.title
            font.family: Theme.hudFont
            font.pixelSize: Theme.fsHeading
            font.weight: Font.DemiBold
            font.letterSpacing: 0.3
            color: Theme.textPrimary
        }
        Label {
            text: sw.description
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsCaption
            color: Theme.textSecondary
        }
    }
}

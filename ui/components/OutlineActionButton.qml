import QtQuick
import QtQuick.Controls

// Red outline action (mock: color #E84545, border #E8454559, hover bg #E8454518)
Button {
    id: btn
    property color tint: Theme.accent

    implicitHeight: 32
    leftPadding: 14; rightPadding: 14
    font.family: Theme.hudFont
    font.pixelSize: Theme.fsCaption
    font.weight: Font.Bold
    font.letterSpacing: 0.5

    contentItem: Label {
        text: btn.text
        font: btn.font
        color: btn.tint
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: btn.enabled ? 1 : 0.4
    }
    background: Rectangle {
        radius: 6
        color: btn.down ? Qt.alpha(btn.tint, 0.16)
             : btn.hovered ? Qt.alpha(btn.tint, 0.09) : "transparent"
        border.width: 1
        border.color: Qt.alpha(btn.tint, 0.35)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}

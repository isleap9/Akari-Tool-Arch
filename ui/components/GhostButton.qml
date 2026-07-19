import QtQuick
import QtQuick.Controls

// Secondary outline button (mock: transparent bg, #34343B border, Rajdhani 600)
Button {
    id: btn
    property bool accentHover: false

    implicitHeight: 36
    leftPadding: 16; rightPadding: 16
    font.family: Theme.hudFont
    font.pixelSize: Theme.fsBody
    font.weight: Font.DemiBold
    font.letterSpacing: 0.5

    contentItem: Label {
        text: btn.text
        font: btn.font
        color: btn.hovered ? Theme.textPrimary : Theme.textSecondary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: btn.enabled ? 1 : 0.4
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    background: Rectangle {
        radius: Theme.btnRadius
        color: btn.down ? Theme.surfaceHover : "transparent"
        border.width: 1
        border.color: btn.hovered ? (btn.accentHover ? Theme.accent : Theme.textFaint)
                                  : Theme.borderHover
        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    }
}

import QtQuick
import QtQuick.Controls

// Glowing red HUD CTA
Button {
    id: btn
    property bool glow: false

    implicitHeight: 38
    leftPadding: 18; rightPadding: 18
    font.family: Theme.hudFont
    font.pixelSize: Theme.fsHeading
    font.weight: Font.Bold
    font.letterSpacing: 0.5

    contentItem: Label {
        text: btn.text
        font: btn.font
        color: "#FFFFFF"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: btn.enabled ? 1 : 0.5
    }
    background: Item {
        Rectangle {   // pulsing glow behind
            visible: btn.glow && btn.enabled
            anchors.centerIn: parent
            width: parent.width + 10
            height: parent.height + 10
            radius: 12
            color: Qt.alpha(Theme.accent, 0.18)
            SequentialAnimation on opacity {
                running: btn.glow && btn.enabled
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.9;  duration: 1500; easing.type: Easing.InOutSine }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: !btn.enabled ? Theme.accentDim
                 : btn.down     ? Theme.accentDim
                 : btn.hovered  ? Theme.accentHover : Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
        }
    }
}

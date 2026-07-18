import QtQuick
import QtQuick.Controls

// Small uppercase pill — the one badge used everywhere (RUNNING, AUR, PASS…)
Rectangle {
    id: badge
    property string text: ""
    property color tint: Theme.textMuted

    radius: height / 2
    color: Qt.alpha(tint, 0.13)
    border.width: 1
    border.color: Qt.alpha(tint, 0.28)
    width: label.implicitWidth + 16
    height: 19

    Label {
        id: label
        anchors.centerIn: parent
        text: badge.text
        font.pixelSize: 9
        font.letterSpacing: 1.2
        font.bold: true
        color: badge.tint
    }
}

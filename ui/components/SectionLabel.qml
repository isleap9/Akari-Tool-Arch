import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// HUD caption — always uppercase Rajdhani with wide tracking
Label {
    font.family: Theme.hudFont
    font.pixelSize: Theme.fsMicro
    font.weight: Font.Bold
    font.letterSpacing: 2.5
    color: Theme.textMuted
    leftPadding: 10
    Layout.topMargin: 16
    Layout.bottomMargin: 2
}

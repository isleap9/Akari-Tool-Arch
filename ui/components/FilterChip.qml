import QtQuick
import QtQuick.Controls

// A toggleable filter pill. Distinct from HudChip, which is a read-only
// header readout — this one is a control and looks like it can be pressed.
Rectangle {
    id: chip
    property string text: ""
    property string count: ""
    property bool selected: false
    signal clicked()

    radius: Theme.btnRadius
    implicitHeight: 36
    implicitWidth: label.implicitWidth + countLabel.implicitWidth
                   + (countLabel.visible ? 8 : 0) + 26

    color: selected ? Qt.alpha(Theme.accent, 0.14)
                    : (hover.hovered ? Theme.surfaceHover : Theme.surface)
    border.width: 1
    border.color: selected ? Qt.alpha(Theme.accent, 0.5)
                           : (hover.hovered ? Theme.borderHover : Theme.border)
    Behavior on color        { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: chip.clicked() }

    Row {
        anchors.centerIn: parent
        spacing: 8
        Label {
            id: label
            text: chip.text
            font.family: Theme.monoFont
            font.pixelSize: Theme.fsLabel
            font.letterSpacing: 1.2
            font.weight: chip.selected ? Font.Bold : Font.Normal
            color: chip.selected ? Theme.accentText : Theme.textSecondary
        }
        Label {
            id: countLabel
            visible: chip.count.length > 0
            text: chip.count
            font.family: Theme.monoFont
            font.pixelSize: Theme.fsLabel
            color: chip.selected ? Theme.accentText : Theme.textFaint
        }
    }
}

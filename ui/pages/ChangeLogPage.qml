import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    spacing: 0

    Component.onCompleted: bridge.refreshChangeLog()

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 12
        Label {
            text: "Every change Akari Tool has made to this system. " +
                  "Backups: pacman.conf edits keep a .akari.bak copy."
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Button {
            text: "Refresh"
            flat: true
            enabled: !bridge.running
            onClicked: bridge.refreshChangeLog()
        }
    }

    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        contentHeight: logArea.height
        clip: true

        Rectangle { anchors.fill: parent; color: Theme.surfaceLog; radius: Theme.cardRadius; border.width: 1; border.color: Theme.border; z: -1 }
        TextArea {
            id: logArea
            width: flick.width
            readOnly: true
            wrapMode: TextArea.Wrap
            font.family: "monospace"
            font.pixelSize: 12
            color: Theme.textSecondary
            text: bridge.changeLog
            background: null
        }
    }
}

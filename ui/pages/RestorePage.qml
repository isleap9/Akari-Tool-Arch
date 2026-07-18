import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    property var confirmDialog: null
    spacing: 0

    Component.onCompleted: bridge.refreshRestore()

    Label {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 12
        text: "Every risky edit keeps a backup next to the original. Restoring saves " +
              "the current state first, so a restore is itself undoable."
        color: Theme.textSecondary
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }

    Label {
        visible: bridge.restoreItems.length === 0
        Layout.leftMargin: Theme.pagePadding
        text: "No backups yet — they appear here after Akari edits a config file."
        color: Theme.textMuted
        font.pixelSize: 13
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        clip: true
        spacing: 8
        model: bridge.restoreItems

        delegate: Rectangle {
            required property var modelData
            readonly property bool isInfo: modelData.backup === "-"
            width: list.width
            height: 72
            radius: Theme.cardRadius
            color: rowHover.hovered ? Theme.surfaceHover : Theme.surface
            border.width: 1
            border.color: rowHover.hovered ? Theme.borderHover : Theme.border
            Behavior on color        { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            HoverHandler { id: rowHover }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: restoreBtn.left
                anchors.rightMargin: 16
                spacing: 4

                Label {
                    text: isInfo ? "System snapshots" : modelData.original
                    font.family: isInfo ? undefined : "monospace"
                    font.pixelSize: 14
                    font.bold: true
                }
                Label {
                    text: isInfo ? modelData.when
                                 : "Backup from " + modelData.when + "  ·  " + modelData.backup
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Button {
                id: restoreBtn
                visible: !isInfo
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 16
                text: "Restore"
                flat: true
                implicitHeight: 36
                Material.foreground: Theme.warn
                enabled: !bridge.running
                onClicked: page.confirmDialog.openWith(
                    "Restore " + modelData.original,
                    "restore " + modelData.id,
                    function() { bridge.applyRestore(modelData.id) })
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    property var confirmDialog: null
    spacing: 0

    Component.onCompleted: bridge.refreshKernels()

    Label {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 12
        text: "Kernels install alongside your current one — nothing is removed. " +
              "Pick the new kernel from the boot menu after a reboot."
        color: Theme.textSecondary
        font.pixelSize: 12
        wrapMode: Text.Wrap
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
        model: bridge.kernels

        delegate: Rectangle {
            required property var modelData
            width: list.width
            height: 72
            radius: Theme.cardRadius
            color: Theme.surface

            // Left: name + badges + description
            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: rightSide.left
                anchors.rightMargin: 16
                spacing: 4

                Row {
                    spacing: 8
                    Label {
                        text: modelData.name
                        font.family: "monospace"
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Rectangle {   // RUNNING badge
                        visible: modelData.running
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 4
                        color: Qt.alpha(Theme.ok, 0.15)
                        width: runLabel.width + 12
                        height: 18
                        Label {
                            id: runLabel
                            anchors.centerIn: parent
                            text: "RUNNING"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            color: Theme.ok
                        }
                    }
                    Rectangle {   // AUR badge
                        visible: modelData.source === "aur"
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 4
                        color: Qt.alpha(Theme.warn, 0.15)
                        width: aurLabel.width + 12
                        height: 18
                        Label {
                            id: aurLabel
                            anchors.centerIn: parent
                            text: "AUR"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                            color: Theme.warn
                        }
                    }
                }
                Label {
                    text: modelData.description
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            // Right: action zone, always right-aligned
            Item {
                id: rightSide
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 16
                width: 120
                height: parent.height

                // Not installed -> Install
                Button {
                    visible: !modelData.installed
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "Install"
                    highlighted: true
                    implicitHeight: 36
                    Material.elevation: 0
                    enabled: !bridge.running
                    onClicked: {
                        var name = modelData.name
                        var isAur = modelData.source === "aur"
                        page.confirmDialog.openWith(
                            "Install " + name
                                + (isAur ? " (AUR — builds in-app, can take a while)" : ""),
                            "kernel " + name,
                            function() {
                                bridge.applyKernel(name)
                            })
                    }
                }

                // Installed, not running, not stock -> Uninstall
                Button {
                    visible: modelData.installed && !modelData.running
                             && modelData.name !== "linux"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "Uninstall"
                    flat: true
                    implicitHeight: 36
                    Material.foreground: Theme.fail
                    enabled: !bridge.running
                    onClicked: page.confirmDialog.openWith(
                        "Remove " + modelData.name,
                        "remove-kernel " + modelData.name,
                        function() { bridge.removeKernel(modelData.name) })
                }

                // Installed stock kernel, not running -> label only
                Label {
                    visible: modelData.installed && !modelData.running
                             && modelData.name === "linux"
                    anchors.centerIn: parent
                    text: "installed"
                    font.pixelSize: 11
                    color: Theme.ok
                }
            }
        }
    }
}

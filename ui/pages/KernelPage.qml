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
            height: 76
            radius: Theme.cardRadius
            color: rowHover.hovered ? Theme.surfaceHover : Theme.surface
            border.width: 1
            border.color: modelData.running ? Qt.alpha(Theme.ok, 0.3)
                        : rowHover.hovered ? Theme.borderHover : Theme.border
            Behavior on color        { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            HoverHandler { id: rowHover }

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
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsHeading
                        font.weight: Font.Bold
                    }
                    Badge {
                        visible: modelData.running
                        anchors.verticalCenter: parent.verticalCenter
                        text: "RUNNING"
                        tint: Theme.ok
                    }
                    Badge {
                        visible: modelData.source === "cachyos"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CACHYOS REPO"
                        tint: Theme.info
                    }
                    Badge {
                        visible: modelData.source === "aur"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "AUR"
                        tint: Theme.warn
                    }
                    }
                Label {
                    text: modelData.description
                    color: Theme.textSecondary
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.fsCaption
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
                OutlineActionButton {
                    visible: !modelData.installed
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "INSTALL"
                    enabled: !bridge.running
                    onClicked: {
                        var name = modelData.name
                        var isAur = modelData.source === "aur"
                        var isCachy = modelData.source === "cachyos"
                        page.confirmDialog.openWith(
                            "Install " + name
                                + (isAur ? " (AUR — builds in-app, can take a while)"
                                 : isCachy ? " (adds the official CachyOS repo, installs prebuilt)"
                                 : ""),
                            "kernel " + name,
                            function() {
                                bridge.applyKernel(name)
                            })
                    }
                }

                // Installed, not running, not stock -> Uninstall
                OutlineActionButton {
                    visible: modelData.installed && !modelData.running
                             && modelData.name !== "linux"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    text: "UNINSTALL"
                    tint: Theme.warn
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
                    text: "INSTALLED"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsMicro
                    font.letterSpacing: 1
                    color: Theme.ok
                }
                Label {
                    visible: modelData.running
                    anchors.centerIn: parent
                    text: "IN USE"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsMicro
                    font.letterSpacing: 1
                    color: Theme.ok
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

// Apps — a system-wide uninstaller. Lists everything the user explicitly
// installed (pacman -Qe + Flatpak apps), searchable, with one-click
// removal. Critical system packages are marked protected by the backend
// and never get a Remove button.
ColumnLayout {
    id: page
    property var confirmDialog: null
    spacing: 0

    property string filter: ""

    function visibleApps() {
        var out = [], f = filter.toLowerCase()
        for (var i = 0; i < bridge.apps.length; i++) {
            var a = bridge.apps[i]
            if (f === ""
                || a.name.toLowerCase().indexOf(f) !== -1
                || a.description.toLowerCase().indexOf(f) !== -1)
                out.push(a)
        }
        return out
    }

    Component.onCompleted: bridge.refreshApps()

    // ---- header row -----------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 10
        spacing: 12

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: Theme.rowRadius
            color: Theme.surface
            border.width: 1
            border.color: search.activeFocus ? Theme.borderFocus : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                Label {
                    text: "\u2315"
                    font.pixelSize: Theme.fsBody
                    color: Theme.textFaint
                }
                TextField {
                    id: search
                    objectName: "searchField"
                    Layout.fillWidth: true
                    // No placeholderText: the Material style animates it into a
                    // floating label above the field, which escapes this custom
                    // bordered wrapper. Use a plain static hint instead.
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsBody
                    color: Theme.textPrimary
                    background: null
                    topPadding: 0
                    bottomPadding: 0
                    leftPadding: 0
                    rightPadding: 0
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: page.filter = text

                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text.length === 0
                        text: "Search installed apps…"
                        font: search.font
                        color: Theme.textMuted
                    }
                }
            }
        }
        Label {
            text: bridge.apps.length === 0
                  ? "Loading…"
                  : list.model.length + " apps"
            font.family: Theme.monoFont
            color: Theme.textSecondary
            font.pixelSize: Theme.fsLabel
        }
        GhostButton {
            text: "REFRESH"
            implicitHeight: 36
            font.pixelSize: Theme.fsBody
            enabled: !bridge.running
            onClicked: bridge.refreshApps()
        }
    }

    // ---- app list ---------------------------------------------------------
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        clip: true
        spacing: 4
        model: page.visibleApps()

        delegate: Rectangle {
            required property var modelData
            width: list.width
            height: 54
            radius: Theme.rowRadius
            color: hoverArea.hovered ? Theme.surfaceHover : Theme.surface
            border.width: 1
            border.color: hoverArea.hovered ? Theme.borderHover : Theme.border
            Behavior on color        { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 8
                        Label {
                            text: modelData.name
                            font.family: Theme.monoFont
                            font.pixelSize: 13
                            color: Theme.textPrimary
                        }
                        Badge {
                            visible: modelData.source === "flatpak"
                            text: "FLATPAK"
                            tint: Theme.info
                        }
                        Badge {
                            visible: modelData.protected
                            text: "SYSTEM"
                            tint: Theme.textMuted
                        }
                    }
                    Label {
                        text: modelData.description
                        font.pixelSize: 11
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                Label {
                    text: modelData.size
                    font.pixelSize: 11
                    color: Theme.textMuted
                }
                OutlineActionButton {
                    visible: !modelData.protected
                    text: "REMOVE"
                    tint: Theme.warn
                    implicitHeight: 30
                    enabled: !bridge.running
                    onClicked: page.confirmDialog.openWith(
                        "Uninstall " + modelData.name,
                        "remove " + modelData.name,
                        function() { bridge.removeSelected([modelData.name]) })
                }
            }
            HoverHandler { id: hoverArea }
        }
    }
}

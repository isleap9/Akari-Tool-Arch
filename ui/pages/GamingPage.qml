import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    property var confirmDialog: null
    spacing: 0

    // name -> true for user-checked packages (missing ones start checked)
    property var selection: ({})
    property int missingCount: 0
    property int selectedCount: countSelected()

    readonly property var groupNames: ({
        core:  "Core — launchers, wine & tools",
        deps:  "Dependencies — 32-bit libs & codecs",
        fonts: "Fonts",
        gpu:   "GPU drivers (detected)",
        aur:   "Optional extras (AUR)"
    })

    function rebuildSelection() {
        var sel = {}, missing = 0
        for (var i = 0; i < bridge.packages.length; i++) {
            var p = bridge.packages[i]
            if (!p.installed) {
                sel[p.name] = true
                missing++
            }
        }
        selection = sel
        missingCount = missing
    }

    function countSelected() {
        var n = 0
        for (var k in selection) if (selection[k]) n++
        return n
    }

    function selectedNames() {
        var names = []
        for (var k in selection) if (selection[k]) names.push(k)
        return names
    }

    function selectionHasAur(names) {
        for (var i = 0; i < bridge.packages.length; i++) {
            var p = bridge.packages[i]
            if (p.group === "aur" && names.indexOf(p.name) !== -1)
                return true
        }
        return false
    }

    Component.onCompleted: bridge.refreshPackages()
    Connections {
        target: bridge
        function onPackagesChanged() { page.rebuildSelection() }
    }

    // ---- header row -----------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 10
        spacing: 12

        Label {
            text: bridge.packages.length === 0 ? "Loading package list…"
                : page.missingCount === 0     ? "Everything installed — " + bridge.packages.length + " packages present"
                : page.missingCount + " of " + bridge.packages.length + " packages missing"
            color: Theme.textSecondary
            font.pixelSize: 13
        }
        Item { Layout.fillWidth: true }
        Button {
            text: "Refresh"
            flat: true
            enabled: !bridge.running
            onClicked: bridge.refreshPackages()
        }
        Button {
            text: page.selectedCount > 0
                  ? "Install selected (" + page.selectedCount + ")"
                  : "Nothing selected"
            highlighted: true
            enabled: !bridge.running && page.selectedCount > 0
            onClicked: {
                var names = page.selectedNames()
                var hasAur = page.selectionHasAur(names)
                page.confirmDialog.openWithText(
                    "Install " + names.length + " package" + (names.length > 1 ? "s" : "")
                        + (hasAur ? " (opens a terminal — AUR builds are interactive)" : ""),
                    "Will install:\n  " + names.join("\n  "),
                    function() {
                        if (hasAur) {
                            if (!bridge.runInTerminal(
                                    ["apply", "selected"].concat(names)))
                                bridge.installSelected(names)
                        } else {
                            bridge.installSelected(names)
                        }
                    })
            }
        }
    }

    // ---- package list -----------------------------------------------------
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        clip: true
        spacing: 2
        model: bridge.packages

        section.property: "group"
        section.criteria: ViewSection.FullString
        section.delegate: Label {
            required property string section
            text: page.groupNames[section] || section
            font.pixelSize: 11
            font.letterSpacing: 1.2
            font.bold: true
            color: Theme.textMuted
            topPadding: 16
            bottomPadding: 6
        }

        delegate: Rectangle {
            required property var modelData
            width: list.width
            height: 40
            radius: 6
            color: hoverArea.hovered ? Theme.navHover : Theme.surface

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                CheckBox {
                    checked: modelData.installed || (page.selection[modelData.name] === true)
                    enabled: !modelData.installed && !bridge.running
                    onToggled: {
                        var sel = page.selection
                        sel[modelData.name] = checked
                        page.selection = sel      // reassign to trigger bindings
                        page.selectedCount = page.countSelected()
                    }
                }
                Label {
                    text: modelData.name
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: modelData.installed ? Theme.textMuted : Theme.textPrimary
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: modelData.installed ? "installed" : "missing"
                    font.pixelSize: 11
                    color: modelData.installed ? Theme.ok : Theme.warn
                }
            }
            HoverHandler { id: hoverArea }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: root
    width: 1100
    height: 720
    visible: true
    title: "Akari Tool Linux"

    Material.theme: Material.Dark
    Material.accent: "#E53935"          // Akari red
    Material.primary: "#E53935"
    Material.background: "#111113"

    // ---- state pushed in from Python (Bridge) --------------------------
    // bridge.status: { key: {state, detail} }}
    // bridge.running: bool, bridge.logText: string

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ================= Sidebar =================
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            color: "#0C0C0E"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                // Brand
                RowLayout {
                    Layout.bottomMargin: 18
                    Layout.topMargin: 6
                    spacing: 8
                    Rectangle {
                        width: 22; height: 22; radius: 4
                        color: Material.accent
                        Label {
                            anchors.centerIn: parent
                            text: "A"; font.bold: true; color: "white"
                        }
                    }
                    Label {
                        text: "AKARI TOOL"
                        font.letterSpacing: 2
                        font.pixelSize: 12
                        font.bold: true
                        color: "#EDEDED"
                    }
                }

                Label { text: "SETUP"; font.pixelSize: 10; font.letterSpacing: 1.5; color: "#666"; Layout.topMargin: 6 }
                NavItem { label: "Overview"; glyph: "\u2302"; selected: true }
                NavItem { label: "Gaming"; glyph: "\u25B6" }
                NavItem { label: "GPU Drivers"; glyph: "\u25A6" }

                Label { text: "OPTIMIZE"; font.pixelSize: 10; font.letterSpacing: 1.5; color: "#666"; Layout.topMargin: 10 }
                NavItem { label: "Tweaks"; glyph: "\u2699" }

                Label { text: "ADVANCED"; font.pixelSize: 10; font.letterSpacing: 1.5; color: "#666"; Layout.topMargin: 10 }
                NavItem { label: "Change Log"; glyph: "\u2630" }

                Item { Layout.fillHeight: true }

                Label {
                    text: "v0.1 · bash backend"
                    font.pixelSize: 10; color: "#555"
                    Layout.bottomMargin: 4
                }
            }
        }

        // ================= Content =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Header
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 28
                Layout.bottomMargin: 12
                spacing: 4
                Label { text: "Akari Tool"; font.pixelSize: 28; font.bold: true }
                Label {
                    text: "Gaming setup for vanilla Arch — dependencies, drivers & tweaks"
                    color: "#9A9A9A"; font.pixelSize: 13
                }
            }

            // Card grid  <-> log view (swap while running)
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: bridge.running || bridge.logText.length > 0 ? 1 : 0

                // ---- page 0: status cards ----
                Flickable {
                    contentHeight: grid.height + 56
                    clip: true

                    GridLayout {
                        id: grid
                        columns: width > 1400 ? 3 : width > 760 ? 2 : 1
                        columnSpacing: 14
                        rowSpacing: 14
                        uniformCellHeights: true
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 28
                        anchors.topMargin: 8

                        StatusCard {
                            title: "System Check"
                            subtitle: statusDetail("multilib")
                            state_: statusState("multilib")
                            actionText: statusState("multilib") === "warn" ? "Enable multilib" : ""
                            onAction: bridge.run("apply", "multilib")
                        }
                        StatusCard {
                            title: "Gaming Packages"
                            subtitle: statusDetail("gaming")
                            state_: statusState("gaming")
                            actionText: "Set up gaming"
                            onAction: bridge.run("apply", "gaming")
                        }
                        StatusCard {
                            title: "GPU Drivers"
                            subtitle: gpuSummary()
                            state_: gpuState()
                            actionText: ""
                        }
                        StatusCard {
                            title: "Performance Tweaks"
                            subtitle: statusDetail("tweaks")
                            state_: statusState("tweaks")
                            actionText: statusState("tweaks") === "warn" ? "Apply tweaks" : ""
                            onAction: bridge.run("apply", "tweaks")
                        }
                        StatusCard {
                            title: "AUR Extras"
                            subtitle: statusDetail("aur")
                            state_: statusState("aur")
                            actionText: ""
                        }
                        StatusCard {
                            title: "Network"
                            subtitle: statusDetail("network")
                            state_: statusState("network")
                            actionText: ""
                        }
                    }
                }

                // ---- page 1: live log ----
                ColumnLayout {
                    spacing: 0
                    Flickable {
                        id: logFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 28
                        Layout.topMargin: 8
                        contentHeight: logLabel.height
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            color: "#0A0A0C"; radius: 8; z: -1
                        }
                        TextArea {
                            id: logLabel
                            width: logFlick.width
                            readOnly: true
                            wrapMode: TextArea.Wrap
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: "#C8C8C8"
                            text: bridge.logText
                            background: null
                            onTextChanged: logFlick.contentY =
                            Math.max(0, contentHeight - logFlick.height)
                        }
                    }
                    RowLayout {
                        Layout.margins: 28
                        Layout.topMargin: 8
                        BusyIndicator { running: bridge.running; visible: bridge.running; implicitHeight: 28 }
                        Label {
                            text: bridge.running ? "Running…" : "Finished."
                            color: "#9A9A9A"
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            text: "Back to overview"
                            enabled: !bridge.running
                            onClicked: { bridge.clearLog(); bridge.run("check", "") }
                        }
                    }
                }
            }

            // Footer / status bar
            Rectangle {
                Layout.fillWidth: true
                height: 30
                color: "#0C0C0E"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: bridge.running ? "#FFB300" : "#43A047"
                    }
                    Label {
                        text: bridge.running ? "Working" : "Ready"
                        font.pixelSize: 11; color: "#9A9A9A"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: "PySide6 · QML Material"
                        font.pixelSize: 11; color: "#555"
                    }
                }
            }
        }
    }

    // ---- helpers reading bridge.status --------------------------------
    function statusState(key)
    {
        var s = bridge.status[key]
        return s ? s.state : "unknown"
    }
    function statusDetail(key)
    {
        var s = bridge.status[key]
        return s ? s.detail : "Checking…"
    }
    function gpuState()
    {
        var k
        for (k in bridge.status)
            if (k.indexOf("gpu_") === 0 && bridge.status[k].state !== "ok")
                return "warn"
            for (k in bridge.status)
                if (k.indexOf("gpu_") === 0)
                    return "ok"
                return "unknown"
            }
            function gpuSummary()
            {
                var parts = []
                for (var k in bridge.status)
                    if (k.indexOf("gpu_") === 0)
                        parts.push(bridge.status[k].detail)
                    return parts.length ? parts.join(" · ") : "Detecting…"
                }

                // ---- inline components ---------------------------------------------
                component NavItem: ItemDelegate {
                id: nav
                property string glyph: ""
                    property string label: ""
                        property bool selected: false
                            Layout.fillWidth: true
                            height: 36

                            contentItem: RowLayout {
                                spacing: 10
                                Rectangle {
                                    width: 3; height: 18; radius: 1.5
                                    color: nav.selected ? Material.accent : "transparent"
                                }
                                Label { text: nav.glyph; color: nav.selected ? "#EDEDED" : "#888" }
                                Label {
                                    text: nav.label
                                    color: nav.selected ? "#EDEDED" : "#999"
                                    font.pixelSize: 13
                                }
                                Item { Layout.fillWidth: true }
                            }
                            background: Rectangle {
                                radius: 6
                                color: nav.selected ? "#1B1B1F" : (nav.hovered ? "#161619" : "transparent")
                            }
                        }

                        component StatusCard: Pane {
                        id: card
                        property string title: ""
                            property string subtitle: ""
                                property string state_: "unknown"   // ok | warn | fail | unknown
                                    property string actionText: ""
                                        signal action()

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 130
                                        Material.elevation: 2
                                        Material.background: "#18181B"
                                        padding: 18

                                        contentItem: ColumnLayout {
                                            spacing: 10
                                            RowLayout {
                                                spacing: 10
                                                Rectangle {   // status chip
                                                    width: 10; height: 10; radius: 5
                                                    color: card.state_ === "ok" ? "#43A047"
                                                    : card.state_ === "warn" ? "#FFB300"
                                                    : card.state_ === "fail" ? "#E53935" : "#555"
                                                }
                                                Label { text: card.title; font.bold: true; font.pixelSize: 15 }
                                                Item { Layout.fillWidth: true }
                                            }
                                            Label {
                                                text: card.subtitle
                                                color: "#9A9A9A"; font.pixelSize: 12
                                                wrapMode: Text.Wrap
                                                Layout.fillWidth: true
                                            }
                                            Button {
                                                visible: card.actionText.length > 0
                                                text: card.actionText
                                                highlighted: true
                                                enabled: !bridge.running
                                                onClicked: card.action()
                                            }
                                            Item { Layout.fillHeight: true }   // pins content to the top
                                            }
                                        }
                                    }

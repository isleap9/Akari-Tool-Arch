import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components
import "pages"

ApplicationWindow {
    id: root
    width: 1100
    height: 720
    visible: true
    title: "Akari Tool Linux"

    Material.theme: Material.Dark
    Material.accent: Theme.accent
    Material.primary: Theme.accent
    Material.background: Theme.background

    // Navigation. The live log overrides pages only while an APPLY runs
    // (plan/list fetches don't hijack the view).
    property int currentPage: 0   // 0 Overview, 1 Gaming, 2 Kernel, 3 Change Log
    readonly property bool showLog: bridge.applying || bridge.logText.length > 0

    ConfirmDialog {
        id: confirmDlg
        parent: Overlay.overlay
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ================= Sidebar =================
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            color: Theme.surfaceAlt

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 4

                RowLayout {
                    Layout.bottomMargin: 18
                    Layout.topMargin: 6
                    spacing: 8
                    Rectangle {
                        width: 22; height: 22; radius: 4
                        color: Theme.accent
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
                        color: Theme.textPrimary
                    }
                }

                SectionLabel { text: "SETUP"; Layout.topMargin: 6 }
                NavItem {
                    label: "Overview"; glyph: "\u2302"
                    selected: root.currentPage === 0 && !root.showLog
                    onNavigate: root.currentPage = 0
                }
                NavItem {
                    label: "Gaming"; glyph: "\u25B6"
                    selected: root.currentPage === 1 && !root.showLog
                    onNavigate: root.currentPage = 1
                }

                SectionLabel { text: "OPTIMIZE" }
                NavItem {
                    label: "Kernel"; glyph: "\u2699"
                    selected: root.currentPage === 2 && !root.showLog
                    onNavigate: root.currentPage = 2
                }

                SectionLabel { text: "ADVANCED" }
                NavItem {
                    label: "Change Log"; glyph: "\u2630"
                    selected: root.currentPage === 3 && !root.showLog
                    onNavigate: root.currentPage = 3
                }

                Item { Layout.fillHeight: true }

                Label {
                    text: "v0.1 · bash backend"
                    font.pixelSize: 10; color: Theme.textFaint
                    Layout.bottomMargin: 4
                }
            }
        }

        // ================= Content =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.pagePadding
                Layout.bottomMargin: 12
                spacing: 4
                Label {
                    text: root.showLog ? "Running" :
                          root.currentPage === 1 ? "Gaming Packages" :
                          root.currentPage === 2 ? "Kernel" :
                          root.currentPage === 3 ? "Change Log" : "Akari Tool"
                    font.pixelSize: 28; font.bold: true
                }
                Label {
                    text: root.showLog ? "Live output from the backend" :
                          root.currentPage === 1
                          ? "Pick exactly what gets installed — missing packages are pre-selected"
                          : root.currentPage === 2
                          ? "Install an alternative kernel for gaming or stability"
                          : root.currentPage === 3
                          ? "A record of everything this tool changed"
                          : "Gaming setup for vanilla Arch — dependencies, drivers & tweaks"
                    color: Theme.textSecondary; font.pixelSize: 13
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.showLog ? 4 : root.currentPage

                OverviewPage  { confirmDialog: confirmDlg }
                GamingPage    { confirmDialog: confirmDlg }
                KernelPage    { confirmDialog: confirmDlg }
                ChangeLogPage {}

                LogPage {
                    onBackRequested: bridge.clearLog()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 30
                color: Theme.surfaceAlt
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: bridge.running ? Theme.warn : Theme.ok
                    }
                    Label {
                        text: bridge.running ? "Working" : "Ready"
                        font.pixelSize: 11; color: Theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: "PySide6 · QML Material"
                        font.pixelSize: 11; color: Theme.textFaint
                    }
                }
            }
        }
    }
}

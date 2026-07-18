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
                    Image {
                        source: "resources/AkariMark.png"
                        sourceSize.width: 26
                        sourceSize.height: 26
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        fillMode: Image.PreserveAspectFit
                        smooth: true
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
                NavItem {
                    label: "Launch Options"; glyph: "\u2318"
                    selected: root.currentPage === 2 && !root.showLog
                    onNavigate: root.currentPage = 2
                }
                NavItem {
                    label: "Apps"; glyph: "\u25A6"
                    selected: root.currentPage === 3 && !root.showLog
                    onNavigate: root.currentPage = 3
                }

                SectionLabel { text: "OPTIMIZE" }
                NavItem {
                    label: "Kernel"; glyph: "\u2699"
                    selected: root.currentPage === 4 && !root.showLog
                    onNavigate: root.currentPage = 4
                }
                NavItem {
                    label: "Maintenance"; glyph: "\u2692"
                    selected: root.currentPage === 5 && !root.showLog
                    onNavigate: root.currentPage = 5
                }

                SectionLabel { text: "HEALTH" }
                NavItem {
                    label: "Diagnose"; glyph: "\u2695"
                    selected: root.currentPage === 6 && !root.showLog
                    onNavigate: root.currentPage = 6
                }

                SectionLabel { text: "ADVANCED" }
                NavItem {
                    label: "Restore"; glyph: "\u21BA"
                    selected: root.currentPage === 7 && !root.showLog
                    onNavigate: root.currentPage = 7
                }
                NavItem {
                    label: "Change Log"; glyph: "\u2630"
                    selected: root.currentPage === 8 && !root.showLog
                    onNavigate: root.currentPage = 8
                }

                Item { Layout.fillHeight: true }

                Label {
                    text: "v0.2 · bash backend"
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
                          root.currentPage === 2 ? "Launch Options" :
                          root.currentPage === 3 ? "Apps" :
                          root.currentPage === 4 ? "Kernel" :
                          root.currentPage === 5 ? "Maintenance" :
                          root.currentPage === 6 ? "Diagnose" :
                          root.currentPage === 7 ? "Restore" :
                          root.currentPage === 8 ? "Change Log" : "Akari Tool"
                    font.pixelSize: 28; font.bold: true
                }
                Label {
                    text: root.showLog ? "Live output from the backend" :
                          root.currentPage === 1
                          ? "Pick exactly what gets installed — missing packages are pre-selected"
                          : root.currentPage === 2
                          ? "Build a Steam launch options string from toggles"
                          : root.currentPage === 3
                          ? "Everything installed on this machine — search & uninstall"
                          : root.currentPage === 4
                          ? "Install an alternative kernel for gaming or stability"
                          : root.currentPage === 5
                          ? "One-click upkeep — AUR helper, mirrors & cleanup"
                          : root.currentPage === 6
                          ? "Functional tests of the gaming stack"
                          : root.currentPage === 7
                          ? "Undo changes — restore backed-up config files"
                          : root.currentPage === 8
                          ? "A record of everything this tool changed"
                          : "Gaming setup for vanilla Arch — dependencies, drivers & tweaks"
                    color: Theme.textSecondary; font.pixelSize: 13
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.showLog ? 9 : root.currentPage

                OverviewPage      { confirmDialog: confirmDlg }
                GamingPage        { confirmDialog: confirmDlg }
                LaunchOptionsPage { confirmDialog: confirmDlg }
                AppsPage          { confirmDialog: confirmDlg }
                KernelPage        { confirmDialog: confirmDlg }
                MaintenancePage   { confirmDialog: confirmDlg }
                DiagnosePage      {}
                RestorePage       { confirmDialog: confirmDlg }
                ChangeLogPage     {}

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

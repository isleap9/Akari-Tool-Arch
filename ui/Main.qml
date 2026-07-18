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
    color: Theme.background

    // Navigation. The live log overrides pages only while an APPLY runs
    // (plan/list fetches don't hijack the view).
    property int currentPage: 0
    readonly property bool showLog: bridge.applying || bridge.logText.length > 0

    readonly property var pageTitles: [
        "Overview", "Gaming Packages", "Launch Options", "Apps",
        "Kernel", "Maintenance", "Diagnose", "Restore", "Change Log"
    ]
    readonly property var pageSubtitles: [
        "Gaming setup for vanilla Arch — dependencies, drivers & tweaks",
        "Pick exactly what gets installed — missing packages are pre-selected",
        "Build a Steam launch options string from toggles",
        "Everything installed on this machine — search & uninstall",
        "Install an alternative kernel for gaming or stability",
        "One-click upkeep — AUR helper, mirrors & cleanup",
        "Functional tests of the gaming stack",
        "Undo changes — restore backed-up config files",
        "A record of everything this tool changed"
    ]

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

            // hairline separating sidebar from content
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.border
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 2

                RowLayout {
                    Layout.bottomMargin: 16
                    Layout.topMargin: 8
                    Layout.leftMargin: 4
                    spacing: 10
                    Image {
                        source: "resources/AkariMark.png"
                        sourceSize.width: 26
                        sourceSize.height: 26
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    ColumnLayout {
                        spacing: 0
                        Label {
                            text: "AKARI"
                            font.letterSpacing: 3
                            font.pixelSize: 13
                            font.bold: true
                            color: Theme.textPrimary
                        }
                        Label {
                            text: "TOOL FOR ARCH"
                            font.letterSpacing: 2
                            font.pixelSize: 8
                            color: Theme.textFaint
                        }
                    }
                }

                SectionLabel { text: "SETUP"; Layout.topMargin: 4 }
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
                    text: "v0.3 · bash backend"
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textFaint
                    Layout.bottomMargin: 4
                    Layout.leftMargin: 10
                }
            }
        }

        // ================= Content =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ---- page header ----
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.pagePadding
                Layout.rightMargin: Theme.pagePadding
                Layout.topMargin: 14
                Layout.bottomMargin: 10
                spacing: 12

                Rectangle {   // accent tick anchoring the title
                    width: 3
                    Layout.preferredHeight: 30
                    radius: 1.5
                    color: Theme.accent
                }
                ColumnLayout {
                    spacing: 1
                    Label {
                        id: pageTitle
                        text: root.showLog ? "Running" : root.pageTitles[root.currentPage]
                        font.pixelSize: Theme.fsTitle
                        font.bold: true
                        color: Theme.textPrimary
                        opacity: 1
                        Behavior on text {
                            SequentialAnimation {
                                NumberAnimation { target: pageTitle; property: "opacity"; to: 0; duration: 60 }
                                PropertyAction {}
                                NumberAnimation { target: pageTitle; property: "opacity"; to: 1; duration: Theme.animMed }
                            }
                        }
                    }
                    Label {
                        text: root.showLog ? "Live output from the backend"
                                           : root.pageSubtitles[root.currentPage]
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fsCaption
                    }
                }
                Item { Layout.fillWidth: true }
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

            // ---- status footer ----
            Rectangle {
                Layout.fillWidth: true
                height: 32
                color: Theme.surfaceAlt
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8
                    Rectangle {
                        id: statusDot
                        width: 8; height: 8; radius: 4
                        color: bridge.running ? Theme.warn : Theme.ok
                        SequentialAnimation on opacity {
                            running: bridge.running
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                        }
                    }
                    Label {
                        text: bridge.running ? "Working" : "Ready"
                        font.pixelSize: 11
                        color: Theme.textSecondary
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: "PySide6 · QML Material"
                        font.pixelSize: 11
                        color: Theme.textFaint
                    }
                }
            }
        }
    }
}

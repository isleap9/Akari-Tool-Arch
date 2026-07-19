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

    // header HUD chip data
    readonly property int readinessPct: {
        var ok = 0, total = 0
        for (var k in bridge.status) {
            var st = bridge.status[k].state
            if (st === "unknown") continue
            total++
            if (st === "ok" || st === "info") ok++
        }
        return total === 0 ? -1 : Math.round(100 * ok / total)
    }
    // Discrete GPU first (nvidia > amd > intel). QVariantMap iterates keys
    // alphabetically, so a plain for..in would show an AMD iGPU (gpu_amd)
    // ahead of an NVIDIA dGPU (gpu_nvidia).
    readonly property string gpuShort: {
        var order = ["gpu_nvidia", "gpu_amd", "gpu_intel"]
        for (var i = 0; i < order.length; i++) {
            var s = bridge.status[order[i]]
            if (s) {
                var d = s.detail || ""
                return d.split("—")[0].trim().split(" ").slice(0, 3).join(" ")
            }
        }
        return ""
    }
    readonly property string kernelShort: {
        for (var i = 0; i < bridge.kernels.length; i++)
            if (bridge.kernels[i].running) return bridge.kernels[i].name
        return ""
    }

    function readiness() {
        var ok = 0, total = 0
        for (var k in bridge.status) {
            var st = bridge.status[k].state
            if (st === "unknown") continue
            total++
            if (st === "ok" || st === "info") ok++
        }
        return total === 0 ? -1 : Math.round(100 * ok / total)
    }

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

    Component.onCompleted: bridge.refreshKernels()

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
            Layout.preferredWidth: 236
            color: Theme.surfaceAlt

            // hairline separating sidebar from content
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Theme.borderSubtle
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 2

                RowLayout {
                    Layout.bottomMargin: 20
                    Layout.topMargin: 8
                    Layout.leftMargin: 6
                    spacing: 11
                    Image {
                        source: "resources/AkariMark.png"
                        sourceSize.width: 30
                        sourceSize.height: 30
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    ColumnLayout {
                        spacing: 2
                        Label {
                            text: "AKARI"
                            font.family: Theme.hudFont
                            font.letterSpacing: 4
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: Theme.textPrimary
                        }
                        Label {
                            text: "TOOL · FOR ARCH"
                            font.family: Theme.monoFont
                            font.letterSpacing: 2.5
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

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    height: 1
                    color: "#1A1A1E"
                }
                Label {
                    text: "v0.3 · bash backend"
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textFaint
                    Layout.topMargin: 10
                    Layout.bottomMargin: 2
                    Layout.leftMargin: 10
                }
            }
        }

        // ================= Content =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ---- page header / top HUD strip ----
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + 32
                color: "transparent"
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: "#1A1A1E"
                }
                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.pagePadding
                    anchors.rightMargin: Theme.pagePadding
                    anchors.topMargin: 18
                    anchors.bottomMargin: 14
                    spacing: 14

                    Rectangle {   // accent tick
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 40
                        radius: 2
                        color: Theme.accent
                    }
                    ColumnLayout {
                        spacing: 2
                        Label {
                            id: pageTitle
                            text: root.showLog ? "Running" : root.pageTitles[root.currentPage]
                            font.family: Theme.hudFont
                            font.pixelSize: Theme.fsPageTitle
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                            color: Theme.textPrimary
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
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsBody
                        }
                    }
                    Item { Layout.fillWidth: true }

                    // HUD chips: READY % · GPU · KERNEL
                    RowLayout {
                        spacing: 8
                        Rectangle {   // READY chip
                            implicitWidth: readyRow.implicitWidth + 24
                            implicitHeight: 30
                            radius: 7
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                            RowLayout {
                                id: readyRow
                                anchors.centerIn: parent
                                spacing: 7
                                Item {
                                    width: 7; height: 7
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 15; height: 15; radius: 7.5
                                        color: Qt.alpha(bridge.running ? Theme.warn : Theme.ok, 0.25)
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 7; height: 7; radius: 3.5
                                        color: bridge.running ? Theme.warn : Theme.ok
                                        SequentialAnimation on opacity {
                                            running: bridge.running
                                            loops: Animation.Infinite
                                            alwaysRunToEnd: true
                                            NumberAnimation { to: 0.35; duration: 500 }
                                            NumberAnimation { to: 1.0;  duration: 500 }
                                        }
                                    }
                                }
                                Label {
                                    text: bridge.running ? "WORKING" : "READY"
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsLabel
                                    color: Theme.textSecondary
                                }
                                Label {
                                    visible: root.readinessPct >= 0
                                    text: root.readinessPct + "%"
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsLabel
                                    font.weight: Font.Bold
                                    color: Theme.textPrimary
                                }
                            }
                        }
                        Rectangle {   // GPU chip
                            visible: root.gpuShort.length > 0
                            implicitWidth: gpuRow.implicitWidth + 24
                            implicitHeight: 30
                            radius: 7
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                            RowLayout {
                                id: gpuRow
                                anchors.centerIn: parent
                                spacing: 6
                                Label {
                                    text: "GPU"
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsLabel
                                    color: Theme.textSecondary
                                }
                                Label {
                                    text: root.gpuShort
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsLabel
                                    color: Theme.textPrimary
                                }
                            }
                        }
                        Rectangle {   // KERNEL chip
                            visible: root.kernelShort.length > 0
                            implicitWidth: kRow.implicitWidth + 24
                            implicitHeight: 30
                            radius: 7
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                            RowLayout {
                                id: kRow
                                anchors.centerIn: parent
                                spacing: 6
                                Label {
                                    text: "KERNEL"
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsLabel
                                    color: Theme.textSecondary
                                }
                                Label {
                                    text: root.kernelShort
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsLabel
                                    color: Theme.textPrimary
                                }
                            }
                        }
                    }
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

        }
    }
}

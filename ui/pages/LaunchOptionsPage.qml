import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

Flickable {
    id: page
    contentHeight: col.height + 56
    clip: true

    property var confirmDialog: null

    Component.onCompleted: bridge.refreshSteamGames()

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pagePadding
        anchors.topMargin: 8
        spacing: 14

        Label {
            Layout.fillWidth: true
            text: "Compose a launch options string for a game, then paste it in " +
                  "Steam: right-click a game → Properties → Launch Options."
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }

        // ---- result ------------------------------------------------------
        Pane {
            Layout.fillWidth: true
            Material.elevation: 1
            Material.background: Theme.surfaceLog
            padding: 14

            contentItem: RowLayout {
                spacing: 12
                TextArea {
                    id: result
                    Layout.fillWidth: true
                    readOnly: true
                    wrapMode: TextArea.Wrap
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: Theme.textPrimary
                    background: null
                    text: page.buildString()
                }
                Button {
                    text: "Copy"
                    highlighted: true
                    Material.elevation: 0
                    implicitHeight: 36
                    onClicked: {
                        result.selectAll()
                        result.copy()
                        result.deselect()
                        text = "Copied!"
                        copyReset.restart()
                    }
                    Timer {
                        id: copyReset
                        interval: 1500
                        onTriggered: parent.text = "Copy"
                    }
                }
            }
        }

        // ---- toggles -----------------------------------------------------
        Pane {
            Layout.fillWidth: true
            Material.elevation: 1
            Material.background: Theme.surface
            padding: 16

            contentItem: ColumnLayout {
                spacing: 2

                Switch {
                    id: swGamemode
                    text: "GameMode — CPU governor & priority while playing"
                    checked: true
                }
                Switch {
                    id: swMangohud
                    text: "MangoHud — FPS / frametime overlay"
                    checked: true
                }
                Switch {
                    id: swWayland
                    text: "Proton Wayland — native Wayland (better for Hyprland, experimental)"
                }
                Switch {
                    id: swGamescope
                    text: "Gamescope — run in a micro-compositor session"
                }

                // gamescope sub-options
                GridLayout {
                    visible: swGamescope.checked
                    columns: 2
                    columnSpacing: 12
                    Layout.leftMargin: 52
                    Layout.topMargin: 4

                    Label { text: "Resolution"; color: Theme.textSecondary; font.pixelSize: 12 }
                    RowLayout {
                        TextField {
                            id: gsW; placeholderText: "2560"; text: "2560"
                            validator: IntValidator { bottom: 1 }
                            Layout.preferredWidth: 84
                        }
                        Label { text: "×"; color: Theme.textSecondary }
                        TextField {
                            id: gsH; placeholderText: "1440"; text: "1440"
                            validator: IntValidator { bottom: 1 }
                            Layout.preferredWidth: 84
                        }
                    }
                    Label { text: "FPS limit"; color: Theme.textSecondary; font.pixelSize: 12 }
                    TextField {
                        id: gsFps; placeholderText: "e.g. 144"
                        validator: IntValidator { bottom: 1 }
                        Layout.preferredWidth: 84
                    }
                    Label { text: "Fullscreen"; color: Theme.textSecondary; font.pixelSize: 12 }
                    CheckBox { id: gsFull; checked: true }
                }
            }
        }

        // ---- apply directly to a Steam game ------------------------------
        Pane {
            Layout.fillWidth: true
            Material.elevation: 1
            Material.background: Theme.surface
            padding: 16

            contentItem: ColumnLayout {
                spacing: 10

                Label {
                    text: "Apply to a Steam game"
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    visible: bridge.steamGames.length === 0
                    text: "No Steam library found (or Steam isn't set up yet). " +
                          "You can still copy the string above and paste it manually."
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    visible: bridge.steamGames.length > 0
                    spacing: 12
                    Layout.fillWidth: true

                    ComboBox {
                        id: gamePicker
                        Layout.fillWidth: true
                        model: bridge.steamGames
                        textRole: "name"
                    }
                    Button {
                        text: "Apply"
                        highlighted: true
                        Material.elevation: 0
                        enabled: gamePicker.currentIndex >= 0 && !bridge.running
                        onClicked: {
                            var game = bridge.steamGames[gamePicker.currentIndex]
                            var opts = page.buildString()
                            page.confirmDialog.openWithText(
                                "Set launch options — " + game.name,
                                "Steam must be closed (it overwrites this file on exit).\n\n" +
                                "New launch options:\n  " + opts +
                                (game.launchOptions.length > 0
                                    ? "\n\nReplaces current:\n  " + game.launchOptions
                                    : "\n\n(no launch options currently set)") +
                                "\n\nA backup of localconfig.vdf is kept and " +
                                "listed under Restore.",
                                function() { bridge.applyLaunchOptions(game.appid, opts) })
                        }
                    }
                }
                Label {
                    visible: bridge.steamGames.length > 0 && gamePicker.currentIndex >= 0
                             && bridge.steamGames[gamePicker.currentIndex].launchOptions.length > 0
                    Layout.fillWidth: true
                    text: "Current: " + (gamePicker.currentIndex >= 0
                              ? bridge.steamGames[gamePicker.currentIndex].launchOptions : "")
                    color: Theme.textMuted
                    font.family: "monospace"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: "Order matters: environment variables first, wrappers next, " +
                  "%command% is the game itself. Lutris/Heroic have equivalent " +
                  "fields per game."
            color: Theme.textMuted
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }

    function buildString() {
        var env = []
        var wrap = []

        if (swWayland.checked) env.push("PROTON_ENABLE_WAYLAND=1")
        if (swGamemode.checked) wrap.push("gamemoderun")
        if (swMangohud.checked) wrap.push("mangohud")
        if (swGamescope.checked) {
            var gs = "gamescope"
            if (gsW.text.length > 0 && gsH.text.length > 0)
                gs += " -W " + gsW.text + " -H " + gsH.text
            if (gsFps.text.length > 0)
                gs += " -r " + gsFps.text
            if (gsFull.checked) gs += " -f"
            gs += " --"
            wrap.push(gs)
        }

        var parts = env.concat(wrap)
        parts.push("%command%")
        return parts.join(" ")
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

// Launch Options — mock layout: 2-col [1.35fr | 1fr]
//   left:  LAUNCH STRING card (gradient) + toggle card
//   right: APPLY TO A STEAM GAME card with per-game rows
Flickable {
    id: page
    contentHeight: grid.height + 56
    clip: true

    property var confirmDialog: null

    Component.onCompleted: bridge.refreshSteamGames()

    GridLayout {
        id: grid
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pagePadding
        anchors.topMargin: 4
        columns: width > 680 ? 2 : 1
        columnSpacing: 16
        rowSpacing: 16

        // ================= LEFT COLUMN =================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 135   // 1.35fr
            Layout.alignment: Qt.AlignTop
            spacing: 14

            // ---- launch string card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: stringCol.implicitHeight + 36
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    id: stringCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 10

                    Label {
                        text: "LAUNCH STRING"
                        font.family: Theme.hudFont
                        font.pixelSize: Theme.fsLabel
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.hudLetterSpacing
                        color: Theme.accent
                    }
                    RowLayout {
                        spacing: 12
                        Layout.fillWidth: true
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: result.implicitHeight + 24
                            radius: Theme.rowRadius
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: Theme.border
                            TextEdit {
                                id: result
                                anchors.fill: parent
                                anchors.margins: 12
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                readOnly: true
                                wrapMode: TextEdit.WrapAnywhere
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fsBody
                                color: Theme.textPrimary
                                selectByMouse: true
                                text: page.buildString()
                            }
                        }
                        PrimaryButton {
                            id: copyBtn
                            text: "COPY"
                            onClicked: {
                                result.selectAll()
                                result.copy()
                                result.deselect()
                                text = "COPIED!"
                                copyReset.restart()
                            }
                            Timer {
                                id: copyReset
                                interval: 1500
                                onTriggered: copyBtn.text = "COPY"
                            }
                        }
                    }
                    Label {
                        text: "Steam → right-click game → Properties → Launch Options"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textMuted
                    }
                }
            }

            // ---- toggles card ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: togglesCol.implicitHeight + 16
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    id: togglesCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 0

                    HudSwitch {
                        id: swGamemode
                        Layout.fillWidth: true
                        padding: 14
                        title: "GameMode"
                        description: "CPU governor & priority while playing"
                        checked: true
                    }
                    HudSwitch {
                        id: swMangohud
                        Layout.fillWidth: true
                        padding: 14
                        title: "MangoHud"
                        description: "FPS / frametime overlay"
                        checked: true
                    }
                    HudSwitch {
                        id: swWayland
                        Layout.fillWidth: true
                        padding: 14
                        title: "Proton Wayland"
                        description: "Native Wayland — better for Hyprland, experimental"
                    }
                    HudSwitch {
                        id: swGamescope
                        Layout.fillWidth: true
                        padding: 14
                        title: "Gamescope"
                        description: "Run in a micro-compositor session"
                    }

                    // gamescope sub-options
                    GridLayout {
                        visible: swGamescope.checked
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 8
                        Layout.leftMargin: 68
                        Layout.bottomMargin: 12

                        Label {
                            text: "Resolution"
                            color: Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                        }
                        RowLayout {
                            TextField {
                                id: gsW; placeholderText: "2560"; text: "2560"
                                font.family: Theme.monoFont
                                validator: IntValidator { bottom: 1 }
                                Layout.preferredWidth: 84
                            }
                            Label { text: "×"; color: Theme.textSecondary }
                            TextField {
                                id: gsH; placeholderText: "1440"; text: "1440"
                                font.family: Theme.monoFont
                                validator: IntValidator { bottom: 1 }
                                Layout.preferredWidth: 84
                            }
                        }
                        Label {
                            text: "FPS limit"
                            color: Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                        }
                        TextField {
                            id: gsFps; placeholderText: "e.g. 144"
                            font.family: Theme.monoFont
                            validator: IntValidator { bottom: 1 }
                            Layout.preferredWidth: 84
                        }
                        Label {
                            text: "Fullscreen"
                            color: Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                        }
                        CheckBox { id: gsFull; checked: true }
                    }
                }
            }
        }

        // ================= RIGHT COLUMN =================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredWidth: 100   // 1fr
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: gamesCol.implicitHeight + 36
            radius: Theme.cardRadius
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            ColumnLayout {
                id: gamesCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 8

                Label {
                    text: "APPLY TO A STEAM GAME"
                    font.family: Theme.hudFont
                    font.pixelSize: Theme.fsLabel
                    font.weight: Font.Bold
                    font.letterSpacing: Theme.hudLetterSpacing
                    color: Theme.textMuted
                    Layout.bottomMargin: 6
                }
                Label {
                    visible: bridge.steamGames.length === 0
                    Layout.fillWidth: true
                    text: "No Steam library found (or Steam isn't set up yet). You can still copy the string and paste it manually."
                    color: Theme.textMuted
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.fsCaption
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: bridge.steamGames
                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: Theme.rowRadius
                        color: gameHover.hovered ? Theme.surfaceHover : "transparent"
                        border.width: 1
                        border.color: gameHover.hovered ? Theme.borderHover : Theme.border
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                        HoverHandler { id: gameHover }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 10

                            ColumnLayout {
                                spacing: 3
                                Layout.fillWidth: true
                                Label {
                                    text: modelData.name
                                    font.family: Theme.bodyFont
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: modelData.launchOptions.length > 0
                                          ? modelData.launchOptions : "no launch options set"
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsMicro
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                            OutlineActionButton {
                                text: "APPLY"
                                enabled: !bridge.running
                                onClicked: {
                                    var game = modelData
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
                    }
                }
                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    text: "Steam must be closed — it overwrites this file on exit. A backup is kept under Restore."
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textFaint
                    wrapMode: Text.Wrap
                }
            }
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

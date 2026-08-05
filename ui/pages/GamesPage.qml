import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

// Games — one library across Steam, Lutris and Heroic. Search it, see which
// compatibility tool each game runs on, and set that game's launch options
// without leaving the tool.
//
// The Launch Options page builds a string in the abstract; this page builds
// one for a game that exists and writes it where that game's launcher looks.
ColumnLayout {
    id: page
    property var confirmDialog: null
    spacing: 0

    property string filter: ""
    property string sourceFilter: ""    // "" = all
    property string openId: ""          // "<source>/<id>" of the expanded row

    // Hybrid graphics: an NVIDIA card alongside an integrated one is the
    // case where per-game render offload actually matters.
    readonly property bool hybridGpu:
        bridge.status["gpu_nvidia"] !== undefined
        && (bridge.status["gpu_amd"] !== undefined
            || bridge.status["gpu_intel"] !== undefined)

    function visibleGames() {
        var out = [], f = filter.toLowerCase()
        for (var i = 0; i < bridge.games.length; i++) {
            var g = bridge.games[i]
            if (g.state === "unavailable") continue
            if (sourceFilter !== "" && g.source !== sourceFilter) continue
            if (f !== "" && g.name.toLowerCase().indexOf(f) === -1) continue
            out.push(g)
        }
        return out
    }

    // Sources that reported a reason for being empty. Showing these beats an
    // empty list that leaves the user guessing whether the tool is broken.
    function notices() {
        var out = []
        for (var i = 0; i < bridge.games.length; i++)
            if (bridge.games[i].state === "unavailable")
                out.push(bridge.games[i])
        return out
    }

    function sourceLabel(s) {
        return s === "steam" ? "STEAM"
             : s === "lutris" ? "LUTRIS"
             : s === "heroic" ? "HEROIC" : s.toUpperCase()
    }
    function sourceTint(s) {
        return s === "steam" ? Theme.info
             : s === "lutris" ? Theme.warn
             : s === "heroic" ? Theme.accentText : Theme.textMuted
    }
    function countFor(s) {
        var n = 0
        for (var i = 0; i < bridge.games.length; i++)
            if (bridge.games[i].state !== "unavailable"
                && (s === "" || bridge.games[i].source === s)) n++
        return n
    }

    // The runner picker needs the installed-builds list, which lives in the
    // Proton model.
    Component.onCompleted: { bridge.refreshGames(); bridge.refreshProton() }

    // Builds this game could be switched to. Heroic keeps Proton and Wine
    // builds in separate directories, so it draws from both.
    function runnersFor(source) {
        var want = source === "steam" ? ["steam"]
                 : source === "lutris" ? ["lutris"]
                 : ["heroic-proton", "heroic-wine"]
        var out = []
        for (var i = 0; i < bridge.protonBuilds.length; i++) {
            var b = bridge.protonBuilds[i]
            if (b.kind !== "installed") continue
            if (want.indexOf(b.target) === -1) continue
            if (out.indexOf(b.name) === -1) out.push(b.name)
        }
        return out
    }

    // ---- header: search, source filters, count --------------------------
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
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsBody
                    color: Theme.textPrimary
                    background: null
                    topPadding: 0; bottomPadding: 0
                    leftPadding: 0; rightPadding: 0
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: page.filter = text

                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text.length === 0
                        text: "Search your games\u2026"
                        font: search.font
                        color: Theme.textMuted
                    }
                }
            }
        }

        Repeater {
            model: [
                { key: "",       label: "ALL" },
                { key: "steam",  label: "STEAM" },
                { key: "lutris", label: "LUTRIS" },
                { key: "heroic", label: "HEROIC" }
            ]
            FilterChip {
                required property var modelData
                visible: modelData.key === "" || page.countFor(modelData.key) > 0
                text: modelData.label
                count: page.countFor(modelData.key).toString()
                selected: page.sourceFilter === modelData.key
                onClicked: page.sourceFilter = modelData.key
            }
        }

        GhostButton {
            text: "REFRESH"
            implicitHeight: 36
            font.pixelSize: Theme.fsBody
            enabled: !bridge.running
            onClicked: bridge.refreshGames()
        }
    }

    // ---- per-source notices ---------------------------------------------
    Repeater {
        model: page.notices()
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: 8
            implicitHeight: noticeText.implicitHeight + 20
            radius: Theme.rowRadius
            color: Theme.surface
            border.width: 1
            border.color: Theme.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                Badge {
                    text: page.sourceLabel(modelData.source)
                    tint: page.sourceTint(modelData.source)
                }
                Label {
                    id: noticeText
                    Layout.fillWidth: true
                    text: modelData.launchOptions
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.fsCaption
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // ---- empty state ----------------------------------------------------
    Label {
        visible: bridge.games.length === 0 && !bridge.running
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.topMargin: 8
        text: "No games found yet. Install Steam, Lutris or Heroic and launch it "
              + "once so it writes its library, then press Refresh."
        font.family: Theme.bodyFont
        font.pixelSize: Theme.fsBody
        color: Theme.textMuted
        wrapMode: Text.Wrap
    }

    // ---- library --------------------------------------------------------
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        clip: true
        spacing: 4
        model: page.visibleGames()

        delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string rowKey: modelData.source + "/" + modelData.id
            readonly property bool expanded: page.openId === rowKey

            width: list.width
            height: 54 + (expanded ? editor.implicitHeight + 16 : 0)
            radius: Theme.rowRadius
            color: expanded ? Theme.surfaceHover
                            : (rowHover.hovered ? Theme.surfaceHover : Theme.surface)
            border.width: 1
            border.color: expanded ? Theme.borderFocus
                                   : (rowHover.hovered ? Theme.borderHover : Theme.border)
            Behavior on height       { NumberAnimation { duration: Theme.animMed; easing.type: Easing.OutCubic } }
            Behavior on color        { ColorAnimation { duration: Theme.animFast } }
            Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
            HoverHandler { id: rowHover }

            // A ListView destroys delegates that scroll out of view, so an
            // expanded row coming back into view has to refill its builder.
            Component.onCompleted: if (expanded) builder.load(modelData.launchOptions)

            // ---- summary line ----
            RowLayout {
                id: summary
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 54
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Badge {
                    text: page.sourceLabel(modelData.source)
                    tint: page.sourceTint(modelData.source)
                }
                ColumnLayout {
                    spacing: 2
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
                              ? modelData.launchOptions
                              : "no launch options set"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsMicro
                        color: modelData.launchOptions.length > 0
                               ? Theme.textSecondary : Theme.textFaint
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                Label {
                    visible: modelData.runner !== "-"
                    text: modelData.runner
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textMuted
                }
                Label {
                    text: modelData.size
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textFaint
                }
                OutlineActionButton {
                    text: row.expanded ? "CLOSE" : "OPTIONS"
                    implicitHeight: 30
                    onClicked: {
                        if (row.expanded) {
                            page.openId = ""
                        } else {
                            page.openId = row.rowKey
                            builder.load(modelData.launchOptions)
                        }
                    }
                }
            }

            // ---- inline editor ----
            ColumnLayout {
                id: editor
                visible: row.expanded
                anchors.top: summary.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 12
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.preferredHeight: 1
                    color: Theme.border
                }

                // Which Proton/Wine this game runs on. Deliberately separate
                // from the launch string: the options wrap the command, this
                // decides what actually runs it.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 2
                    Layout.topMargin: 4
                    spacing: 10
                    visible: page.runnersFor(modelData.source).length > 0

                    Label {
                        text: "RUNS ON"
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsMicro
                        font.letterSpacing: 1.2
                        color: Theme.textMuted
                    }
                    ComboBox {
                        id: runnerBox
                        Layout.fillWidth: true
                        Layout.maximumWidth: 320
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsCaption
                        model: page.runnersFor(modelData.source)
                        currentIndex: Math.max(
                            0, page.runnersFor(modelData.source).indexOf(modelData.runner))
                    }
                    OutlineActionButton {
                        text: "SWITCH"
                        implicitHeight: 28
                        enabled: !bridge.running
                               && runnerBox.currentText !== modelData.runner
                        onClicked: {
                            var g = modelData
                            var b = runnerBox.currentText
                            page.confirmDialog.openWith(
                                "Run " + g.name + " on " + b,
                                "gamerunner " + g.source + " " + g.id + " " + b,
                                function() { bridge.setGameRunner(g.source, g.id, b) })
                        }
                    }
                }

                LaunchOptionsBuilder {
                    id: builder
                    Layout.fillWidth: true
                    offerPrimeOffload: page.hybridGpu
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 10
                    spacing: 12

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: Theme.rowRadius
                        color: Theme.surfaceAlt
                        border.width: 1
                        border.color: Theme.border
                        Label {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: Text.AlignVCenter
                            text: builder.built.length > 0
                                  ? builder.built : "(no launch options \u2014 will be cleared)"
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fsMicro
                            color: builder.built.length > 0 ? Theme.textPrimary : Theme.textMuted
                            elide: Text.ElideMiddle
                        }
                    }
                    PrimaryButton {
                        text: "APPLY"
                        enabled: !bridge.running
                        onClicked: {
                            var g = modelData
                            var opts = builder.built
                            page.confirmDialog.openWithText(
                                "Set launch options \u2014 " + g.name,
                                page.warningFor(g.source)
                                + "\n\nNew launch options:\n  "
                                + (opts.length > 0 ? opts : "(cleared)")
                                + (g.launchOptions.length > 0
                                    ? "\n\nReplaces current:\n  " + g.launchOptions
                                    : "\n\n(no launch options currently set)")
                                + "\n\nThe config file is backed up first and listed "
                                + "under Restore.",
                                function() {
                                    bridge.applyGameOptions(g.source, g.id, opts)
                                    page.openId = ""
                                })
                        }
                    }
                }
            }
        }
    }

    // Each launcher loses the edit in its own way; say which one applies.
    function warningFor(source) {
        return source === "steam"
            ? "Steam must be closed \u2014 it keeps this file in memory and "
              + "rewrites it on exit."
            : source === "lutris"
            ? "Lutris must be closed \u2014 it caches game configs while running."
            : "Heroic must be closed \u2014 it rewrites its config on exit."
    }
}

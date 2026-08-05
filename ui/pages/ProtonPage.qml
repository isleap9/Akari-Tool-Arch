import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

// Proton — fetch GloriousEggroll's compatibility tools straight from GitHub
// into the directory each launcher scans.
//
// Grouped by launcher rather than by build, because that is the decision the
// user is actually making: Steam wants a Proton build, Lutris and Heroic want
// a Wine build, and a build installed for one is invisible to the others.
ColumnLayout {
    id: page
    property var confirmDialog: null
    spacing: 0

    property int keepCount: 2

    Component.onCompleted: bridge.refreshProton()

    // ---- model shaping ---------------------------------------------------
    function targets() {
        var seen = {}, out = []
        for (var i = 0; i < bridge.protonBuilds.length; i++) {
            var b = bridge.protonBuilds[i]
            if (b.kind === "error") continue
            if (!seen[b.target]) { seen[b.target] = true; out.push(b.target) }
        }
        return out
    }
    function targetLabel(t) {
        return t === "steam" ? "Steam"
             : t === "lutris" ? "Lutris"
             : t === "heroic-proton" ? "Heroic \u00B7 Proton"
             : t === "heroic-wine" ? "Heroic \u00B7 Wine" : t
    }
    function targetHint(t) {
        return t === "steam"
            ? "Properties \u2192 Compatibility \u2192 Force a specific Steam Play tool"
            : t === "lutris"
            ? "Configure \u2192 Runner options \u2192 Wine version"
            : "Settings \u2192 Wine/Proton version"
    }
    function installedFor(t) {
        var out = []
        for (var i = 0; i < bridge.protonBuilds.length; i++) {
            var b = bridge.protonBuilds[i]
            if (b.kind === "installed" && b.target === t) out.push(b)
        }
        return out
    }
    // Remote builds not already present for this target — the list is
    // "what can I add", so showing something already installed is noise.
    function availableFor(t) {
        var have = {}, out = []
        for (var i = 0; i < bridge.protonBuilds.length; i++) {
            var b = bridge.protonBuilds[i]
            if (b.kind === "installed" && b.target === t) have[b.name] = true
        }
        for (var j = 0; j < bridge.protonBuilds.length; j++) {
            var r = bridge.protonBuilds[j]
            if (r.kind === "remote" && r.target === t && !have[r.name]) out.push(r)
        }
        return out
    }
    // What this launcher currently runs games on. Empty means it is still on
    // the stock Proton/Wine it shipped with.
    function defaultFor(t) {
        for (var i = 0; i < bridge.protonBuilds.length; i++) {
            var b = bridge.protonBuilds[i]
            if (b.kind === "default" && b.target === t) return b.name
        }
        return ""
    }
    // True when the launcher is pointed at a build that has been deleted.
    // It then falls back to its own Proton/Wine, which is indistinguishable
    // from the setting having been ignored.
    function defaultMissing(t) {
        for (var i = 0; i < bridge.protonBuilds.length; i++) {
            var b = bridge.protonBuilds[i]
            if (b.kind === "default" && b.target === t)
                return b.detail === "missing"
        }
        return false
    }
    function errors() {
        var out = []
        for (var i = 0; i < bridge.protonBuilds.length; i++)
            if (bridge.protonBuilds[i].kind === "error")
                out.push(bridge.protonBuilds[i])
        return out
    }
    function humanSize(bytes) {
        var b = parseFloat(bytes)
        if (isNaN(b) || b <= 0) return ""
        var u = ["B", "KiB", "MiB", "GiB"]
        var i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return b.toFixed(1) + u[i]
    }

    // ---- header ----------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 12
        spacing: 12

        Label {
            Layout.fillWidth: true
            text: "Installing a build only makes it available \u2014 no launcher "
                  + "switches to a newer one on its own. Use Install & use, or "
                  + "Use by default on one you already have."
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsCaption
            color: Theme.textSecondary
            wrapMode: Text.Wrap
        }
        GhostButton {
            text: "PRUNE OLD"
            implicitHeight: 36
            font.pixelSize: Theme.fsBody
            enabled: !bridge.running
            onClicked: page.confirmDialog.openWith(
                "Prune old compatibility tools",
                "proton-prune " + page.keepCount,
                function() { bridge.pruneProton(page.keepCount) })
        }
        GhostButton {
            text: "REFRESH"
            implicitHeight: 36
            font.pixelSize: Theme.fsBody
            enabled: !bridge.running
            onClicked: bridge.refreshProton()
        }
    }

    // ---- errors ----------------------------------------------------------
    Repeater {
        model: page.errors()
        Rectangle {
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pagePadding
            Layout.rightMargin: Theme.pagePadding
            Layout.bottomMargin: 8
            implicitHeight: 44
            radius: Theme.rowRadius
            color: Qt.alpha(Theme.warn, 0.08)
            border.width: 1
            border.color: Qt.alpha(Theme.warn, 0.3)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                Badge { text: modelData.track.toUpperCase(); tint: Theme.warn }
                Label {
                    Layout.fillWidth: true
                    text: modelData.detail
                          + " \u2014 GitHub allows 60 requests an hour without a login; "
                          + "wait a few minutes and press Refresh."
                    font.family: Theme.bodyFont
                    font.pixelSize: Theme.fsCaption
                    color: Theme.textSecondary
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    Label {
        visible: page.targets().length === 0 && page.errors().length === 0 && !bridge.running
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        text: "No launcher detected. Install Steam, Lutris or Heroic first \u2014 "
              + "compatibility tools go into a directory the launcher owns, so "
              + "there is nowhere to put them yet."
        font.family: Theme.bodyFont
        font.pixelSize: Theme.fsBody
        color: Theme.textMuted
        wrapMode: Text.Wrap
    }

    // ---- one card per launcher -------------------------------------------
    ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 14

            Repeater {
                model: page.targets()

                Rectangle {
                    required property string modelData
                    readonly property string target: modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: cardCol.implicitHeight + 34
                    radius: Theme.cardRadius
                    color: Theme.surface
                    border.width: 1
                    border.color: Theme.border

                    ColumnLayout {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 17
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            spacing: 10
                            Label {
                                text: page.targetLabel(target).toUpperCase()
                                font.family: Theme.hudFont
                                font.pixelSize: Theme.fsLabel
                                font.weight: Font.Bold
                                font.letterSpacing: Theme.hudLetterSpacing
                                color: Theme.accent
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: page.targetHint(target)
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textFaint
                            }
                        }

                        // The single most useful line on this page: which
                        // build this launcher is actually using right now.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 4
                            Layout.preferredHeight: 34
                            radius: Theme.rowRadius
                            color: Theme.surfaceAlt
                            border.width: 1
                            border.color: Theme.border
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 8
                                Label {
                                    text: "CURRENTLY USING"
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsMicro
                                    font.letterSpacing: 1.2
                                    color: Theme.textMuted
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: page.defaultFor(target).length === 0
                                          ? "the stock Proton/Wine this launcher ships with"
                                          : page.defaultMissing(target)
                                            ? page.defaultFor(target)
                                              + " \u2014 not installed any more, so it falls "
                                              + "back to stock. Pick another below."
                                            : page.defaultFor(target)
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsCaption
                                    color: page.defaultMissing(target) ? Theme.warn
                                         : page.defaultFor(target).length > 0
                                           ? Theme.textPrimary : Theme.textMuted
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // -- installed --
                        Label {
                            visible: page.installedFor(target).length === 0
                            text: "Nothing installed here yet."
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                            color: Theme.textMuted
                        }
                        Repeater {
                            model: page.installedFor(target)
                            Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                radius: Theme.rowRadius
                                color: iHover.hovered ? Theme.surfaceHover : "transparent"
                                border.width: 1
                                border.color: iHover.hovered ? Theme.borderHover : Theme.border
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                                HoverHandler { id: iHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    StatusDot { tint: Theme.ok }
                                    Label {
                                        text: modelData.name
                                        font.family: Theme.monoFont
                                        font.pixelSize: 13
                                        color: Theme.textPrimary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Badge {
                                        visible: page.defaultFor(modelData.target) === modelData.name
                                        text: "IN USE"
                                        tint: Theme.ok
                                    }
                                    Label {
                                        text: modelData.size
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fsMicro
                                        color: Theme.textMuted
                                    }
                                    OutlineActionButton {
                                        visible: page.defaultFor(modelData.target) !== modelData.name
                                        text: "USE BY DEFAULT"
                                        tint: Theme.ok
                                        implicitHeight: 28
                                        enabled: !bridge.running
                                        onClicked: page.confirmDialog.openWith(
                                            "Use " + modelData.name + " by default",
                                            "compat-default " + modelData.target + " " + modelData.name,
                                            function() {
                                                bridge.setCompatDefault(modelData.target,
                                                                        modelData.name)
                                            })
                                    }
                                    OutlineActionButton {
                                        text: "REMOVE"
                                        tint: Theme.warn
                                        implicitHeight: 28
                                        enabled: !bridge.running
                                        onClicked: page.confirmDialog.openWith(
                                            "Remove " + modelData.name,
                                            "proton-remove " + modelData.name + " " + modelData.target,
                                            function() {
                                                bridge.removeProton(modelData.name, modelData.target)
                                            })
                                    }
                                }
                            }
                        }

                        // -- available --
                        Label {
                            visible: page.availableFor(target).length > 0
                            Layout.topMargin: 8
                            text: "AVAILABLE"
                            font.family: Theme.hudFont
                            font.pixelSize: Theme.fsLabel
                            font.weight: Font.Bold
                            font.letterSpacing: Theme.hudLetterSpacing
                            color: Theme.textMuted
                        }
                        Repeater {
                            model: page.availableFor(target)
                            Rectangle {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44
                                radius: Theme.rowRadius
                                color: aHover.hovered ? Theme.surfaceHover : "transparent"
                                border.width: 1
                                border.color: aHover.hovered ? Theme.borderHover : Theme.border
                                Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                                HoverHandler { id: aHover }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 12
                                    spacing: 10
                                    Label {
                                        text: modelData.name
                                        font.family: Theme.monoFont
                                        font.pixelSize: 13
                                        color: Theme.textPrimary
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    // The newest build GitHub offers for this
                                    // track, which is what most people want.
                                    Badge {
                                        visible: index === 0
                                        text: "LATEST"
                                        tint: Theme.ok
                                    }
                                    Label {
                                        text: page.humanSize(modelData.size)
                                        font.family: Theme.monoFont
                                        font.pixelSize: Theme.fsMicro
                                        color: Theme.textFaint
                                    }
                                    OutlineActionButton {
                                        text: "INSTALL"
                                        implicitHeight: 28
                                        enabled: !bridge.running
                                        onClicked: page.confirmDialog.openWith(
                                            "Install " + modelData.name,
                                            "proton-install " + modelData.track + " "
                                              + modelData.name + " " + modelData.target,
                                            function() {
                                                bridge.installProton(modelData.track,
                                                                     modelData.name,
                                                                     modelData.target,
                                                                     false)
                                            })
                                    }
                                    // The common case, so it gets the solid
                                    // button: download it AND start using it.
                                    PrimaryButton {
                                        text: "INSTALL & USE"
                                        implicitHeight: 28
                                        font.pixelSize: Theme.fsMicro
                                        enabled: !bridge.running
                                        onClicked: page.confirmDialog.openWith(
                                            "Install and use " + modelData.name,
                                            "proton-install " + modelData.track + " "
                                              + modelData.name + " " + modelData.target
                                              + " default",
                                            function() {
                                                bridge.installProton(modelData.track,
                                                                     modelData.name,
                                                                     modelData.target,
                                                                     true)
                                            })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

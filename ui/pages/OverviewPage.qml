import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

// Overview — performance-HUD layout:
//   [ readiness gauge | recommended-action hero ]
//   [ 3-col metric card grid                    ]
//   [ HARDWARE strip          | RECENT CHANGES  ]
Flickable {
    id: page
    property var confirmDialog: null
    contentHeight: col.height + 56
    clip: true

    Component.onCompleted: bridge.refreshPackages()

    // ---- helpers reading bridge state ----------------------------------
    function statusState(key) {
        var s = bridge.status[key]
        return s ? s.state : "unknown"
    }
    function statusDetail(key) {
        var s = bridge.status[key]
        return s ? s.detail : "Checking…"
    }
    function needsSetup() {
        return statusState("gaming") === "warn" || statusState("multilib") === "warn"
               || statusState("tweaks") === "warn"
    }
    function diagCounts() {
        var ok = 0, warn = 0, fail = 0
        for (var i = 0; i < bridge.diagnostics.length; i++) {
            var st = bridge.diagnostics[i].state
            if (st === "ok" || st === "info") ok++
            else if (st === "fail") fail++
            else warn++
        }
        return { ok: ok, warn: warn, fail: fail, total: bridge.diagnostics.length }
    }
    function pkgCounts() {
        var inst = 0
        for (var i = 0; i < bridge.packages.length; i++)
            if (bridge.packages[i].installed) inst++
        return { installed: inst, total: bridge.packages.length }
    }
    // Readiness = share of resolved status checks that are OK
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
    function pendingSummary() {
        var warn = 0, fail = 0
        for (var k in bridge.status) {
            var st = bridge.status[k].state
            if (st === "warn") warn++
            else if (st === "fail") fail++
        }
        if (warn === 0 && fail === 0) return "all checks passing"
        var parts = []
        if (warn > 0) parts.push(warn + (warn === 1 ? " tweak pending" : " tweaks pending"))
        if (fail > 0) parts.push(fail + (fail === 1 ? " warning" : " warnings"))
        return parts.join(" · ")
    }
    // Discrete-first ordering (nvidia > amd > intel) — QVariantMap key order
    // is alphabetical, which would list an AMD iGPU before an NVIDIA dGPU.
    function gpuEntries() {
        var order = ["gpu_nvidia", "gpu_amd", "gpu_intel"]
        var out = []
        for (var i = 0; i < order.length; i++) {
            var s = bridge.status[order[i]]
            if (s) out.push({ label: out.length === 0 ? "GPU" : "GPU " + (out.length + 1),
                              value: s.detail,
                              state: s.state })
        }
        return out
    }
    function runningKernel() {
        for (var i = 0; i < bridge.kernels.length; i++)
            if (bridge.kernels[i].running) return bridge.kernels[i].name
        return "detecting…"
    }
    function recentChanges() {
        if (!bridge.changeLog || bridge.changeLog.length === 0) return []
        var lines = bridge.changeLog.trim().split("\n")
        var out = []
        for (var i = lines.length - 1; i >= 0 && out.length < 4; i--) {
            var l = lines[i].trim()
            if (l.length === 0) continue
            // "2026-07-18T15:54:05+02:00 | cleanup: trimmed pacman cache"
            var time = "", text = l
            var bar = l.indexOf("|")
            if (bar > 0) {
                var ts = l.substring(0, bar).trim()
                text = l.substring(bar + 1).trim()
                var m = ts.match(/T(\d{2}:\d{2})/)   // ISO stamp -> HH:MM
                time = m ? m[1] : ts.split(" ").pop().substring(0, 5)
            }
            out.push({ time: time, text: text })
        }
        return out
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pagePadding
        anchors.topMargin: 4
        spacing: 16

        // ================= HERO ROW =================
        GridLayout {
            Layout.fillWidth: true
            columns: width > 680 ? 2 : 1
            columnSpacing: 16
            rowSpacing: 16

            // ---- readiness gauge ----
            Rectangle {
                Layout.preferredWidth: 300
                Layout.minimumWidth: 260
                Layout.fillHeight: true
                Layout.minimumHeight: 250
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    spacing: 0

                    Label {
                        text: "SYSTEM READINESS"
                        font.family: Theme.hudFont
                        font.pixelSize: Theme.fsLabel
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.hudLetterSpacing
                        color: Theme.textMuted
                    }
                    Item { Layout.fillHeight: true }
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 158
                        Layout.preferredHeight: 158

                        Canvas {
                            id: gauge
                            anchors.fill: parent
                            property real value: Math.max(0, page.readiness())
                            onValueChanged: requestPaint()
                            Behavior on value { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                var c = width / 2, r = width / 2 - 1
                                var start = -Math.PI / 2
                                var sweep = 2 * Math.PI * value / 100
                                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI)
                                ctx.fillStyle = String(Theme.border); ctx.fill()
                                ctx.beginPath(); ctx.moveTo(c, c)
                                ctx.arc(c, c, r, start, start + sweep)
                                ctx.closePath()
                                ctx.fillStyle = String(Theme.accent); ctx.fill()
                            }
                        }
                        Rectangle {   // inner disc
                            anchors.centerIn: parent
                            width: 134; height: 134; radius: 67
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 1
                                Label {
                                    text: page.readiness() < 0 ? "—" : page.readiness()
                                    font.family: Theme.hudFont
                                    font.weight: Font.Bold
                                    font.pixelSize: Theme.fsDisplay
                                    color: Theme.textPrimary
                                }
                                Label {
                                    visible: page.readiness() >= 0
                                    text: "%"
                                    font.family: Theme.hudFont
                                    font.pixelSize: 20
                                    color: Theme.textSecondary
                                    Layout.alignment: Qt.AlignBottom
                                    Layout.bottomMargin: 6
                                }
                            }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: page.readiness() >= 90 ? "OPTIMIZED"
                                    : page.readiness() < 0   ? "SCANNING"
                                    : "TUNING"
                                font.family: Theme.monoFont
                                font.pixelSize: Theme.fsBadge
                                font.letterSpacing: 1.5
                                color: Theme.textMuted
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: page.pendingSummary()
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsLabel
                        color: Theme.textSecondary
                    }
                }
            }

            // ---- recommended action hero ----
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 250
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    anchors.leftMargin: 26
                    anchors.rightMargin: 26
                    spacing: 0

                    Label {
                        text: "RECOMMENDED ACTION"
                        font.family: Theme.hudFont
                        font.pixelSize: Theme.fsLabel
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.hudLetterSpacing
                        color: Theme.accent
                    }
                    Label {
                        Layout.topMargin: 6
                        text: page.needsSetup() ? "Finish your gaming setup"
                            : page.statusState("sysupdate") === "warn" ? "Updates available"
                            : "System is ready to play"
                        font.family: Theme.hudFont
                        font.weight: Font.Bold
                        font.pixelSize: Theme.fsHero
                        font.letterSpacing: 0.5
                        color: Theme.textPrimary
                    }
                    Label {
                        Layout.topMargin: 6
                        Layout.fillWidth: true
                        Layout.maximumWidth: 560
                        text: page.needsSetup()
                              ? "Install the missing pieces of the gaming stack and apply the remaining tweaks to reach 100% readiness."
                              : page.statusState("sysupdate") === "warn"
                              ? "A system upgrade is pending. Keeping Arch current avoids partial-upgrade breakage."
                              : "Everything Akari checks is in place. Diagnostics run below — game on."
                        font.family: Theme.bodyFont
                        font.pixelSize: Theme.fsBody
                        color: Theme.textSecondary
                        wrapMode: Text.Wrap
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.topMargin: 20
                        Layout.fillWidth: true
                        spacing: 12

                        PrimaryButton {
                            visible: page.needsSetup()
                            glow: true
                            text: "SET UP GAMING"
                            enabled: !bridge.running
                            onClicked: page.confirmDialog.openWith("Set up everything", "all",
                                           function() { bridge.run("apply", "all") })
                        }
                        PrimaryButton {
                            visible: !page.needsSetup() && page.statusState("sysupdate") === "warn"
                            glow: true
                            text: "UPDATE SYSTEM"
                            enabled: !bridge.running
                            onClicked: page.confirmDialog.openWith("Full system upgrade", "sysupdate",
                                           function() { bridge.run("apply", "sysupdate") })
                        }
                        GhostButton {
                            text: "RUN DIAGNOSTICS"
                            enabled: !bridge.running
                            onClicked: bridge.runDiagnose()
                        }
                        Label {
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.minimumWidth: 40
                            text: {
                                var p = page.pkgCounts()
                                var d = page.diagCounts()
                                var pkgs = p.total === 0 ? "…" : p.installed + "/" + p.total
                                var diag = d.total === 0 ? "…" : d.ok + "·" + d.warn + "·" + d.fail
                                return "PKGS " + pkgs + "   DIAG " + diag
                            }
                            font.family: Theme.monoFont
                            font.pixelSize: Theme.fsLabel
                            color: Theme.textMuted
                        }
                    }
                }
            }
        }

        // ================= METRIC CARDS =================
        GridLayout {
            Layout.fillWidth: true
            columns: width > 760 ? 3 : 1
            columnSpacing: Theme.cardSpacing
            rowSpacing: Theme.cardSpacing

            StatusCard {
                title: "Gaming Packages"
                subtitle: page.statusDetail("gaming")
                state_: page.statusState("gaming")
                metric: {
                    var p = page.pkgCounts()
                    return p.total === 0 ? "" : p.installed + "/" + p.total
                }
                metricSub: "INSTALLED"
                barSegments: {
                    var p = page.pkgCounts()
                    if (p.total === 0) return []
                    var f = p.installed / p.total
                    return f >= 1 ? [{frac: 1, state: "ok"}]
                                  : [{frac: f, state: "ok"}, {frac: 1 - f, state: "warn"}]
                }
                actionText: page.statusState("gaming") === "warn" ? "Set up gaming" : ""
                busy: bridge.running
                onAction: page.confirmDialog.openWith("Set up gaming", "gaming",
                              function() { bridge.run("apply", "gaming") })
            }
            StatusCard {
                title: "Diagnostics"
                subtitle: {
                    var c = page.diagCounts()
                    return c.total === 0 ? "Running functional tests…"
                         : "Functional tests of the live gaming stack — details on Diagnose"
                }
                state_: {
                    var c = page.diagCounts()
                    return c.total === 0 ? "unknown"
                         : c.fail > 0 ? "fail" : c.warn > 0 ? "warn" : "ok"
                }
                metric: {
                    var c = page.diagCounts()
                    return c.total === 0 ? "" : c.ok + "·" + c.warn + "·" + c.fail
                }
                metricSub: "PASS · WARN · FAIL"
                barSegments: {
                    var c = page.diagCounts()
                    if (c.total === 0) return []
                    var segs = []
                    if (c.ok > 0)   segs.push({frac: c.ok / c.total,   state: "ok"})
                    if (c.warn > 0) segs.push({frac: c.warn / c.total, state: "warn"})
                    if (c.fail > 0) segs.push({frac: c.fail / c.total, state: "fail"})
                    return segs
                }
            }
            StatusCard {
                title: "System Check"
                subtitle: page.statusDetail("multilib")
                state_: page.statusState("multilib")
                actionText: page.statusState("multilib") === "warn" ? "Enable multilib" : ""
                busy: bridge.running
                onAction: page.confirmDialog.openWith("Enable multilib", "multilib",
                              function() { bridge.run("apply", "multilib") })
            }
            StatusCard {
                title: "Proton-GE"
                subtitle: page.statusDetail("proton")
                state_: page.statusState("proton")
            }
            StatusCard {
                title: "Performance Tweaks"
                subtitle: page.statusDetail("tweaks")
                state_: page.statusState("tweaks")
                actionText: page.statusState("tweaks") === "warn" ? "Apply tweaks" : ""
                busy: bridge.running
                onAction: page.confirmDialog.openWith("Apply performance tweaks", "tweaks",
                              function() { bridge.run("apply", "tweaks") })
            }
            StatusCard {
                title: "System Updates"
                subtitle: page.statusDetail("sysupdate")
                state_: page.statusState("sysupdate")
                actionText: page.statusState("sysupdate") === "warn" ? "Update system" : ""
                busy: bridge.running
                onAction: page.confirmDialog.openWith("Full system upgrade", "sysupdate",
                              function() { bridge.run("apply", "sysupdate") })
            }
        }

        // ================= HARDWARE + RECENT CHANGES =================
        GridLayout {
            Layout.fillWidth: true
            columns: width > 900 ? 2 : 1
            columnSpacing: Theme.cardSpacing
            rowSpacing: Theme.cardSpacing

            Rectangle {   // HARDWARE strip
                Layout.fillWidth: true
                Layout.preferredWidth: 14   // ~1.4fr
                Layout.minimumHeight: 118
                Layout.preferredHeight: hwCol.implicitHeight + 36
                Layout.fillHeight: true
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                clip: true

                ColumnLayout {
                    id: hwCol
                    anchors.fill: parent
                    anchors.margins: 18
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 14

                    Label {
                        text: "HARDWARE"
                        font.family: Theme.hudFont
                        font.pixelSize: Theme.fsLabel
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.hudLetterSpacing
                        color: Theme.textMuted
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width > 560 ? 4 : 2
                        columnSpacing: 14
                        rowSpacing: 12

                        Repeater {
                            model: {
                                var items = page.gpuEntries().slice(0, 2)
                                var cpu = bridge.status["cpu"]
                                if (cpu) items.push({ label: "CPU",
                                                      value: cpu.detail,
                                                      state: cpu.state })
                                var ram = bridge.status["ram"]
                                if (ram) items.push({ label: "RAM",
                                                      value: ram.detail,
                                                      state: ram.state })
                                items.push({ label: "KERNEL",
                                             value: page.runningKernel(),
                                             state: "ok" })
                                items.push({ label: "NETWORK",
                                             value: page.statusDetail("network"),
                                             state: page.statusState("network") })
                                return items
                            }
                            ColumnLayout {
                                required property var modelData
                                spacing: 3
                                Label {
                                    text: modelData.label
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsBadge
                                    font.letterSpacing: 1.5
                                    color: Theme.textMuted
                                }
                                Label {
                                    text: modelData.value
                                    font.family: Theme.bodyFont
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: Theme.stateLabel(modelData.state)
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsMicro
                                    color: Theme.stateColor(modelData.state)
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            Rectangle {   // RECENT CHANGES feed
                Layout.fillWidth: true
                Layout.preferredWidth: 10   // ~1fr
                Layout.minimumHeight: 118
                Layout.preferredHeight: changesCol.implicitHeight + 36
                Layout.fillHeight: true
                radius: Theme.cardRadius
                color: Theme.surface
                border.width: 1
                border.color: Theme.border
                clip: true

                ColumnLayout {
                    id: changesCol
                    anchors.fill: parent
                    anchors.margins: 18
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    Label {
                        text: "RECENT CHANGES"
                        font.family: Theme.hudFont
                        font.pixelSize: Theme.fsLabel
                        font.weight: Font.Bold
                        font.letterSpacing: Theme.hudLetterSpacing
                        color: Theme.textMuted
                    }
                    ColumnLayout {
                        spacing: 9
                        Label {
                            visible: page.recentChanges().length === 0
                            text: "No changes yet — actions you apply will show up here."
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                            color: Theme.textFaint
                        }
                        Repeater {
                            model: page.recentChanges()
                            RowLayout {
                                required property var modelData
                                spacing: 10
                                Label {
                                    visible: modelData.time.length > 0
                                    text: modelData.time
                                    font.family: Theme.monoFont
                                    font.pixelSize: Theme.fsMicro
                                    color: Theme.textFaint
                                    Layout.preferredWidth: 40
                                    Layout.maximumWidth: 40
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    color: Theme.accentDim
                                }
                                Label {
                                    text: modelData.text
                                    font.family: Theme.bodyFont
                                    font.pixelSize: Theme.fsCaption
                                    color: Theme.textSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}

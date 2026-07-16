import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

Flickable {
    id: page
    property var confirmDialog: null
    contentHeight: grid.height + 56
    clip: true

    // ---- helpers reading bridge.status ---------------------------------
    function statusState(key) {
        var s = bridge.status[key]
        return s ? s.state : "unknown"
    }
    function statusDetail(key) {
        var s = bridge.status[key]
        return s ? s.detail : "Checking…"
    }
    function gpuState() {
        var k
        for (k in bridge.status)
            if (k.indexOf("gpu_") === 0 && bridge.status[k].state !== "ok")
                return "warn"
        for (k in bridge.status)
            if (k.indexOf("gpu_") === 0)
                return "ok"
        return "unknown"
    }
    function diagCounts() {
        var ok = 0, warn = 0, fail = 0
        for (var i = 0; i < bridge.diagnostics.length; i++) {
            var st = bridge.diagnostics[i].state
            if (st === "ok") ok++
            else if (st === "fail") fail++
            else warn++
        }
        return { ok: ok, warn: warn, fail: fail, total: bridge.diagnostics.length }
    }
    function needsSetup() {
        return statusState("gaming") === "warn" || statusState("multilib") === "warn"
               || statusState("tweaks") === "warn"
    }
    function gpuSummary() {
        var parts = []
        for (var k in bridge.status)
            if (k.indexOf("gpu_") === 0)
                parts.push(bridge.status[k].detail)
        return parts.length ? parts.join(" · ") : "Detecting…"
    }

    GridLayout {
        id: grid
        columns: width > 1400 ? 3 : width > 760 ? 2 : 1
        columnSpacing: Theme.cardSpacing
        rowSpacing: Theme.cardSpacing
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.pagePadding
        anchors.topMargin: 8

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
            title: "Gaming Packages"
            subtitle: page.statusDetail("gaming")
            state_: page.statusState("gaming")
            actionText: page.needsSetup() ? "Set up everything" : "Set up gaming"
            busy: bridge.running
            onAction: page.needsSetup()
                ? page.confirmDialog.openWith("Set up everything", "all",
                      function() { bridge.run("apply", "all") })
                : page.confirmDialog.openWith("Set up gaming", "gaming",
                      function() { bridge.run("apply", "gaming") })
        }
        StatusCard {
            title: "GPU Drivers"
            subtitle: page.gpuSummary()
            state_: page.gpuState()
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
            title: "AUR Extras"
            subtitle: page.statusDetail("aur")
            state_: page.statusState("aur")
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
        StatusCard {
            title: "Diagnosis"
            subtitle: {
                var c = page.diagCounts()
                return c.total === 0 ? "Running functional tests…"
                     : c.ok + " pass · " + c.warn + " warn · " + c.fail
                       + " fail — details on the Diagnose page"
            }
            state_: {
                var c = page.diagCounts()
                return c.total === 0 ? "unknown"
                     : c.fail > 0 ? "fail" : c.warn > 0 ? "warn" : "ok"
            }
        }
        StatusCard {
            title: "Network"
            subtitle: page.statusDetail("network")
            state_: page.statusState("network")
        }
    }
}

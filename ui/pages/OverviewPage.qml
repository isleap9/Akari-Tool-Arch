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
            actionText: "Set up gaming"
            busy: bridge.running
            onAction: page.confirmDialog.openWith("Set up gaming", "gaming",
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
            title: "Network"
            subtitle: page.statusDetail("network")
            state_: page.statusState("network")
        }
    }
}

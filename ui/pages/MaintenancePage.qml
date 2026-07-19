import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

// Maintenance — one-click system upkeep backed by akari-setup.sh targets:
//   apply paru      bootstrap an AUR helper on fresh installs
//   apply mirrors   rank the fastest pacman mirrors (reflector)
//   apply cleanup   trim package cache + remove orphans
Item {
    id: page
    property var confirmDialog

    function st(key) {
        var s = bridge.status[key]
        return s ? s.state : "unknown"
    }
    function det(key, fallback) {
        var s = bridge.status[key]
        return s && s.detail ? s.detail : fallback
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.pagePadding
        anchors.topMargin: 24
        spacing: 16

        Label {
            Layout.fillWidth: true
            text: "One-click upkeep — each action previews a plan and keeps a backup before it changes anything."
            font.family: Theme.bodyFont
            color: Theme.textSecondary
            font.pixelSize: Theme.fsBody
            wrapMode: Text.Wrap
        }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        columns: width > 900 ? 3 : 1
        columnSpacing: 14
        rowSpacing: 14
        flow: GridLayout.LeftToRight

        StatusCard {
            title: "AUR Helper"
            subtitle: page.det("aur", "Install paru so AUR packages can be installed from Akari.")
            state_: page.st("aur")
            outlineAction: true
            actionText: "Install paru"
            busy: bridge.running
            onAction: page.confirmDialog.openWith(
                "Install paru (AUR helper)", "paru",
                function() { bridge.run("apply", "paru") })
        }

        StatusCard {
            title: "Mirrors"
            subtitle: page.det("mirrors", "Rank the fastest mirrors with reflector.")
                      + " Current list is backed up first."
            state_: page.st("mirrors")
            outlineAction: true
            actionText: "Optimize mirrors"
            busy: bridge.running
            onAction: page.confirmDialog.openWith(
                "Optimize pacman mirrors", "mirrors",
                function() { bridge.run("apply", "mirrors") })
        }

        StatusCard {
            title: "Cleanup"
            subtitle: page.det("cache", "Trim the pacman cache and remove orphans.")
                      + " The plan preview lists exactly what would change."
            state_: page.st("cache")
            outlineAction: true
            actionText: "Clean up"
            busy: bridge.running
            onAction: page.confirmDialog.openWith(
                "System cleanup", "cleanup",
                function() { bridge.run("apply", "cleanup") })
        }

        StatusCard {
            title: "Snapshots"
            subtitle: page.det("snapshots", "Create a filesystem snapshot you can roll back to.")
            state_: page.st("snapshots")
            outlineAction: true
            actionText: "Snapshot now"
            busy: bridge.running
            onAction: page.confirmDialog.openWith(
                "Create snapshot", "snapshot",
                function() { bridge.run("apply", "snapshot") })
        }

        StatusCard {
            title: "Flatpak"
            subtitle: page.det("flatpak", "Set up Flatpak + Flathub for AUR-free app installs.")
            state_: page.st("flatpak")
            outlineAction: true
            actionText: "Set up Flatpak"
            busy: bridge.running
            onAction: page.confirmDialog.openWith(
                "Set up Flatpak", "flatpak-setup",
                function() { bridge.run("apply", "flatpak-setup") })
        }

        StatusCard {
            title: "Akari Updates"
            subtitle: page.det("update", "Check GitHub for a newer version of Akari Tool.")
            state_: page.st("update")
            outlineAction: true
            actionText: "Update Akari"
            busy: bridge.running
            onAction: page.confirmDialog.openWith(
                "Update Akari Tool", "self-update",
                function() { bridge.run("apply", "self-update") })
        }

    }

        Item { Layout.fillHeight: true }   // keep cards pinned to the top
    }
}

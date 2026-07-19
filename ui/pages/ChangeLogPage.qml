import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

// Change Log — mock: dark timeline panel; rows = mono time (92px) + tag pill +
// mono message, red left-border on hover.
ColumnLayout {
    id: page
    spacing: 0

    Component.onCompleted: bridge.refreshChangeLog()

    // Parse "…time… TAG message" lines heuristically; fall back to plain text.
    function entries() {
        if (!bridge.changeLog || bridge.changeLog.trim().length === 0) return []
        var out = []
        var lines = bridge.changeLog.trim().split("\n")
        for (var i = lines.length - 1; i >= 0; i--) {
            var l = lines[i].trim()
            if (l.length === 0) continue
            var m = l.match(/^(\[?[\d:\-\. ]+\]?)\s+(\S+)\s+(.*)$/)
            if (m && m[1].replace(/[\[\]\s]/g, "").length >= 4)
                out.push({ time: m[1].replace(/[\[\]]/g, "").trim(),
                           tag: m[2].toUpperCase(), text: m[3] })
            else
                out.push({ time: "", tag: "", text: l })
        }
        return out
    }
    function tagTint(tag) {
        return tag.indexOf("REMOV") === 0 || tag.indexOf("UNINSTALL") === 0 ? Theme.warn
             : tag.indexOf("FAIL") === 0 || tag.indexOf("ERROR") === 0      ? Theme.fail
             : tag.indexOf("RESTOR") === 0                                  ? Theme.info
             : Theme.ok
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 16
        spacing: 12
        Label {
            text: "Every change Akari Tool has made to this system. pacman.conf edits keep a .akari.bak copy."
            color: Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsBody
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        GhostButton {
            text: "REFRESH"
            enabled: !bridge.running
            onClicked: bridge.refreshChangeLog()
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        radius: Theme.cardRadius
        color: Theme.surfaceAlt
        border.width: 1
        border.color: Theme.border
        clip: true

        Label {
            visible: page.entries().length === 0
            anchors.centerIn: parent
            text: "No changes recorded yet."
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsBody
            color: Theme.textFaint
        }

        ListView {
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            clip: true
            model: page.entries()

            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: Math.max(38, rowContent.implicitHeight + 16)
                color: rowHover.hovered ? Theme.surfaceDeep : "transparent"
                HoverHandler { id: rowHover }

                Rectangle {   // red left border on hover
                    width: 2
                    height: parent.height
                    color: rowHover.hovered ? Theme.accent : "transparent"
                }

                RowLayout {
                    id: rowContent
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 16

                    Label {
                        visible: modelData.time.length > 0
                        text: modelData.time
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsLabel
                        color: Theme.textFaint
                        Layout.preferredWidth: 92
                        elide: Text.ElideRight
                    }
                    Badge {
                        visible: modelData.tag.length > 0
                        text: modelData.tag
                        tint: page.tagTint(modelData.tag)
                    }
                    Label {
                        text: modelData.text
                        font.family: Theme.monoFont
                        font.pixelSize: Theme.fsCaption
                        color: Theme.textCode
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    spacing: 0

    Component.onCompleted: bridge.runDiagnose()

    function counts() {
        var ok = 0, warn = 0, fail = 0
        for (var i = 0; i < bridge.diagnostics.length; i++) {
            var st = bridge.diagnostics[i].state
            if (st === "ok" || st === "info") ok++
            else if (st === "fail") fail++
            else warn++
        }
        return { ok: ok, warn: warn, fail: fail }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 18
        spacing: 14

        Label {
            text: bridge.diagnostics.length === 0
                  ? "Running functional tests…"
                  : "These tests exercise the actual gaming stack — not just package presence."
            color: Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsBody
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
        Repeater {
            model: bridge.diagnostics.length === 0 ? [] : [
                { count: page.counts().ok,   label: "PASS", tint: Theme.ok },
                { count: page.counts().warn, label: "WARN", tint: Theme.warn },
                { count: page.counts().fail, label: "FAIL", tint: Theme.fail }
            ]
            RowLayout {
                required property var modelData
                spacing: 5
                Label {
                    text: modelData.count
                    font.family: Theme.hudFont
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    color: modelData.tint
                }
                Label {
                    text: modelData.label
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.fsLabel
                    color: modelData.tint
                }
            }
        }
        GhostButton {
            text: "RUN AGAIN"
            enabled: !bridge.running
            onClicked: bridge.runDiagnose()
        }
    }

    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        contentHeight: grid.height
        clip: true

        GridLayout {
            id: grid
            width: parent.width
            columns: width > 760 ? 2 : 1
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: bridge.diagnostics
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: content.implicitHeight + 28
                    radius: Theme.cardRadius
                    color: Theme.surface
                    border.width: 1
                    border.color: modelData.state === "warn" || modelData.state === "fail"
                                  ? Qt.alpha(Theme.stateColor(modelData.state), 0.35)
                                  : Theme.border

                    ColumnLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 6

                        RowLayout {
                            spacing: 10
                            Layout.fillWidth: true
                            StatusDot { tint: Theme.stateColor(modelData.state) }
                            Label {
                                text: modelData.title
                                font.family: Theme.hudFont
                                font.weight: Font.DemiBold
                                font.pixelSize: Theme.fsHeading
                                color: Theme.textPrimary
                            }
                            Item { Layout.fillWidth: true }
                            Badge {
                                text: modelData.state === "ok"   ? "PASS"
                                    : modelData.state === "info" ? "INFO"
                                    : modelData.state === "warn" ? "WARN" : "FAIL"
                                tint: Theme.stateColor(modelData.state)
                            }
                        }
                        Label {
                            text: modelData.detail
                            color: Theme.textSecondary
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                        Label {
                            visible: modelData.fix.length > 0
                            text: (modelData.state === "info" ? "Tip: " : "Fix: ") + modelData.fix
                            color: modelData.state === "info" ? Theme.info : Theme.warn
                            font.family: Theme.bodyFont
                            font.pixelSize: Theme.fsCaption
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}

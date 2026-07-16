import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    spacing: 0

    Component.onCompleted: bridge.runDiagnose()

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: 12
        spacing: 12
        Label {
            text: bridge.diagnostics.length === 0
                  ? "Running functional tests…"
                  : "These tests exercise the actual gaming stack — not just package presence."
            color: Theme.textSecondary
            font.pixelSize: 12
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Button {
            text: "Run again"
            flat: true
            enabled: !bridge.running
            onClicked: bridge.runDiagnose()
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.leftMargin: Theme.pagePadding
        Layout.rightMargin: Theme.pagePadding
        Layout.bottomMargin: Theme.pagePadding
        clip: true
        spacing: 8
        model: bridge.diagnostics

        delegate: Rectangle {
            required property var modelData
            width: list.width
            height: content.height + 28
            radius: Theme.cardRadius
            color: Theme.surface

            ColumnLayout {
                id: content
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 14
                spacing: 4

                RowLayout {
                    spacing: 10
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: Theme.stateColor(modelData.state)
                    }
                    Label {
                        text: modelData.title
                        font.bold: true
                        font.pixelSize: 14
                    }
                    Label {
                        text: modelData.state === "ok"   ? "PASS"
                            : modelData.state === "warn" ? "WARN" : "FAIL"
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        color: Theme.stateColor(modelData.state)
                    }
                    Item { Layout.fillWidth: true }
                }
                Label {
                    text: modelData.detail
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
                Label {
                    visible: modelData.fix.length > 0
                    text: "Fix: " + modelData.fix
                    color: Theme.warn
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }
}

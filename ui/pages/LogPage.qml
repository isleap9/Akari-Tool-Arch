import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import components

ColumnLayout {
    id: page
    signal backRequested()
    spacing: 0

    Flickable {
        id: logFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.margins: Theme.pagePadding
        Layout.topMargin: 8
        contentHeight: logLabel.height
        clip: true

        Rectangle {
            anchors.fill: parent
            color: Theme.surfaceLog
            radius: Theme.cardRadius
            border.width: 1
            border.color: Theme.border
            z: -1
        }
        TextArea {
            id: logLabel
            width: logFlick.width
            readOnly: true
            wrapMode: TextArea.Wrap
            font.family: Theme.monoFont
            font.pixelSize: 12
            color: Theme.textSecondary
            text: bridge.logText
            background: null
            onTextChanged: logFlick.contentY =
                Math.max(0, contentHeight - logFlick.height)
        }
    }

    RowLayout {
        Layout.margins: Theme.pagePadding
        Layout.topMargin: 8
        BusyIndicator {
            running: bridge.running
            visible: bridge.running
            implicitHeight: 28
        }
        Label {
            text: bridge.running ? "Running…" : "Finished."
            color: Theme.textSecondary
        }
        Item { Layout.fillWidth: true }
        Button {
            text: "Back to overview"
            enabled: !bridge.running
            onClicked: page.backRequested()
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Dialog {
    id: dlg
    property var acceptAction: null
    property bool loading: bridge.running

    // openWith("Install linux-zen", "kernel linux-zen", fn)   <- plan from backend
    // openWithText("Install 3 packages", "steam\nlutris", fn) <- caller-provided text
    function openWith(title_, planTarget, action) {
        title = title_
        acceptAction = action
        planArea.usesBridgePlan = true
        bridge.requestPlan(planTarget)
        open()
    }
    function openWithText(title_, text_, action) {
        title = title_
        acceptAction = action
        planArea.usesBridgePlan = false
        planArea.staticText = text_
        open()
    }

    modal: true
    anchors.centerIn: parent
    width: Math.min(560, parent ? parent.width - 80 : 560)
    Material.background: Theme.surface

    background: Rectangle {
        color: Theme.surface
        radius: Theme.cardRadius
        border.width: 1
        border.color: Theme.borderHover
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.animFast }
        NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: Theme.animMed; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.animFast }
    }

    contentItem: ColumnLayout {
        spacing: 12
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(planArea.contentHeight + 24, 320)
            contentHeight: planArea.height
            clip: true
            Rectangle {
                anchors.fill: parent
                color: Theme.surfaceLog
                radius: 6
                border.width: 1
                border.color: Theme.border
                z: -1
            }
            TextArea {
                id: planArea
                property bool usesBridgePlan: true
                property string staticText: ""
                width: parent.width
                readOnly: true
                wrapMode: TextArea.Wrap
                font.family: Theme.monoFont
                font.pixelSize: Theme.fsCaption
                color: Theme.textSecondary
                background: null
                text: usesBridgePlan
                      ? (bridge.planText.length > 0 ? bridge.planText : "Loading plan…")
                      : staticText
            }
        }
        RowLayout {
            Item { Layout.fillWidth: true }
            Button {
                text: "Cancel"
                flat: true
                onClicked: dlg.close()
            }
            Button {
                text: "Proceed"
                highlighted: true
                Material.elevation: 0
                enabled: !dlg.loading
                onClicked: {
                    dlg.close()
                    if (dlg.acceptAction) dlg.acceptAction()
                }
            }
        }
    }
}

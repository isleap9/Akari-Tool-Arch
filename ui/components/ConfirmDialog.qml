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

    contentItem: ColumnLayout {
        spacing: 12
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(planArea.contentHeight + 24, 320)
            contentHeight: planArea.height
            clip: true
            Rectangle { anchors.fill: parent; color: Theme.surfaceLog; radius: 6; z: -1 }
            TextArea {
                id: planArea
                property bool usesBridgePlan: true
                property string staticText: ""
                width: parent.width
                readOnly: true
                wrapMode: TextArea.Wrap
                font.family: "monospace"
                font.pixelSize: 12
                color: "#C8C8C8"
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

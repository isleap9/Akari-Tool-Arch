import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Metric / status card (HUD style).
// Minimal use: title + subtitle + state_. Optional: metric/metricSub big number,
// barSegments [{frac, state}] for the thin segmented bar, actionText for a CTA.
Rectangle {
    id: card
    property string title: ""
    property string subtitle: ""
    property string state_: "unknown"   // ok | info | warn | fail | unknown
    property string actionText: ""
    property bool outlineAction: false  // Maintenance-style full-width outline button
    property bool busy: false
    property string metric: ""
    property string metricSub: ""
    property var barSegments: []        // e.g. [{frac: .8, state: "ok"}, {frac: .2, state: "warn"}]
    signal action()

    Layout.fillWidth: true
    Layout.preferredHeight: inner.implicitHeight + 32
    Layout.fillHeight: true
    Layout.minimumHeight: 148
    radius: Theme.cardRadius
    color: hover.hovered ? Theme.surfaceHover : Theme.surface
    border.width: 1
    border.color: card.state_ === "warn" || card.state_ === "fail"
                  ? Qt.alpha(Theme.stateColor(card.state_), 0.35)
                  : hover.hovered ? Theme.borderHover : Theme.border
    Behavior on color        { ColorAnimation { duration: Theme.animFast } }
    Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    HoverHandler { id: hover }

    ColumnLayout {
        id: inner
        anchors.fill: parent
        anchors.margins: 16
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 8

        RowLayout {
            spacing: 9
            Layout.fillWidth: true
            StatusDot { tint: Theme.stateColor(card.state_) }
            Label {
                text: card.title
                font.family: Theme.hudFont
                font.weight: Font.Bold
                font.pixelSize: Theme.fsHeading
                font.letterSpacing: 0.5
                color: Theme.textPrimary
            }
            Item { Layout.fillWidth: true }
            Badge {
                text: Theme.stateLabel(card.state_)
                tint: Theme.stateColor(card.state_)
            }
        }
        Label {
            text: card.subtitle
            font.family: Theme.monoFont
            font.pixelSize: Theme.fsCaption
            color: Theme.textSecondary
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            Layout.fillWidth: true
            Layout.minimumHeight: 34
        }
        RowLayout {
            visible: card.metric.length > 0
            spacing: 8
            Label {
                text: card.metric
                font.family: Theme.hudFont
                font.weight: Font.Bold
                font.pixelSize: Theme.fsMetric
                color: Theme.textPrimary
            }
            Label {
                text: card.metricSub
                font.family: Theme.monoFont
                font.pixelSize: Theme.fsMicro
                color: Theme.textMuted
                Layout.alignment: Qt.AlignBaseline
            }
        }
        Item { Layout.fillHeight: true }
        // segmented bar
        Rectangle {
            visible: card.barSegments.length > 0
            Layout.fillWidth: true
            height: 6
            radius: 3
            color: Theme.surfaceAlt
            clip: true
            Row {
                anchors.fill: parent
                spacing: 3
                Repeater {
                    model: card.barSegments
                    Rectangle {
                        required property var modelData
                        height: parent.height
                        width: Math.max(0, (parent.width - 3 * (card.barSegments.length - 1))
                                           * modelData.frac)
                        color: Theme.stateColor(modelData.state)
                    }
                }
            }
        }
        PrimaryButton {
            visible: card.actionText.length > 0 && !card.outlineAction
            text: card.actionText.toUpperCase()
            enabled: !card.busy
            implicitHeight: 34
            font.pixelSize: Theme.fsBody
            onClicked: card.action()
        }
        OutlineActionButton {
            visible: card.actionText.length > 0 && card.outlineAction
            text: card.actionText.toUpperCase()
            enabled: !card.busy
            implicitHeight: 34
            Layout.fillWidth: true
            onClicked: card.action()
        }
    }
}

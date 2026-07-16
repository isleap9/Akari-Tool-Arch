pragma Singleton
import QtQuick

QtObject {
    // Brand
    readonly property color accent:      "#E53935"   // Akari red

    // Surfaces
    readonly property color background:  "#111113"
    readonly property color surface:     "#18181B"
    readonly property color surfaceAlt:  "#0C0C0E"   // sidebar / footer
    readonly property color surfaceLog:  "#0A0A0C"
    readonly property color navSelected: "#1B1B1F"
    readonly property color navHover:    "#161619"

    // Text
    readonly property color textPrimary:   "#EDEDED"
    readonly property color textSecondary: "#9A9A9A"
    readonly property color textMuted:     "#666666"
    readonly property color textFaint:     "#555555"

    // Status
    readonly property color ok:      "#43A047"
    readonly property color info:    "#4A9EDD"
    readonly property color warn:    "#FFB300"
    readonly property color fail:    "#E53935"
    readonly property color unknown: "#555555"

    function stateColor(state) {
        return state === "ok"   ? ok
             : state === "info" ? info
             : state === "warn" ? warn
             : state === "fail" ? fail : unknown
    }

    // Metrics
    readonly property int  pagePadding: 28
    readonly property int  cardSpacing: 14
    readonly property int  cardRadius:  8
}

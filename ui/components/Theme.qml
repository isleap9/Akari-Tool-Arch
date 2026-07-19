pragma Singleton
import QtQuick

QtObject {
    // Brand
    readonly property color accent:       "#E84545"   // Akari red (ignition — use sparingly)
    readonly property color accentDim:    "#B03030"
    readonly property color accentHover:  "#F05656"
    readonly property color accentText:   "#F06A6A"
    readonly property color accentGlow:   Qt.alpha("#E84545", 0.12)

    // Fonts (registered in app.py from ui/resources/fonts)
    readonly property string hudFont:  "Rajdhani"
    readonly property string bodyFont: "IBM Plex Sans"
    readonly property string monoFont: "JetBrains Mono"

    // Surfaces — warm near-black, one step per elevation
    readonly property color background:   "#121214"
    readonly property color surface:      "#19191C"
    readonly property color surfaceHover: "#1F1F23"
    readonly property color surfaceDeep:  "#141416"   // gauge inner / gradients
    readonly property color surfaceAlt:   "#0D0D0F"   // sidebar / footer / bar tracks
    readonly property color surfaceLog:   "#0A0A0C"

    // Hairlines
    readonly property color border:       "#26262B"
    readonly property color borderSubtle: "#1A1A1E"   // header/sidebar dividers
    readonly property color borderHover:  "#34343B"
    readonly property color borderFocus:  Qt.alpha("#E84545", 0.55)

    // Nav
    readonly property color navSelected:  "#1D1D22"
    readonly property color navHover:     "#17171B"

    // Text
    readonly property color textPrimary:   "#F0EFED"
    readonly property color textSecondary: "#A3A19E"
    readonly property color textMuted:     "#6B6A67"
    readonly property color textFaint:     "#4E4D4B"
    readonly property color textCode:      "#C8C6C3"   // changelog message text

    // Status
    readonly property color ok:      "#4CAF50"
    readonly property color info:    "#5BA8E5"
    readonly property color warn:    "#F5B133"
    readonly property color fail:    "#E84545"
    readonly property color unknown: "#5A5A5E"

    function stateColor(state) {
        return state === "ok"   ? ok
             : state === "info" ? info
             : state === "warn" ? warn
             : state === "fail" ? fail : unknown
    }
    function stateLabel(state) {
        return state === "ok"   ? "OK"
             : state === "info" ? "INFO"
             : state === "warn" ? "ATTENTION"
             : state === "fail" ? "FAILED" : "CHECKING"
    }

    // Type scale
    readonly property int  fsDisplay:   46   // gauge % / hero numbers
    readonly property int  fsHero:      28   // hero headline
    readonly property int  fsPageTitle: 26
    readonly property int  fsMetric:    30   // big card numbers
    readonly property int  fsTitle:     16
    readonly property int  fsHeading:   15   // card titles
    readonly property int  fsBody:      13
    readonly property int  fsCaption:   12
    readonly property int  fsLabel:     11   // HUD section labels
    readonly property int  fsMicro:     10
    readonly property int  fsBadge:      9
    readonly property real hudLetterSpacing: 2.0

    // Metrics
    readonly property int  pagePadding: 28
    readonly property int  cardSpacing: 14
    readonly property int  cardRadius:  12
    readonly property int  rowRadius:   8
    readonly property int  btnRadius:   7
    readonly property int  animFast:    120
    readonly property int  animMed:     180
}

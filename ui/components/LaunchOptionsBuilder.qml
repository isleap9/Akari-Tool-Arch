import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A set of toggles that builds a launch-options string, and can read an
// existing string back into those toggles.
//
// Lives here rather than inside a page because two places need it: the
// Launch Options page builds a string to copy by hand, and the Games page
// builds one to write straight into a specific game's config.
//
// The round trip is deliberately lossy in one direction only: `load()`
// recognises the options this builder produces and leaves anything else
// alone in `passthrough`, so hand-written flags survive an edit instead of
// being silently dropped.
ColumnLayout {
    id: builder

    // The GPU switch is only meaningful on a hybrid machine, so the page
    // tells us whether to offer it rather than us guessing here.
    property bool offerPrimeOffload: false

    // Anything in the loaded string this builder does not recognise.
    property string passthrough: ""

    readonly property string built: {
        var env = [], wrap = []

        if (swPrime.checked && offerPrimeOffload) {
            env.push("__NV_PRIME_RENDER_OFFLOAD=1")
            env.push("__GLX_VENDOR_LIBRARY_NAME=nvidia")
            env.push("__VK_LAYER_NV_optimus=NVIDIA_only")
        }
        if (swWayland.checked) env.push("PROTON_ENABLE_WAYLAND=1")
        if (swNgx.checked) env.push("PROTON_ENABLE_NGX_UPDATER=1")
        if (passthrough.length > 0) wrap.push(passthrough)
        if (swGamemode.checked) wrap.push("gamemoderun")
        if (swMangohud.checked) wrap.push("mangohud")
        if (swGamescope.checked) {
            var gs = "gamescope"
            if (gsW.text.length > 0 && gsH.text.length > 0)
                gs += " -W " + gsW.text + " -H " + gsH.text
            if (gsFps.text.length > 0) gs += " -r " + gsFps.text
            if (gsFull.checked) gs += " -f"
            gs += " --"
            wrap.push(gs)
        }

        var parts = env.concat(wrap)
        // An empty string means "no launch options", which is a valid and
        // useful thing to apply — don't return a bare %command%.
        if (parts.length === 0) return ""
        parts.push("%command%")
        return parts.join(" ")
    }

    // Set every toggle from an existing launch string.
    function load(options) {
        var s = options || ""
        swPrime.checked   = s.indexOf("__NV_PRIME_RENDER_OFFLOAD") !== -1
        swWayland.checked = s.indexOf("PROTON_ENABLE_WAYLAND") !== -1
        swNgx.checked     = s.indexOf("PROTON_ENABLE_NGX_UPDATER") !== -1
        swGamemode.checked = /(^|\s)gamemoderun(\s|$)/.test(s)
        swMangohud.checked = /(^|\s)mangohud(\s|$)/.test(s)
        swGamescope.checked = /(^|\s)gamescope(\s|$|\s)/.test(s)

        var mw = s.match(/gamescope[^%]*?-W\s+(\d+)/)
        var mh = s.match(/gamescope[^%]*?-H\s+(\d+)/)
        var mr = s.match(/gamescope[^%]*?-r\s+(\d+)/)
        gsW.text = mw ? mw[1] : ""
        gsH.text = mh ? mh[1] : ""
        gsFps.text = mr ? mr[1] : ""
        gsFull.checked = swGamescope.checked ? /gamescope[^%]*?\s-f(\s|$)/.test(s) : true

        // Keep whatever we didn't account for, so applying an edit is not a
        // quiet way to lose someone's hand-tuned flags.
        var known = [
            /__NV_PRIME_RENDER_OFFLOAD=\S*/g, /__GLX_VENDOR_LIBRARY_NAME=\S*/g,
            /__VK_LAYER_NV_optimus=\S*/g, /PROTON_ENABLE_WAYLAND=\S*/g,
            /PROTON_ENABLE_NGX_UPDATER=\S*/g,
            /gamescope(\s+-\S+(\s+\d+)?)*\s+--/g,
            /(^|\s)gamemoderun(?=\s|$)/g, /(^|\s)mangohud(?=\s|$)/g,
            /%command%/g
        ]
        var rest = s
        for (var i = 0; i < known.length; i++) rest = rest.replace(known[i], " ")
        passthrough = rest.replace(/\s+/g, " ").trim()
    }

    function reset() {
        passthrough = ""
        swPrime.checked = false
        swWayland.checked = false
        swNgx.checked = false
        swGamemode.checked = true
        swMangohud.checked = true
        swGamescope.checked = false
        gsW.text = ""; gsH.text = ""; gsFps.text = ""
        gsFull.checked = true
    }

    spacing: 0

    HudSwitch {
        id: swGamemode
        Layout.fillWidth: true
        padding: 12
        title: "GameMode"
        description: "CPU governor & priority while playing"
        checked: true
    }
    HudSwitch {
        id: swMangohud
        Layout.fillWidth: true
        padding: 12
        title: "MangoHud"
        description: "FPS / frametime overlay"
        checked: true
    }
    HudSwitch {
        id: swPrime
        visible: builder.offerPrimeOffload
        Layout.fillWidth: true
        padding: 12
        title: "Render on the NVIDIA GPU"
        description: "Hybrid graphics — send this game to the discrete card"
    }
    HudSwitch {
        id: swWayland
        Layout.fillWidth: true
        padding: 12
        title: "Proton Wayland"
        description: "Native Wayland — better for Hyprland, experimental"
    }
    HudSwitch {
        id: swNgx
        Layout.fillWidth: true
        padding: 12
        title: "DLSS updater"
        description: "Let Proton keep the game's DLSS libraries current"
    }
    HudSwitch {
        id: swGamescope
        Layout.fillWidth: true
        padding: 12
        title: "Gamescope"
        description: "Run in a micro-compositor session"
    }

    GridLayout {
        visible: swGamescope.checked
        columns: 2
        columnSpacing: 12
        rowSpacing: 8
        Layout.leftMargin: 58
        Layout.bottomMargin: 10
        Layout.topMargin: 2

        Label {
            text: "Resolution"
            color: Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsCaption
        }
        RowLayout {
            TextField {
                id: gsW
                placeholderText: "2560"
                font.family: Theme.monoFont
                validator: IntValidator { bottom: 1 }
                Layout.preferredWidth: 78
            }
            Label { text: "\u00D7"; color: Theme.textSecondary }
            TextField {
                id: gsH
                placeholderText: "1440"
                font.family: Theme.monoFont
                validator: IntValidator { bottom: 1 }
                Layout.preferredWidth: 78
            }
        }
        Label {
            text: "FPS limit"
            color: Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsCaption
        }
        TextField {
            id: gsFps
            placeholderText: "e.g. 144"
            font.family: Theme.monoFont
            validator: IntValidator { bottom: 1 }
            Layout.preferredWidth: 78
        }
        Label {
            text: "Fullscreen"
            color: Theme.textSecondary
            font.family: Theme.bodyFont
            font.pixelSize: Theme.fsCaption
        }
        CheckBox { id: gsFull; checked: true }
    }

    // Surfaced rather than hidden: someone who put a custom flag in Steam
    // deserves to see that Akari is preserving it, not wonder where it went.
    Label {
        visible: builder.passthrough.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.bottomMargin: 10
        text: "Keeping your existing flags: " + builder.passthrough
        font.family: Theme.monoFont
        font.pixelSize: Theme.fsMicro
        color: Theme.textMuted
        wrapMode: Text.Wrap
    }
}

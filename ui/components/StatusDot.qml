import QtQuick

// Status dot with a soft glow halo (no shader effects needed)
Item {
    id: dot
    property color tint: Theme.unknown
    width: 9; height: 9

    Rectangle {   // glow halo
        anchors.centerIn: parent
        width: 21; height: 21; radius: 10.5
        color: Qt.alpha(dot.tint, 0.18)
    }
    Rectangle {
        anchors.centerIn: parent
        width: 9; height: 9; radius: 4.5
        color: dot.tint
    }
}

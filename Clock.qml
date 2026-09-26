import Quickshell
import QtQuick

Text {
    text: Qt.formatDateTime(clock.date, "hh:mm")
    color: "#ffffff"

    font {
        family: "SF Mono"
        letterSpacing: -1
        pixelSize: 19
        weight: 600
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
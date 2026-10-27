import Quickshell
import QtQuick
import Qt.labs.folderlistmodel

// Newest file in ~/Pictures/Screenshots. FolderListModel watches the
// folder itself (no polling process). Only a file newer than the last one
// counts, so deleting the newest screenshot doesn't announce an older one;
// a short settle delay lets the screenshot tool finish writing it first.
Item {
    id: screenshotMonitor

    readonly property string latestPath: _latestPath
    property string _latestPath: ""
    property real _latestMs: 0

    FolderListModel {
        id: folder
        folder: "file://" + Quickshell.env("HOME") + "/Pictures/Screenshots"
        showDirs: false
        sortField: FolderListModel.Time
        onCountChanged: settle.restart()
    }

    Timer {
        id: settle
        interval: 150
        onTriggered: {
            if (folder.count === 0) return
            const ms = folder.get(0, "fileModified").getTime()
            if (ms <= screenshotMonitor._latestMs) return
            screenshotMonitor._latestMs = ms
            screenshotMonitor._latestPath = folder.get(0, "filePath")
        }
    }
}

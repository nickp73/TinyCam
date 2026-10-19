import QtQuick
import Quickshell.Io

QtObject {
    id: root

    property string preferredDevice: ""
    property string devicePath: ""
    property bool isReady: false
    property string errorMessage: ""
    property var state: ({})

    function resetConnection(message) {
        isReady = false
        devicePath = ""
        state = ({})
        errorMessage = message
    }

    property Process backend: Process {
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("tinycam_backend.py").toString().replace(/^file:\/\//, "")),
                  "--device", root.preferredDevice]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    const msg = JSON.parse(data)
                    const wasReady = root.isReady
                    if (msg.connected !== undefined) root.isReady = msg.connected === true
                    if (msg.device !== undefined) root.devicePath = msg.device
                    if (msg.state !== undefined) root.state = msg.state
                    if (msg.status === "error") root.errorMessage = msg.message || "Camera command failed"
                    // Polling should not immediately erase a rejected command's error.
                    else if (!wasReady || msg.action !== "sync") root.errorMessage = ""
                } catch (error) {
                    root.errorMessage = "Invalid response from camera controller"
                }
            }
        }
        stderr: SplitParser {
            onRead: data => { root.errorMessage = data }
        }
        onExited: function(exitCode) {
            root.resetConnection("Camera controller stopped (" + exitCode + "); retrying…")
        }
        onRunningChanged: {
            if (!running) root.resetConnection("Camera controller unavailable; retrying…")
        }
    }

    property Timer connectionTimer: Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.syncState()
    }

    onPreferredDeviceChanged: {
        resetConnection("")
        if (backend && backend.running) backend.running = false
    }

    function sendCommand(command) {
        if (!isReady || !backend.running) return
        backend.write(JSON.stringify(command) + "\n")
    }

    function applyPreset(name) { sendCommand({ action: "preset_apply", name: name }) }
    function savePreset(name) { sendCommand({ action: "preset_save", name: name }) }
    function setControl(name, value) {
        sendCommand({ action: "set", ctrl: name, value: Math.round(value) })
    }
    function setPanTilt(pan, tilt) {
        sendCommand({ action: "set_pt", pan: Math.round(pan), tilt: Math.round(tilt) })
    }
    function syncState() {
        if (!backend.running) backend.running = true
        else backend.write(JSON.stringify({ action: "sync" }) + "\n")
    }
    function retry() {
        errorMessage = ""
        syncState()
    }

    Component.onCompleted: syncState()
}

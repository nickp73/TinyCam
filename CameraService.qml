import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool isReady: false
    property var state: ({
        pan_absolute: 0,
        tilt_absolute: 0,
        zoom_absolute: 0,
        focus_automatic_continuous: 1,
        focus_absolute: 37,
        auto_exposure: 0,
        exposure_time_absolute: 330,
        gain: 20,
        white_balance_automatic: 0,
        white_balance_temperature: 5000,
        brightness: 32,
        contrast: 53,
        saturation: 69,
        sharpness: 44,
        backlight_compensation: 11
    })

    property Process backend: Process {
        command: ["python3", Qt.resolvedUrl("tinycam_backend.py").toString().replace("file://", "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    let msg = JSON.parse(data);
                    if (msg.status === "ready") root.isReady = true;
                    if (msg.state) root.state = msg.state;
                } catch(e) {}
            }
        }
    }

    function sendCommand(cmdObj) {
        if (backend.running) {
            backend.write(JSON.stringify(cmdObj) + "\n");
        }
    }

    function applyPreset(name) {
        sendCommand({ action: "preset_apply", name: name });
    }

    function savePreset(name) {
        sendCommand({ action: "preset_save", name: name });
    }

    function setControl(ctrlName, val) {
        let next = Object.assign({}, root.state);
        next[ctrlName] = Math.round(val);
        root.state = next;
        sendCommand({ action: "set", ctrl: ctrlName, value: Math.round(val) });
    }

    function setPanTilt(pan, tilt) {
        let next = Object.assign({}, root.state);
        next.pan_absolute = Math.round(pan);
        next.tilt_absolute = Math.round(tilt);
        root.state = next;
        sendCommand({ action: "set_pt", pan: Math.round(pan), tilt: Math.round(tilt) });
    }

    function syncState() {
        sendCommand({ action: "sync" });
    }

    Component.onCompleted: backend.running = true
}
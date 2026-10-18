import QtQuick
import QtQuick.Controls as QQC
import QtMultimedia
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.nickp73.tinycam"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int activeTab: 0 // 0: Gimbal & Focus, 1: Color & Kelvin, 2: Exposure & HDR
  property bool showGrid: true

  readonly property var cam: hostWidget ? hostWidget.camService : null

  function open() {
    if (cam) cam.syncState()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // Throttle XY pad drags to ~30 Hz for smooth gimbal movement
  Timer {
    id: gimbalThrottle
    interval: 33
    repeat: false
    property int targetPan: 0
    property int targetTilt: 0
    onTriggered: {
      if (root.cam) root.cam.setPanTilt(targetPan, targetTilt)
    }
  }

  function queuePanTilt(pan, tilt) {
    gimbalThrottle.targetPan = Math.max(-468000, Math.min(468000, Math.round(pan / 3600) * 3600))
    gimbalThrottle.targetTilt = Math.max(-288000, Math.min(324000, Math.round(tilt / 3600) * 3600))
    if (!gimbalThrottle.running) gimbalThrottle.start()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(440)
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // 1. Header Bar
        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "📷 TinyCam Studio"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            width: 96
            height: 22
            radius: 11
            color: root.cam && root.cam.isReady ? "#1e3a2f" : "#3a1e28"
            anchors.verticalCenter: parent.verticalCenter
            Text {
              anchors.centerIn: parent
              text: root.cam && root.cam.isReady ? "● Tiny 2 Lite" : "○ Offline"
              color: root.cam && root.cam.isReady ? "#a6e3a1" : "#f38ba8"
              font.pixelSize: 11
            }
          }

          Rectangle {
            width: 72
            height: 24
            radius: 6
            color: root.showGrid ? "#3b82f6" : "#313244"
            anchors.verticalCenter: parent.verticalCenter
            Text {
              anchors.centerIn: parent
              text: root.showGrid ? "Grid: ON" : "Grid: OFF"
              color: "#cdd6f4"
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.showGrid = !root.showGrid
            }
          }
        }

        // 2. Live 16:9 Viewfinder (Releases /dev/video0 when closed)
        Rectangle {
          width: parent.width
          height: Math.round(parent.width * 9 / 16)
          color: "#11111b"
          radius: 8
          border.color: "#313244"
          border.width: 1
          clip: true

          MediaDevices { id: mediaDevices }

          CaptureSession {
            camera: Camera {
              id: camDevice
              active: root.opened
              onActiveChanged: {
                if (active) {
                  let formats = camDevice.cameraDevice.videoFormats
                  for (let i = 0; i < formats.length; i++) {
                    let f = formats[i]
                    if (f.resolution.width === 1280 && f.resolution.height === 720 && f.maxFrameRate >= 30) {
                      camDevice.cameraFormat = f
                      break
                    }
                  }
                }
              }
            }
            videoOutput: viewfinder
          }

          VideoOutput {
            id: viewfinder
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
          }

          // Rule-of-Thirds Framing Overlay
          Item {
            anchors.fill: parent
            visible: root.showGrid
            Rectangle { x: parent.width / 3; y: 0; width: 1; height: parent.height; color: "#40ffffff" }
            Rectangle { x: (parent.width / 3) * 2; y: 0; width: 1; height: parent.height; color: "#40ffffff" }
            Rectangle { x: 0; y: parent.height / 3; width: parent.width; height: 1; color: "#40ffffff" }
            Rectangle { x: 0; y: (parent.height / 3) * 2; width: parent.width; height: 1; color: "#40ffffff" }
          }
        }

        // 3. Quick Presets Bar
        Row {
          width: parent.width
          spacing: 6

          Repeater {
            model: [
              { label: "Face", preset: "Face Center" },
              { label: "Desk", preset: "Desk View" },
              { label: "Wide", preset: "Wide Room" },
              { label: "💤 Stow", preset: "Privacy Sleep" }
            ]
            delegate: Rectangle {
              width: (content.width - 18) / 4
              height: 30
              radius: 6
              color: presetMouse.pressed ? "#3b82f6" : "#313244"
              border.color: "#45475a"
              border.width: 1
              required property var modelData
              Text {
                anchors.centerIn: parent
                text: parent.modelData.label
                color: "#cdd6f4"
                font.pixelSize: 12
                font.bold: true
              }
              MouseArea {
                id: presetMouse
                anchors.fill: parent
                onClicked: if (root.cam) root.cam.applyPreset(parent.modelData.preset)
              }
            }
          }
        }

        // 4. Studio Navigation Tabs (Custom pills - zero property conflict)
        Row {
          width: parent.width
          spacing: 6

          Repeater {
            model: ["Gimbal & Focus", "Color & Kelvin", "Exposure & HDR"]
            delegate: Rectangle {
              width: (content.width - 12) / 3
              height: 28
              radius: 6
              required property int index
              required property string modelData
              color: root.activeTab === index ? "#3b82f6" : "#1e1e2e"
              border.color: root.activeTab === index ? "#89b4fa" : "#45475a"
              border.width: 1
              Text {
                anchors.centerIn: parent
                text: parent.modelData
                color: "#cdd6f4"
                font.pixelSize: 11
                font.bold: root.activeTab === parent.index
              }
              MouseArea {
                anchors.fill: parent
                onClicked: root.activeTab = parent.index
              }
            }
          }
        }

        // ==========================================
        // TAB 0: 2D XY GIMBAL PAD, ZOOM & FOCUS
        // ==========================================
        Column {
          width: parent.width
          spacing: 8
          visible: root.activeTab === 0

          Row {
            width: parent.width
            spacing: 12

            // Interactive 2D XY Gimbal Pad
            Rectangle {
              id: xyPad
              width: 170
              height: 140
              radius: 8
              color: "#181825"
              border.color: "#45475a"
              border.width: 1

              Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: "#313244" }
              Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: "#313244" }

              Rectangle {
                id: puck
                width: 18
                height: 18
                radius: 9
                color: "#89b4fa"
                border.color: "#ffffff"
                border.width: 2

                x: {
                  let pan = root.cam && root.cam.state ? (root.cam.state.pan_absolute || 0) : 0
                  let normX = (pan + 468000) / 936000
                  return Math.max(0, Math.min(xyPad.width - width, normX * (xyPad.width - width)))
                }
                y: {
                  let tilt = root.cam && root.cam.state ? (root.cam.state.tilt_absolute || 0) : 0
                  let normY = (324000 - tilt) / (324000 + 288000)
                  return Math.max(0, Math.min(xyPad.height - height, normY * (xyPad.height - height)))
                }
              }

              MouseArea {
                anchors.fill: parent
                function updateFromMouse(mx, my) {
                  let normX = Math.max(0, Math.min(1, mx / width))
                  let normY = Math.max(0, Math.min(1, my / height))
                  let pan = -468000 + normX * 936000
                  let tilt = 324000 - normY * (324000 + 288000)
                  root.queuePanTilt(pan, tilt)
                }
                onPressed: function(mouse) { updateFromMouse(mouse.x, mouse.y) }
                onPositionChanged: function(mouse) { if (pressed) updateFromMouse(mouse.x, mouse.y) }
                onDoubleClicked: if (root.cam) root.cam.setPanTilt(0, 0)
              }
            }

            // Nudge D-Pad & Coordinates Readout
            Column {
              width: parent.width - 182
              spacing: 6

              Text {
                text: {
                  let p = root.cam && root.cam.state ? Math.round((root.cam.state.pan_absolute || 0) / 3600) : 0
                  let t = root.cam && root.cam.state ? Math.round((root.cam.state.tilt_absolute || 0) / 3600) : 0
                  return "Pan: " + p + "°  |  Tilt: " + t + "°"
                }
                color: root.barForeground
                font.pixelSize: 12
                font.bold: true
              }

              Text {
                text: "Drag pad or double-click to center"
                color: "#a6adc8"
                font.pixelSize: 11
              }

              Row {
                spacing: 4
                Repeater {
                  model: [
                    { lbl: "◀", ctrl: "pan_absolute", step: -18000 },
                    { lbl: "▲", ctrl: "tilt_absolute", step: 18000 },
                    { lbl: "▼", ctrl: "tilt_absolute", step: -18000 },
                    { lbl: "▶", ctrl: "pan_absolute", step: 18000 }
                  ]
                  delegate: Rectangle {
                    width: 40; height: 28; radius: 6; color: "#313244"
                    required property var modelData
                    Text { anchors.centerIn: parent; text: parent.modelData.lbl; color: "#cdd6f4"; font.pixelSize: 12 }
                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        if (root.cam) {
                          let cur = root.cam.state[parent.modelData.ctrl] || 0
                          root.cam.setControl(parent.modelData.ctrl, cur + parent.modelData.step)
                        }
                      }
                    }
                  }
                }
              }

              Rectangle {
                width: parent.width; height: 28; radius: 6; color: "#313244"
                Text { anchors.centerIn: parent; text: "Reset Center (0°, 0°)"; color: "#cdd6f4"; font.pixelSize: 12 }
                MouseArea {
                  anchors.fill: parent
                  onClicked: if (root.cam) root.cam.setPanTilt(0, 0)
                }
              }
            }
          }

          // Digital Zoom Slider
          Column {
            width: parent.width
            spacing: 2
            Text {
              text: "Digital Zoom: " + (root.cam && root.cam.state ? (root.cam.state.zoom_absolute || 0) : 0) + "%"
              color: root.barForeground
              font.pixelSize: 12
            }
            QQC.Slider {
              width: parent.width
              from: 0; to: 100
              value: root.cam && root.cam.state ? (root.cam.state.zoom_absolute || 0) : 0
              onMoved: if (root.cam) root.cam.setControl("zoom_absolute", value)
            }
          }

          // Auto / Manual Focus Controls
          QQC.CheckBox {
            id: afCheck
            text: "Continuous Autofocus"
            checked: root.cam && root.cam.state ? (root.cam.state.focus_automatic_continuous === 1) : true
            onToggled: if (root.cam) root.cam.setControl("focus_automatic_continuous", checked ? 1 : 0)
          }

          Column {
            width: parent.width
            spacing: 2
            opacity: afCheck.checked ? 0.4 : 1.0
            enabled: !afCheck.checked
            Text {
              text: "Manual Focus Distance: " + (root.cam && root.cam.state ? (root.cam.state.focus_absolute || 0) : 0)
              color: root.barForeground
              font.pixelSize: 12
            }
            QQC.Slider {
              width: parent.width
              from: 0; to: 100
              value: root.cam && root.cam.state ? (root.cam.state.focus_absolute || 37) : 37
              onMoved: if (root.cam) root.cam.setControl("focus_absolute", value)
            }
          }
        }

        // ==========================================
        // TAB 1: COLOR & KELVIN WHITE BALANCE
        // ==========================================
        Column {
          width: parent.width
          spacing: 6
          visible: root.activeTab === 1

          QQC.CheckBox {
            id: awbCheck
            text: "Auto White Balance (AWB)"
            checked: root.cam && root.cam.state ? (root.cam.state.white_balance_automatic === 1) : false
            onToggled: if (root.cam) root.cam.setControl("white_balance_automatic", checked ? 1 : 0)
          }

          Column {
            width: parent.width
            spacing: 2
            opacity: awbCheck.checked ? 0.4 : 1.0
            enabled: !awbCheck.checked
            Text {
              text: "Color Temperature: " + (root.cam && root.cam.state ? (root.cam.state.white_balance_temperature || 5000) : 5000) + " K"
              color: root.barForeground
              font.pixelSize: 12
            }
            QQC.Slider {
              width: parent.width
              from: 2000; to: 10000; stepSize: 100
              value: root.cam && root.cam.state ? (root.cam.state.white_balance_temperature || 5000) : 5000
              onMoved: if (root.cam) root.cam.setControl("white_balance_temperature", value)
            }
          }

          Column {
            width: parent.width; spacing: 2
            Text { text: "Brightness: " + (root.cam && root.cam.state ? (root.cam.state.brightness || 32) : 32); color: root.barForeground; font.pixelSize: 12 }
            QQC.Slider {
              width: parent.width; from: 0; to: 100
              value: root.cam && root.cam.state ? (root.cam.state.brightness || 32) : 32
              onMoved: if (root.cam) root.cam.setControl("brightness", value)
            }
          }

          Column {
            width: parent.width; spacing: 2
            Text { text: "Contrast: " + (root.cam && root.cam.state ? (root.cam.state.contrast || 53) : 53); color: root.barForeground; font.pixelSize: 12 }
            QQC.Slider {
              width: parent.width; from: 0; to: 100
              value: root.cam && root.cam.state ? (root.cam.state.contrast || 53) : 53
              onMoved: if (root.cam) root.cam.setControl("contrast", value)
            }
          }

          Column {
            width: parent.width; spacing: 2
            Text { text: "Saturation: " + (root.cam && root.cam.state ? (root.cam.state.saturation || 69) : 69); color: root.barForeground; font.pixelSize: 12 }
            QQC.Slider {
              width: parent.width; from: 0; to: 100
              value: root.cam && root.cam.state ? (root.cam.state.saturation || 69) : 69
              onMoved: if (root.cam) root.cam.setControl("saturation", value)
            }
          }

          Column {
            width: parent.width; spacing: 2
            Text { text: "Sharpness: " + (root.cam && root.cam.state ? (root.cam.state.sharpness || 44) : 44); color: root.barForeground; font.pixelSize: 12 }
            QQC.Slider {
              width: parent.width; from: 0; to: 100
              value: root.cam && root.cam.state ? (root.cam.state.sharpness || 44) : 44
              onMoved: if (root.cam) root.cam.setControl("sharpness", value)
            }
          }
        }

        // ==========================================
        // TAB 2: EXPOSURE, GAIN & BACKLIGHT/HDR
        // ==========================================
        Column {
          width: parent.width
          spacing: 6
          visible: root.activeTab === 2

          QQC.CheckBox {
            id: aeCheck
            text: "Auto Exposure"
            checked: root.cam && root.cam.state ? (root.cam.state.auto_exposure === 0) : true
            onToggled: if (root.cam) root.cam.setControl("auto_exposure", checked ? 0 : 1)
          }

          Column {
            width: parent.width
            spacing: 2
            opacity: aeCheck.checked ? 0.4 : 1.0
            enabled: !aeCheck.checked
            Text {
              text: "Manual Shutter / Exposure Time: " + (root.cam && root.cam.state ? (root.cam.state.exposure_time_absolute || 330) : 330)
              color: root.barForeground
              font.pixelSize: 12
            }
            QQC.Slider {
              width: parent.width
              from: 1; to: 2500
              value: root.cam && root.cam.state ? (root.cam.state.exposure_time_absolute || 330) : 330
              onMoved: if (root.cam) root.cam.setControl("exposure_time_absolute", value)
            }
          }

          Column {
            width: parent.width; spacing: 2
            Text {
              text: "Sensor Gain (ISO): " + (root.cam && root.cam.state ? (root.cam.state.gain || 20) : 20)
              color: root.barForeground
              font.pixelSize: 12
            }
            QQC.Slider {
              width: parent.width; from: 1; to: 64
              value: root.cam && root.cam.state ? (root.cam.state.gain || 20) : 20
              onMoved: if (root.cam) root.cam.setControl("gain", value)
            }
          }

          Column {
            width: parent.width; spacing: 2
            Text {
              text: "Backlight Compensation (HDR): " + (root.cam && root.cam.state ? (root.cam.state.backlight_compensation || 11) : 11)
              color: root.barForeground
              font.pixelSize: 12
            }
            QQC.Slider {
              width: parent.width; from: 0; to: 18; stepSize: 1
              value: root.cam && root.cam.state ? (root.cam.state.backlight_compensation || 11) : 11
              onMoved: if (root.cam) root.cam.setControl("backlight_compensation", value)
            }
          }
        }
      }
    }
  }
}
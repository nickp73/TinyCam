import QtQuick
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
  property int activeTab: 0
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

  // Reusable pure-QML Slider component (zero QtQuick.Controls dependency)
  component StudioSlider: Column {
    id: sliderRoot
    width: parent.width
    spacing: 4
    property string label: ""
    property real minVal: 0
    property real maxVal: 100
    property real stepVal: 1
    property real currentVal: 50
    signal valueEdited(int newVal)

    Text {
      text: sliderRoot.label + ": " + Math.round(sliderRoot.currentVal)
      color: root.barForeground
      font.pixelSize: 12
    }

    Rectangle {
      id: track
      width: parent.width
      height: 18
      radius: 9
      color: "#181825"
      border.color: "#45475a"
      border.width: 1

      Rectangle {
        width: {
          let ratio = (sliderRoot.currentVal - sliderRoot.minVal) / Math.max(1, (sliderRoot.maxVal - sliderRoot.minVal))
          return Math.max(14, Math.min(track.width, ratio * track.width))
        }
        height: parent.height
        radius: 9
        color: "#3b82f6"
      }

      MouseArea {
        anchors.fill: parent
        function updateVal(mx) {
          let ratio = Math.max(0, Math.min(1, mx / track.width))
          let raw = sliderRoot.minVal + ratio * (sliderRoot.maxVal - sliderRoot.minVal)
          let stepped = Math.round(raw / sliderRoot.stepVal) * sliderRoot.stepVal
          sliderRoot.valueEdited(stepped)
        }
        onPressed: function(mouse) { updateVal(mouse.x) }
        onPositionChanged: function(mouse) { if (pressed) updateVal(mouse.x) }
      }
    }
  }

  // Reusable pure-QML Button pill
  component StudioButton: Rectangle {
    id: btnRoot
    height: 30
    radius: 6
    property string text: ""
    property bool active: false
    signal clicked()
    color: btnMouse.pressed ? "#2563eb" : (active ? "#3b82f6" : "#313244")
    border.color: active ? "#89b4fa" : "#45475a"
    border.width: 1

    Text {
      anchors.centerIn: parent
      text: btnRoot.text
      color: "#cdd6f4"
      font.pixelSize: 12
      font.bold: btnRoot.active
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      onClicked: btnRoot.clicked()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
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
          spacing: 8

          Text {
            text: "📷 TinyCam Studio"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          StudioButton {
            width: 80
            height: 24
            text: root.showGrid ? "Grid: ON" : "Grid: OFF"
            active: root.showGrid
            onClicked: root.showGrid = !root.showGrid
          }
        }

        // 2. Live 16:9 Viewfinder
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
            }
            videoOutput: viewfinder
          }

          VideoOutput {
            id: viewfinder
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
          }

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

          StudioButton {
            width: (parent.width - 18) / 4
            text: "Face"
            onClicked: if (root.cam) root.cam.applyPreset("Face Center")
          }
          StudioButton {
            width: (parent.width - 18) / 4
            text: "Desk"
            onClicked: if (root.cam) root.cam.applyPreset("Desk View")
          }
          StudioButton {
            width: (parent.width - 18) / 4
            text: "Wide"
            onClicked: if (root.cam) root.cam.applyPreset("Wide Room")
          }
          StudioButton {
            width: (parent.width - 18) / 4
            text: "💤 Stow"
            onClicked: if (root.cam) root.cam.applyPreset("Privacy Sleep")
          }
        }

        // 4. Studio Navigation Tabs
        Row {
          width: parent.width
          spacing: 6

          StudioButton {
            width: (parent.width - 12) / 3
            text: "Gimbal & Focus"
            active: root.activeTab === 0
            onClicked: root.activeTab = 0
          }
          StudioButton {
            width: (parent.width - 12) / 3
            text: "Color & Kelvin"
            active: root.activeTab === 1
            onClicked: root.activeTab = 1
          }
          StudioButton {
            width: (parent.width - 12) / 3
            text: "Exposure & HDR"
            active: root.activeTab === 2
            onClicked: root.activeTab = 2
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

            Rectangle {
              id: xyPad
              width: 160
              height: 130
              radius: 8
              color: "#181825"
              border.color: "#45475a"
              border.width: 1

              Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: "#313244" }
              Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: "#313244" }

              Rectangle {
                id: puck
                width: 16
                height: 16
                radius: 8
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

            Column {
              width: parent.width - 172
              spacing: 6

              Text {
                text: {
                  let p = root.cam && root.cam.state ? Math.round((root.cam.state.pan_absolute || 0) / 3600) : 0
                  let t = root.cam && root.cam.state ? Math.round((root.cam.state.tilt_absolute || 0) / 3600) : 0
                  return "Pan: " + p + "° | Tilt: " + t + "°"
                }
                color: root.barForeground
                font.pixelSize: 12
                font.bold: true
              }

              Row {
                spacing: 4
                StudioButton {
                  width: 36; text: "◀"
                  onClicked: if (root.cam) root.cam.setControl("pan_absolute", (root.cam.state.pan_absolute || 0) - 18000)
                }
                StudioButton {
                  width: 36; text: "▲"
                  onClicked: if (root.cam) root.cam.setControl("tilt_absolute", (root.cam.state.tilt_absolute || 0) + 18000)
                }
                StudioButton {
                  width: 36; text: "▼"
                  onClicked: if (root.cam) root.cam.setControl("tilt_absolute", (root.cam.state.tilt_absolute || 0) - 18000)
                }
                StudioButton {
                  width: 36; text: "▶"
                  onClicked: if (root.cam) root.cam.setControl("pan_absolute", (root.cam.state.pan_absolute || 0) + 18000)
                }
              }

              StudioButton {
                width: parent.width
                text: "Center (0°, 0°)"
                onClicked: if (root.cam) root.cam.setPanTilt(0, 0)
              }
            }
          }

          StudioSlider {
            label: "Digital Zoom (%)"
            minVal: 0; maxVal: 100; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.zoom_absolute || 0) : 0
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("zoom_absolute", v) }
          }

          StudioButton {
            width: parent.width
            property bool afOn: root.cam && root.cam.state ? (root.cam.state.focus_automatic_continuous === 1) : true
            text: afOn ? "Autofocus: ON (Click for Manual)" : "Autofocus: OFF (Manual Mode)"
            active: afOn
            onClicked: if (root.cam) root.cam.setControl("focus_automatic_continuous", afOn ? 0 : 1)
          }

          StudioSlider {
            label: "Manual Focus"
            minVal: 0; maxVal: 100; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.focus_absolute || 37) : 37
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("focus_absolute", v) }
          }
        }

        // ==========================================
        // TAB 1: COLOR & KELVIN WHITE BALANCE
        // ==========================================
        Column {
          width: parent.width
          spacing: 8
          visible: root.activeTab === 1

          StudioButton {
            width: parent.width
            property bool awbOn: root.cam && root.cam.state ? (root.cam.state.white_balance_automatic === 1) : false
            text: awbOn ? "Auto White Balance: ON" : "Auto White Balance: OFF (Manual Kelvin)"
            active: awbOn
            onClicked: if (root.cam) root.cam.setControl("white_balance_automatic", awbOn ? 0 : 1)
          }

          StudioSlider {
            label: "White Balance (K)"
            minVal: 2000; maxVal: 10000; stepVal: 100
            currentVal: root.cam && root.cam.state ? (root.cam.state.white_balance_temperature || 5000) : 5000
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("white_balance_temperature", v) }
          }

          StudioSlider {
            label: "Brightness"
            minVal: 0; maxVal: 100; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.brightness || 32) : 32
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("brightness", v) }
          }

          StudioSlider {
            label: "Contrast"
            minVal: 0; maxVal: 100; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.contrast || 53) : 53
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("contrast", v) }
          }

          StudioSlider {
            label: "Saturation"
            minVal: 0; maxVal: 100; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.saturation || 69) : 69
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("saturation", v) }
          }

          StudioSlider {
            label: "Sharpness"
            minVal: 0; maxVal: 100; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.sharpness || 44) : 44
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("sharpness", v) }
          }
        }

        // ==========================================
        // TAB 2: EXPOSURE, GAIN & BACKLIGHT/HDR
        // ==========================================
        Column {
          width: parent.width
          spacing: 8
          visible: root.activeTab === 2

          StudioButton {
            width: parent.width
            property bool aeOn: root.cam && root.cam.state ? (root.cam.state.auto_exposure === 0) : true
            text: aeOn ? "Auto Exposure: ON" : "Auto Exposure: OFF (Manual Shutter)"
            active: aeOn
            onClicked: if (root.cam) root.cam.setControl("auto_exposure", aeOn ? 1 : 0)
          }

          StudioSlider {
            label: "Shutter / Exposure Time"
            minVal: 1; maxVal: 2500; stepVal: 10
            currentVal: root.cam && root.cam.state ? (root.cam.state.exposure_time_absolute || 330) : 330
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("exposure_time_absolute", v) }
          }

          StudioSlider {
            label: "Sensor Gain (ISO)"
            minVal: 1; maxVal: 64; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.gain || 20) : 20
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("gain", v) }
          }

          StudioSlider {
            label: "Backlight Compensation (HDR)"
            minVal: 0; maxVal: 18; stepVal: 1
            currentVal: root.cam && root.cam.state ? (root.cam.state.backlight_compensation || 11) : 11
            onValueEdited: function(v) { if (root.cam) root.cam.setControl("backlight_compensation", v) }
          }
        }
      }
    }
  }
}
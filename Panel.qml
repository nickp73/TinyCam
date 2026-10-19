import QtQuick
import QtMultimedia
import qs.Commons
import qs.Commons as Commons
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

  readonly property bool cameraReady: cam !== null && cam.isReady
  readonly property var previewDevice: {
    if (!cameraReady || !cam.devicePath) return null
    const inputs = mediaDevices.videoInputs
    for (let i = 0; i < inputs.length; ++i) {
      if (inputs[i].id.toString() === cam.devicePath) return inputs[i]
    }
    return null
  }

  function value(name, fallback) {
    const current = cam && cam.state ? cam.state[name] : undefined
    return current === undefined ? fallback : current
  }

  function ensureVisible(item) {
    // Let column layout settle after a tab or enabled-state change.
    Qt.callLater(root.scrollToControl, item)
  }

  function scrollToControl(item) {
    if (!item || !item.activeFocus) return
    for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
      if (typeof ancestor.forceLayout === "function") ancestor.forceLayout()
      if (ancestor === content) break
    }
    const point = item.mapToItem(content, 0, 0)
    if (point.y < scroller.contentY) scroller.contentY = point.y
    else if (point.y + item.height > scroller.contentY + scroller.height)
      scroller.contentY = point.y + item.height - scroller.height
    scroller.returnToBounds()
  }

  function focusNext(direction) {
    const controls = []
    function visit(item) {
      if (!item.visible || !item.enabled) return
      if (item.keyboardControl === true) controls.push(item)
      for (let i = 0; i < item.children.length; ++i) visit(item.children[i])
    }
    visit(content)
    if (!controls.length) return
    let index = controls.findIndex(item => item.activeFocus)
    index = index < 0 ? (direction > 0 ? 0 : controls.length - 1)
                     : (index + direction + controls.length) % controls.length
    controls[index].forceActiveFocus(Qt.TabFocusReason)
    ensureVisible(controls[index])
  }

  function handleNavigation(event) {
    if (event.key === Qt.Key_Escape) root.close()
    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      const direction = (event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1
      if (event.modifiers & Qt.ControlModifier) root.switchPanel(direction)
      else root.focusNext(direction)
    } else return false
    event.accepted = true
    return true
  }

  function open() {
    if (cam) cam.syncState()
    root.controller.show()
  }

  function close() {
    gimbalThrottle.stop()
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

  component StudioSlider: Column {
    id: sliderRoot
    width: parent.width
    spacing: Style.space(4)
    property bool keyboardControl: true
    property string label: ""
    property real minVal: 0
    property real maxVal: 100
    property real stepVal: 1
    property real currentVal: 50
    signal valueEdited(int newVal)
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.Slider
    Accessible.name: label
    onActiveFocusChanged: if (activeFocus) root.ensureVisible(sliderRoot)

    function editValue(value) {
      const stepped = minVal + Math.round((value - minVal) / stepVal) * stepVal
      valueEdited(Math.max(minVal, Math.min(maxVal, stepped)))
    }
    Keys.onPressed: function(event) {
      if (root.handleNavigation(event)) return
      if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) editValue(currentVal - stepVal)
      else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) editValue(currentVal + stepVal)
      else if (event.key === Qt.Key_Home) editValue(minVal)
      else if (event.key === Qt.Key_End) editValue(maxVal)
      else { event.accepted = false; return }
      event.accepted = true
    }

    Text {
      text: sliderRoot.label + ": " + Math.round(sliderRoot.currentVal)
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Rectangle {
      id: track
      width: parent.width
      height: Style.space(18)
      radius: height / 2
      color: Style.normalFill
      border.color: sliderRoot.activeFocus ? Commons.Color.accent : Commons.Color.muted
      border.width: sliderRoot.activeFocus ? Style.space(2) : Style.space(1)

      Rectangle {
        x: Style.space(3)
        width: {
          const ratio = (sliderRoot.currentVal - sliderRoot.minVal) / Math.max(1, sliderRoot.maxVal - sliderRoot.minVal)
          return Math.max(0, Math.min(1, ratio)) * (track.width - Style.space(6))
        }
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - Style.space(6)
        radius: height / 2
        color: Commons.Color.accent
      }

      MouseArea {
        anchors.fill: parent
        function updateVal(mx) {
          const ratio = Math.max(0, Math.min(1, mx / track.width))
          sliderRoot.editValue(sliderRoot.minVal + ratio * (sliderRoot.maxVal - sliderRoot.minVal))
        }
        onPressed: function(mouse) {
          sliderRoot.forceActiveFocus(Qt.MouseFocusReason)
          updateVal(mouse.x)
        }
        onPositionChanged: function(mouse) { if (pressed) updateVal(mouse.x) }
      }
    }
  }

  component StudioButton: Rectangle {
    id: btnRoot
    height: Style.space(30)
    radius: Math.min(Style.space(6), Style.cornerRadius)
    property bool keyboardControl: true
    property string text: ""
    property bool active: false
    signal clicked()
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: if (enabled) clicked()
    onActiveFocusChanged: if (activeFocus) root.ensureVisible(btnRoot)
    color: btnMouse.pressed ? Style.pressedFill
         : active ? Style.selectedAccentFill
         : Style.controlFill(activeFocus, btnMouse.containsMouse, Commons.Color.popups.text, Commons.Color.accent)
    border.color: activeFocus || active ? Commons.Color.accent : Commons.Color.muted
    border.width: activeFocus ? Style.space(2) : Style.space(1)
    Keys.onPressed: function(event) {
      if (root.handleNavigation(event)) return
      if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        if (!event.isAutoRepeat) clicked()
        event.accepted = true
      } else event.accepted = false
    }

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: btnRoot.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: btnRoot.active
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {
        btnRoot.forceActiveFocus(Qt.MouseFocusReason)
        btnRoot.clicked()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: gridButton
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        event.accepted = root.handleNavigation(event)
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

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
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            StudioButton {
              id: gridButton
              width: Style.space(80)
              height: Style.space(24)
              text: root.showGrid ? "Grid: ON" : "Grid: OFF"
              active: root.showGrid
              onClicked: root.showGrid = !root.showGrid
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              width: parent.width - retryButton.width - parent.spacing
              text: root.cam && root.cam.errorMessage ? root.cam.errorMessage
                  : root.cameraReady ? "Connected · " + root.cam.devicePath : "Waiting for OBSBOT Tiny 2 Lite…"
              color: root.cam && root.cam.errorMessage ? Commons.Color.urgent : Commons.Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
            StudioButton {
              id: retryButton
              width: Style.space(60)
              text: "Retry"
              onClicked: if (root.cam) root.cam.retry()
            }
          }

          Text {
            width: parent.width
            text: "Tab: next control · Arrows: adjust · Enter/Space: activate · Ctrl+Tab: next panel · Esc: close"
            color: Commons.Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          // 2. Live 16:9 Viewfinder
          Rectangle {
            width: parent.width
            height: Math.round(parent.width * 9 / 16)
            color: Commons.Color.background
            radius: Style.space(8)
            border.color: Commons.Color.muted
            border.width: Style.space(1)
            clip: true

            MediaDevices { id: mediaDevices }

            CaptureSession {
              camera: Camera {
                id: camDevice
                cameraDevice: root.previewDevice || mediaDevices.defaultVideoInput
                active: root.opened && root.previewDevice !== null
              }
              videoOutput: viewfinder
            }

            VideoOutput {
              id: viewfinder
              anchors.fill: parent
              fillMode: VideoOutput.PreserveAspectFit
            }

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              text: !root.cameraReady ? "Camera unavailable"
                  : !root.previewDevice ? "Selected camera is not available for preview"
                  : camDevice.error !== Camera.NoError ? camDevice.errorString : ""
              visible: text !== ""
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
            }

            Item {
              anchors.fill: parent
              visible: root.showGrid && camDevice.active
              Rectangle { x: parent.width / 3; y: 0; width: Style.space(1); height: parent.height; color: Util.alpha(Commons.Color.popups.text, 0.3) }
              Rectangle { x: (parent.width / 3) * 2; y: 0; width: Style.space(1); height: parent.height; color: Util.alpha(Commons.Color.popups.text, 0.3) }
              Rectangle { x: 0; y: parent.height / 3; width: parent.width; height: Style.space(1); color: Util.alpha(Commons.Color.popups.text, 0.3) }
              Rectangle { x: 0; y: (parent.height / 3) * 2; width: parent.width; height: Style.space(1); color: Util.alpha(Commons.Color.popups.text, 0.3) }
            }
          }

          // 3. Quick Presets Bar
          Row {
            enabled: root.cameraReady
            width: parent.width
            spacing: Style.space(6)

            StudioButton {
              width: (parent.width - Style.space(18)) / 4
              text: "Face"
              onClicked: if (root.cam) root.cam.applyPreset("Face Center")
            }
            StudioButton {
              width: (parent.width - Style.space(18)) / 4
              text: "Desk"
              onClicked: if (root.cam) root.cam.applyPreset("Desk View")
            }
            StudioButton {
              width: (parent.width - Style.space(18)) / 4
              text: "Wide"
              onClicked: if (root.cam) root.cam.applyPreset("Wide Room")
            }
            StudioButton {
              width: (parent.width - Style.space(18)) / 4
              text: "💤 Stow"
              onClicked: if (root.cam) root.cam.applyPreset("Privacy Sleep")
            }
          }

          // 4. Studio Navigation Tabs
          Row {
            width: parent.width
            spacing: Style.space(6)

            StudioButton {
              width: (parent.width - Style.space(12)) / 3
              text: "Gimbal & Focus"
              active: root.activeTab === 0
              onClicked: root.activeTab = 0
            }
            StudioButton {
              width: (parent.width - Style.space(12)) / 3
              text: "Color & Kelvin"
              active: root.activeTab === 1
              onClicked: root.activeTab = 1
            }
            StudioButton {
              width: (parent.width - Style.space(12)) / 3
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
            spacing: Style.space(8)
            visible: root.activeTab === 0
            enabled: root.cameraReady

            Row {
              width: parent.width
              spacing: Style.space(12)

              Rectangle {
                id: xyPad
                property bool keyboardControl: true
                activeFocusOnTab: true
                Accessible.role: Accessible.Slider
                Accessible.name: "Pan and tilt. Arrow keys adjust; Home centers."
                onActiveFocusChanged: if (activeFocus) root.ensureVisible(xyPad)
                Keys.onPressed: function(event) {
                  if (root.handleNavigation(event)) return
                  let pan = root.value("pan_absolute", 0)
                  let tilt = root.value("tilt_absolute", 0)
                  if (event.key === Qt.Key_Left) pan -= 18000
                  else if (event.key === Qt.Key_Right) pan += 18000
                  else if (event.key === Qt.Key_Up) tilt += 18000
                  else if (event.key === Qt.Key_Down) tilt -= 18000
                  else if (event.key === Qt.Key_Home) { pan = 0; tilt = 0 }
                  else { event.accepted = false; return }
                  root.queuePanTilt(pan, tilt)
                  event.accepted = true
                }
                width: Style.space(160)
                height: Style.space(130)
                radius: Style.space(8)
                color: Style.normalFill
                border.color: activeFocus ? Commons.Color.accent : Commons.Color.muted
                border.width: activeFocus ? Style.space(2) : Style.space(1)

                Rectangle { anchors.centerIn: parent; width: parent.width; height: Style.space(1); color: Commons.Color.muted }
                Rectangle { anchors.centerIn: parent; width: Style.space(1); height: parent.height; color: Commons.Color.muted }

                Rectangle {
                  id: puck
                  width: Style.space(16)
                  height: Style.space(16)
                  radius: Style.space(8)
                  color: Commons.Color.accent
                  border.color: Commons.Color.popups.text
                  border.width: Style.space(2)

                  x: {
                    let pan = root.value("pan_absolute", 0)
                    let normX = (pan + 468000) / 936000
                    return Math.max(0, Math.min(xyPad.width - width, normX * (xyPad.width - width)))
                  }
                  y: {
                    let tilt = root.value("tilt_absolute", 0)
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
                  onPressed: function(mouse) { xyPad.forceActiveFocus(Qt.MouseFocusReason); updateFromMouse(mouse.x, mouse.y) }
                  onPositionChanged: function(mouse) { if (pressed) updateFromMouse(mouse.x, mouse.y) }
                  onDoubleClicked: { gimbalThrottle.stop(); if (root.cam) root.cam.setPanTilt(0, 0) }
                }
              }

              Column {
                width: parent.width - Style.space(172)
                spacing: Style.space(6)

                Text {
                  text: {
                    let p = root.cam && root.cam.state ? Math.round(root.value("pan_absolute", 0) / 3600) : 0
                    let t = root.cam && root.cam.state ? Math.round(root.value("tilt_absolute", 0) / 3600) : 0
                    return "Pan: " + p + "° | Tilt: " + t + "°"
                  }
                  color: Commons.Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Row {
                  spacing: Style.space(4)
                  StudioButton {
                    width: Style.space(36); text: "◀"
                    onClicked: if (root.cam) root.cam.setControl("pan_absolute", root.value("pan_absolute", 0) - 18000)
                  }
                  StudioButton {
                    width: Style.space(36); text: "▲"
                    onClicked: if (root.cam) root.cam.setControl("tilt_absolute", root.value("tilt_absolute", 0) + 18000)
                  }
                  StudioButton {
                    width: Style.space(36); text: "▼"
                    onClicked: if (root.cam) root.cam.setControl("tilt_absolute", root.value("tilt_absolute", 0) - 18000)
                  }
                  StudioButton {
                    width: Style.space(36); text: "▶"
                    onClicked: if (root.cam) root.cam.setControl("pan_absolute", root.value("pan_absolute", 0) + 18000)
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
              currentVal: root.value("zoom_absolute", 0)
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
              enabled: root.value("focus_automatic_continuous", 1) === 0
              minVal: 0; maxVal: 100; stepVal: 1
              currentVal: root.value("focus_absolute", 37)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("focus_absolute", v) }
            }
          }

          // ==========================================
          // TAB 1: COLOR & KELVIN WHITE BALANCE
          // ==========================================
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.activeTab === 1
            enabled: root.cameraReady

            StudioButton {
              width: parent.width
              property bool awbOn: root.cam && root.cam.state ? (root.cam.state.white_balance_automatic === 1) : false
              text: awbOn ? "Auto White Balance: ON" : "Auto White Balance: OFF (Manual Kelvin)"
              active: awbOn
              onClicked: if (root.cam) root.cam.setControl("white_balance_automatic", awbOn ? 0 : 1)
            }

            StudioSlider {
              label: "White Balance (K)"
              enabled: root.value("white_balance_automatic", 1) === 0
              minVal: 2000; maxVal: 10000; stepVal: 100
              currentVal: root.value("white_balance_temperature", 5000)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("white_balance_temperature", v) }
            }

            StudioSlider {
              label: "Brightness"
              minVal: 0; maxVal: 100; stepVal: 1
              currentVal: root.value("brightness", 32)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("brightness", v) }
            }

            StudioSlider {
              label: "Contrast"
              minVal: 0; maxVal: 100; stepVal: 1
              currentVal: root.value("contrast", 53)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("contrast", v) }
            }

            StudioSlider {
              label: "Saturation"
              minVal: 0; maxVal: 100; stepVal: 1
              currentVal: root.value("saturation", 69)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("saturation", v) }
            }

            StudioSlider {
              label: "Sharpness"
              minVal: 0; maxVal: 100; stepVal: 1
              currentVal: root.value("sharpness", 44)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("sharpness", v) }
            }
          }

          // ==========================================
          // TAB 2: EXPOSURE, GAIN & BACKLIGHT/HDR
          // ==========================================
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.activeTab === 2
            enabled: root.cameraReady

            StudioButton {
              width: parent.width
              property bool aeOn: root.cam && root.cam.state ? (root.cam.state.auto_exposure === 0) : true
              text: aeOn ? "Auto Exposure: ON" : "Auto Exposure: OFF (Manual Shutter)"
              active: aeOn
              onClicked: if (root.cam) root.cam.setControl("auto_exposure", aeOn ? 1 : 0)
            }

            StudioSlider {
              label: "Shutter / Exposure Time"
              enabled: root.value("auto_exposure", 0) === 1
              minVal: 1; maxVal: 2500; stepVal: 10
              currentVal: root.value("exposure_time_absolute", 330)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("exposure_time_absolute", v) }
            }

            StudioSlider {
              label: "Sensor Gain (ISO)"
              minVal: 1; maxVal: 64; stepVal: 1
              currentVal: root.value("gain", 20)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("gain", v) }
            }

            StudioSlider {
              label: "Backlight Compensation (HDR)"
              minVal: 0; maxVal: 18; stepVal: 1
              currentVal: root.value("backlight_compensation", 11)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("backlight_compensation", v) }
            }
          }
        }
      }
    }
  }
}

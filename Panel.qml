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
  property bool reverseCamera: false
  property bool savePresetMode: false
  readonly property bool hasHardwareFlip: root.value("image_flip_hor", -1) >= 0
  readonly property bool isCameraReversed: hasHardwareFlip
    ? root.value("image_flip_hor", 0) === 1
    : root.reverseCamera

  function toggleReverseCamera() {
    const next = !root.isCameraReversed
    root.reverseCamera = next
    if (root.cameraReady && root.cam && root.hasHardwareFlip)
      root.cam.setControl("image_flip_hor", next ? 1 : 0)
  }

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

            StudioButton {
              id: reverseButton
              width: Style.space(96)
              height: Style.space(24)
              text: root.isCameraReversed ? "Reverse: ON" : "Reverse: OFF"
              active: root.isCameraReversed
              onClicked: root.toggleReverseCamera()
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
              onClicked: {
                if (cameraLoader.active && (viewfinderBox.cameraError || !viewfinderBox.cameraActive))
                  previewRestart.start()
                if (root.cam) root.cam.retry()
              }
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
            id: viewfinderBox
            width: parent.width
            height: Math.round(parent.width * 9 / 16)
            color: Commons.Color.background
            radius: Style.space(8)
            border.color: Commons.Color.muted
            border.width: Style.space(1)
            clip: true
            property string cameraError: ""
            property bool cameraActive: false

            MediaDevices { id: mediaDevices }

            Timer {
              id: previewRestart
              interval: 100
            }

            Loader {
              id: cameraLoader
              active: root.opened && !previewRestart.running
                && root.value("dev_status", 1) === 1 && root.previewDevice !== null
              onActiveChanged: {
                if (!active) {
                  viewfinderBox.cameraError = ""
                  viewfinderBox.cameraActive = false
                }
              }
              sourceComponent: CaptureSession {
                camera: Camera {
                  cameraDevice: root.previewDevice
                  active: true
                  Component.onCompleted: {
                    viewfinderBox.cameraActive = active
                    viewfinderBox.cameraError = (error !== Camera.NoError) ? errorString : ""
                  }
                  onActiveChanged: viewfinderBox.cameraActive = active
                  onErrorChanged: viewfinderBox.cameraError = (error !== Camera.NoError) ? errorString : ""
                }
                videoOutput: viewfinder
              }
            }

            VideoOutput {
              id: viewfinder
              anchors.fill: parent
              fillMode: VideoOutput.PreserveAspectFit
              transform: Scale {
                origin.x: viewfinder.width / 2
                xScale: (!root.hasHardwareFlip && root.reverseCamera) ? -1 : 1
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              text: !root.cameraReady ? "Camera unavailable"
                  : root.value("dev_status", 1) === 3 ? "Camera asleep"
                  : root.value("dev_status", 1) === 4 ? "Privacy mode"
                  : !root.previewDevice ? "Selected camera is not available for preview"
                  : viewfinderBox.cameraError
              visible: text !== ""
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
            }

            Item {
              anchors.fill: parent
              visible: root.showGrid && viewfinderBox.cameraActive
              Rectangle { x: parent.width / 3; y: 0; width: Style.space(1); height: parent.height; color: Util.alpha(Commons.Color.popups.text, 0.3) }
              Rectangle { x: (parent.width / 3) * 2; y: 0; width: Style.space(1); height: parent.height; color: Util.alpha(Commons.Color.popups.text, 0.3) }
              Rectangle { x: 0; y: parent.height / 3; width: parent.width; height: Style.space(1); color: Util.alpha(Commons.Color.popups.text, 0.3) }
              Rectangle { x: 0; y: (parent.height / 3) * 2; width: parent.width; height: Style.space(1); color: Util.alpha(Commons.Color.popups.text, 0.3) }
            }
          }

          // 3. Quick Presets & Hardware Sleep/Firmware Presets Bar
          Column {
            enabled: root.cameraReady
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(24)) / 5
                text: "Face"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.savePreset("Face Center"); root.savePresetMode = false }
                  else root.cam.applyPreset("Face Center")
                }
              }
              StudioButton {
                width: (parent.width - Style.space(24)) / 5
                text: "Desk"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.savePreset("Desk View"); root.savePresetMode = false }
                  else root.cam.applyPreset("Desk View")
                }
              }
              StudioButton {
                width: (parent.width - Style.space(24)) / 5
                text: "Wide"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.savePreset("Wide Room"); root.savePresetMode = false }
                  else root.cam.applyPreset("Wide Room")
                }
              }
              StudioButton {
                width: (parent.width - Style.space(24)) / 5
                text: "💤 Stow"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.savePreset("Privacy Sleep"); root.savePresetMode = false }
                  else root.cam.applyPreset("Privacy Sleep")
                }
              }
              StudioButton {
                width: (parent.width - Style.space(24)) / 5
                text: root.savePresetMode ? "💾 Saving" : "💾 Save"
                active: root.savePresetMode
                onClicked: root.savePresetMode = !root.savePresetMode
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "HW 1"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.saveHwPreset(0); root.savePresetMode = false }
                  else root.cam.applyHwPreset(0)
                }
              }
              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "HW 2"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.saveHwPreset(1); root.savePresetMode = false }
                  else root.cam.applyHwPreset(1)
                }
              }
              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "HW 3"
                onClicked: {
                  if (!root.cam) return
                  if (root.savePresetMode) { root.cam.saveHwPreset(2); root.savePresetMode = false }
                  else root.cam.applyHwPreset(2)
                }
              }
              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                property bool isSleeping: root.value("dev_status", 1) !== 1
                text: isSleeping ? "⚡ Wake" : "🌙 Sleep"
                active: isSleeping
                onClicked: if (root.cam) root.cam.setControl("dev_status", isSleeping ? 1 : 3)
              }
            }
          }

          // 4. Studio Navigation Tabs
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                text: "Gimbal & Focus"
                active: root.activeTab === 0
                onClicked: root.activeTab = 0
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                text: "AI & Gestures"
                active: root.activeTab === 3
                onClicked: root.activeTab = 3
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                text: "Color & Kelvin"
                active: root.activeTab === 1
                onClicked: root.activeTab = 1
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                text: "Exposure & HDR"
                active: root.activeTab === 2
                onClicked: root.activeTab = 2
              }
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

            StudioSlider {
              label: "Zoom Speed (0 = Auto)"
              minVal: 0; maxVal: 10; stepVal: 1
              currentVal: root.value("zoom_speed", 0)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("zoom_speed", v) }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "FOV 86° Wide"
                active: root.value("fov", 0) === 0
                onClicked: if (root.cam) root.cam.setControl("fov", 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "FOV 78° Med"
                active: root.value("fov", 0) === 1
                onClicked: if (root.cam) root.cam.setControl("fov", 1)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "FOV 65° Narrow"
                active: root.value("fov", 0) === 2
                onClicked: if (root.cam) root.cam.setControl("fov", 2)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool afOn: root.cam && root.cam.state ? (root.cam.state.focus_automatic_continuous === 1) : true
                text: afOn ? "Autofocus: ON" : "Autofocus: OFF"
                active: afOn
                onClicked: if (root.cam) root.cam.setControl("focus_automatic_continuous", afOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                enabled: root.value("focus_automatic_continuous", 1) === 1
                property bool faceAfOn: root.value("face_auto_focus", 1) === 1
                text: faceAfOn ? "Face AF: ON" : "Face AF: OFF"
                active: faceAfOn
                onClicked: if (root.cam) root.cam.setControl("face_auto_focus", faceAfOn ? 0 : 1)
              }
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

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool wdrOn: root.value("hdr", 0) === 1
                text: wdrOn ? "Hardware HDR: ON" : "Hardware HDR: OFF"
                active: wdrOn
                onClicked: if (root.cam) root.cam.setControl("hdr", wdrOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool faceAeOn: root.value("face_ae", 1) === 1
                text: faceAeOn ? "Face AE: ON" : "Face AE: OFF"
                active: faceAeOn
                onClicked: if (root.cam) root.cam.setControl("face_ae", faceAeOn ? 0 : 1)
              }
            }

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
              label: "Backlight Compensation (EV)"
              minVal: 0; maxVal: 18; stepVal: 1
              currentVal: root.value("backlight_compensation", 11)
              onValueEdited: function(v) { if (root.cam) root.cam.setControl("backlight_compensation", v) }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Flicker: OFF"
                active: root.value("power_line_frequency", 1) === 0
                onClicked: if (root.cam) root.cam.setControl("power_line_frequency", 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "50 Hz"
                active: root.value("power_line_frequency", 1) === 1
                onClicked: if (root.cam) root.cam.setControl("power_line_frequency", 1)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "60 Hz"
                active: root.value("power_line_frequency", 1) === 2
                onClicked: if (root.cam) root.cam.setControl("power_line_frequency", 2)
              }
            }
          }

          // ==========================================
          // TAB 3: AI TRACKING & HAND GESTURES
          // ==========================================
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.activeTab === 3
            enabled: root.cameraReady

            Text {
              text: "AI Tracking Mode"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Off"
                active: root.value("ai_mode", 0) === 0
                onClicked: if (root.cam) root.cam.setAiMode(0, 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Human"
                active: root.value("ai_mode", 0) === 2
                onClicked: if (root.cam) root.cam.setAiMode(2, root.value("ai_sub_mode", 0))
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Group"
                active: root.value("ai_mode", 0) === 1
                onClicked: if (root.cam) root.cam.setAiMode(1, 0)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Hand"
                active: root.value("ai_mode", 0) === 3
                onClicked: if (root.cam) root.cam.setAiMode(3, 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Desk"
                active: root.value("ai_mode", 0) === 5
                onClicked: if (root.cam) root.cam.setAiMode(5, 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Whiteboard"
                active: root.value("ai_mode", 0) === 4
                onClicked: if (root.cam) root.cam.setAiMode(4, 0)
              }
            }

            Text {
              text: "Human Framing Sub-Mode"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)
              enabled: root.value("ai_mode", 0) === 2

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Standard"
                active: root.value("ai_mode", 0) === 2 && root.value("ai_sub_mode", 0) === 0
                onClicked: if (root.cam) root.cam.setAiMode(2, 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Upper Body"
                active: root.value("ai_mode", 0) === 2 && root.value("ai_sub_mode", 0) === 1
                onClicked: if (root.cam) root.cam.setAiMode(2, 1)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Close Up"
                active: root.value("ai_mode", 0) === 2 && root.value("ai_sub_mode", 0) === 2
                onClicked: if (root.cam) root.cam.setAiMode(2, 2)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)
              enabled: root.value("ai_mode", 0) === 2

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                text: "Headless"
                active: root.value("ai_mode", 0) === 2 && root.value("ai_sub_mode", 0) === 3
                onClicked: if (root.cam) root.cam.setAiMode(2, 3)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                text: "Lower Body"
                active: root.value("ai_mode", 0) === 2 && root.value("ai_sub_mode", 0) === 4
                onClicked: if (root.cam) root.cam.setAiMode(2, 4)
              }
            }

            Text {
              text: "Tracking Speed & Auto-Zoom"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Standard"
                active: root.value("ai_tracking_mode", 0) === 0
                onClicked: if (root.cam) root.cam.setControl("ai_tracking_mode", 0)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Headroom"
                active: root.value("ai_tracking_mode", 0) === 1
                onClicked: if (root.cam) root.cam.setControl("ai_tracking_mode", 1)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                text: "Motion"
                active: root.value("ai_tracking_mode", 0) === 2
                onClicked: if (root.cam) root.cam.setControl("ai_tracking_mode", 2)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool autoZoomOn: root.value("ai_auto_zoom", 1) === 1
                text: autoZoomOn ? "Auto Zoom: ON" : "Auto Zoom: OFF"
                active: autoZoomOn
                onClicked: if (root.cam) root.cam.setControl("ai_auto_zoom", autoZoomOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool zoneOn: root.value("ai_zone_track", 0) === 1
                text: zoneOn ? "Zone Track: ON" : "Zone Track: OFF"
                active: zoneOn
                onClicked: if (root.cam) root.cam.setControl("ai_zone_track", zoneOn ? 0 : 1)
              }
            }

            Text {
              text: "Hand Gesture Controls"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool targetOn: root.value("gesture_target", 1) === 1
                text: targetOn ? "✋ Target Lock: ON" : "✋ Target Lock: OFF"
                active: targetOn
                onClicked: if (root.cam) root.cam.setControl("gesture_target", targetOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool zoomOn: root.value("gesture_zoom", 1) === 1
                text: zoomOn ? "🤏 Gesture Zoom: ON" : "🤏 Gesture Zoom: OFF"
                active: zoomOn
                onClicked: if (root.cam) root.cam.setControl("gesture_zoom", zoomOn ? 0 : 1)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool dynZoomOn: root.value("gesture_dynamic_zoom", 0) === 1
                text: dynZoomOn ? "↔ Dynamic Zoom: ON" : "↔ Dynamic Zoom: OFF"
                active: dynZoomOn
                onClicked: if (root.cam) root.cam.setControl("gesture_dynamic_zoom", dynZoomOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool mirrorOn: root.value("gesture_mirror", 0) === 1
                text: mirrorOn ? "⇄ Zoom Mirror: ON" : "⇄ Zoom Mirror: OFF"
                active: mirrorOn
                onClicked: if (root.cam) root.cam.setControl("gesture_mirror", mirrorOn ? 0 : 1)
              }
            }

            Text {
              text: "Audio & Voice Control"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool agcOn: root.value("audio_auto_gain", 1) === 1
                text: agcOn ? "🎙 Mic Auto Gain: ON" : "🎙 Mic Auto Gain: OFF"
                active: agcOn
                onClicked: if (root.cam) root.cam.setControl("audio_auto_gain", agcOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool langEn: root.value("voice_ctrl_language", 1) === 1
                text: langEn ? "🗣 Voice Lang: EN" : "🗣 Voice Lang: ZH"
                active: langEn
                onClicked: if (root.cam) root.cam.setControl("voice_ctrl_language", langEn ? 0 : 1)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool hiOn: root.value("voice_hi_tiny", 0) === 1
                text: hiOn ? "🗣 Wake/Sleep: ON" : "🗣 Wake/Sleep: OFF"
                active: hiOn
                onClicked: if (root.cam) root.cam.setControl("voice_hi_tiny", hiOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool trkOn: root.value("voice_track", 0) === 1
                text: trkOn ? "🗣 Track/Unlock: ON" : "🗣 Track/Unlock: OFF"
                active: trkOn
                onClicked: if (root.cam) root.cam.setControl("voice_track", trkOn ? 0 : 1)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool vZoomOn: root.value("voice_zoom", 0) === 1
                text: vZoomOn ? "🗣 Voice Zoom: ON" : "🗣 Voice Zoom: OFF"
                active: vZoomOn
                onClicked: if (root.cam) root.cam.setControl("voice_zoom", vZoomOn ? 0 : 1)
              }
              StudioButton {
                width: (parent.width - Style.space(6)) / 2
                property bool vPresetOn: root.value("voice_preset", 0) === 1
                text: vPresetOn ? "🗣 Voice Presets: ON" : "🗣 Voice Presets: OFF"
                active: vPresetOn
                onClicked: if (root.cam) root.cam.setControl("voice_preset", vPresetOn ? 0 : 1)
              }
            }

            Text {
              text: "Hardware Sleep & Privacy"
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                property bool sleepOn: root.value("dev_status", 1) === 3
                text: sleepOn ? "🌙 Sleep: ON" : "⚡ Run Mode"
                active: sleepOn
                onClicked: if (root.cam) root.cam.setControl("dev_status", sleepOn ? 1 : 3)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                property bool privOn: root.value("dev_status", 1) === 4
                text: privOn ? "🔒 Privacy: ON" : "🔒 Privacy: OFF"
                active: privOn
                onClicked: if (root.cam) root.cam.setControl("dev_status", privOn ? 1 : 4)
              }
              StudioButton {
                width: (parent.width - Style.space(12)) / 3
                property bool sleepMicOn: root.value("sleep_micro", 0) === 1
                text: sleepMicOn ? "🎙 Sleep Mic: ON" : "🔇 Sleep Mic: OFF"
                active: sleepMicOn
                onClicked: if (root.cam) root.cam.setControl("sleep_micro", sleepMicOn ? 0 : 1)
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "Auto-Sleep: OFF"
                active: root.value("auto_sleep_time", 0) === 0
                onClicked: if (root.cam) root.cam.setControl("auto_sleep_time", 0)
              }
              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "30s"
                active: root.value("auto_sleep_time", 0) === 30
                onClicked: if (root.cam) root.cam.setControl("auto_sleep_time", 30)
              }
              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "2m"
                active: root.value("auto_sleep_time", 0) === 120
                onClicked: if (root.cam) root.cam.setControl("auto_sleep_time", 120)
              }
              StudioButton {
                width: (parent.width - Style.space(18)) / 4
                text: "10m"
                active: root.value("auto_sleep_time", 0) === 600
                onClicked: if (root.cam) root.cam.setControl("auto_sleep_time", 600)
              }
            }
          }
        }
      }
    }
  }
}

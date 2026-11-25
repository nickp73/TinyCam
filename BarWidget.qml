pragma ComponentBehavior: Bound
import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.nickp73.tinycam"

  readonly property var camService: serviceLoader.item

  Loader {
    id: serviceLoader
    active: root.opened
    sourceComponent: CameraService {
      preferredDevice: String(root.setting("device", ""))
    }
  }

  readonly property var loadedPanel: panelLoader.item

  readonly property bool opened: root.loadedPanel
    ? root.loadedPanel.opened === true
    : false
  readonly property bool popoutSwitchClosing: root.loadedPanel
    ? root.loadedPanel.popoutSwitchClosing === true
    : false

  function open() {
    if (root.loadedPanel) root.loadedPanel.open()
  }

  function close() {
    if (root.loadedPanel) root.loadedPanel.close()
  }

  function toggle() {
    if (root.loadedPanel) root.loadedPanel.toggle()
  }

  function closeForPopoutSwitch() {
    if (root.loadedPanel) root.loadedPanel.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!root.loadedPanel) return
    root.loadedPanel.bar = root.bar
    root.loadedPanel.anchorItem = button
    root.loadedPanel.hostWidget = root
    root.loadedPanel.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "📷"
    tooltipText: root.camService && !root.camService.isReady
      ? (root.camService.errorMessage || "Waiting for OBSBOT camera")
      : "Open TinyCam Studio"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}

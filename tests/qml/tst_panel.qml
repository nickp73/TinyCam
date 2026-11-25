import QtQuick
import QtTest
import "../.." as Tiny

Item {
  width: 500
  height: 650
  QtObject {
    id: fakeCam
    property bool isReady: true
    property string devicePath: "/nonexistent-camera"
    property string errorMessage: ""
    property var state: ({brightness: 0, focus_automatic_continuous: 0})
    property var lastCommand: []
    function syncState() {}
    function retry() {}
    function setControl(name, value) { lastCommand = [name, value] }
    function setPanTilt(pan, tilt) { lastCommand = ["pt", pan, tilt] }
    function applyPreset(name) { lastCommand = ["preset", name] }
  }
  QtObject { id: host; property var camService: fakeCam }
  QtObject {
    id: fakeBar
    property int lastDirection: 0
    function switchPanelFrom(owner, direction) { lastDirection = direction; return true }
  }
  Tiny.Panel { id: popup; hostWidget: host; bar: fakeBar; width: 500; height: 650 }
  TestCase {
    name: "TinyCamPanel"
    when: windowShown
    function findControl(property, value, item) {
      item = item || popup
      if (item[property] === value) return item
      for (let i = 0; i < item.children.length; ++i) {
        const found = findControl(property, value, item.children[i])
        if (found) return found
      }
      return null
    }
    function init() {
      fakeCam.isReady = true
      fakeCam.state = {brightness: 0, focus_automatic_continuous: 0}
      fakeCam.lastCommand = []
      popup.activeTab = 0
      popup.showGrid = true
      popup.reverseCamera = false
      popup.open()
      wait(20)
    }
    function cleanup() { popup.close() }
    function test_tab_and_button_activation() {
      const grid = findControl("text", "Grid: ON")
      const reverse = findControl("text", "Reverse: OFF")
      verify(grid !== null)
      verify(reverse !== null)
      grid.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      verify(reverse.activeFocus)
      keyClick(Qt.Key_Space)
      compare(popup.reverseCamera, true)
      compare(reverse.text, "Reverse: ON")
      keyClick(Qt.Key_Return)
      compare(popup.reverseCamera, false)
      keyClick(Qt.Key_Tab)
      verify(findControl("text", "Retry").activeFocus)
      keyClick(Qt.Key_Tab, Qt.ShiftModifier)
      verify(reverse.activeFocus)
      keyClick(Qt.Key_Tab, Qt.ShiftModifier)
      verify(grid.activeFocus)
      keyClick(Qt.Key_Space)
      compare(popup.showGrid, false)
      keyClick(Qt.Key_Return)
      compare(popup.showGrid, true)
      keyClick(Qt.Key_Escape)
      compare(popup.opened, false)
    }
    function test_slider_readback_zero_and_keyboard_bounds() {
      popup.activeTab = 1
      const slider = findControl("label", "Brightness")
      compare(slider.currentVal, 0)
      slider.forceActiveFocus()
      keyClick(Qt.Key_Left)
      compare(fakeCam.lastCommand[1], 0)
      keyClick(Qt.Key_Right)
      compare(fakeCam.lastCommand[1], 1)
      keyClick(Qt.Key_End)
      compare(fakeCam.lastCommand[1], 100)
      compare(slider.currentVal, 0) // No optimistic value without camera acknowledgement.
    }
    function test_tab_skips_disabled_controls() {
      const autofocus = findControl("text", "Autofocus: OFF")
      const faceAf = findControl("text", "Face AF: ON")
      verify(autofocus !== null)
      verify(faceAf !== null)
      verify(!faceAf.enabled)
      fakeCam.state = {focus_automatic_continuous: 1}
      faceAf.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      verify(findControl("text", "Grid: ON").activeFocus)
    }
    function test_gimbal_arrows_and_home() {
      function findPad(item) {
        if (item.Accessible.name === "Pan and tilt. Arrow keys adjust; Home centers.") return item
        for (let i = 0; i < item.children.length; ++i) {
          const found = findPad(item.children[i]); if (found) return found
        }
        return null
      }
      const xy = findPad(popup)
      verify(xy !== null)
      xy.forceActiveFocus()
      keyClick(Qt.Key_Right)
      tryCompare(fakeCam, "lastCommand", ["pt", 18000, 0])
      keyClick(Qt.Key_Home)
      tryCompare(fakeCam, "lastCommand", ["pt", 0, 0])
    }
    function test_panel_switching_and_scroll_into_view() {
      popup.activeTab = 1
      const slider = findControl("label", "Sharpness")
      slider.forceActiveFocus()
      verify(slider.activeFocus, "Sharpness must have active focus")
      const scroll = findControl("flickableDirection", Flickable.VerticalFlick)
      verify(scroll !== null)
      wait(200)
      const position = slider.mapToItem(scroll, 0, 0)
      verify(position.y >= 0, "y=" + position.y + ", contentY=" + scroll.contentY)
      verify(position.y + slider.height <= scroll.height + 1, "y=" + position.y + ", slider=" + slider.height + ", viewport=" + scroll.height + ", contentY=" + scroll.contentY + ", contentHeight=" + scroll.contentHeight)
      keyClick(Qt.Key_Tab, Qt.ControlModifier)
      compare(fakeBar.lastDirection, 1)
      keyClick(Qt.Key_Tab, Qt.ControlModifier | Qt.ShiftModifier)
      compare(fakeBar.lastDirection, -1)
    }
    function test_disconnected_controls_are_disabled() {
      fakeCam.isReady = false
      verify(!findControl("text", "Face").enabled)
      verify(!findControl("label", "Digital Zoom (%)").enabled)
      verify(findControl("text", "Retry").enabled)
    }
  }
}

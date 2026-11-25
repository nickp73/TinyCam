import QtQuick
Item {
  property string moduleName: ""
  property bool manageIpc: true
  property var settings: ({})
  property var bar: null
  property bool opened: false
  property QtObject controller: QtObject {
    function show() { opened = true }
    function hide() { opened = false }
  }
  function open() { controller.show() }
  function close() { controller.hide() }
}

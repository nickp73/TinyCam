import QtQuick
Item {
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 420
  property int contentHeight: 600
  width: contentWidth
  height: contentHeight
  function fittedContentWidth(value) { return Math.min(420, value) }
  function fittedContentHeight(value) { return Math.min(450, value) }
  onOpenChanged: if (open && focusTarget) focusTarget.forceActiveFocus()
}

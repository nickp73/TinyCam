pragma Singleton
import QtQuick
QtObject {
  property real scale: 1
  property int cornerRadius: 8
  property color normalFill: "#222222"
  property color pressedFill: "#555555"
  property color selectedAccentFill: "#666666"
  property QtObject font: QtObject {
    property string family: "sans-serif"
    property int body: 12
    property int bodySmall: 11
    property int subtitle: 16
  }
  function space(x) { return Math.round(x * scale) }
  function controlFill(focused, hovered, foreground, accent) { return focused ? accent : normalFill }
}

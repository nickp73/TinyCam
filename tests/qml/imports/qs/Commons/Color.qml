pragma Singleton
import QtQuick
QtObject {
  property color accent: "#77aaff"
  property color muted: "#888888"
  property color urgent: "#ff0000"
  property color background: "#111111"
  property QtObject popups: QtObject { property color text: "#eeeeee" }
}

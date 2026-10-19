# TinyCam

An Omarchy bar widget for the OBSBOT Tiny 2 Lite (`3564:fef9`), with a live
preview, pan/tilt controls, presets, focus, exposure, and colour adjustments.

The plugin uses Omarchy's QML components, Qt Multimedia, and system `python3`.
The Python backend uses only the standard library.

## Camera selection

TinyCam discovers the OBSBOT by USB vendor/product identity and selects its
primary video node. The preview uses the same device reported by the backend.
It does not activate a different camera if the selected camera is unavailable.

For multiple OBSBOT cameras, add a `device` value to this widget's existing
entry in `~/.config/omarchy/shell.json`, for example:

```json
{
  "id": "io.github.nickp73.tinycam",
  "device": "/dev/v4l/by-id/<your-camera>-video-index0"
}
```

Use the actual path from `/dev/v4l/by-id/`; a stable path continues to work when
Linux changes the `/dev/videoN` numbering. An explicitly selected device must
still identify as an OBSBOT Tiny 2 Lite.

The controller checks the connection every two seconds and reconnects after
unplugging or a backend exit. The panel displays errors and offers a Retry
button. Values update from camera readback, including after a rejected command.
Preview capture is active only while the panel is open.

## Keyboard controls

- **Tab / Shift+Tab:** move through visible, enabled controls.
- **Enter / Space:** activate the focused button.
- **Arrow keys:** adjust the focused slider or pan/tilt pad.
- **Home / End:** move a slider to its minimum/maximum.
- **Home on the pan/tilt pad:** center the camera.
- **Ctrl+Tab / Ctrl+Shift+Tab:** switch between Omarchy panels.
- **Escape:** close TinyCam.

The focus outline follows the current theme. The panel scrolls to keep the
focused control visible on smaller displays or at larger text sizes.

## Presets

Presets live in `$XDG_CONFIG_HOME/tinycam/presets.json`, defaulting to
`~/.config/tinycam/presets.json`. Built-in defaults only fill missing preset
names; saved values are preserved. Writes replace the file atomically, and
invalid preset files are reported rather than overwritten.

The current panel applies the four named presets. The backend also supports
`preset_save` for callers using its newline-delimited JSON protocol.

## Checks

Run the backend regression tests without accessing camera hardware:

```sh
python3 -B -m unittest discover -s tests -v
```

Run the panel's keyboard and scrolling checks with a simulated camera and shell
host (no preview capture or hardware control):

```sh
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
  /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import tests/qml/imports
```

For QML linting, use the **Qt 6** linter and an import directory whose `qs`
entry points to `/usr/share/omarchy/shell` (Quickshell normally supplies that
mapping at runtime):

```sh
lint_imports=$(mktemp -d)
ln -s /usr/share/omarchy/shell "$lint_imports/qs"
/usr/lib/qt6/bin/qmllint -I "$lint_imports" BarWidget.qml Panel.qml CameraService.qml
```

A read-only hardware check prints the detected device and its current controls:

```sh
python3 -B tinycam_backend.py < /dev/null
```

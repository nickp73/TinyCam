# TinyCam

TinyCam puts a live viewfinder and camera controls for the **OBSBOT Tiny 2 Lite** in the Omarchy bar. Open the camera icon to frame a shot, adjust focus and exposure, recall a preset, or turn on hand-gesture zoom.

## Installation

You need Omarchy with its Quickshell-based bar and `omarchy plugin` commands, Qt 6 Multimedia, Git, system `python3`, and access to the camera’s Linux video device. The controller uses Python’s standard library. Omarchy launches it when you open the panel.

### Install with Omarchy

From a terminal, install the repository and enable the widget in one step. If prompted, choose the bar section where you want the camera icon.

```sh
omarchy plugin add https://github.com/nickp73/TinyCam.git --enable
```

### Install with git clone

For a working checkout you can edit, use these commands on a fresh installation. The destination directory matches the plugin ID in `manifest.json`.

```sh
mkdir -p ~/.config/omarchy/plugins
git clone https://github.com/nickp73/TinyCam.git ~/.config/omarchy/plugins/io.github.nickp73.tinycam
cd ~/.config/omarchy/plugins/io.github.nickp73.tinycam
omarchy plugin enable io.github.nickp73.tinycam --section right
```

If you already have a TinyCam checkout there, skip the clone and run the enable command. Omarchy reloads local plugin edits automatically.

**SDK features in this working tree.** Hardware presets, gesture settings, AI tracking controls, and hardware sleep/privacy use the native OBSBOT bridge. This checkout has local changes and native libraries outside the committed source. A clone of the current commit provides the committed feature set. To use the SDK controls described below on another machine, you also need the matching updated plugin source, `libtinycam_sdk.so`, and its compatible OBSBOT `libdev.so` libraries. Keep the libraries and their versioned links beside `tinycam_backend.py`.

## First use

1. Connect the camera and click the camera icon. The panel shows the selected device path once connected.
2. Open **Gimbal & Focus** to position the camera and set digital zoom. **Grid** adds framing guides. **Reverse** uses hardware mirroring when available and otherwise mirrors the preview.
3. For L-shaped hand zoom, open **AI & Gestures**, enable **Gesture Zoom**, and hold your thumb and index finger in an L shape in view of the camera. You can use this gesture independently of the HW preset buttons.

| Tab | Controls |
| --- | --- |
| Gimbal & Focus | Pan, tilt, centering, digital zoom, zoom speed, field of view, autofocus, and manual focus |
| Color & Kelvin | White balance, manual colour temperature, brightness, contrast, saturation, and sharpness |
| Exposure & HDR | HDR, face exposure, shutter, gain, backlight compensation, and flicker reduction |
| AI & Gestures | Tracking and framing modes, auto zoom, gesture controls, voice commands, hardware sleep, privacy, and auto-sleep |

## Save and recall a camera position

| Buttons | Where the position is stored | What they recall |
| --- | --- | --- |
| **Face**, **Desk**, **Wide**, **Stow** | On this computer | Named pan, tilt, and zoom settings. Stow initially points the camera down. |
| **HW 1**, **HW 2**, **HW 3** | In the camera | Three numbered hardware framing presets. You choose what each slot contains. |

To **recall** a position, click its button. To **save** one, frame the shot, click **Save**, then click the destination button while **Saving** is shown. Saving replaces the position in that slot. Click **Saving** again before selecting a slot to cancel.

Local presets live in `$XDG_CONFIG_HOME/tinycam/presets.json`, usually `~/.config/tinycam/presets.json`. TinyCam preserves saved positions when adding missing defaults. For hardware sleep, use **Sleep**. **Stow** only changes framing.

## Camera selection and multiple monitors

TinyCam discovers the primary video node of a supported OBSBOT by USB identity. With one camera, selection is automatic. If several supported cameras are connected, list the stable device links and set the widget’s `device` to the desired camera’s actual `video-index0` path.

```sh
ls -l /dev/v4l/by-id/
omarchy bar set io.github.nickp73.tinycam device '/dev/v4l/by-id/<your-camera>-video-index0'
```

Each monitor starts its controller when you open its panel and releases it on close. To move the preview, close TinyCam on the first monitor and open it on the next. Sleep and privacy stop preview capture. The open panel keeps controls available so you can wake the camera.

## Troubleshooting

- **Missing bar icon.** Run `omarchy plugin list` and look for `io.github.nickp73.tinycam`. If present, run the enable command above.
- **Camera unavailable.** Check the USB connection and selected device path. Close another preview using the camera, then press **Retry**. An open panel polls every two seconds and waits for an outstanding poll before sending another.
- **Preview failed after a preset or gesture.** Press **Retry** once to refresh controls and recreate a failed preview. If Linux reports a USB disconnect, reconnect the camera and wait for the device to reappear.
- **Preview works but an SDK command fails.** Check the installed source version and native libraries described under Installation. The backend check below prints the camera’s reported state or a connection error.

## Keyboard controls

| Keys | Action |
| --- | --- |
| Tab / Shift+Tab | Move between visible, enabled controls |
| Enter / Space | Activate the focused button |
| Arrow keys | Adjust a slider or move the pan/tilt pad |
| Home / End | Go to a slider’s minimum or maximum |
| Home on the pan/tilt pad | Center the camera |
| Ctrl+Tab / Ctrl+Shift+Tab | Switch between Omarchy panels |
| Escape | Close TinyCam |

## Manage the installation

Disable the widget to take it off the bar while keeping its files. Use the enable command above to bring it back.

```sh
omarchy plugin disable io.github.nickp73.tinycam
```

For an Omarchy-managed Git install, run `omarchy plugin update io.github.nickp73.tinycam` to update or `omarchy plugin remove io.github.nickp73.tinycam` to uninstall. Removal deletes the installed plugin directory. Preserve any local work in that directory first.

## Checks

Run these commands from the plugin directory. The test suites require the local `tests/` directory, and the backend suite also checks that the native SDK bridge loads.

Run the backend tests with simulated camera controls:

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

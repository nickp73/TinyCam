#!/usr/bin/env python3
"""
TinyCam Studio Persistent Daemon for OBSBOT Tiny 2 Lite (3564:fef9)
Supports PTZ Gimbal XY, Presets, Optics (Focus/Zoom), Exposure, and Color/Kelvin.
"""
import argparse
import ctypes
import errno
import fcntl
import json
import os
import sys
import tempfile
from pathlib import Path

VIDIOC_G_CTRL = 0xC008561B
VIDIOC_S_CTRL = 0xC008561C

CTRLS = {
    "brightness": 0x00980900,
    "contrast": 0x00980901,
    "saturation": 0x00980902,
    "hue": 0x00980903,
    "white_balance_automatic": 0x0098090C,
    "red_balance": 0x0098090E,
    "blue_balance": 0x0098090F,
    "gain": 0x00980913,
    "power_line_frequency": 0x00980918,
    "white_balance_temperature": 0x0098091A,
    "sharpness": 0x0098091B,
    "backlight_compensation": 0x0098091C,
    "auto_exposure": 0x009a0901,           # 0: Auto, 1: Manual, 3: Aperture Priority
    "exposure_time_absolute": 0x009a0902,  # 1..2500 (active when auto_exposure=1)
    "pan_absolute": 0x009a0908,            # -468000..468000 (step 3600)
    "tilt_absolute": 0x009a0909,           # -324000..324000 (step 3600)
    "focus_absolute": 0x009a090A,          # 0..100 (active when focus_automatic_continuous=0)
    "focus_automatic_continuous": 0x009a090C,
    "zoom_absolute": 0x009a090D,           # 0..100
}

class V4L2Control(ctypes.Structure):
    _fields_ = [("id", ctypes.c_uint32), ("value", ctypes.c_int32)]

CONFIG_PATH = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tinycam" / "presets.json"
USB_ID = ("3564", "fef9")
DISCONNECT_ERRORS = {errno.ENODEV, errno.ENXIO, errno.EIO, errno.EBADF}

DEFAULT_PRESETS = {
    "Face Center": {"pan_absolute": 0, "tilt_absolute": 0, "zoom_absolute": 0},
    "Desk View": {"pan_absolute": 0, "tilt_absolute": -162000, "zoom_absolute": 35},
    "Wide Room": {"pan_absolute": -72000, "tilt_absolute": -18000, "zoom_absolute": 0},
    "Privacy Sleep": {"pan_absolute": 0, "tilt_absolute": -288000, "zoom_absolute": 0},
}

def find_device(preferred="", sysfs=Path("/sys/class/video4linux"), dev_root=Path("/dev")):
    """Select the OBSBOT's primary video node, never an unrelated default camera."""
    matches = []
    for node in sysfs.glob("video*"):
        try:
            if (node / "index").read_text().strip() != "0":
                continue
            for parent in node.resolve().parents:
                if (parent / "idVendor").exists():
                    identity = ((parent / "idVendor").read_text().strip().lower(),
                                (parent / "idProduct").read_text().strip().lower())
                    if identity == USB_ID:
                        matches.append((dev_root / node.name).resolve())
                    break
        except OSError:
            continue  # The device may have disappeared during enumeration.
    if preferred:
        selected = Path(preferred).resolve()
        if selected not in matches:
            raise FileNotFoundError("Selected device is not an available OBSBOT Tiny 2 Lite video input")
        return str(selected)
    if not matches:
        raise FileNotFoundError("OBSBOT Tiny 2 Lite not connected")
    if len(matches) > 1:
        raise ValueError("Multiple OBSBOT cameras found; set the widget's device to a /dev/v4l/by-id/ path")
    return str(matches[0])


def read_presets(path):
    if not path.exists():
        return {}
    presets = json.loads(path.read_text())
    if not isinstance(presets, dict) or any(
        not isinstance(values, dict) or any(
            key not in CTRLS or type(value) is not int for key, value in values.items()
        ) for values in presets.values()
    ):
        raise ValueError("Invalid presets file; existing file has been preserved")
    return presets


def write_presets(path, presets):
    """Replace atomically, so an interrupted write cannot truncate saved presets."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(presets, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


class ObsbotDaemon:
    def __init__(self, device="", config_path=None):
        self.preferred_device = device
        self.device = ""
        self.fd = None
        self.config_path = CONFIG_PATH if config_path is None else Path(config_path)

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
        self.fd = None
        self.device = ""

    def connect(self):
        if self.fd is None:
            device = find_device(self.preferred_device)
            self.fd = os.open(device, os.O_RDWR | os.O_NONBLOCK)
            self.device = device
        # A control read also detects unplugging while the descriptor is open.
        self.get_ctrl("pan_absolute")

    def _sync_defaults(self):
        presets = read_presets(self.config_path)
        merged = {**DEFAULT_PRESETS, **presets}
        if merged != presets:
            write_presets(self.config_path, merged)
        return merged

    def get_ctrl(self, name: str) -> int:
        ctrl = V4L2Control(id=CTRLS[name], value=0)
        fcntl.ioctl(self.fd, VIDIOC_G_CTRL, ctrl)
        return ctrl.value

    def set_ctrl(self, name: str, value: int):
        if name not in CTRLS:
            raise ValueError(f"Unknown camera control: {name}")
        if name in ("pan_absolute", "tilt_absolute"):
            value = int(round(value / 3600.0) * 3600)
        elif name == "white_balance_temperature":
            value = int(round(value / 100.0) * 100)
        ctrl = V4L2Control(id=CTRLS[name], value=int(value))
        fcntl.ioctl(self.fd, VIDIOC_S_CTRL, ctrl)

    def get_all_state(self) -> dict:
        state = {}
        for name in CTRLS:
            try:
                state[name] = self.get_ctrl(name)
            except OSError as error:
                if error.errno in DISCONNECT_ERRORS:
                    raise
                # Unsupported controls are omitted rather than given fake values.
        return state

    def apply_preset(self, name: str):
        presets = self._sync_defaults()
        if name not in presets:
            raise ValueError(f"Unknown preset: {name}")
        for key, value in presets[name].items():
            self.set_ctrl(key, value)

    def save_preset(self, name: str):
        presets = self._sync_defaults()
        presets[name] = {key: self.get_ctrl(key) for key in
                         ("pan_absolute", "tilt_absolute", "zoom_absolute")}
        write_presets(self.config_path, presets)

    def handle_command(self, cmd):
        try:
            self.connect()
            action = cmd.get("action")
            if action == "set":
                self.set_ctrl(cmd["ctrl"], cmd["value"])
            elif action == "set_pt":
                self.set_ctrl("pan_absolute", cmd["pan"])
                self.set_ctrl("tilt_absolute", cmd["tilt"])
            elif action == "preset_apply":
                self.apply_preset(cmd["name"])
            elif action == "preset_save":
                self.save_preset(cmd["name"])
            elif action != "sync":
                raise ValueError(f"Unknown action: {action}")
            return {"status": "ok", "connected": True, "device": self.device,
                    "state": self.get_all_state(), "action": action}
        except Exception as error:
            state = {}
            # Re-read after failure: a two-control operation may have partly succeeded.
            if self.fd is not None:
                try:
                    self.get_ctrl("pan_absolute")
                    state = self.get_all_state()
                except OSError:
                    self.close()
            return {"status": "error", "message": str(error),
                    "connected": self.fd is not None, "device": self.device, "state": state}

    def run(self):
        def emit(message):
            print(json.dumps(message), flush=True)

        try:
            emit(self.handle_command({"action": "sync"}))
            for line in sys.stdin:
                if not line.strip():
                    continue
                try:
                    cmd = json.loads(line)
                    if not isinstance(cmd, dict):
                        raise ValueError("Command must be a JSON object")
                except (ValueError, TypeError) as error:
                    emit({"status": "error", "message": str(error)})
                    continue
                emit(self.handle_command(cmd))
        finally:
            self.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="", help="OBSBOT video device (prefer /dev/v4l/by-id/)")
    args = parser.parse_args()
    ObsbotDaemon(args.device).run()

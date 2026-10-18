#!/usr/bin/env python3
"""
TinyCam Studio Persistent Daemon for OBSBOT Tiny 2 Lite (3564:fef9)
Supports PTZ Gimbal XY, Presets, Optics (Focus/Zoom), Exposure, and Color/Kelvin.
"""
import ctypes
import fcntl
import json
import os
import sys
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

CONFIG_PATH = Path.home() / ".config" / "tinycam" / "presets.json"

DEFAULT_PRESETS = {
    "Face Center": {"pan_absolute": 0, "tilt_absolute": 0, "zoom_absolute": 0},
    "Desk View": {"pan_absolute": 0, "tilt_absolute": -162000, "zoom_absolute": 35},
    "Wide Room": {"pan_absolute": -72000, "tilt_absolute": -18000, "zoom_absolute": 0},
    "Privacy Sleep": {"pan_absolute": 0, "tilt_absolute": -288000, "zoom_absolute": 0},
}

class ObsbotDaemon:
    def __init__(self, device="/dev/video0"):
        self.fd = os.open(device, os.O_RDWR | os.O_NONBLOCK)
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        self._sync_defaults()

    def _sync_defaults(self):
        presets = {}
        if CONFIG_PATH.exists():
            try:
                presets = json.loads(CONFIG_PATH.read_text())
            except Exception:
                presets = {}
        presets.update(DEFAULT_PRESETS)
        CONFIG_PATH.write_text(json.dumps(presets, indent=2))

    def get_ctrl(self, name: str) -> int:
        ctrl = V4L2Control(id=CTRLS[name], value=0)
        fcntl.ioctl(self.fd, VIDIOC_G_CTRL, ctrl)
        return ctrl.value

    def set_ctrl(self, name: str, value: int):
        if name not in CTRLS:
            return
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
            except OSError:
                pass
        return state

    def apply_preset(self, name: str):
        presets = json.loads(CONFIG_PATH.read_text())
        if name in presets:
            for k, v in presets[name].items():
                try:
                    self.set_ctrl(k, v)
                except OSError:
                    pass

    def save_preset(self, name: str):
        presets = json.loads(CONFIG_PATH.read_text())
        presets[name] = {
            "pan_absolute": self.get_ctrl("pan_absolute"),
            "tilt_absolute": self.get_ctrl("tilt_absolute"),
            "zoom_absolute": self.get_ctrl("zoom_absolute"),
        }
        CONFIG_PATH.write_text(json.dumps(presets, indent=2))

    def run(self):
        print(json.dumps({"status": "ready", "state": self.get_all_state()}), flush=True)
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                cmd = json.loads(line)
                action = cmd.get("action")
                if action == "set":
                    self.set_ctrl(cmd["ctrl"], cmd["value"])
                elif action == "set_pt":
                    self.set_ctrl("pan_absolute", cmd["pan"])
                    self.set_ctrl("tilt_absolute", cmd["tilt"])
                elif action == "preset_apply":
                    self.apply_preset(cmd["name"])
                    print(json.dumps({"status": "ok", "state": self.get_all_state()}), flush=True)
                    continue
                elif action == "preset_save":
                    self.save_preset(cmd["name"])
                elif action == "sync":
                    print(json.dumps({"status": "ok", "state": self.get_all_state()}), flush=True)
                    continue
                print(json.dumps({"status": "ok"}), flush=True)
            except Exception as e:
                print(json.dumps({"status": "error", "message": str(e)}), flush=True)

if __name__ == "__main__":
    ObsbotDaemon().run()
#!/usr/bin/env python3
"""
TinyCam Studio Persistent Daemon for OBSBOT Tiny 2 4K (3564:fef9)
Supports PTZ Gimbal XY, Presets, Optics (Focus/Zoom), Exposure, and Color/Kelvin.
"""
import argparse
import ctypes
import errno
import fcntl
import json
import os
import sys
import signal
import tempfile
import time
from pathlib import Path

VIDIOC_G_CTRL = 0xC008561B
VIDIOC_S_CTRL = 0xC008561C
USBDEVFS_RESET = 0x5514
USBDEVFS_IOCTL = 0xC0105512
USBDEVFS_CONNECT = 0x5517

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

SDK_AI_CTRLS = {
    "ai_mode",               # 0: Off, 1: Group, 2: Human, 3: Hand, 4: Whiteboard, 5: Desk
    "ai_sub_mode",           # 0: Standard, 1: UpperBody, 2: CloseUp, 3: Headless, 4: LowerBody
    "ai_tracking_mode",      # 0: Standard, 1: Headroom, 2: Motion
    "ai_auto_zoom",          # 0: Off, 1: On
    "ai_zone_track",         # 0: Off, 1: On
    "gesture_target",        # 0: Off, 1: On
    "gesture_zoom",          # 0: Off, 1: On
    "gesture_dynamic_zoom",  # 0: Off, 1: On
    "gesture_mirror",        # 0: Off, 1: On
    "image_flip_hor",        # 0: Off, 1: On (Hardware UVC stream flip)
    "fov",                   # 0: 86° Wide, 1: 78° Medium, 2: 65° Narrow
    "hdr",                   # 0: Off, 1: On (Hardware WDR)
    "face_auto_focus",       # 0: Off, 1: On
    "face_ae",               # 0: Off, 1: On
    "zoom_speed",            # 0: Default, 1..10: Smooth speed
    "audio_auto_gain",       # 0: Off, 1: On
    "voice_hi_tiny",         # 0: Off, 1: On (Hi Tiny + Sleep Tiny)
    "voice_track",           # 0: Off, 1: On (Track Me + Unlock Me)
    "voice_zoom",            # 0: Off, 1: On (Zoom In + Zoom Out)
    "voice_preset",          # 0: Off, 1: On (Preset Position 1/2/3)
    "voice_ctrl_language",   # 0: Chinese, 1: English
    "dev_status",            # 1: Run/Wake, 3: Sleep, 4: Privacy
    "sleep_micro",           # 0: Mute mic in sleep, 1: Mic active in sleep
    "auto_sleep_time",       # Auto-sleep delay in seconds (0 = disabled)
}

GESTURE_TYPES = {
    "gesture_target": 0,
    "gesture_zoom": 1,
    "gesture_dynamic_zoom": 2,
    "gesture_mirror": 3,
}

VOICE_CMD_GROUPS = {
    "voice_hi_tiny": (0, 1),  # AudioCtrlHiTiny, AudioCtrlSleepTiny
    "voice_track": (2, 3),    # AudioCtrlTrack, AudioCtrlUnlock
    "voice_zoom": (4, 5),     # AudioCtrlZoomIn, AudioCtrlZoomOut
    "voice_preset": (6,),     # AudioCtrlPreset
}

class V4L2Control(ctypes.Structure):
    _fields_ = [("id", ctypes.c_uint32), ("value", ctypes.c_int32)]


class UsbdevfsIoctl(ctypes.Structure):
    _fields_ = [("ifno", ctypes.c_int), ("ioctl_code", ctypes.c_int), ("data", ctypes.c_void_p)]


class TinyCamAiState(ctypes.Structure):
    _fields_ = [
        ("ai_mode", ctypes.c_int32),
        ("ai_sub_mode", ctypes.c_int32),
        ("ai_tracking_mode", ctypes.c_int32),
        ("gesture_target", ctypes.c_int32),
        ("gesture_zoom", ctypes.c_int32),
        ("gesture_dynamic_zoom", ctypes.c_int32),
        ("gesture_mirror", ctypes.c_int32),
        ("ai_zone_track", ctypes.c_int32),
        ("hand_track_type", ctypes.c_int32),
        ("image_flip_hor", ctypes.c_int32),
        ("fov", ctypes.c_int32),
        ("hdr", ctypes.c_int32),
        ("face_ae", ctypes.c_int32),
        ("face_auto_focus", ctypes.c_int32),
        ("anti_flicker", ctypes.c_int32),
        ("audio_auto_gain", ctypes.c_int32),
        ("voice_ctrl", ctypes.c_int32),
        ("voice_ctrl_language", ctypes.c_int32),
        ("product_type", ctypes.c_int32),
        ("dev_status", ctypes.c_int32),
        ("sleep_micro", ctypes.c_int32),
        ("auto_sleep_time", ctypes.c_int32),
    ]


class ObsbotSdkBridge:
    POLL_INTERVAL_SECONDS = 10.0

    def __init__(self, base_dir=None):
        self.lib = None
        self._last_poll = 0.0
        root = Path(__file__).resolve().parent if base_dir is None else Path(base_dir)
        sdk_candidates = (
            root / "libdev.so.1.0.0",
            root / "libdev.so",
            root / "Osbot_SDK" / "linux" / "x86_64-release" / "libdev.so",
        )
        bridge_so = root / "libtinycam_sdk.so"
        if not bridge_so.exists():
            return
        try:
            for sdk_so in sdk_candidates:
                if sdk_so.exists():
                    ctypes.CDLL(str(sdk_so), mode=ctypes.RTLD_GLOBAL)
                    break
            lib = ctypes.CDLL(str(bridge_so))
            lib.tinycam_sdk_get_ai_state.argtypes = [ctypes.c_char_p, ctypes.POINTER(TinyCamAiState)]
            lib.tinycam_sdk_get_ai_state.restype = ctypes.c_int
            lib.tinycam_sdk_set_ai_mode.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
            lib.tinycam_sdk_set_ai_mode.restype = ctypes.c_int
            lib.tinycam_sdk_set_tracking_mode.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_tracking_mode.restype = ctypes.c_int
            lib.tinycam_sdk_set_auto_zoom.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_auto_zoom.restype = ctypes.c_int
            lib.tinycam_sdk_set_gesture.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
            lib.tinycam_sdk_set_gesture.restype = ctypes.c_int
            lib.tinycam_sdk_set_zone_track.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_zone_track.restype = ctypes.c_int
            lib.tinycam_sdk_set_image_flip.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_image_flip.restype = ctypes.c_int
            lib.tinycam_sdk_set_fov.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_fov.restype = ctypes.c_int
            lib.tinycam_sdk_set_hdr.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_hdr.restype = ctypes.c_int
            lib.tinycam_sdk_set_face_focus.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_face_focus.restype = ctypes.c_int
            lib.tinycam_sdk_set_face_ae.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_face_ae.restype = ctypes.c_int
            lib.tinycam_sdk_set_zoom_with_speed.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
            lib.tinycam_sdk_set_zoom_with_speed.restype = ctypes.c_int
            lib.tinycam_sdk_set_audio_auto_gain.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_audio_auto_gain.restype = ctypes.c_int
            lib.tinycam_sdk_set_voice_ctrl.argtypes = [ctypes.c_char_p, ctypes.c_int32, ctypes.c_int32]
            lib.tinycam_sdk_set_voice_ctrl.restype = ctypes.c_int
            lib.tinycam_sdk_set_anti_flicker.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_anti_flicker.restype = ctypes.c_int
            lib.tinycam_sdk_set_dev_status.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_dev_status.restype = ctypes.c_int
            lib.tinycam_sdk_set_sleep_micro.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_sleep_micro.restype = ctypes.c_int
            lib.tinycam_sdk_set_auto_sleep_time.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_set_auto_sleep_time.restype = ctypes.c_int
            lib.tinycam_sdk_trigger_hw_preset.argtypes = [ctypes.c_char_p, ctypes.c_int32]
            lib.tinycam_sdk_trigger_hw_preset.restype = ctypes.c_int
            lib.tinycam_sdk_save_hw_preset.argtypes = [
                ctypes.c_char_p, ctypes.c_int32, ctypes.c_float, ctypes.c_float, ctypes.c_float
            ]
            lib.tinycam_sdk_save_hw_preset.restype = ctypes.c_int
            lib.tinycam_sdk_close.argtypes = []
            lib.tinycam_sdk_close.restype = None
            self.lib = lib
        except OSError:
            self.lib = None

    @property
    def available(self) -> bool:
        return self.lib is not None

    def get_state(self, device: str, cache: dict, force: bool = False) -> dict:
        if not self.lib or not device or not os.path.exists(device):
            return dict(cache)
        now = time.monotonic()
        if not force and cache and (now - self._last_poll) < self.POLL_INTERVAL_SECONDS:
            return dict(cache)
        raw = TinyCamAiState()
        if self.lib.tinycam_sdk_get_ai_state(device.encode(), ctypes.byref(raw)) != 0:
            return dict(cache)
        self._last_poll = now
        vmask = int(raw.voice_ctrl)
        state = {
            "ai_mode": int(raw.ai_mode),
            "ai_sub_mode": int(raw.ai_sub_mode),
            "ai_tracking_mode": int(raw.ai_tracking_mode),
            "ai_auto_zoom": int(cache.get("ai_auto_zoom", 1)),
            "ai_zone_track": int(raw.ai_zone_track),
            "gesture_target": int(raw.gesture_target),
            "gesture_zoom": int(raw.gesture_zoom),
            "gesture_dynamic_zoom": int(raw.gesture_dynamic_zoom),
            "gesture_mirror": int(raw.gesture_mirror),
            "image_flip_hor": int(raw.image_flip_hor),
            "fov": int(raw.fov),
            "hdr": int(raw.hdr),
            "face_ae": int(raw.face_ae),
            "face_auto_focus": int(raw.face_auto_focus),
            "zoom_speed": int(cache.get("zoom_speed", 0)),
            "audio_auto_gain": int(raw.audio_auto_gain),
            "voice_hi_tiny": 1 if (vmask & 0b0000011) else 0,
            "voice_track": 1 if (vmask & 0b0110000) or (vmask & 0b0001100) else 0,
            "voice_zoom": 1 if (vmask & 0b0001100) or (vmask & 0b0110000) else 0,
            "voice_preset": 1 if (vmask & 0b1000000) else 0,
            "voice_ctrl_language": int(raw.voice_ctrl_language),
            "product_type": int(raw.product_type),
            "dev_status": int(raw.dev_status) if int(raw.dev_status) > 0 else 1,
            "sleep_micro": int(raw.sleep_micro),
            "auto_sleep_time": max(0, int(raw.auto_sleep_time)),
        }
        for key in ("voice_hi_tiny", "voice_track", "voice_zoom", "voice_preset"):
            if key in cache:
                state[key] = int(cache[key])
        cache.update(state)
        return state

    def set_ai_mode(self, device: str, mode: int, sub_mode: int, cache: dict):
        if not self.lib:
            raise RuntimeError("OBSBOT SDK bridge library (libtinycam_sdk.so) is not loaded")
        if self.lib.tinycam_sdk_set_ai_mode(device.encode(), int(mode), int(sub_mode)) != 0:
            raise OSError(errno.EIO, "OBSBOT SDK failed to set AI tracking mode")
        cache["ai_mode"] = int(mode)
        if int(mode) == 2:
            cache["ai_sub_mode"] = int(sub_mode)
        self._last_poll = time.monotonic()

    def set_zoom_with_speed(self, device: str, zoom_percent: int, speed: int) -> bool:
        if not self.lib:
            return False
        return self.lib.tinycam_sdk_set_zoom_with_speed(device.encode(), int(zoom_percent), int(speed)) == 0

    def trigger_hw_preset(self, device: str, preset_id: int):
        if not self.lib:
            raise RuntimeError("OBSBOT SDK bridge library (libtinycam_sdk.so) is not loaded")
        if self.lib.tinycam_sdk_trigger_hw_preset(device.encode(), int(preset_id)) != 0:
            raise OSError(errno.EIO, f"OBSBOT SDK failed to trigger hardware preset {preset_id + 1}")

    def save_hw_preset(self, device: str, preset_id: int, yaw_deg: float, pitch_deg: float, zoom_ratio: float):
        if not self.lib:
            raise RuntimeError("OBSBOT SDK bridge library (libtinycam_sdk.so) is not loaded")
        rc = self.lib.tinycam_sdk_save_hw_preset(
            device.encode(), int(preset_id), float(yaw_deg), float(pitch_deg), float(zoom_ratio)
        )
        if rc != 0:
            raise OSError(errno.EIO, f"OBSBOT SDK failed to save hardware preset {preset_id + 1}")

    def set_ctrl(self, device: str, name: str, value: int, cache: dict):
        if not self.lib:
            raise RuntimeError("OBSBOT SDK bridge library (libtinycam_sdk.so) is not loaded")
        dev_bytes = device.encode()
        val = int(value)
        if name == "ai_mode":
            sub_mode = int(cache.get("ai_sub_mode", 0)) if val == 2 else 0
            self.set_ai_mode(device, val, sub_mode, cache)
            return
        if name == "ai_sub_mode":
            self.set_ai_mode(device, 2, val, cache)
            return
        if name == "zoom_speed":
            cache["zoom_speed"] = max(0, min(10, val))
            return
        if name == "ai_tracking_mode":
            rc = self.lib.tinycam_sdk_set_tracking_mode(dev_bytes, val)
        elif name == "ai_auto_zoom":
            rc = self.lib.tinycam_sdk_set_auto_zoom(dev_bytes, val)
        elif name == "ai_zone_track":
            rc = self.lib.tinycam_sdk_set_zone_track(dev_bytes, val)
        elif name in GESTURE_TYPES:
            rc = self.lib.tinycam_sdk_set_gesture(dev_bytes, GESTURE_TYPES[name], val)
        elif name == "image_flip_hor":
            rc = self.lib.tinycam_sdk_set_image_flip(dev_bytes, val)
        elif name == "fov":
            rc = self.lib.tinycam_sdk_set_fov(dev_bytes, val)
        elif name == "hdr":
            rc = self.lib.tinycam_sdk_set_hdr(dev_bytes, val)
        elif name == "face_auto_focus":
            rc = self.lib.tinycam_sdk_set_face_focus(dev_bytes, val)
        elif name == "face_ae":
            rc = self.lib.tinycam_sdk_set_face_ae(dev_bytes, val)
        elif name == "audio_auto_gain":
            rc = self.lib.tinycam_sdk_set_audio_auto_gain(dev_bytes, val)
        elif name == "voice_ctrl_language":
            rc = self.lib.tinycam_sdk_set_voice_ctrl(dev_bytes, 101, val)
        elif name in VOICE_CMD_GROUPS:
            rc = 0
            for cmd_id in VOICE_CMD_GROUPS[name]:
                if self.lib.tinycam_sdk_set_voice_ctrl(dev_bytes, cmd_id, 1 if val else 0) != 0:
                    rc = -1
        elif name == "dev_status":
            rc = self.lib.tinycam_sdk_set_dev_status(dev_bytes, val)
        elif name == "sleep_micro":
            rc = self.lib.tinycam_sdk_set_sleep_micro(dev_bytes, val)
        elif name == "auto_sleep_time":
            rc = self.lib.tinycam_sdk_set_auto_sleep_time(dev_bytes, val)
        else:
            raise ValueError(f"Unknown SDK control: {name}")
        if rc != 0:
            raise OSError(errno.EIO, f"OBSBOT SDK rejected {name}={val}")
        cache[name] = val
        self._last_poll = time.monotonic()

    def close(self):
        if self.lib:
            self.lib.tinycam_sdk_close()

CONFIG_PATH = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "tinycam" / "presets.json"
USB_ID = ("3564", "fef9")
EXTRA_OBSBOT_USB_IDS = {("3564", "fef8"), ("3564", "feef"), ("3564", "fef1")}
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
                    if identity == USB_ID or (USB_ID == ("3564", "fef9") and identity in EXTRA_OBSBOT_USB_IDS):
                        matches.append((dev_root / node.name).resolve())
                    break
        except OSError:
            continue  # The device may have disappeared during enumeration.
    if preferred:
        selected = Path(preferred).resolve()
        if selected not in matches:
            raise FileNotFoundError("Selected device is not an available OBSBOT Tiny 2 4k video input")
        return str(selected)
    if not matches:
        raise FileNotFoundError("OBSBOT Tiny 2 4k not connected")
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
    def __init__(self, device="", config_path=None, sdk=None):
        self.preferred_device = device
        self.device = ""
        self.fd = None
        self.config_path = CONFIG_PATH if config_path is None else Path(config_path)
        self.sdk = ObsbotSdkBridge() if sdk is None else sdk
        self._ai_cache = {}

    def close(self):
        if self.fd is not None:
            os.close(self.fd)
        self.fd = None
        self.device = ""

    def shutdown(self):
        self.close()
        if self.sdk:
            self.sdk.close()

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
        if name in SDK_AI_CTRLS:
            self.sdk.set_ctrl(self.device, name, int(value), self._ai_cache)
            return
        if name not in CTRLS:
            raise ValueError(f"Unknown camera control: {name}")
        if name == "zoom_absolute" and self.sdk and self.sdk.available:
            speed = int(self._ai_cache.get("zoom_speed", 0))
            if speed > 0 and self.sdk.set_zoom_with_speed(self.device, int(value), speed):
                return
        if name in ("pan_absolute", "tilt_absolute"):
            value = int(round(value / 3600.0) * 3600)
        elif name == "white_balance_temperature":
            value = int(round(value / 100.0) * 100)
        ctrl = V4L2Control(id=CTRLS[name], value=int(value))
        fcntl.ioctl(self.fd, VIDIOC_S_CTRL, ctrl)

    def set_ai_mode(self, mode: int, sub_mode: int = 0):
        self.sdk.set_ai_mode(self.device, int(mode), int(sub_mode), self._ai_cache)

    def get_all_state(self) -> dict:
        state = {}
        for name in CTRLS:
            try:
                state[name] = self.get_ctrl(name)
            except OSError as error:
                if error.errno in DISCONNECT_ERRORS:
                    raise
                # Unsupported controls are omitted rather than given fake values.
        if self.sdk and self.sdk.available:
            state.update(self.sdk.get_state(self.device, self._ai_cache))
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

    def apply_hw_preset(self, preset_id: int):
        self.sdk.trigger_hw_preset(self.device, int(preset_id))

    def save_hw_preset(self, preset_id: int):
        try:
            yaw_deg = self.get_ctrl("pan_absolute") / 3600.0
            pitch_deg = self.get_ctrl("tilt_absolute") / 3600.0
            zoom_ratio = 1.0 + max(0, min(100, self.get_ctrl("zoom_absolute"))) / 100.0
        except OSError:
            yaw_deg, pitch_deg, zoom_ratio = 0.0, 0.0, 1.0
        self.sdk.save_hw_preset(self.device, int(preset_id), yaw_deg, pitch_deg, zoom_ratio)

    def handle_command(self, cmd):
        try:
            self.connect()
            action = cmd.get("action")
            if action == "set":
                self.set_ctrl(cmd["ctrl"], cmd["value"])
            elif action == "set_ai_mode":
                self.set_ai_mode(cmd["mode"], cmd.get("sub_mode", 0))
            elif action == "set_pt":
                self.set_ctrl("pan_absolute", cmd["pan"])
                self.set_ctrl("tilt_absolute", cmd["tilt"])
            elif action == "preset_apply":
                self.apply_preset(cmd["name"])
            elif action == "preset_save":
                self.save_preset(cmd["name"])
            elif action == "hw_preset_apply":
                self.apply_hw_preset(cmd["id"])
            elif action == "hw_preset_save":
                self.save_hw_preset(cmd["id"])
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
            return {"status": "error", "message": str(error), "action": cmd.get("action"),
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
            self.shutdown()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default="", help="OBSBOT video device (prefer /dev/v4l/by-id/)")
    args = parser.parse_args()
    ObsbotDaemon(args.device).run()

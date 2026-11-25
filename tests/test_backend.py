import errno
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

import tinycam_backend as backend


class DeviceDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sysfs = self.root / 'class'
        self.sysfs.mkdir()
        self.dev = self.root / 'dev'
        self.dev.mkdir()

    def add_device(self, name, usb='obsbot', identity=backend.USB_ID, index=0):
        parent = self.root / 'devices' / usb
        parent.mkdir(parents=True, exist_ok=True)
        (parent / 'idVendor').write_text(identity[0])
        (parent / 'idProduct').write_text(identity[1])
        node = parent / 'interface' / 'video4linux' / name
        node.mkdir(parents=True)
        (node / 'index').write_text(str(index))
        (self.sysfs / name).symlink_to(node)
        (self.dev / name).touch()
        return str(self.dev / name)

    def find(self, preferred=''):
        return backend.find_device(preferred, self.sysfs, self.dev)

    def test_selects_obsbot_after_unrelated_camera_and_skips_metadata(self):
        self.add_device('video0', 'other', ('1234', '5678'))
        selected = self.add_device('video2')
        self.add_device('video3', index=1)
        self.assertEqual(self.find(), selected)

    def test_never_falls_back_to_unrelated_camera(self):
        self.add_device('video0', 'other', ('1234', '5678'))
        with self.assertRaises(FileNotFoundError):
            self.find()

    def test_multiple_cameras_require_selection_and_accept_stable_symlink(self):
        first = self.add_device('video2')
        self.add_device('video4', 'second')
        with self.assertRaises(ValueError):
            self.find()
        stable = self.dev / 'by-id-camera'
        stable.symlink_to(first)
        self.assertEqual(self.find(str(stable)), first)

    def test_explicit_unrelated_device_is_rejected(self):
        other = self.add_device('video0', 'other', ('1234', '5678'))
        self.add_device('video2')
        with self.assertRaises(FileNotFoundError):
            self.find(other)


class PresetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'presets.json'
        self.daemon = backend.ObsbotDaemon(config_path=self.path)

    def test_saved_builtin_and_custom_presets_survive_restart(self):
        saved = {'pan_absolute': 72000, 'tilt_absolute': -18000, 'zoom_absolute': 25}
        with patch.object(self.daemon, 'get_ctrl', side_effect=saved.__getitem__):
            self.daemon.save_preset('Face Center')
            self.daemon.save_preset('My desk')
        restarted = backend.ObsbotDaemon(config_path=self.path)
        presets = restarted._sync_defaults()
        self.assertEqual(presets['Face Center'], saved)
        self.assertEqual(presets['My desk'], saved)
        self.assertEqual(presets['Wide Room'], backend.DEFAULT_PRESETS['Wide Room'])

    def test_existing_complete_presets_are_not_rewritten(self):
        self.daemon._sync_defaults()
        with patch.object(backend, 'write_presets') as write:
            self.daemon._sync_defaults()
            write.assert_not_called()

    def test_corrupt_or_invalid_files_are_preserved(self):
        for invalid in ('broken JSON', '[]', '{"Face Center": {"pan_absolute": "oops"}}'):
            with self.subTest(invalid=invalid):
                self.path.write_text(invalid)
                with self.assertRaises(ValueError):
                    self.daemon._sync_defaults()
                self.assertEqual(self.path.read_text(), invalid)

    def test_failed_replace_preserves_previous_file_and_cleans_temporary(self):
        self.path.write_text('{"existing": {}}')
        with patch.object(Path, 'replace', side_effect=OSError('disk error')):
            with self.assertRaises(OSError):
                backend.write_presets(self.path, backend.DEFAULT_PRESETS)
        self.assertEqual(self.path.read_text(), '{"existing": {}}')
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.daemon = backend.ObsbotDaemon()
        self.state = {'pan_absolute': 0, 'tilt_absolute': 0, 'brightness': 32}
        self.connected = True
        self.reject_write = False
        self.addCleanup(patch.stopall)
        patch.object(backend, 'find_device', return_value='/dev/video2').start()
        patch.object(backend.os, 'open', return_value=42).start()
        self.close_mock = patch.object(backend.os, 'close').start()
        patch.object(backend.fcntl, 'ioctl', side_effect=self.ioctl).start()

    def ioctl(self, fd, operation, ctrl):
        if not self.connected:
            raise OSError(errno.ENODEV, 'Device disconnected')
        name = next(key for key, value in backend.CTRLS.items() if value == ctrl.id)
        if name not in self.state or (operation == backend.VIDIOC_S_CTRL and self.reject_write):
            raise OSError(errno.EINVAL, 'Unsupported control value')
        if operation == backend.VIDIOC_G_CTRL:
            ctrl.value = self.state[name]
        else:
            # Simulate the camera clamping a requested value.
            self.state[name] = min(ctrl.value, 64) if name == 'brightness' else ctrl.value

    def test_set_returns_confirmed_value_including_zero(self):
        response = self.daemon.handle_command({'action': 'set', 'ctrl': 'brightness', 'value': 90})
        self.assertEqual(response['state']['brightness'], 64)
        response = self.daemon.handle_command({'action': 'set', 'ctrl': 'brightness', 'value': 0})
        self.assertEqual(response['state']['brightness'], 0)
        self.assertTrue(response['connected'])
        self.assertEqual(response['device'], '/dev/video2')

    def test_failed_command_reports_error_and_actual_state(self):
        self.reject_write = True
        response = self.daemon.handle_command({'action': 'set', 'ctrl': 'brightness', 'value': 90})
        self.assertEqual(response['status'], 'error')
        self.assertIn('Unsupported control value', response['message'])
        self.assertEqual(response['state']['brightness'], 32)
        self.assertTrue(response['connected'])

    def test_unplug_and_reconnect(self):
        self.daemon.handle_command({'action': 'sync'})
        self.connected = False
        response = self.daemon.handle_command({'action': 'sync'})
        self.assertFalse(response['connected'])
        self.assertEqual(response['device'], '')
        self.assertEqual(response['state'], {})
        self.close_mock.assert_called_once_with(42)
        self.connected = True
        response = self.daemon.handle_command({'action': 'sync'})
        self.assertTrue(response['connected'])
        self.assertEqual(response['status'], 'ok')

    def test_no_camera_at_start_then_reconnect(self):
        with patch.object(backend, 'find_device', side_effect=FileNotFoundError('No camera')):
            response = self.daemon.handle_command({'action': 'sync'})
        self.assertFalse(response['connected'])
        self.assertEqual(response['message'], 'No camera')
        self.assertTrue(self.daemon.handle_command({'action': 'sync'})['connected'])

    def test_protocol_survives_bad_json_and_closes_on_eof(self):
        output = io.StringIO()
        with patch.object(backend.sys, 'stdin', io.StringIO('bad\n[]\n{"action":"sync"}\n')), redirect_stdout(output):
            self.daemon.run()
        responses = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([response['status'] for response in responses], ['ok', 'error', 'error', 'ok'])
        self.close_mock.assert_called_once_with(42)
        self.assertIsNone(self.daemon.fd)

    def test_sdk_bridge_loads_from_plugin_root_and_throttles_polls(self):
        bridge = backend.ObsbotSdkBridge()
        self.assertTrue(bridge.available)
        calls = []

        def fake_get_ai_state(_dev, raw_ptr):
            calls.append(_dev)
            raw_ptr._obj.ai_mode = 2
            raw_ptr._obj.ai_sub_mode = 1
            raw_ptr._obj.dev_status = 1
            return 0

        with patch.object(backend.os.path, 'exists', return_value=True), \
             patch.object(bridge.lib, 'tinycam_sdk_get_ai_state', side_effect=fake_get_ai_state), \
             patch.object(bridge.lib, 'tinycam_sdk_set_ai_mode', return_value=0) as set_ai:
            daemon = backend.ObsbotDaemon(sdk=bridge)
            first = daemon.handle_command({'action': 'sync'})
            self.assertEqual(first['state']['ai_mode'], 2)
            self.assertEqual(len(calls), 1)
            second = daemon.handle_command({'action': 'sync'})
            self.assertEqual(second['state']['ai_mode'], 2)
            self.assertEqual(len(calls), 1)
            updated = daemon.handle_command({'action': 'set_ai_mode', 'mode': 1, 'sub_mode': 0})
            set_ai.assert_called_once_with(b'/dev/video2', 1, 0)
            self.assertEqual(updated['state']['ai_mode'], 1)
            self.assertEqual(len(calls), 1)


if __name__ == '__main__':
    unittest.main()

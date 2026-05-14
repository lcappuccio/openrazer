# OpenRazer Custom Setup Documentation

## Hardware
- **Keyboard**: Razer Huntsman V3 X TKL (USB `1532:02B1`)
- **Mouse**: Razer Basilisk V3 (USB `1532:0099`)
- **OS**: Ubuntu 24.04
- **Kernel**: 6.17.x (generic)

---

## Overview

The upstream OpenRazer PPA package (`openrazer-driver-dkms`) did not support the Huntsman V3 X TKL at the time of setup. Additionally, the upstream `razermouse` driver contained a regression that broke the Basilisk V3 scroll mode toggle button. The ripple effect also lacked a configurable base color, leaving the keyboard unlit between keypresses.

All fixes are implemented as patches on top of the upstream source, maintained in a personal fork:
**https://github.com/lcappuccio/openrazer**

---

## Driver Changes

### 1. Razer Huntsman V3 X TKL Support (`razerkbd`)

Files modified:
- `driver/razerkbd_driver.h` — added `USB_DEVICE_ID_RAZER_HUNTSMAN_V3_X_TKL 0x02B1`
- `driver/razerkbd_driver.c` — added device to all relevant switch cases and `CREATE_DEVICE_FILE` probe section, with its own case (not sharing `BLACKWIDOW_V4_X`) and **without** `game_led_state`, `macro_led_state`, `macro_led_effect`, and `matrix_effect_wheel` (not supported by hardware)
- `daemon/openrazer_daemon/hardware/keyboards.py` — added `RazerHuntsmanV3XTKL` class with correct `EVENT_FILE_REGEX`:
  ```python
  EVENT_FILE_REGEX = re.compile(r'.*Razer_Huntsman_V3_X_Tenkeyless-if01-event-kbd')
  ```
  Note: the regex must match the actual `/dev/input/by-id/` filename, which uses `Tenkeyless` not `TKL`. A wrong regex causes `No event files for KeyWatcher` and breaks the ripple effect.
- `install_files/udev/99-razer.rules` — added `02b1` to the keyboards product ID list
- `README.md` — added device entry

### 2. Basilisk V3 Scroll Mode Toggle Button Fix (`razermouse`)

**Root cause**: The `REP4_SCROLL (0x54)` mapping was added to handle the Basilisk Mobile, intercepting the scroll toggle button's HID report (`04 54 00...`) and mapping it to `BTN_MOUSE+12`. However, this mapping never sent the actual firmware toggle command, breaking the physical button on the Basilisk V3.

**Fix**: Added a workqueue to defer the firmware call out of interrupt context (`raw_event` cannot sleep):

Files modified:
- `driver/razermouse_driver.h` — added `scroll_mode` and `scroll_toggle_work` fields to `razer_mouse_device` struct
- `driver/razermouse_driver.c`:
  - Added `scroll_toggle_worker()` function that calls `razer_chroma_misc_set_scroll_mode()` with toggled value
  - Added `INIT_WORK()` in `razer_mouse_init()`
  - In `razer_raw_event()`, intercept `REP4_SCROLL` and call `schedule_work()` instead of emitting a key event

### 3. Ripple Effect Base Color (`ripple_effect.py`)

**Problem**: The ripple effect leaves all non-rippling keys black, making the keyboard unlit unless a key is being pressed.

**Fix**: `daemon/openrazer_daemon/misc/ripple_effect.py` reads a base color from a user config file and fills the keyboard matrix with it before applying the ripple overlay each frame.

Config file: `~/.config/openrazer/ripple_base_color.json`

```json
{
    "r": 0,
    "g": 255,
    "b": 255,
    "enabled": true
}
```

Set `"enabled": false` to revert to default black background without deleting the file.

The config is read each time the ripple effect is enabled (i.e. when Polychromatic activates it), so changes take effect after restarting the daemon — no reinstall needed.

---

## System-Level Setup

### User Groups

The user must be in both `plugdev` and `input` groups:

```bash
sudo usermod -aG plugdev $USER
sudo usermod -aG input $USER
```

Log out and back in (or restart the user systemd session) for group changes to take effect.

- `plugdev` — required for openrazer daemon to access sysfs device files
- `input` — required for openrazer daemon to open `/dev/input/` event files for keyboard

### udev Rules

The stock `99-razer.rules` fires `razer_mount` on device `add` events. However, `razerkbd` may load after udev has already processed the keyboard HID events, meaning permissions are never set for the keyboard at boot.

Fix: add a bind-time udev rule in `/etc/udev/rules.d/` (survives package upgrades):

```bash
sudo vi /etc/udev/rules.d/99-razer-plugdev.rules
```

```
ACTION=="bind", DRIVER=="razerkbd", RUN+="/usr/lib/udev/razer_mount razerkbd $kernel"
ACTION=="bind", DRIVER=="razermouse", RUN+="/usr/lib/udev/razer_mount razermouse $kernel"
```

```bash
sudo udevadm control --reload-rules
```

### Polychromatic Device Database

The installed Polychromatic package (0.9.6) predates the Huntsman V3 X TKL entry in the upstream database. The device must be added to `/usr/share/polychromatic/devices/openrazer.json`:

```json
"1532:02B1": {
    "form_factor": "keyboard",
    "matrix": "18,6",
    "name": "Razer Huntsman V3 X TKL",
    "since": "3.12.0"
},
```

This is handled automatically by the install script.

---

## DKMS

The upstream `openrazer-driver-dkms` package manages the kernel modules via DKMS. On package upgrade, the DKMS source tree (`/usr/src/openrazer-driver-X.Y.Z/`) is overwritten with stock files, losing custom changes.

The install script handles this by copying the custom driver sources to the DKMS tree before building.

**Important**: The DKMS version directory changes on package upgrades (e.g. `3.12.0` → `3.12.2`). The install script detects this dynamically.

**Important**: After a DKMS rebuild, stale uncompressed `.ko` files may remain alongside the new `.ko.zst` files and take precedence. The install script removes them explicitly.

---

## Install Script

Located at `/home/leo/Projects/openrazer/install_razer_drivers.sh`.

Run after:
- Kernel upgrades
- `openrazer-driver-dkms` package upgrades
- Any driver source changes

```bash
cd /home/leo/Projects/openrazer
./install_razer_drivers.sh
```

The script:
1. Detects current DKMS version dynamically
2. Copies custom driver sources to the DKMS tree
3. Builds all kernel modules
4. Installs `.ko.zst` modules, removing stale uncompressed `.ko` files
5. Runs `depmod`
6. Reloads `razerkbd` and `razermouse` modules
7. Reinstalls the daemon Python egg
8. Fixes sysfs permissions via `razer_mount` and `chgrp`
9. Restarts `openrazer-daemon`
10. Patches Polychromatic device database if needed
11. Initialises mouse scroll mode to tactile (0)

---

## Permissions Fix Script

Located at `/home/leo/Projects/openrazer/fix_razer_permissions.sh`.

Run if devices show as `?` in Polychromatic after reboot or daemon restart:

```bash
#!/bin/bash
set -e

for dev in /sys/bus/hid/drivers/razerkbd/0003:1532:*/; do
    sudo chgrp -R plugdev "$dev"
done

for id in $(ls /sys/bus/hid/drivers/razermouse/ | grep "1532:0099"); do
    sudo /usr/lib/udev/razer_mount razermouse "$id"
done

systemctl --user restart openrazer-daemon
```

With the `/etc/udev/rules.d/99-razer-plugdev.rules` bind rule in place, this should not be necessary on normal reboots.

---

## Upstream PRs

- **Keyboard support**: https://github.com/openrazer/openrazer/pull/2766
- **Mouse scroll button fix**: https://github.com/openrazer/openrazer/pull/2767

---

## Known Limitations

- No lighting at the GDM login screen — daemon is a user service, starts after login; devices have no onboard memory
- Scroll wheel lighting zone (`matrix_effect_wheel`) not supported — hardware doesn't have it
- Game mode and macro LEDs not exposed — hardware has the keys but no dedicated LEDs
- Lighting settings do not persist across daemon restarts without Polychromatic applying them
- Ripple base color change requires daemon restart to take effect
- The entire setup must be reapplied after `openrazer-driver-dkms` package upgrades via `install_razer_drivers.sh`
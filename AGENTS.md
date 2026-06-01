# AGENTS.md

## Project Overview

OpenRazer is a collection of open-source Linux drivers for Razer peripherals (keyboards, mice, headsets, mouse mats, accessories). It consists of three components versioned together:

- **kernel module** (`driver/`) — C, exposes a sysfs interface to Razer USB devices via Linux USB HID
- **DBus daemon** (`daemon/`) — Python 3, wraps the kernel interface and exposes it over DBus as `openrazer_daemon`
- **Python client library** (`pylib/`) — Python 3, provides `openrazer` package for apps to communicate with the daemon over DBus

## Setup Commands

### System dependencies (Debian/Ubuntu)
```bash
# Kernel module development
apt-get install -y make gcc flex bison bc linux-headers-$(uname -r)

# Daemon/library development
apt-get install -y libnotify-bin python3 python3-daemonize python3-dbus python3-gi python3-numpy python3-pyudev python3-setproctitle

# Linting/formatting (CI only)
apt-get install -y astyle autopep8 pylint
```

### Build kernel module
```bash
make driver
```

### Test daemon from source
```bash
PYTHONPATH="pylib:daemon" python3 ./daemon/run_openrazer_daemon.py -Fv --config=$PWD/daemon/resources/razer.conf
```

### Run tests
```bash
# Run all validation scripts
make -C driver clean
scripts/ci/check-astyle-formatting.sh
scripts/ci/check-autopep8-formatting.sh
scripts/ci/check-pylint.sh
scripts/ci/test-vermin.sh
scripts/ci/test-hex-casing.sh
scripts/ci/test-auto-generate.sh
scripts/ci/test-daemon.sh
```

### Format source code (auto-fix)
```bash
./scripts/format_source.sh
```

### Generate auto-generated files
```bash
./scripts/generate_appstream_file.sh
./scripts/generate_all_fake_drivers.sh -f
```

## Development Workflow

### Add new device support

1. Find VID/PID via `lsusb` (Razer VID is `1532`)
2. Append device to **README.md** (ordered by type, then by VID:PID)
3. Create device class in `daemon/openrazer_daemon/hardware/[device_type].py` (use existing devices as reference)
4. Add PID constant in `driver/razer[device_type]_driver.h` (e.g. `#define USB_DEVICE_ID_RAZER_STRIDER_CHROMA 0x0C05`)
5. Add device support in `driver/razer[device_type]_driver.c` (sysfs attributes, USB communication, features/effects)
6. Append PID to `install_files/udev/99-razer.rules`
7. Run `./scripts/format_source.sh`
8. Run `./scripts/generate_appstream_file.sh`
9. Run `./scripts/generate_all_fake_drivers.sh -f`

### Working with the daemon

- The daemon cannot run in a virtualenv — must use system site-packages
- Set `PYTHONPATH="pylib:daemon"` to run from sources
- Configuration: `daemon/resources/razer.conf`

### Working with the kernel module

- Recommended to test in a VM (QEMU with USB passthrough recommended)
- Reload a module: `rmmod razerkbd && insmod razerkbd.ko`
- Driver messages: `dmesg`
- Kernel modules built: `razerkbd.ko`, `razermouse.ko`, `razerkraken.ko`, `razeraccessory.ko`

## Testing Instructions

- **C formatting**: `scripts/ci/check-astyle-formatting.sh` (style: linux, tool: astyle)
- **Python formatting**: `scripts/ci/check-autopep8-formatting.sh` (max-line-length 500, ignore E402)
- **Python linting**: `scripts/ci/check-pylint.sh` (errors only)
- **Python version compat**: `scripts/ci/test-vermin.sh` (target: Python 3.9+)
- **Hex casing**: `scripts/ci/test-hex-casing.sh`
- **Auto-generation**: `scripts/ci/test-auto-generate.sh`
- **Functional**: `scripts/ci/test-daemon.sh` (sets up fake driver, launches daemon)
- **Unit tests**: `python3 -m unittest discover -s daemon/tests` and `python3 -m unittest discover -s pylib/tests`

## Code Style

- **C**: `--style=linux` via astyle. Run `scripts/format_source.sh` to auto-fix.
- **Python**: autopep8 with `--max-line-length 500 --ignore E402`. Run `scripts/format_source.sh` to auto-fix.
- **Naming**: Python uses `snake_case`. C follows Linux kernel style.
- **Import ordering**: Standard library first, then third-party, then local (E402 ignored in some files).
- **New device PIDs**: Must be added in ascending order in header files, udev rules, and README.

## Build and Deployment

- **Version**: `3.12.1` (managed via bump2version, config in `.bumpversion.cfg`)
- **Kernel module**: Built via `make driver` using kernel's Kbuild system
- **Python packages**: `daemon/setup.py` → `openrazer_daemon`, `pylib/setup.py` → `openrazer`
- **DKMS**: `install_files/dkms/dkms.conf` — driver installed via DKMS
- **Debian packaging**: Full `debian/` directory with `control`, `rules`, `changelog`
- **CI**: Sourcehut builds (`.builds/`) run full formatting, lint, compile, and functional tests
- **GitHub Actions**: Only stale issue management (`.github/workflows/stale.yml`)

## Pull Request Guidelines

- Title format: `[component] Brief description`
- Link related issues in PR description
- Describe what is implemented, tested/working, and what is not working
- Run formatting and tests before submitting
- All CI checks must pass (formatting, lint, compile, functional tests)

## Key Files and Directories

| Path | Purpose |
|---|---|
| `driver/` | Linux kernel module (C) |
| `daemon/openrazer_daemon/hardware/` | Device class definitions (one file per device type) |
| `daemon/openrazer_daemon/` | Daemon logic |
| `pylib/openrazer/` | Client library |
| `pylib/openrazer/_fake_driver/` | Fake driver configs for testing |
| `install_files/udev/99-razer.rules` | udev rules |
| `install_files/appstream/` | AppStream metadata |
| `install_files/dkms/` | DKMS configuration |
| `scripts/ci/` | CI check scripts |
| `.builds/` | Sourcehut CI configuration |

## Additional Notes

- The project uses GPL-2.0-or-later (kernel module and daemon) and CC-BY-SA-4.0 (documentation assets)
- Daemon dependencies: `daemonize`, `dbus-python`, `PyGObject`, `pyudev`, `setproctitle`
- Library dependencies: `dbus-python`, `numpy`, `openrazer_daemon`
- Testing uses Python's `unittest` framework (not pytest)
- No `pyproject.toml`, `setup.cfg`, or `tox.ini` — packaging is done via `setup.py`

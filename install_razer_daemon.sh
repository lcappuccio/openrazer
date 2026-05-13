#!/bin/bash
set -e

cd daemon && sudo python3 setup.py install
systemctl --user restart openrazer-daemon
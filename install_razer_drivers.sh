#!/bin/bash
set -e

KERNEL=$(uname -r)
DKMS_VERSION=$(ls /usr/src | grep openrazer-driver | sort -V | tail -1 | sed 's/openrazer-driver-//')
DKMS_SRC=/usr/src/openrazer-driver-${DKMS_VERSION}/driver

echo ":: Copying driver sources to DKMS tree (${DKMS_VERSION})"
sudo cp driver/razerkbd_driver.c driver/razerkbd_driver.h "$DKMS_SRC/"
sudo cp driver/razermouse_driver.c driver/razermouse_driver.h "$DKMS_SRC/"

echo ":: Building"
make driver

echo ":: Installing modules"
cd driver
zstd -f razerkbd.ko -o razerkbd.ko.zst
zstd -f razermouse.ko -o razermouse.ko.zst
sudo rm -f /lib/modules/$KERNEL/updates/dkms/razerkbd.ko
sudo rm -f /lib/modules/$KERNEL/updates/dkms/razermouse.ko
sudo cp razerkbd.ko.zst /lib/modules/$KERNEL/updates/dkms/razerkbd.ko.zst
sudo cp razermouse.ko.zst /lib/modules/$KERNEL/updates/dkms/razermouse.ko.zst
cd ..

echo ":: Updating module deps"
sudo depmod -a

echo ":: Reloading modules"
sudo rmmod razerkbd razermouse 2>/dev/null || true
sudo modprobe razerkbd
sudo modprobe razermouse

echo ":: Reinstalling daemon"
(cd daemon && sudo python3 setup.py install)

echo ":: Fixing sysfs permissions"
sleep 1
for dev in /sys/bus/hid/drivers/razerkbd/0003:1532:*/; do
    sudo chgrp -R plugdev "$dev"
done
for id in $(ls /sys/bus/hid/drivers/razermouse/ | grep "1532:0099"); do
    sudo /usr/lib/udev/razer_mount razermouse "$id"
done

echo ":: Restarting daemon"
systemctl --user restart openrazer-daemon

echo ":: Patching Polychromatic device database"
if ! grep -q "02B1" /usr/share/polychromatic/devices/openrazer.json; then
    sudo cp /usr/share/polychromatic/devices/openrazer.json /usr/share/polychromatic/devices/openrazer.json.bak
    sudo sed -i 's/"1532:02B6":/"1532:02B1": {\n        "form_factor": "keyboard",\n        "matrix": "18,6",\n        "name": "Razer Huntsman V3 X TKL",\n        "since": "3.12.0"\n    },\n    "1532:02B6":/' /usr/share/polychromatic/devices/openrazer.json
fi

echo ":: Initialising mouse scroll mode"
python3 -c "
import openrazer.client, time
time.sleep(2)
dm = openrazer.client.DeviceManager()
for d in dm.devices:
    if hasattr(d, 'scroll_mode'):
        d.scroll_mode = 0
"

echo "Done."
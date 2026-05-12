for dev in /sys/bus/hid/drivers/razerkbd/0003:1532:*/; do
    sudo chgrp -R plugdev "$dev"
done
for id in $(ls /sys/bus/hid/drivers/razermouse/ | grep "1532:0099"); do
    sudo /usr/lib/udev/razer_mount razermouse "$id"
done
systemctl --user restart openrazer-daemon

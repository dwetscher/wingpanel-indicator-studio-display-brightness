// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 dwetscher

/*
 * DisplayMonitor.vala — detects whether an Apple Studio Display is on USB.
 *
 * Uses GUdev to enumerate USB devices and to receive hotplug (add/remove)
 * events, so the indicator can show itself only while a display is connected
 * and update live when one is plugged in or unplugged. This reads udev
 * metadata only, so it works regardless of HID access permissions.
 */

public class StudioDisplay.DisplayMonitor : GLib.Object {
    // Apple vendor ID + Studio Display product IDs (same set asdbctl matches).
    private const string VENDOR_ID = "05ac";
    private const string[] PRODUCT_IDS = { "1114", "1116", "1118" };

    private GUdev.Client client;

    // Emitted when a Studio Display is plugged in (true) or removed (false).
    public signal void changed (bool connected);

    public DisplayMonitor () {
        client = new GUdev.Client ({ "usb" });
        client.uevent.connect ((action, device) => {
            // Any USB add/remove can change presence; re-check by enumeration.
            if (action == "add" || action == "remove" || action == "change") {
                changed (is_connected ());
            }
        });
    }

    public bool is_connected () {
        foreach (GUdev.Device device in client.query_by_subsystem ("usb")) {
            if (device.get_devtype () != "usb_device") {
                continue;
            }
            if (device.get_sysfs_attr ("idVendor") != VENDOR_ID) {
                continue;
            }
            var pid = device.get_sysfs_attr ("idProduct");
            if (pid == null) {
                continue;
            }
            foreach (unowned string known in PRODUCT_IDS) {
                if (pid == known) {
                    return true;
                }
            }
        }
        return false;
    }
}

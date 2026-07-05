// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 dwetscher

/*
 * BrightnessController.vala — cached brightness state + write throttling.
 *
 * The cached `current_percent` is the source of truth for the UI so nothing
 * ever blocks on the HID transfer. Because every asdbctl call re-opens the HID
 * device, writes are coalesced: rapid slider drags / scroll bursts collapse
 * into at most one in-flight `set` plus one queued value.
 */

public class BrightnessController : GLib.Object {
    public int current_percent { get; private set; default = 50; }
    public bool has_error { get; private set; default = false; }
    public string error_message { get; private set; default = ""; }

    // Emitted when the brightness value changes (from any source).
    public signal void changed ();
    // Emitted when the error state changes.
    public signal void state_changed ();

    private Asdbctl asdbctl;
    private int pending = -1;          // queued value, or -1 when none
    private bool write_in_flight = false;
    private uint debounce_id = 0;

    private const int DEBOUNCE_MS = 120;

    public BrightnessController (Asdbctl asdbctl) {
        this.asdbctl = asdbctl;
    }

    public void start () {
        // Read the initial value once. The popover re-reads on open (opened()),
        // so no periodic polling runs inside the panel process.
        refresh.begin ();
    }

    // Reads the real brightness from the display and updates the cache.
    public async void refresh () {
        if (!asdbctl.available) {
            set_error ("asdbctl not found on PATH");
            return;
        }
        try {
            int v = yield asdbctl.get_brightness ();
            clear_error ();
            if (v != current_percent) {
                current_percent = v;
                changed ();
            }
        } catch (Error e) {
            set_error (e.message);
        }
    }

    // Requests a new brightness value. Updates the cache/UI immediately and
    // schedules a debounced write to the display.
    public void request_set (int percent) {
        percent = percent.clamp (0, 100);
        if (percent != current_percent) {
            current_percent = percent;
            changed ();
        }
        pending = percent;

        if (debounce_id == 0 && !write_in_flight) {
            debounce_id = Timeout.add (DEBOUNCE_MS, () => {
                debounce_id = 0;
                flush.begin ();
                return Source.REMOVE;
            });
        }
    }

    public void step (int delta) {
        request_set (current_percent + delta);
    }

    private async void flush () {
        if (write_in_flight) {
            return;
        }
        write_in_flight = true;
        while (pending != -1) {
            int target = pending;
            pending = -1;
            try {
                yield asdbctl.set_brightness (target);
                clear_error ();
            } catch (Error e) {
                set_error (e.message);
                break;
            }
        }
        write_in_flight = false;
    }

    private void set_error (string msg) {
        if (!has_error || error_message != msg) {
            has_error = true;
            error_message = msg;
            state_changed ();
        }
    }

    private void clear_error () {
        if (has_error) {
            has_error = false;
            error_message = "";
            state_changed ();
        }
    }
}

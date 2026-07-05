// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 dwetscher

/*
 * Asdbctl.vala — thin async wrapper around the `asdbctl` CLI.
 *
 * asdbctl is a one-shot Rust binary (no daemon): every call opens the USB HID
 * device, performs a single get/set and exits. We shell out to it with
 * GLib.Subprocess so the UI never blocks on the HID transfer.
 */

public errordomain AsdbctlError {
    NOT_FOUND,
    NO_DISPLAY,
    FAILED,
}

public class Asdbctl : GLib.Object {
    // Absolute path to the resolved binary, or null if it is not on PATH.
    public string? binary { get; private set; }
    // Optional target for multi-display setups (passed as --serial).
    public string? serial { get; set; default = null; }

    public bool available {
        get { return binary != null; }
    }

    public Asdbctl () {
        binary = Environment.find_program_in_path ("asdbctl");
    }

    private string[] build_args (string[] extra) {
        var args = new GenericArray<string> ();
        args.add (binary);
        if (serial != null && serial != "") {
            args.add ("--serial");
            args.add (serial);
        }
        foreach (unowned string e in extra) {
            args.add (e);
        }
        return args.data;
    }

    // Returns the current brightness as a percentage (0-100).
    public async int get_brightness () throws Error {
        if (binary == null) {
            throw new AsdbctlError.NOT_FOUND ("asdbctl not found on PATH");
        }

        var proc = new Subprocess.newv (
            build_args ({ "get" }),
            SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );

        string stdout_buf;
        string stderr_buf;
        yield proc.communicate_utf8_async (null, null, out stdout_buf, out stderr_buf);

        if (!proc.get_successful ()) {
            throw_for_stderr (stderr_buf);
        }

        // asdbctl prints e.g. "brightness 47"
        MatchInfo mi;
        var re = /brightness\s+(\d+)/;
        if (re.match (stdout_buf, 0, out mi)) {
            return int.parse (mi.fetch (1)).clamp (0, 100);
        }

        throw new AsdbctlError.FAILED (
            "Could not parse asdbctl output: %s".printf (stdout_buf.strip ())
        );
    }

    // Sets brightness to the given percentage (clamped to 0-100).
    public async void set_brightness (int percent) throws Error {
        if (binary == null) {
            throw new AsdbctlError.NOT_FOUND ("asdbctl not found on PATH");
        }

        percent = percent.clamp (0, 100);
        var proc = new Subprocess.newv (
            build_args ({ "set", percent.to_string () }),
            SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE
        );

        string stdout_buf;
        string stderr_buf;
        yield proc.communicate_utf8_async (null, null, out stdout_buf, out stderr_buf);

        if (!proc.get_successful ()) {
            throw_for_stderr (stderr_buf);
        }
    }

    [NoReturn]
    private void throw_for_stderr (string? stderr_buf) throws Error {
        var msg = (stderr_buf ?? "").strip ();
        if (msg.down ().contains ("no apple studio display")) {
            throw new AsdbctlError.NO_DISPLAY ("No Apple Studio Display found");
        }
        throw new AsdbctlError.FAILED (msg.length > 0 ? msg : "asdbctl exited with an error");
    }
}

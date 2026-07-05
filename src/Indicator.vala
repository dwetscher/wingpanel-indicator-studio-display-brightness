// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 dwetscher

/*
 * Indicator.vala — the wingpanel indicator.
 *
 * Loaded as a plugin directly into the wingpanel process (like the Sound,
 * Power and Network indicators), so its popover can host a real Gtk.Scale
 * slider rendered natively in-process — no SNI, no dbusmenu, no appicontray.
 *
 * The Asdbctl + BrightnessController backend is shared with nothing else; all
 * work is async so it never blocks the panel.
 */

public class StudioDisplay.Indicator : Wingpanel.Indicator {
    private Gtk.EventBox? display_widget = null;

    private Gtk.Grid? popover = null;
    private Gtk.Scale? scale = null;
    private Gtk.Label? value_label = null;

    private Asdbctl asdbctl;
    private BrightnessController controller;
    private DisplayMonitor monitor;
    // Guards against feedback when we push a controller value into the scale.
    private bool syncing = false;

    public Indicator () {
        Object (
            code_name: "studio-display-brightness",
            visible: false
        );

        asdbctl = new Asdbctl ();
        controller = new BrightnessController (asdbctl);
        controller.changed.connect (on_value_changed);
        controller.state_changed.connect (on_state_changed);

        // Show only while an Apple Studio Display is connected; track hotplug.
        monitor = new DisplayMonitor ();
        monitor.changed.connect (on_display_changed);
        update_visibility ();
        if (visible) {
            controller.refresh.begin ();
        }
    }

    private void update_visibility () {
        visible = monitor.is_connected () && asdbctl.available;
    }

    private void on_display_changed (bool connected) {
        bool was_visible = visible;
        update_visibility ();
        if (visible && !was_visible) {
            // Just connected — read the display's current brightness.
            controller.refresh.begin ();
        }
    }

    public override Gtk.Widget get_display_widget () {
        if (display_widget == null) {
            // OverlayIcon is the panel-icon widget the built-in indicators use;
            // it sizes/themes the symbolic icon to match the panel.
            var icon = new Wingpanel.Widgets.OverlayIcon ("display-brightness-symbolic");

            // EventBox gives us an input window so scroll reaches us.
            display_widget = new Gtk.EventBox ();
            display_widget.visible_window = false;
            display_widget.above_child = true;
            display_widget.add_events (
                Gdk.EventMask.SCROLL_MASK | Gdk.EventMask.SMOOTH_SCROLL_MASK
            );
            display_widget.add (icon);
            display_widget.scroll_event.connect (on_scroll);
            display_widget.show_all ();
        }
        return display_widget;
    }

    public override Gtk.Widget? get_widget () {
        if (popover == null) {
            var title = new Gtk.Label ("Studio Display Brightness");
            title.get_style_context ().add_class ("h4");
            title.halign = Gtk.Align.START;
            title.margin_start = 12;
            title.margin_end = 12;

            var icon = new Gtk.Image.from_icon_name (
                "display-brightness-symbolic", Gtk.IconSize.MENU
            );

            scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 5);
            // Step by 5 for arrow keys, trough clicks and scroll (GTK would
            // otherwise use a page increment of 10× the step).
            scale.set_increments (5, 5);
            scale.draw_value = false;
            scale.hexpand = true;
            scale.width_request = 175;
            scale.set_value (controller.current_percent);
            scale.value_changed.connect (on_scale_changed);

            value_label = new Gtk.Label (format_pct (controller.current_percent));
            value_label.width_chars = 4;
            value_label.xalign = 1;

            var slider_row = new Gtk.Grid ();
            slider_row.column_spacing = 6;
            slider_row.margin_start = 12;
            slider_row.margin_end = 12;
            slider_row.attach (icon, 0, 0);
            slider_row.attach (scale, 1, 0);
            slider_row.attach (value_label, 2, 0);

            popover = new Gtk.Grid ();
            popover.row_spacing = 6;
            popover.margin_top = 6;
            popover.margin_bottom = 6;
            popover.width_request = 280;
            popover.attach (title, 0, 0);
            popover.attach (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), 0, 1);
            popover.attach (slider_row, 0, 2);
            popover.show_all ();
        }
        return popover;
    }

    public override void opened () {
        // Sync to the display's real value each time the popover opens.
        controller.refresh.begin ();
    }

    public override void closed () {
    }

    private bool on_scroll (Gdk.EventScroll e) {
        // Scroll up increases, scroll down decreases.
        switch (e.direction) {
            case Gdk.ScrollDirection.UP:
            case Gdk.ScrollDirection.RIGHT:
                controller.step (5);
                return true;
            case Gdk.ScrollDirection.DOWN:
            case Gdk.ScrollDirection.LEFT:
                controller.step (-5);
                return true;
            case Gdk.ScrollDirection.SMOOTH:
                if (e.delta_y < 0 || e.delta_x > 0) {
                    controller.step (5);
                } else if (e.delta_y > 0 || e.delta_x < 0) {
                    controller.step (-5);
                }
                return true;
            default:
                return false;
        }
    }

    private void on_scale_changed () {
        if (syncing || scale == null) {
            return;
        }
        int v = (int) scale.get_value ();
        if (value_label != null) {
            value_label.label = format_pct (v);
        }
        controller.request_set (v);
    }

    private void on_value_changed () {
        int p = controller.current_percent;
        if (scale != null) {
            syncing = true;
            scale.set_value (p);
            syncing = false;
        }
        if (value_label != null) {
            value_label.label = format_pct (p);
        }
    }

    private void on_state_changed () {
        // Visibility is driven by USB presence (DisplayMonitor), not by CLI
        // errors — a connected display stays visible even if a single call
        // fails. Just surface errors to the log.
        if (controller.has_error) {
            warning ("Studio Display brightness unavailable: %s", controller.error_message);
        }
    }

    private static string format_pct (int v) {
        return "%d%%".printf (v);
    }
}

// Module entry point. wingpanel looks up the exported `get_indicator` symbol,
// so this must live at global scope (no namespace prefix).
public Wingpanel.Indicator? get_indicator (Module module,
                                           Wingpanel.IndicatorManager.ServerType server_type) {
    // Don't load on the login greeter — only in a real user session.
    if (server_type != Wingpanel.IndicatorManager.ServerType.SESSION) {
        return null;
    }
    debug ("Activating Studio Display Brightness indicator");
    return new StudioDisplay.Indicator ();
}

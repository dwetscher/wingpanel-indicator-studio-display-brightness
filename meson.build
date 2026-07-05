project('studio-display-brightness', ['vala', 'c'],
    version: '0.1.0',
    license: 'GPL-3.0-or-later',
    meson_version: '>= 0.56.0',
)

gtk_dep = dependency('gtk+-3.0')
glib_dep = dependency('glib-2.0')
gio_dep = dependency('gio-2.0')
# The wingpanel indicator API (libwingpanel-dev). We are loaded as a plugin
# into the wingpanel process, like the Sound/Power/Network indicators.
wingpanel_dep = dependency('wingpanel')
# GUdev — detect Apple Studio Display USB presence / hotplug.
gudev_dep = dependency('gudev-1.0')

common_deps = [gtk_dep, glib_dep, gio_dep, wingpanel_dep, gudev_dep]

# Where wingpanel looks for indicator modules (e.g. /usr/lib/.../wingpanel).
indicatorsdir = wingpanel_dep.get_variable(pkgconfig: 'indicatorsdir')

# udev rule granting the seat user access to the Studio Display HID device.
install_data('data/20-asd-backlight.rules', install_dir: '/usr/lib/udev/rules.d')

subdir('src')

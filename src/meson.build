# Built as a shared module (plugin) and installed into wingpanel's indicators
# directory, where wingpanel discovers and loads it at startup.
shared_module('studio-display-brightness',
    'Indicator.vala',
    'Asdbctl.vala',
    'BrightnessController.vala',
    'DisplayMonitor.vala',
    dependencies: common_deps,
    install: true,
    install_dir: indicatorsdir,
)

# Release-specific syntax differences belong only in this file.
# No release branches are currently required.
#
# dunfell (3.1): BitBake does not support colon overrides.
# kirkstone (4.0) and scarthgap (5.0): the shared assignment syntax works.
# wrynose (6.0): DISTRO_FEATURES_BACKFILL was removed and systemd became
# the nodistro default. We leave the poky DISTRO_FEATURES / IMAGE_FEATURES
# baseline and INIT_MANAGER untouched, so these changes need no workaround.
#
# Add any future required release-specific branches below.

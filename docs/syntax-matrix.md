# BitBake syntax matrix

| Item | dunfell (3.1) | kirkstone (4.0) | scarthgap (5.0) | wrynose (6.0) |
|---|---|---|---|---|
| Override operator | `_append` / `_remove` | `:append` / `:remove` | `:append` / `:remove` | `:append` / `:remove` |
| systemd adds `usrmerge` | No | No | Yes | Yes |
| systemd suppresses sysvinit backfill | `_append` | `:append` | `:append` | No backfill line |

Do not force `usrmerge` on 3.1 or 4.0 to make this matrix uniform. On 3.1 it
requires `CONVERSION_CMD` and substantial QA adjustments, while its benefit is
limited to merged-/usr path layout. `yp-common.inc` uses `:remove` on 4.0+ and
sets the equivalent `_remove` operation from an anonymous configuration block
only on 3.1. This conditional is necessary because BitBake 6.x fatally rejects
even an inactive legacy `_remove` assignment during parsing.

Other `init-manager-systemd.inc` details, including provider, initscript,
device-manager and `ROOT_HOME` differences, are recorded in
[`distro-features.md`](distro-features.md).

# `deployment/` — snapshot of the running CPE610 node

What is actually on the deployed device, captured **2026-09-26** — the day the 2-node RF
cluster was first verified working end to end.

This directory is **evidence, not a build input.** Nothing here is flashed, installed or
compiled by the build in the top-level README. It exists so that "what is really running"
can be diffed against "what the guides claim", because for a long stretch those two
disagreed. The reconciled values live in
[`../docs/DEPLOYED_PARAMETERS.md`](../docs/DEPLOYED_PARAMETERS.md).

## Provenance

| Path here | Captured from |
| --- | --- |
| `etc/`, `usr/`, `packages-installed.txt`, `system-info.txt` | the CPE610 itself, via `ArvinVeiyon/Relay_Station_Pxlabs` → `Node_CPE610/` |
| `wifibroadcast.cfg.relay` | the **relay** (`vind-rly`), `/etc/wifibroadcast.cfg` |

`wifibroadcast.cfg.relay` is named for its origin on purpose: the node does not have a
`wifibroadcast.cfg` of its own. It runs the base `wfb-ng` + `wfb-ng-tun` pair with no
`wfb-server`, and is driven entirely over cluster-ssh from the relay. The relay's config is
therefore the only place the link parameters exist.

## Contents

| File | What it shows |
| --- | --- |
| `etc/openwrt_release` | OpenWrt 24.10.4, `r28959-29397011cc`, ath79/generic, mips_24kc |
| `etc/config/network` | `br-lan` = eth0 at **10.5.7.102/24**; a `wan` on `phy0-sta0` that never comes up |
| `etc/config/wireless` | `radio0 disabled '1'`, `country 'IN'` (not the effective regdomain), leftover `sta` section |
| `etc/config/dropbear` | password auth still `on` — see the security note below |
| `etc/config/dhcp`, `etc/config/firewall`, `etc/config/system` | stock apart from DHCP being ignored on both interfaces; hostname `OpenWrt`, TZ `Asia/Kolkata` |
| `etc/rc.local` | **stock and empty** — proof the monitor iface is not started at boot |
| `usr/sbin/wfb-mon0.sh` | the monitor-interface script the relay invokes over cluster-ssh |
| `packages-installed.txt` | 120 packages; `wfb-ng` / `wfb-ng-tun` at **25.01-r1** |
| `system-info.txt` | kernel 6.6.110, uname, release, full package list |
| `wifibroadcast.cfg.relay` | the deployed link configuration, all profiles |

## Three things this snapshot settles

1. **The committed custom image *is* the deployed firmware, near-exactly.**
   `images/custom/…manifest` and `packages-installed.txt` share **118 packages at identical
   versions**. The device adds only `ethtool` and `tcpdump`, baked into a slightly later
   build. The image is not "close to" what is deployed — it matches.

2. **The monitor interface is not started at boot.** `rc.local` is stock and there is no
   `/etc/init.d/wfb-mon0`, contrary to what both guides instruct. `phy0-mon0` is created by
   the relay on every cluster start via `custom_init_script`. Reboot the node on its own and
   it comes up with no monitor interface until the relay's cluster service restarts.

3. **The deployed wfb-ng is 25.01-r1**, not the 24.9.7-r2 that `packages/ipk/` and
   `package/*/Makefile` in this repo still pin.

## Security

The `option key` in `etc/config/wireless` is **redacted** — the house SSID PSK is not stored
in git. No private keys are in this directory and none belong here.

The upstream `Relay_Station_Pxlabs` repo that these files were pulled from is public and
*does* still contain real `gs.key`, `drone.key` and `wfb_cluster_ed25519`. That is tracked
as an open item in [`../docs/DEPLOYED_PARAMETERS.md`](../docs/DEPLOYED_PARAMETERS.md#security)
and needs key rotation plus a history purge, not just a delete commit.

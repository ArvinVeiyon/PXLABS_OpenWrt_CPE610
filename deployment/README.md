# Deployment Records — CPE610 Receive Node

| Field | Value |
| --- | --- |
| Document type | Configuration records annex |
| Capture date | 2026-09-26 |
| Revision | 1.1 |
| Date | 2026-09-27 |
| Status | Current |
| Subject | The configuration in force on the deployed CPE610 v2 node |

These files record the configuration in force on the deployed device as at 2026-09-26, the date
on which two-node RF cluster operation was first confirmed end to end.

**Classification.** This directory is a set of records. It is not a build input. Nothing here
is flashed, installed or compiled by the build procedure in the top-level README. Its purpose
is to permit the configuration in force to be compared against the configuration described in
the deployment manuals, the two having diverged over an extended period. The reconciled values
are specified in [`../docs/DEPLOYED_PARAMETERS.md`](../docs/DEPLOYED_PARAMETERS.md).

---

## 1 Provenance

| Path in this directory | Source |
| --- | --- |
| `etc/`, `usr/`, `packages-installed.txt`, `system-info.txt` | The CPE610 unit, by way of `ArvinVeiyon/Relay_Station_Pxlabs` → `Node_CPE610/` |
| `wifibroadcast.cfg.relay` | The relay (`vind-rly`), `/etc/wifibroadcast.cfg` |

`wifibroadcast.cfg.relay` is named for its origin deliberately. The node holds no
`wifibroadcast.cfg` of its own: it runs the base `wfb-ng` and `wfb-ng-tun` pair, without
`wfb-server`, and is driven entirely over cluster SSH from the relay. The relay's configuration
is therefore the sole location in which the link parameters exist.

The file is retained here because it is the only record of the node's link parameters. Its
presence does not place relay-side subject matter within the scope of this repository.

---

## 2 Contents

| File | Content |
| --- | --- |
| `etc/openwrt_release` | OpenWrt 24.10.4, `r28959-29397011cc`, ath79/generic, mips_24kc |
| `etc/config/network` | `br-lan` = eth0 at 10.5.7.102/24; a `wan` interface on `phy0-sta0` that is never raised |
| `etc/config/wireless` | `radio0 disabled '1'`; `country 'IN'`, which is not the effective regulatory domain; residual `sta` section |
| `etc/config/dropbear` | Password authentication remains enabled; see Section 4 |
| `etc/config/dhcp`, `etc/config/firewall`, `etc/config/system` | Unmodified except that DHCP is disregarded on both interfaces; hostname `OpenWrt`, time zone `Asia/Kolkata` |
| `etc/rc.local` | Unmodified and empty — evidence that the monitor interface is not raised at boot |
| `usr/sbin/wfb-mon0.sh` | The monitor-interface script the relay invokes over cluster SSH |
| `packages-installed.txt` | 120 packages; `wfb-ng` and `wfb-ng-tun` at 25.01-r1 |
| `system-info.txt` | Kernel 6.6.110, `uname` output, release identification, full package list |
| `wifibroadcast.cfg.relay` | The deployed link configuration, all profiles |

---

## 3 Findings established by these records

**3.1 The committed custom image is the deployed firmware.**
`images/custom/…manifest` and `packages-installed.txt` share 118 packages at identical
versions. The device carries two additional packages, `ethtool` and `tcpdump`, incorporated in
a marginally later build. The image is to be described as matching deployment, not as
approximating it.

**3.2 The monitor interface is not raised at boot.**
`rc.local` is unmodified and no `/etc/init.d/wfb-mon0` service is present, contrary to the
instruction given in both deployment manuals. `phy0-mon0` is created by the relay at each
cluster start through `custom_init_script`. A node rebooted in isolation therefore has no
monitor interface until the relay's cluster service is restarted.

**3.3 The deployed WFB-NG version is 25.01-r1.**
These packages are supplied by the official OpenWrt 24.10.4 package feed. They were not built
from the superseded 24.9.7-r2 recipes formerly held under `package/` and `packages/ipk/`, which
did not contribute to the deployed image and were removed from this repository on 2026-09-27.
The provenance evidence is recorded in README §3.

---

## 4 Security

The `option key` value in `etc/config/wireless` is redacted. The residential SSID pre-shared
key is not stored in version control. No private keys are held in this directory and none are
to be added.

**Key material in the upstream records repository — risk accepted.** The link and SSH keypairs
associated with this installation are present in the upstream repository from which these files
were retrieved. The operator has assessed this as acceptable on the grounds that the
installation is a test vehicle, and no rotation is scheduled. Recorded as an accepted risk on
2026-09-27; see
[`../docs/DEPLOYED_PARAMETERS.md`](../docs/DEPLOYED_PARAMETERS.md#10-security). The acceptance
is scoped to the test installation and does not extend to any production vehicle.

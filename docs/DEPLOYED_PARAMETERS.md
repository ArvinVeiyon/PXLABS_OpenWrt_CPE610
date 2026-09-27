# Deployed Parameters — Authoritative Reference

| Field | Value |
| --- | --- |
| Document type | Parameter reference |
| Applies to | CPE610 v2 receive node and relay `vind-rly`, `wifibroadcast-cluster@gs` |
| Revision | 1.1 |
| Date | 2026-09-27 |
| Status | Current — authoritative |
| Verified | 2026-09-26, against the live relay configuration and the node records |

**Precedence.** This document overrides every parameter value stated in the two deployment
manuals and in `config/master.cfg`. Where they disagree with this document, this document
governs.

**Source of record.** `/etc/wifibroadcast.cfg` on the relay (`vind-rly`), captured from
`ArvinVeiyon/Relay_Station_Pxlabs` → `System_files/etc/wifibroadcast.cfg`, together with the
node records in [`../deployment/`](../deployment/). Verification was performed on 2026-09-26,
the date on which two-node RF cluster operation was first confirmed end to end.

**Origin of the discrepancies.** `config/master.cfg` is the upstream WFB-NG template, not the
deployed configuration. It was labelled as the configuration used for this deployment, and both
Word-sourced manuals were written against it and against earlier bench values. That single
mislabelling accounts for every discrepancy recorded in Section 1.

---

## 1 Corrections

| Parameter | Incorrect value and its source | Deployed value |
| --- | --- | --- |
| `wifi_channel` | 165 (5825 MHz) in `master.cfg`; 157 (5785 MHz) in both manuals | **161 — 5805 MHz, HT20** |
| `wifi_txpower` | `None` in `master.cfg` | **3000** (30 dBm × 100, relay 8812eu); node override remains `None` |
| `temp_measurement_interval` | 10 in `master.cfg` | **2** |
| `ssh_key` | `/root/.ssh/wfb_cluster_ed25519` in both manuals (`master.cfg` has `None`) | **`/home/vind-admin/.ssh/wfb_cluster_ed25519`** |
| `api_port` / `stats_port` | 8203 / 8303, placed in `[cluster]` — manuals only | **`[gs]`: 8103 / 8003**, as `master.cfg` already specifies |
| `custom_init_script` | `/usr/sbin/wfb-mon0.sh` in both manuals (`master.cfg` has `None`) | **`sh /usr/sbin/wfb-mon0.sh`**, with the interpreter stated explicitly |
| Addressing plan | 10.5.6.100 relay / 10.5.6.102 node — main manual, "Distributed Setup" §0 | **10.5.7.100 relay eth0 / 10.5.7.102 node** |
| Role of the CPE610 | "RX only, no cluster" — main manual §3 | **Cluster node** of `wifibroadcast-cluster@gs` |

`mcs_index = 1` is not a discrepancy. `master.cfg` already carries this value and it matches
deployment. The manuals do not mention the parameter at all, which is why it is easily
overlooked.

The addressing plan in the `_v1` manual (10.5.7.0/24) is already correct. Only the main
manual's §0 block retains the superseded 10.5.6.x addresses.

### 1.1 Corrections with functional consequence

Two of the entries above affect operation rather than documentation accuracy.

**`api_port` and `stats_port` placed in `[cluster]` have no effect.** WFB-NG reads both from
the profile section. The manuals instruct the operator to add them to `[cluster]`; following
that instruction leaves the statistics API bound elsewhere than expected, with no error raised.
The correct location is `[gs]`, at 8103 and 8003 respectively.

**`custom_init_script` requires the explicit `sh` prefix.** The node's
`/usr/sbin/wfb-mon0.sh` is invoked over cluster SSH. Without the stated interpreter the
execution fails against the node's `ash` shell and `phy0-mon0` is never created.

---

## 2 RF link

| Setting | Value | Note |
| --- | --- | --- |
| `wifi_channel` | `161` | 5805 MHz |
| Channel width | HT20 | `bandwidth = 20`, `force_vht = False` |
| `wifi_region` | `'BO'` | Permissive regulatory domain; see Section 2.1 |
| `wifi_txpower` | `3000` | 30 dBm × 100; applies to the relay's 8812eu. The node overrides to `None`, the driver default |
| `mcs_index` | `1` | Selected low deliberately; see the MCS note in the `_v1` manual, §6.5 |
| `stbc` / `ldpc` | `1` / `1` | |
| `short_gi` | `False` | |
| `radio_mtu` | `1445` | |
| `tx_sel_rssi_delta` | `3` | Governs transmit arbitration between nodes; see Section 6.2 |
| `temp_measurement_interval` | `2` | |
| `temp_overheat_warning` | `60` | |

### 2.1 Regulatory domain — two writers, order significant

1. `/usr/sbin/wfb-mon0.sh` on the node executes `iw reg set IN`, followed by
   `iw dev phy0-mon0 set channel 161 HT20`.
2. The WFB-NG generated cluster initialisation runs that script first, then re-applies
   `iw reg set BO` and channel 161 from `[cluster]`.

`BO` is therefore the effective regulatory domain, not `IN`. `deployment/etc/config/wireless`
separately specifies `country 'IN'`, which is likewise not the effective value.

**CAUTION.** Do not amend the `IN` setting in the script on the assumption that it determines
the operating domain. It is overwritten immediately afterwards, and changing it has no effect.

---

## 3 Cluster topology

The relay executes `wfb-server --profiles gs --cluster ssh` under
`wifibroadcast-cluster@gs`, with two radio nodes.

| Node | Address | WLAN interface | Notes |
| --- | --- | --- | --- |
| Relay's own adapter | `127.0.0.1` | `wlx00c0cab6db3b` (RTL8812EU) | `server_address` must be `127.0.0.1` for local adapters |
| CPE610 v2 | `10.5.7.102` | `phy0-mon0` (ath9k) | Monitor interface created by `custom_init_script` |

```
ssh_user          = 'root'
ssh_port          = 22
ssh_key           = '/home/vind-admin/.ssh/wfb_cluster_ed25519'
server_address    = '10.5.7.100'      # relay eth0 — the only address every node can reach
base_port_server  = 10000
base_port_node    = 11000
```

Per-node override for the CPE610:

```python
'10.5.7.102': { 'wlans': ['phy0-mon0'],
                'ssh_user': 'root',
                'ssh_port': 22,
                'ssh_key': '/home/vind-admin/.ssh/wfb_cluster_ed25519',
                'custom_init_script': 'sh /usr/sbin/wfb-mon0.sh',
                'wifi_channel': 161,
                'wifi_txpower': None },
```

### 3.1 Addressing

| Host or interface | Address |
| --- | --- |
| Relay, eth0 (cluster server) | 10.5.7.100 |
| CPE610 node, br-lan | 10.5.7.102 |
| Relay, Wi-Fi side | 10.5.6.101 |
| Laptop / ground-station client | 10.5.6.50 |
| Ground-station tunnel interface `gs-wfb` | 10.5.5.77/24 |
| Drone tunnel interface `drone-wfb` | 10.5.5.87/24 |

Two subnets are in use. The cluster operates on 10.5.7.0/24, between relay eth0 and the node;
video and client traffic operate on 10.5.6.0/24. The main manual's "Distributed Setup" §0
specifies 10.5.6.100 and 10.5.6.102 for the cluster. That is the superseded plan and is
incorrect for the current deployment.

---

## 4 Ports

| Profile | `stats_port` | `api_port` |
| --- | --- | --- |
| `[gs]` | 8003 | 8103 |
| `[drone]` | 8002 | 8102 |

`base_port_server = 10000`, `base_port_node = 11000`.

---

## 5 Streams and forward error correction

| Stream | `fec_k` | `fec_n` | `fec_delay` | Peer |
| --- | --- | --- | --- | --- |
| Video | 8 | 12 | 0 | gs: `connect://10.5.6.50:5600` · drone: `listen://127.0.0.1:5602` |
| MAVLink | 1 | 3 | 0 | gs: `connect://127.0.0.1:14560` · drone: `listen://0.0.0.0:14550` |
| Tunnel | 2 | 4 | 500 | gs interface `gs-wfb` · drone interface `drone-wfb` |

MAVLink additional settings: `mavlink_sys_id = 3`, `mavlink_comp_id = 68`,
`inject_rssi = True`, `mavlink_agg_timeout = 0.1`, `mavlink_err_rate = True`. Tunnel
additional settings: `tunnel_agg_timeout = 0.005`, `default_route = False` at both ends.

Keypairs: `[gs_base] keypair = 'gs.key'`, `[drone_base] keypair = 'drone.key'`. No key
material is stored in this repository and none is to be added; see Section 10.

---

## 6 Node characteristics

### 6.1 No network egress, by design

`radio0` is set to `disabled '1'`, with the consequence that the residual `sta` configuration
for SSID `Nilan_5GHz` never comes up, `phy0-sta0` does not exist, and there is neither a
default route nor a package feed. The CPE610 has a single radio and cannot operate as a station
and a channel-161 monitor concurrently. Any package must be transferred as an `.ipk` over
Ethernet from the relay.

This constraint is also why WFB-NG is incorporated into the firmware rather than installed:
`/overlay` has approximately 450 KB free and `libstdcpp6` alone requires approximately 2 MB.
`opkg install` cannot succeed on this platform.

### 6.2 Receive-only in practice, irrespective of configuration

The ath9k driver reports absolute dBm — values of −23 to −21 were observed — and supplies no
noise figure, so reported SNR is 0. The relay's RTL8812EU reports `rssi_avg` of +14 to +16.
The transmit selector evaluates these against `tx_sel_rssi_delta = 3`, with the result that
the relay adapter consistently wins transmit arbitration. This is a chipset reporting
difference and requires no corrective action.

The node's receive contribution is measured and material: 220 packets from the node against
233 from the relay's local adapter over the same interval, with `dec_err: [0, 0]`.

---

## 7 Boot behaviour as deployed

Both manuals instruct the operator to install `/etc/init.d/wfb-mon0` with `START=25` and
`STOP=10`, so that the monitor interface is raised at boot. **That service is not installed on
the deployed node.** `deployment/etc/rc.local` is unmodified and the records contain no
`init.d` entry.

In the deployed system `phy0-mon0` is created by the relay at each cluster start, through
`custom_init_script`. Two consequences follow:

- A node rebooted in isolation has no monitor interface until the cluster service is
  restarted on the relay.
- `/usr/sbin/wfb-mon0.sh` must be present on the node filesystem for cluster start to
  succeed. It is preserved at
  [`../deployment/usr/sbin/wfb-mon0.sh`](../deployment/usr/sbin/wfb-mon0.sh).

Installing the init script would make the node self-sufficient at boot. This is a sound
improvement, but it does not describe the current configuration.

---

## 8 WFB-NG version state

| Component | WFB-NG version |
| --- | --- |
| CPE610 node, and the custom image manifest | **25.01-r1** |
| Relay, drone, companion computer | 25.4.27.73439 |

The node's 25.01-r1 packages are supplied by the official OpenWrt 24.10.4 package feed, not
built from a recipe in this repository. See README §3 for the provenance evidence.

The superseded 24.9.7-r2 recipes and `.ipk` artifacts under `package/` and `packages/ipk/`
did not contribute to the deployed image and are not a version discrepancy in the deployed
system. See README §3.1.

### 8.1 Assessment of the version skew

The skew between the node at 25.01-r1 and the remaining stations at 25.4.27.73439 is open but
is not a defect. In cluster mode the node operates as a transparent pipe: it holds no key,
performs no FEC and maintains no session state. Only the UDP datagram framing must
correspond, and it does.

Closing the skew requires building 25.4.27 for `mips_24kc` on an x86 host with network access
and transferring the resulting `.ipk` to the node over Ethernet.

---

## 9 Reference: node interface summary

| Interface | State | Address |
| --- | --- | --- |
| `br-lan` (eth0) | Up | 10.5.7.102/24, static |
| `phy0-mon0` | Created per cluster start | No address; monitor mode, channel 161 HT20 |
| `radio0` | `disabled '1'` | Not raised |
| `phy0-sta0` | Not present | Residual `sta` configuration is never applied |

---

## 10 Security

Three findings are open. All are tracked outside this repository.

1. **`ArvinVeiyon/Relay_Station_Pxlabs` is public and its `master` branch contains genuine
   private keys** — `System_files/etc/gs.key` and `System_files/etc/drone.key` (WFB-NG
   keypairs), and `System_files/home/vind-admin/.ssh/wfb_cluster_ed25519` (an OpenSSH private
   key). All three are retrievable without authentication. A party holding the WFB-NG keypairs
   can decrypt the link and inject into it. Remediation requires key rotation — `wfb_keygen`
   and a fresh ed25519 key — together with a history purge. Deleting the files in a new commit
   is not sufficient.
2. The node's `etc/config/dropbear` has `PasswordAuth` and `RootPasswordAuth` both set to
   `on`, while key-based authentication from the relay is already functional. Both may be
   disabled. Recorded as found; not yet changed.
3. No key material is held in this repository. `*.key` is excluded by `.gitignore`. This
   condition is to be maintained.

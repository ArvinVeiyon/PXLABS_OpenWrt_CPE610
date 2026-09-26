# Deployed parameters — authoritative reference

**This file overrides every parameter value stated in the two deployment guides and in
`config/master.cfg`.** Where they disagree, this file is right.

Source of truth: `/etc/wifibroadcast.cfg` on the relay (`vind-rly`), captured from
`ArvinVeiyon/Relay_Station_Pxlabs` → `System_files/etc/wifibroadcast.cfg`, plus the node
snapshot in [`../deployment/`](../deployment/). Verified 2026-09-26, the day the 2-node RF
cluster was first confirmed working end to end.

> **Why the guides are wrong.** `config/master.cfg` in this repo is the *upstream wfb-ng
> template*, not the deployed config. It was mislabelled as "the config used for this
> deployment", and both `.docx` guides were written against it and against earlier bench
> values. That single mislabelling is the root of every discrepancy below.

---

## Corrections at a glance

| Parameter | Wrong value, and where it comes from | **Actually deployed** |
| --- | --- | --- |
| `wifi_channel` | 165 (5825 MHz) in `master.cfg`; 157 (5785 MHz) in both guides | **161 → 5805 MHz, HT20** |
| `wifi_txpower` | `None` in `master.cfg` | **3000** (30 dBm ×100, relay 8812eu); node override stays `None` |
| `temp_measurement_interval` | 10 in `master.cfg` | **2** |
| `ssh_key` | `/root/.ssh/wfb_cluster_ed25519` — both guides (`master.cfg` has `None`) | **`/home/vind-admin/.ssh/wfb_cluster_ed25519`** |
| `api_port` / `stats_port` | 8203 / 8303 placed inside `[cluster]` — **guides only** | **`[gs]`: 8103 / 8003** (which is what `master.cfg` already has) |
| `custom_init_script` | `/usr/sbin/wfb-mon0.sh` — both guides (`master.cfg` has `None`) | **`sh /usr/sbin/wfb-mon0.sh`** (explicit `sh`) |
| IP plan | 10.5.6.100 relay / 10.5.6.102 node — main guide, "Distributed Setup" §0 | **10.5.7.100 relay eth0 / 10.5.7.102 node** |
| Role of the CPE610 | "RX only, **no cluster**" — main guide §3 | **cluster node** of `wifibroadcast-cluster@gs` |
| wfb-ng version | 24.9.7-r2 — this repo's `packages/ipk/` and `package/*/Makefile` | **25.01-r1** on the device and in the image manifest |

`mcs_index = 1` is **not** a discrepancy — `master.cfg` already carries it and it matches
deployment. The guides simply never mention it, which is why it is easy to miss.

The older `_v1` guide's IP plan (10.5.7.0/24) is also already correct; only the main guide's
§0 block has the pre-move 10.5.6.x addresses.

Two of these are more than cosmetic:

- **`api_port` / `stats_port` in `[cluster]` does nothing.** wfb-ng reads them from the
  profile section. The guides tell you to add them to `[cluster]`; do that and the stats
  API silently isn't where you expect it. They belong in `[gs]` (8103 / 8003).
- **`custom_init_script` must start with `sh`.** The node's `/usr/sbin/wfb-mon0.sh` is
  invoked over cluster-ssh; without the explicit interpreter the exec fails on the node's
  ash shell and `phy0-mon0` is never created.

---

## RF link

| Setting | Value | Note |
| --- | --- | --- |
| `wifi_channel` | `161` | 5805 MHz |
| Channel width | HT20 | `bandwidth = 20`, `force_vht = False` |
| `wifi_region` | `'BO'` | permissive regdomain — see the regdomain note below |
| `wifi_txpower` | `3000` | 30 dBm ×100; applies to the relay's 8812eu. Node overrides to `None` (driver default) |
| `mcs_index` | `1` | deliberately low; see MCS note in the guide |
| `stbc` / `ldpc` | `1` / `1` | |
| `short_gi` | `False` | |
| `radio_mtu` | `1445` | |
| `tx_sel_rssi_delta` | `3` | drives which node transmits — see "RX-only in practice" |
| `temp_measurement_interval` | `2` | |
| `temp_overheat_warning` | `60` | |

### Regdomain: two writers, and the order matters

1. `/usr/sbin/wfb-mon0.sh` on the node runs `iw reg set IN`, then
   `iw dev phy0-mon0 set channel 161 HT20`.
2. wfb-ng's generated cluster init runs that script **first**, then re-applies
   `iw reg set BO` and channel 161 from `[cluster]`.

So **`BO` is the effective regdomain**, not `IN`. `deployment/etc/config/wireless`
separately carries `country 'IN'`, which is also not the effective value. Do not "fix" the
`IN` in the script thinking it is what the radio ends up on — it is overwritten a moment
later, and changing it changes nothing.

---

## Cluster topology

Relay runs `wfb-server --profiles gs --cluster ssh` (`wifibroadcast-cluster@gs`). Two RF nodes:

| Node | Address | WLAN | Notes |
| --- | --- | --- | --- |
| Relay's own card | `127.0.0.1` | `wlx00c0cab6db3b` (RTL8812EU) | `server_address` must be `127.0.0.1` for local cards |
| CPE610 v2 | `10.5.7.102` | `phy0-mon0` (ath9k) | monitor iface created by `custom_init_script` |

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

### Addresses

| Host | Address |
| --- | --- |
| Relay, eth0 (cluster server) | 10.5.7.100 |
| CPE610 node, br-lan | 10.5.7.102 |
| Relay, Wi-Fi side | 10.5.6.101 |
| Laptop / GS client | 10.5.6.50 |
| GS tunnel iface `gs-wfb` | 10.5.5.77/24 |
| Drone tunnel iface `drone-wfb` | 10.5.5.87/24 |

Note the **two subnets**: the cluster runs on 10.5.7.0/24 (relay eth0 ↔ node), while video
and client traffic live on 10.5.6.0/24. The main guide's "Distributed Setup" §0 uses
10.5.6.100/.102 for the cluster — that is the pre-move plan and is wrong for the current
deployment.

---

## Ports

| Profile | `stats_port` | `api_port` |
| --- | --- | --- |
| `[gs]` | 8003 | 8103 |
| `[drone]` | 8002 | 8102 |

`base_port_server = 10000`, `base_port_node = 11000`.

---

## Streams and FEC

| Stream | `fec_k` | `fec_n` | `fec_delay` | Peer |
| --- | --- | --- | --- | --- |
| video | 8 | 12 | 0 | gs: `connect://10.5.6.50:5600` · drone: `listen://127.0.0.1:5602` |
| mavlink | 1 | 3 | 0 | gs: `connect://127.0.0.1:14560` · drone: `listen://0.0.0.0:14550` |
| tunnel | 2 | 4 | 500 | gs iface `gs-wfb` · drone iface `drone-wfb` |

MAVLink extras: `mavlink_sys_id = 3`, `mavlink_comp_id = 68`, `inject_rssi = True`,
`mavlink_agg_timeout = 0.1`, `mavlink_err_rate = True`. Tunnel: `tunnel_agg_timeout = 0.005`,
`default_route = False` on both ends.

Keypairs: `[gs_base] keypair = 'gs.key'`, `[drone_base] keypair = 'drone.key'`. **No key
material is stored in this repo and none should be** — see [Security](#security).

---

## Two structural facts about the node

### It has no internet, by design

`radio0` is `disabled '1'`, so the leftover `sta` config for SSID `Nilan_5GHz` never comes
up, `phy0-sta0` does not exist, and there is no default route and no package feed. The
CPE610 has **one radio** — it physically cannot be a station and a channel-161 monitor at
the same time. Any package must arrive as an `.ipk` carried in over Ethernet from the relay.

This is also why wfb-ng is **baked into the firmware** rather than installed: `/overlay`
has ~450 KB free and `libstdcpp6` alone needs ~2 MB. `opkg install` can never work here.

### It is effectively RX-only regardless of configuration

ath9k reports true dBm (−23..−21 observed) and supplies no noise figure, so SNR reads 0.
The relay's RTL8812EU reports `rssi_avg` of +14..+16. The TX selector compares those against
`tx_sel_rssi_delta = 3`, so **the relay card always wins TX arbitration**. This is a chipset
reporting difference, not a fault, and it does not need fixing.

Its RX contribution is real and measured: 220 packets from the node versus 233 from the
relay's local card in the same window, `dec_err: [0, 0]`.

---

## Boot behaviour — what is actually deployed

The guides tell you to install `/etc/init.d/wfb-mon0` (`START=25` / `STOP=10`) so the
monitor interface comes up at boot. **That service is not installed on the deployed node.**
`deployment/etc/rc.local` is stock and there is no `init.d` entry in the snapshot.

In practice `phy0-mon0` is created by the relay, on every cluster start, through
`custom_init_script`. Consequences worth knowing:

- Rebooting the node alone leaves it with **no monitor interface** until the cluster
  service is restarted on the relay.
- `/usr/sbin/wfb-mon0.sh` must exist on the node's filesystem for cluster start to work. It
  is preserved in [`../deployment/usr/sbin/wfb-mon0.sh`](../deployment/usr/sbin/wfb-mon0.sh).

Installing the init script would make the node self-sufficient at boot. It is a reasonable
improvement; it is simply not what is running today.

---

## Version skew (open, not a defect)

| Component | wfb-ng version |
| --- | --- |
| CPE610 node (and the custom image manifest) | **25.01-r1** |
| Relay / drone / companion | 25.4.27.73439 |
| `packages/ipk/*.ipk` and `package/*/Makefile` in this repo | 24.9.7-r2 — **stale, cannot rebuild the committed image** |

In cluster mode the node is a dumb pipe: no key, no FEC, no session state. Only the UDP
datagram framing has to match, and it does. Closing the skew means building 25.4.27 for
`mips_24kc` on an x86 host with internet access and carrying the `.ipk` in over Ethernet.

---

## Security

Three items are open and are tracked outside this repo:

1. **`ArvinVeiyon/Relay_Station_Pxlabs` is public and its `master` branch contains real
   private keys** — `System_files/etc/gs.key`, `System_files/etc/drone.key` (wfb-ng
   keypairs) and `System_files/home/vind-admin/.ssh/wfb_cluster_ed25519` (OpenSSH private
   key), all fetchable unauthenticated. Anyone holding the wfb keypairs can decrypt and
   inject into the link. Remediation needs key **rotation** (`wfb_keygen`, fresh ed25519)
   *and* a history purge — deleting the files in a new commit is not sufficient.
2. The node's `etc/config/dropbear` has `PasswordAuth` and `RootPasswordAuth` both `on`
   while key auth from the relay already works. Both can be turned off. Left as found.
3. Nothing in *this* repo carries key material; `*.key` is gitignored. Keep it that way.

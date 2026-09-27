# Changelog

| Field | Value |
| --- | --- |
| Document type | Release changelog |
| Applies to | `PXLABS_OpenWrt_CPE610` — all releases |
| Revision | 1.0 |
| Date | 2026-09-27 |
| Status | Current |

**Scope.** This file records what changed in each release of this repository: firmware, build
configuration, deployment records and documentation. Document revision numbers and the
document-by-document history are held separately in
[`docs/DOCUMENT_REGISTER.md`](docs/DOCUMENT_REGISTER.md).

**Release tags are frozen.** A published tag is never moved, deleted or re-cut. A correction to
released content is made on `main` and carried into the next release. Consequently the **Unreleased**
section below is the accumulating content of the next release, and the released sections are
historical records that do not change.

**Versioning.** Tags take the form `v<openwrt-release>-pxlabs-cpe610-r<n>`. The OpenWrt component
identifies the upstream base; `r<n>` increments for each release on that base. A change of OpenWrt
base restarts the release counter — for example a rebase onto 24.10.5 would be
`v24.10.5-pxlabs-cpe610-r1`.

---

## Unreleased

Content accumulated on `main` since `v24.10.4-pxlabs-cpe610-r1`. Destined for `r2`.

### Added

- **Operations and Maintenance Manual**
  ([`docs/CPE610_Operations_and_Maintenance_Manual.md`](docs/CPE610_Operations_and_Maintenance_Manual.md),
  revision 1.0). Covers the node in service: normal indications, logging, routine checks, start and
  stop procedures with the required restart order, fault isolation, recovery and rollback,
  configuration backup, replacement-unit provisioning and a maintenance record. Closes the gap
  between commissioning and in-service operation.
- **This changelog** and the
  [document register](docs/DOCUMENT_REGISTER.md), establishing release and document-revision
  tracking from r1 onward.

### Changed

- **The exposure of link and SSH key material in the upstream records repository is now recorded as
  an accepted risk rather than an open finding.** The operator assessed it as acceptable on the
  grounds that the installation is a test vehicle; no rotation is scheduled. Recorded with the
  accepting party, the date and the basis in README §9,
  [`docs/DEPLOYED_PARAMETERS.md`](docs/DEPLOYED_PARAMETERS.md) §10.1 and
  `deployment/README.md` §4. Each location states that the acceptance is scoped to the test
  installation and does not extend to a production vehicle.
- The security section of `DEPLOYED_PARAMETERS.md` was subdivided (§10.1 key material, §10.2 node
  SSH authentication, §10.3 this repository) so that the accepted risk does not obscure the two
  items that remain actionable.
- Exact file paths in the upstream records repository are no longer enumerated in this repository's
  documentation.
- Cross-reference tables in all five pre-existing documents updated to list the new manual.

### Documented for the first time

Findings established while writing the Operations and Maintenance Manual:

- Node logging is a **128 KiB in-memory ring buffer** (`log_size '128'`, `logd`). Nothing survives a
  reboot, so restarting a node under investigation destroys the only evidence.
- **NTP is configured on the node but unreachable** — the client is enabled against
  `openwrt.pool.ntp.org` while the node has no default route. The clock never synchronises, so node
  log timestamps cannot be correlated against the relay by absolute time.
- `option timezone 'IST-5:30'` is correct despite appearing inverted; POSIX reverses the sign, so it
  denotes UTC+5:30.
- The LAN LED is configured as `trigger netdev` / `mode link tx rx` on `eth0`, making it a usable
  first-line physical diagnostic.
- The deployed unit carries `tcpdump` 4.99.5-r1 and `ethtool` 6.11-r1, which the committed image does
  **not**. A replacement unit flashed from the image will lack both, and the node has no package feed
  to add them afterwards.

### Verified

- The per-release image recovery procedure was executed against r1: the file recovered with
  `git show <tag>:images/custom/…-sysupgrade.bin` matched the released SHA-256 exactly.
- SHA-256 values computed for the `images/stock/` pair, which carries no checksum file of its own.

---

## `v24.10.4-pxlabs-cpe610-r1` — 2026-09-27

First stable release. Tag points at commit `45f9f72`. Published as a GitHub release on
2026-09-27 at 06:33 UTC.

| Item | Value |
| --- | --- |
| Device | TP-Link CPE610 v2 (Atheros AR9344, `mips_24kc`) |
| OpenWrt | 24.10.4 (`r28959-29397011cc`), kernel 6.6.110 |
| WFB-NG | 25.01-r1, from the official OpenWrt 24.10.4 package feed |
| RF configuration | Channel 161, 5805 MHz, HT20, regulatory domain `BO` |
| Factory image SHA-256 | `c362d2a4dcbcd7175de9249b870456ab979315c27a1000619a2e23e0a073505c` |
| Sysupgrade image SHA-256 | `81d0090aac913561441014d54b0555ec595789f647b8e891496d75250eb4407d` |

### Deployment status at release

Two-node RF cluster verified end to end on 2026-09-26. The committed image matches the deployed
unit: 118 packages at identical versions, the device carrying only `ethtool` and `tcpdump` in
addition, from a marginally later build. Measured receive contribution 220 packets against the relay
adapter's 233 over the same interval, with `dec_err: [0, 0]`.

### Added

- Firmware images with WFB-NG incorporated, plus package manifest, CycloneDX SBOM and checksums
  (`images/custom/`).
- Unmodified OpenWrt 24.10.4 release images, retained for recovery (`images/stock/`).
- ImageBuilder and SDK build configuration (`config/`).
- TP-Link vendor configuration backup taken from the unit before conversion (`stock-firmware/`).
- Records of the configuration in force on the node, captured 2026-09-26 (`deployment/`, 12 files
  plus an annex describing them).
- Authoritative parameter reference (`docs/DEPLOYED_PARAMETERS.md`).
- Installation and commissioning manual, restructured as a six-part sequential procedure ending in a
  24-item acceptance checklist.
- Cluster deployment manual covering the systemd unit, per-profile environment and cluster
  troubleshooting.

### Fixed

- **WFB-NG provenance corrected.** Earlier documentation stated that the committed package recipes
  could not reproduce the committed image, and that closing the gap required re-importing recipes and
  rebuilding. That was wrong. WFB-NG 25.01-r1 is published in the official OpenWrt 24.10.4 package
  feed and was retrieved from it by the ImageBuilder; the feed is already declared in
  `config/imagebuilder-repositories.conf`, so the build is reproducible from the committed
  configuration alone. Established by three independent checks: the package control metadata records
  `Source: feeds/packages/net/wfb-ng`; the ImageBuilder download cache holds the two packages at
  `71e4fd95…` and `905a0269…`; and the ImageBuilder's own cached copy of the official feed index
  lists those identical checksums.
- **Deployed parameter values corrected against the running system.** Eight discrepancies between the
  documentation and the deployed configuration, all traced to a single mislabelling of
  `config/master.cfg` as the deployed configuration when it is the upstream template. Two have
  functional consequence: `api_port` and `stats_port` placed in `[cluster]` have no effect and belong
  in `[gs]`; and `custom_init_script` requires an explicit `sh` prefix or the monitor interface is
  never created. Full table in `docs/DEPLOYED_PARAMETERS.md` §1.
- **Documented build command corrected.** It carried `FILES=files/`, but no `files/` tree exists and
  neither `wfb-mon0.sh` nor `init.d/wfb-mon0` is present in the built root filesystem. The package
  selection was reconstructed from the 118-entry image manifest.
- **Boot behaviour corrected.** Both manuals instructed installation of `/etc/init.d/wfb-mon0` so the
  monitor interface is raised at boot. That service is not installed on the deployed node;
  `phy0-mon0` is created by the relay at each cluster start through `custom_init_script`.
- Malformed code fences from the original `.docx` conversion repaired, and duplicated section
  numbering resolved where two source documents had been concatenated.

### Removed

- Superseded WFB-NG 24.9.7-r2 package recipes (`package/wfb-ng/`, `package/wfb-ng-full/`) and the two
  compiled `.ipk` artifacts (`packages/ipk/`). These were an abandoned local-build approach that did
  not contribute to the deployed image: the `.ipk` files were staged in the ImageBuilder's
  `packages-local/` directory, whose index `Packages` is zero bytes, while `repositories.conf`
  declares the local repository as `file:packages`. Their presence implied, incorrectly, that they
  were a build input. Recoverable from history at `83c4879` and earlier.

### Documentation

All documents rewritten in technical-manual register with document-control blocks, numbered sections,
stated precedence and `NOTE` / `CAUTION` admonitions in place of conversational commentary. Revisions
as released are recorded in [`docs/DOCUMENT_REGISTER.md`](docs/DOCUMENT_REGISTER.md).

---

## Pre-release history

Recorded for traceability. These commits precede the first release.

| Commit | Date | Content |
| --- | --- | --- |
| `2abaf8e` | 2026-09-27 | Operations and Maintenance Manual added *(unreleased — see above)* |
| `d70416a` | 2026-09-27 | Key exposure recorded as an accepted risk *(unreleased — see above)* |
| `45f9f72` | 2026-09-27 | Superseded 24.9.7-r2 artifacts removed; commissioning manual restructured — **released as r1** |
| `83c4879` | 2026-09-27 | WFB-NG provenance corrected; documentation set rewritten in manual register |
| `bd41589` | 2026-09-26 | Deployed parameters corrected; `.docx` guides converted to Markdown; node records added |
| `dc707d8` | 2026-09-26 | Remote repository stub merged (unrelated histories) |
| `314cd4c` | 2026-09-26 | Initial import: CPE610 v2 OpenWrt 24.10.4 build material |
| `b3efb4d` | 2026-09-26 | Repository created |

---

## Carried forward

Open items at the current revision. None is a defect in the released firmware.

| Item | Status | Reference |
| --- | --- | --- |
| WFB-NG version skew — node at 25.01-r1, relay and drone at 25.4.27.73439 | Open, not a defect. In cluster mode the node is transparent: no key, no FEC, no session state. Only UDP datagram framing must correspond, and it does. | `docs/DEPLOYED_PARAMETERS.md` §8.1 |
| Node `dropbear` permits password authentication while key authentication already functions | Open. Recorded as found; not changed. | `docs/DEPLOYED_PARAMETERS.md` §10.2 |
| Key material exposed in the upstream records repository | **Risk accepted** by the operator, 2026-09-27, test installation only. Not scheduled for remediation. | `docs/DEPLOYED_PARAMETERS.md` §10.1 |
| OpenWrt failsafe mode, and reversion to vendor firmware | Documented but **not validated on this unit**. Validate on a spare before field use. | `docs/CPE610_Operations_and_Maintenance_Manual.md` §8.1, §9.5 |

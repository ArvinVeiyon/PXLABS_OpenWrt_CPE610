# Superseded WFB-NG Package Artifacts

| Field | Value |
| --- | --- |
| Document type | Artifact status notice |
| Revision | 1.0 |
| Date | 2026-09-27 |
| Status | Superseded — retained for historical traceability |

## Status

The `.ipk` files in this directory are **superseded and must not be used as a build input.**

| Artifact | Version |
| --- | --- |
| `wfb-ng_24.9.7-r2_mips_24kc.ipk` | 24.9.7-r2 |
| `wfb-ng-tun_24.9.7-r2_mips_24kc.ipk` | 24.9.7-r2 |

The deployed firmware contains WFB-NG **25.01-r1**, supplied by the official OpenWrt 24.10.4
package feed and resolved automatically by the ImageBuilder.

## Origin

These artifacts were produced on 2025-12-25 by compiling `svpcom/wfb-ng@3a05304` in the OpenWrt
SDK, using the recipes retained at `package/wfb-ng/` and `package/wfb-ng-full/`. That approach
was abandoned once the package was found to be published in the official feed.

## Evidence that they did not contribute to the deployed image

- The files were staged in the ImageBuilder's `packages-local/` directory, whose index file
  `Packages` is zero bytes. Nothing can be resolved from an empty index.
- `config/imagebuilder-repositories.conf` declares the local repository as `file:packages`, not
  `packages-local`.
- The image manifest records `wfb-ng - 25.01-r1` and `wfb-ng-tun - 25.01-r1`, and the
  corresponding downloaded packages in the ImageBuilder cache match the official feed index by
  SHA-256.

## Applicable procedures

| Objective | Reference |
| --- | --- |
| Reproduce the deployed image | README.md §7.1 |
| Provenance of WFB-NG 25.01-r1 | README.md §3 |
| Status of these artifacts | README.md §3.1 |
| Build WFB-NG from source, where a newer version is required | README.md §7.2 |

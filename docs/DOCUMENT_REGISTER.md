# Document Register

| Field | Value |
| --- | --- |
| Document type | Document control register |
| Applies to | All controlled documents in `PXLABS_OpenWrt_CPE610` |
| Revision | 1.0 |
| Date | 2026-09-27 |
| Status | Current |

**Purpose.** This register lists every controlled document in this repository with its current
revision, states which document governs on a conflict, and records the revision issued with each
release. Release content is recorded separately in [`../CHANGELOG.md`](../CHANGELOG.md).

---

## 1 Current register

| Document | Type | Rev | Date | Status | Governs |
| --- | --- | --- | --- | --- | --- |
| [`DEPLOYED_PARAMETERS.md`](DEPLOYED_PARAMETERS.md) | Parameter reference | 1.2 | 2026-09-27 | Current — **authoritative** | Every deployed parameter value: RF, cluster topology, addressing, ports, streams and FEC, security findings |
| [`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md) | Installation and commissioning manual | 2.1 | 2026-09-27 | Current | Build, flash, verify, configure and commission a node, end to end |
| [`CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md`](CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md) | Operational deployment manual (cluster) | 1.2 | 2026-09-27 | Current | Cluster configuration, the systemd unit, per-profile environment, cluster troubleshooting |
| [`CPE610_Operations_and_Maintenance_Manual.md`](CPE610_Operations_and_Maintenance_Manual.md) | Operations and maintenance manual | 1.0 | 2026-09-27 | Current | The node in service: checks, logging, restart order, fault isolation, recovery, replacement units |
| [`../README.md`](../README.md) | Technical reference | 1.2 | 2026-09-27 | Current | WFB-NG provenance, repository layout, image records, build reproduction, exclusions |
| [`../deployment/README.md`](../deployment/README.md) | Configuration records annex | 1.2 | 2026-09-27 | Current | What the node's captured records contain and what they establish |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Release changelog | 1.0 | 2026-09-27 | Current | What changed in each release |
| `DOCUMENT_REGISTER.md` (this document) | Document control register | 1.0 | 2026-09-27 | Current | Document revisions and precedence |

### 1.1 Uncontrolled files retained for reference

| File | Status |
| --- | --- |
| `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.docx` | Source document, retained unaltered. Superseded by the Markdown manual; **do not work from it** — its parameter values are wrong. |
| `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.docx` | As above, dated 27 Dec 2025. |
| `../config/master.cfg` | Upstream WFB-NG template, not the deployed configuration. Carries a `[PXLABS]` notice to that effect. |

---

## 2 Precedence

Where two documents disagree, the higher entry governs.

| Order | Document | Applies to |
| --- | --- | --- |
| 1 | `DEPLOYED_PARAMETERS.md` | Any parameter value |
| 2 | `deployment/README.md` and the `deployment/` records | What is actually configured on the node, as captured |
| 3 | The three manuals | Procedure |
| 4 | `README.md` | Repository and build facts |

**Rationale.** Parameter values were the single largest source of error in this repository's history:
eight discrepancies, all traceable to one mislabelled file. Naming one authoritative source and
giving it precedence in writing is what prevents that recurring. The manuals state procedure and
reproduce values only for continuity, always with a pointer to the authority.

---

## 3 Revision issued with each release

Release tags are frozen, so these rows are historical records and do not change.

### `v24.10.4-pxlabs-cpe610-r1` — 2026-09-27, tag at `45f9f72`

| Document | Revision as released |
| --- | --- |
| `DEPLOYED_PARAMETERS.md` | 1.1 |
| `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md` | 2.0 |
| `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md` | 1.1 |
| `README.md` | 1.1 |
| `deployment/README.md` | 1.1 |
| `CPE610_Operations_and_Maintenance_Manual.md` | Not issued — added after r1 |
| `CHANGELOG.md` | Not issued — added after r1 |
| `DOCUMENT_REGISTER.md` | Not issued — added after r1 |

To read a document exactly as released, take it from the tag rather than from `main`:

```sh
git show v24.10.4-pxlabs-cpe610-r1:docs/DEPLOYED_PARAMETERS.md
```

---

## 4 Revision history

### `DEPLOYED_PARAMETERS.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-26 | Issued. Eight deployed-parameter corrections established against the running system. |
| 1.1 | 2026-09-27 | Rewritten in manual register. WFB-NG version section corrected: 25.01-r1 comes from the official OpenWrt feed, and the 24.9.7-r2 artifacts were not a deployed-system discrepancy. |
| 1.2 | 2026-09-27 | Security section subdivided into §10.1 key material, §10.2 node SSH authentication, §10.3 this repository. Key exposure reclassified from open finding to accepted risk, test installation only. Related-documents table added. |

### `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-26 | Converted from the `.docx` source. Corrections applied inline and annotated. |
| 1.1 | 2026-09-27 | Rewritten in manual register. WFB-NG source corrected to the official feed; the `FILES=` overlay claim removed. |
| 2.0 | 2026-09-27 | Restructured as a six-part sequential procedure. Path register with real paths and shell variables added; build-output verification added; post-flash verification added; 24-item commissioning acceptance checklist added. Major revision — the document's structure changed, not only its content. |
| 2.1 | 2026-09-27 | Appendix B extended to list the Operations and Maintenance Manual. |

### `CPE610_OpenWrt_WFB-NG_RX_Deployment_Guide_v1.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-26 | Converted from the `.docx` source, dated 27 Dec 2025. Corrections applied inline and annotated. |
| 1.1 | 2026-09-27 | Rewritten in manual register. WFB-NG source corrected to the official feed; node verification command corrected (`wfb-server --version` is not valid on the node); real build paths substituted for placeholders. |
| 1.2 | 2026-09-27 | Related-documents table extended to list the Operations and Maintenance Manual. |

### `CPE610_Operations_and_Maintenance_Manual.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-27 | Issued. Twelve sections and two appendices. Five operational findings documented for the first time — see `../CHANGELOG.md`, Unreleased. Two procedures marked as not validated on this unit. |

### `README.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-26 | Issued alongside the parameter corrections. |
| 1.1 | 2026-09-27 | Rewritten as a technical reference in manual register. WFB-NG provenance section added with its evidence; superseded 24.9.7-r2 artifacts recorded as removed; build reproduction corrected and given real paths. |
| 1.2 | 2026-09-27 | Key exposure reclassified as an accepted risk in §9. Layout block extended for the Operations and Maintenance Manual. |

### `deployment/README.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-26 | Issued with the node records captured that day. |
| 1.1 | 2026-09-27 | Rewritten as a records annex in manual register. WFB-NG provenance finding corrected. |
| 1.2 | 2026-09-27 | Key exposure reclassified as an accepted risk in §4. |

### `CHANGELOG.md` and `DOCUMENT_REGISTER.md`

| Rev | Date | Change |
| --- | --- | --- |
| 1.0 | 2026-09-27 | Issued, establishing release and document-revision tracking from r1 onward. |

---

## 5 Conventions and maintenance

### 5.1 Revision numbering

| Increment | When |
| --- | --- |
| Major (`1.x` → `2.0`) | The document's structure or scope changes — sections renumbered, a procedure reordered, material moved in or out. |
| Minor (`1.1` → `1.2`) | Content changes within the existing structure: corrections, added notes, updated cross-references. |

A revision number is bumped **in the same commit as the change**. A document that changed without a
bump cannot be cited reliably, because two different contents then share one revision number.

**NOTE — one lapse on record.** All five documents issued with r1 were modified by commits `d70416a`
and `2abaf8e` without a revision bump. This was corrected when this register was created: those
documents now carry 1.2, 2.1 and 1.2 as listed in Section 1, and Section 3 records what r1 actually
shipped. The tag itself was not touched.

### 5.2 Relationship to frozen tags

A released tag is never moved, deleted or re-cut. A correction to released content is made on `main`
and carried into the next release. The current revision of a document on `main` may therefore be
ahead of the revision that any release shipped — Section 3 records the difference, and it is not
drift.

### 5.3 When the deployed configuration changes

A change to the node or relay configuration requires three updates in the same commit:

1. `DEPLOYED_PARAMETERS.md` — the value and, where relevant, its verification evidence.
2. The `deployment/` records — so the captured reference stays truthful.
3. Any procedure in the manuals that states the old value.

Then re-run the commissioning acceptance checks, installation manual §22, and record the
intervention in the Operations and Maintenance Manual §12.

### 5.4 Register maintenance

Update this register when a document is added, revised, superseded or withdrawn, and when a release
is cut. A document absent from Section 1 is not a controlled document and carries no authority.

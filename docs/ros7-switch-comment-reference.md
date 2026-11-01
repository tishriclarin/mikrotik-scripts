# RouterOS 7 switch interface comment convention

This document supersedes earlier examples that used `OLT:AREA1` for a port label or `NAS-LAN:101,102,103` to supply tagged VLANs.

## Canonical format

Interface comments are underscore-separated tokens, and argument values use a colon. The token order is flexible. Space characters inside VLAN lists are ignored.

```text
NAME:<label>_ROLE:<role>_PVID:<vid>_TAG:<vid>_TAGS:<vids>_MGMT:<vid>_UNTAG:<vid>_SPEED:<setting>_MEDIA:<type>_ARP:AUTO
```

- `NAME:<label>`: the interface's descriptive name. `NAME:AREA1`, `NAME:NAS-LAN`, `NAME:UPLINK` are valid.
- `TAGS:<list>`: tagged VLAN membership, such as `TAGS:101,102,103` or `TAGS:10to15`.
- `PVID:<vid>`: explicit untagged VLAN, which takes precedence over `UNTAG`.
- `TAG:<vid>`: **one** tagged service VLAN, used as an OLT ARP lookup reference when no explicit `PVID` exists.
- `MGMT:<vid>`: management VLAN, tagged by default. `UNTAG:<vid>` can make that VLAN the PVID only in the absence of an explicit PVID.
- `ROLE:<role>`: optional explicit port role. Supported roles: `OLT`, `UPLINK`, `DOWNLINK`, `NAS-LAN`, `NAS-WAN`, `MGMT`. When provided, this controls RSTP and OLT service discovery independent of `NAME`. For known labels like `NAME:NAS-LAN`, the role is inferred. An otherwise unrecognized `NAME` with a singular `TAG` or `PVID` is currently inferred to be an OLT; use `ROLE` to prevent accidental misclassification.
- `SPEED:AUTO` is the default. `1G` or `10G` requires compatible `MEDIA` for the current updater.
- `ARP:AUTO` is read-only discovery. Static ARP entries require verified IP, MAC and L3 interface evidence; this script does not add them.

## Examples

**NAS-LAN trunk — revised:**

```text
TAGS:101,102,103_NAME:NAS-LAN
```

Equivalent:

```text
NAME:NAS-LAN_TAGS:101,102,103
```

**OLT with untagged service VLAN:**

```text
NAME:AREA1_ROLE:OLT_PVID:51_MGMT:101_TAGS:10,11,12_SPEED:AUTO_ARP:AUTO
```

`ROLE:OLT` can be omitted in this example because a named port with an explicit `PVID` currently defaults to the OLT role. Keeping the role explicit is safer for mixed environments.

**OLT with tagged service VLAN:**

```text
NAME:AREA1_ROLE:OLT_TAG:51_MGMT:101_TAGS:10,11,12_SPEED:10G_MEDIA:OPTICAL_ARP:AUTO
```

**NAS-WAN trunk:**

```text
NAME:NAS-WAN_TAGS:20,101
```

**UPLINK:**

```text
NAME:UPLINK_VLAN:AUTO_MGMT:101
```

**Downstream switch:**

```text
NAME:DOWNLINK_ROLE:DOWNLINK_TAGS:10,11,12,51_MGMT:101
```

**Management access port:**

```text
NAME:MGMT_MGMT:101_UNTAG:101
```

**Reserved port:**

```text
NAME:OLT_RESERVED
```

## Removed duplicated syntax

`NAS-LAN:101,102,103` and `NAS-LAN:AUTO` are deprecated and now generate an explicit error in the script. Use `NAME:NAS-LAN_TAGS:...`.

Legacy `OLT:AREA1` is temporarily accepted with a warning, but `NAME:AREA1_ROLE:OLT` is the canonical form. A bridge comment uses the **separate** `MAIN-BRIDGE_SW:1_IGMP` convention; do not confuse its proposed `NAME` management-identity field with interface `NAME` parsing.

## Current limitations

The large `ros7UpdateSwitchConfig.rsc` updater has not been tested on production RouterOS 7.25 hardware. The management cutover, scheduled five-minute watchdog and reconnect confirmation remain a separate design, not executable migration. Preview only on remote devices until test results are reviewed.

## Frame-type and VLAN filtering behavior (November 2026)

`NAME:NAS-LAN_TAGS:10,11,12` describes a tagged-only NAS-LAN interface:

```routeros
frame-types=admit-only-vlan-tagged ingress-filtering=yes
```

`NAME:NAS-LAN_TAGS:10,11,12_PVID:51` describes a hybrid interface with tagged VLANs 10/11/12 and untagged VLAN 51:

```routeros
frame-types=admit-all ingress-filtering=yes pvid=51
```

`NAME:NAS-WAN_PVID:20` and `NAME: NAS-WAN_PVID:20` both describe an **untagged-only access port** using VLAN 20:

```routeros
frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes pvid=20
```

VLAN 20 becomes the port's dynamically untagged bridge VLAN membership through PVID, provided bridge VLAN filtering is enabled. It does not need a redundant static untagged bridge VLAN row. Management list membership may independently protect ports against changes.

### Bridge comment VLAN-FILTERING

- `MAIN-BRIDGE_SW:1_IGMP`: desired `vlan-filtering=yes` by default
- `MAIN-BRIDGE_SW:1_IGMP_VLAN-FILTERING:YES`: explicitly request `vlan-filtering=yes`
- `MAIN-BRIDGE_SW:1_IGMP_VLAN-FILTERING:NO`: explicitly request `vlan-filtering=no`

The updater compares desired and current values, previews only required changes, and places bridge VLAN filtering **last** in the apply sequence. If enabling VLAN filtering from `no` to `yes`, it fails closed unless the running configuration already contains a reachable VLAN-on-bridge management IP and bridge VLAN entries that admit the same management VLAN on the CPU bridge interface and the identified protected management port (tagged or correctly configured PVID). An absent/ambiguous path is not considered safe. It requires interactive Safe Mode, session verification, gateway ARP baseline and post-change check, and user confirmation. It does **not** create the independent five-minute management-migration watchdog.

**No RouterOS hardware test has been performed**. Use preview first. The bridge VLAN filtering transition can still interrupt forwarding or remove hardware offloading on incompatible switch chipsets; verify model support and use an out-of-band recovery path.

## Reserved physical interface-name prefixes

The actual RouterOS Ethernet interface name takes precedence over the `NAME:` comment when selecting the RSTP role and path cost:

| Physical interface name | Path cost | Edge | Restricted role |
| --- | ---: | --- | --- |
| `UPLINK*` | 1 | no | no |
| `NAS-LAN_*` or `NAS-LAN` | 10000 | no | yes |
| `OLT-*` | 20000 | yes-discover | yes |
| `DOWNLINK*` | 20000 | no | yes |
| All other interfaces | 20000 | yes-discover | yes |

Examples: `DOWNLINK1`, `DOWNLINK-AREA2`, and `DOWNLINK_sfp3` are downstream ports with `path-cost=20000`, `edge=no`, `restricted-role=yes`. `OLT-AREA1` has `path-cost=20000`. Management interface-list protections still override automatic bridge-port changes.

The conventions are prefix matches on physical interface names; `NAME:` and `ROLE:` remain fallback means to classify ports not using these reserved physical names. These rules do not guarantee root-port choice independently of spanning-tree BPDUs. Verify via RouterOS preview and bridge monitor before applying remotely.

## Automatic bridge hierarchy: SW:AUTO and SW-VALUE

On a bridge comment, `SW:AUTO` requests an automatic hierarchy proposal using RSTP:

```text
MAIN-BRIDGE_IGMP_VLAN-FILTERING:YES_SW:AUTO
```

The script reads the actual bridge RSTP `root-port` and `root-path-cost` twice, two seconds apart, using `/interface bridge monitor ... once do={...}`. It accepts the result only when both readings match, the local bridge is not the root, the bridge monitor reports an enabled state, the root port is a unique physical Ethernet bridge member marked UPLINK (reserved interface-name prefix or `ROLE:UPLINK` / `NAME:UPLINK`), and the local root-port `path-cost` is explicitly `1`. Physical names `NAS-LAN*`, `OLT-*` and `DOWNLINK*` are rejected even if their comment says UPLINK.

The measured root-path-cost must be an integer between 1 and 15. If valid, a value such as 4 produces:

```text
MAIN-BRIDGE_IGMP_VLAN-FILTERING:YES_SW:AUTO_SW-VALUE:4
```

The derived desired bridge priority is `4 * 4096 = 16384`. The script **previews** required changes and applies the bridge-comment and priority changes only after the existing safety/confirmation checks; it also checks that the root port has not changed after applying. When the root port is not UPLINK or RSTP values are unstable, missing, or out of range, **no automatic level is calculated**: `SW-VALUE` is left unchanged, priority is left unchanged, and the preview reports the skip reason.

`SW:N` remains the manual mode; `SW-VALUE` is script-managed output only when `SW:AUTO` is set. The reported root-path-cost represents cascade depth **only if every bridge on the path contributes exactly cost 1** and the RSTP root is the intended core. BPDUs carry a root bridge ID, not the core's RouterOS identity; the script does not yet authenticate the intended `CORE-SWITCH` root ID. Do not use `SW:AUTO` for production priority changes until the root ID and RouterOS monitor callback have been validated on your specific hardware.

The full updater remains untested on live RouterOS 7.25 hardware. Run dry-run and preview first.

## Pending SW:AUTO: CHECK-SW marker

When `SW:AUTO` cannot validate a stable RSTP UPLINK root port (including UPLINK being down), the current updater **plans** adding `_CHECK-SW` to the bridge comment. A valid later run proposes `SW-VALUE:N` and removes `_CHECK-SW` in that same change, after confirmation and the existing management safeguards. While pending, it does not replace the existing SW-VALUE or change the bridge priority.

**Trigger status:** an automatic periodic scheduler or link-up event trigger has **not yet been installed**. The flag alone is passive; currently the user must rerun the updater preview and apply. A future one-minute watchdog may check `CHECK-SW` and re-evaluate the RSTP root without running the entire configuration updater automatically. This avoids unintended VLAN changes and unapproved live RSTP priority changes.

In manual mode, bridge priority is `SW:N * 4096`; e.g. `SW:1` = `4096`. The actual root bridge priority is selected by RSTP, not guaranteed solely by this arithmetic.

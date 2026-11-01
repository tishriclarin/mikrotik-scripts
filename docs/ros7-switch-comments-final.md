# Final comment arguments: RouterOS 7 switch updater

Canonical specification consolidated on 2026-11-01. This describes the current updater and flags functionality that remains planned, not implemented. Full RouterOS 7.25 hardware testing has not been completed.

## 1. Main bridge comment

Manual bridge:

    MAIN-BRIDGE_SW:1_IGMP_VLAN-FILTERING:YES

Core bridge:

    MAIN-BRIDGE_SW:0_IGMP_VLAN-FILTERING:YES

Automatic level:

    MAIN-BRIDGE_SW:AUTO_IGMP_VLAN-FILTERING:YES

After successful automatic RSTP detection (script-managed result):

    MAIN-BRIDGE_SW:AUTO_IGMP_VLAN-FILTERING:YES_SW-VALUE:4

When automatic detection is unavailable (script-managed pending flag):

    MAIN-BRIDGE_SW:AUTO_IGMP_VLAN-FILTERING:YES_CHECK-SW

| Field | Valid arguments | Semantics |
| --- | --- | --- |
| MAIN-BRIDGE | Bridge selection marker, also supports exact legacy MAIN-SWITCH | If exactly one bridge exists, it is selected regardless of its comment; with multiple bridges the marker must uniquely identify the main one |
| SW | 0..15 or AUTO | Manual hierarchy level or guarded RSTP-derived hierarchy |
| SW-VALUE | Script-managed number | Result from SW:AUTO; do not supply manually |
| CHECK-SW | Script-managed pending flag | UPLINK root-port calculation unavailable; remove after successful guarded update |
| IGMP | IGMP (yes), IGMP:NO | Yes by default |
| VLAN-FILTERING | YES, NO | Yes by default; changes guarded and applied last |

SW:N bridge priority = N * 4096. SW:0 = 0, SW:1 = 4096, SW:4 = 16384.

SW:AUTO only proposes SW-VALUE when two RSTP monitor readings match and the root port is an eligible UPLINK with local port path-cost 1. The reported root-path-cost is treated as the depth (1..15). When validation fails the old priority and SW-VALUE are kept, and CHECK-SW is proposed. CHECK-SW is passive until the script is run again; an automatic retry scheduler is not yet installed. Root-path-cost represents hop count only if all path segments contribute cost 1. The expected CORE-SWITCH root bridge ID is not yet authenticated.

## 2. Interface comment grammar

Use underscore to separate tokens, colon to separate key/value, comma to separate VLAN values. Avoid underscores within NAME values because they are delimiters. NAME may contain spaces, for example `NAME:AREA1 OLT` or `NAME: NAS-WAN`; surrounding spaces are trimmed.

    NAME:<label>_ROLE:<role>_PVID:<vlan>_TAG:<vlan>_TAGS:<list>_MGMT:<vlan>_UNTAG:<vlan>_SPEED:<setting>_MEDIA:<type>_ARP:AUTO

The order of tokens is flexible. Use only the fields needed for each interface.

| Field | Accepted values | Result |
| --- | --- | --- |
| NAME | AREA1, UPLINK, NAS-LAN, NAS-WAN, DOWNLINK, MGMT, other label | **Bridge-port comment**: sets `/interface bridge port comment` to the NAME value without renaming the physical Ethernet interface |
| ROLE | OLT, UPLINK, DOWNLINK, NAS-LAN, NAS-WAN, MGMT | Explicit port role when needed |
| PVID | Exactly one VLAN, e.g. 51 | One untagged/native VLAN; wins over UNTAG |
| TAG | Exactly one VLAN, e.g. 51 | Tagged OLT service VLAN; used for ARP lookup if PVID is absent |
| TAGS | 10,11,12 or 10to15 or 10 to 15 or 10-15 | Additional tagged VLANs |
| MGMT | Numeric management VLAN, e.g. 101 | Tagged unless the port uses that VLAN as its effective PVID |
| UNTAG | One existing MGMT VLAN | Makes MGMT VLAN PVID only if no explicit PVID |
| VLAN | 20,101 or AUTO | Tagged VLAN membership; AUTO broad inclusion needs WAN/subscriber separation review |
| SPEED | AUTO, 1G, 10G | AUTO by default; forced speed currently requires MEDIA and model-compatible mode |
| MEDIA | OPTICAL, DAC, COPPER | Describes link medium for requested fixed speed |
| ARP | AUTO | Default, read-only MAC/IP discovery; does not create unverified static ARP |
| NAME:OLT_RESERVED / OTHER | Reserved/inactive | Disabled only when guarded policy allows; management ports protected |

Deprecated: NAS-LAN:10,11,12 and NAS-LAN:AUTO. Replace with NAME:NAS-LAN_TAGS:10,11,12. Legacy OLT:AREA1 temporarily accepted; use NAME:AREA1_ROLE:OLT instead.

VLAN access/frame-type outcomes:

| Comment | Frame types | Untagged/tagged |
| --- | --- | --- |
| NAME:NAS-WAN_PVID:20 | admit-only-untagged-and-priority-tagged | PVID 20 untagged |
| NAME:NAS-LAN_TAGS:10,11,12 | admit-only-vlan-tagged | VLANs 10,11,12 tagged |
| NAME:NAS-LAN_PVID:51_TAGS:10,11,12 | admit-all | VLAN 51 untagged, 10/11/12 tagged |
| NAME:MGMT_MGMT:101_UNTAG:101 | admit-only-untagged-and-priority-tagged | MGMT 101 untagged |
| NAME:AREA1_ROLE:OLT_PVID:51_MGMT:101_UNTAG:101 | admit-all | PVID 51 wins; MGMT 101 stays tagged |

ARP:AUTO scans VLAN from the explicit OLT PVID (priority) or singular TAG, and MGMT VLAN separately; only MAC prefix C0:FF:EE or C0:FE:EE (digit zero) is considered. Static ARP needs verified IP/MAC/L3 interface and is not automatically installed.


### NAME bridge-port comment reconciliation

For example, on a physical Ethernet interface `sfp-sfpplus3` with:

    NAME:AREA1 OLT_ROLE:OLT_PVID:51_MGMT:101

the updater previews and, when approved, performs:

    /interface bridge port set [find where interface="sfp-sfpplus3"] comment="AREA1 OLT"

It does **not** rename `sfp-sfpplus3`. Existing bridge ports are updated only when the comment differs; new bridge ports receive the comment after creation. The port remains referenced under its original physical name for VLAN and RSTP changes. Ports protected through the management interface lists are not modified.

## 3. Recommended ready-to-use examples

Uplink:

    NAME:UPLINK_VLAN:AUTO_MGMT:101_SPEED:AUTO

NAS-WAN access:

    NAME:NAS-WAN_PVID:20_SPEED:AUTO

NAS-LAN tagged trunk:

    NAME:NAS-LAN_TAGS:10,11,12,51_MGMT:101_SPEED:AUTO

NAS-LAN hybrid:

    NAME:NAS-LAN_TAGS:10,11,12_PVID:51_MGMT:101

OLT service VLAN untagged:

    NAME:AREA1_ROLE:OLT_PVID:51_MGMT:101_TAGS:10,11,12_SPEED:AUTO_ARP:AUTO

OLT service VLAN tagged:

    NAME:AREA1_ROLE:OLT_TAG:51_MGMT:101_TAGS:10,11,12_SPEED:10G_MEDIA:OPTICAL_ARP:AUTO

Downlink:

    NAME:AREA2_ROLE:DOWNLINK_TAGS:10,11,12,51_MGMT:101

Management access:

    NAME:MGMT_MGMT:101_UNTAG:101

Reserved:

    NAME:OLT_RESERVED

## 4. Reserved physical interface-name behavior

Actual RouterOS interface-name prefixes take precedence over descriptive NAME/ROLE for reserved physical port patterns:

| Physical interface-name prefix | RSTP path cost | edge | restricted-role |
| --- | ---: | --- | --- |
| UPLINK* | 1 | no | no |
| NAS-LAN_* or NAS-LAN | 10000 | no | yes |
| OLT-* | 20000 | yes-discover | yes |
| DOWNLINK* | 20000 | no | yes |
| Others | 20000 | yes-discover | yes |

Protected management interface lists: MGMT-IF, MGMT, MANAGEMENT. Management client IP source lists: MGMT, REMOTE-MGMT, MANAGEMENT, REMOTE-MANAGEMENT, REMOTE_MANAGEMENT.

## 5. Proposed but NOT YET implemented management migration

Planned management bridge arguments:

    MAIN-BRIDGE_SW:AUTO_IGMP_MGMT:101_IP:192.168.101.10/24_MGMT-PORTS:UPLINK,DETECT

The current updater does not implement that VLAN migration, user logout/reconnect, independent five-minute rollback watchdog, or link-up periodic CHECK-SW retry. Also, proposed system identity NAME:AREA1_DSW requires a custom parser for the underscore in its value; identity mismatch alone is not evidence of factory-default configuration. Refer to docs/ros7-management-vlan-cutover.md.

Always use the loader's dry-run, read-only preview and validated recovery access before applying to a production switch.

# RouterOS 7 management VLAN cutover: reconnect and recovery contract

Status: **design / not yet an executable production migration**. The current `ros7UpdateSwitchConfig.rsc` has not been modified by this document. Do not claim automatic five-minute rollback or automatic logout until a tested companion script exists.

## Input

`BRIGE-MAIN_SW:1_MGMT:101_IP:192.168.101.10/24_MGMT-PORTS:UPLINK,DETECT`

`BRIGE-MAIN` is accepted as supplied alongside corrected `BRIDGE-MAIN` or `MAIN-BRIDGE`. `DETECT` requests the management/Etherboot physical port. RouterBOOT `etherboot-port` is model-dependent and not available on all devices.

## Management/Etherboot port discovery: explicit, RouterBOOT, copper fallback

Apply the following ordered rules to identify the *designated management access port* (not proof of the current session's ingress):

1. **Known, unambiguous management port:** use a previously confirmed physical port from the switch model, explicit deployment configuration, or a uniquely matching physical interface from management interface lists (`MGMT-IF`, `MGMT`, `MANAGEMENT`). If a list contains multiple physical ports, it is not a unique management-port answer; continue with reliable device-specific evidence.
2. **RouterBOOT Etherboot port:** use `/system routerboard settings get etherboot-port` if the property is exposed and names an existing physical Ethernet interface. RouterBOOT exposes this setting only on certain models.
3. **One RJ45 copper Ethernet interface:** if no reliable identification above succeeds, enumerate actual Ethernet interfaces with **factory `default-name` matching `^ether[0-9]+# RouterOS 7 management VLAN cutover: reconnect and recovery contract

Status: **design / not yet an executable production migration**. The current `ros7UpdateSwitchConfig.rsc` has not been modified by this document. Do not claim automatic five-minute rollback or automatic logout until a tested companion script exists.

## Input

`BRIGE-MAIN_SW:1_MGMT:101_IP:192.168.101.10/24_MGMT-PORTS:UPLINK,DETECT`

**. If exactly one exists, select it as `DETECT`.
4. **Multiple RJ45 copper Ethernet interfaces:** select the **last physical copper port**, defined deterministically as the greatest numeric suffix of the factory `default-name` (e.g., `ether10` after `ether9`; do not compare names lexicographically).
5. **No reliable copper candidates:** fail closed. Never guess an SFP/QSFP interface. Combo ports and renamed or unusual copper interfaces can defeat the `etherN` heuristic and require model-specific verification.

Display a detection result such as `DETECT: ether8 [method=highest-numbered-copper, confidence=heuristic]` in preview, with the complete candidate list. **The heuristic must not authorize deleting the existing bridge IP, terminating the current user session, or modifying the selected management port without a separate management-VLAN reconnection proof and working five-minute rollback watchdog.** The physical access-port designation is not equivalent to identifying the *actual session ingress port*. Require explicit human confirmation when using the multi-copper fallback.

For an automatic cutover, do not silently set `UPLINK` or the selected `DETECT` port's PVID from the fallback until the migration transaction and watchdog have captured the exact original values and supplied a reliable recovery path.

The read-only detector is available as [`ros7DetectManagementPort.rsc`](../ros7DetectManagementPort.rsc) with its SHA-512 sidecar. Importing it registers a global function, then:

```routeros
:global ros7DetectManagementPort
:local managementPort [$ros7DetectManagementPort]
:put ("Proposed management/Etherboot access port: " . $managementPort)
```

Its output includes the discovery method and copper candidate list when fallback is needed. It does **not** modify any interface or prove the current session path. The management-VLAN migration script/watchdog is still unimplemented; wire this helper in only after validating its result on the specific CRS model.


## Initial state and staged configuration

- Select the only existing bridge, or uniquely labeled bridge; never change another bridge silently. If no bridge exists, use a separate first-provisioning process with explicit port assignments.
- Determine whether the specified VLAN interface (101) exists on the selected bridge, whether `192.168.101.10/24` is configured on it, and whether VLAN 101 has bridge CPU tagged membership, UPLINK tagged membership, and DETECT access-port untagged membership via PVID 101.
- A partial configuration is not "factory default". Compare and plan every missing/incorrect item separately; do not overwrite unrelated VLAN rows or working management interfaces.
- Add the VLAN interface with the bridge parent and desired address. Add/adjust tagged membership for the bridge CPU and UPLINK. Add/adjust PVID 101 and untagged membership for the explicitly identified access/BOOT port. When VLAN filtering is disabled, stage entries first; do not enable filtering until management access can be validated.
- Preserve the existing bridge IP and all original forwarding/bridge settings during test. Record exact original items and create rollback script BEFORE changing anything.
- Only one cutover may run. A persistent scheduled watchdog must be active BEFORE any forced logout and be able to rollback after five minutes without the interactive terminal or global function alive. On reboot, default to rollback rather than implicitly committing.

## Management connection branches (user-requested behavior)

### Current administrator is proven to be connected to the MGMT VLAN IP

1. Start the independent five-minute watchdog and apply only staged changes.
2. Positively identify the **original** terminal session as being connected to the management VLAN IP. RouterOS `/user active` shows the client SOURCE address, not the switch destination IP; a username/source match alone is insufficient. If the destination cannot be established, do not force logout.
3. After the independently scheduled rollback watchdog is armed, deliberately log out **only that original session ID**, using `/user active remove <id>` (or `request-logout` where supported). Do not terminate every session using the same username. The stage script must finish before an independent scheduled task performs the logout.
4. Require reconnection to the VLAN IP and a one-time confirmation command from that new session while the five-minute watchdog is pending. Confirmation must verify a new authenticated session, the expected management destination, and the staging token. Do not infer success from a matching username/source alone.
5. If confirmation occurs within five minutes, cancel the watchdog, then remove only the legacy IP on the bridge (if it was recorded as a migration candidate). Otherwise automatically restore the exact staged settings and leave the legacy IP intact.

### Current administrator is on the actual Etherboot/management access port

- **Do not disconnect the current session.** Preserve the port's bridge membership, PVID and old access until a new VLAN session is independently verified.
- Keep the legacy bridge IP while adding and testing the VLAN management path.
- Continue the non-disruptive next configuration stage only if the old session stays connected and the preflight confirms it does not touch the access port.
- Do not remove the bridge IP before explicit new-VLAN confirmation. The next configuration stage must not change the Etherboot port itself until migration commits.

### Connection cannot be established as either case

- Abort. Do not infer physical ingress from `/user active address` alone. ARP/FDB and connection tracking can help identify possible paths but may be absent or ambiguous.

## Watchdog contract

An independent RouterOS scheduler task polls pending state every ten seconds. Pending record includes switch identity, target VLAN/IP, original session ID/user, target IP, original configuration IDs/values, deadline, and a random one-time challenge. The watchdog is the ONLY path authorized to revert a timed-out or interrupted staged migration. Confirmation must be recorded in a way the scheduler can read reliably (not a per-terminal local/global variable), and must verify the new management path. Never use broad `/ip address remove [find interface=bridge]` or `/user active remove [find name=user]` operations. Do not delete previously existing bridge VLAN rows or bridge ports on rollback.

## Safety limitations

- Interactive Safe Mode is attached to the initiating terminal. Intentionally terminating that session while Safe Mode owns pending changes can trigger premature rollback. The forced-logout branch needs a separate watchdog-driven transaction; do not combine a forced logout with an assumed persistent Safe Mode transaction.
- `/user active` shows who connected and from where, **not the local destination IP**; obtaining destination proof may require network-specific tracking or a verified new-session challenge from a trusted source.
- A static gateway ping from the switch does not confirm subscriber-side switching. A gateway IP/ARP check remains a secondary check, not the commit condition.
- Do not mistake a link up on Etherboot for proven out-of-band access. The port must remain reachable when bridge filtering changes.

References: MikroTik RouterOS user session documentation, bridge management access/VLAN filtering, RouterBOARD etherboot-port model restrictions and scheduler guidance.

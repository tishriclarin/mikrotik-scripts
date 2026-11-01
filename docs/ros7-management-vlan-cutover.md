# RouterOS 7 management VLAN cutover: reconnect and recovery contract

Status: **design / not yet an executable production migration**. The current `ros7UpdateSwitchConfig.rsc` has not been modified by this document. Do not claim automatic five-minute rollback or automatic logout until a tested companion script exists.

## Input

`BRIGE-MAIN_SW:1_MGMT:101_IP:192.168.101.10/24_MGMT-PORTS:UPLINK,DETECT`

`BRIGE-MAIN` is accepted as supplied alongside corrected `BRIDGE-MAIN` or `MAIN-BRIDGE`. `DETECT` requests physical Etherboot port discovery only when the routerboard actually exposes the setting. Do not substitute ether1 silently: RouterBOOT etherboot-port is model-dependent.

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
2. Test the new VLAN path using a **second session** addressed explicitly to the VLAN interface IP. RouterOS `/user active` displays client SOURCE address, not the switch destination IP; same username/source alone is insufficient evidence that the new management VLAN works.
3. Only when a session can be positively associated with the new VLAN IP, intentionally log out **only the original session ID** with `/user active remove <id>` (or `request-logout` on builds with that action). Do not remove all sessions by username.
4. Require reconnection to the VLAN IP and a one-time confirmation command from that new session while the watchdog is pending. Successful reconnection requires both a new session and proof of its destination, not just a matching source address.
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

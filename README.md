# MikroTik Scripts

RouterOS 7 scripts with SHA-512 checksum sidecars.

## Integrity convention

Every `.rsc` file must have a matching checksum file:

```text
filename.rsc
filename.rsc.sha512
```

The checksum file uses the standard `sha512sum` format:

```text
<128-character SHA-512 digest>  filename.rsc
```

RouterOS natively supports SHA-512 through `:convert transform=sha512`. The verifier scans root-level `.rsc` files. Missing, malformed, oversized, or mismatched scripts are moved with their available checksum file into `invalid-files/`.

## Route-f installation

Download the verifier, its checksum, the installer, and its checksum:

```routeros
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/verify.rsc" dst-path="verify.rsc" check-certificate=yes
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/verify.rsc.sha512" dst-path="verify.rsc.sha512" check-certificate=yes
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/installers/install-route-f.rsc" dst-path="install-route-f.rsc" check-certificate=yes
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/installers/install-route-f.rsc.sha512" dst-path="install-route-f.rsc.sha512" check-certificate=yes
/import file-name="verify.rsc"
/import file-name="install-route-f.rsc"
```

If verification fails, `verify.rsc` raises an error and moves invalid files into `invalid-files/`. Do not import a quarantined file.

## Current limitation

RouterOS can retrieve a file's `contents` property directly only up to 60 KB. The verifier therefore rejects and quarantines larger scripts instead of partially verifying them.

## RouterOS 7: isolate OLT switch ports

The root-level `ros7_switch_isolate_olt.rsc` is an installer. Importing it creates the **persistent** system script `ros7_switch_isolate_olt` but does not run switch-port changes immediately. Its companion `ros7_switch_isolate_olt.rsc.sha512` follows the integrity convention above.

It selects Ethernet interfaces whose comments begin with `OLT-` and sets each matching port's `forwarding-override` to switch ports **on the same chip** whose Ethernet comments do **not** begin with `OLT-`. A switch CPU port, when exposed in the isolation table, is included. Only OLT ports are modified; other ports retain their settings.

### Download and install

```routeros
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/ros7_switch_isolate_olt.rsc" dst-path=ros7_switch_isolate_olt.rsc check-certificate=yes
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/ros7_switch_isolate_olt.rsc.sha512" dst-path=ros7_switch_isolate_olt.rsc.sha512 check-certificate=yes
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/verify.rsc" dst-path=verify.rsc check-certificate=yes
/tool fetch url="https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/main/verify.rsc.sha512" dst-path=verify.rsc.sha512 check-certificate=yes
/import file-name=verify.rsc
/import file-name=ros7_switch_isolate_olt.rsc
```

**Verification note:** `verify.rsc` checks **all** root-level `.rsc` files, not just this installer. It quarantines missing or mismatched checksum pairs. Download all required matching sidecars before invoking it, and do not import a quarantined file.

### Configure and safely apply

1. In **System → Scripts**, edit `ros7_switch_isolate_olt` and replace `SET_MGMT_IP` and `SET_GATEWAY` with the switch's **actual management source IPv4 address** and the **reachable management gateway**. This is deliberately manual: RouterOS cannot reliably infer which IP/gateway your remote session uses in every topology.
2. Open an **interactive** SSH or WinBox terminal and press **Ctrl+X**. Confirm the prompt displays `<SAFE>`. The system script cannot enter Safe Mode on behalf of the terminal session.
3. Run `/system script run ros7_switch_isolate_olt` from that session. The script tests gateway reachability before changing anything and after **each** OLT port, and attempts to restore original override values on a failed post-change test.
4. Verify `/interface ethernet switch port-isolation print detail`, check OLT forwarding, and establish a **second** remote SSH/WinBox session via the actual management path.
5. If everything works, return to the original `<SAFE>` terminal and press **Ctrl+X** to commit. If not, press **Ctrl+D** in that terminal to abandon changes. If disconnected unexpectedly, Safe Mode normally rolls the changes back after the connection times out.

**Limitations:** A successful gateway ping is not proof that your management session, OLT service, or RSTP topology remains functional. Do not use this as a zero-risk remote change. Have out-of-band access for critical switches. Supported hardware must expose the `/interface ethernet switch port-isolation` `forwarding-override` feature; some MikroTik switch families use different isolation mechanisms. This script is not automatically scheduled.

## Current global isolation script: ros7SwitchIsolateOLT

Use the separate loader `load-ros7SwitchIsolateOLT.rsc` for installation. Both `load-ros7SwitchIsolateOLT.rsc` and `ros7SwitchIsolateOLT.rsc` must be present under MikroTik Files. Download and verify their matching SHA-512 sidecars first.

Run:

```routeros
/import file-name=load-ros7SwitchIsolateOLT.rsc
:global ros7SwitchIsolateOLT
[$ros7SwitchIsolateOLT false]
```

The **main script** checks the RouterOS major version (7). The **separate loader** requires RouterOS 7.16+, checks that the main .rsc file exists, runs `/import file-name=ros7SwitchIsolateOLT.rsc verbose=yes dry-run`, and imports the main script **only when dry-run succeeds**. Main-script import registers the global function and performs a preview-only self-test; it does not apply port isolation.

For a remote apply, use an interactive Safe Mode session (Ctrl+X), verify a second management connection, and run `[$ros7SwitchIsolateOLT true]` after reviewing the plan.

Dry-run checks import syntax and some command errors but does not guarantee runtime or hardware compatibility. The existing `install-ros7SwitchIsolateOLT.rsc` is retained for compatibility; the recommended new entry point is `load-ros7SwitchIsolateOLT.rsc`.

**Pending safety features:** the current main script does not yet implement single-instance cancellation, a 30-second confirmation timeout, or automatic backup rotation.

## ros7UpdateSwitchConfig: loop protection on all Ethernet ports

The latest `ros7UpdateSwitchConfig.rsc` previews or enables `loop-protect=on` for **every physical Ethernet interface** on the switch. This includes UPLINK, NAS-LAN, OLT, DOWNLINK, unannotated ports, and MGMT-IF members. The MGMT-IF exception for VLAN/bridge/RSTP changes remains; only loop protection is applied to those interfaces. Existing `loop-protect-send-interval` and `loop-protect-disable-time` values are preserved.

The main script is used with `load-ros7UpdateSwitchConfig.rsc` and SHA-512 sidecars. The loader validates with import dry-run before registering the global function.

    /import file-name=load-ros7UpdateSwitchConfig.rsc
    :global ros7UpdateSwitchConfig
    [$ros7UpdateSwitchConfig false]

Review the preview before applying. RouterOS loop protection can temporarily disable a port if it detects its own loop-protect packet; the default recovery is five minutes unless configured otherwise. Because an uplink or management Ethernet port can be affected, apply remotely only with Safe Mode and an out-of-band recovery plan.

    [$ros7UpdateSwitchConfig true]

This is complementary to RSTP, not a replacement. Virtual/bridge interfaces are not modified by the all-Ethernet loop-protection step.

## RSTP port profiles (ros7UpdateSwitchConfig)

The comment-driven bridge updater now reconciles `edge`, `restricted-role`, and `path-cost` for both existing and newly created bridge ports on `MAIN-SWITCH`.

| Port type (comment prefix) | edge | restricted-role | path-cost |
| --- | --- | --- | --- |
| `UPLINK` | `no` | `no` | `1` |
| `NAS-LAN` | `no` | `no` | `10000` |
| `OLT`, `DOWNLINK`, other unprotected ports | `yes` | `yes` | `20000` |

The VLAN/bridge/RSTP settings of interfaces explicitly listed in `MGMT-IF` are preserved and may differ from these profiles. The all-Ethernet loop-protect setting remains separate.

**Safety:** `edge=yes` is intended for ports without downstream STP-aware bridges, and `restricted-role=yes` can place a port into discarding state when superior BPDUs are received. These configured preferences do not guarantee which port is elected root; verify the bridge monitor and live forwarding topology. Run a preview first and apply only under interactive Safe Mode with an out-of-band recovery path.

Use `load-ros7UpdateSwitchConfig.rsc` to dry-run and import the main script; call `[$ros7UpdateSwitchConfig false]` for preview and `[$ros7UpdateSwitchConfig true]` to apply after confirmation. Runtime hardware behavior has not been tested on the target switch.

## WAN-side UPLINK and OLT-side NAS-LAN role separation

Network topology clarification: `UPLINK` provides upstream VLAN/gateway connectivity for `NAS-WAN`; `NAS-LAN` carries the subscriber service VLANs toward `OLT` devices. **NAS-LAN is not a backup RSTP root path**.

Current `ros7UpdateSwitchConfig` RSTP policy: `UPLINK` has `edge=no restricted-role=no path-cost=1`, `NAS-LAN` has `edge=no restricted-role=yes path-cost=10000`, `DOWNLINK` has `edge=no restricted-role=yes path-cost=20000`, while `OLT` and other unprotected endpoint-facing ports use `edge=yes-discover restricted-role=yes path-cost=20000`. `MGMT-IF` bridge settings remain protected.

**AUTO VLAN caveat:** The existing `NAS-LAN:AUTO` rule still adds **every discovered VLAN**, including any WAN VLAN; `UPLINK_VLAN:AUTO` still adds tagged/MGMT VLANs while excluding OLT PVIDs. These behaviors were explicitly defined earlier and are **not yet adjusted to enforce strict WAN/subscriber VLAN separation**. Use an explicit numeric `NAS-LAN:...` VLAN list for production isolation until AUTO rules are narrowed. A descriptive `NAS-WAN:LABEL` alone does not identify VLAN IDs.

Spanning tree root selection depends on BPDUs received from a valid upstream switch; configured port costs do not guarantee a root port in an arbitrary topology. Always preview and verify the RSTP bridge monitor and VLAN forwarding before committing.

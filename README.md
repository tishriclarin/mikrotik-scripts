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

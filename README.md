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

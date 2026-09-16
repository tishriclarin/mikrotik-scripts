# MikroTik Configurator

Verified, modular RouterOS configuration projects with staging, SHA-512 verification, backups, uninstall, and snapshot restore.

## Router file tree

```text
mkt-scripts/
├── shared/
│   └── verify.rsc
├── bth/
│   ├── install.rsc
│   ├── apply.rsc
│   ├── uninstall.rsc
│   ├── restore.rsc
│   └── history/
├── autoconfigurator/
└── tmp/
```

RouterOS may display paths without a leading `/`; `mkt-scripts/...` and `/mkt-scripts/...` refer to the same logical project tree in this documentation.

## Trust and installation flow

1. Download `bth/install.rsc` from a pinned Git commit.
2. Import it. This only defines the `installBTHBootstrap` function.
3. Run `$installBTHBootstrap`. It downloads dependencies and their `.sha512` files into `mkt-scripts/tmp/bth`.
4. The bootstrap verifies `verify.rsc` itself before importing it.
5. `verify.rsc` verifies all remaining files before they are copied into permanent storage or imported.
6. The BTH installer runs in preview mode unless `confirm=yes` is supplied.
7. Temporary staged files are deleted after successful installation.

The pinned bootstrap is the root of trust. A checksum downloaded from the same mutable location as its file does not independently prevent repository compromise; pinning the initial installer commit prevents silent replacement of the bootstrap.

## Minimum target

- RouterOS 7.14 or later
- ARM, ARM64, or TILE RouterBOARD supported by Back to Home
- Internet and MikroTik IP Cloud access

## Bootstrap example

```routeros
/tool/fetch url="RAW_COMMIT_URL/mikrotik-configurator/bth/install.rsc" dst-path="mkt-scripts/bth/install.rsc"
/import file-name="mkt-scripts/bth/install.rsc" verbose=yes
$installBTHBootstrap
```

After the bootstrap succeeds, preview the configuration:

```routeros
$installBTH address="10.231.0.1/30" username="wg" os="debian" defaultRoute="no" protocol="tcp" ports="22,443,8291,8729" access="MGMT,NAT" reset-all="no" safe-mode="yes" backup="yes" confirm="no"
```


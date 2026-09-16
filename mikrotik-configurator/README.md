# MikroTik Configurator

Manifest-driven RouterOS configuration framework. Development currently focuses on the reusable `shared` engine and the `bth` project.

## Layout

```text
mikrotik-configurator/
├── shared/
│   ├── bootstrap.rsc
│   ├── verify.rsc
│   ├── runtime.rsc
│   ├── transaction.rsc
│   ├── install.rsc
│   └── uninstall.rsc
└── bth/
    ├── manifest.rsc
    ├── install.rsc
    ├── uninstall.rsc
    ├── restore.rsc
    └── files/
        ├── check_config.rsc
        ├── check_management.rsc
        ├── configure_bth.rsc
        ├── firewall_settings.rsc
        ├── address_lists.rsc
        ├── generate_client.rsc
        ├── test_connection.rsc
        ├── finalize.rsc
        ├── uninstall_project.rsc
        ├── restore_snapshot.rsc
        └── status.rsc
```

Every `.rsc` file has a sibling `.rsc.sha512` file. The bootstrap, manifest, shared runtime, and every project module are verified before execution.

## Runtime tree on RouterOS

```text
mkt-scripts/
├── shared/
├── bth/
│   ├── files/
│   └── history/
└── tmp/
```

## Execution model

1. Download `shared/bootstrap.rsc` from a pinned Git commit.
2. Import it and run `$bootstrapProject project="bth"`.
3. The bootstrap downloads and verifies the shared engine, BTH manifest, and thin wrappers.
4. Run `$installBTH ... confirm="no"` for verified staging and read-only prechecks.
5. Enter RouterOS Safe Mode and rerun with `confirm="yes"`.
6. The shared engine creates export/binary snapshots and a reverse-order rollback journal.
7. BTH modules execute in manifest order, followed by safety tests.
8. Successful transactions are marked `COMMITTED`; failures attempt rollback.

## BTH preview

```routeros
$installBTH address="10.231.0.1/30" username="wg" os="debian" defaultRoute="no" protocol="tcp" ports="22,443,8291,8729" access="MGMT,NAT" reset-all="no" safe-mode="yes" backup="yes" confirm="no"
```

`bth/install.rsc` and `bth/uninstall.rsc` are thin wrappers. Generic behavior remains in `shared/install.rsc` and `shared/uninstall.rsc`; BTH-specific operations remain under `bth/files`.


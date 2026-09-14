# installBTH RouterOS provisioner

Upload install_bth.rsc and install_bth.rsc.sha512 to RouterOS Files. Verify the checksum before importing.

Import once:

    /import file-name=install_bth.rsc

First call previews the exact plan and performs no mutation:

    $installBTH address="10.231.0.1/30" ports="22,443,8291,8729" access="MGMT,NAT" reset-all="no"

Defaults are username=wg, os=debian, defaultRoute=no, protocol=tcp, reset-all=no, safe-mode=yes, backup=yes, access=MGMT and confirm=no.

After reviewing the plan, enter native Safe Mode with Ctrl+X or F4 and rerun with confirmation:

    $installBTH address="10.231.0.1/30" ports="22,443,8291,8729" access="MGMT,NAT" reset-all="no" confirm="yes"

For split routing, optionally add:

    routes="10.231.0.0/30,192.168.100.0/24"

reset-all="yes" removes all BTH users plus addresses, firewall rules, and generated files tagged by this installer. It does not factory-reset RouterOS.

The generated Debian shell installer and SHA-512 file appear under RouterOS Files. Download both, run sha512sum -c filename.sha512, then execute the installer with sudo.

# Remove only MikroTik Configurator BTH-created objects.
:global uninstallBTH do={
    :local u $username
    :local approved $confirm
    :if ([:typeof $u] = "nothing") do={ :set u "wg" }
    :if ([:typeof $approved] = "nothing") do={ :set approved "no" }
    :local fwComment ("installBTH:firewall:" . $u)
    :local addrComment ("installBTH:address:" . $u)
    :local accessPrefix ("installBTH:access:" . $u . ":")
    :put ("Will remove BTH user and tagged objects for username=" . $u)
    :if ($approved != "yes") do={ :put "Preview only. Rerun with confirm=yes."; :return }
    /ip/cloud/back-to-home-users/remove [find where name=$u]
    /ip/firewall/filter/remove [find where comment=$fwComment]
    /ip/firewall/address-list/remove [find where comment~$accessPrefix]
    /ip/address/remove [find where comment=$addrComment]
    :log warning ("mkt-configurator: uninstalled BTH user " . $u)
    :put "BTH project objects removed. Use restore.rsc for a full snapshot restore."
}
:put "uninstallBTH loaded"


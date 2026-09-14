# MikroTik RouterOS 7
# Removes VRF-WAN10 through VRF-WAN23.
# Does not remove MACVLAN interfaces, DHCP clients, routes, NAT, or LAN config.
# Import with: /import file-name=undo-wan-vrf.rsc

:local removedCount 0
:local missingCount 0

:for wanNumber from=10 to=23 do={
    :local vrfName ("VRF-WAN" . $wanNumber)
    :local vrfID [/ip vrf find where name=$vrfName]

    :if ([:len $vrfID] > 0) do={
        /ip vrf remove $vrfID
        :set removedCount ($removedCount + 1)
        :log warning ("undo-wan-vrf: removed " . $vrfName)
    } else={
        :set missingCount ($missingCount + 1)
        :log info ("undo-wan-vrf: already absent " . $vrfName)
    }
}

:put ("WAN VRF undo completed: removed=" . $removedCount . ", already-absent=" . $missingCount)
:log warning ("undo-wan-vrf: completed; removed=" . $removedCount . ", already-absent=" . $missingCount)

/ip vrf print

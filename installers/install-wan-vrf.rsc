# MikroTik RouterOS 7
# Creates one VRF per WAN MACVLAN from WAN10-MAC through WAN23-MAC.
# LAN/customer VLAN interfaces are not changed and remain in main.
# Import with: /import file-name=install-wan-vrf.rsc

:local createdCount 0
:local updatedCount 0
:local missingCount 0
:local mainID [/ip vrf find where name="main"]

:if ([:len $mainID] = 0) do={
    :log error "install-wan-vrf: built-in main VRF was not found"
    :error "Built-in main VRF was not found"
}

:for wanNumber from=10 to=23 do={
    :local wanInterface ("WAN" . $wanNumber . "-MAC")
    :local vrfName ("VRF-WAN" . $wanNumber)
    :local wanInterfaceID [/interface find where name=$wanInterface]

    :if ([:len $wanInterfaceID] = 0) do={
        :set missingCount ($missingCount + 1)
        :log warning ("install-wan-vrf: skipped " . $vrfName . "; missing interface " . $wanInterface)
    } else={
        :local vrfID [/ip vrf find where name=$vrfName]

        :if ([:len $vrfID] = 0) do={
            /ip vrf add name=$vrfName interfaces=$wanInterface
            :set vrfID [/ip vrf find where name=$vrfName]
            :set createdCount ($createdCount + 1)
            :log info ("install-wan-vrf: created " . $vrfName . " for " . $wanInterface)
        } else={
            /ip vrf set $vrfID interfaces=$wanInterface disabled=no
            :set updatedCount ($updatedCount + 1)
            :log info ("install-wan-vrf: updated " . $vrfName . " for " . $wanInterface)
        }

        # VRF interface matching is top-to-bottom. Keep it above
        # the built-in main interfaces=all entry.
        :set mainID [/ip vrf find where name="main"]
        :if (([:len $vrfID] > 0) && ([:len $mainID] > 0)) do={
            /ip vrf move $vrfID $mainID
        }
    }
}

:put ("WAN VRF setup completed: created=" . $createdCount . ", updated=" . $updatedCount . ", missing-interfaces=" . $missingCount)
:log info ("install-wan-vrf: completed; created=" . $createdCount . ", updated=" . $updatedCount . ", missing=" . $missingCount)

/ip vrf print

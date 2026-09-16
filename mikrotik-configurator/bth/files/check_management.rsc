# Read-only management and Internet baseline
:global mktProjectContext
:local managementAddress ""
:local managementInterface "routed/unknown"
:local managementReachable false
:local internetReachable false
:foreach activeID in=[/user/active/find] do={
    :local activeVia [/user/active/get $activeID via]
    :if (($activeVia = "ssh") || ($activeVia = "telnet") || ($activeVia = "winbox")) do={
        :local candidate [/user/active/get $activeID address]
        :if ([:len $candidate] > 0) do={ :set managementAddress $candidate }
    }
}
:if ([:len $managementAddress] > 0) do={
    :if ([/ping address=$managementAddress count=2 interval=300ms] > 0) do={ :set managementReachable true }
    :local arpID [/ip/arp/find where address=$managementAddress]
    :if ([:len $arpID] > 0) do={ :set managementInterface [/ip/arp/get [:pick $arpID 0] interface] }
}
:if ([/ping address=8.8.8.8 count=2 interval=300ms] > 0) do={ :set internetReachable true }
:set ($mktProjectContext->"managementAddress") $managementAddress
:set ($mktProjectContext->"managementInterface") $managementInterface
:set ($mktProjectContext->"managementReachable") $managementReachable
:set ($mktProjectContext->"internetReachable") $internetReachable
:put ("Management=" . $managementAddress . " interface=" . $managementInterface . " reachable=" . $managementReachable)
:put ("Internet 8.8.8.8 reachable=" . $internetReachable)


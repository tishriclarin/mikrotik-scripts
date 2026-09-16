# Post-change safety tests
:global mktProjectContext
:local u ($mktProjectContext->"username")
:if ([:len [/ip/cloud/back-to-home-users/find where name=$u]] = 0) do={ :error "TEST FAILED: BTH user missing" }
:local bthIf ($mktProjectContext->"bthInterface")
:if ([:len [/interface/wireguard/find where name=$bthIf]] = 0) do={ :error "TEST FAILED: BTH WireGuard interface missing" }
:local managementAddress ($mktProjectContext->"managementAddress")
:if ((($mktProjectContext->"managementReachable") = true) && ([:len $managementAddress] > 0)) do={
    :if ([/ping address=$managementAddress count=3 interval=300ms] = 0) do={ :error "TEST FAILED: management source became unreachable" }
}
:if (($mktProjectContext->"internetReachable") = true) do={
    :if ([/ping address=8.8.8.8 count=3 interval=300ms] = 0) do={ :error "TEST FAILED: Internet connectivity changed" }
}
:put "BTH structural and reachability tests passed"


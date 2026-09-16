# Generate a WireGuard configuration artifact for the BTH user
:global mktProjectContext
:global mktWriteFile
:local u ($mktProjectContext->"username")
:local userID ($mktProjectContext->"userID")
:local clientAddress ($mktProjectContext->"clientAddress")
:local privateKey [/ip/cloud/back-to-home-users/get $userID private-key]
:local serverKey [/ip/cloud/get vpn-public-key]
:local vpnHost [/ip/cloud/get vpn-dns-name]
:local vpnPort [/ip/cloud/get vpn-port]
:local relayHost $vpnHost
:local vpnMarker [:find $vpnHost ".vpn."]
:if ([:typeof $vpnMarker] != "nil") do={
    :set relayHost ([:pick $vpnHost 0 $vpnMarker] . ".sn." . [:pick $vpnHost ($vpnMarker + 5) [:len $vpnHost]])
}
:local allowed ($mktProjectContext->"routes")
:if ([:typeof $allowed] = "nothing") do={ :set allowed "0.0.0.0/0" }
:if (($mktProjectContext->"defaultRoute") = "no") do={ :set allowed ($mktProjectContext->"address") }
:local configText ("[Interface]\nPrivateKey = " . $privateKey . "\nAddress = " . $clientAddress . "\n\n[Peer]\nPublicKey = //////////////////////////////////////////8=\nAllowedIPs = 0.0.0.0/32\nEndpoint = " . $relayHost . ":" . $vpnPort . "\nPersistentKeepalive = 15\n\n[Peer]\nPublicKey = " . $serverKey . "\nAllowedIPs = " . $allowed . "\nEndpoint = " . $vpnHost . ":" . $vpnPort . "\nPersistentKeepalive = 15\n")
:local configPath ("mkt-scripts/bth/client-" . $u . ".conf")
$mktWriteFile path=$configPath data=$configText
:set ($mktProjectContext->"clientConfig") $configPath

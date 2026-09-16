# Enable BTH and create the requested BTH user/address
:global mktProjectContext
:global mktJournalAdd
:global mktLog
:local a ($mktProjectContext->"address")
:local u ($mktProjectContext->"username")
:local resetAll ($mktProjectContext->"reset-all")
:local clientAddress ($mktProjectContext->"clientAddress")
:if ([:typeof $resetAll] = "nothing") do={ :set resetAll "no" }
:local userTag ("mkt-configurator:bth:user:" . $u)
/ip/cloud/set ddns-enabled=yes back-to-home-vpn=enabled
:delay 5s
:local bthIf [/ip/cloud/get vpn-interface]
:if ([:len $bthIf] = 0) do={ :error "BTH FAILED: vpn-interface unavailable" }
:if ($resetAll = "yes") do={ /ip/cloud/back-to-home-users/remove [find] }
/ip/cloud/back-to-home-users/remove [find where name=$u]
/ip/cloud/back-to-home-users/add name=$u client-address=$clientAddress allow-lan=yes
:local userID [/ip/cloud/back-to-home-users/find where name=$u]
:if ([:len $userID] = 0) do={ :error "BTH FAILED: user creation failed" }
:local addressTag ("mkt-configurator:bth:address:" . $u)
/ip/address/remove [find where comment=$addressTag]
/ip/address/add interface=$bthIf address=$a comment=$addressTag
:local undoAddress ("/ip/address/remove [find where comment=\"" . $addressTag . "\"]")
:local undoUser ("/ip/cloud/back-to-home-users/remove [find where name=\"" . $u . "\"]")
$mktJournalAdd command=$undoAddress
$mktJournalAdd command=$undoUser
:set ($mktProjectContext->"bthInterface") $bthIf
:set ($mktProjectContext->"userID") $userID
:local logMessage ("configured BTH user " . $u)
$mktLog message=$logMessage

# Add the BTH client prefix to requested address lists
:global mktProjectContext
:global mktJournalAdd
:local u ($mktProjectContext->"username")
:local accessList ($mktProjectContext->"access")
:if ([:typeof $accessList] = "nothing") do={ :set accessList "MGMT" }
:local userID ($mktProjectContext->"userID")
:local clientCIDR [/ip/cloud/back-to-home-users/get $userID client-address]
:local comma [:find $clientCIDR ","]
:if ([:typeof $comma] != "nil") do={ :set clientCIDR [:pick $clientCIDR 0 $comma] }
:foreach listName in=[:toarray $accessList] do={
    :if (($listName != "MGMT") && ($listName != "REMOTE-MGMT") && ($listName != "LAN") && ($listName != "WAN") && ($listName != "NAT")) do={
        :error ("BTH FAILED: unsupported access list " . $listName)
    }
    :local listTag ("mkt-configurator:bth:access:" . $u . ":" . $listName)
    /ip/firewall/address-list/remove [find where comment=$listTag]
    /ip/firewall/address-list/add list=$listName address=$clientCIDR comment=$listTag
    :local undoList ("/ip/firewall/address-list/remove [find where comment=\"" . $listTag . "\"]")
    $mktJournalAdd command=$undoList
}
:set ($mktProjectContext->"clientAddress") $clientCIDR

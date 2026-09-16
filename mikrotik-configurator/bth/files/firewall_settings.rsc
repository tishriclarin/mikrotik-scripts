# Install the BTH input rule
:global mktProjectContext
:global mktJournalAdd
:local u ($mktProjectContext->"username")
:local proto ($mktProjectContext->"protocol")
:local portList ($mktProjectContext->"ports")
:local bthIf ($mktProjectContext->"bthInterface")
:local clientAddress ($mktProjectContext->"clientAddress")
:local fwTag ("mkt-configurator:bth:firewall:" . $u)
/ip/firewall/filter/remove [find where comment=$fwTag]
/ip/firewall/filter/add chain=input action=accept protocol=$proto dst-port=$portList in-interface=$bthIf src-address=$clientAddress place-before=0 comment=$fwTag
:local undoFirewall ("/ip/firewall/filter/remove [find where comment=\"" . $fwTag . "\"]")
$mktJournalAdd command=$undoFirewall

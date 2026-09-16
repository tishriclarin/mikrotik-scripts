# Remove only objects owned by this BTH project
:global mktProjectContext
:local u ($mktProjectContext->"username")
:if ([:typeof $u] = "nothing") do={ :set u "wg" }
:local fwTag ("mkt-configurator:bth:firewall:" . $u)
:local addressTag ("mkt-configurator:bth:address:" . $u)
:local accessPrefix ("mkt-configurator:bth:access:" . $u . ":")
/ip/firewall/filter/remove [find where comment=$fwTag]
/ip/firewall/address-list/remove [find where comment~$accessPrefix]
/ip/address/remove [find where comment=$addressTag]
/ip/cloud/back-to-home-users/remove [find where name=$u]
:local clientFile ("mkt-scripts/bth/client-" . $u . ".conf")
/file/remove [find where name=$clientFile]
:log warning ("mkt-configurator: uninstalled BTH user " . $u)

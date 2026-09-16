# Read-only BTH parameter validation
:global mktProjectContext
:local a ($mktProjectContext->"address")
:local u ($mktProjectContext->"username")
:local targetOS ($mktProjectContext->"os")
:local useDefault ($mktProjectContext->"defaultRoute")
:local proto ($mktProjectContext->"protocol")
:local portList ($mktProjectContext->"ports")
:if ([:typeof $u] = "nothing") do={ :set u "wg"; :set ($mktProjectContext->"username") $u }
:if ([:typeof $targetOS] = "nothing") do={ :set targetOS "debian"; :set ($mktProjectContext->"os") $targetOS }
:if ([:typeof $useDefault] = "nothing") do={ :set useDefault "no"; :set ($mktProjectContext->"defaultRoute") $useDefault }
:if ([:typeof $proto] = "nothing") do={ :set proto "tcp"; :set ($mktProjectContext->"protocol") $proto }
:if ([:typeof $a] = "nothing") do={ :error "PRECHECK FAILED: address is required" }
:if ($targetOS != "debian") do={ :error "PRECHECK FAILED: only Debian is supported" }
:if (($useDefault != "yes") && ($useDefault != "no")) do={ :error "PRECHECK FAILED: defaultRoute must be yes or no" }
:if (($proto != "tcp") && ($proto != "udp")) do={ :error "PRECHECK FAILED: protocol must be tcp or udp" }
:if ([:typeof $portList] = "nothing") do={ :error "PRECHECK FAILED: ports is required" }
:local slash [:find $a "/"]
:if ([:typeof $slash] = "nil") do={ :error "PRECHECK FAILED: address must include /30" }
:if ([:pick $a ($slash + 1) [:len $a]] != "30") do={ :error "PRECHECK FAILED: only /30 is supported" }
:local routerIP [:pick $a 0 $slash]
:local dot1 [:find $routerIP "."]
:local dot2 [:find $routerIP "." ($dot1 + 1)]
:local dot3 [:find $routerIP "." ($dot2 + 1)]
:if ([:typeof $dot3] = "nil") do={ :error "PRECHECK FAILED: invalid IPv4 address" }
:local lastOctet [:tonum [:pick $routerIP ($dot3 + 1) [:len $routerIP]]]
:if (([:typeof $lastOctet] = "nil") || (($lastOctet % 4) != 1)) do={ :error "PRECHECK FAILED: /30 router address must be first usable address" }
:local prefix [:pick $routerIP 0 ($dot3 + 1)]
:local clientAddress ($prefix . ($lastOctet + 1) . "/32")
:set ($mktProjectContext->"routerIP") $routerIP
:set ($mktProjectContext->"clientAddress") $clientAddress
:put ("BTH precheck: username=" . $u . " address=" . $a . " os=" . $targetOS)

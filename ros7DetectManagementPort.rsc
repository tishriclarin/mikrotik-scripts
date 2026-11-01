# RouterOS 7 read-only management/Etherboot port detector.
# Import registers the global function and stores a persistent loader.
# Usage: :global ros7DetectManagementPort; :put [$ros7DetectManagementPort]
:local v [/system resource get version]
:if ([:pick $v 0 2] != "7.") do={ :error ("RouterOS 7 required: " . $v) }
:local prior [/system script find where name="ros7DetectManagementPort"]
:if ([:len $prior] > 1) do={ :error "Duplicate detector scripts" }
:if ([:len $prior] = 1) do={ /system script remove $prior }
/system script add name=ros7DetectManagementPort policy=read,test source={
    :global ros7DetectManagementPort do={
        :global ros7ManagementPortMethod
        :local chosen ""
        :local method ""
        :local names ""
        :local physicalNames [:toarray ""]

        # Prefer an explicit and unique physical management interface-list member.
        :foreach listName in={"MGMT-IF";"MGMT";"MANAGEMENT"} do={
            :local foundList [/interface list find where name=$listName]
            :if ([:len $foundList] > 1) do={
                :error ("Ambiguous interface list " . $listName)
            }
            :if ([:len $foundList] = 1) do={
                :foreach member in=[/interface list member find where list=$listName] do={
                    :local name [/interface list member get $member interface]
                    :if ([:len [/interface ethernet find where name=$name]] = 1) do={
                        :if ([:typeof [:find ("," . $names . ",") ("," . $name . ",")]] = "nil") do={
                            :if ([:len $names] = 0) do={ :set names $name } else={
                                :set names ($names . "," . $name)
                            }
                            :set physicalNames ($physicalNames, $name)
                        }
                    }
                }
            }
        }
        :if ([:len $physicalNames] = 1) do={
            :set chosen [:pick $physicalNames 0]
            :set method "unique-management-interface-list"
        }
        :if ([:len $physicalNames] > 1) do={
            :put ("Multiple management-list Ethernet members: " . $names)
        }

        # Try RouterBOOT etherboot-port where supported. It may be absent.
        :if ($chosen = "") do={
            :local bootName ""
            :onerror bootError in={
                :set bootName [:tostr [/system routerboard settings get etherboot-port]]
            } do={
                :put "RouterBOOT etherboot-port not exposed; considering copper fallback"
            }
            :if ([:len $bootName] > 0) do={
                :local found [/interface ethernet find where name=$bootName]
                :if ([:len $found] != 1) do={
                    :set found [/interface ethernet find where default-name=$bootName]
                }
                :if ([:len $found] = 1) do={
                    :set chosen [/interface ethernet get $found name]
                    :set method "routerboot-etherboot-port"
                }
            }
        }

        # Fallback only: factory default-name etherN = built-in RJ45 candidate.
        # The largest numeric N wins. Never use alphabetical sorting.
        :if ($chosen = "") do={
            :local count 0
            :local maxNum -1
            :local maxName ""
            :foreach eth in=[/interface ethernet find] do={
                :local factory [:tostr [/interface ethernet get $eth default-name]]
                :local name [/interface ethernet get $eth name]
                :if ($factory ~ "^ether[0-9]+$") do={
                    :local number [:tonum [:pick $factory 5 [:len $factory]]]
                    :if ([:typeof $number] = "num") do={
                        :set count ($count + 1)
                        :put ("COPPER CANDIDATE: " . $factory . " => " . $name)
                        :if ($number > $maxNum) do={
                            :set maxNum $number
                            :set maxName $name
                        }
                    }
                }
            }
            :if ($count = 1) do={
                :set chosen $maxName
                :set method "sole-etherN-copper-fallback"
            }
            :if ($count > 1) do={
                :set chosen $maxName
                :set method "highest-numbered-etherN-copper-fallback"
            }
        }
        :if ($chosen = "") do={
            :error "ABORT: Cannot identify management/Etherboot RJ45 physical port"
        }
        :set ros7ManagementPortMethod $method
        :put ("MGMT DETECT: " . $chosen . " method=" . $method)
        :if ($method ~ "fallback$") do={
            :put "HEURISTIC ONLY: Not proof of current session ingress."
            :put "Do not disconnect sessions or remove old bridge IP without reconnect test and watchdog."
        }
        :return $chosen
    }
}
/system script run ros7DetectManagementPort
:put "Global ros7DetectManagementPort available (read only)."

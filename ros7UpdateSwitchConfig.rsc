# ros7UpdateSwitchConfig.rsc
# RouterOS 7 global function installer.
# No configuration changes during import.
# Call: :global ros7UpdateSwitchConfig; [$ros7UpdateSwitchConfig false]
# Apply: enter Safe Mode, then [$ros7UpdateSwitchConfig true]
:local version [/system resource get version]
:if ([:pick $version 0 2] != "7.") do={ :error ("RouterOS 7 required: " . $version) }
:local prior [/system script find where name="ros7UpdateSwitchConfig"]
:if ([:len $prior] > 1) do={ :error "Duplicate system-script names" }
:if ([:len $prior] = 1) do={ /system script remove $prior }
/system script add name=ros7UpdateSwitchConfig policy=read,write,test source={
    :global ros7UpdateSwitchConfig do={
    :local apply $1
    :if ([:typeof $apply] = "nil") do={ :set apply false }
    :if ([:typeof $apply] != "bool") do={ :error "Boolean argument required" }
    :local version [/system resource get version]
    :if ([:pick $version 0 2] != "7.") do={ :error "RouterOS 7 required" }

    :local append do={
        :local old [:tostr $1]
        :local item [:tostr $2]
        :if ([:len $item] = 0) do={ :return $old }
        :if ([:typeof [:find ("," . $old . ",") ("," . $item . ",")]] = "nil") do={
            :if ([:len $old] = 0) do={ :return $item }
            :return ($old . "," . $item)
        }
        :return $old
    }

    :local expand do={
        :local raw [:tostr $1]
        :local result ""
        :local emitted 0
        :local clean ""
        :for i from=0 to=([:len $raw] - 1) do={
            :local ch [:pick $raw $i ($i + 1)]
            :if ($ch != " ") do={ :set clean ($clean . $ch) }
        }
        :set raw $clean
        :while ([:len $raw] > 0) do={
            :local comma [:find $raw ","]
            :local token ""
            :if ([:typeof $comma] = "nil") do={
                :set token $raw
                :set raw ""
            } else={
                :set token [:pick $raw 0 $comma]
                :set raw [:pick $raw ($comma + 1) [:len $raw]]
            }
            :if ([:len $token] = 0) do={ :error "Empty VLAN element" }
            :local split [:find $token "to"]
            :local chars 2
            :if ([:typeof $split] = "nil") do={
                :set split [:find $token "-"]
                :set chars 1
            }
            :local low 0
            :local high 0
            :if ([:typeof $split] = "nil") do={
                :set low [:tonum $token]
                :set high $low
            } else={
                :set low [:tonum [:pick $token 0 $split]]
                :set high [:tonum [:pick $token ($split + $chars) [:len $token]]]
            }
            :if (([:typeof $low] != "num") || ([:typeof $high] != "num")) do={
                :error ("Invalid VLAN expression " . $token)
            }
            :if (($low < 1) || ($high > 4094) || ($high < $low) || (($high - $low) > 255)) do={
                :error ("Invalid VLAN range " . $token)
            }
            :for vlan from=$low to=$high do={
                :set emitted ($emitted + 1)
                :if ($emitted > 256) do={ :error "More than 256 VLAN entries" }
                :local v [:tostr $vlan]
                :if ([:typeof [:find ("," . $result . ",") ("," . $v . ",")]] = "nil") do={
                    :if ([:len $result] = 0) do={ :set result $v } else={
                        :set result ($result . "," . $v)
                    }
                }
            }
        }
        :return $result
    }

    :local allBridges [/interface bridge find]
    :local bridgeTotal [:len $allBridges]
    :if ($bridgeTotal = 0) do={
        :error "ABORT: No bridge exists on this switch"
    }
    :local bridgeId ""
    :if ($bridgeTotal = 1) do={
        :set bridgeId [:pick $allBridges 0]
        :put "MAIN-SWITCH auto-detected: only one bridge exists."
    } else={
        :local matches [:toarray ""]
        :foreach bridgeItem in=$allBridges do={
            :local bc [:tostr [/interface bridge get $bridgeItem comment]]
            :if (($bc = "MAIN-SWITCH") || ($bc ~ "^MAIN-BRIDGE")) do={
                :set matches ($matches, $bridgeItem)
            }
        }
        :if ([:len $matches] != 1) do={
            :error ("ABORT: " . $bridgeTotal . " bridges exist; uniquely mark MAIN-BRIDGE or MAIN-SWITCH")
        }
        :set bridgeId [:pick $matches 0]
        :put "MAIN-SWITCH selected using bridge comment."
    }
    :local bridgeName [/interface bridge get $bridgeId name]
    :local bridgeComment [:tostr [/interface bridge get $bridgeId comment]]
    :local filtering [/interface bridge get $bridgeId vlan-filtering]
    :local wantFiltering true
    :local filterNo ($bridgeComment ~ "(^|_)VLAN-FILTERING:NO($|_)")
    :local filterYes ($bridgeComment ~ "(^|_)VLAN-FILTERING:YES($|_)")
    :if ($filterNo && $filterYes) do={ :error "Conflicting bridge VLAN-FILTERING values" }
    :if ($filterNo) do={ :set wantFiltering false }
    :if (($bridgeComment ~ "(^|_)VLAN-FILTERING:") && (!$filterNo) && (!$filterYes)) do={
        :error "VLAN-FILTERING accepts only YES or NO"
    }
    :local wantIgmp true
    :if ($bridgeComment ~ "(^|_)IGMP:NO($|_)") do={
        :set wantIgmp false
    }
    :local igmpNow [/interface bridge get $bridgeId igmp-snooping]
    :put ("BRIDGE: " . $bridgeName . " comment=" . $bridgeComment)
    :local protocol [/interface bridge get $bridgeId protocol-mode]
    :if ($protocol != "rstp") do={
        :error ("MAIN-SWITCH must use rstp; existing protocol-mode=" . $protocol)
    }
    :local identity [/system identity get name]
    :local swAuto ($bridgeComment ~ "(^|_)SW:AUTO($|_)")
    :local swReady false
    :local hopLevel 0
    :local proposedBridgeComment $bridgeComment
    :local autoRootPort ""
    :if ($swAuto) do={
        :local p1 ""; :local p2 ""
        :local c1 -1; :local c2 -1
        :local r1 ""; :local r2 ""
        :local id1 ""; :local id2 ""
        :local state1 ""; :local state2 ""
        :onerror e in={
            /interface bridge monitor $bridgeName once do={
                :set p1 [:tostr $"root-port"]
                :set c1 [:tonum $"root-path-cost"]
                :set r1 [:tostr $"root-bridge"]
                :set id1 [:tostr $"root-bridge-id"]
                :set state1 [:tostr $state]
            }
            :delay 2s
            /interface bridge monitor $bridgeName once do={
                :set p2 [:tostr $"root-port"]
                :set c2 [:tonum $"root-path-cost"]
                :set r2 [:tostr $"root-bridge"]
                :set id2 [:tostr $"root-bridge-id"]
                :set state2 [:tostr $state]
            }
        } do={ :put ("SW:AUTO monitor failed: " . $e) }
        :if (($p1 = $p2) && ($c1 = $c2) && ($r1 = $r2) && ($id1 = $id2) && ([:len $id1] > 0) && ($state1 = "enabled") && ($state1 = $state2) && (($r1 = "no") || ($r1 = "false")) && ([:typeof $c1] = "num") && ($c1 >= 1) && ($c1 <= 15) && ($p1 != "") && ($p1 != "none")) do={
            :local bp [/interface bridge port find where bridge=$bridgeName and interface=$p1]
            :local eth [/interface ethernet find where name=$p1]
            :if (([:len $bp] = 1) && ([:len $eth] = 1)) do={
                :local pc [/interface ethernet get $eth comment]
                :local uplink (($p1 ~ "^UPLINK") || ($pc ~ "(^|_)ROLE:UPLINK($|_)") || ($pc ~ "(^|_)NAME: *UPLINK($|_)"))
                :if (($p1 ~ "^NAS-LAN(_|$)") || ($p1 ~ "^OLT-") || ($p1 ~ "^DOWNLINK")) do={ :set uplink false }
                :if ($uplink && ([:tostr [/interface bridge port get $bp path-cost]] = "1")) do={
                    :set swReady true
                    :set hopLevel $c1
                    :set autoRootPort $p1
                }
            }
        }
        :if (!$swReady) do={
            :put ("SW:AUTO SKIP: root-port=" . $p1 . " cost=" . $c1 . ". Requires stable UPLINK root port with cost=1.")
        } else={
            :local pos [:find $bridgeComment "_SW-VALUE:"]
            :if ([:typeof $pos] = "nil") do={
                :set proposedBridgeComment ($bridgeComment . "_SW-VALUE:" . $hopLevel)
            } else={
                :local next [:find $bridgeComment "_" ($pos + 1)]
                :local prefix [:pick $bridgeComment 0 ($pos + 10)]
                :if ([:typeof $next] = "nil") do={
                    :set proposedBridgeComment ($prefix . $hopLevel)
                } else={
                    :set proposedBridgeComment ($prefix . $hopLevel . [:pick $bridgeComment $next [:len $bridgeComment]])
                }
            }
            :put ("SW:AUTO verified root-port=" . $p1 . " root-path-cost=" . $hopLevel)
        }
    } else={
        :local reference $identity
        :if ($bridgeComment ~ "(^|_)SW:[0-9]+($|_)") do={ :set reference $bridgeComment }
        :local pos [:find $reference "_SW:"]
        :if ([:typeof $pos] = "nil") do={ :error "Need SW:AUTO or SW:N" }
        :local digits [:pick $reference ($pos + 4) [:len $reference]]
        :local next [:find $digits "_"]
        :if ([:typeof $next] != "nil") do={ :set digits [:pick $digits 0 $next] }
        :set hopLevel [:tonum $digits]
        :if (([:typeof $hopLevel] != "num") || ($hopLevel < 0) || ($hopLevel > 15)) do={ :error "SW level out of range 0..15" }
        :set swReady true
    }
    :local desiredPriority ($hopLevel * 4096)
    :local currentPriority [/interface bridge get $bridgeId priority]
    :if ($swReady) do={ :put ("SW level=" . $hopLevel . " desired bridge priority=" . $desiredPriority) }
    :put "Only UPLINK is an allowed root-port path (cost 1); NAS-LAN serves the OLT gateway (cost 10000, root guarded)."
    :put "Comments: use NAME:XXX for port identity, TAGS:... for VLAN membership; ROLE:OLT optional if service VLAN is not explicit."
    :put "UPLINK: edge=no role=no; NAS-LAN: edge=no role=yes; DOWNLINK: edge=no role=yes; OLT/other: edge=yes-discover role=yes."
    :if ($swReady && ($hopLevel = 0)) do={
        :put "CORE LEVEL 0: root bridge has no root port."
    }
    :put "TOPOLOGY: UPLINK supplies VLAN/gateway access to NAS-WAN."
    :put "TOPOLOGY: NAS-LAN carries the OLT subscriber service VLANs."
    :put "NAS-LAN uses TAGS for explicit subscriber VLAN membership."
    :put "Separate WAN VLANs from subscriber VLANs with explicit TAGS lists."
    :put ("BRIDGE: " . $bridgeName . " vlan-filtering=" . $filtering)
    :put "VLAN-FILTERING follows bridge comment, with guarded apply-last behavior."
    :if (!$filtering && $wantFiltering) do={
        :put "VLAN FILTERING: currently no; desired yes (preflight required)."
    }

    :local roleOf do={
        :local c [:tostr $1]
        :local physical [:tostr $2]
        :if ($physical ~ "^UPLINK") do={ :return "UPLINK" }
        :if ($physical ~ "^NAS-LAN(_|$)") do={ :return "NAS-LAN" }
        :if ($physical ~ "^OLT-") do={ :return "OLT" }
        :if ($physical ~ "^DOWNLINK") do={ :return "DOWNLINK" }
        :foreach role in={"UPLINK";"NAS-LAN";"NAS-WAN";"DOWNLINK";"MGMT";"OLT"} do={
            :if ($c ~ ("(^|_)ROLE:" . $role . "($|_)")) do={ :return $role }
        }
        :foreach role in={"UPLINK";"NAS-LAN";"NAS-WAN";"DOWNLINK";"MGMT";"OLT"} do={
            :if ($c ~ ("(^|_)NAME: *" . $role . "($|_)")) do={ :return $role }
        }
        :if ($c ~ "(^|_)NAME: *UPLINK") do={ :return "UPLINK" }
        :if ($c ~ "(^|_)NAME: *OLT-") do={ :return "OLT" }
        :if ($c ~ "^UPLINK") do={ :return "UPLINK" }
        :if ($c ~ "^DOWNLINK") do={ :return "DOWNLINK" }
        :if ($c ~ "^OLT:") do={ :return "OLT" }
        :if ($c ~ "(^|_)NAS-LAN:") do={ :return "NAS-LAN" }
        :if (($c ~ "(^|_)NAME:") && (($c ~ "(^|_)PVID:") || ($c ~ "(^|_)TAG:"))) do={ :return "OLT" }
        :return "OTHER"
    }

    :local stpCostByName do={
        :local p [:tostr $1]
        :local c [:tostr $2]
        :if ($p ~ "^UPLINK") do={ :return 1 }
        :if ($p ~ "^NAS-LAN(_|$)") do={ :return 10000 }
        :if (($p ~ "^OLT-") || ($p ~ "^DOWNLINK")) do={ :return 20000 }
        :if ($c ~ "(^|_)NAME: *") do={
            :if ($c ~ "(^|_)NAME: *UPLINK") do={ :return 1 }
            :if ($c ~ "(^|_)NAME: *NAS-LAN($|_)") do={ :return 10000 }
            :return 20000
        }
        :if ($p ~ "^UPLINK") do={ :return 1 }
        :if ($p ~ "^NAS-LAN(_|$)") do={ :return 10000 }
        :return 20000
    }

    :local mgmtMembers ""
    :foreach listName in={"MGMT-IF";"MGMT";"MANAGEMENT"} do={
        :local mgmtList [/interface list find where name=$listName]
        :if ([:len $mgmtList] > 1) do={ :error ("Ambiguous management list: " . $listName) }
        :if ([:len $mgmtList] = 1) do={
            :local inc [:tostr [/interface list get $mgmtList include]]
            :local exc [:tostr [/interface list get $mgmtList exclude]]
            :if (([:len $inc] > 0) || ([:len $exc] > 0)) do={
                :error ("ABORT: inherited management list requires manual review: " . $listName)
            }
            :foreach m in=[/interface list member find where list=$listName] do={
                :set mgmtMembers [$append $mgmtMembers [/interface list member get $m interface]]
            }
        }
    }
    :put ("PROTECTED MANAGEMENT INTERFACES: " . $mgmtMembers)

    :local names [:toarray ""]
    :local pvids [:toarray ""]
    :local tags [:toarray ""]
    :local autos [:toarray ""]
    :local speeds [:toarray ""]
    :local mediaTypes [:toarray ""]
    :local stpCosts [:toarray ""]
    :local stpRoles [:toarray ""]
    :local stpEdges [:toarray ""]
    :local arpVlans [:toarray ""]
    :local universe ""
    :local oltPvids ""
    :local mgmtArpVlans ""
    :local accessPorts ""

    :foreach eth in=[/interface ethernet find] do={
        :local name [/interface ethernet get $eth name]
        :local comment [:tostr [/interface ethernet get $eth comment]]
        :local rest $comment
        :local pvid ""
        :local explicitPvid ""
        :local untagRequest ""
        :local mgmtVlans ""
        :local tagged ""
        :local auto ""
        :local speed "AUTO"
        :local media ""
        :local arpMode "AUTO"
        :local displayName ""
        :local tagReference ""
        :local recognized false
        :local role [$roleOf $comment $name]
        :local isOlt ($role = "OLT")
        :while ([:len $rest] > 0) do={
            :local cut [:find $rest "_"]
            :local token ""
            :if ([:typeof $cut] = "nil") do={
                :set token $rest
                :set rest ""
            } else={
                :set token [:pick $rest 0 $cut]
                :set rest [:pick $rest ($cut + 1) [:len $rest]]
            }
            :local colon [:find $token ":"]
            :local key $token
            :local val ""
            :if ([:typeof $colon] != "nil") do={
                :set key [:pick $token 0 $colon]
                :set val [:pick $token ($colon + 1) [:len $token]]
            } else={
                :foreach prefix in={"TAGS-";"TAG-";"PVID-";"MGMT-";"UNTAG-";"VLAN-";"SPEED-";"MEDIA-";"ARP-";"NAME-";"ROLE-"} do={
                    :if ([:pick $token 0 [:len $prefix]] = $prefix) do={
                        :set key [:pick $prefix 0 ([:len $prefix] - 1)]
                        :set val [:pick $token [:len $prefix] [:len $token]]
                    }
                }
            }
            :if (($key = "NAME") || ($key = "ROLE") || ($key = "OLT") || ($key = "DOWNLINK") || ($key = "UPLINK")) do={
                :set recognized true
            }
            :if ($key = "NAME") do={ :set displayName $val }
            :if ($key = "OLT") do={
                :set displayName $val
                :put ("LEGACY COMMENT " . $name . ": use NAME:" . $val . " instead of OLT:" . $val)
            }
            :if ($key = "ROLE") do={
                :if (($val != "OLT") && ($val != "UPLINK") && ($val != "DOWNLINK") && ($val != "NAS-LAN") && ($val != "NAS-WAN") && ($val != "MGMT")) do={
                    :error ("Unrecognized ROLE " . $val . " on " . $name)
                }
            }
            :if ($key = "ARP") do={
                :if ($val != "AUTO") do={
                    :error ("Unsupported ARP mode on " . $name . ": " . $val)
                }
                :set arpMode "AUTO"
            }
            :if ($key = "TAG") do={
                :local found [$expand $val]
                :if ([:len [:toarray $found]] != 1) do={
                    :error ("TAG must contain exactly one VLAN; use TAGS for lists on " . $name)
                }
                :set tagReference $found
                :set tagged [$append $tagged $found]
                :set recognized true
            }
            :if ($key = "UNTAG") do={
                :local requested [$expand $val]
                :if ([:len [:toarray $requested]] != 1) do={
                    :error ("UNTAG requires exactly one VLAN on " . $name)
                }
                :if (([:len $untagRequest] > 0) && ($untagRequest != $requested)) do={
                    :error ("Conflicting UNTAG values on " . $name)
                }
                :set untagRequest $requested
                :set recognized true
            }
            :if (($key = "TAGS") || ($key = "MGMT") || ($key = "VLAN")) do={
                :if ($val = "AUTO") do={
                    :if ($key != "VLAN") do={ :error ("AUTO invalid for " . $key . " on " . $name) }
                    :set auto "UPLINK"
                } else={
                    :local found [$expand $val]
                    :foreach vid in=[:toarray $found] do={
                        :if ($key = "MGMT") do={
                            :set mgmtVlans [$append $mgmtVlans $vid]
                            :set mgmtArpVlans [$append $mgmtArpVlans $vid]
                        } else={
                            :set tagged [$append $tagged $vid]
                        }
                    }
                }
                :set recognized true
            }
            :if ($key = "PVID") do={
                :local found [$expand $val]
                :if ([:len [:toarray $found]] != 1) do={ :error ("PVID must be one VLAN: " . $name) }
                :if (([:len $explicitPvid] > 0) && ($explicitPvid != $found)) do={
                    :error ("Conflicting PVID values on " . $name)
                }
                :set explicitPvid $found
                :set pvid $found
                :set recognized true
            }
            :if ($key = "NAS-LAN") do={
                :error ("NAS-LAN:<VLAN> is deprecated on " . $name . "; use NAME:NAS-LAN_TAGS:<VLANs>")
            }
            :if ($key = "SPEED") do={
                :if (($val != "AUTO") && ($val != "10G") && ($val != "1G")) do={
                    :error ("Invalid SPEED on " . $name)
                }
                :set speed $val
                :set recognized true
            }
            :if ($key = "MEDIA") do={
                :if (($val != "OPTICAL") && ($val != "DAC") && ($val != "COPPER")) do={
                    :error ("Invalid MEDIA on " . $name)
                }
                :set media $val
            }
        }
        :if ([:len $untagRequest] > 0) do={
            :if ([:typeof [:find ("," . $mgmtVlans . ",") ("," . $untagRequest . ",")]] = "nil") do={
                :error ("UNTAG:" . $untagRequest . " has no matching MGMT VLAN on " . $name)
            }
            :if ([:len $explicitPvid] = 0) do={
                :set pvid $untagRequest
                :put ("MGMT UNTAG SELECTED: " . $name . " pvid=" . $pvid)
            } else={
                :if ($explicitPvid != $untagRequest) do={
                    :put ("PVID PRIORITY: " . $name . " PVID=" . $explicitPvid . " overrides UNTAG=" . $untagRequest . "; management stays tagged")
                }
            }
        }
        :foreach mgmtVid in=[:toarray $mgmtVlans] do={
            :if ($mgmtVid != $pvid) do={
                :set tagged [$append $tagged $mgmtVid]
            } else={
                :put ("MGMT UNTAGGED THROUGH PVID: " . $name . " VLAN=" . $mgmtVid)
            }
        }
        :if (($comment ~ "^OLT_RESERVED") || ($comment ~ "^OTHER") || ($comment ~ "(^|_)NAME:OLT_RESERVED($|_)") || ($comment ~ "(^|_)NAME:OTHER($|_)")) do={
            :set recognized false
        }
        :if ($recognized) do={
            :if ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $name . ",")]] != "nil") do={
                :put ("PROTECTED MGMT-IF, no change: " . $name)
            } else={
                :if (([:len $pvid] > 0) && ([:typeof [:find ("," . $tagged . ",") ("," . $pvid . ",")]] != "nil")) do={
                    :error ("Tagged and PVID conflict on " . $name . ": " . $pvid)
                }
                :if (([:len $pvid] > 0) && ([:len $tagged] = 0) && ([:len $auto] = 0)) do={
                    :set accessPorts [$append $accessPorts $name]
                    :put ("ACCESS VLAN-UNTAGGED-ONLY: " . $name . " PVID=" . $pvid)
                }
                :set names ($names, $name)
                :set pvids ($pvids, $pvid)
                :set tags ($tags, $tagged)
                :set autos ($autos, $auto)
                :set speeds ($speeds, $speed)
                :set mediaTypes ($mediaTypes, $media)
                :local cost [$stpCostByName $name $comment]
                :local restriction "yes"
                :local edgeSetting "yes-discover"
                :if ($role = "UPLINK") do={
                    :set restriction "no"
                    :set edgeSetting "no"
                }
                :if (($role = "NAS-LAN") || ($role = "DOWNLINK")) do={
                    :set edgeSetting "no"
                }
                :set stpCosts ($stpCosts, $cost)
                :set stpRoles ($stpRoles, $restriction)
                :set stpEdges ($stpEdges, $edgeSetting)
                :local arpVlan ""
                :if ($isOlt) do={
                    :if ([:len $explicitPvid] > 0) do={
                        :set arpVlan $explicitPvid
                    } else={
                        :set arpVlan $tagReference
                    }
                    :if ([:len $arpVlan] = 0) do={
                        :put ("ARP:AUTO SKIP " . $name . " (" . $displayName . "): no PVID or single TAG reference")
                    }
                }
                :set arpVlans ($arpVlans, $arpVlan)
                :foreach id in=[:toarray $tagged] do={ :set universe [$append $universe $id] }
                :if ([:len $pvid] > 0) do={
                    :set universe [$append $universe $pvid]
                    :if ($isOlt) do={ :set oltPvids [$append $oltPvids $pvid] }
                }
            }
        }
    }

    :local n [:len $names]
    :if (([:len $pvids] != $n) || ([:len $tags] != $n) || ([:len $autos] != $n) || ([:len $speeds] != $n) || ([:len $mediaTypes] != $n) || ([:len $stpCosts] != $n) || ([:len $stpRoles] != $n) || ([:len $stpEdges] != $n) || ([:len $arpVlans] != $n)) do={
        :error "ABORT: Internal port metadata array length mismatch"
    }
    :if ($n = 0) do={ :error "No recognized interface comments on this switch" }
    :put ("MANAGED PORTS: " . $n . " VLAN UNIVERSE: " . $universe)
    :local actions [:toarray ""]
    :local actionIds [:toarray ""]
    :local actionValues [:toarray ""]
    :local actionsCount 0
    :if ($filtering != $wantFiltering) do={
        :put ("UPDATE BRIDGE VLAN-FILTERING " . $bridgeName . " " . $filtering . " -> " . $wantFiltering . " (apply last)")
        :set actions ($actions, "VLANFILTER")
        :set actionIds ($actionIds, $bridgeName)
        :set actionValues ($actionValues, [:tostr $wantFiltering])
        :set actionsCount ($actionsCount + 1)
    }
    :if ($igmpNow != $wantIgmp) do={
        :put ("UPDATE BRIDGE IGMP snooping " . $bridgeName . " " . $igmpNow . " -> " . $wantIgmp)
        :set actions ($actions, "IGMP")
        :set actionIds ($actionIds, $bridgeName)
        :set actionValues ($actionValues, [:tostr $wantIgmp])
        :set actionsCount ($actionsCount + 1)
    }
    :if ($swReady && ($currentPriority != $desiredPriority)) do={
        :put ("UPDATE BRIDGE PRIORITY " . $currentPriority . " -> " . $desiredPriority)
        :set actions ($actions, "BRIDGEPRIORITY")
        :set actionIds ($actionIds, $bridgeName)
        :set actionValues ($actionValues, [:tostr $desiredPriority])
        :set actionsCount ($actionsCount + 1)
    }
    :if ($swAuto && $swReady && ($bridgeComment != $proposedBridgeComment)) do={
        :put ("UPDATE BRIDGE COMMENT " . $bridgeComment . " -> " . $proposedBridgeComment)
        :set actions ($actions, "BRIDGECOMMENT")
        :set actionIds ($actionIds, $bridgeName)
        :set actionValues ($actionValues, $proposedBridgeComment)
        :set actionsCount ($actionsCount + 1)
    }


    :local uplinkPorts ""
    :local oltFacingPorts ""
    :foreach uplinkRow in=[/interface ethernet find] do={
        :local uplinkComment [:tostr [/interface ethernet get $uplinkRow comment]]
        :local physicalName [/interface ethernet get $uplinkRow name]
        :if ([$roleOf $uplinkComment $physicalName] = "UPLINK") do={
            :set uplinkPorts [$append $uplinkPorts $physicalName]
        }
        :if (([$roleOf $uplinkComment $physicalName] = "OLT") || ([$roleOf $uplinkComment $physicalName] = "DOWNLINK")) do={
            :set oltFacingPorts [$append $oltFacingPorts $physicalName]
        }
    }
    :local scanVlans [:toarray ""]
    :local scanKinds [:toarray ""]
    :local uniqueScan ""
    :for index from=0 to=($n - 1) do={
        :local oltVid [:pick $arpVlans $index]
        :if ([:len $oltVid] > 0) do={
            :if ([:typeof [:find ("," . $uniqueScan . ",") ("," . $oltVid . ",")]] = "nil") do={
                :set uniqueScan [$append $uniqueScan $oltVid]
                :set scanVlans ($scanVlans, $oltVid)
                :set scanKinds ($scanKinds, ("OLT PVID/TAG from " . [:pick $names $index]))
            }
        }
    }
    :foreach mgmtVid in=[:toarray $mgmtArpVlans] do={
        :if ([:typeof [:find ("," . $uniqueScan . ",") ("," . $mgmtVid . ",")]] = "nil") do={
            :set uniqueScan [$append $uniqueScan $mgmtVid]
            :set scanVlans ($scanVlans, $mgmtVid)
            :set scanKinds ($scanKinds, "MGMT")
        } else={
            :put ("ARP:AUTO MGMT VLAN " . $mgmtVid . " included in existing VLAN scan")
        }
    }
    :local scanCount [:len $scanVlans]
    :if ($scanCount > 0) do={
        :for scanIndex from=0 to=($scanCount - 1) do={
            :local scanVlan [:pick $scanVlans $scanIndex]
            :local scanKind [:pick $scanKinds $scanIndex]
            :put ("ARP:AUTO SCAN " . $scanKind . " VLAN " . $scanVlan)
            :local seen 0
            :local correlated 0
            :foreach learned in=[/interface bridge host find where bridge=$bridgeName] do={
                :local vid [:tostr [/interface bridge host get $learned vid]]
                :if ($vid = $scanVlan) do={
                    :local mac [:tostr [/interface bridge host get $learned mac-address]]
                    :local onIf [:tostr [/interface bridge host get $learned on-interface]]
                    :if (($mac ~ "^C0:FF:EE") || ($mac ~ "^C0:FE:EE")) do={
                        :local allowedSource ([:typeof [:find ("," . $uplinkPorts . ",") ("," . $onIf . ",")]] != "nil")
                        :local isMgmtScan ([:typeof [:find ("," . $mgmtArpVlans . ",") ("," . $scanVlan . ",")]] != "nil")
                        :if ($isMgmtScan) do={
                            :if ([:typeof [:find ("," . $oltFacingPorts . ",") ("," . $onIf . ",")]] != "nil") do={
                                :set allowedSource true
                            }
                        }
                        :if ($allowedSource) do={
                            :set seen ($seen + 1)
                            :if ($seen > 128) do={
                                :error ("ARP:AUTO too many MAC candidates on VLAN " . $scanVlan)
                            }
                            :local pairFound false
                            :foreach neighbor in=[/ip arp find where mac-address=$mac] do={
                                :local ip [:tostr [/ip arp get $neighbor address]]
                                :local arpIf [:tostr [/ip arp get $neighbor interface]]
                                :local vlanIf [/interface vlan find where name=$arpIf]
                                :if ([:len $vlanIf] = 1) do={
                                    :local arpVid [:tostr [/interface vlan get $vlanIf vlan-id]]
                                    :local parent [/interface vlan get $vlanIf interface]
                                    :if (($arpVid = $scanVlan) && ($parent = $bridgeName) && ([:len $ip] > 0)) do={
                                        :set correlated ($correlated + 1)
                                        :set pairFound true
                                        :put ("ARP REVIEW: " . $scanKind . " VLAN=" . $scanVlan . " IP=" . $ip . " MAC=" . $mac . " interface=" . $arpIf)
                                    }
                                }
                            }
                            :if (!$pairFound) do={
                                :put ("MAC ONLY: " . $mac . " via " . $onIf . " VLAN=" . $scanVlan . " (no validated IP mapping)")
                            }
                        }
                    }
                }
            }
            :put ("ARP:AUTO RESULT " . $scanKind . " VLAN " . $scanVlan . ": MAC candidates=" . $seen . " local IP correlations=" . $correlated)
        }
    } else={
        :put "ARP:AUTO: no PVID/TAG or MGMT VLAN references found"
    }
    :put "ARP:AUTO is read-only: no static ARP writes without verified L3 IP-MAC mappings."

    :for i from=0 to=($n - 1) do={
        :local name [:pick $names $i]
        :local pvid [:pick $pvids $i]
        :local accessOnly ([:typeof [:find ("," . $accessPorts . ",") ("," . $name . ",")]] != "nil")
        :local tagHere [:pick $tags $i]
        :local autoHere [:pick $autos $i]
        :local frameDesired ""
        :if ($accessOnly) do={
            :set frameDesired "admit-only-untagged-and-priority-tagged"
        } else={
            :if (([:len $tagHere] > 0) || ([:len $autoHere] > 0)) do={
                :if ([:len $pvid] > 0) do={
                    :set frameDesired "admit-all"
                } else={
                    :set frameDesired "admit-only-vlan-tagged"
                }
            }
        }
        :local wantedCost [:pick $stpCosts $i]
        :local wantedRole [:pick $stpRoles $i]
        :local wantedEdge [:pick $stpEdges $i]
        :if ($accessOnly) do={
            :foreach row in=[/interface bridge vlan find where bridge=$bridgeName] do={
                :if (![/interface bridge vlan get $row dynamic]) do={
                    :local staticTag [:tostr [/interface bridge vlan get $row tagged]]
                    :if ([:typeof [:find ("," . $staticTag . ",") ("," . $name . ",")]] != "nil") do={
                        :error ("ABORT: access-only " . $name . " remains statically TAGGED on VLAN " . [/interface bridge vlan get $row vlan-ids] . "; review VLAN table")
                    }
                    :local staticUntag [:tostr [/interface bridge vlan get $row untagged]]
                    :if ([:typeof [:find ("," . $staticUntag . ",") ("," . $name . ",")]] != "nil") do={
                        :local assigned [$expand [:tostr [/interface bridge vlan get $row vlan-ids]]]
                        :if (($assigned != $pvid)) do={
                            :error ("ABORT: access-only " . $name . " has untagged VLAN " . $assigned . " conflicting with PVID " . $pvid)
                        }
                    }
                }
            }
        }
        :local existing [/interface bridge port find where interface=$name]
        :if ([:len $existing] > 1) do={ :error ("Duplicate bridge ports: " . $name) }
        :if ([:len $existing] = 1) do={
            :local onBridge [/interface bridge port get $existing bridge]
            :if ($onBridge != $bridgeName) do={
                :error ("ABORT: " . $name . " already belongs to bridge " . $onBridge)
            }
            :local existingCost [/interface bridge port get $existing path-cost]
            :local existingRole [/interface bridge port get $existing restricted-role]
            :local existingEdge [:tostr [/interface bridge port get $existing edge]]
            :local needStp false
            :if ($existingEdge != $wantedEdge) do={ :set needStp true }
            :if ([:tostr $existingCost] != [:tostr $wantedCost]) do={
                :set needStp true
            }
            :if ($wantedRole = "yes") do={
                :if (!$existingRole) do={ :set needStp true }
            }
            :if ($wantedRole = "no") do={
                :if ($existingRole) do={ :set needStp true }
            }
            :if ($needStp) do={
                :put ("UPDATE RSTP " . $name . " cost=" . $wantedCost . " restricted-role=" . $wantedRole . " edge=" . $wantedEdge)
                :set actions ($actions, "RSTP")
                :set actionIds ($actionIds, $name)
                :set actionValues ($actionValues, ([:tostr $wantedCost] . ":" . $wantedRole . ":" . $wantedEdge))
                :set actionsCount ($actionsCount + 1)
            }
            :if (!$accessOnly && ([:len $frameDesired] > 0)) do={
                :local currentFrame [:tostr [/interface bridge port get $existing frame-types]]
                :local currentIngress [/interface bridge port get $existing ingress-filtering]
                :if (($currentFrame != $frameDesired) || (!$currentIngress)) do={
                    :put ("SET FRAMES " . $name . " " . $frameDesired . " ingress-filtering=yes")
                    :set actions ($actions, "FRAMES")
                    :set actionIds ($actionIds, $name)
                    :set actionValues ($actionValues, $frameDesired)
                    :set actionsCount ($actionsCount + 1)
                }
            }
            :if ($accessOnly) do={
                :local curPvid [:tostr [/interface bridge port get $existing pvid]]
                :local curFrames [:tostr [/interface bridge port get $existing frame-types]]
                :local curIngress [/interface bridge port get $existing ingress-filtering]
                :if (($curPvid != $pvid) || ($curFrames != "admit-only-untagged-and-priority-tagged") || (!$curIngress)) do={
                    :put ("SET ACCESS VLAN-UNTAGGED-ONLY " . $name . " pvid=" . $pvid . " frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes")
                    :set actions ($actions, "ACCESS")
                    :set actionIds ($actionIds, $name)
                    :set actionValues ($actionValues, $pvid)
                    :set actionsCount ($actionsCount + 1)
                }
            } else={
                :if ([:len $pvid] > 0) do={
                    :if ([:tostr [/interface bridge port get $existing pvid]] != $pvid) do={
                        :put ("UPDATE PVID " . $name . " -> " . $pvid)
                        :set actions ($actions, "PVID")
                        :set actionIds ($actionIds, $name)
                        :set actionValues ($actionValues, $pvid)
                        :set actionsCount ($actionsCount + 1)
                    }
                }
            }
        } else={
            :put ("ADD BRIDGE PORT " . $name . " to " . $bridgeName . " pvid=" . $pvid)
            :local action "PORT"
            :if ($accessOnly) do={ :set action "PORTACCESS" }
            :set actions ($actions, $action)
            :set actionIds ($actionIds, $name)
            :set actionValues ($actionValues, $pvid)
            :set actionsCount ($actionsCount + 1)
            :if (!$accessOnly && ([:len $frameDesired] > 0)) do={
                :put ("SET FRAMES AFTER ADD " . $name . " " . $frameDesired)
                :set actions ($actions, "FRAMES")
                :set actionIds ($actionIds, $name)
                :set actionValues ($actionValues, $frameDesired)
                :set actionsCount ($actionsCount + 1)
            }
        }
    }

    :foreach bp in=[/interface bridge port find where bridge=$bridgeName] do={
        :local pname [/interface bridge port get $bp interface]
        :local isMgmt ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $pname . ",")]] != "nil")
        :local managed false
        :foreach known in=$names do={
            :if ($known = $pname) do={ :set managed true }
        }
        :if ($isMgmt) do={
            :local role [/interface bridge port get $bp restricted-role]
            :if (!$role) do={
                :put ("WARNING: MGMT-IF " . $pname . " remains root-port eligible (protected, not modified)")
            }
        } else={
            :if (!$managed) do={
                :local desiredCost 20000
                :local desiredRole "yes"
                :local desiredEdge "yes-discover"
                :local phy [/interface ethernet find where name=$pname]
                :if ([:len $phy] = 1) do={
                    :local pc [/interface ethernet get $phy comment]
                    :set desiredCost [$stpCostByName $pname $pc]
                    :local r [$roleOf $pc $pname]
                    :if ($r = "UPLINK") do={
                        :set desiredRole "no"
                        :set desiredEdge "no"
                    }
                    :if (($r = "NAS-LAN") || ($r = "DOWNLINK")) do={
                        :set desiredEdge "no"
                    }
                }
                :local nowCost [/interface bridge port get $bp path-cost]
                :local nowRole [/interface bridge port get $bp restricted-role]
                :local nowEdge [:tostr [/interface bridge port get $bp edge]]
                :local requiresChange ([:tostr $nowCost] != [:tostr $desiredCost])
                :if ($nowEdge != $desiredEdge) do={ :set requiresChange true }
                :if ($desiredRole = "yes") do={
                    :if (!$nowRole) do={ :set requiresChange true }
                } else={
                    :if ($nowRole) do={ :set requiresChange true }
                }
                :if ($requiresChange) do={
                    :put ("UPDATE RSTP UNANNOTATED " . $pname . " cost=" . $desiredCost . " restricted-role=" . $desiredRole . " edge=" . $desiredEdge)
                    :set actions ($actions, "RSTP")
                    :set actionIds ($actionIds, $pname)
                    :set actionValues ($actionValues, ([:tostr $desiredCost] . ":" . $desiredRole . ":" . $desiredEdge))
                    :set actionsCount ($actionsCount + 1)
                }
            }
        }
    }

    :foreach vid in=[:toarray $universe] do={
        :local want ""
        :for i from=0 to=($n - 1) do={
            :local name [:pick $names $i]
            :local tagsThis [:pick $tags $i]
            :local pvidThis [:pick $pvids $i]
            :local autoThis [:pick $autos $i]
            :local explicitly ([:typeof [:find ("," . $tagsThis . ",") ("," . $vid . ",")]] != "nil")
            :local autoInclude false
            :if ($autoThis = "UPLINK") do={
                :if ([:typeof [:find ("," . $oltPvids . ",") ("," . $vid . ",")]] = "nil") do={
                    :set autoInclude true
                }
            }
            :if ($explicitly || $autoInclude) do={
                :if ($pvidThis = $vid) do={ :error ("Port " . $name . " is both tagged and PVID VLAN " . $vid) }
                :set want [$append $want $name]
            }
        }
        :if ([:len $want] > 0) do={
            :local matched [:toarray ""]
            :foreach row in=[/interface bridge vlan find where bridge=$bridgeName] do={
                :if (![/interface bridge vlan get $row dynamic]) do={
                    :local vlanSet [$expand [:tostr [/interface bridge vlan get $row vlan-ids]]]
                    :if ([:typeof [:find ("," . $vlanSet . ",") ("," . $vid . ",")]] != "nil") do={
                        :set matched ($matched, $row)
                    }
                }
            }
            :if ([:len $matched] > 1) do={ :error ("Multiple static VLAN entries for " . $vid) }
            :if ([:len $matched] = 0) do={
                :put ("ADD TAGGED VLAN " . $vid . " -> " . $want)
                :set actions ($actions, "VLANADD")
                :set actionIds ($actionIds, $vid)
                :set actionValues ($actionValues, $want)
                :set actionsCount ($actionsCount + 1)
            } else={
                :local row [:pick $matched 0]
                :if ([/interface bridge vlan get $row disabled]) do={
                    :error ("Disabled static VLAN entry requires review: " . $vid)
                }
                :local oldTag [:tostr [/interface bridge vlan get $row tagged]]
                :local oldUntag [:tostr [/interface bridge vlan get $row untagged]]
                :local newTag $oldTag
                :foreach name in=[:toarray $want] do={
                    :if ([:typeof [:find ("," . $oldUntag . ",") ("," . $name . ",")]] != "nil") do={
                        :error ("Tagged/untagged conflict on VLAN " . $vid . ": " . $name)
                    }
                    :set newTag [$append $newTag $name]
                }
                :if ($newTag != $oldTag) do={
                    :local rowSet [$expand [:tostr [/interface bridge vlan get $row vlan-ids]]]
                    :if ([:len [:toarray $rowSet]] != 1) do={
                        :error ("Existing multi-VLAN row for VLAN " . $vid . " requires manual split")
                    }
                    :put ("EXTEND TAGGED VLAN " . $vid . " -> " . $newTag)
                    :set actions ($actions, "VLANSET")
                    :set actionIds ($actionIds, $row)
                    :set actionValues ($actionValues, $newTag)
                    :set actionsCount ($actionsCount + 1)
                }
            }
        }
    }

    :for i from=0 to=($n - 1) do={
        :local speed [:pick $speeds $i]
        :local media [:pick $mediaTypes $i]
        :local name [:pick $names $i]
        :if ($speed = "AUTO") do={
            :local eth [/interface ethernet find where name=$name]
            :if (![/interface ethernet get $eth auto-negotiation]) do={
                :put ("SPEED AUTO " . $name . ": enable auto-negotiation")
                :set actions ($actions, "SPEEDAUTO")
                :set actionIds ($actionIds, $name)
                :set actionValues ($actionValues, "")
                :set actionsCount ($actionsCount + 1)
            }
        }
        :if (($speed = "1G") || ($speed = "10G")) do={
            :local mode ""
            :if ($media = "OPTICAL") do={
                :if ($speed = "1G") do={ :set mode "1G-baseX" } else={ :set mode "10G-baseSR-LR" }
            }
            :if ($media = "DAC") do={
                :if ($speed = "1G") do={ :set mode "1G-baseT-full" } else={ :set mode "10G-baseCR" }
            }
            :if ($media = "COPPER") do={
                :if ($speed = "1G") do={ :set mode "1G-baseT-full" } else={ :set mode "10G-baseT" }
            }
            :if ($mode = "") do={
                :put ("SPEED REVIEW: " . $name . " requires MEDIA:OPTICAL, MEDIA:DAC or MEDIA:COPPER")
                :if ($apply) do={
                    :error ("SPEED:" . $speed . " needs explicit MEDIA on " . $name)
                }
            }
            :if ([:len $mode] > 0) do={
                :local eth [/interface ethernet find where name=$name]
                :local actualSpeed [:tostr [/interface ethernet get $eth speed]]
                :local negotiation [/interface ethernet get $eth auto-negotiation]
                :if (($actualSpeed != $mode) || ($negotiation)) do={
                    :put ("SPEED " . $name . ": auto-negotiation=no speed=" . $mode)
                    :set actions ($actions, "SPEED")
                    :set actionIds ($actionIds, $name)
                    :set actionValues ($actionValues, $mode)
                    :set actionsCount ($actionsCount + 1)
                }
            }
        }
    }
    :foreach phys in=[/interface ethernet find] do={
        :local pname [/interface ethernet get $phys name]
        :local pc [:tostr [/interface ethernet get $phys comment]]
        :local isProtected ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $pname . ",")]] != "nil")
        :if (($pc ~ "^MGMT") || ($pc ~ "^Management") || ([$roleOf $pc $pname] = "MGMT") || ($pname ~ "^MGMT") || ($pname ~ "^Management")) do={
            :set isProtected true
        }
        :local known false
        :foreach managedName in=$names do={
            :if ($managedName = $pname) do={ :set known true }
        }
        :local explicitDisable (($pc ~ "^OLT_RESERVED") || ($pc ~ "^OTHER") || ($pc ~ "(^|_)NAME:OLT_RESERVED($|_)") || ($pc ~ "(^|_)NAME:OTHER($|_)"))
        :local hasBridge ([:len [/interface bridge port find where interface=$pname]] > 0)
        :local hasIP ([:len [/ip address find where interface=$pname and disabled=no]] > 0)
        :local isRunning [/interface ethernet get $phys running]
        :if (!$known && !$isProtected) do={
            :if (!$explicitDisable && ($hasBridge || $hasIP || $isRunning)) do={
                :put ("SKIP UNCLASSIFIED ACTIVE/CONFIGURED: " . $pname)
            } else={
                :if (![/interface ethernet get $phys disabled]) do={
                    :put ("DISABLE UNUSED: " . $pname)
                    :set actions ($actions, "DISABLE")
                    :set actionIds ($actionIds, $pname)
                    :set actionValues ($actionValues, "yes")
                    :set actionsCount ($actionsCount + 1)
                }
            }
        }
    }
    :local loopChanges 0
    :foreach etherId in=[/interface ethernet find] do={
        :local etherName [/interface ethernet get $etherId name]
        :local state [:tostr [/interface ethernet get $etherId loop-protect]]
        :local isMgmtPort ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $etherName . ",")]] != "nil")
        :if (($state != "on") && !$isMgmtPort) do={
            :put ("ENABLE LOOP-PROTECT " . $etherName . " (current=" . $state . ")")
            :set actions ($actions, "LOOPPROTECT")
            :set actionIds ($actionIds, $etherName)
            :set actionValues ($actionValues, "on")
            :set actionsCount ($actionsCount + 1)
            :set loopChanges ($loopChanges + 1)
        }
    }
    :put ("LOOP-PROTECT: " . $loopChanges . " physical Ethernet interfaces need enabling")
    :put "========== ONLY PROPOSED CHANGES ABOVE =========="
    :put ("PLANNED CHANGES: " . $actionsCount)
    :if (!$apply) do={ :put "PREVIEW ONLY: NO CHANGES APPLIED"; :return }
    :if ($actionsCount = 0) do={ :put "ALREADY IN SYNC"; :return }

    :local ownsSafe false
    :onerror safetyError in={
        :set ownsSafe [/safe-mode get current]
    } do={ :error ("ABORT: cannot inspect Safe Mode: " . $safetyError) }
    :if (!$ownsSafe) do={
        :error "ABORT: apply requires terminal-owned SAFE MODE (Ctrl+X)"
    }

    :local sessions [/user active find]
    :if ([:len $sessions] != 1) do={
        :error "ABORT: one active session is required to identify the invoking management path"
    }
    :local client [:tostr [/user active get [:pick $sessions 0] address]]
    :if (($client ~ "[A-Fa-f]") || ([:typeof [:find $client ":"]] != "nil")) do={
        :error "ABORT: management path currently requires IPv4 SSH/WinBox access"
    }
    :local clientIp [:toip $client]
    :if ([:typeof $clientIp] != "ip") do={ :error "ABORT: active management session is not IPv4" }
    :local trusted false
    :local matchingList ""
    :foreach addrRow in=[/ip firewall address-list find where ($clientIp in address)] do={
        :local listName [/ip firewall address-list get $addrRow list]
        :if (($listName = "MGMT") || ($listName = "REMOTE-MGMT") || ($listName = "MANAGEMENT") || ($listName = "REMOTE-MANAGEMENT") || ($listName = "REMOTE_MANAGEMENT")) do={
            :set trusted true
            :set matchingList $listName
        }
    }
    :if (!$trusted) do={
        :error ("ABORT: active client " . $client . " not in a recognized management address list")
    }
    :put ("MANAGEMENT SESSION: " . $client . " recognized by " . $matchingList)

    :local routes [/ip route find where dst-address="0.0.0.0/0" and active]
    :local gateway ""
    :foreach routeId in=$routes do={
        :if ([/ip route get $routeId routing-table] = "main") do={
            :if ([:len $gateway] > 0) do={ :error "ABORT: multiple main default gateways" }
            :set gateway [:tostr [/ip route get $routeId gateway]]
        }
    }
    :if (($gateway = "") || ([:typeof [:find $gateway ","]] != "nil") || ([:typeof [:find $gateway "%"]] != "nil")) do={
        :error "ABORT: gateway is absent/ambiguous; cannot establish L2 baseline"
    }

    :local firstPing [/ping address=$gateway count=3]
    :local arpEntries [/ip arp find where address=$gateway]
    :if ([:len $arpEntries] != 1) do={ :error "ABORT: no unique gateway ARP entry" }
    :local arpEntry [:pick $arpEntries 0]
    :local firstMac [:tostr [/ip arp get $arpEntry mac-address]]
    :local firstIf [:tostr [/ip arp get $arpEntry interface]]
    :if ([:len $firstMac] != 17) do={ :error "ABORT: gateway ARP MAC unresolved" }

    :local protectedPort ""
    :local clientMac ""
    :local neighbor [/ip arp find where address=$client]
    :if ([:len $neighbor] = 1) do={
        :set clientMac [:tostr [/ip arp get [:pick $neighbor 0] mac-address]]
    }
    :local pathMac $firstMac
    :if ([:len $clientMac] = 17) do={ :set pathMac $clientMac }
    :foreach host in=[/interface bridge host find where bridge=$bridgeName] do={
        :if ([:tostr [/interface bridge host get $host mac-address]] = $pathMac) do={
            :local foundPort [:tostr [/interface bridge host get $host on-interface]]
            :if (($protectedPort != "") && ($protectedPort != $foundPort)) do={
                :error "ABORT: multiple possible management ingress ports"
            }
            :set protectedPort $foundPort
        }
    }
    :if (($protectedPort = "") && ([:len [/interface ethernet find where name=$firstIf]] = 1)) do={
        :set protectedPort $firstIf
    }
    :if ($protectedPort = "") do={
        :error "ABORT: physical management path cannot be identified confidently"
    }
    :for idx from=0 to=($actionsCount - 1) do={
        :local target [:tostr [:pick $actionIds $idx]]
        :local val [:tostr [:pick $actionValues $idx]]
        :if (($target = $protectedPort) || ([:typeof [:find ("," . $val . ",") ("," . $protectedPort . ",")]] != "nil")) do={
            :error ("ABORT: planned action touches management path " . $protectedPort)
        }
    }
    :put ("PROTECTED MANAGEMENT PORT: " . $protectedPort . " session=" . $client)
    :put ("GATEWAY BASELINE: " . $gateway . " MAC=" . $firstMac . " via=" . $firstIf . " pingReplies=" . $firstPing)
    :if ($wantFiltering && !$filtering) do={
        :local mgmtSafe false
        :foreach v in=[/interface vlan find where interface=$bridgeName] do={
            :local vid [:tostr [/interface vlan get $v vlan-id]]
            :local vn [/interface vlan get $v name]
            :if ([:len [/ip address find where interface=$vn and disabled=no]] > 0) do={
                :local cpu false
                :local path false
                :foreach vr in=[/interface bridge vlan find where bridge=$bridgeName] do={
                    :if (![/interface bridge vlan get $vr disabled]) do={
                        :local ids [$expand [:tostr [/interface bridge vlan get $vr vlan-ids]]]
                        :if ([:typeof [:find ("," . $ids . ",") ("," . $vid . ",")]] != "nil") do={
                            :local tagged [:tostr [/interface bridge vlan get $vr tagged]]
                            :if ([:typeof [:find ("," . $tagged . ",") ("," . $bridgeName . ",")]] != "nil") do={ :set cpu true }
                            :if ([:typeof [:find ("," . $tagged . ",") ("," . $protectedPort . ",")]] != "nil") do={ :set path true }
                        }
                    }
                }
                :local bp [/interface bridge port find where bridge=$bridgeName and interface=$protectedPort]
                :if ([:len $bp] = 1) do={
                    :if (([:tostr [/interface bridge port get $bp pvid]] = $vid) && ([:tostr [/interface bridge port get $bp frame-types]] != "admit-only-vlan-tagged")) do={ :set path true }
                }
                :if ($cpu && $path) do={ :set mgmtSafe true }
            }
        }
        :if (!$mgmtSafe) do={
            :error "ABORT: enabling VLAN filtering requires an active VLAN-on-bridge management IP and same-VLAN bridge CPU plus protected physical path"
        }
    }

    :local decision false
    :local pending true
    :while ($pending) do={
        :put "Press Y=YES, N=NO, W=WAIT another 60 seconds (timeout cancels)."
        :local key 0
        :onerror keyError in={ :set key [/terminal inkey timeout=1m] } do={
            :put ("Timed out or terminal error: " . $keyError)
        }
        :if (($key = 87) || ($key = 119)) do={
            :put "WAIT selected: extending confirmation by 60 seconds"
        } else={
            :set pending false
            :if (($key = 89) || ($key = 121)) do={ :set decision true }
        }
    }
    :if (!$decision) do={ :error "CANCELLED: no YES approval" }

    :local password ""
    :global ros7SwitchBackupPassword
    :if ([:typeof $ros7SwitchBackupPassword] = "str") do={ :set password $ros7SwitchBackupPassword }
    :if ([:len $password] < 12) do={
        :error "ABORT: set global ros7SwitchBackupPassword (12+ chars) for encrypted binary backup"
    }
    :local stamp [:tostr [/system clock get time]]
    :local fileDate [:tostr [/system clock get date]]
    :local base ("ros7UpdateSwitchConfig_" . $fileDate . "_" . $stamp)
    :local safeBase ""
    :for i from=0 to=([:len $base] - 1) do={
        :local ch [:pick $base $i ($i + 1)]
        :if ($ch ~ "^[A-Za-z0-9_-]$") do={ :set safeBase ($safeBase . $ch) } else={
            :set safeBase ($safeBase . "_")
        }
    }
    /system backup save name=$safeBase encryption=aes-sha256 password=$password
    /export file=$safeBase
    :delay 2s
    :local bin [/file find where name=($safeBase . ".backup")]
    :local rsc [/file find where name=($safeBase . ".rsc")]
    :if (([:len $bin] != 1) || ([:len $rsc] != 1)) do={ :error "Backup pair not created" }
    :if (([/file get $bin size] = 0) || ([/file get $rsc size] = 0)) do={ :error "Backup pair empty" }
    :put ("BACKUP PAIR SAVED: " . $safeBase)

    :local appliedOK true
    :local applyReason ""
    :onerror applyFailure in={
        :for i from=0 to=($actionsCount - 1) do={
        :local action [:pick $actions $i]
        :local name [:pick $actionIds $i]
        :local value [:pick $actionValues $i]
        :if ($action = "IGMP") do={
            /interface bridge set $bridgeId igmp-snooping=($value = "true")
        }
        :if ($action = "BRIDGEPRIORITY") do={
            /interface bridge set $bridgeId priority=[:tonum $value]
        }
        :if ($action = "BRIDGECOMMENT") do={
            /interface bridge set $bridgeId comment=$value
        }
        :if (($action = "PORT") || ($action = "PORTACCESS")) do={
            :local cost 20000
            :local restrictedBoolean true
            :local edgeSetting "yes-discover"
            :local ethId [/interface ethernet find where name=$name]
            :if ([:len $ethId] = 1) do={
                :local c [/interface ethernet get $ethId comment]
                :set cost [$stpCostByName $name $c]
                :local r [$roleOf $c $name]
                :if ($r = "UPLINK") do={
                    :set restrictedBoolean false
                    :set edgeSetting "no"
                }
                :if (($r = "NAS-LAN") || ($r = "DOWNLINK")) do={
                    :set edgeSetting "no"
                }
            }
            :if ($action = "PORTACCESS") do={
                :if ([:len $value] = 0) do={
                    :error ("ACCESS port missing PVID: " . $name)
                }
                /interface bridge port add bridge=$bridgeName interface=$name pvid=[:tonum $value] path-cost=$cost restricted-role=$restrictedBoolean edge=$edgeSetting frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
            } else={
                :if ($value = "") do={
                    /interface bridge port add bridge=$bridgeName interface=$name path-cost=$cost restricted-role=$restrictedBoolean edge=$edgeSetting
                } else={
                    /interface bridge port add bridge=$bridgeName interface=$name pvid=[:tonum $value] path-cost=$cost restricted-role=$restrictedBoolean edge=$edgeSetting
                }
            }
        }
        :if ($action = "RSTP") do={
            :local firstColon [:find $value ":"]
            :if ([:typeof $firstColon] = "nil") do={ :error "Invalid RSTP planned action" }
            :local secondColon [:find $value ":" ($firstColon + 1)]
            :if ([:typeof $secondColon] = "nil") do={ :error "Missing RSTP edge setting" }
            :local cost [:tonum [:pick $value 0 $firstColon]]
            :local restriction [:pick $value ($firstColon + 1) $secondColon]
            :local edgeSetting [:pick $value ($secondColon + 1) [:len $value]]
            :if ((($restriction != "yes") && ($restriction != "no")) || (($edgeSetting != "yes") && ($edgeSetting != "no") && ($edgeSetting != "yes-discover"))) do={
                :error ("Invalid RSTP state: " . $value)
            }
            :local bridgePort [/interface bridge port find where interface=$name and bridge=$bridgeName]
            :if ([:len $bridgePort] != 1) do={
                :error ("Missing bridge port " . $name)
            }
            /interface bridge port set $bridgePort path-cost=$cost restricted-role=($restriction = "yes") edge=$edgeSetting
        }
        :if ($action = "FRAMES") do={
            :local bp [/interface bridge port find where interface=$name and bridge=$bridgeName]
            :if ([:len $bp] != 1) do={ :error ("FRAMES target missing: " . $name) }
            /interface bridge port set $bp frame-types=$value ingress-filtering=yes
        }
        :if ($action = "ACCESS") do={
            :local bridgePort [/interface bridge port find where interface=$name and bridge=$bridgeName]
            :if ([:len $bridgePort] != 1) do={
                :error ("Access bridge port missing: " . $name)
            }
            /interface bridge port set $bridgePort pvid=[:tonum $value] frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
        }
        :if ($action = "PVID") do={
            /interface bridge port set [find where interface=$name and bridge=$bridgeName] pvid=[:tonum $value]
        }
        :if ($action = "VLANADD") do={
            /interface bridge vlan add bridge=$bridgeName vlan-ids=[:tonum $name] tagged=$value
        }
        :if ($action = "VLANSET") do={
            /interface bridge vlan set $name tagged=$value
        }
        :if ($action = "DISABLE") do={
            :local disableId [/interface ethernet find where name=$name]
            :if ([:len $disableId] != 1) do={ :error ("Disable target missing: " . $name) }
            /interface ethernet set $disableId disabled=yes
        }
        :if ($action = "LOOPPROTECT") do={
            :local etherId [/interface ethernet find where name=$name]
            :if ([:len $etherId] != 1) do={
                :error ("LOOPPROTECT interface not found uniquely: " . $name)
            }
            /interface ethernet set $etherId loop-protect=on
        }
        :if ($action = "SPEEDAUTO") do={
            /interface ethernet set [find where name=$name] auto-negotiation=yes
        }
        :if ($action = "SPEED") do={
            /interface ethernet set [find where name=$name] auto-negotiation=no speed=$value
        }
        :if ($action != "VLANFILTER") do={ :put ("DONE: " . $action . " " . $name) }
        }
        :if ($filtering != $wantFiltering) do={
            /interface bridge set $bridgeId vlan-filtering=$wantFiltering
            :put ("DONE: VLAN-FILTERING " . $bridgeName . "=" . $wantFiltering)
            :delay 3s
        }
        :local afterPing [/ping address=$gateway count=3]
        :local afterRows [/ip arp find where address=$gateway]
        :if ([:len $afterRows] != 1) do={ :error "Gateway ARP vanished" }
        :local afterRow [:pick $afterRows 0]
        :local afterMac [:tostr [/ip arp get $afterRow mac-address]]
        :local afterIf [:tostr [/ip arp get $afterRow interface]]
        :local afterStatus [:tostr [/ip arp get $afterRow status]]
        :if (($afterMac != $firstMac) || ($afterIf != $firstIf)) do={
            :error "Gateway ARP MAC/interface changed"
        }
        :if (($afterStatus = "failed") || ($afterStatus = "incomplete")) do={
            :error "Gateway ARP is incomplete"
        }
        :if (($firstPing > 0) && ($afterPing = 0)) do={
            :error "Gateway ICMP was reachable before but not after"
        }
        :put ("GATEWAY VERIFIED: " . $gateway . " MAC=" . $afterMac . " via=" . $afterIf)
        :if ($swAuto && $swReady) do={
            :local nowRoot ""
            :onerror err in={
                /interface bridge monitor $bridgeName once do={ :set nowRoot [:tostr $"root-port"] }
            } do={ :error "SW:AUTO post-apply monitor failed" }
            :if ($nowRoot != $autoRootPort) do={ :error ("SW:AUTO root-port changed from " . $autoRootPort . " to " . $nowRoot) }
        }
    } do={
        :set appliedOK false
        :set applyReason $applyFailure
    }
    :if (!$appliedOK) do={
        :log error ("ros7UpdateSwitchConfig: " . $applyReason)
        :put ("APPLY/HEALTH CHECK FAILED: " . $applyReason)
        :onerror unrollFailure in={
            /safe-mode unroll
        } do={
            :error ("SAFE MODE AUTO-UNROLL FAILED: " . $unrollFailure . "; press Ctrl+D manually")
        }
        :error "SAFE MODE AUTO-UNROLLED: configuration reverted"
    }
    :put "CONFIG UPDATE COMPLETE. Verify VLANs, root port, and link status before Safe Mode commit."
    :if ($swAuto) do={ :put ("SW:AUTO valid=" . $swReady . " level=" . $hopLevel) }
    :put ("Bridge RSTP root-port and root-path-cost check:")
    :put "UPLINK alone is root-port eligible. NAS-LAN is a protected subscriber gateway-facing port, not an STP backup."
    :put "RSTP path cost cannot guarantee root-port choice against arbitrary advertised upstream costs."
    /interface bridge monitor $bridgeName once
    }
}
/system script run ros7UpdateSwitchConfig
:global ros7UpdateSwitchConfig
:if ([:typeof $ros7UpdateSwitchConfig] != "code") do={ :error "Global function registration failed" }
:put "Installed ros7UpdateSwitchConfig. Preview with [$ros7UpdateSwitchConfig false]"

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

        # Return unique comma-separated items.
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

        # "10,11,12", "10 to 15", "10to15", "10-15".
        # Hard limit: 256 VLANs per expression, range 1..4094.
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

        :local bridges [/interface bridge find where comment="MAIN-SWITCH"]
        :if ([:len $bridges] != 1) do={ :error "Expected exactly one bridge with comment MAIN-SWITCH" }
        :local bridgeId [:pick $bridges 0]
        :local bridgeName [/interface bridge get $bridgeId name]
        :local filtering [/interface bridge get $bridgeId vlan-filtering]
        :local protocol [/interface bridge get $bridgeId protocol-mode]
        :if ($protocol != "rstp") do={
            :error ("MAIN-SWITCH must use rstp; existing protocol-mode=" . $protocol)
        }
        # Identity hierarchy: CORE-SW_SW:0, ISULAN-DSW_SW:1, etc.
        :local identity [/system identity get name]
        :if (($identity ~ "_SW:[0-9]+$") = false) do={
            :error ("ABORT: Identity must end with _SW:<level>, e.g. CORE-SW_SW:0; current=" . $identity)
        }
        :local marker [:find $identity "_SW:"]
        :if ([:typeof $marker] = "nil") do={
            :error ("ABORT: Missing SW level in identity " . $identity)
        }
        :local hopLevel [:tonum [:pick $identity ($marker + 4) [:len $identity]]]
        :if (([:typeof $hopLevel] != "num") || ($hopLevel > 15) || ($hopLevel < 0)) do={
            :error ("ABORT: SW level must be between 0 and 15, got " . $identity)
        }
        :local desiredPriority ($hopLevel * 4096)
        :local currentPriority [/interface bridge get $bridgeId priority]
        :put ("RSTP HIERARCHY: " . $identity . " level=" . $hopLevel . " priority=" . $desiredPriority)
        :put "Only UPLINK is an allowed root-port path (cost 1); NAS-LAN serves the OLT gateway (cost 10000, root guarded)."
        :put "UPLINK: edge=no role=no; NAS-LAN: edge=no role=yes; DOWNLINK: edge=no role=yes; OLT/other: edge=yes-discover role=yes."
        :if ($hopLevel = 0) do={
            :put "CORE LEVEL 0: root bridge has no root port."
        }
        :put "TOPOLOGY: UPLINK supplies VLAN/gateway access to NAS-WAN."
        :put "TOPOLOGY: NAS-LAN carries the OLT subscriber service VLANs."
        :put "CAUTION: NAS-LAN:AUTO currently includes every discovered VLAN, including possible WAN VLANs."
        :put "Use NAS-LAN:<explicit VLAN list> for WAN/subscriber separation."
        :put ("BRIDGE: " . $bridgeName . " vlan-filtering=" . $filtering)
        :put "EXPECTED: vlan-filtering=yes. This script will NOT toggle it remotely."
        :if (!$filtering) do={
            :put "WARNING: vlan-filtering=no; configuration will be staged but not effective."
            :put "This script will NOT enable vlan-filtering."
        }

        # Preserve existing physical management ports.
        :local mgmtMembers ""
        :local mgmtList [/interface list find where name="MGMT-IF"]
        :if ([:len $mgmtList] > 0) do={
            :if ([:len $mgmtList] != 1) do={ :error "Ambiguous MGMT-IF interface list" }
            :local inc [:tostr [/interface list get $mgmtList include]]
            :local exc [:tostr [/interface list get $mgmtList exclude]]
            :if (([:len $inc] > 0) || ([:len $exc] > 0)) do={
                :error "MGMT-IF uses dynamic include/exclude rules; inspect manually"
            }
            :foreach m in=[/interface list member find where list="MGMT-IF"] do={
                :set mgmtMembers [$append $mgmtMembers [/interface list member get $m interface]]
            }
        }

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
            :local tagged ""
            :local auto ""
            :local speed "AUTO"
            :local media ""
            :local arpMode "AUTO"
            :local oltName ""
            :local tagReference ""
            :local recognized false
            :local isOlt ($comment ~ "^OLT")
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
                    # Hyphen separator applies only to known argument keys.
                    :foreach prefix in={"TAGS-";"TAG-";"PVID-";"MGMT-";"VLAN-";"SPEED-";"MEDIA-";"ARP-"} do={
                        :if ([:pick $token 0 [:len $prefix]] = $prefix) do={
                            :set key [:pick $prefix 0 ([:len $prefix] - 1)]
                            :set val [:pick $token [:len $prefix] [:len $token]]
                        }
                    }
                }
                :if (($key = "OLT") || ($key = "DOWNLINK") || ($key = "UPLINK")) do={
                    :set recognized true
                }
                # OLT:AREA1, OLT:51 etc. are labels, never VLAN IDs.
                :if ($key = "OLT") do={
                    :set oltName $val
                }
                :if ($key = "ARP") do={
                    :if ($val != "AUTO") do={
                        :error ("Unsupported ARP mode on " . $name . ": " . $val)
                    }
                    :set arpMode "AUTO"
                }
                # TAG:51 is a single tagged VLAN AND the ARP reference if no PVID.
                # TAGS:10,11,12 adds other tagged VLANs but is not the ARP reference.
                :if ($key = "TAG") do={
                    :local found [$expand $val]
                    :if ([:len [:toarray $found]] != 1) do={
                        :error ("TAG must contain exactly one VLAN; use TAGS for lists on " . $name)
                    }
                    :set tagReference $found
                    :set tagged [$append $tagged $found]
                    :set recognized true
                }
                :if (($key = "TAGS") || ($key = "MGMT") || ($key = "VLAN")) do={
                    :if ($val = "AUTO") do={
                        :if ($key != "VLAN") do={ :error ("AUTO invalid for " . $key . " on " . $name) }
                        :set auto "UPLINK"
                    } else={
                        :local found [$expand $val]
                        :foreach vid in=[:toarray $found] do={
                            :set tagged [$append $tagged $vid]
                            # MGMT VLANs are additional ARP:AUTO scan targets,
                            # independently of PVID or singular TAG.
                            :if ($key = "MGMT") do={
                                :set mgmtArpVlans [$append $mgmtArpVlans $vid]
                            }
                        }
                    }
                    :set recognized true
                }
                :if ($key = "PVID") do={
                    :local found [$expand $val]
                    :if ([:len [:toarray $found]] != 1) do={ :error ("PVID must be one VLAN: " . $name) }
                    :set pvid $found
                    :set recognized true
                }
                :if ($key = "NAS-LAN") do={
                    :set recognized true
                    :if ($val = "AUTO") do={
                        :set auto "NAS-LAN"
                    } else={
                        :local found [$expand $val]
                        :foreach vid in=[:toarray $found] do={ :set tagged [$append $tagged $vid] }
                    }
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
                # NAS-WAN:ISULAN-NAS is a descriptive marker, never a VLAN number.
            }
            :if (($comment ~ "^OLT_RESERVED") || ($comment ~ "^OTHER")) do={
                :set recognized false
            }
            :if ($recognized) do={
                :if ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $name . ",")]] != "nil") do={
                    :put ("PROTECTED MGMT-IF, no change: " . $name)
                } else={
                    :if (([:len $pvid] > 0) && ([:typeof [:find ("," . $tagged . ",") ("," . $pvid . ",")]] != "nil")) do={
                        :error ("Tagged and PVID conflict on " . $name . ": " . $pvid)
                    }
                    # A PVID without any TAG/MGMT/VLAN or AUTO tagging is an untagged-only port.
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
                    :local cost 20000
                    :local restriction "yes"
                    :local edgeSetting "yes-discover"
                    :if ($comment ~ "^UPLINK") do={
                        :set cost 1
                        :set restriction "no"
                        :set edgeSetting "no"
                    }
                    :if ($comment ~ "^NAS-LAN") do={
                        :set cost 10000
                        :set restriction "yes"
                        :set edgeSetting "no"
                    }
                    :if ($comment ~ "^DOWNLINK") do={
                        :set edgeSetting "no"
                    }
                    :set stpCosts ($stpCosts, $cost)
                    :set stpRoles ($stpRoles, $restriction)
                    :set stpEdges ($stpEdges, $edgeSetting)
                    :local arpVlan ""
                    :if ($isOlt) do={
                        # PVID takes precedence; otherwise use single TAG reference.
                        :if ([:len $pvid] > 0) do={
                            :set arpVlan $pvid
                        } else={
                            :set arpVlan $tagReference
                        }
                        :if ([:len $arpVlan] = 0) do={
                            :put ("ARP:AUTO SKIP " . $name . " (" . $oltName . "): no PVID or single TAG reference")
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

        # Validate parallel arrays before referencing them by index.
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
        :if ($currentPriority != $desiredPriority) do={
            :put ("SET BRIDGE RSTP PRIORITY " . $bridgeName . ": " . $currentPriority . " -> " . $desiredPriority)
            :set actions ($actions, "BRIDGEPRIORITY")
            :set actionIds ($actionIds, $bridgeName)
            :set actionValues ($actionValues, [:tostr $desiredPriority])
            :set actionsCount ($actionsCount + 1)
        }


        # ARP:AUTO discovery: OLT:AREA1 is a label, not a VLAN.
        # Reference VLAN = PVID if present, otherwise singular TAG.
        # TAGS:... is not an OLT ARP reference; MGMT:... supplies additional ARP scan VLANs.
        # Filter for C0:FF:EE and C0:FE:EE (digit zero), learned on UPLINK.
        # Static ARP requires IP+MAC+L3 interface; a bridge FDB alone cannot
        # supply a trustworthy IP. This stage intentionally does NOT write ARP.
        :local uplinkPorts ""
        :foreach uplinkRow in=[/interface ethernet find] do={
            :local uplinkComment [:tostr [/interface ethernet get $uplinkRow comment]]
            :if ($uplinkComment ~ "^UPLINK") do={
                :set uplinkPorts [$append $uplinkPorts [/interface ethernet get $uplinkRow name]]
            }
        }
        # Include both OLT PVID/TAG references and MGMT VLANs.
        # Deduplicate VLANs so MGMT:101 repeated across ports is inspected once.
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
                        # C0 uses a hexadecimal ZERO, not the letter O.
                        :if (($mac ~ "^C0:FF:EE") || ($mac ~ "^C0:FE:EE")) do={
                            :if ([:typeof [:find ("," . $uplinkPorts . ",") ("," . $onIf . ",")]] != "nil") do={
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

        # Compare bridge membership and explicit PVID.
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
            # Strict access-port check: do not silently retain explicitly tagged memberships.
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

        # Also enforce root guard for EXISTING unannotated bridge ports.
        # Managed ports are handled above; MGMT-IF members are protected.
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
                        :if ($pc ~ "^UPLINK") do={
                            :set desiredCost 1
                            :set desiredRole "no"
                            :set desiredEdge "no"
                        }
                        :if ($pc ~ "^NAS-LAN") do={
                            :set desiredCost 10000
                            :set desiredRole "yes"
                            :set desiredEdge "no"
                        }
                        :if ($pc ~ "^DOWNLINK") do={
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

        # Plan one VLAN at a time. Only append static tagged membership.
        # PVIDs use RouterOS dynamic untagged membership.
        :foreach vid in=[:toarray $universe] do={
            :local want ""
            :for i from=0 to=($n - 1) do={
                :local name [:pick $names $i]
                :local tagsThis [:pick $tags $i]
                :local pvidThis [:pick $pvids $i]
                :local autoThis [:pick $autos $i]
                :local explicitly ([:typeof [:find ("," . $tagsThis . ",") ("," . $vid . ",")]] != "nil")
                :local autoInclude false
                :if ($autoThis = "NAS-LAN") do={ :set autoInclude true }
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

        # Speed comments: skip unsafe guesses about optical, DAC or copper.
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
        # Disable explicitly reserved/OTHER ports by default.
        # Unclassified ports are disabled only when link-down, unbridged and unaddressed.
        # Protect MGMT-IF membership and interface names beginning MGMT/Management.
        :foreach phys in=[/interface ethernet find] do={
            :local pname [/interface ethernet get $phys name]
            :local pc [:tostr [/interface ethernet get $phys comment]]
            :local isProtected ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $pname . ",")]] != "nil")
            :if (($pc ~ "^MGMT") || ($pc ~ "^Management") || ($pname ~ "^MGMT") || ($pname ~ "^Management")) do={
                :set isProtected true
            }
            :local known false
            :foreach managedName in=$names do={
                :if ($managedName = $pname) do={ :set known true }
            }
            :local explicitDisable (($pc ~ "^OLT_RESERVED") || ($pc ~ "^OTHER"))
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
        # RouterOS Ethernet loop protection complements RSTP.
        # Cover ALL physical Ethernet interfaces, including MGMT-IF members,
        # uplinks, downlinks, NAS ports, disabled ports, and unannotated ports.
        # Only change loop-protect: preserve each interface's existing timers.
        :local loopChanges 0
        :foreach etherId in=[/interface ethernet find] do={
            :local etherName [/interface ethernet get $etherId name]
            :local state [:tostr [/interface ethernet get $etherId loop-protect]]
            :if ($state != "on") do={
                :put ("ENABLE LOOP-PROTECT " . $etherName . " (current=" . $state . ")")
                :set actions ($actions, "LOOPPROTECT")
                :set actionIds ($actionIds, $etherName)
                :set actionValues ($actionValues, "on")
                :set actionsCount ($actionsCount + 1)
                :set loopChanges ($loopChanges + 1)
            }
        }
        :put ("LOOP-PROTECT: " . $loopChanges . " physical Ethernet interfaces need enabling")
        :put ("PLANNED CHANGES: " . $actionsCount)
        :if ($apply && !$filtering) do={
            :error "ABORT: MAIN-SWITCH vlan-filtering=no. Enable separately after verifying management VLAN access."
        }
        :if (!$apply) do={ :put "PREVIEW ONLY: NO CHANGES APPLIED"; :return }
        :if ($actionsCount = 0) do={ :put "ALREADY IN SYNC"; :return }
        :put "WARNING: This can interrupt switching. Use interactive Safe Mode Ctrl+X."
        :put "Press Y within 30 seconds to apply. Other keys/timeout cancel."
        :local response 0
        :onerror e in={
            :set response [/terminal inkey timeout=30s]
        } do={ :error ("Interactive confirmation failed: " . $e) }
        :if (($response != 89) && ($response != 121)) do={ :error "CANCELLED" }

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

        # Non-destructive: no deletes, no vlan-filtering toggle, no bridge moves.
        :for i from=0 to=($actionsCount - 1) do={
            :local action [:pick $actions $i]
            :local name [:pick $actionIds $i]
            :local value [:pick $actionValues $i]
            :if ($action = "BRIDGEPRIORITY") do={
                /interface bridge set $bridgeId priority=[:tonum $value]
            }
            :if (($action = "PORT") || ($action = "PORTACCESS")) do={
                :local cost 20000
                :local restrictedBoolean true
                :local edgeSetting "yes-discover"
                :local ethId [/interface ethernet find where name=$name]
                :if ([:len $ethId] = 1) do={
                    :local c [/interface ethernet get $ethId comment]
                    :if ($c ~ "^UPLINK") do={
                        :set cost 1
                        :set restrictedBoolean false
                        :set edgeSetting "no"
                    }
                    :if ($c ~ "^NAS-LAN") do={
                        :set cost 10000
                        :set restrictedBoolean true
                        :set edgeSetting "no"
                    }
                    :if ($c ~ "^DOWNLINK") do={
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
            :put ("DONE: " . $action . " " . $name)
        }
        :put "CONFIG UPDATE COMPLETE. Verify VLANs, root port, and link status before Safe Mode commit."
        :put ("Identity SW level " . $hopLevel . " is manually declared; NOT measured hop count.")
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

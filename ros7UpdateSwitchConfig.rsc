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
        :put ("BRIDGE: " . $bridgeName . " vlan-filtering=" . $filtering)
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
        :local universe ""
        :local oltPvids ""

        :foreach eth in=[/interface ethernet find] do={
            :local name [/interface ethernet get $eth name]
            :local comment [:tostr [/interface ethernet get $eth comment]]
            :local rest $comment
            :local pvid ""
            :local tagged ""
            :local auto ""
            :local speed ""
            :local media ""
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
                    :foreach prefix in={"TAG-";"PVID-";"MGMT-";"VLAN-";"SPEED-";"MEDIA-"} do={
                        :if ([:pick $token 0 [:len $prefix]] = $prefix) do={
                            :set key [:pick $prefix 0 ([:len $prefix] - 1)]
                            :set val [:pick $token [:len $prefix] [:len $token]]
                        }
                    }
                }
                :if (($key = "OLT") || ($key = "DOWNLINK") || ($key = "UPLINK")) do={
                    :set recognized true
                }
                :if (($key = "TAG") || ($key = "MGMT") || ($key = "VLAN")) do={
                    :if ($val = "AUTO") do={
                        :if ($key != "VLAN") do={ :error ("AUTO invalid for " . $key . " on " . $name) }
                        :set auto "UPLINK"
                    } else={
                        :local found [$expand $val]
                        :foreach vid in=[:toarray $found] do={
                            :set tagged [$append $tagged $vid]
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
            :if ($recognized) do={
                :if ([:typeof [:find ("," . $mgmtMembers . ",") ("," . $name . ",")]] != "nil") do={
                    :put ("PROTECTED MGMT-IF, no change: " . $name)
                } else={
                    :if (([:len $pvid] > 0) && ([:typeof [:find ("," . $tagged . ",") ("," . $pvid . ",")]] != "nil")) do={
                        :error ("Tagged and PVID conflict on " . $name . ": " . $pvid)
                    }
                    :set names ($names, $name)
                    :set pvids ($pvids, $pvid)
                    :set tags ($tags, $tagged)
                    :set autos ($autos, $auto)
                    :set speeds ($speeds, $speed)
                    :set mediaTypes ($mediaTypes, $media)
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
        :if (([:len $pvids] != $n) || ([:len $tags] != $n) || ([:len $autos] != $n) || ([:len $speeds] != $n) || ([:len $mediaTypes] != $n)) do={
            :error "ABORT: Internal port metadata array length mismatch"
        }
        :if ($n = 0) do={ :error "No recognized interface comments on this switch" }
        :put ("MANAGED PORTS: " . $n . " VLAN UNIVERSE: " . $universe)
        :local actions [:toarray ""]
        :local actionIds [:toarray ""]
        :local actionValues [:toarray ""]
        :local actionsCount 0

        # Compare bridge membership and explicit PVID.
        :for i from=0 to=($n - 1) do={
            :local name [:pick $names $i]
            :local pvid [:pick $pvids $i]
            :local existing [/interface bridge port find where interface=$name]
            :if ([:len $existing] > 1) do={ :error ("Duplicate bridge ports: " . $name) }
            :if ([:len $existing] = 1) do={
                :local onBridge [/interface bridge port get $existing bridge]
                :if ($onBridge != $bridgeName) do={
                    :error ("ABORT: " . $name . " already belongs to bridge " . $onBridge)
                }
                :if ([:len $pvid] > 0) do={
                    :if ([:tostr [/interface bridge port get $existing pvid]] != $pvid) do={
                        :put ("UPDATE PVID " . $name . " -> " . $pvid)
                        :set actions ($actions, "PVID")
                        :set actionIds ($actionIds, $name)
                        :set actionValues ($actionValues, $pvid)
                        :set actionsCount ($actionsCount + 1)
                    }
                }
            } else={
                :put ("ADD BRIDGE PORT " . $name . " to " . $bridgeName . " pvid=" . $pvid)
                :set actions ($actions, "PORT")
                :set actionIds ($actionIds, $name)
                :set actionValues ($actionValues, $pvid)
                :set actionsCount ($actionsCount + 1)
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
                        :set actionIds ($actionIds, $vid)
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
        :put ("PLANNED CHANGES: " . $actionsCount)
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
            :if ($action = "PORT") do={
                :if ($value = "") do={
                    /interface bridge port add bridge=$bridgeName interface=$name
                } else={
                    /interface bridge port add bridge=$bridgeName interface=$name pvid=[:tonum $value]
                }
            }
            :if ($action = "PVID") do={
                /interface bridge port set [find where interface=$name and bridge=$bridgeName] pvid=[:tonum $value]
            }
            :if ($action = "VLANADD") do={
                /interface bridge vlan add bridge=$bridgeName vlan-ids=[:tonum $name] tagged=$value
            }
            :if ($action = "VLANSET") do={
                /interface bridge vlan set [find where bridge=$bridgeName and vlan-ids=[:tonum $name] and dynamic=no] tagged=$value
            }
            :if ($action = "SPEEDAUTO") do={
                /interface ethernet set [find where name=$name] auto-negotiation=yes
            }
            :if ($action = "SPEED") do={
                /interface ethernet set [find where name=$name] auto-negotiation=no speed=$value
            }
            :put ("DONE: " . $action . " " . $name)
        }
        :put "CONFIG UPDATE COMPLETE. Verify bridge VLAN table and link status before Safe Mode commit."
    }
}
/system script run ros7UpdateSwitchConfig
:global ros7UpdateSwitchConfig
:if ([:typeof $ros7UpdateSwitchConfig] != "code") do={ :error "Global function registration failed" }
:put "Installed ros7UpdateSwitchConfig. Preview with [$ros7UpdateSwitchConfig false]"

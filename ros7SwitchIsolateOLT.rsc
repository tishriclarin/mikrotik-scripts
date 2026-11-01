# RouterOS 7 global function installer (import registers function, never applies changes).
:local rosVersion [/system resource get version]
:if ([:pick $rosVersion 0 2] != "7.") do={
    :error ("ABORT: Requires RouterOS 7; running " . $rosVersion)
}
:put ("RouterOS version verified: " . $rosVersion)
:local prior [/system script find where name="ros7SwitchIsolateOLT"]
:if ([:len $prior] > 0) do={ /system script remove $prior }
/system script add name=ros7SwitchIsolateOLT policy=read,write,test source={
    :global ros7SwitchIsolateOLT do={
        :local apply $1
        :if ([:typeof $apply] = "nil") do={ :set apply false }
        :if ([:typeof $apply] != "bool") do={ :error "Argument must be Boolean true or false" }
    :local sources [:toarray ""]
    :local desired [:toarray ""]
    :local previous [:toarray ""]
    :local attempted [:toarray ""]
    :local mgmtMembers [:toarray ""]
    :local stage "initialization"
    :local planFailed false
    :local planError ""

    :put "=== ros7SwitchIsolateOLT ==="
    :put "Isolation comment prefixes: OLT and DOWNLINK"

    :local mgmtList [/interface list find where name="MGMT-IF"]
    :if ([:len $mgmtList] > 1) do={
        :error "ABORT: Multiple MGMT-IF lists detected"
    }
    :if ([:len $mgmtList] = 1) do={
        :local inc [:tostr [/interface list get $mgmtList include]]
        :local exc [:tostr [/interface list get $mgmtList exclude]]
        :if (([:len $inc] > 0) || ([:len $exc] > 0)) do={
            :error "ABORT: MGMT-IF has include/exclude lists; dynamic membership not resolved"
        }
        :foreach m in=[/interface list member find where list="MGMT-IF"] do={
            :local ifname [/interface list member get $m interface]
            :set mgmtMembers ($mgmtMembers, $ifname)
            :put ("PROTECTED MGMT-IF: " . $ifname)
        }
    } else={
        :put "MGMT-IF absent: checking management comments and names"
    }

    :onerror err in={
        :foreach src in=[/interface ethernet switch port-isolation find] do={
            :set stage "reading source switch-port entry"
            :local srcName [/interface ethernet switch port-isolation get $src name]
            :set stage ("source " . $srcName)
            :local srcEth [/interface ethernet find where name=$srcName]
            :if ([:len $srcEth] = 1) do={
                :local srcComment [/interface ethernet get $srcEth comment]
                :local isolated (($srcComment ~ "^OLT") || ($srcComment ~ "^DOWNLINK"))
                :local protected false
                :foreach m in=$mgmtMembers do={
                    :if ($m = $srcName) do={ :set protected true }
                }
                :if (($srcComment ~ "^MGMT") || ($srcComment ~ "^Management")) do={
                    :set protected true
                }
                :if (($srcName ~ "^MGMT") || ($srcName ~ "^Management")) do={
                    :set protected true
                }
                :if ($isolated && $protected) do={
                    :put ("SKIP PROTECTED: " . $srcName)
                }
                :if ($isolated && !$protected) do={
                    :local chip [/interface ethernet switch port-isolation get $src switch]
                    :local allowed ""
                    :foreach dst in=[/interface ethernet switch port-isolation find] do={
                        :set stage ("source " . $srcName . ", reading destination")
                        :local dstName [/interface ethernet switch port-isolation get $dst name]
                        :set stage ("source " . $srcName . ", destination " . $dstName)
                        :local dstChip [/interface ethernet switch port-isolation get $dst switch]
                        :if ($dstChip = $chip) do={
                            :local dstEth [/interface ethernet find where name=$dstName]
                            :if ([:len $dstEth] = 1) do={
                                :local c [/interface ethernet get $dstEth comment]
                                :local dstIsolated (($c ~ "^OLT") || ($c ~ "^DOWNLINK"))
                                :if (!$dstIsolated) do={
                                    :local running [/interface ethernet get $dstEth running]
                                    :local allowSpecial (($c ~ "^UPLINK") || ($c ~ "^MGMT") || ($c ~ "^Management"))
                                    :if (($dstName ~ "^MGMT") || ($dstName ~ "^Management")) do={
                                        :set allowSpecial true
                                    }
                                    :foreach m in=$mgmtMembers do={
                                        :if ($m = $dstName) do={ :set allowSpecial true }
                                    }
                                    :if ($running || $allowSpecial) do={
                                        :if ([:len $allowed] = 0) do={
                                            :set allowed $dstName
                                        } else={
                                            :set allowed ($allowed . "," . $dstName)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    :if ([:len $allowed] = 0) do={
                        :error ("No eligible forwarding destinations for " . $srcName)
                    }
                    :set stage ("reading original override for " . $srcName)
                    :local original [:tostr [/interface ethernet switch port-isolation get $src forwarding-override]]
                    :if ($original != $allowed) do={
                        :set sources ($sources, $srcName)
                        :set desired ($desired, $allowed)
                        :set previous ($previous, $original)
                        :put "-------------------------------------------"
                        :put ("SOURCE:  " . $srcName)
                        :put ("CURRENT: " . $original)
                        :put ("NEW:     " . $allowed)
                    } else={
                        :put ("UNCHANGED: " . $srcName)
                    }
                }
            }
        }
    } do={
        :set planFailed true
        :set planError $err
    }

    :if ($planFailed) do={
        :put ("PLANNING ERROR AT: " . $stage)
        :error ("ABORT: " . $planError)
    }
        :local count [:len $sources]
        :put ("PROPOSED CHANGES: " . $count)
        :if ($count > 30) do={ :error "ABORT: too many ports" }
        :if ($count = 0) do={ :put "NO CHANGES REQUIRED"; :return }
        :if (!$apply) do={ :put "PREVIEW ONLY - NO CHANGES APPLIED"; :return }
        :put "WARNING: LIVE SWITCH CHANGE. Use Safe Mode Ctrl+X before remote changes."
        :local answer ""
        :onerror askError in={ :set answer [/terminal/ask prompt="Type YES to apply, NO to cancel"] } do={
            :error ("ABORT: confirmation unavailable: " . $askError)
        }
        :if ($answer != "YES") do={ :put "CANCELLED"; :return }
        :local modified [:toarray ""]
        :local failed false
        :local reason ""
        :onerror applyError in={
            :for i from=0 to=($count - 1) do={
                :local portName [:pick $sources $i]
                :local row [/interface ethernet switch port-isolation find where name=$portName]
                :if ([:len $row] != 1) do={ :error ("Source not found: " . $portName) }
                :set modified ($modified, $i)
                /interface ethernet switch port-isolation set $row forwarding-override=[:pick $desired $i]
                :put ("APPLIED: " . $portName)
            }
        } do={
            :set failed true
            :set reason $applyError
        }
        :if ($failed) do={
            :put ("APPLY ERROR: " . $reason)
            :local restoreFailed false
            :foreach i in=$modified do={
                :local name [:pick $sources $i]
                :onerror restoreErr in={
                    :local row [/interface ethernet switch port-isolation find where name=$name]
                    :if ([:len $row] != 1) do={ :error "Source missing during rollback" }
                    /interface ethernet switch port-isolation set $row forwarding-override=[:pick $previous $i]
                    :put ("RESTORED: " . $name)
                } do={
                    :set restoreFailed true
                    :put ("RESTORE ERROR: " . $name . " " . $restoreErr)
                }
            }
            :if ($restoreFailed) do={ :error "ROLLBACK INCOMPLETE - CHECK PORTS" }
            :error "FAILED: ROLLBACK ATTEMPTED"
        }
        :put "ISOLATION APPLIED. Check subscriber traffic and management before committing."
    }
}
:local installedId [/system script find where name="ros7SwitchIsolateOLT"]
:if ([:len $installedId] != 1) do={ :error "ABORT: Installed script not found uniquely" }
:onerror parseError in={
    :local parsed [:parse [/system script get $installedId source]]
} do={
    :error ("ABORT: Installed script parse failed: " . $parseError)
}
:put "Saved system script parse check PASSED"
/system script run ros7SwitchIsolateOLT
:global ros7SwitchIsolateOLT
:if ([:typeof $ros7SwitchIsolateOLT] != "code") do={
    :error "ABORT: Global function was not registered"
}
:put "Global function registered. Starting read-only preview self-test..."
[$ros7SwitchIsolateOLT false]
:put "Preview test completed; no forwarding changes were made."
:put "Call preview: :global ros7SwitchIsolateOLT; [\$ros7SwitchIsolateOLT false]"
:put "Call apply:   :global ros7SwitchIsolateOLT; [\$ros7SwitchIsolateOLT true]"

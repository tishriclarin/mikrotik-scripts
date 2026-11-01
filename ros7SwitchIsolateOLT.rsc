# ros7SwitchIsolateOLT - RouterOS 7.25+ one-time terminal script
# PREVIEW by default. To apply, change the value below to true.
# For remote work, use interactive Safe Mode (Ctrl+X) before applying.
{
    :local apply false

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
    :local total [:len $sources]
    :put "==========================================="
    :put ("PROPOSED PORT CHANGES: " . $total)
    :if ($total > 30) do={ :error "ABORT: More than 30 changes in one batch" }
    :if ($total = 0) do={
        :put "NO CHANGES REQUIRED"
    } else={
        :if (!$apply) do={
            :put "PREVIEW ONLY - NOTHING MODIFIED"
        } else={
            :local inSafe false
            :local safeEnabled false
            :onerror safeErr in={
                :set inSafe [/safe-mode get current]
                :set safeEnabled [/safe-mode get enabled]
            } do={
                :error ("ABORT: Cannot inspect Safe Mode: " . $safeErr)
            }
            :if ($safeEnabled && !$inSafe) do={
                :error "ABORT: Another session owns Safe Mode"
            }
            :local confirmed $inSafe
            :if (!$inSafe) do={
                :put "WARNING: SAFE MODE NOT ACTIVE"
                :put "Review every SOURCE / CURRENT / NEW line above."
                :local answer ""
                :onerror askErr in={
                    :set answer [/terminal ask prompt="Type YES to apply, otherwise cancel"]
                } do={
                    :error ("ABORT: Interactive confirmation unavailable: " . $askErr)
                }
                :if ($answer = "YES") do={ :set confirmed true }
            }
            :if (!$confirmed) do={
                :put "CANCELLED - NO CHANGES APPLIED"
            } else={
                :local failed false
                :local reason ""
                :onerror applyErr in={
                    :for i from=0 to=($total - 1) do={
                        :local name [:pick $sources $i]
                        :local rule [:pick $desired $i]
                        :local portId [/interface ethernet switch port-isolation find where name=$name]
                        :if ([:len $portId] != 1) do={
                            :error ("Source missing or ambiguous: " . $name)
                        }
                        :set attempted ($attempted, $i)
                        /interface ethernet switch port-isolation set $portId forwarding-override=$rule
                        :put ("APPLIED: " . $name)
                    }
                } do={
                    :set failed true
                    :set reason $applyErr
                }
                :if ($failed) do={
                    :put ("APPLY ERROR: " . $reason)
                    :local rollbackFailed false
                    :foreach i in=$attempted do={
                        :local name [:pick $sources $i]
                        :local old [:pick $previous $i]
                        :onerror restoreErr in={
                            :local portId [/interface ethernet switch port-isolation find where name=$name]
                            :if ([:len $portId] != 1) do={
                                :error ("Source disappeared: " . $name)
                            }
                            /interface ethernet switch port-isolation set $portId forwarding-override=$old
                            :put ("RESTORED: " . $name)
                        } do={
                            :set rollbackFailed true
                            :put ("RESTORE FAILED: " . $name . " " . $restoreErr)
                        }
                    }
                    :if ($rollbackFailed) do={
                        :error "ROLLBACK INCOMPLETE - REVIEW CURRENT PORT SETTINGS"
                    }
                    :error "APPLY FAILED - ROLLBACK ATTEMPTED"
                }
                :put "OLT + DOWNLINK ISOLATION APPLIED"
                :put ("UPDATED PORTS: " . $total)
                :put "MGMT-IF member port settings remain unchanged"
                :put "Verify switching traffic and management from another session"
                :if ($inSafe) do={
                    :put "Ctrl+X to COMMIT; Ctrl+D to ABANDON Safe Mode changes"
                }
            }
        }
    }
}

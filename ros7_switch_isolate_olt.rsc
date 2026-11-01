# RouterOS 7 - persistent system script installer
# Creates ros7_switch_isolate_olt. Does not execute port changes during import.
# IMPORTANT: Update mgmtIP and gateway inside the installed script before running.
# Run from an interactive terminal with <SAFE> shown (Ctrl+X).
/system script add name=ros7_switch_isolate_olt policy=read,write,test source={
    :local mgmtIP "SET_MGMT_IP"
    :local cfgGateway "SET_GATEWAY"

    :if (($mgmtIP = "SET_MGMT_IP") || ($cfgGateway = "SET_GATEWAY")) do={
        :error "ABORT: Set mgmtIP and cfgGateway in script source first"
    }

    :local sourceOK false
    :foreach ipRow in=[/ip address find where disabled=no] do={
        :local ipText [/ip address get $ipRow address]
        :local slash [:find $ipText "/"]
        :if ([:typeof $slash] != "nil") do={
            :if ([:pick $ipText 0 $slash] = $mgmtIP) do={
                :set sourceOK true
            }
        }
    }
    :if (!$sourceOK) do={
        :error "ABORT: management source IP is not active on this router"
    }

    :if ([/ping address=$cfgGateway src-address=$mgmtIP count=3] = 0) do={
        :error "ABORT: management gateway unreachable before changes"
    }

    :local targets [:toarray ""]
    :local planned [:toarray ""]
    :local saved [:toarray ""]

    # Build the entire change plan before modifying any port.
    :foreach oltEntry in=[/interface ethernet switch port-isolation find] do={
        :local portName [/interface ethernet switch port-isolation get $oltEntry name]
        :local ethId [/interface ethernet find where name=$portName]
        :if ([:len $ethId] > 0) do={
            :local portComment [/interface ethernet get $ethId comment]
            :if ($portComment ~ "^OLT-") do={
                :local chipName [/interface ethernet switch port-isolation get $oltEntry switch]
                :local allowed ""
                :local allowedPhysical 0
                :foreach candidateRow in=[/interface ethernet switch port-isolation find where switch=$chipName] do={
                    :local otherName [/interface ethernet switch port-isolation get $candidateRow name]
                    :local otherEth [/interface ethernet find where name=$otherName]
                    :local otherIsOlt false
                    :if ([:len $otherEth] > 0) do={
                        :if ([/interface ethernet get $otherEth comment] ~ "^OLT-") do={
                            :set otherIsOlt true
                        } else={
                            :set allowedPhysical ($allowedPhysical + 1)
                        }
                    }
                    :if (!$otherIsOlt) do={
                        :if ([:len $allowed] = 0) do={
                            :set allowed $otherName
                        } else={
                            :set allowed ($allowed . "," . $otherName)
                        }
                    }
                }
                :if (($allowedPhysical = 0) || ([:len $allowed] = 0)) do={
                    :error ("ABORT: no non-OLT Ethernet destinations for " . $portName)
                }
                :set targets ($targets, $portName)
                :set ($planned->$portName) $allowed
                :set ($saved->$portName) [/interface ethernet switch port-isolation get $oltEntry forwarding-override]
                :put ("PLAN " . $portName . " -> " . $allowed)
            }
        }
    }

    :local total [:len $targets]
    :if ($total = 0) do={
        :error "ABORT: no Ethernet ports with comments starting OLT-"
    }
    :if ($total > 30) do={
        :error "ABORT: over 30 OLT ports; split changes to stay within Safe Mode history"
    }

    :local failed false
    :local why ""
    :onerror e in={
        :foreach portName in=$targets do={
            :local portId [/interface ethernet switch port-isolation find where name=$portName]
            /interface ethernet switch port-isolation set $portId forwarding-override=($planned->$portName)
            :delay 1s
            :if ([/ping address=$cfgGateway src-address=$mgmtIP count=3] = 0) do={
                :error ("gateway ping failed after changing " . $portName)
            }
        }
    } do={
        :set failed true
        :set why $e
    }

    :if ($failed) do={
        :log warning ("ros7_switch_isolate_olt: attempting rollback: " . $why)
        :foreach portName in=$targets do={
            :onerror restoreError in={
                :local portId [/interface ethernet switch port-isolation find where name=$portName]
                /interface ethernet switch port-isolation set $portId forwarding-override=($saved->$portName)
            } do={
                :log error ("ros7_switch_isolate_olt: restore failed for " . $portName . ": " . $restoreError)
            }
        }
        :error "FAILED: verify rollback; abandon Safe Mode with Ctrl+D"
    }

    :log info ("ros7_switch_isolate_olt: changed " . $total . " OLT ports; gateway is reachable")
    :put "Gateway reachable. Verify a SECOND management session before committing Safe Mode (Ctrl+X)."
}

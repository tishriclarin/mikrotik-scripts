# MikroTik RouterOS 7
# One-time installer for DHCP-triggered ECMP routes in routing-table=main.
# Import with: /import file-name=install-route-f.rsc

:put "Installing route-f..."

# Replace only the installer-owned loader script.
:foreach scriptID in=[/system script find where name="load-route-f"] do={
    /system script remove $scriptID
}

/system script add name=load-route-f policy=read,write,test,policy dont-require-permissions=no source={
    :global "route-f" do={
        :local iface $1
        :local leaseBound $2
        :local gatewayAddress $3

        :local routeComment ("MAIN-ECMP-" . $iface)
        :local routeIDs [/ip route find where dst-address="0.0.0.0/0" and routing-table="main" and comment=$routeComment]

        # A valid DHCP lease creates or repairs this WAN's route in main.
        :if ($leaseBound = 1) do={
            :if (([:typeof $gatewayAddress] = "nil") || ($gatewayAddress = "")) do={
                :log error ("route-f: DHCP supplied no gateway on " . $iface)
                :return false
            }

            :local routeGateway ($gatewayAddress . "%" . $iface)
            :local keepRoute ""
            :local duplicateCount 0

            :foreach routeID in=$routeIDs do={
                :if ($keepRoute = "") do={
                    :set keepRoute $routeID
                } else={
                    /ip route remove $routeID
                    :set duplicateCount ($duplicateCount + 1)
                }
            }

            :if ($keepRoute = "") do={
                /ip route add dst-address=0.0.0.0/0 gateway=$routeGateway routing-table=main distance=1 scope=30 target-scope=10 comment=$routeComment
                :log info ("route-f: added main ECMP route through " . $routeGateway)
            } else={
                /ip route set $keepRoute gateway=$routeGateway distance=1 scope=30 target-scope=10 disabled=no
                :log info ("route-f: repaired main ECMP route through " . $routeGateway)
            }

            :if ($duplicateCount > 0) do={
                :log warning ("route-f: removed " . $duplicateCount . " duplicate route(s) for " . $iface)
            }

            :return true
        }

        # Losing the DHCP lease removes only this WAN's route from main.
        :if ([:len $routeIDs] > 0) do={
            /ip route remove $routeIDs
            :log warning ("route-f: lease lost; removed main ECMP route for " . $iface)
        }

        :return false
    }

    :log info "route-f: global function loaded"
}

# Replace only the installer-owned installation script.
:foreach scriptID in=[/system script find where name="install-route-f"] do={
    /system script remove $scriptID
}

/system script add name=install-route-f policy=read,write,test,policy dont-require-permissions=no source={
    :local marker "ROUTE-F-TRIGGER"
    :local triggerSource "\r\n# ROUTE-F-TRIGGER\r\n:global \"route-f\"; :if ([:typeof \$\"route-f\"] != \"closure\") do={/system script run load-route-f; :global \"route-f\"}; :if ([:typeof \$\"route-f\"] = \"closure\") do={[\$\"route-f\" \$interface \$bound \$\"gateway-address\"]} else={:log error (\"DHCP: failed to load route-f for \" . \$interface)}\r\n"

    :if ([:len [/system script find where name="load-route-f"]] = 0) do={
        :log error "install-route-f: load-route-f is missing"
        :error "load-route-f is missing"
    }

    :local installedCount 0
    :local skippedCount 0

    :foreach dhcpID in=[/ip dhcp-client find] do={
        :local iface [/ip dhcp-client get $dhcpID interface]
        :local currentSource [:tostr [/ip dhcp-client get $dhcpID script]]
        :local markerPosition [:find $currentSource $marker]

        :if ([:typeof $markerPosition] = "nil") do={
            :local newSource $triggerSource

            :if ([:len $currentSource] > 0) do={
                :set newSource ($currentSource . "\r\n" . $triggerSource)
            }

            /ip dhcp-client set $dhcpID script=$newSource
            :set installedCount ($installedCount + 1)
            :log info ("install-route-f: installed DHCP trigger on " . $iface)
        } else={
            :set skippedCount ($skippedCount + 1)
            :log info ("install-route-f: trigger already present on " . $iface)
        }
    }

    :log info ("install-route-f: completed; installed=" . $installedCount . ", already-present=" . $skippedCount)
}

# Load the global function now and patch every existing DHCP client.
/system script run load-route-f
/system script run install-route-f

:put "route-f installation complete."
:put "Verify with: /ip dhcp-client print detail"
:put "Verify routes with: /ip route print where comment~\"MAIN-ECMP-\""

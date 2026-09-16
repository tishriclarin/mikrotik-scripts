# MikroTik Configurator BTH apply module
# Imported only after SHA-512 verification.

:global installBTH do={
    :local a $address
    :local u $username
    :if ([:typeof $u] = "nothing") do={ :set u "wg" }
    :local targetOS $os
    :if ([:typeof $targetOS] = "nothing") do={ :set targetOS "debian" }
    :set targetOS [:convert $targetOS transform=lc]
    :local useDefault $defaultRoute
    :if ([:typeof $useDefault] = "nothing") do={ :set useDefault "no" }
    :set useDefault [:convert $useDefault transform=lc]
    :local proto $protocol
    :if ([:typeof $proto] = "nothing") do={ :set proto "tcp" }
    :set proto [:convert $proto transform=lc]
    :local portList $ports
    :local resetAll $"reset-all"
    :if ([:typeof $resetAll] = "nothing") do={ :set resetAll "no" }
    :set resetAll [:convert $resetAll transform=lc]
    :local allowed $routes
    :local safeMode $"safe-mode"
    :if ([:typeof $safeMode] = "nothing") do={ :set safeMode "yes" }
    :set safeMode [:convert $safeMode transform=lc]
    :local makeBackup $backup
    :if ([:typeof $makeBackup] = "nothing") do={ :set makeBackup "yes" }
    :set makeBackup [:convert $makeBackup transform=lc]
    :local approved $confirm
    :if ([:typeof $approved] = "nothing") do={ :set approved "no" }
    :set approved [:convert $approved transform=lc]
    :local accessList $access
    :if ([:typeof $accessList] = "nothing") do={ :set accessList "MGMT" }

    # Precheck: no mutation is allowed above this line.
    :if ([:typeof $a] = "nothing") do={ :error "PRECHECK FAILED: address is required" }
    :if ($targetOS != "debian") do={ :error ("PRECHECK FAILED: OS '" . $targetOS . "' not supported; use debian") }
    :if (($useDefault != "yes") && ($useDefault != "no")) do={ :error "PRECHECK FAILED: defaultRoute must be yes or no" }
    :if (($resetAll != "yes") && ($resetAll != "no")) do={ :error "PRECHECK FAILED: reset-all must be yes or no" }
    :if (($proto != "tcp") && ($proto != "udp")) do={ :error "PRECHECK FAILED: protocol must be tcp or udp" }
    :if ([:len $portList] = 0) do={ :error "PRECHECK FAILED: ports is required" }
    :if (($safeMode != "yes") && ($safeMode != "no")) do={ :error "PRECHECK FAILED: safe-mode must be yes or no" }
    :if (($makeBackup != "yes") && ($makeBackup != "no")) do={ :error "PRECHECK FAILED: backup must be yes or no" }
    :if (($approved != "yes") && ($approved != "no")) do={ :error "PRECHECK FAILED: confirm must be yes or no" }
    :foreach token in=[:toarray $accessList] do={
        :if (($token != "MGMT") && ($token != "REMOTE-MGMT") && ($token != "LAN") && ($token != "WAN") && ($token != "NAT")) do={ :error ("PRECHECK FAILED: unsupported access constant " . $token) }
    }

    :local slash [:find $a "/"]
    :if ([:typeof $slash] = "nil") do={ :error "PRECHECK FAILED: address requires /30" }
    :if ([:pick $a ($slash + 1) [:len $a]] != "30") do={ :error "PRECHECK FAILED: only IPv4 /30 is supported" }
    :local routerIP [:pick $a 0 $slash]
    :local d1 [:find $routerIP "."]
    :local d2 [:find $routerIP "." ($d1 + 1)]
    :local d3 [:find $routerIP "." ($d2 + 1)]
    :if ([:typeof $d3] = "nil") do={ :error "PRECHECK FAILED: invalid IPv4 address" }
    :local last [:tonum [:pick $routerIP ($d3 + 1) [:len $routerIP]]]
    :if (([:typeof $last] = "nil") || (($last % 4) != 1)) do={ :error "PRECHECK FAILED: router /30 must be first usable address (.1,.5,.9,...)" }
    :local base [:pick $routerIP 0 ($d3 + 1)]
    :local clientIP ($base . ($last + 1))
    :local clientCIDR ($clientIP . "/32")
    :local fwComment ("installBTH:firewall:" . $u)
    :local addrComment ("installBTH:address:" . $u)
    :local accessPrefix ("installBTH:access:" . $u . ":")
    :if ($useDefault = "yes") do={ :set allowed "0.0.0.0/0" }
    :if (($useDefault = "no") && ([:len $allowed] = 0)) do={ :set allowed ($base . ($last - 1) . "/30") }

    # Resolve the active management path. Abort if several remote sessions make it ambiguous.
    :local mgmtAddress ""
    :local mgmtCount 0
    :foreach activeID in=[/user/active/find] do={
        :local activeVia [/user/active/get $activeID via]
        :if (($activeVia = "ssh") || ($activeVia = "telnet") || ($activeVia = "winbox")) do={
            :local activeAddress [/user/active/get $activeID address]
            :if ([:len $activeAddress] > 0) do={ :set mgmtAddress $activeAddress; :set mgmtCount ($mgmtCount + 1) }
        }
    }
    :if ($mgmtCount > 1) do={ :error "PRECHECK FAILED: management session discovery is ambiguous; close other SSH/Telnet/WinBox sessions" }
    :local mgmtReachable false
    :local internetReachable false
    :local mgmtArpPresent false
    :local mgmtInterface "routed/unknown"
    :if ([:len $mgmtAddress] > 0) do={
        :if ([/ping address=$mgmtAddress count=2 interval=300ms] > 0) do={ :set mgmtReachable true }
        :local arpID [/ip/arp/find where address=$mgmtAddress]
        :if ([:len $arpID] > 0) do={ :set mgmtArpPresent true; :set mgmtInterface [/ip/arp/get [:pick $arpID 0] interface] }
    }
    :if ([/ping address=8.8.8.8 count=2 interval=300ms] > 0) do={ :set internetReachable true }

    :put "========== installBTH CHANGE PLAN =========="
    :put ("BTH user: " . $u . " (logical role: admin; no RouterOS login user created)")
    :put ("Router/client: " . $a . " / " . $clientCIDR)
    :put ("Default route: " . $useDefault . "; AllowedIPs: " . $allowed)
    :put ("Firewall input: " . $proto . "/" . $portList)
    :put ("Address-list access: " . $accessList)
    :put ("reset-all=" . $resetAll . " safe-mode=" . $safeMode . " backup=" . $makeBackup)
    :put ("Management source=" . $mgmtAddress . " interface=" . $mgmtInterface . " ARP=" . $mgmtArpPresent . " ping=" . $mgmtReachable)
    :put ("Internet 8.8.8.8 reachable=" . $internetReachable)
    :if ($resetAll = "yes") do={ :put "WARNING: all BTH users and previous installBTH objects will be removed" }
    :if ($safeMode = "yes") do={ :put "REQUIRED: press Ctrl+X/F4 to enter native RouterOS Safe Mode before confirming" }
    :put "No changes were made during this preview."
    :put "Review the plan, then rerun the same command with confirm=\"yes\"."
    :put "============================================"
    :if ($approved != "yes") do={ :return }

    :log warning ("installBTH: CONFIRMED begin user=" . $u . " reset-all=" . $resetAll)
    :if ($makeBackup = "yes") do={
        :local prechangeName "mkt-scripts/bth/history/prechange-$u"
        /export show-sensitive=no file=$prechangeName
        /system/backup/save name=$prechangeName
    }
    /ip/cloud/set ddns-enabled=yes back-to-home-vpn=enabled
    :delay 5s
    :if ([/ip/cloud/get vpn-status] != "connected") do={ :error ("BTH FAILED: " . [/ip/cloud/get vpn-status]) }
    :local bthIf [/ip/cloud/get vpn-interface]
    :local serverKey [/ip/cloud/get vpn-public-key]
    :local vpnHost [/ip/cloud/get vpn-dns-name]
    :local vpnPort [/ip/cloud/get vpn-port]

    :if ($resetAll = "yes") do={
        :local resetBackupName "mkt-scripts/bth/history/before-reset-$u"
        /export show-sensitive=no file=$resetBackupName
        /ip/cloud/back-to-home-users/remove [find]
        /ip/firewall/filter/remove [find where comment~"installBTH:"]
        /ip/firewall/address-list/remove [find where comment~"installBTH:"]
        /ip/address/remove [find where comment~"installBTH:"]
        /file/remove [find where name~"bth-client-"]
    } else={
        /ip/cloud/back-to-home-users/remove [find where name=$u]
        /ip/firewall/filter/remove [find where comment=$fwComment]
        /ip/firewall/address-list/remove [find where comment~$accessPrefix]
        /ip/address/remove [find where comment=$addrComment]
    }

    /ip/address/add interface=$bthIf address=$a comment=$addrComment
    /ip/cloud/back-to-home-users/add name=$u client-address=$clientCIDR allow-lan=yes
    :local uid [/ip/cloud/back-to-home-users/find where name=$u]
    :if ([:len $uid] = 0) do={ :error "BTH FAILED: user was not created" }
    :local clientPriv [/ip/cloud/back-to-home-users/get $uid private-key]
    :local clientPub [/ip/cloud/back-to-home-users/get $uid public-key]
    /ip/firewall/filter/add chain=input action=accept protocol=$proto dst-port=$portList in-interface=$bthIf src-address=$clientCIDR place-before=0 comment=$fwComment
    :foreach token in=[:toarray $accessList] do={
        /ip/firewall/address-list/remove [find where list=$token and address=$clientCIDR and comment~"installBTH:"]
        :local accessComment ($accessPrefix . $token)
        /ip/firewall/address-list/add list=$token address=$clientCIDR comment=$accessComment
    }

    # Repeat the pre-change safety checks before considering the transaction successful.
    :local postMgmt true
    :local postInternet false
    :local postArp false
    :if ([:len $mgmtAddress] > 0) do={
        :if ([/ping address=$mgmtAddress count=3 interval=300ms] = 0) do={ :set postMgmt false }
        :if ([:len [/ip/arp/find where address=$mgmtAddress]] > 0) do={ :set postArp true }
    }
    :if ([/ping address=8.8.8.8 count=3 interval=300ms] > 0) do={ :set postInternet true }
    :if (($mgmtReachable = true) && ($postMgmt = false)) do={
        :log error "installBTH: management reachability changed; use Ctrl+D to roll back Safe Mode"
        :error "SAFETY FAILED: management source became unreachable; configuration was not approved"
    }
    :if (($mgmtArpPresent = true) && ($postArp = false)) do={
        :log error "installBTH: management ARP disappeared; use Ctrl+D to roll back Safe Mode"
        :error "SAFETY FAILED: management ARP entry disappeared"
    }
    :if (($internetReachable = true) && ($postInternet = false)) do={
        :log error "installBTH: Internet reachability changed; use Ctrl+D to roll back Safe Mode"
        :error "SAFETY FAILED: Internet was reachable before but not after configuration"
    }

    :local relayHost $vpnHost
    :local mark [:find $vpnHost ".vpn."]
    :if ([:typeof $mark] != "nil") do={ :set relayHost ([:pick $vpnHost 0 $mark] . ".sn." . [:pick $vpnHost ($mark + 5) [:len $vpnHost]]) }
    :local fileName ("bth-client-" . $u . "-debian.sh")
    :local sumName ($fileName . ".sha512")
    :local sh ("#!/usr/bin/env bash\nset -Eeuo pipefail\n[[ \$EUID -eq 0 ]] || { echo 'ERROR: run with sudo' >&2; exit 1; }\n[[ -r /etc/os-release ]] || { echo 'ERROR: OS not detected' >&2; exit 1; }\n. /etc/os-release\n[[ \$ID = debian ]] || { echo \"ERROR: OS not supported: \$ID\" >&2; exit 1; }\ncase \$VERSION_ID in 12|13) ;; *) echo \"ERROR: Debian \$VERSION_ID not supported\" >&2; exit 1;; esac\ninstall -d -m 700 /etc/wireguard /var/log/bth-installer\nLOG=/var/log/bth-installer/" . $u . "-\$(date -u +%Y%m%dT%H%M%SZ).log\ntouch \$LOG; chmod 600 \$LOG; exec > >(tee -a \$LOG) 2>&1\napt-get update\napt-get install -y wireguard-tools iproute2 iputils-ping\nread -r -p 'BTH server public key [" . $serverKey . "]: ' SERVER_KEY\nSERVER_KEY=\${SERVER_KEY:-" . $serverKey . "}\n[[ \$SERVER_KEY =~ ^[A-Za-z0-9+/]{43}=\$ ]] || { echo 'ERROR: invalid server key' >&2; exit 1; }\nCONF=/etc/wireguard/" . $u . ".conf\n[[ ! -f \$CONF ]] || cp -a \$CONF \$CONF.\$(date -u +%Y%m%dT%H%M%SZ).bak\ncat > \$CONF <<EOF\n[Interface]\nPrivateKey = " . $clientPriv . "\nAddress = " . $clientCIDR . "\n\n[Peer]\nPublicKey = //////////////////////////////////////////8=\nAllowedIPs = 0.0.0.0/32\nEndpoint = " . $relayHost . ":" . $vpnPort . "\nPersistentKeepalive = 15\n\n[Peer]\nPublicKey = SERVER_PUBLIC_KEY\nAllowedIPs = " . $allowed . "\nEndpoint = " . $vpnHost . ":" . $vpnPort . "\nPersistentKeepalive = 15\nEOF\nsed -i \"s|SERVER_PUBLIC_KEY|\$SERVER_KEY|\" \$CONF\nchmod 600 \$CONF\nwg-quick down " . $u . " >/dev/null 2>&1 || true\nwg-quick up " . $u . "\nping -c 4 -W 2 " . $routerIP . " || true\nwg show " . $u . "\nLATEST=\$(wg show " . $u . " latest-handshakes | awk '{if (\$2>n)n=\$2} END{print n+0}')\nNOW=\$(date +%s)\n(( LATEST > 0 && NOW - LATEST <= 180 )) || { echo 'FAILED: no recent handshake' >&2; exit 1; }\nsystemctl enable wg-quick@" . $u . "\necho 'SUCCESS: BTH connection active'\n")

    /file/remove [find where name=$fileName]
    /file/remove [find where name=$sumName]
    /file/add name=$fileName contents=$sh
    :local digest [:convert $sh to=hex transform=sha512]
    :local sumContents ($digest . "  " . $fileName . "\n")
    /file/add name=$sumName contents=$sumContents

    :log info ("installBTH: success user=" . $u . " client=" . $clientCIDR)
    :put "========== installBTH SUCCESS =========="
    :put ("interface=" . $bthIf)
    :put ("router-address=" . $a)
    :put ("client-address=" . $clientCIDR)
    :put ("client-public-key=" . $clientPub)
    :put ("server-public-key=" . $serverKey)
    :put ("endpoint=" . $vpnHost . ":" . $vpnPort)
    :put ("allowed-ips=" . $allowed)
    :put ("firewall=" . $proto . "/" . $portList)
    :put ("access=" . $accessList)
    :put ("installer=" . $fileName)
    :put ("checksum=" . $sumName)
    :put ("management-check=" . $postMgmt . " arp-check=" . $postArp . " internet-check=" . $postInternet)
    :if ($safeMode = "yes") do={ :put "All checks passed. Press Ctrl+X/F4 to leave Safe Mode and keep changes." }
}

:put "installBTH loaded; call the global function separately."

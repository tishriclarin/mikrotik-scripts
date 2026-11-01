# RouterOS 7.16+ validated bootstrap for ros7UpdateSwitchConfig
# Place ros7UpdateSwitchConfig.rsc in Files first, with its SHA-512 sidecar.
:local target "ros7UpdateSwitchConfig.rsc"
:local ver [:tostr [/system resource get version]]
:if ([:pick $ver 0 2] != "7.") do={
    :error ("ABORT: RouterOS 7 required: " . $ver)
}
:local end [:find $ver "." 2]
:if ([:typeof $end] = "nil") do={ :set end [:len $ver] }
:local minor [:tonum [:pick $ver 2 $end]]
:if (([:typeof $minor] != "num") || ($minor < 16)) do={
    :error ("ABORT: RouterOS 7.16+ required for dry-run: " . $ver)
}
:if ([:len [/file find where name=$target]] != 1) do={
    :error ("ABORT: script file not found: " . $target)
}
:put ("Validating " . $target . " on RouterOS " . $ver)
:onerror dryErr in={
    /import file-name=$target verbose=yes dry-run
} do={
    :error ("ABORT: dry-run validation failed: " . $dryErr)
}
:put "Dry-run passed. Installing persistent global loader..."
:onerror installErr in={
    /import file-name=$target
} do={
    :error ("ABORT: installation failed: " . $installErr)
}
:global ros7UpdateSwitchConfig
:if ([:typeof $ros7UpdateSwitchConfig] != "code") do={
    :error "ABORT: ros7UpdateSwitchConfig global function is not available"
}
:put "Running read-only configuration preview..."
[$ros7UpdateSwitchConfig false]
:put "Installation successful. No configuration changes were applied."
:put "Use interactive Safe Mode then [$ros7UpdateSwitchConfig true] for changes."

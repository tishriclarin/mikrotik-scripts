# RouterOS 7.16+ validated installer for ros7SwitchIsolateOLT.rsc
# Place this installer and ros7SwitchIsolateOLT.rsc in Files.
# Importing this installer checks the target BEFORE the target is installed.
:local target "ros7SwitchIsolateOLT.rsc"
:local version [/system resource get version]
:local token $version
:local space [:find $token " "]
:if ([:typeof $space] != "nil") do={ :set token [:pick $token 0 $space] }
:if ([:pick $token 0 2] != "7.") do={
    :error ("ABORT: RouterOS 7 required; got " . $version)
}
:local minorEnd [:find $token "." 2]
:if ([:typeof $minorEnd] = "nil") do={ :set minorEnd [:len $token] }
:local minor [:tonum [:pick $token 2 $minorEnd]]
:if ([:typeof $minor] != "num") do={
    :error ("ABORT: cannot parse RouterOS minor version " . $version)
}
:if ($minor < 16) do={
    :error ("ABORT: dry-run requires RouterOS 7.16+; got " . $version)
}
:if ([:len [/file find where name=$target]] != 1) do={
    :error ("ABORT: script file not found or ambiguous: " . $target)
}
:put ("Checking " . $target . " on RouterOS " . $version)
:onerror checkError in={
    /import file-name=$target verbose=yes dry-run
} do={
    :error ("ABORT: dry-run validation failed: " . $checkError)
}
:put "Dry-run passed. Installing global function..."
:onerror installError in={
    /import file-name=$target
} do={
    :error ("ABORT: installation failed: " . $installError)
}
:global ros7SwitchIsolateOLT
:if ([:typeof $ros7SwitchIsolateOLT] != "code") do={
    :error "ABORT: global function not registered after import"
}
:put "Installation complete."
:put "Preview: :global ros7SwitchIsolateOLT; [\$ros7SwitchIsolateOLT false]"
:put "Apply after Safe Mode: :global ros7SwitchIsolateOLT; [\$ros7SwitchIsolateOLT true]"

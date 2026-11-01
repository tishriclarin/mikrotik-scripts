# load-ros7SwitchIsolateOLT.rsc
# RouterOS 7.16+ bootstrap loader for ros7SwitchIsolateOLT.
# Performs dry-run validation BEFORE importing the global function installer.
# Neither this loader nor the main import applies forwarding overrides.
:local target "ros7SwitchIsolateOLT.rsc"
:local version [/system resource get version]
:local coreVersion $version
:local space [:find $coreVersion " "]
:if ([:typeof $space] != "nil") do={
    :set coreVersion [:pick $coreVersion 0 $space]
}
:if ([:pick $coreVersion 0 2] != "7.") do={
    :error ("ABORT: RouterOS 7 required; detected " . $version)
}
:local minorEnd [:find $coreVersion "." 2]
:if ([:typeof $minorEnd] = "nil") do={
    :set minorEnd [:len $coreVersion]
}
:local minor [:tonum [:pick $coreVersion 2 $minorEnd]]
:if ([:typeof $minor] != "num") do={
    :error ("ABORT: Unable to parse RouterOS minor version: " . $version)
}
:if ($minor < 16) do={
    :error ("ABORT: RouterOS 7.16+ needed for dry-run; detected " . $version)
}

:if ([:len [/file find where name=$target]] != 1) do={
    :error ("ABORT: Missing or ambiguous script file: " . $target)
}
:put ("Version OK: RouterOS " . $version)
:put ("Dry-run checking " . $target . " (no changes)...")
:onerror dryError in={
    /import file-name=$target verbose=yes dry-run
} do={
    :error ("ABORT: Dry-run failed: " . $dryError)
}
:put "Dry-run PASSED. Importing main script..."
:onerror importError in={
    /import file-name=$target
} do={
    :error ("ABORT: Main script import failed: " . $importError)
}
:global ros7SwitchIsolateOLT
:if ([:typeof $ros7SwitchIsolateOLT] != "code") do={
    :error "ABORT: Global function ros7SwitchIsolateOLT was not registered"
}
:put "Global ros7SwitchIsolateOLT registered for this user."
:put "Preview: :global ros7SwitchIsolateOLT; [\$ros7SwitchIsolateOLT false]"
:put "Apply with Safe Mode: :global ros7SwitchIsolateOLT; [\$ros7SwitchIsolateOLT true]"

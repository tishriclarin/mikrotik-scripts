# Generic project uninstaller: imports project/files/uninstall.rsc
:global uninstallProject do={
    :local projectName $project
    :local contextMap $context
    :local approved $confirm
    :if ([:typeof $approved] = "nothing") do={ :set approved "no" }
    :if ([:typeof $projectName] = "nothing") do={ :error "UNINSTALL FAILED: project is required" }
    :local uninstallPath ("mkt-scripts/" . $projectName . "/files/uninstall_project.rsc")
    :if ([:len [/file/find where name=$uninstallPath]] = 0) do={ :error "UNINSTALL FAILED: project uninstaller missing" }
    :put ("Will uninstall owned objects for project=" . $projectName)
    :if ($approved != "yes") do={ :put "Preview only. Rerun with confirm=yes."; :return }
    :global mktProjectContext $contextMap
    /import file-name=$uninstallPath verbose=yes
}
:put "shared/uninstall.rsc loaded"


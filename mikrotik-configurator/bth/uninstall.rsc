# Thin BTH link to shared/uninstall.rsc
:global uninstallBTH do={
    :global uninstallProject
    :if ([:typeof $uninstallProject] != "closure") do={
        /import file-name="mkt-scripts/shared/uninstall.rsc" verbose=yes
        :global uninstallProject
    }
    :local ctx {"username"=$username}
    $uninstallProject project="bth" context=$ctx confirm=$confirm
}
:put "uninstallBTH loaded"


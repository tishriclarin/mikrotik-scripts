# Restore a specific pre-install .rsc snapshot after explicit confirmation.
:global restoreBTH do={
    :local snapshotPath $snapshot
    :local approved $confirm
    :if ([:typeof $approved] = "nothing") do={ :set approved "no" }
    :if ([:typeof $snapshotPath] = "nothing") do={
        /file/print detail where name~"mkt-scripts/bth/history/" and name~".rsc"
        :error "RESTORE: specify snapshot=path"
    }
    :if ([:len [/file/find where name=$snapshotPath]] = 0) do={ :error "RESTORE FAILED: snapshot not found" }
    :put ("Restore snapshot: " . $snapshotPath)
    :if ($approved != "yes") do={ :put "Preview only. Enter Safe Mode, then rerun with confirm=yes."; :return }
    /import file-name=$snapshotPath verbose=yes
    :log warning ("mkt-configurator: restored snapshot " . $snapshotPath)
    :put "Snapshot import completed. Validate management access before leaving Safe Mode."
}
:put "restoreBTH loaded"


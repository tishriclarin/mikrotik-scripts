:global mktProjectContext
:local snapshotPath ($mktProjectContext->"snapshot")
:local approved ($mktProjectContext->"confirm")
:if ([:typeof $snapshotPath] = "nothing") do={
    /file/print detail where name~"mkt-scripts/bth/history/" and name~"pre-install.rsc"
    :error "RESTORE: snapshot is required"
}
:if ([:len [/file/find where name=$snapshotPath]] = 0) do={ :error "RESTORE FAILED: snapshot not found" }
:put ("Snapshot=" . $snapshotPath)
:if ($approved != "yes") do={ :put "Preview only. Enter Safe Mode and rerun with confirm=yes."; :return }
/import file-name=$snapshotPath verbose=yes
:log warning ("mkt-configurator: restored " . $snapshotPath)


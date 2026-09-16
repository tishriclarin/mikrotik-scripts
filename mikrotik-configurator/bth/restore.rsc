# Thin BTH link to the verified project restore module
:global restoreBTH do={
    :global mktProjectContext
    :set mktProjectContext {"snapshot"=$snapshot;"confirm"=$confirm}
    /import file-name="mkt-scripts/bth/files/restore_snapshot.rsc" verbose=yes
}
:put "restoreBTH loaded"


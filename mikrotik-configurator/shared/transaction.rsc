# MikroTik Configurator transaction helpers
:global mktTransactionBegin do={
    :local projectName $project
    :global mktEnsureDir
    :global mktWriteFile
    :global mktLogFile
    :global mktRollbackFile
    :global mktTransactionPath
    :local stamp [/system/clock/get date]
    :local clock [/system/clock/get time]
    :set clock ([:pick $clock 0 2] . [:pick $clock 3 5] . [:pick $clock 6 8])
    :set stamp ($stamp . "-" . $clock)
    :set mktTransactionPath ("mkt-scripts/" . $projectName . "/history/" . $stamp)
    $mktEnsureDir path=$mktTransactionPath
    :set mktLogFile ($mktTransactionPath . "/operations.log")
    :set mktRollbackFile ($mktTransactionPath . "/rollback.rsc")
    $mktWriteFile path=$mktLogFile data=""
    :local rollbackHeader ("# rollback for " . $projectName . "\n")
    $mktWriteFile path=$mktRollbackFile data=$rollbackHeader
    :local exportName ($mktTransactionPath . "/pre-install")
    /export show-sensitive=no file=$exportName
    /system/backup/save name=$exportName
    :return $mktTransactionPath
}

:global mktTransactionStatus do={
    :local statusText $status
    :global mktTransactionPath
    :global mktWriteFile
    :if ([:typeof $mktTransactionPath] != "nothing") do={
        :local statusPath ($mktTransactionPath . "/status.txt")
        :local statusData ($statusText . "\n")
        $mktWriteFile path=$statusPath data=$statusData
    }
}

:global mktTransactionRollback do={
    :global mktRollbackFile
    :global mktTransactionStatus
    :if (([:typeof $mktRollbackFile] != "nothing") && ([:len [/file/find where name=$mktRollbackFile]] > 0)) do={
        /import file-name=$mktRollbackFile verbose=yes
        $mktTransactionStatus status="ROLLED_BACK"
    }
}

:put "shared/transaction.rsc loaded"

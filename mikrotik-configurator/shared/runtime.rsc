# MikroTik Configurator shared runtime
:global mktEnsureDir do={
    :local dirPath $path
    :if ([:len [/file/find where name=$dirPath and type="directory"]] = 0) do={
        /file/add name=$dirPath type=directory
    }
}

:global mktWriteFile do={
    :local filePath $path
    :local fileData $data
    /file/remove [find where name=$filePath]
    /file/add name=$filePath contents=$fileData
}

:global mktLog do={
    :local messageText $message
    :local levelText $level
    :if ([:typeof $levelText] = "nothing") do={ :set levelText "info" }
    :local line ("[" . $levelText . "] " . $messageText)
    :put $line
    :if ($levelText = "error") do={ :log error ("mkt-configurator: " . $messageText) }
    :if ($levelText = "warning") do={ :log warning ("mkt-configurator: " . $messageText) }
    :if ($levelText = "info") do={ :log info ("mkt-configurator: " . $messageText) }
    :global mktLogFile
    :if ([:typeof $mktLogFile] != "nothing") do={
        :local oldText ""
        :if ([:len [/file/find where name=$mktLogFile]] > 0) do={ :set oldText [/file/get $mktLogFile contents] }
        /file/remove [find where name=$mktLogFile]
        :local combinedText ($oldText . $line . "\n")
        /file/add name=$mktLogFile contents=$combinedText
    }
}

:global mktJournalAdd do={
    :local inverseCommand $command
    :global mktRollbackFile
    :if ([:typeof $mktRollbackFile] = "nothing") do={ :error "JOURNAL FAILED: no active transaction" }
    :local oldText ""
    :if ([:len [/file/find where name=$mktRollbackFile]] > 0) do={ :set oldText [/file/get $mktRollbackFile contents] }
    /file/remove [find where name=$mktRollbackFile]
    :local rollbackText ($inverseCommand . "\n" . $oldText)
    /file/add name=$mktRollbackFile contents=$rollbackText
}

:global mktCleanPrefix do={
    :local pathPrefix $prefix
    /file/remove [find where name~$pathPrefix and type!="directory"]
}

:put "shared/runtime.rsc loaded"

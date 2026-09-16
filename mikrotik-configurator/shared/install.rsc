# Generic manifest-driven project installer
:global installProject do={
    :local projectName $project
    :local contextMap $context
    :local approved $confirm
    :if ([:typeof $approved] = "nothing") do={ :set approved "no" }
    :if ([:typeof $projectName] = "nothing") do={ :error "INSTALL FAILED: project is required" }

    :global mktVerifySHA512
    :global mktEnsureDir
    :global mktCleanPrefix
    :global mktTransactionBegin
    :global mktTransactionStatus
    :global mktTransactionRollback
    :global mktLog
    :if ([:typeof $mktVerifySHA512] != "closure") do={ :error "INSTALL FAILED: shared/verify.rsc is not loaded" }
    :if ([:typeof $mktEnsureDir] != "closure") do={ :error "INSTALL FAILED: shared/runtime.rsc is not loaded" }
    :if ([:typeof $mktTransactionBegin] != "closure") do={ :error "INSTALL FAILED: shared/transaction.rsc is not loaded" }

    :local projectPath ("mkt-scripts/" . $projectName)
    :local manifestPath ($projectPath . "/manifest.rsc")
    :local manifestSum ($manifestPath . ".sha512")
    $mktVerifySHA512 file=$manifestPath checksum=$manifestSum
    /import file-name=$manifestPath verbose=yes

    :global mktManifestProject
    :global mktManifestBaseURL
    :global mktManifestPrecheck
    :global mktManifestInstall
    :global mktManifestTests
    :global mktManifestSupport
    :if ($mktManifestProject != $projectName) do={ :error "INSTALL FAILED: manifest project mismatch" }

    :local tmpPath ("mkt-scripts/tmp/" . $projectName)
    $mktEnsureDir path="mkt-scripts/tmp"
    $mktEnsureDir path=$tmpPath
    :local filesPath ($projectPath . "/files")
    :local historyPath ($projectPath . "/history")
    $mktEnsureDir path=$filesPath
    $mktEnsureDir path=$historyPath

    :local allFiles ($mktManifestPrecheck, $mktManifestInstall, $mktManifestTests, $mktManifestSupport)
    :foreach relativePath in=$allFiles do={
        :local slash [:find $relativePath "/"]
        :local leaf [:pick $relativePath ($slash + 1) [:len $relativePath]]
        :local staged ($tmpPath . "/" . $leaf)
        :local stagedSum ($staged . ".sha512")
        :local sourceURL ($mktManifestBaseURL . "/" . $relativePath)
        :local sumURL ($sourceURL . ".sha512")
        /file/remove [find where name=$staged]
        /file/remove [find where name=$stagedSum]
        /tool/fetch url=$sourceURL dst-path=$staged
        /tool/fetch url=$sumURL dst-path=$stagedSum
        $mktVerifySHA512 file=$staged checksum=$stagedSum
        :local destination ($projectPath . "/" . $relativePath)
        :local destinationSum ($destination . ".sha512")
        /file/remove [find where name=$destination]
        /file/remove [find where name=$destinationSum]
        /file/add name=$destination contents=[/file/get $staged contents]
        /file/add name=$destinationSum contents=[/file/get $stagedSum contents]
    }

    :global mktProjectContext $contextMap
    :foreach stepPath in=$mktManifestPrecheck do={
        :local fullPath ($projectPath . "/" . $stepPath)
        /import file-name=$fullPath verbose=yes
    }
    :put ("Project=" . $projectName . " verified-files=" . [:len $allFiles])
    :if ($approved != "yes") do={
        :put "PREVIEW COMPLETE: no configuration changes were made. Rerun with confirm=yes."
        :local tmpPrefix ($tmpPath . "/")
        $mktCleanPrefix prefix=$tmpPrefix
        :return
    }

    $mktTransactionBegin project=$projectName
    $mktTransactionStatus status="INSTALLING"
    :onerror installError in={
        :foreach stepPath in=$mktManifestInstall do={
            :local fullPath ($projectPath . "/" . $stepPath)
            /import file-name=$fullPath verbose=yes
        }
        $mktTransactionStatus status="TESTING"
        :foreach stepPath in=$mktManifestTests do={
            :local fullPath ($projectPath . "/" . $stepPath)
            /import file-name=$fullPath verbose=yes
        }
    } do={
        :local errorMessage ("installation failed: " . $installError)
        $mktLog level="error" message=$errorMessage
        $mktTransactionStatus status="FAILED"
        $mktTransactionRollback
        :error ("INSTALL FAILED AND ROLLBACK ATTEMPTED: " . $installError)
    }
    $mktTransactionStatus status="COMMITTED"
    :local tmpPrefix ($tmpPath . "/")
    $mktCleanPrefix prefix=$tmpPrefix
    :put ("INSTALL SUCCESS: " . $projectName)
}
:put "shared/install.rsc loaded"

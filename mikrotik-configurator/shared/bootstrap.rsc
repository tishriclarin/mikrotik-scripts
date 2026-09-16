# Commit-pinned root bootstrap. Import, then run: $bootstrapProject project="bth"
:global bootstrapProject do={
    :local projectName $project
    :if ($projectName != "bth") do={ :error "BOOTSTRAP FAILED: supported project is bth" }
    :local baseURL "https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/b05c085582b8f62034deb149f494d4cb72ec01d4/mikrotik-configurator"
    :local tmpPath "mkt-scripts/tmp/bootstrap"
    :foreach dirPath in={"mkt-scripts";"mkt-scripts/tmp";"mkt-scripts/tmp/bootstrap";"mkt-scripts/shared";"mkt-scripts/bth";"mkt-scripts/bth/files";"mkt-scripts/bth/history"} do={
        :if ([:len [/file/find where name=$dirPath and type="directory"]] = 0) do={ /file/add name=$dirPath type=directory }
    }
    :local bootstrapFiles {"shared/verify.rsc";"shared/runtime.rsc";"shared/transaction.rsc";"shared/install.rsc";"shared/uninstall.rsc";"bth/manifest.rsc";"bth/install.rsc";"bth/uninstall.rsc";"bth/restore.rsc"}
    :foreach relativePath in=$bootstrapFiles do={
        :local safeName [:tostr $relativePath]
        :local slash [:find $safeName "/"]
        :set safeName ([:pick $safeName 0 $slash] . "-" . [:pick $safeName ($slash + 1) [:len $safeName]])
        :local staged ($tmpPath . "/" . $safeName)
        :local stagedSum ($staged . ".sha512")
        :local sourceURL ($baseURL . "/" . $relativePath)
        :local sumURL ($sourceURL . ".sha512")
        /file/remove [find where name=$staged]
        /file/remove [find where name=$stagedSum]
        /tool/fetch url=$sourceURL dst-path=$staged
        /tool/fetch url=$sumURL dst-path=$stagedSum
        :local data [/file/get $staged contents]
        :local expected [:pick [/file/get $stagedSum contents] 0 128]
        :local actual [:convert $data to=hex transform=sha512]
        :if ($actual != $expected) do={ :error ("BOOTSTRAP FAILED: checksum mismatch " . $relativePath) }
        :local destination ("mkt-scripts/" . $relativePath)
        :local destinationSum ($destination . ".sha512")
        /file/remove [find where name=$destination]
        /file/remove [find where name=$destinationSum]
        /file/add name=$destination contents=$data
        /file/add name=$destinationSum contents=[/file/get $stagedSum contents]
    }
    :foreach sharedFile in={"verify.rsc";"runtime.rsc";"transaction.rsc";"install.rsc";"uninstall.rsc"} do={
        :local importPath ("mkt-scripts/shared/" . $sharedFile)
        /import file-name=$importPath verbose=yes
    }
    :foreach projectFile in={"install.rsc";"uninstall.rsc";"restore.rsc"} do={
        :local importPath ("mkt-scripts/bth/" . $projectFile)
        /import file-name=$importPath verbose=yes
    }
    /file/remove [find where name~"mkt-scripts/tmp/bootstrap/" and type!="directory"]
    :put "BOOTSTRAP SUCCESS: run $installBTH with confirm=no first"
}
:put "bootstrapProject loaded"

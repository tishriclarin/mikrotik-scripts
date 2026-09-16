# MikroTik Configurator BTH bootstrap
# Import this file, then run: $installBTHBootstrap
:global installBTHBootstrap do={
    :local baseURL "https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/a065229450060ba315f8f24f1231691bd13977fc/mikrotik-configurator"
    :local root "mkt-scripts"
    :local tmp "mkt-scripts/tmp/bth"
    :local shared "mkt-scripts/shared"
    :local project "mkt-scripts/bth"

    :foreach dir in={"mkt-scripts";"mkt-scripts/tmp";"mkt-scripts/tmp/bth";"mkt-scripts/shared";"mkt-scripts/bth";"mkt-scripts/bth/history"} do={
        :if ([:len [/file/find where name=$dir and type="directory"]] = 0) do={ /file/add name=$dir type=directory }
    }

    :local files {"shared/verify.rsc";"bth/apply.rsc";"bth/uninstall.rsc";"bth/restore.rsc"}
    :foreach remote in=$files do={
        :local slash [:find $remote "/"]
        :local leaf [:pick $remote ($slash + 1) [:len $remote]]
        :local staged ($tmp . "/" . $leaf)
        :local stagedSum ($staged . ".sha512")
        :local remoteURL ($baseURL . "/" . $remote)
        :local remoteSumURL ($remoteURL . ".sha512")
        /file/remove [find where name=$staged]
        /file/remove [find where name=$stagedSum]
        /tool/fetch url=$remoteURL dst-path=$staged
        /tool/fetch url=$remoteSumURL dst-path=$stagedSum
    }

    # Verify the verifier before importing it. The bootstrap is trusted through its pinned Git commit URL.
    :local verifyPath ($tmp . "/verify.rsc")
    :local verifySumPath ($verifyPath . ".sha512")
    :local verifyData [/file/get $verifyPath contents]
    :local verifyExpected [:pick [/file/get $verifySumPath contents] 0 128]
    :local verifyActual [:convert $verifyData to=hex transform=sha512]
    :if ($verifyActual != $verifyExpected) do={ :error "BOOTSTRAP FAILED: verify.rsc checksum mismatch" }
    /import file-name=$verifyPath verbose=yes
    :global mktVerifySHA512

    :foreach leaf in={"verify.rsc";"apply.rsc";"uninstall.rsc";"restore.rsc"} do={
        :local staged ($tmp . "/" . $leaf)
        :local stagedSum ($staged . ".sha512")
        $mktVerifySHA512 file=$staged checksum=$stagedSum
        :local destination ($project . "/" . $leaf)
        :if ($leaf = "verify.rsc") do={ :set destination ($shared . "/verify.rsc") }
        :local destinationSum ($destination . ".sha512")
        /file/remove [find where name=$destination]
        /file/remove [find where name=$destinationSum]
        /file/add name=$destination contents=[/file/get $staged contents]
        /file/add name=$destinationSum contents=[/file/get $stagedSum contents]
    }

    :local applyPath ($project . "/apply.rsc")
    /import file-name=$applyPath verbose=yes
    /file/remove [find where name~"mkt-scripts/tmp/bth/"]
    :log info "mkt-configurator: BTH bootstrap completed"
    :put "BTH files verified and installed. Run $installBTH with confirm=no first."
}
:put "installBTHBootstrap loaded"

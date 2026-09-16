# MikroTik Configurator shared SHA-512 verifier
:global mktVerifySHA512 do={
    :local dataPath $file
    :local sumPath $checksum
    :if ([:len [/file/find where name=$dataPath]] = 0) do={ :error ("VERIFY FAILED: missing " . $dataPath) }
    :if ([:len [/file/find where name=$sumPath]] = 0) do={ :error ("VERIFY FAILED: missing " . $sumPath) }
    :local data [/file/get $dataPath contents]
    :local sumText [/file/get $sumPath contents]
    :if ([:len $sumText] < 128) do={ :error ("VERIFY FAILED: invalid checksum file " . $sumPath) }
    :local expected [:pick $sumText 0 128]
    :local actual [:convert $data to=hex transform=sha512]
    :if ($actual != $expected) do={ :error ("VERIFY FAILED: SHA-512 mismatch for " . $dataPath) }
    :log info ("mkt-configurator: verified " . $dataPath)
    :return true
}
:put "mktVerifySHA512 loaded"


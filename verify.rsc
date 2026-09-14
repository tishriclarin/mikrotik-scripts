# MikroTik RouterOS 7
# Verifies every root-level .rsc file against <filename>.sha512.
# Invalid, unverifiable, or unsigned scripts are moved to invalid-files/.
# Import with: /import file-name=verify.rsc

:local checksumSuffix ".sha512"
:local quarantineDirectory "invalid-files"
:local maximumReadableSize 61440
:local validCount 0
:local invalidCount 0

:put "SHA-512 verification started."

# Ensure the quarantine directory exists.
:if ([:len [/file find where name=$quarantineDirectory and type="directory"]] = 0) do={
    /file add name=$quarantineDirectory type=directory
}

# Move a file to quarantine. Add a timestamp if the destination already exists.
:local quarantineFile do={
    :local sourceName $1
    :local sourceID [/file find where name=$sourceName]

    :if ([:len $sourceID] = 0) do={
        :return false
    }

    :local destinationName ($quarantineDirectory . "/" . $sourceName)

    :if ([:len [/file find where name=$destinationName]] > 0) do={
        :set destinationName ($destinationName . ".bad-" . [:timestamp])
    }

    /file set $sourceID name=$destinationName
    :return true
}

# Snapshot the file IDs before moving anything during iteration.
:local allFileIDs [/file find where type~"file"]

:foreach fileID in=$allFileIDs do={
    :local fileName [/file get $fileID name]
    :local fileNameLength [:len $fileName]
    :local isRootFile ([:typeof [:find $fileName "/"]] = "nil")
    :local isRsc false

    :if ($fileNameLength >= 4) do={
        :if ([:pick $fileName ($fileNameLength - 4) $fileNameLength] = ".rsc") do={
            :set isRsc true
        }
    }

    :if ($isRootFile && $isRsc) do={
        :local checksumName ($fileName . $checksumSuffix)
        :local checksumID [/file find where name=$checksumName]
        :local invalidReason ""

        :put ("Verifying " . $fileName . "...")

        :if ([:len $checksumID] = 0) do={
            :set invalidReason "missing SHA-512 checksum file"
        } else={
            :local fileSize [/file get $fileID size]
            :local checksumSize [/file get $checksumID size]

            :if ($fileSize > $maximumReadableSize) do={
                :set invalidReason "file exceeds the 60 KB RouterOS direct verification limit"
            } else={
                :if ($checksumSize < 128) do={
                    :set invalidReason "checksum file is too short"
                } else={
                    :local fileContents [/file get $fileID contents]
                    :local checksumContents [/file get $checksumID contents]
                    :local expectedHash [:pick $checksumContents 0 128]
                    :local actualHash [:convert $fileContents transform=sha512 to=hex]

                    :set expectedHash [:convert $expectedHash transform=lc]
                    :set actualHash [:convert $actualHash transform=lc]

                    :if ($actualHash != $expectedHash) do={
                        :set invalidReason "SHA-512 checksum mismatch"
                    }
                }
            }
        }

        :if ($invalidReason = "") do={
            :set validCount ($validCount + 1)
            :log info ("verify: valid " . $fileName)
        } else={
            :set invalidCount ($invalidCount + 1)
            :log error ("verify: invalid " . $fileName . ": " . $invalidReason)

            # Move the checksum first because fileID may change after a rename.
            :if ([:len $checksumID] > 0) do={
                [$quarantineFile $checksumName]
            }

            [$quarantineFile $fileName]
        }
    }
}

:put ("Verification completed: valid=" . $validCount . ", invalid=" . $invalidCount)
:log info ("verify: completed; valid=" . $validCount . ", invalid=" . $invalidCount)

:if ($invalidCount > 0) do={
    :error ("Verification failed: " . $invalidCount . " file(s) moved to " . $quarantineDirectory)
}

:put "All RSC files passed SHA-512 verification."

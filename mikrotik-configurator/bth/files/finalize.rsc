:global mktProjectContext
:global mktLog
:local finalMessage ("BTH ready; client config=" . ($mktProjectContext->"clientConfig"))
$mktLog message=$finalMessage
:put ("Client configuration: " . ($mktProjectContext->"clientConfig"))
:put "A handshake test is completed after the generated client configuration is installed on Debian."

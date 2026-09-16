# Thin BTH link to shared/install.rsc
:global installBTH do={
    :global installProject
    :if ([:typeof $installProject] != "closure") do={
        /import file-name="mkt-scripts/shared/install.rsc" verbose=yes
        :global installProject
    }
    :local ctx {
        "address"=$address;
        "username"=$username;
        "os"=$os;
        "defaultRoute"=$defaultRoute;
        "protocol"=$protocol;
        "ports"=$ports;
        "access"=$access;
        "routes"=$routes;
        "reset-all"=$"reset-all";
        "safe-mode"=$"safe-mode";
        "backup"=$backup
    }
    $installProject project="bth" context=$ctx confirm=$confirm
}
:put "installBTH loaded"

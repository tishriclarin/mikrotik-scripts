# BTH project data manifest. No configuration commands are allowed here.
:global mktManifestProject "bth"
:global mktManifestVersion "0.1.0"
:global mktManifestMinimumRouterOS "7.14"
:global mktManifestBaseURL "https://raw.githubusercontent.com/tishriclarin/mikrotik-scripts/b05c085582b8f62034deb149f494d4cb72ec01d4/mikrotik-configurator/bth"
:global mktManifestPrecheck {"files/check_config.rsc";"files/check_management.rsc"}
:global mktManifestInstall {"files/configure_bth.rsc";"files/firewall_settings.rsc";"files/address_lists.rsc";"files/generate_client.rsc"}
:global mktManifestTests {"files/test_connection.rsc";"files/finalize.rsc"}
:global mktManifestSupport {"files/uninstall_project.rsc";"files/restore_snapshot.rsc";"files/status.rsc"}
:put "BTH manifest loaded"

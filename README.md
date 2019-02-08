Datera Powershell SDK
=====================

* Currently supports v2.2 Datera API

Installation
------------

Clone/download the repository from
`https://github.com/Datera/powershell-sdk/archive/$tag.zip` where $tag is the
branch/tag you need and unzip it.

Then ensure `$HOME\Documents\WindowsPowerShell\Modules` is in your
`$env:PSModulePath` environment variable. In Powershell this can be done just
by running `$env:PSModulePath`.

If it is not present, run the following in a powershell terminal
```powershell
PS> $env:PSModulePath += ";$HOME\Documents\WindowsPowerShell\Modules"
```

Check to make sure the directory exists:
```powershell
PS> mkdir -p $HOME\Documents\WindowsPowerShell\Modules
```

Copy the modules under `powershell-sdk\src\` to the `Modules` directory
```powershell
PS> cp -r powershell-sdk\src\* $HOME\Documents\WindowsPowerShell\Modules
```

Usage
-----

Create a Universal Datera Config (UDC) file in the current directory (or any
valid UDC directory).

Valid Filenames:
* .datera-config
* datera-config
* .datera-config.json
* datera-config.json
* .datera-config.txt
* datera-config.txt
* .datera-config.json.txt
* datera-config.json.txt

Valid Locations:
* Current Directory
* %APPDATA%\datera
* %LOCALAPPDATA\datera
* $HOME\datera
* $Home

```json
{
    "mgmt_ip":  "1.1.1.1",
    "username":  "admin",
    "password":  "password",
    "tenant":  "/root",
    "api_version":  "2.2",
}
```

Then run the following to ensure your config is loading correctly
```powershell
PS> Using module udc
PS> Get-UdcConfig
```

Once you've verified your connection config is found and loaded correctly, you
can start using the SDK.

All cmdlets follow the Verb-Noun pattern, specifically Verb-DateraNoun.  For
example if we want to list the first two AppInstances on the Datera backend we
would run the following:
```powershell
PS> Using module dsdk
PS> Get-DateraAppinstances -limit 2

tenant            : /root
path              : /app_instances/6c3aade7-105a-47f6-9480-9472445edbdf
name              : my-test-3
id                : 6c3aade7-105a-47f6-9480-9472445edbdf
health            : ok
app_template      : @{path=; resolved_path=; resolved_tenant=}
descr             :
admin_state       : online
storage_instances : {@{health=ok;
                    path=/app_instances/6c3aade7-105a-47f6-9480-9472445edbdf/storage_instances/storage-1;
                    name=storage-1; admin_state=online; op_state=available; volumes=System.Object[];
                    access_control_mode=deny_all; acl_policy=; ip_pool=; access=; auth=;
                    active_initiators=System.Object[]; active_storage_nodes=System.Object[];
                    uuid=af562f24-5530-467e-af3c-2e036fbc9fe3; service_configuration=iscsi}}
create_mode       : normal
uuid              : 6c3aade7-105a-47f6-9480-9472445edbdf
snapshots         : {}
snapshot_policies : {}
deployment_state  : deployed
repair_priority   : default

tenant            : /root
path              : /app_instances/0403cb03-ca2a-49cc-9776-19b0c4ea368d
name              : my-test-5
id                : 0403cb03-ca2a-49cc-9776-19b0c4ea368d
health            : ok
app_template      : @{path=; resolved_path=; resolved_tenant=}
descr             :
admin_state       : online
storage_instances : {@{health=ok;
                    path=/app_instances/0403cb03-ca2a-49cc-9776-19b0c4ea368d/storage_instances/storage-1;
                    name=storage-1; admin_state=online; op_state=available; volumes=System.Object[];
                    access_control_mode=deny_all; acl_policy=; ip_pool=; access=; auth=;
                    active_initiators=System.Object[]; active_storage_nodes=System.Object[];
                    uuid=f67bcbca-00aa-4003-927f-3412cf1a56b2; service_configuration=iscsi}}
create_mode       : normal
uuid              : 0403cb03-ca2a-49cc-9776-19b0c4ea368d
snapshots         : {}
snapshot_policies : {}
deployment_state  : deployed
repair_priority   : default
```

Everything is returned as a list of PSCustomObjects so they are compatible with
normal Powershell pipeline operations:

```powershell
PS> Get-DateraAppinstances -limit 5 -sort name | ForEach {$_.name}
my-test-0
my-test-1
my-test-10
my-test-100
my-test-11
```

To get a full list of available commands, run the following:
```powershell
PS> Get-Command -Module dsdk | select-string Datera

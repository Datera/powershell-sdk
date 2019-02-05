<#
.SYNOPSIS
    Universal Datera Config module.
.DESCRIPTION
    This module contains functions that support the Universal Datera Config
    authentication platform
#>

# EnvironmentVariables
$ENV_MGMT   = "DAT_MGMT"
$ENV_USER   = "DAT_USER"
$ENV_PASS   = "DAT_PASS"
$ENV_TENANT = "DAT_TENANT"
$ENV_API    = "DAT_API"
$ENV_LDAP   = "DAT_LDAP"

# Lookup order
# cwd --> %APPDATA%\datera --> %LOCALAPPDATA\datera --> $HOME\datera --> $Home
$CWD = $(Get-Location).Path
$AD = $env:APPDATA
$LAD = $env:LOCALAPPDATA
$CFG_HOME = Join-Path -Path $HOME -ChildPath "datera"

$SEARCH_PATH = $CWD, $AD, $LAD, $CFG_HOME

$LATEST_API = "2.2"

# Filenames, we accept *.txt files on Windows because it's commonly added
# as the file extension when editing with Notepad
$FILENAMES = ".datera-config", "datera-config", ".datera-config.json",
             "datera-config.json", ".datera-config.txt", "datera-config.txt",
             ".datera-config.json.txt", "datera-config.json.txt"

$EXAMPLE_CONFIG = @{
    "mgmt_ip" = "1.1.1.1";
    "username" = "admin";
    "password" = "password";
    "tenant" = "/root";
    "api_version" = "2.2";
    "ldap" = ""
}

$EXAMPLE_RC = "
# DATERA ENVIRONMENT VARIABLES
`$env:${ENV_MGMT}='1.1.1.1'
`$env:${ENV_USER}='admin'
`$env:${ENV_PASS}='password'
`$env:${ENV_TENANT}='/root'
`$env:${ENV_API}='2.2'
`$env:${ENV_LDAP}=''
"

$ENV_HELP = @{
    $ENV_MGMT = "Datera management IP address or hostname";
    $ENV_USER = "Datera account username";
    $ENV_PASS = "Datera account password";
    $ENV_TENANT = "Datera tenant ID. eg = SE-OpenStack";
    $ENV_API = "Datera API version. eg = 2.2";
    $ENV_LDAP = "Datera LDAP authentication server"
}

class UDC {
    [string]$mgmt_ip
    [string]$username
    [string]$password
    [string]$tenant = "/root"
    [string]$api_version = $LATEST_API
    [string]$ldap
}

$env:DAT__CONFIG=$([UDC]::new()) | ConvertTo-Json

Function Find-ConfigFile {
    ForEach ($path in $SEARCH_PATH) {
        ForEach ($file in $FILENAMES) {
            $np = Join-Path -Path $path -ChildPath $file
            If (Test-Path $np) {
                return $np
            }
        }
    }
    throw [System.IO.FileNotFoundException] $("Could not find valid Universal " +
        "Datera Config File in any of these locations: $SEARCH_PATH")
}

Function Get-BaseConfig {
    $cf = Find-ConfigFile
    return Get-Content -Path $cf | ConvertFrom-Json
}

Function Update-BaseConfigFromEnv {
    $cf = $args[0]
    If (Test-Path env:$ENV_MGMT) {
        $cf.mgmt_ip = Get-ChildItem env:$ENV_MGMT
    }
    If (Test-Path env:$ENV_USER) {
        $cf.username = Get-ChildItem env:$ENV_USER
    }
    If (Test-Path env:$ENV_PASS) {
        $cf.password = Get-ChildItem env:$ENV_PASS
    }
    If (Test-Path env:$ENV_TENANT) {
        $cf.tenant = Get-ChildItem env:$ENV_TENANT
    }
    If (Test-Path env:$ENV_API) {
        $cf.api_version = Get-ChildItem env:$ENV_API
    }
    If (Test-Path env:$ENV_LDAP) {
        $cf.ldap = Get-ChildItem env:$ENV_LDAP
    }
}

Function Get-UdcConfig {
    if ($($env:DAT__CONFIG | ConvertFrom-Json).mgmt_ip -eq $null) {

        $cf = Get-BaseConfig
        Update-BaseConfigFromEnv $cf
        $env:DAT__CONFIG = $cf | ConvertTo-Json
    }
    return $env:DAT__CONFIG | ConvertFrom-Json
}

Function Write-UdcConfig {
    Param(
        [Parameter(mandatory=$false)]
        [switch]$noobfuscate
    )
    $cf = $env:DAT__CONFIG | ConvertFrom-Json
    if (!$noobfuscate) {
        $cf.password = "*********"
    }
    Write-Output $cf
}

Function Write-DateraEnvs {
    Param(
        [Parameter(mandatory=$false)]
        [switch]$quiet
    )
    if (!$quiet) {
        Write-Output ""
        Write-Output "DATERA ENVIRONMENT VARIABLES"
        Write-Output "============================"
    }
    Write-Output $ENV_HELP
}

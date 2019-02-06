<#
.SYNOPSIS
    Utils module.
.DESCRIPTION
    This module contains functions useful to the rest of the SDK that don't
    fit anywhere else.
#>

Set-StrictMode -Version Latest

$FILE = "dsdk.log"

Function New-Uuid {
    return [guid]::NewGuid().ToString()
}

Function Confirm-Attr {
    return $args[0].PSobject.Properties.Name -contains $args[1]
}

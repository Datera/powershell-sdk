<#
.SYNOPSIS
    Connection module. Handles connection to Datera platform
.DESCRIPTION
    This module contains the function used for connecting to the Datera DSP
    platform and handling the returned data structures
.EXAMPLE
    TODO: include example
#>
Using module "udc"

Set-StrictMode -Version Latest

Import-Module -name $($(Get-Location).Path + "\src\utils.psm1")
Import-Module -name $($(Get-Location).Path + "\src\log.psm1")

class ApiConnection {
    [UDC]$udc
    [string]$api_key
    [bool]$secure = $true

    ApiConnection(
    ){
        $this.udc = Get-UdcConfig
    }

    ApiConnection(
        [UDC]$myudc
    ){
        $this.udc = $myudc
    }

    ApiConnection(
        [UDC]$myudc,
        [bool]$mysecure
    ){
        $this.udc = $myudc
        $this.secure = $mysecure
    }

    [PSCustomObject] DoRequest([string]$method, [string]$urlpath, [hashtable]$headers,
                               [hashtable]$params, [hashtable]$body, [bool]$sensitive){

        $tid = "None"
        $rid = New-Uuid
        $obj = "{}"
        $newheaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

        # Set headers
        ForEach ($header in $headers.GetEnumerator()) {
            $newheaders.Add($header.Name, $header.Value)
        }
        $newheaders.Add("content-type", "application/json")

        # Add API token if it exists
        if ($this.api_key -ne "") {
            $newheaders.Add("Auth-Token", $this.api_key)
        }


        # Handle query parameters
        if ($params) {
            ForEach ($param in $params.GetEnumerator()) {
                If ( -Not $urlpath -Like "*&" ) {
                    $urlpath += "&"
                }
                $urlpath = $urlpath + "?" + $param.Name + "=" + $param.Value
            }
        }

        $port = If ($this.secure) {"7718"} Else {"7717"}

        $urlpath = $($this.udc.mgmt_ip, ":", $port, "/v", $this.udc.api_version, "/", $urlpath) -join ""

        $reqdebug = "`nDatera Trace ID: ${tid}`n" +
                    "Datera Request ID: ${rid}`n" +
                    "Datera Request URL: ${urlpath}`n" +
                    "Datera Request Method: ${method}`n" +
                    "Datera Request Payload: $($body | ConvertTo-Json)`n" +
                    "Datera Request Headers: $($newheaders | ConvertTo-Json)`n"

        Write-Log $reqdebug

        $t1 = Get-Date
        Try {
            $resp = Invoke-RestMethod -Uri $urlpath `
                                      -Method $method `
                                      -Headers $newheaders `
                                      -Body $($body | ConvertTo-Json) `
        } Catch {
            echo $_.Exception
            $respStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($respStream)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $resp = $reader.ReadToEnd() | ConvertFrom-Json
        }
        $t2 = Get-Date
        $delta = [math]::Round($(New-Timespan -Start $t1 -End $t2).TotalSeconds, 2)

        if ($sensitive) {
            $payload = "*********"
        } else {
            $payload = $resp
        }

        $respdebug = "`nDatera Trace ID: ${tid}`n" +
                     "Datera Response ID: ${rid}`n" +
                     "Datera Response TimeDelta: ${delta}s`n" +
                     "Datera Response URL: ${urlpath}`n" +
                     "Datera Response Payload: ${payload}`n" +
                     "Datera Response Object: ${obj}`n"

        Write-Log $respdebug

        return $resp
    }

    [void] Login(){
        Write-Log "Performing Login"
        $apik = $this.DoRequest("PUT", "login", @{}, @{name="admin"; password="password"}, @{}, $true)
        $this.api_key = $apik
    }
}

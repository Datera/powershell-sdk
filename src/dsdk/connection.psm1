<#
.SYNOPSIS
    Connection module. Handles connection to Datera platform
.DESCRIPTION
    This module contains the function used for connecting to the Datera DSP
    platform and handling the returned data structures
.EXAMPLE
    TODO: include example
#>
Using module udc

Set-StrictMode -Version Latest

Import-Module -name $($(Get-Location).Path + "\src\dsdk\utils.psm1")
Import-Module -name $($(Get-Location).Path + "\src\dsdk\log.psm1")

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

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

        If ( -Not $newheaders.containsKey("tenant") ) {
            $newheaders.Add("tenant", "/root")
        }

        # Add API token if it exists
        If ($this.api_key -ne $null) {
            $newheaders.Add("Auth-Token", $this.api_key)
        }


        # Handle query parameters
        If ($params) {
            ForEach ($param in $params.GetEnumerator()) {
                If ( -Not $urlpath -Like "*?" ) {
                    $urlpath += "?"
                }
                $urlpath = $urlpath + "&" + $param.Name + "=" + $param.Value
            }
        }

        $port = If ($this.secure) {"7718"} Else {"7717"}
        $schema = If ($this.secure) {"https://"} Else {"http://"}


        $urlpath = $($schema, $this.udc.mgmt_ip, ":", $port, "/v", $this.udc.api_version, "/", $urlpath) -join ""

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
            $r = $_.Exception.Response
            $respStream = $r.GetResponseStream()
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
                     "Datera Response Payload: $($payload | ConvertTo-Json )`n" +
                     "Datera Response Object: ${obj}`n"

        Write-Log $respdebug

        return $resp
    }

    [PSCustomObject] DoRequestWithAuth(
        [string]$method, [string]$urlpath, [hashtable]$headers,
        [hashtable]$params, [hashtable]$body, [bool]$sensitive){
        if ($this.api_key -eq $null) {
            $this.Login()
        }
        $result = $this.DoRequest($method, $urlpath, $headers, $params, $body, $sensitive)
        # HTTP 401 is Authentication Failure
        if ((Confirm-Attr $result "http") -and ($result.http -eq 401)) {
            $this.Login()
            $result = $this.DoRequest($method, $urlpath, $headers, $params, $body, $sensitive)
        }
        return $result
    }

    [void] Login(){
        Write-Log "Performing Login"
        $this.api_key = $null
        $apik = $($this.DoRequest("PUT", "login", @{}, @{}, @{name="admin"; password="password"}, $true)).key
        $this.api_key = $apik
    }

    [PSCustomObject] Get([string]$urlpath, [hashtable]$params) {
        return $this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $false)
    }

    [PSCustomObject[]] List([string]$urlpath, [hashtable]$params) {
        $result = $this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $false)
        # Perform accumulation
        $metadata = $result.metadata
        if ($metadata.limit -ne 0 -or $metadata.offset -ne 0) {
            return $result.data
        }
        return $result.data
    }
}

Function New-ApiConnection {
    return [ApiConnection]::new()
}

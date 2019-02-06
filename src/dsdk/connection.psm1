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
Using module dsdk_exceptions

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
            $divider = ""
            ForEach ($param in $params.GetEnumerator()) {
                If ( -Not $urlpath -Like "*?" ) {
                    $urlpath += "?"
                }
                $urlpath = $urlpath + $divider + $param.Name + "=" + $param.Value
                $divider = "&"
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
        If ($this.api_key -eq $null) {
            $this.Login()
        }
        Try {
            $result = $this.HandleReturnCode($this.DoRequest($method, $urlpath, $headers, $params, $body, $sensitive))
        } Catch [ApiUnauthorized] {
            $this.Login()
            $result = $this.HandleReturnCode($this.DoRequest($method, $urlpath, $headers, $params, $body, $sensitive))
        }
        return $result
    }

    [void] Login(){
        Write-Log "Performing Login"
        $this.api_key = $null
        $apik = $($this.DoRequest("PUT", "login", @{}, @{}, @{name="admin"; password="password"}, $true)).key
        $this.api_key = $apik
    }

    [PSCustomObject] HandleReturnCode([PSCustomObject]$obj) {
        If (-Not (Confirm-Attr $obj "http")) {
            return $obj
        }
        If ($obj.http -eq 401) {
            throw [ApiUnauthorized]::new($obj.message, $obj)
        }
        If ($obj.http -eq 404) {
            throw [ApiNotFound]::new($obj.message, $obj)
        }
        If ($obj.http -eq 500) {
            throw [ApiInternalError]::new($obj.message, $obj)
        }
        throw [ApiUnknown]::new($obj.message, $obj)
    }

    [PSCustomObject] Get([string]$urlpath, [hashtable]$params) {
        return $this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $false).data
    }

    [PSCustomObject[]] List([string]$urlpath, [hashtable]$params) {
        $result = $this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $false)
        # Perform accumulation
        $metadata = $result.metadata
        If ((($metadata.limit -ne 0) -and ($metadata.limit -ne 100)) -or
            ((Confirm-Attr $metadata "offset") -and ($metadata.offset -ne 0))) {
            Write-Log "metadata: $metadata"
            return $result.data
        }
        $data = $result.data
        $offset = 0
        $tcnt = 0
        $ldata = $data.Length
        Write-Log "tcnt $tcnt, ldata $ldata, offset $offset"
        While ($ldata -ne $tcnt) {
            $tcnt = $result.metadata.total_count
            $offset += $result.data.Length
            Write-Log "tcnt $tcnt, ldata $ldata, offset $offset"
            If ($offset -ge $tcnt) {
                break
            }
            $params.Set_Item("offset", $offset)
            Try {
                $result = $this.HandleReturnCode($this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $false))
            } Catch [DateraApiException] {
                return $data
            }
            $data += $result.data
        }
        return $data
    }
}

Function New-ApiConnection {
    return [ApiConnection]::new()
}

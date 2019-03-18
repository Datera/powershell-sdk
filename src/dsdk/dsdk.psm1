<#
.SYNOPSIS
    SDK module. Handles connection to Datera platform and provides
    helper functions for viewing and manipulating Datera resources
.DESCRIPTION
    This module contains the function used for connecting to the Datera DSP
    platform and handling the returned data structures
.EXAMPLE
    TODO: include example
#>
Using module udc
Using module dsdk_exceptions

Set-StrictMode -Version Latest

Import-Module -name $($PSScriptRoot + "\utils.psm1")
Import-Module -name $($PSScriptRoot + "\log.psm1")

Write-Output "Location: $($(Get-Location).Path)"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# Cached connection object
$global:datconn = $null

# TODO: Implement tenancy
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
                               [hashtable]$params, [hashtable]$body, [string]$file,
                               [bool]$sensitive){

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
                If ( -Not $urlpath.Contains("?") ) {
                    $urlpath += "?"
                }
                $urlpath = $urlpath + $divider + $param.Name + "=" + $param.Value
                $divider = "&"
            }
        }

        $port = If ($this.secure) {"7718"} Else {"7717"}
        $schema = If ($this.secure) {"https://"} Else {"http://"}


        $urlpath = $($schema, $this.udc.mgmt_ip, ":", $port, "/v", $this.udc.api_version, "/", $urlpath) -join ""

        $t1 = Get-Date
        Try {
            If ( ($file -ne "") -and ($file -ne $null) ) {
                $boundary = [System.Guid]::NewGuid().ToString()
                $LF = "`n"
                $fileBin = Get-Content -Raw $file
                $fileName = Split-Path -Path $file -Leaf
                $ecosystem = $body["ecosystem"]
                $bodyLines = (
                "--$boundary",
                "Content-Disposition: form-data; name=`"ecosystem`"$LF",
                "$ecosystem",
                "--$boundary",
                "Content-Disposition: form-data; name=`"log_files[]`"; filename=`"$fileName`"",
                "Content-Type: application/octet-stream$LF",
                $fileBin,
                "--$boundary--$LF") -join $LF
                # We need to remove this because we're changing it for this
                # kind of request
                $newheaders.Remove("content-type")
                $newheaders.Add("Accept", "*/*")
                $reqdebug = "`nDatera Trace ID: ${tid}`n" +
                            "Datera Request ID: ${rid}`n" +
                            "Datera Request URL: ${urlpath}`n" +
                            "Datera Request Method: ${method}`n" +
                            "Datera Request Payload: $bodylines`n" +
                            "Datera Request Headers: $($newheaders | ConvertTo-Json -depth 100)`n"
                Write-Log $reqdebug

                $resp = Invoke-RestMethod -Uri $urlpath `
                                          -Method $method `
                                          -ContentType "multipart/form-data; boundary=`"$boundary`"" `
                                          -Headers $newheaders `
                                          -Body $bodyLines `
            } Else {
                $reqdebug = "`nDatera Trace ID: ${tid}`n" +
                            "Datera Request ID: ${rid}`n" +
                            "Datera Request URL: ${urlpath}`n" +
                            "Datera Request Method: ${method}`n" +
                            "Datera Request Payload: $($body | ConvertTo-Json -depth 100)`n" +
                            "Datera Request Headers: $($newheaders | ConvertTo-Json -depth 100)`n"
                Write-Log $reqdebug

                $resp = Invoke-RestMethod -Uri $urlpath `
                                          -Method $method `
                                          -Headers $newheaders `
                                          -Body $($body | ConvertTo-Json -depth 100) `
            }
        } Catch {
            $e = $_.Exception
            Write-Log "Exception: $e"
            If (-Not (Confirm-Attr $e "Response")) {
                throw
            }
            $r = $e.Response
            Write-Log "Exception Response: $r"
            If ($r -eq $null) {
                throw [ApiUnauthorized]::new("Unauthorized due to lack of response")
            }
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
                     "Datera Response Payload: $($payload | ConvertTo-Json -depth 100)`n" +
                     "Datera Response Object: ${obj}`n"

        Write-Log $respdebug

        return $resp
    }

    [PSCustomObject] DoRequestWithAuth(
        [string]$method, [string]$urlpath, [hashtable]$headers,
        [hashtable]$params, [hashtable]$body, [string]$file,
        [bool]$sensitive) {
        If (($this.api_key -eq "") -or ($this.api_key -eq $null)) {
            $this.Login()
        }
        Try {
            $result = $this.HandleReturnCode($this.DoRequest($method, $urlpath, $headers, $params, $body, $file, $sensitive))
        } Catch [ApiUnauthorized] {
            $this.Login()
            $result = $this.HandleReturnCode($this.DoRequest($method, $urlpath, $headers, $params, $body, $file, $sensitive))
        }
        return $result
    }

    [void] Login(){
        Write-Log "Performing Login"
        $this.api_key = $null
        $apik = $($this.DoRequest("PUT", "login", @{}, @{}, @{name="admin"; password="password"}, $null, $true)).key
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

    [PSCustomObject] Create([string]$urlpath, [hashtable]$body) {
        return $this.DoRequestWithAuth("Post", $urlpath, @{}, @{}, $body, $null, $false).data
    }

    [PSCustomObject] Set([string]$urlpath, [hashtable]$body) {
        return $this.DoRequestWithAuth("Put", $urlpath, @{}, @{}, $body, $null, $false).data
    }

    [PSCustomObject] Get([string]$urlpath) {
        return $this.DoRequestWithAuth("Get", $urlpath, @{}, @{}, $null, $null, $false).data
    }

    [PSCustomObject] Delete([string]$urlpath) {
        return $this.DoRequestWithAuth("Delete", $urlpath, @{}, @{}, $null, $null, $false).data
    }

    [PSCustomObject[]] List([string]$urlpath, [hashtable]$params) {
        $result = $this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $null, $false)
        # Perform accumulation
        $metadata = $result.metadata
        If ((($metadata.limit -ne 0) -and ($metadata.limit -ne 100)) -or
            ((Confirm-Attr $metadata "offset") -and ($metadata.offset -ne 0))) {
            return $result.data
        }
        $data = $result.data
        $offset = 0
        $tcnt = 0
        $rcnt = 0
        $limit = $result.metadata.limit
        $ldata = $data.Length
        While (($ldata -ne $tcnt) -and ($ldata -ne $limit) -and ($ldata -ne $rcnt)) {
            $tcnt = $result.metadata.total_count
            $rcnt = $result.metadata.request_count
            $offset += $result.data.Length
            If ($offset -ge $tcnt) {
                break
            }
            $params.Set_Item("offset", $offset)
            Try {
                $result = $this.DoRequestWithAuth("Get", $urlpath, @{}, $params, $null, $false)
            } Catch [DateraApiException] {
                return $data
            }
            $data += $result.data
        }
        return $data
    }

    [PSCustomObject[]] Upload([string]$urlpath, [string[]]$file, [hashtable]$body) {
        return $this.DoRequestWithAuth("Put", $urlpath, @{}, @{}, $body, $file, $false).data
    }
}

Function New-DateraApiConnection {
    Param(
        [Parameter(mandatory=$false)]
        [UDC]$udc,

        [Parameter(mandatory=$false)]
        [switch]$force
    )
    If (($global:datconn -eq $null) -or ($force)) {
        If ($udc -ne $null) {
            $global:datconn = [ApiConnection]::new($udc)
        } Else {
            $global:datconn = [ApiConnection]::new()
        }
    }
    return $global:datconn
}

###################
# Combo Functions #
###################

Function New-DateraAiSiVol {
    Param(
        [Parameter(mandatory=$true)]
        [string]$name,

        [Parameter(mandatory=$true)]
        [int]$size,

        [Parameter(mandatory=$false)]
        [int]$replicas = 3,

        [Parameter(mandatory=$false)]
        [string]$placement = "hybrid",

        [Parameter(mandatory=$false)]
        [string]$ip_pool = "default",

        [Parameter(mandatory=$false)]
        [string]$siname = "storage-1",

        [Parameter(mandatory=$false)]
        [string]$volname = "volume-1"

    )

    $body = @{
        "name"=$name;
        "access_control_mode"="deny_all";
        "storage_instances"=@(
            @{
                "name"=$siname;
                "ip_pool"=@{"path"="/access_network_ip_pools/$ip_pool"};
                "volumes"=@(
                    @{
                        "name"=$volname;
                        "size"=$size;
                        "placement_mode"=$placement;
                        "replica_count"=$replicas;
                        "snapshot_policies"=@();
                    }
                );
            }
        );
    }
    return $(New-DateraApiConnection).Create("app_instances", $body)
}

#########################
# AppInstance Functions #
#########################

Function Get-DateraAppInstances {
    Param(
        [Parameter(mandatory=$false)]
        [int]$limit,

        [Parameter(mandatory=$false)]
        [int]$offset,

        [Parameter(mandatory=$false)]
        [string]$sort,

        [Parameter(mandatory=$false)]
        [string]$filter
    )
    $params = @{}
    If ($limit -gt 0) {
        $params["limit"] = $limit
    }
    If ($offset -gt 0) {
        $params["offset"] = $offset
    }
    If ($sort -ne "") {
        $params["sort"] = $sort
    }
    If ($filter -ne "") {
        $params["filter"] = $filter
    }
    return $(New-DateraApiConnection).List("app_instances", $params)
}

Function Get-DateraAppInstance {
    Param(
        [Parameter(mandatory=$true)]
        [string]$id
    )
    return $(New-DateraApiConnection).Get("app_instances/$id")
}

Function Get-DateraAppInstanceMatchName {
    Param(
        [Parameter(mandatory=$true)]
        [string]$m
    )
    return $(New-DateraApiConnection).List("app_instances", @{filter="match(name,.*$m.*)"})
}

Function Set-DateraAppInstance {
    Param(
        [Parameter(mandatory=$true)]
        [string]$id,

        [Parameter(mandatory=$true)]
        [hashtable]$kvs
    )
    return $(New-DateraApiConnection).Set("app_instances/$id", $kvs)
}

Function Remove-DateraAppInstance {
    Param(
        [Parameter(mandatory=$true)]
        [string]$id
    )
    return $(New-DateraApiConnection).Delete("app_instances/$id")
}


#############################
# StorageInstance Functions #
#############################
Function Get-DateraStorageInstances {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [int]$limit,

        [Parameter(mandatory=$false)]
        [int]$offset,

        [Parameter(mandatory=$false)]
        [string]$sort,

        [Parameter(mandatory=$false)]
        [string]$filter
    )
    $params = @{}
    If ($limit -gt 0) {
        $params["limit"] = $limit
    }
    If ($offset -gt 0) {
        $params["offset"] = $offset
    }
    If ($sort -ne "") {
        $params["sort"] = $sort
    }
    If ($filter -ne "") {
        $params["filter"] = $filter
    }
    return $(New-DateraApiConnection).List("app_instances/$appid/storage_instances", $params)
}

Function Get-DateraStorageInstance {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1"
    )
    return $(New-DateraApiConnection).Get("app_instances/$appid/storage_instances/$sid")
}

Function Get-DateraStorageInstanceMatchName {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$true)]
        [string]$m
    )
    return $(New-DateraApiConnection).List("app_instances/$appid/storage_instances", @{filter="match(name,.*$m.*)"})
}

Function Set-DateraStorageInstance {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1",

        [Parameter(mandatory=$true)]
        [hashtable]$kvs
    )
    return $(New-DateraApiConnection).Set("app_instances/$appid/storage_instances/$sid", $kvs)
}

Function Remove-DateraStorageInstance {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1"
    )
    return $(New-DateraApiConnection).Delete("app_instances/$appid/storage_instances/$sid")
}

####################
# Volume Functions #
####################
Function Get-DateraVolumes {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1",

        [Parameter(mandatory=$false)]
        [int]$limit,

        [Parameter(mandatory=$false)]
        [int]$offset,

        [Parameter(mandatory=$false)]
        [string]$sort,

        [Parameter(mandatory=$false)]
        [string]$filter
    )
    $params = @{}
    If ($limit -gt 0) {
        $params["limit"] = $limit
    }
    If ($offset -gt 0) {
        $params["offset"] = $offset
    }
    If ($sort -ne "") {
        $params["sort"] = $sort
    }
    If ($filter -ne "") {
        $params["filter"] = $filter
    }
    return $(New-DateraApiConnection).List("app_instances/$appid/storage_instances/$sid/volumes", $params)
}

Function Get-DateraVolume {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1",

        [Parameter(mandatory=$false)]
        [string]$volid = "volume-1"
    )
    return $(New-DateraApiConnection).Get("app_instances/$appid/storage_instances/$sid/volumes/$volid")
}

Function Get-DateraVolumeMatchName {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1",

        [Parameter(mandatory=$false)]
        [string]$volid = "volume-1",

        [Parameter(mandatory=$true)]
        [string]$m
    )
    return $(New-DateraApiConnection).List("app_instances/$appid/storage_instances/$sid/volumes", @{filter="match(name,.*$m.*)"})
}

Function Set-DateraVolume {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1",

        [Parameter(mandatory=$false)]
        [string]$volid = "volume-1",

        [Parameter(mandatory=$true)]
        [hashtable]$kvs
    )
    return $(New-DateraApiConnection).Set("app_instances/$appid/storage_instances/$sid/volumes/$volid", $kvs)
}

Function Remove-DateraVolume {
    Param(
        [Parameter(mandatory=$true)]
        [string]$appid,

        [Parameter(mandatory=$false)]
        [string]$sid = "storage-1",

        [Parameter(mandatory=$false)]
        [string]$volid = "volume-1"
    )
    return $(New-DateraApiConnection).Delete("app_instances/$appid/storage_instances/$sid/volumes/$volid")
}

#######################
# Initiator Functions #
#######################

Function New-DateraInitiator {
    Param(
        [Parameter(mandatory=$true)]
        [string]$name,

        [Parameter(mandatory=$true)]
        [string]$id,

        [Parameter(mandatory=$false)]
        [switch]$force
    )
    $body = @{id=$id; name=$name; force=$force}
    return $(New-DateraApiConnection).Create("initiators", $body)
}

Function Get-DateraInitiators {
    Param(
        [Parameter(mandatory=$false)]
        [int]$limit,

        [Parameter(mandatory=$false)]
        [int]$offset,

        [Parameter(mandatory=$false)]
        [string]$sort,

        [Parameter(mandatory=$false)]
        [string]$filter
    )
    $params = @{}
    If ($limit -gt 0) {
        $params["limit"] = $limit
    }
    If ($offset -gt 0) {
        $params["offset"] = $offset
    }
    If ($sort -ne "") {
        $params["sort"] = $sort
    }
    If ($filter -ne "") {
        $params["filter"] = $filter
    }
    return $(New-DateraApiConnection).List("initiators", $params)
}

Function Get-DateraInitiator {
    Param(
        [Parameter(mandatory=$true)]
        [string]$id
    )
    return $(New-DateraApiConnection).Get("initiators/$id")
}

Function Set-DateraInitiator {
    Param(
        [Parameter(mandatory=$true)]
        [string]$id,

        [Parameter(mandatory=$true)]
        [hashtable]$kvs
    )
    return $(New-DateraApiConnection).Set("initiators/$id", $kvs)
}

####################
# System Functions #
####################
Function Get-DateraSystem {
    return $(New-DateraApiConnection).Get("system")
}

########################
# Log Upload Functions #
########################
# Function Send-File {
#     Param(
#         [Parameter(mandatory=$true)]
#         [string]$file
#     )
#     return $(New-DateraApiConnection).Upload("logs_upload", $file, @{"ecosystem" = "other"})
# }

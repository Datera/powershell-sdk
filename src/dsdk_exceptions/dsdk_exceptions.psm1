Set-StrictMode -Version Latest

class DateraException : System.Exception {
    [PSCustomObject]$result

    DateraException([string]$message) : base($message){
    }

    DateraException([string]$message, [PSCustomObject]$myresult) : base($message){
        $this.result = $myresult
    }
}

class DateraApiException : DateraException {
    DateraApiException([string]$message) : base($message){
    }
    DateraApiException([string]$message, [PSCustomObject]$myresult) : base($message){
        $this.result = $myresult
    }
}

class ApiUnauthorized : DateraException {
    ApiUnauthorized([string]$message) : base($message){
    }
    ApiUnauthorized([string]$message, [PSCustomObject]$myresult) : base($message){
        $this.result = $myresult
    }
}

class ApiNotFound : DateraException {
    ApiNotFound([string]$message) : base($message){
    }
    ApiNotFound([string]$message, [PSCustomObject]$myresult) : base($message){
        $this.result = $myresult
    }
}

class ApiInternalError : DateraException {
    ApiInternalError([string]$message) : base($message){
    }
    ApiInternalError([string]$message, [PSCustomObject]$myresult) : base($message){
        $this.result = $myresult
    }
}

class ApiUnknown : DateraException {
    ApiUnknown([string]$message) : base($message){
    }
    ApiUnknown([string]$message, [PSCustomObject]$myresult) : base($message){
        $this.result = $myresult
    }
}

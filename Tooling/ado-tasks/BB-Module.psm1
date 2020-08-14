function Get-TowerAuthToken {
    param(
        [string][ValidateSet("Production", "Development", "Other")]$TowerEnvironment,
        [string]$TowerUser,
        [string]$TowerPassword,
        [string]$TowerURL
    )
    switch ($TowerEnvironment) {
        "Production" { $AuthType = "Bearer" ; $TowerURL = "tower.000ukso.sbp.eyclienthub.com" }
        "Development" { $AuthType = "Bearer" ; $TowerURL = "tower.000ukso.sbp.eyclienthubd.com" }
        "Other" { }
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $TowerUser,$TowerPassword)))
    $headers = @{
        "Authorization" = "Basic $base64AuthInfo"
    }
    $result = Invoke-RestMethod -Method POST -Headers $headers -Uri ("https://{0}/api/v2/tokens/" -f $TowerURL)

    [PSCustomObject]@{
        Token    = $result.token
        Headers  = @{"Authorization" = "$AuthType $($result.token)" }
        TowerURL = $TowerURL
    }
}

function Get-TowerTemplateCreds {
    param(
        $Authentication,
        $TemplateID
    )
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 

    $results = @()
    $TemplateUrl = "https://$towerURL/api/v2/job_templates/$TemplateID/credentials/"
    
    #$Headers = @{Authorization ="token $token"}
    $creds = Invoke-RestMethod -Method Get -Uri "$TemplateUrl" -UseBasicParsing -ContentType "application/json" -Headers $Headers

    foreach($cred in $creds)
    {
        Write-host "Existing Credentials returned: $($cred.results.id)"
        $results += $cred.results.id
    }

    return $results
}

Function Get-CustomVstsInput($ParameterName, $Type) {

    if ($Type -eq "Integer") {
        $retrievedValue = Get-VstsInput -Name $ParameterName -AsInt
        
        if ($retrievedValue -eq 0) {
            return $null
        }
    }
    elseif ($Type -eq "Boolean") {
        $retrievedValue = Get-VstsInput -Name $ParameterName -AsBool
    }
    else {
        $retrievedValue = Get-VstsInput -Name $ParameterName  -ErrorAction SilentlyContinue
    }
    
    return $retrievedValue

}

function Get-TowerTemplates {
    param(
        $Authentication
    )
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 
    $uri = "https://$TowerURL/api/v2/job_templates/?page_size=200&name__contains=bb"
    #/api/v2/job_templates/9/survey_spec/
    #$Headers = @{Authorization ="token $token"}
    #$Headers = @{ "Authorization" = "Bearer $token"}
    $WB = Invoke-WebRequest -Uri $uri -ContentType "application/json" -Headers $Headers -Method Get -UseBasicParsing 
    $result = $wb.Content | ConvertFrom-Json
    $result.results #| Select-Object name,id,url,survey_enabled
}

function Launch-TowerTemplate {
    param(
        $Authentication,
        $Body,
        $TemplateID
    )
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 

    try {
        $Body | ConvertFrom-Json
    }
    catch {
        throw "Body doesnt have a valid Payload"
    }

    $TemplateUrl = "https://$towerURL/api/v2/job_templates/$TemplateID/launch/"
    
    Write-verbose "Launching $TemplateUrl with Payload $Body" -verbose
    
    #$Headers = @{Authorization ="token $token"}
    Invoke-RestMethod -Method Post -Uri "$TemplateUrl" -Body $Body -UseBasicParsing -ContentType "application/json" -Headers $Headers
}
function Get-TowerJobStatus {
    param(
        $Authentication,
        [string[]]$JobIDs,
        [switch]$Wait
    )
    if ($wait) { Write-Verbose "Wait Flag Enabled" -Verbose }
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 
        
    DO {
        $Status = @()
        Foreach ($JobID in $JobIDs) {
            $JobID = $JobID.trim()
            $TemplateUrl = "https://$towerURL/api/v2/jobs/$JobID/" 
 
            #$Headers = @{Authorization ="token $token"}
            #$TemplateUrl
            $response = Invoke-RestMethod -Method get -Uri "$TemplateUrl" -ContentType "application/json" -Headers $Headers -UseBasicParsing
        
            $output = @([PSCustomObject]@{
                    JobID        = $JobID;
                    Status       = $response.status  ;
                    TemplateID   = $response.summary_fields.job_template.id  ;
                    TemplateName = $response.summary_fields.job_template.name  
                } )
                   
            $Status += $output
            
        }

        #$Status
        If ($wait) { Start-Sleep -Seconds 15 }
        IF (($status.status -eq "failed") -eq $false) { $JobFailed = 0 }else { $JobFailed = ($status.status -eq "failed").count }
        IF (($status.status -eq "running") -eq $false) { $JobRunning = 0 }else { $JobRunning = ($status.status -eq "running").count }
        IF (($status.status -eq "successful") -eq $false) { $JobSuccessful = 0 }else { $JobSuccessful = ($status.status -eq "successful").count }
        IF (($status.status -eq "pending") -eq $false) { $Jobpending = 0 }else { $Jobpending = ($status.status -eq "pending").count }
        IF (($status.status -eq "waiting") -eq $false) { $Jobwaiting = 0 }else { $Jobwaiting = ($status.status -eq "waiting").count }
        "[$(Get-date)] Jobs Running: $JobRunning | Jobs Failed: $JobFailed  | Jobs successful: $JobSuccessful | Jobs pending: $Jobpending | Jobs waiting: $Jobwaiting"
        $WhoFailed = $status | Where-Object Status -eq "failed"
        If ($WhoFailed) { 
            $tempFile = New-TemporaryFile

            (Invoke-RestMethod -Method GET -Headers $Headers -Uri ("https://{0}/api/v2/jobs/{1}/stdout/?format=json" -f $towerURL,$WhoFailed.JobId)).content | Out-File $tempFile

            Get-Content $tempFile | Where-Object {$_ -like "*fatal*msg*"} | Select-Object -Last 5

            Throw "Job $($WhoFailed.JobId) Failed"
        }
    }while ($Wait -and ( ($JobRunning -gt 0 -or $Jobpending -gt 0 -or $Jobwaiting -gt 0) -and $JobFailed -eq 0) )
    $Status
}


function Get-ResourceNameRegEx {
    param(
        $Authentication,
        $JobId,
        $BBName
    )
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 

    $TemplateUrl = "https://$towerURL/api/v2/jobs/$JobId/stdout/?format=txt"
    
    $output = Invoke-RestMethod -Method Get -Uri "$TemplateUrl" -UseBasicParsing -ContentType "application/json" -Headers $Headers

    [regex]$regex = '{0}:\\\\"/(\w+)/[a-z0-9.-]*/[a-zA-Z0-9!@#$&()\\-`.+,/\"]*' -f $BBName
    [regex]$regextsv = '{0}:/(\w+)/[a-z0-9.-]*/[a-zA-Z0-9!@#$&()\\-`.+,/\"]*' -f $BBName

    $regexResponse = $regex.Matches($output) | Select -First 1 | % { $_.value }

    $regexName = [regex] '(\/(\w+[.*]*)*\\)'
    $regexId = [regex] '\\(.*)\\'
    if($regexResponse -eq $null)
    {
        $regexResponse = $regextsv.Matches($output) | Select -First 1 | % { $_.value }
        $regexName = [regex] '(\/(\w+[.*]*)*")'
        $regexId = [regex] '/(.*)"'
    }
    $meaningAllNames = New-Object PSObject
    
    $regexIpAddress = [regex] "\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"

    if (![string]::IsNullOrWhiteSpace($regexResponse))
    {
        try
        {
            $name = $regexName.Match($regexResponse) | Select -First 1 | % { $_.value }
            $id = $regexId.Match($regexResponse) | Select -First 1 | % { $_.value }
            $ipAddress = $regexIpAddress.Matches($output) | Select -First 1 | % { $_.value }
            
            Write-host "Process the Name of the Resource"
            $meaningAllNames | Add-Member -MemberType NoteProperty -Name "Name" -Value $name.Replace("/","").Replace("\","").Replace("""","")
            
            Write-host "Processing the Resource ID"
            $meaningAllNames | Add-Member -MemberType NoteProperty -Name "ID" -Value $id.Replace("\","").Replace("""","")

            if (![string]::IsNullOrWhiteSpace($ipAddress)) {
                Write-host "Processing the IP Address if available"
                $meaningAllNames | Add-Member -MemberType NoteProperty -Name "private_ip" -Value $ipAddress
            }
        }
        catch
        {
            $ErrorMessage = $_.Exception.message
            Write-host "Error while processing the Resource details. Error: $ErrorMessage"
        }
        
    }

    return $meaningAllNames 

}

function Get-ResourceExMultiResource {
    param(
        $Authentication,
        $JobId  
    )
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 

    $TemplateUrl = "https://$towerURL/api/v2/jobs/$JobId/stdout/?format=txt"
    
    $output = Invoke-RestMethod -Method Get -Uri "$TemplateUrl" -UseBasicParsing -ContentType "application/json" -Headers $Headers
    
    [regex]$regex = '.* : \\\\"/(\w+)/[a-z0-9.-]*/[a-zA-Z0-9!@#$&()\\-`.+,/\"]*'
    $resourcedetails = $regex.Matches($output)
    [array]$meaningAllNamesarray  = @()


    forEach($resource in $resourcedetails)
    {
        # split the output with : 
        $name = $resource.Value.Split(":")[1].tostring()
        $id = $resource.Value.Split(":")[2].tostring() 
        $meaningAllNames = New-Object PSObject
    
        if (![string]::IsNullOrWhiteSpace($resourcedetails))
        {
            try
            {
                     
                Write-host "Process the Name of the Resource"
                $meaningAllNames| Add-Member -MemberType NoteProperty -Name "Name" -Value $name.Replace("""","").Trim()
            
                Write-host "Processing the Resource ID"
                $meaningAllNames| Add-Member -MemberType NoteProperty -Name "ID" -Value $id.Replace("\","").Replace("""","").Trim()

            
                $meaningAllNamesarray += $meaningAllNames
   
            }
            catch
            {
                $ErrorMessage = $_.Exception.message
                Write-host "Error while processing the Resource details. Error: $ErrorMessage"
            }
        }
    }
    return $meaningAllNamesarray
}
function Get-ResourceName {
    param(
        $Authentication,
        [string]$JobID,
        $BBName
    )
    $TowerURL = $Authentication.TowerURL
    $Headers = $Authentication.Headers 

    $Templateevent = "https://$towerURL/api/v2/jobs/$JobID/job_events/" 

    $baseUrl = "https://$towerURL/api/v2/"

    $jobResponse = Invoke-RestMethod -Method get -Uri "$Templateevent" -ContentType "application/json" -Headers $Headers -UseBasicParsing
    $flag = $false
    $meaningAllNames = $null
    $meaningAllNames = New-Object PSObject

    while (!$flag) {
        $nextPage = $jobResponse.next -replace "/api/v2/", ""

        $resourceIp = $null

        $jobResponse | Select-Object -ExpandProperty results | Where-Object { $_.stdout -like "*private_ip:*" -and $_.event_data.task_path -like "*/$BBName/*" } | ForEach-Object {
            $temp = $_.stdout

            $regex = [regex] "\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b"

            $resourceIp = $regex.Matches($temp) | % { $_.value }

            if (![string]::IsNullOrWhiteSpace($resourceIp)) {
                $meaningAllNames | Add-Member -MemberType NoteProperty -Name "private_ip" -Value $resourceIp
            }

        }

        $rgName = $jobResponse | Select-Object -ExpandProperty results |
        Where-Object { $_.event_data.task -eq "Print Resource ID" -and $_.event_data.task_path -like "*/$BBName/*" } |
        Select-Object -Property @{Name = "TaskName"; Expression = { $_.event_data.task } },
        @{Name = "Name"; Expression = { [regex]::match($_.stdout, '(\/(\w+)\\)|(\/(\w+)")').Groups[1].Value -replace "\\", "" -replace "/", "" } }, @{Name = "ID"; Expression = { [regex]::match($_.stdout, '\\(.*?)\\').Groups[1].Value -replace '"', "" } } | ? { $_.Name -ne $null -and $_.ID -ne $null } #| select -ExpandProperty Name
    
        [string]$resourceName = $rgName.Name 
        [string]$resourceID = $rgName.ID

        if (![string]::IsNullOrWhiteSpace($resourceName) -and ![string]::IsNullOrWhiteSpace($resourceID)) {
            try {
                Write-host "Detected the ResourceName $resourceName and the ResourceID $resourceID"
                $meaningAllNames | Add-Member -MemberType NoteProperty -Name "Name" -Value $resourceName.replace(" ", "")
                $meaningAllNames | Add-Member -MemberType NoteProperty -Name "ID" -Value $resourceID.replace(" ", "")
                $flag = $true
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-host "Error while processing the ResourceName. Error: $ErrorMessage"
            }

        }

        if (![string]::IsNullOrEmpty($nextPage)) {
            $nextPagetemp = $baseUrl + $nextPage;
            $jobResponse = getAnsibleEventsJobPages -url $nextPagetemp -jobId $JobID -header $Headers
        }
        else {
            $flag = $true
        }

    }


    $meaningAllNames
}

Function getAnsibleEventsJobPages($url, $jobId, $header) {

    try {

        Write-host "[$(Get-date)] Processing URL: $url"
        $response = Invoke-RestMethod -Uri $url -Headers $header
        return $response
    }
    catch {
        throw $_.Exception;
    }
}

function downloadFile($url, $targetFile) {
    Get-PWD
    "Downloading $url"
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000) #15 second timeout
    $response = $request.GetResponse()
    $totalLength = [System.Math]::Floor($response.get_ContentLength() / 1024)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList "$script:ScriptDirectory\$targetFile", Create
    $buffer = new-object byte[] 1000KB
    $count = $responseStream.Read($buffer, 0, $buffer.length)
    $downloadedBytes = $count
    while ($count -gt 0) {
        write-host "Downloaded $([System.Math]::Floor($downloadedBytes/1024)) KB of  $totalLength KB"
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer, 0, $buffer.length)
        $downloadedBytes = $downloadedBytes + $count
    }
    "`nFinished Download"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}


function Get-CTPBuildingBlocks {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        $towerToken,
        $projecid,
        $query
    )    

    $uri = "https://{0}/api/v2/job_templates/?{1}" -f $towerToken.TowerURL, $query

    $header = $towerToken.Headers
    #$header = @{
    #	"Content-Type"		     = "application/json"
    #	"Authorization"		     = "Token $towerToken"
    #}
    
    $buildingBlocksTemplates = @()
    
    do {
        $response = Invoke-RestMethod -Uri $uri -Headers $header -Method Get
        $uri = "https://{0}{1}" -f $towerToken.TowerURL, $response.next
        $response.results | Where-Object { $_.name -like "*-bb-*" -and $_.project -eq $projecid } | ForEach-Object {
            $bbName = $_.name.remove(0, $_.name.indexof("-bb-") + 4).remove($_.name.lastindexof("-") - ($_.name.indexof("-bb-") + 4))
            $bbVersion = $_.name.remove(0, $_.name.lastindexof("-") + 1)
            if($bbVersion -like "V*") { $bbVersion = $bbVersion.remove(0,1) }

            $buildingBlockTemplate = New-Object -TypeName PSCustomObject
            $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "BuildingBlock" -Value $bbName
            $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Version" -Value $bbVersion
            $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "TemplateID" -Value $_.id
            $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "TemplateName" -Value $_.name
            $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Endpoint" -Value $("https://{0}{1}" -f $towerToken.TowerURL, $_.url)
            $buildingBlocksTemplates += $buildingBlockTemplate
        }
    }
    while ($null -ne $response.next)
    
    $buildingBlocksTemplates
}

function List-Parameters {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [String]$uGit,
        [parameter(Mandatory = $true)]
        [String]$pGit,
        [parameter(Mandatory = $false)]
        [switch]$GenerateConfig

    )

    Get-PWD
    $jsonconfigpath = "$script:ScriptDirectory\Config.JSON"

    if ((Test-Path $jsonconfigpath) -eq $true) {
        # Write-host "File Present: $jsonconfigpath"
        $Config = Get-Content "$script:ScriptDirectory\Config.JSON" -Raw | ConvertFrom-Json
        $Script:BBsConfig = $Config 
    }
       
    if ($GenerateConfig.IsPresent) {
        Write-Host "Config will be created in the location $script:ScriptDirectory\Config.JSON"
        Initiate-Config -uGit $uGit -pGit $pGit 
    }
        
    if ((Test-Path $jsonconfigpath) -eq $true) {
        # Write-host "File Present: $jsonconfigpath"
        $Config = Get-Content "$script:ScriptDirectory\Config.JSON" -Raw | ConvertFrom-Json
        $Script:BBsConfig = $Config 
    }
    else {
        Throw "Configuration file is missing. Please generate Configuration File to Continue"
    }
        
    $Script:BBsConfig
        
}

function List-Parameters-Single-File {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$file,
        [parameter(Mandatory = $true)]
        [string]$version,
        [parameter(Mandatory = $true)]
        [string]$BBName,
        [parameter(Mandatory = $false)]
        [switch]$GenerateConfig
    )

    Get-PWD
    $jsonconfigpath = "$script:ScriptDirectory\Config.JSON"

    if ((Test-Path $jsonconfigpath) -eq $true) {
        # Write-host "File Present: $jsonconfigpath"
        $Config = Get-Content "$script:ScriptDirectory\Config.JSON" -Raw | ConvertFrom-Json
        $Script:BBsConfig = $Config 
    }
       
    if ($GenerateConfig.IsPresent) {
        Write-Host "Config will be created in the location $script:ScriptDirectory\Config.JSON"
        $ParamArray = @()
    
        $ParamArray += Process-MDFile -file $file -Version $version -BBName $BBName

        $ParamArray += Get-PreviousData    
            
        Generate-Config -ParamArray $ParamArray
    }
        
    if ((Test-Path $jsonconfigpath) -eq $true) {
        # Write-host "File Present: $jsonconfigpath"
        $Config = Get-Content "$script:ScriptDirectory\Config.JSON" -Raw | ConvertFrom-Json
        $Script:BBsConfig = $Config 
    }
    else {
        Throw "Configuration file is missing. Please generate Configuration File to Continue"
    }
        
    $Script:BBsConfig
        
}

	
Function Get-ApprovedEntry($BuidlingBlock, $Version) {
    
    #Write-Verbose "Procssing $BuidlingBlock with version $Version"

    #$Config = Get-Content $script:ScriptDirectory\Config.JSON -Raw | ConvertFrom-Json
    $BBCheck = $Script:BBsConfig | ? { $_.BuildingBlock -eq "$BuidlingBlock" -and $_.Version -eq "$Version" -and $_.Approved -eq "Yes" }

    if ($BBCheck -eq $null) {
        #Write-host "Empty - $BBCheck"
        return $false
    }
    else {
        #Write-host "Result - $BBCheck"
        return $BBCheck
    }

}

Function Get-Parameters($paramTemp, $type, $Mandatory, $defaultVaule, $groupName, $tempDescription, $isdropDown, $varType) {
    $dynStatus = Get-DynamicStatus -varname $paramTemp
    $EditableOptions = "True"

    if ($dynStatus -eq $true) {
        $isdropDown = $true
        $EditableOptions = "True"

        $editableOption = new-object psobject -Property @{
            EditableOptions = $EditableOptions
        }

        $sarr = new-object psobject -Property @{
            name         = ($paramTemp)
            type         = "pickList"
            paramset     = $type
            label        = ($paramTemp)
            required     = $Mandatory
            defaultValue = $defaultVaule
            groupname    = $groupName
            helpMarkDown = $tempDescription
            properties   = $editableOption
        }

        #Read-Host $sarr
    }
    elseif ($isdropDown -ne $true) {
        $sarr = new-object psobject -Property @{
            name         = ($paramTemp)
            type         = $varType
            label        = ($paramTemp)
            required     = $Mandatory
            defaultValue = $defaultVaule
            groupname    = $groupName
            helpMarkDown = $tempDescription
            paramset     = $type

        }
    }
    else {

        $editableOption = new-object psobject -Property @{
            EditableOptions = $EditableOptions
        }

        $listVars = $Script:BBsConfig.Variables

        $sarr = new-object psobject -Property @{
            name         = ($paramTemp)
            type         = "pickList"
            paramset     = $type
            label        = ($paramTemp)
            required     = $Mandatory
            defaultValue = $defaultVaule
            groupname    = $groupName
            helpMarkDown = $tempDescription
            options      = $Script:BBsConfig.Variables.$paramTemp
            properties   = $editableOption
        }
    }

    return $sarr
}

Function Process-MDTable($content, $type) {
    try {
        $account = @() 
        foreach ($line in $content.Split("`r")) {

            if ($line -like "*Parameter |*" -or $line -like "*--*" -or $line -like "|-*" -or $line -like "| -*" -or $line -notlike "*|*") {
                #$test = $line.split("|")
                #.Replace(" ","") 
            }
            else {
                $test = $line.split("|")
                $defaultValue = ""
                #.Replace(" ","") 
        
                if ($type -eq "CoDev") {
                    $Mandatory = $false
                    $varType = "string"
                    $groupName = "codev"

                }
                else {
                    
                    $tempMandatory = $test[5].Replace(" ", "")
                    $checkboxDefault = $test[3].Replace(" ", "")
                    if ($tempMandatory -eq "Yes") {
                        $Mandatory = $true
                        $groupName = "mandatory"
                    }
                    else {
                        $Mandatory = $false
                        $groupName = "optional"
                    }
            
                    #detect the VarType
                    $varType = $test[6].Replace(" ", "")
            
                    #$varType = $tempMandatory
                    if ($varType -like "*string*") {
                        $varType = "string"            
                    }
                    elseif ($varType -like "*int*") {
                        $varType = "Integer"
                    }
                    elseif ($varType -like "*object*") {
                        $varType = "object"
                    }
                    elseif ($varType -like "*bool*") {
                        
                        $varType = "boolean"
                        if($checkboxDefault -like "*true*")
                        {
                            $defaultValue = "True"
                        }
                        else
                        {
                            $defaultValue = "False"
                        }

                    }
                    elseif ($varType -like "*array*") {
                        $varType = "Array"
                    }
                    else {
                        $varType = "string" 
                    }
                }

                $paramTemp = $test[1].Replace("*", "").Replace(" ", "") 
                $tempDescription = $test[2]
                $isdropDown = $false


                $detectMandatory = Get-DefaultMandatory -varname $paramTemp

                $detectdataType = Get-DefaultDataType -varname $paramTemp

                if ($detectMandatory -eq $true) {
                    $Mandatory = $true
                    $groupName = "mandatory"
                }

                if ($detectdataType -ne $false) {
                    $varType = $detectdataType
                    $detectdataType
                }

                if (Test-Path $script:ScriptDirectory\Config.JSON) {
                    #$tempConfig = Get-Content $script:ScriptDirectory\Config.JSON -Raw | ConvertFrom-Json
            
                    # Write-host "Processing $($Script:BBsConfig.Variables.$paramTemp)"

                    if ($Script:BBsConfig.Variables.$paramTemp -ne $null) {
                        #Write-host "The Param $paramTemp is going to be dropdown"
                        $isdropDown = $true
                    }

                }
        
                #$defaultValue = $null
                #$defaultResult = Get-DefaultValues -varname $paramTemp


                if ($paramTemp -eq "AZURE_RM_CLIENTID" -or $paramTemp -eq "AZURE_RM_SECRET") {
                    Write-Host "Skipping Credentials Parameter: $paramTemp"
                }
                elseif ($paramTemp -like "var_*" -and $type -ne "CoDev") {
                    $sarr = Get-Parameters -paramTemp $paramTemp -type $Type -Mandatory $Mandatory -defaultVaule $defaultValue -groupName $groupName -tempDescription $tempDescription -isdropDown $isdropDown -varType $varType
                    $account += $sarr
                }
                elseif ($type -eq "CoDev" -and $paramTemp -ne "-") {
                    $sarr = Get-Parameters -paramTemp $paramTemp -type $type -Mandatory $Mandatory -defaultVaule $defaultValue -groupName $groupName -tempDescription $tempDescription -isdropDown $isdropDown -varType $varType
                    $account += $sarr
                }
            }
        }

        return $account
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        #Write-Host "Process MD: Error $ErrorMessage"
    }
}

Function Get-DefaultMandatory($varname) {
    try {

        if ($Script:BBsConfig.Mandatory.$varname -eq "Yes") {
            Write-host "Default Mandatory Set for the $varname from the Config" -ForegroundColor Green
            return $true
        }
        else {
            return $false
        }
        
    }
    catch {
        return $false
    }
}

Function Get-DynamicStatus($varname) {
    try {

        if ($Script:BBsConfig.Dynamic.$varname -eq "Yes") {
            Write-host "Dynamic Set for the $varname from the Config" -ForegroundColor Green
            return $true
        }
        else {
            return $false
        }
        
    }
    catch {
        return $false
    }
}


Function Get-DefaultValues($varname) {
    try {

        if ($Script:BBsConfig.DefaultValues.$varname -ne $null) {
            $tempDef = $Script:BBsConfig.DefaultValues.$varname
            Write-host "Default Value for the $varname is $tempDef " -ForegroundColor Green
            return $tempDef
        }
        else {
            return $false
        }
        
    }
    catch {
        return $false
    }
}
Function Get-DefaultDataType($varname) {
    try {

        if ($Script:BBsConfig.DataTypes.$varname -ne $null) {
            $dataType = $Script:BBsConfig.DataTypes.$varname
            return $dataType
        }
        else {
            return $false
        }
        
    }
    catch {
        return $false
    }
}
Function Initiate-Config($uGit, $pGit) {
    $ParamArray = @()

    Get-Wiki -uGit $uGit -pGit $pGit
    Get-ChildItem -Path (Join-Path $script:ScriptDirectory "Wiki\WikiContent\Building-Block-Readme-Files") -Include "*.md" -Recurse | ForEach-Object {
        $ParamArray += Process-MDFile -file $_.FullName -Version $_.Name.Replace("%2D", "-").Replace(".md", "") -BBName $_.Directory.Name.Replace("%2D", "-")
    }

    $ParamArray += Get-PreviousData    
            
    Generate-Config -ParamArray $ParamArray
}

Function Process-MDFile($file, $version, $BBName){
    try {

        $json = @()

        Get-Content $file | ForEach-Object {
            $_ = $_ -replace '\s+', ' '

            if ($_ -like "*Co-Dev*" -and $_ -like "*Parameter*" -and $_ -like "#*") {
                $type = "CoDev"
            }
            elseif ($_ -like "*Create*" -and $_ -like "*Parameter*" -and $_ -like "#*") {
                $type = "Create"
            }
            elseif ($_ -like "*Destroy*" -and $_ -like "*Parameter*" -and $_ -like "#*") {
                $type = "Destroy"
            }

            #$_ -Like "| Parameter |*" -or 
            if ($_ -Like "*Parameter |*" -or $lineprocess -ne $false) {
                $lineprocess = $true

                if ($_ -ne "") {
                    $content = $content + $_ + "`r`n"
                }
                else {
            
                    $output = $null
                    $output = Process-MDTable -content $content.Trim() -type $type		
                    $lineprocess = $false
                    $content = $null
                    $json += $output 
            
                }
        
            }
            else {
                #Write-Host $_
            }
        }
        #$json | Out-GridView -PassThru
        $versionBB = $Version.Replace("V", "")
        $CreateBB = $json | ? { $_.paramset -eq "Create" } #| select -ExcludeProperty paramset
        $DestroyBB = $json | ? { $_.paramset -eq "Destroy" } #| select -ExcludeProperty paramset
        $CoDevBB = $json | ? { $_.paramset -eq "CoDev" } #| select -ExcludeProperty paramset


        if (Test-Path $script:ScriptDirectory\Config.JSON) {
            $checkBB = Get-ApprovedEntry -BuidlingBlock $BBName -Version $versionBB
        }
        else {
            $checkBB = $false
        }

            
        if ($checkBB -eq $false) {   
            $test = [PSCustomObject]@{
                Version       = $versionBB
                Create        = $CreateBB
                Destroy       = $DestroyBB
                CoDEv         = $CoDevBB
                BuildingBlock = $BBName
                Approved      = ""
            }
        }
        else {
            Write-host "BB $BBName with version $versionBB is in Approved State" -ForegroundColor Green
            $test = [PSCustomObject]@{
                Version       = $versionBB 
                Create        = $checkBB.Create
                Destroy       = $checkBB.Destroy
                CoDEv         = $checkBB.CoDEv
                BuildingBlock = $BBName
                Approved      = "Yes"
            }
        }
        return $test
    }
    catch {
        throw "Error While processing $($file): $($_.Exception.Message)"
    }
    return $null
}

Function Get-PreviousData(){
    $ParamArray = @()

    $test = [PSCustomObject]@{
        Towers      = @("tower.000ukso.sbp.eyclienthubd.com", "tower.000ukso.sbp.eyclienthub.com")
        HelpMsg     = "This tool can deploy Building Blocks by dynamically generating the Parameters"
        TowerConfig = "True"
    }
    $ParamArray += $test

    if (Test-Path $script:ScriptDirectory\Config.JSON) {
        #$tempConfig = Get-Content $script:ScriptDirectory\Config.JSON -Raw | ConvertFrom-Json
        if ($Script:BBsConfig.Variables -ne $null) {
            $test = new-object psobject -Property @{
                Variables = $Script:BBsConfig.Variables | select -ExcludeProperty $null
            }

            Write-host "Backing Up the DefaultValues" -ForegroundColor Green
            $ParamArray += $test

        }

        if ($Script:BBsConfig.Mandatory -ne $null) {
            $test = new-object psobject -Property @{
                Mandatory = $Script:BBsConfig.Mandatory | select -ExcludeProperty $null
            }

            Write-host "Backing Up the Mandatory Values" -ForegroundColor Green
            $ParamArray += $test
        }

        if ($Script:BBsConfig.DataTypes -ne $null) {
            $test = new-object psobject -Property @{
                DataTypes = $Script:BBsConfig.DataTypes | select -ExcludeProperty $null
            }

            Write-host "Backing Up the DataTypes Values" -ForegroundColor Green
            $ParamArray += $test
        }

        if ($Script:BBsConfig.Dynamic -ne $null) {
            $test = new-object psobject -Property @{
                Dynamic = $Script:BBsConfig.Dynamic | select -ExcludeProperty $null
            }

            Write-host "Backing Up the Dynamic Values" -ForegroundColor Green
            $ParamArray += $test
        }

        if ($Script:BBsConfig.DefaultValues -ne $null) {
            $test = new-object psobject -Property @{
                DefaultValues = $Script:BBsConfig.DefaultValues | select -ExcludeProperty $null
            }
            Write-host "Backing Up the Default Values" -ForegroundColor Green
            $ParamArray += $test
        }

    }

    return $ParamArray
}

Function Generate-Config($ParamArray){
    $Jsonobj = $ParamArray | ConvertTo-Json -Depth 10

    $Jsonobj | Out-File $script:ScriptDirectory\Config.JSON -Force
}

Function Get-Wiki($uGit, $pGit) {

    if ((Test-Path -Path "$script:ScriptDirectory\Wiki") -eq $true) {
        Remove-Item -Path "$script:ScriptDirectory\Wiki" -Recurse -Force
    }

    git clone "https://$($uGit):$($pGit)@eysbp.visualstudio.com/CTP%20-%20Building%20Blocks/_git/Building-Blocks.wiki" "$script:ScriptDirectory\Wiki\WikiContent" | Out-Null
}
Function Get-PWD() {
    $script:ScriptDirectory = $null
    if ($psISE) {
        $script:ScriptDirectory = Split-Path -Path $psISE.CurrentFile.FullPath        
    }
    else {
        $script:ScriptDirectory = $PSScriptRoot
    }

    if ($script:ScriptDirectory -eq $null) {
        $script:ScriptDirectory = $MyInvocation.MyCommand.Path        
    }

    if (!(Test-Path "$script:ScriptDirectory\output")) {
        New-Item -Path "$script:ScriptDirectory\output" -ItemType Directory | Out-Null
        #$script:ScriptDirectory = "$script:ScriptDirectory\output"
    }
    else {
        #$script:ScriptDirectory = "$script:ScriptDirectory\output"
    }

    Write-Verbose "Current Directory Path: $script:ScriptDirectory"

}
Function Get-Parameter {
    [cmdletbinding(
        DefaultParameterSetName = 'Name'
    )]
    Param(
        [Parameter(
            ParameterSetName = 'Name',
            Mandatory = $true
        )]
        [Parameter(
            ParameterSetName = 'Version'
        )]
        [String]
        $BuildingBlock,

        [Parameter(
            ParameterSetName = 'Version'
        )]
        [String]
        $Version
    )
    
    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        $params = $Script:BBsConfig | ? { $_.BuildingBlock -eq $BuildingBlock -and $_.Version -eq $Version }
    }
    else {
        $params = $Script:BBsConfig | ? { $_.BuildingBlock -eq $BuildingBlock }
    }

    $params
}

function Get-ObjectMembers {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [PSCustomObject]$obj
    )
    $obj | Get-Member -MemberType NoteProperty | ForEach-Object {
        $key = $_.Name
        [PSCustomObject]@{Key = $key; Value = $obj."$key" }
    }
}

function GetVSTSCredential {
    [CmdletBinding()]
    Param(
        $userEmail,
        $Token
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $userEmail, $token)))
    return @{Authorization = ("Basic {0}" -f $base64AuthInfo) }
}

function MD-Report() {
    [CmdletBinding()]
    Param(
        $content,
        $path,
        $outputFile,
        $environment
    )

    $mdcontent = "This is the list of the currently available Building Blocks ADO extensions in $environment
| Building Block |  ID  | Template | Name |
|-----------|-----------|-----------|-----------|`n"
    $groupcontent = $content | Sort-Object -Property template | Group-Object -Property buildingblock
    foreach($BB in $groupcontent | Sort-Object -Property name)
    {
        $extensionName = $null
        $extensionID = $null
        $extensiontemplate = $null
        Foreach($property in $BB.Group)
        {
            $extensionName += "$($property.name)<br />"
            $extensionID += "$($property.id)<br />"
            $extensiontemplate += "$($property.template)<br />"
        }
        $mdcontent += "|" +  $($BB.Name) + "|" + $extensionID + "|" + $extensiontemplate + "|" + $extensionName + "|" + "`n"
    }
    $mdcontent | out-file $(Join-Path $path -ChildPath $outputFile) -Force
}
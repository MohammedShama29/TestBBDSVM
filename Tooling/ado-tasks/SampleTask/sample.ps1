[CmdletBinding()]
param()

# For more information on the Azure DevOps Task SDK:
# https://github.com/Microsoft/vsts-task-lib
Trace-VstsEnteringInvocation $MyInvocation
try {
    # Set the working directory.
    #$cwd = Get-VstsInput -Name cwd -Require
    #Assert-VstsPath -LiteralPath $cwd -PathType Container
    #Write-Verbose "Setting working directory to '$cwd'."
    #Set-Location $cwd
    #VARIABLES

    $Type = "##TYPE##"
    $Module=  "BB-Module"
    $TemplateID = "##TEMPLATEID##"
    
    #Import-Module .\ps_modules\VstsTaskSdk\VstsTaskSdk.psm1
    Write-Host "Importing Module $Module"
    $WarningPreference = 'SilentlyContinue'
    Import-Module .\$Module.psm1 -Force  -ErrorAction SilentlyContinue

    $Config = Get-Content .\Config.JSON -Raw | ConvertFrom-Json

    $WarningPreference = 'Continue'

    $myObj= ""| Select-Object extra_vars
    $myObj.extra_vars =  New-Object -TypeName psobject 

    $azureServiceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'azureConnection'
	$azureServiceName = Get-VstsInput -Name $azureServiceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)

    if($Type -eq "Deploy")
    {
        foreach($Wolala in $Config.Create)
        {
            #$retrievedValue = Get-VstsInput -Name $Wolala  -ErrorAction SilentlyContinue
            $retrievedValue = Get-CustomVstsInput -ParameterName $Wolala.Name -Type $Wolala.type
            If (![string]::IsNullOrEmpty($retrievedValue)){
                try {
                    if($Wolala.type -eq "Array")
                    {
                        Write-Host "Detected an Array input"
                        $ret = @()
                        $retrievedValue | ConvertFrom-Json | Foreach {
                            $ret += $_
                        }
                        $myObj.extra_vars | Add-Member -Name $Wolala.Name -Value $ret -MemberType NoteProperty
                    }
                    elseif($Wolala.type -eq "String")
                    {
                        $myObj.extra_vars | Add-Member -Name $Wolala.Name -Value $retrievedValue -MemberType NoteProperty
                    }
                    else {
                        try{
                            $parsedValue = $retrievedValue | ConvertFrom-Json
                        }catch{
                            $parsedValue = $retrievedValue
                        }
                        Write-Host "Retrieved Value for $Wolala" # : $retrievedValue"
                        $myObj.extra_vars | Add-Member -Name $Wolala.Name -Value $parsedValue -MemberType NoteProperty
                    }
                }
                catch {
                    $ErrorMessage = $_.Exception.message
                    Write-host "Error while processing the $($Wolala.Name). Error: $ErrorMessage"
                }

                
            }
        }
    }
    else {
        
        foreach($Wolala in $Config.Destroy)
        {
            $retrievedValue = Get-CustomVstsInput -ParameterName $Wolala.Name -Type $Wolala.type
            If (![string]::IsNullOrEmpty($retrievedValue)){

                try {
                    Write-Host "Retrieved Value for $Wolala" # : $retrievedValue"
                    $myObj.extra_vars | Add-Member -Name $Wolala.Name -Value $retrievedValue -MemberType NoteProperty
                }
                catch {
                    $ErrorMessage = $_.Exception.message
                    Write-host "Error while processing the $($Wolala.Name). Error: $ErrorMessage"
                }

            }
        }

    }

    #Proecssing CoDev parameter
    foreach($Wolala in $Config.CoDev)
    {
        try {
            $retrievedValue = Get-CustomVstsInput -ParameterName $Wolala.Name -Type $Wolala.type
            If (![string]::IsNullOrEmpty($retrievedValue)){
                Write-Host "Retrieved Value for $Wolala" # : $retrievedValue"
                $myObj.extra_vars | Add-Member -Name $Wolala.Name -Value $retrievedValue -MemberType NoteProperty
            }
        }
        catch {
            $ErrorMessage = $_.Exception.message
            Write-host "Error while processing the $($Wolala.Name). Error: $ErrorMessage"
        }

    }

    if ($azureServiceName) {
        # Let the task SDK throw an error message if the input isn't defined.
        $azureEndpoint = Get-VstsEndpoint -Name $azureServiceName -Require

        try {
            $myObj.extra_vars | Add-Member -Name "var_azure_rm_subid" -Value $($azureEndpoint.Data.subscriptionID) -MemberType NoteProperty    
        }
        catch {
            $ErrorMessage = $_.Exception.message
            Write-host "Error while adding the SubID from the Azure RM Service Connection. You already have the SubID configured on the Co-Dev Parameter Set"
        }
        
        #$myObj.extra_vars | Add-Member -Name "AZURE_RM_CLIENTID" -Value $($azureEndpoint.Auth.Parameters.ServicePrincipalId) -MemberType NoteProperty
        #$myObj.extra_vars | Add-Member -Name "AZURE_RM_SECRET" -Value $($azureEndpoint.Auth.Parameters.ServicePrincipalKey) -MemberType NoteProperty

    }


    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    #Gathering the variables   
    $towerEnvironment = "##TOWER##"
	
	$serviceNameInput = Get-VstsInput -Name ConnectedServiceNameSelector -Default 'ansibleTowerConn'
	Write-Host $serviceNameInput
	$serviceName = Get-VstsInput -Name $serviceNameInput -Default (Get-VstsInput -Name DeploymentEnvironmentName)

	Write-Host $serviceName
    if (!$serviceName) {
            # Let the task SDK throw an error message if the input isn't defined.
        Get-VstsInput -Name $serviceNameInput -Require
    }

    $endpoint = Get-VstsEndpoint -Name $serviceName -Require

    $miscParam = Get-CustomVstsInput -ParameterName "additional_param" -Type "string"

    if(![string]::IsNullOrEmpty($miscParam))
    {
        $jsonValue = $miscParam | ConvertFrom-Json
        $temp2 = Get-ObjectMembers -obj $jsonValue
        foreach($value in $temp2)
        {
            try {
                $myObj.extra_vars | Add-Member -Name $value.Key -Value $value.Value -MemberType NoteProperty
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-host "Error while processing the $($value.Key). Error: $ErrorMessage"
            }            
        }
    }

    $towerUser = $endpoint.Auth.Parameters.UserName
    $towerPassword = $endpoint.Auth.Parameters.Password

    $Authentication  = Get-TowerAuthToken -TowerEnvironment $TowerEnvironment -TowerUser $TowerUser -TowerPassword $towerPassword

    $objArray = Get-TowerTemplateCreds -Authentication $Authentication -TemplateID $TemplateID

    $credentials = Get-CustomVstsInput -ParameterName "credentials" -Type "string"
    try {
        if(![string]::IsNullOrEmpty($credentials))
        {
            [int[]]$temparry = $null
            $credentials.Split(",") | foreach {
            $temparry += $_
            }           
            try {
                Write-host "Processing the credentials Object"
                $temparry += $objArray 
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Host "Error While Processing the Credential object. $ErrorMessage"
            }
            
            Add-Member -InputObject $myObj -MemberType NoteProperty -Name "credentials" -Value $temparry
            
        }
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Host "Error While Processing the Credential object. $ErrorMessage"
    }


    $Body = $myObj | ConvertTo-Json -Depth 99
    $Body
            
    $TrimmedJobID = $null
    $responseWait = Get-VstsInput -Name "Wait"
	
	if($responseWait -eq "Wait")
	{
		$wait = $true
	}
	else
	{
		$wait = $false
	}
	
    $TrimmedJobID = $null
    write-verbose "Launch-TowerTemplate -Authentication $Authentication -Body $body -TemplateID $TemplateID"
    $Wr = Launch-TowerTemplate -Authentication $Authentication -Body $body -TemplateID $TemplateID
    If(!($wr.job)){
        Write-Warning "Error Creating the Job"
    }else{
        $JobId=[string]$wr.job
        $TrimmedJobID= $JobId.trim()
        Write-Verbose "Job $TrimmedJobID Created" -Verbose
        Write-Host $TrimmedJobID

        If($wait){
            write-verbose "Get-TowerJobStatus -Authentication $Authentication -JobIDs $TrimmedJobID -Wait" -verbose
            Get-TowerJobStatus -Authentication $Authentication -JobIDs $TrimmedJobID -Wait
        }
    }

    $bbName = "##BBName##"
    $resourceResponse = Get-ResourceNameRegEx -Authentication $Authentication -JobID $TrimmedJobID -BBName $bbName
    $resourceName = $resourceResponse.Name
    $resourceID = $resourceResponse.ID

    if($resourceName -eq $null -and $bbName -like "*capsule*")
    {
        $resourceResponse = Get-ResourceNameRegEx -Authentication $Authentication -JobID $TrimmedJobID -BBName "resource-group"
        $resourceName = $resourceResponse.Name
        $resourceID = $resourceResponse.ID
    }

    try {
        
        $multiResourceResponse = Get-ResourceExMultiResource -Authentication $Authentication -JobID $TrimmedJobID 
        ForEach($item in $multiResourceResponse)
        {
            Write-Output ("##vso[task.setvariable variable=$($item.Name);isOutput=true]$($item.ID)")
            Write-Host ("Multiple resources detected, please use $($item.Name) as reference to get the value $($item.ID)")
        }
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Host "Warning while processing multi resource. $ErrorMessage"
    }

    Write-Output ("##vso[task.setvariable variable=name;isOutput=true]$resourceName")
    Write-Output ("##vso[task.setvariable variable=id;isOutput=true]$resourceID")
    Write-Output ("##vso[task.setvariable variable=jobid;isOutput=true]$TrimmedJobID")

    try
    {
        if($resourceResponse.private_ip -ne $null)
        {
            $tempIp = $resourceResponse.private_ip
            Write-Host "IP: $($resourceResponse.private_ip)"
            Write-Output ("##vso[task.setvariable variable=ip;isOutput=true]$tempIp")
        }
    }
    catch
    {
        $ErrorMessage = $_.Exception.message
        Write-Host "Error while gathering the IP details. $ErrorMessage"
    }
    
    Write-Host "Resource Name: $resourceName"
    Write-Host "Resource ID: $resourceID"
    Write-Host "Ansible Job ID: $TrimmedJobID"
    

    # Output the message to the log. 
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}

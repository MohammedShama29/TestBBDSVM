param(
  $functionName = "BB-Create_app-service-plan-V1.0.0",
  $outPath = "C:\Temp\",
  $id = "03dbce00-8159-11e9-b9a2-dd5b8ed3f195",
  $name = "BBCreateWinVM",
  $friendlyName = "BB-Create-WinVM",
  $description = "BB-Testing-Task",
  $author = "Platform Engineering - Building Blocks",
  $helpMarkDown = "This is the vNextBB",
  $Major = "1",
  $Minor = "0",
  $Patch = "0",
  $instanceNameFormat = 'Deploy WinVM $(message)', 
  #[Parameter(mandatory=$true)]$inputs,
  $Nodetarget = "sample.js",
  $powershellTarget = "sample.ps1",
  $BBConfig,
  $type
)

function Create-JsonTaskFileInputs {
  param(
    $functionName = "BB-Create_app-service-plan-V1.0.0"
  )

  $Inputs = $null

  foreach ($item in $BBConfig.Create) {
    $item | foreach { $_.PSObject.Properties.Remove('paramset') }
  }
        
  foreach ($item in $BBConfig.Destroy) {
    $item | foreach { $_.PSObject.Properties.Remove('paramset') }
  }

  foreach ($item in $BBConfig.CoDev) {
    $item | foreach { $_.PSObject.Properties.Remove('paramset') }
  }

  if ($type -eq "Deploy") {
    #$MandatoryParameters = $BBConfig.Create | Where-Object required -eq $true 
    #$OptionalParameters = $BBConfig.Create | Where-Object required -ne $true
    #$OptionalParameters += $BBConfig.CoDev

    $Inputs += $BBConfig.Create #| Where-Object required -eq $true 
    #$Inputs += $BBConfig.Create | Where-Object required -ne $true
    $Inputs += $BBConfig.CoDev
  }
  else {
    #$MandatoryParameters = $BBConfig.Destroy | Where-Object required -eq $true 
    #$OptionalParameters = $BBConfig.Destroy | Where-Object required -ne $true 
          
    $Inputs += $BBConfig.Destroy #| Where-Object required -eq $true 
    #$Inputs += $BBConfig.Destroy | Where-Object required -ne $true 
    $Inputs += $BBConfig.CoDev
  }

  $Inputs += @([PSCustomObject]@{
    name         = "azureConnection";
    type         = "connectedService:AzureRM"; 
    label        = "AzureRM Subscription";  
    required     = $false; 
    helpMarkDown = "Select the Azure Resource Manager subscription for the deployment."; 
  } )

  $Inputs += @([PSCustomObject]@{
      name         = "ansibleTowerConn";
      type         = "connectedService:ansibleTower"; 
      label        = "Ansible Tower service connection";  
      required     = $true; 
      helpMarkDown = "Select an Ansible Tower service connection. Required for deploy the ansible template."; 
    } )

  $Inputs += @([PSCustomObject]@{
      name         = "credentials";
      type         = "string"; 
      label        = "credentials";  
      required     = $true; 
      helpMarkDown = "Extra Credentials to pass. Comman separated credetial object numbers gathered from the tower. For ex: 1,2,3"; 
    } )

  $Inputs += @([PSCustomObject]@{
      name         = "additional_param";
      type         = "string"; 
      label        = "Additional Param";  
      groupname    = "optional";
      required     = $false; 
      helpMarkDown = 'This input can be used in case of any misc parameters to be passed. Input is expected in JSON format. For ex: {"param1": "value", "param2": "Value"}'; 
    } )

  $inputs += @([PSCustomObject]@{
      name         = "Wait";
      type         = "pickList"; 
      label        = "Action"; 
      defaultValue = "Wait"; 
      required     = $true; 
      helpMarkDown = "Waits for the job to complete otherwise it will go to the next job without waiting for the completion of the existing deployment"; 
      options      = @{
        Wait   = "Wait";
        NoWait = "Dont Wait"
      }
    } )
         
  $Inputs | ConvertTo-Json
}

$inputs = Create-JsonTaskFileInputs -functionName $functionName 
   

$JsonTaskFile = '{
  "id": "' + $id + '",
  "name": "' + $name + '",
  "friendlyName": "' + $friendlyName + '",
  "description": "' + $description + '",
  "author": "' + $author + '",
  "helpMarkDown": "' + $helpMarkDown + '",
  "category": "Deploy",
  "visibility": [
    "Build",
    "Release"
  ],
  "demands": [],
  "version": {
    "Major": "' + $Major + '",
    "Minor": "' + $Minor + '",
    "Patch": "' + $Patch + '"
  },
  "minimumAgentVersion": "1.95.0",
  "instanceNameFormat": "' + $instanceNameFormat + '",
  "groups": [
  {
    "name": "mandatory",
    "displayName": "Mandatory Parameters",
    "isExpanded": true
  },
  {
    "name": "optional",
    "displayName": "Optional Parameters",
    "isExpanded": true
  },
  {
    "name": "codev",
    "displayName": "Co-Dev Parameters",
    "isExpanded": true
  }
  ],
  "inputs": ' + $inputs + ',
  "dataSourceBindings": [],
  "execution": {
    "PowerShell3": {
      "target":  "' + $powershellTarget + '"
    }
  }
}'

#if(!(Test-Path $outPath)){
#    New-Item $outPath -ItemType Directory
#}
$JsonTaskFile | Out-File $outPath\task.json -Encoding ascii 
param(
    $BuildingBlock,
    $BranchName,
    $userMail,
    $PatToken,
    $TowerProjectId,
    $TowerUserName,
    $TowerPassword,
    $Environment
)

Function Get-TaskFiles($BBs, $Config, $environment, $towerEnv, $BuildIDs) {
    foreach ($BB in $BBs) {

        $Function = [PSCustomObject]@{
            Name = "$($BB.TemplateName)"
        }

        Write-Host "Processing : $($BB.BuildingBlock) with Function Name: $($Function.Name)"        

        $bbName = $BB.BuildingBlock.Remove(0, $BB.BuildingBlock.IndexOf("-") + 1)

        Write-Host "Name: $bbName"

        $bbConfig = $Config | ? { $_.BuildingBlock -eq $bbName -and $_.Version -eq $BB.Version }

        if ($bbConfig -ne $null) {
    
            New-Item "$PSScriptRoot/output/$($Function.Name)" -ItemType Directory -Force | Out-Null

            Copy-Item -Path "$PSScriptRoot/$sampleTask/*" -Destination "$PSScriptRoot/output/$($function.Name)" -Include "sample.ps1" -Recurse -Container -Force

            $Jsonobj = $bbConfig | ConvertTo-Json -Depth 10

            $Jsonobj | Out-File "$PSScriptRoot/output/$($Function.Name)/Config.JSON" -Force

            #Create TaskFile
            #azure-
            if ($bbConfig.Version -eq "NONCERTIFIED") {
                $friendlyname = "$($environment.ToLower())-$($bbConfig.BuildingBlock)-NONCERT"
            }
            else {
                $friendlyname = "$($environment.ToLower())-$($bbConfig.BuildingBlock)-V$($bbConfig.Version)"
            }
            $description = $function.Name.replace(".", "-").replace("_", "-")
            $name = $function.Name.replace("-", "").replace("_", "").replace(".", "")

            #accomodate 40 chars for STAGING Templates
            $friendlyname = $friendlyname -replace "staging-", "stg-" -replace "additional-domain-controller", "ad-dc"

                
            Write-Host "Friendly Name: $friendlyname"
            Write-Host "Name: $name"

            $existBuildID = $BuildIDs | Where-Object name -eq "$name"
            if ($existBuildID) {
                $id = $existBuildID.id
                Write-Host "Existing detected with the name $($existBuildID.name) and ID $id" -ForegroundColor Green 
            }
            else {
                $id = (New-Guid).Guid
            }
            #VSTS ONLY SHOWS ONE MAJOR VERSION OF EACH TASK. TO OVERRIDE A VERSION THE FLAX ON TFX DOES NOT WORK, YOU NEED TO INCREMENT THE VERSION.  
            $major = 1
            #MINOR WILL HAVE THE REAL MINOR_PATCH of the BB version
            $minor = 80

            $date = (Get-Date)
            #PATCH CURRENTLY IS USED TO INCREMENT THIS
            $patch = ("$($date.Year)" + "$($date.DayOfYear)" + "$(Get-Date -Format "hhmmss")").Substring(2, 9)

            $type = $null
            if ($function.name -like "*Create*") {
                $type = "Deploy"
                $instanceFormat = "BB - Deploy - $name"
            }
            elseif ($function.name -like "*Destroy*") {
                $type = "Destroy"
                $instanceFormat = "BB - Remove - $name"
            }
            else {
                $instanceFormat = $name
            }

            Write-Host "Instance Format $instanceFormat"

            $taskArguments = @{
                "id"                 = $id
                "name"               = $name
                "outPath"            = "$PSScriptRoot\output\$($function.Name)"
                "functionName"       = $function.Name
                "friendlyName"       = $friendlyname
                "Major"              = $major
                "Minor"              = $minor
                "Patch"              = $patch
                "instanceNameFormat" = $instanceFormat
                "BBConfig"           = $bbConfig
                "Type"               = $type
                "description"        = $description
                "helpMarkDown"       = $bbname
            }
            
            & "$PSScriptRoot/Create-VstsJsonTaskFile.ps1" @taskArguments

            (Get-Content $PSScriptRoot\output\$($Function.Name)\sample.ps1 ) -replace "##TYPE##", "$type" -replace "##TEMPLATEID##", "$($BB.TemplateID)" -replace "##TOWER##", "$towerEnv" -replace "##BBName##", "$bbName" | Set-Content $PSScriptRoot\output\$($Function.Name)\sample.ps1

        }
        else {
            Write-Warning "BB - $bbName with Version $($BB.Version) not available in Config" 
        }
    }

}

$here = (Get-Location).Path

$BranchName = $BranchName.replace("refs/heads/", "")

$version = if ($BranchName -eq "master") { "NONCERTIFIED" } else { $BranchName }
$version = $version.replace("version/", "")

if ($BranchName -ne "master" -and $BranchName -NotLike "version/*") {
    Write-Host "Not a version branch"
    exit
}

if (-Not(Test-Path "$here\ReadMe\$BuildingBlock\$version\README.md")) {
    Write-Host "README not found"
    exit
}

#Variables
$sampleTask = "SampleTask"
$Module = "BB-Module"

#Import Module
Import-Module Newtonsoft.Json
Import-Module $PSScriptRoot\$Module.psm1
If (Get-Module -Name $Module) {
    Write-Host "Module Succesfully Imported"    
}
else {
    throw "No module found"
}

$TowerEnvironment = if ($Environment -eq "PROD") { "Production" } else { "Development" }

if ($Environment -eq "DEV" -or $Environment -eq "QA") {
    $orgAdo = "eysbp-poc"
}
else {
    $orgAdo = "eysbp"
}

Write-host "The Org selected is: $orgAdo"

#Get list of Projects
$Token = GetVSTSCredential -userEmail $userMail -Token $PatToken
$wr = Invoke-WebRequest https://dev.azure.com/$orgAdo/_apis/distributedtask/tasks?visibility%5B%5D=Build -Method Get -Headers $Token -ContentType "application/json" -UseBasicParsing 
$json = $wr | ConvertFrom-JsonNewtonsoft

$BuildIDs = $json.value | ? { $_.description -like "*-bb-*" } | foreach { 
    @([PSCustomObject]@{
        name = $_.name;
        id   = $_.id
    })
}

Write-Host "Authenticating with Ansible Tower"
$towerToken = Get-TowerAuthToken -TowerEnvironment $TowerEnvironment -TowerUser $TowerUserName -TowerPassword $TowerPassword

Write-Host "Getting templates from Ansible Tower"
$BBs = Get-CTPBuildingBlocks -towerToken $towerToken -projecid $TowerProjectId -query "or__name=$($Environment.ToLower())-bb-create-$BuildingBlock-$Version&or__name=$($Environment.ToLower())-bb-destroy-$BuildingBlock-$Version"

if ($BBs.length -ne 2) {
    throw "Templates not found"
}

Write-Host "Processing README parameters"
$Config = List-Parameters-Single-File -file "$here\ReadMe\$BuildingBlock\$version\README.md" -GenerateConfig -version $version -BBName $BuildingBlock

if (Test-Path "output") { Remove-Item "output" -Recurse -Force }

#Common Files in a Directory
New-Item "$PSScriptRoot\output\common" -ItemType Directory -Force | Out-Null

Copy-Item -Path "$PSScriptRoot/$sampleTask/*" -Destination "$PSScriptRoot/output/common" -Recurse -Force -Verbose

Remove-Item -Path "$PSScriptRoot/output/common/sample.ps1" -Force -Verbose

Copy-Item -Path "$PSScriptRoot/BB-Module.psm1" -Destination "$PSScriptRoot/output/common" -Force -Verbose

Get-TaskFiles -BBs $BBs -Config $Config -environment $Environment -towerEnv $TowerEnvironment -BuildIDs $BuildIDs

Write-Host "Publishing"

$releaseArguments = @{
    "BuildingBlock" = $BuildingBlock
    "Version"       = $Version
    "Environment"   = $Environment
    "PatToken"      = $PatToken
    "ADOHeader"     = $Token
}
& "$PSScriptRoot/Release-Tasks.ps1" @releaseArguments

Write-Host "Done"
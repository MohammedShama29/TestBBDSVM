param(
  [switch]$SkipSoftware,
  [switch]$SkipTest,
  [string]$repoStorageAccountName,
  [string]$artifactStorageAccountName
)

$scriptsLocation = $PSScriptRoot
$here = (Get-Location).Path

$artifactStorageContainer = (Get-Item -Path $here).Name
$BranchName = &git rev-parse --abbrev-ref HEAD 
$version = if($BranchName -eq "master") { "NONCERTIFIED" } else { $BranchName }
$version = $version.replace("version/", "") 
$version = $version.replace("feature/", "")
$version = $version.replace("bugfix/", "")

If (!$SkipSoftware) {
  if ($repoStorageAccountName -eq '') {
    throw('repoStorageAccountName parameter must be provided')
  }

  Write-Host "Downloading Software..."
  & $scriptsLocation\Download-Software.ps1
}

If (!($SkipTest)) {
  $TestResults = Invoke-Pester -Script @{ Path = "$scriptsLocation\azureDeploy.tests.ps1"; Parameters = @{ WorkingFolder = (Get-Location).Path } } -PassThru

  if ($TestResults.FailedCount -gt 0) {
    throw "Test Task failed"
  }
}

#Prepare Locally the files
Write-Host "Cleaning Up Output folder"
if (Test-Path "$here\output") {
  Get-ChildItem "$here\output" | Remove-Item -force -Recurse
}
Else {
  New-Item "$here\output" -ItemType Directory
}
  
& $scriptsLocation\build.ps1 "$BranchName"

#Login to Azure
Write-Host "Logging in..."
$subscriptions = $null
try { $subscriptions = Get-AzSubscription }catch { }
if ($null -eq $subscriptions) { Login-AzAccount -ErrorAction Stop }

Function Check-StorageAccountRG( $StorageAccountName) {
  $subs = Get-AzSubscription | Where-Object name -like "EY-CTSBP-*-HUB*" | Select-Object name, id
  #$subs
  Foreach ($sub in $subs) {
    write-verbose "Checking $($Sub.name)"  -verbose
        
    Select-AzSubscription -SubscriptionId $sub.id | out-null
    $StoFound = Get-AzResource | Where-Object name -eq $artifactStorageAccountName
    If ($StoFound) {
      write-verbose "Found it on Sub $($Sub.name)" -verbose
      $ResourceGroupname = $StoFound.ResourceGroupName
      Break
    }
  }
  if (!($ResourceGroupname)) { throw "No account found" }else { $ResourceGroupname }
}
function Check-Container ($Container, $StorageContext, [switch]$Clean) {

  if ($Container) {
    If (!(Get-AzStorageContainer -Context $StorageContext -Name $Container -ErrorAction SilentlyContinue)) {
      Write-Host "Create a Blob Container ($Container) in the Storage Account"
      New-AzStorageContainer -Context $StorageContext -Name $Container
    }
    else {
      Write-Host "Using existing blob container ($Container)"
    }
    
    if ($Clean) {
      Write-Host "Removing all BLOB from $Container"
      Get-AzStorageBlob -Container $Container -Context $StorageContext | Remove-AzStorageBlob -Force -Verbose
    }
  }
}


#Publish Playbooks
$AnsiblePlaybooks = New-Item -Path $(Split-Path -Path $here) -Name Ansible-Playbooks -Type Directory -Force
$bbPlaybooks = New-Item -Path $AnsiblePlaybooks.FullName -Name $($here | Split-Path -Leaf) -ItemType Directory -Force

$playbooksFolder = $bbPlaybooks.FullName
if (Test-Path -Path "$playbooksFolder\$version") {
  Get-ChildItem -Path "$playbooksFolder\$version" -Recurse | Remove-Item -Force -Recurse
}

$bbVersionFolder = New-Item -Path $bbPlaybooks.FullName -Name $version -Type Directory -Force
Copy-Item -Path "$here\output\$version\Ansible\playbooks\*" -Destination $bbVersionFolder.FullName -Filter "*.*" -Recurse 


################

#artifact Storage
$artifactresourceGroupName = Check-StorageAccountRG -StorageAccountName  $artifactStorageAccountName
Write-Host "Obtain the Storage Account authentication keys using Azure Resource Manager (ARM)"
$artifactKeys = Get-AzStorageAccountKey -ResourceGroupName $artifactresourceGroupName -Name $artifactStorageAccountName;

Write-Host "Use the Azure.Storage module to create a Storage Authentication Context"
$artifactStorageContext = New-AzStorageContext -StorageAccountName $artifactStorageAccountName -StorageAccountKey $artifactKeys[0].Value;

Check-Container -Container $artifactStorageContainer -StorageContext $artifactStorageContext

Write-Host "Publishing ""$here\output\Artifacts"" folder content"
  
$artPath = "$here\output\$version\Artifacts\"
Get-ChildItem $artPath -File | ForEach-Object {
  $fileName = $version + "\" + $_.Name
  Set-AzStorageBlobContent -Context $artifactStorageContext -Container $artifactStorageContainer -File $_.FullName -Blob $fileName -Verbose -Force
}

################

if (!$SkipSoftware) {
  #repo Storage
  
  $repoResourceGroupName = Check-StorageAccountRG -StorageAccountName  $repoStorageAccountName
  Write-Host "Obtain the Storage Account authentication keys using Azure Resource Manager (ARM)"
  $repoKeys = Get-AzStorageAccountKey -ResourceGroupName $repoResourceGroupName -Name $repoStorageAccountName;

  Write-Host "Use the Azure.Storage module to create a Storage Authentication Context"
  $repoStorageContext = New-AzStorageContext -StorageAccountName $repoStorageAccountName -StorageAccountKey $repoKeys[0].Value;
  

  $softPath = "$here\output\$version\Software"
  Write-Host $softPath
  ForEach ($Folder In (Get-ChildItem $softPath -Directory)) {
    Write-Host ("Publishing ""{0}"" folder content" -f $Folder.FullName)
    Check-Container -StorageContext $repoStorageContext -Container $Folder.Name.ToLower()
    Get-ChildItem -Path $Folder.FullName -File | ForEach-Object {
      $fileName = $version + "\" + $_.Name;  
      Set-AzStorageBlobContent -Context $repoStorageContext -Container $Folder.Name.ToLower() -File $_.FullName -Blob $fileName -Verbose -force
    }
  }
}
param(
    [string]$StorageAccountName,
    [string]$StorageContainer,
    [string]$BranchName
)

$here = (Get-Location).Path

Function Get-StorageAccountRG($StorageAccountName){
  $subs = Get-AzSubscription | Where-Object { $_.Name -like "EY-CTSBP-*-HUB*" }
  Foreach ($sub in $subs){
    Write-Verbose -Message "Checking $($Sub.name)"  -verbose
    Set-AzContext $sub | out-null
    $StoFound= Get-AzResource | Where-Object { $_.Name -eq $StorageAccountName }
    If ($StoFound){
      Write-Verbose -Message "Found it on Sub $($Sub.name)" -verbose
      $ResourceGroupname = $StoFound.ResourceGroupName
      Break
    }
  }
  if(!($ResourceGroupname)){throw "No account found"}else{$ResourceGroupname}
}

function Set-Container ($Container, $StorageContext, [switch]$clean){
  if($Container){
    If(!(Get-AzStorageContainer -Context $StorageContext -Name $Container -ErrorAction SilentlyContinue))
    {
      Write-Verbose -Message "Create a Blob Container ($Container) in the Storage Account"
      New-AzStorageContainer -Context $StorageContext -Name $Container
    }
    else {
      Write-Verbose -Message "Using existing blob container ($Container)"
    }
    if($Clean)
    {
      Write-Verbose -Message  "Removing all BLOB from $Container"
      Get-AzStorageBlob -Container $Container -Context $StorageContext | Remove-AzStorageBlob -Force -Verbose
    }
  }
}

#Obtain Storage Account information and context
Write-Verbose -Message "Obtaining Storage Account information and context"
$resourceGroupName =  Get-StorageAccountRG -StorageAccountName  $StorageAccountName
Write-Verbose -Message "Obtain the Storage Account authentication keys using Azure Resource Manager (ARM)"
$storageKeys = Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $StorageAccountName;
Write-Verbose -Message "Use the Azure.Storage module to create a Storage Authentication Context"
$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageKeys[0].Value;
Set-Container -Container $StorageContainer -StorageContext $StorageContext

#Calculate directory entry points
$version = if($BranchName -eq "master") { "NONCERTIFIED" } else { $BranchName }
$version = $version.replace("version/", "") 
$version = $version.replace("feature/", "")
$version = $version.replace("bugfix/", "")

Write-Verbose -Message "Processing version: $version"
$artPath = "$here\$version\Artifacts\"
Get-ChildItem $artPath -File | ForEach-Object {
  $fileName = $version+"\"+$_.Name    
  Set-AzStorageBlobContent -Context $StorageContext -Container $StorageContainer -File $_.FullName -Blob $fileName -Verbose -Force
}
param(
    [string]$StorageAccountName,
    [string]$BranchName
)

$here = (Get-Location).Path

Function Get-StorageAccountRG($StorageAccountName){
  $subs = Get-AzSubscription | Where-Object { $_.name -like "EY-CTSBP-*-HUB*" }
  Foreach ($sub in $subs){
    Write-Verbose -Message "Checking $($Sub.name)"  -verbose
      
    Set-AzContext $sub | out-null
    $StoFound= Get-AzResource | Where-Object { $_.name -eq $StorageAccountName }
    If ($StoFound){
      Write-Verbose -Message "Found it on Sub $($Sub.name)" -verbose
      $ResourceGroupname = $StoFound.ResourceGroupName
      Break
    }
  }
  if( !($ResourceGroupname) ) { throw "No account found" } else { $ResourceGroupname }
}

function Set-Container ($Container, $StorageContext, [switch]$clean){
  if($Container){
    if(!(Get-AzStorageContainer -Context $StorageContext -Name $Container -ErrorAction SilentlyContinue))
    {
      Write-Verbose -Message "Create a Blob Container ($Container) in the Storage Account"
      New-AzStorageContainer -Context $StorageContext -Name $Container
    }
    else {
      Write-Verbose -Message "Using existing blob container ($Container)"
    }
    if($Clean)
    {
      Write-Verbose -Message "Removing all BLOB fomr $Container"
      Get-AzStorageBlob -Container $Container -Context $StorageContext | Remove-AzStorageBlob -Force -Verbose
    }
  }
}

#Obtain Storage Account information and context
Write-Verbose -Message "Obtaining Storage Account information and context"
$repoResourceGroupName =  Get-StorageAccountRG -StorageAccountName  $StorageAccountName
Write-Verbose -Message "Obtain the Storage Account authentication keys using Azure Resource Manager (ARM)"
$repoKeys = Get-AzStorageAccountKey -ResourceGroupName $repoResourceGroupName -Name $StorageAccountName;
Write-Verbose -Message "Use the Azure.Storage module to create a Storage Authentication Context"
$repoStorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $repoKeys[0].Value;

#Calculate directory entry points
$version = if($BranchName -eq "master") { "NONCERTIFIED" } else { $BranchName }
$version = $version.replace("version/", "") 
$version = $version.replace("feature/", "")
$version = $version.replace("bugfix/", "")

Write-Verbose -Message "Processing version: $version"
if(Test-Path -Path "$here\$version\Software") {
  $softPath = "$here\$version\Software"
  ForEach($Folder In (Get-ChildItem $softPath -Directory))
  {
    Set-Container -StorageContext $repoStorageContext -Container $Folder.Name.ToLower()
    Write-Verbose -Message ("Publishing ""{0}"" folder content" -f $Folder.FullName)
    Get-ChildItem -Path $Folder.FullName -File | ForEach-Object {
      $fileName = $version+"\"+$_.Name;  
      Set-AzStorageBlobContent -Context $repoStorageContext -Container $Folder.Name.ToLower() -File $_.FullName -Blob $fileName -Verbose -force
    }
  }
} else {
  Write-Verbose -Message "No 'Software' folder was found."
}
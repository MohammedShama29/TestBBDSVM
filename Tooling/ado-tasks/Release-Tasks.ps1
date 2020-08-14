param(
    $BuildingBlock,
    $Version,
    $Environment,
    $Publisher = "CTPE",
    $PatToken,
    $ADOHeader
)

$json = @"
{
    "manifestVersion": 1,
    "id": "",
    "name": "",
    "version": "",
    "publisher": "",
    "targets": [
        {
            "id": "Microsoft.VisualStudio.Services"
        }
    ],
    "description": "",
    "categories": [
        "Azure Pipelines"
    ],
    "icons": {
        "default": "common/icon.png"
    },
    "files": [
    ],
    "contributions": []
}
"@

$name = "$($Environment.ToLower())-bb-$BuildingBlock-$Version"
$id = $name.replace(".", "-")

$here = "$PSScriptRoot/output"

$items = Get-ChildItem -Directory $here | ? { $_.name -like "$Environment-bb-*-$BuildingBlock-$Version" } | select -Property Name, FullName

if ($items.length -ne 2) {
    throw "Required tasks not found"
}

$output = $json | ConvertFrom-Json
$output.id = $id
$output.name = $name
$output.publisher = $publisher
$output.description = $name
$output.version = Get-Date -Format "1.1.yMMdd.1Hmmss"

foreach ($bb in $items) {
    Write-Host "Processing $($bb.Name)"
    Copy-Item -Path "$here/common/*" -Destination "$($bb.FullName)" -Recurse -Container:$True -Force -Verbose
    $path = New-Object -TypeName psobject
    $path | Add-Member -MemberType NoteProperty -Name path -Value "$($bb.name)"
    $path | Add-Member -MemberType NoteProperty -Name addressable -Value $True
    $output.files += $path
    $inputObject = New-Object -TypeName psobject
    $target = @("ms.vss-distributed-task.tasks")
    $prop = New-Object -TypeName psobject
    $prop | Add-Member -MemberType NoteProperty -Name name -Value "$($bb.name)"
    $inputObject | Add-Member -MemberType NoteProperty -Name id -Value "$($bb.name)"
    $inputObject | Add-Member -MemberType NoteProperty -Name type -Value "ms.vss-distributed-task.task"
    $inputObject | Add-Member -MemberType NoteProperty -Name targets -Value $target
    $inputObject | Add-Member -MemberType NoteProperty -Name properties -Value $prop
    $output.contributions += $inputObject
}


if ($Environment -eq "DEV" -or $Environment -eq "QA") {
    $orgAdo = "eysbp-poc"
}
else {
    $orgAdo = "eysbp"
}

Write-host "The Org selected is: $orgAdo"

$output | ConvertTo-JSON -Depth 100 | Out-file $PSScriptRoot/output/vss-extension-$name.json -Encoding ascii
Write-Host "##########################################################################################"
Write-Host "##########################################################################################"
Write-Host "##########################################################################################"
$orgAdo
Write-Host "##########################################################################################"
Write-Host "##########################################################################################"
Write-Host "##########################################################################################"
$output | ConvertTo-JSON -Depth 100
Write-Host "##########################################################################################"
Write-Host "##########################################################################################"
Write-Host "##########################################################################################"

tfx extension publish --manifest-globs $here/vss-extension-$name.json --token $PatToken --root $here --share-with $orgAdo

Write-Host "Published $($item.Name)"

Write-Host "Checking if installed"

try{
    Invoke-WebRequest https://extmgmt.dev.azure.com/$orgAdo/_apis/extensionmanagement/installedextensionsbyname/$publisher/$($id)?api-version=5.1-preview.1 -Method Get -Headers $ADOHeader -ContentType "application/json" -UseBasicParsing
    Write-Host "Extension in already installed in $orgAdo"
}catch{
    $StatusCode = $_.Exception.Response.StatusCode.value__
    Write-Host "Received status code: $StatusCode"
    if($StatusCode -eq 404){
        Write-Host "Trying to install extension"
        Invoke-WebRequest https://extmgmt.dev.azure.com/$orgAdo/_apis/extensionmanagement/installedextensionsbyname/$publisher/$($id)?api-version=5.1-preview.1 -Method Post -Headers $ADOHeader -ContentType "application/json" -UseBasicParsing
        Write-Host "Installation completed"
    }else{
        throw $_.Exception
    }
}
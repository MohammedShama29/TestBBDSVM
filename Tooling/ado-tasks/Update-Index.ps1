param(
    $userMail,
    $PatToken,
    $Environment,
    $outputFile = "Index.md",
    $BranchName
)

$BranchName = $BranchName.replace("refs/heads/", "")
$here = (Get-Location).Path

if ($BranchName -ne "master" -and $BranchName -NotLike "version/*") {
    Write-Host "Not a version branch"
    exit
}

#Variables
$sampleTask = "SampleTask"
$Module = "BB-Module"


$modulePath = Join-Path $PSScriptRoot -ChildPath "$Module.psm1"

#Import Module
Import-Module $modulePath
If (Get-Module -Name $Module) {
    Write-Host "Module Succesfully Imported"    
}
else {
    throw "No module found"
}

Function Get-Page()
{
    param(
        [string]$FileName,
        $Token
    )
   

  $tempFileName = $FileName.Replace(".md","").Replace("-","%20")
  $Page = 'https://dev.azure.com/eysbp/CTP%20-%20Building%20Blocks/_apis/wiki/wikis/Building-Blocks.wiki/pages?path=%2FBuilding%20Blocks%2FBuilding%20Blocks%20ADO%20CustomExtension%20Index%2F{0}&api-version=5.1' -f $tempFileName

  $pageDetails = Invoke-WebRequest -Method Get -Uri $Page -Headers $Token -ContentType application/json

  return $pageDetails

}


Function Update-Wiki()
{
    param(
        [string]$FileName,
        $Token,
        $FilePath
    )

    $details = Get-Page -FileName $FileName -Token $Token
    
    [string]$Etag = $details.Headers.ETag
    $Token.Remove("If-Match")

    if($Etag -ne $null)
    {
       $Token.Add("If-Match",$Etag) 
    }
    
    $tempFileName = $FileName.Replace(".md","").Replace("-","%20")
    $Page = 'https://dev.azure.com/eysbp/CTP%20-%20Building%20Blocks/_apis/wiki/wikis/Building-Blocks.wiki/pages?path=%2FBuilding%20Blocks%2FBuilding%20Blocks%20ADO%20CustomExtension%20Index%2F{0}&api-version=5.1' -f $tempFileName

    $data = @{
      "content"= "$(Get-Content -Path $FilePath -Raw)"
    }

    try
    {
        Invoke-RestMethod -Method Put -Uri $Page -Headers $Token -Body $($data | ConvertTo-Json) -ContentType application/json
        #throw "fail"
    }
    catch
    {
        $ErrorMessage = $_.Exception.Message
        Write-host "$ErrorMessage"
        throw $ErrorMessage
    }
    finally
    {
        $Token.Remove("If-Match")
    }

}


#List all the Custom Extensions
$Token = GetVSTSCredential -userEmail $userMail -Token $PatToken
$wr = Invoke-WebRequest https://dev.azure.com/eysbp/_apis/distributedtask/tasks?visibility%5B%5D=Build -Method Get -Headers $Token -ContentType "application/json" -UseBasicParsing 
$content = $wr.Content 
$json = $content | ConvertFrom-JsonNewtonsoft -Verbose

$BuildIDs=$json.value | Where-Object { $_.name -like "$($Environment.ToLower())bb*" } | foreach { 
    @([PSCustomObject]@{
        name = $_.friendlyName;
        id = $_.id;
        template = $_.description
        buildingblock = $_.helpMarkDown
    })
}

if (-not(Test-Path "$(Join-Path $here -ChildPath "output")"))
{
    New-Item "$(Join-Path $here -ChildPath "output")" -ItemType Directory -Force | Out-Null
}


MD-Report -content $BuildIDs -path output -outputFile $outputFile -environment $Environment

Write-Host "MD file created successfully"

$i=0
$flag = $false

do{

try
{
    $i++
    Write-Host "Attempt $i of 10"

       if ((Test-Path "$(Join-Path $here -ChildPath "output/$outputFile")") -eq $true)
       {
       
            Write-Host "Copying the Index File to the Wiki"
            #Uncomment this to save the changes to Wiki
            Update-Wiki -FileName $outputFile -Token $Token -FilePath "$(Join-Path $here -ChildPath "output/$outputFile")"

            Write-Host "Done"
       }
       else
       {
            throw "File does not exists at location: $(Join-Path $here -ChildPath "output/$outputFile")"
       }
       $flag = $true

}
catch
{
    $ErrorMessage = $_.exception.message
    Write-host "$ErrorMessage"
    Start-Sleep -Seconds $(Get-Random -Minimum 5 -Maximum 30)
}
finally{
    If($i -ge 10)
    {
        $flag = $true
        throw "Error while updating the Index. Please check above logs for more information"
    }  
}
} while ($flag -ne $true)



param(
    [parameter(Mandatory = $true)][string]$uGit,
    [parameter(Mandatory = $true)][string]$pGit,
    [parameter(Mandatory = $true)][string]$uTower,
    [parameter(Mandatory = $true)][string]$pTower,
    [string]$tower = "tower.000ukso.sbp.eyclienthub.com",
    [string]$outputFile = "Index.md",
    [string]$projectID = "236",
    [parameter(Mandatory = $true)][string]$environment
)

$here = (Get-Location).Path

if ($environment -eq "PROD") {
    $tower = "tower.000ukso.sbp.eyclienthub.com"
    $createdBy = "/api/v2/users/10/"
} else {
    $tower = "tower.000ukso.sbp.eyclienthubd.com"
    $createdBy = "/api/v2/users/137/"
}


Function Get-FileContents
{
    param(

        [string] $repoName,
        [string] $branchName,
        [string] $projectName,
        $Token
    )
    try
    {
        $url = "https://dev.azure.com/eysbp/{2}/_apis/git/repositories/{0}/items?versionDescriptor.version={1}&scopePath=/&recursionLevel=Full&includeContentMetadata=true&api-version=5.1" -f  $repoName, $branchName, $projectName

        $response = (Invoke-RestMethod -Method Get -Uri $url -Headers $Token)
        return $response
    }
    catch
    {
        return $null
    }
}

Function Get-Page()
{
    param(
        [string]$FileName,
        $Token
    )
   

  $tempFileName = $FileName.Replace(".md","").Replace("-","%20")
  $Page = 'https://dev.azure.com/eysbp/CTP%20-%20Building%20Blocks/_apis/wiki/wikis/Building-Blocks.wiki/pages?path=%2FBuilding%20Blocks%2F{0}&api-version=5.1' -f $tempFileName

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
    $Page = 'https://dev.azure.com/eysbp/CTP%20-%20Building%20Blocks/_apis/wiki/wikis/Building-Blocks.wiki/pages?path=%2FBuilding%20Blocks%2F{0}&api-version=5.1' -f $tempFileName

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

function GetVSTSCredential {
    Param(
        $userEmail,
        $Token
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $userEmail, $token)))
    return @{Authorization = ("Basic {0}" -f $base64AuthInfo)}
}


function Get-TowerAuthToken {
    param(
        [string]$TowerUser,
        [string]$TowerPassword,
        [string]$TowerURL
    )

    $AuthType = "Bearer"

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


Function MD-Report($content, $path) {
    $mdcontent = "This is the list of the currently available building block templates on $environment
| Building Block |  Prod Template  | Template ID |
|-----------|-----------|-----------|`n"

    $groupcontent = $content | Group-Object -Property Name


    foreach ($BB in $groupcontent) {
        $dataTemplate = $null
        $dataTemplateID = $null

        Foreach ($property in $BB.Group) {
            $dataTemplate += "[$($property.TemplateName)]($($property.Endpoint)) <br />"
            $dataTemplateID += "$($property.TemplateID) <br />"
        }
    
        $mdcontent += "| $($BB.Name) | " + $dataTemplate + "| $dataTemplateID |" + "`n"
    }

    $mdcontent | out-file $(Join-Path $path -ChildPath $outputFile) -Force
}

function Get-CTPBuildingBlocks {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [validateset("tower.000ukso.sbp.eyclienthub.com", "tower.000ukso.sbp.eyclienthubd.com")]
        [string]$ComputerName,
        [parameter(Mandatory = $true)][pscredential]$Credential,
        [array]$array
    )


    $token = Get-TowerAuthToken -TowerUser $uTower -TowerPassword $pTower -TowerURL $ComputerName
    

    $uri = "https://{0}/api/v2/job_templates/?project={1}" -f $ComputerName, $projectID


    $header = @{
        "Content-Type"  = "application/json"
        "Authorization" = "Bearer $($token.Token)"
    }
    
 

    $buildingBlocksTemplates = @()

    do {
        $response = Invoke-RestMethod -Uri $uri -Headers $header -Method Get
        $uri = "https://{0}{1}" -f $ComputerName, $response.next
		
        $response.results | Where-Object { $_.name -like "*-bb-*" -and $_.project -eq $projectID -and $_.related.created_by -eq $createdBy } | ForEach-Object {

            $BBName = $_.name

            try {
                $playbook = $_.playbook.split("/")
                $name = $playbook[0]
                $version = $playbook[1]
                $envtype = $_.name.split("-")[0]
                
                $FilePath = Join-Path "$envtype-BuildingBlocks\" "$($_.playbook)"

                if (($array -contains $FilePath) -or ($_.Description.Split(":")[1].Replace(" ", "") -eq "")) {
                    throw  "Name or location not found"
                } elseif ( -not ($version -ceq "NONCERTIFIED") -and -not ($version -cmatch "^V") ) {
					throw "Invalid version"
                }

                Write-Host "Processing the Building Block: $($_.name)"
            

                #Write-host $_
                $buildingBlockTemplate = New-Object -TypeName PSCustomObject
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "BuildingBlock" -Value $_.name.remove(0, $_.name.indexof("-bb-") + 4).remove($_.name.indexof($version) - 4 - 1 - $_.name.indexof("-bb-"))
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Name" -Value $name
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Version" -Value $version
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "TemplateID" -Value $_.id
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "TemplateName" -Value $_.name
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Endpoint" -Value $("https://{0}/#/templates/job_template/{1}" -f $ComputerName, $_.id)
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Playbook" -Value $_.playbook
                $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "FullName" -Value $_.name

                if ($array -contains $FilePath) {
                    $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Status" -Value "Healthy"
                } else {
                    $buildingBlockTemplate | Add-Member -MemberType NoteProperty -Name "Status" -Value "Not Available"
                }

                $buildingBlocksTemplates += $buildingBlockTemplate
            } catch {
                $ErrorMessage = $_.Exception.Message

                Write-Host "Error while processing the BB: $BBName - $ErrorMessage"
            }
        }

    } while ($null -ne $response.next)

    $buildingBlocksTemplates
}

$secstr = New-Object -TypeName System.Security.SecureString
$pTower.ToCharArray() | ForEach-Object { $secstr.AppendChar($_) }
$creds = New-Object -typename System.Management.Automation.PSCredential -argumentlist $uTower, $secstr

$TokenADO = GetVSTSCredential -userEmail $uGit -Token $pGit
$i=0
$flag = $false

do{

try
{
    $i++
    Write-Host "Attempt $i of 10"
    $itemlist = Get-FileContents -repoName "Ansible-PlayBooks" -branchName "$environment-BuildingBlocks" -projectName "EY%20-%20Platform%20Engineering" -Token $TokenADO
    if($itemlist -ne $null)
    {
       $repo = Get-CTPBuildingBlocks -ComputerName $tower -Credential $creds -array $($itemlist.value.path) | Sort-Object -Property Name, TemplateName
       MD-Report -content $repo -path "$here"

       if ((Test-Path "$(Join-Path $here -ChildPath $outputFile)") -eq $true)
       {
       
            Write-Host "Copying the Index File to the Wiki"

            #Uncomment this to save the changes to Wiki
            Update-Wiki -FileName $outputFile -Token $TokenADO -FilePath "$(Join-Path $here -ChildPath $outputFile)"

            Write-Host "Done"
       }
       else
       {
            throw "File does not exists at location: $(Join-Path $here -ChildPath $outputFile)"
       }


       $flag = $true
    }else
    {
        throw "File listing failed from the Target branch"
    }
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



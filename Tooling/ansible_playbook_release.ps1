param(
  [Parameter(Mandatory)][string]$requestedFor,
  [Parameter(Mandatory)][string]$requestedForEmail,
  [Parameter(Mandatory)][string]$environmentName,
  [Parameter(Mandatory)][string]$sourceBranchName,
  [Parameter(Mandatory)][string]$repositoryName,    
  [Parameter(Mandatory)][string]$uGit,
  [Parameter(Mandatory)][string]$pGit,
  [Parameter(Mandatory)][string]$uTower,
  [Parameter(Mandatory)][string]$pTower,
  [Parameter(Mandatory)][string]$towerInstance,
  [Parameter(Mandatory)][array]$teams,
  [Parameter(Mandatory)][array]$credentials
)

function Get-TowerToken{
  param(
    [parameter(Mandatory=$true)][string]$towerInstance,
    [parameter(Mandatory=$true)][string]$towerUserName,
    [parameter(Mandatory=$true)][string]$towerUserPassword
  )

  $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $towerUserName,$towerUserPassword)))
  $headers = @{
    "Authorization" = "Basic $base64AuthInfo"
  }
  Invoke-RestMethod -Method POST -Headers $headers -Uri ("https://{0}/api/v2/tokens/" -f $towerInstance)
}

function Get-TowerEndpointInfo{
  param(
    [parameter(Mandatory=$true)][string]$towerInstance,
    [parameter(Mandatory=$true)][string]$towerToken,
    [parameter(Mandatory=$true)][string]$towerEndpoint
  )

  [array]$results = @()
  $uri = ("https://{0}/api/v2/{1}/" -f $towerInstance,$towerEndpoint)
  $headers = @{
    "Authorization" = "Bearer $towerToken"
    "Content-Type"  = "application/json"
  }
  Do{
    $response = Invoke-RestMethod -Method GET -Headers $headers -Uri $uri
    $results += $response.results
    $uri = "https://{0}{1}" -f $towerInstance, $response.next
  }While($null -ne $response.next)
  $results
}

function Update-TowerProject{
  param(
    [parameter(Mandatory=$true)][string]$towerInstance,
    [parameter(Mandatory=$true)][string]$towerToken,
    [parameter(Mandatory=$true)][string]$towerProjectId
  )

  $headers = @{
    "Authorization" = "Bearer $towerToken"
    "Content-Type"  = "application/json"
  }
  $temp1 = Invoke-RestMethod -Method POST -Headers $headers -Uri ("https://{0}/api/v2/projects/{1}/update/" -f $towerInstance,$towerProjectId)
  $temp1
  Do{
    $temp2 = Invoke-RestMethod -Method GET -Headers $headers -Uri ("https://{0}/api/v2/project_updates/{1}/" -f $towerInstance,$temp1.id)
    $temp2
    Start-Sleep -Seconds 15
  }While($temp2.status -ne "successful")
}

function CreateUpdate-TowerTemplate{
  param(
      [parameter(Mandatory=$false)][string]$towerTemplateTemplateId,
      [parameter(Mandatory=$true)][string]$towerInstance,
      [parameter(Mandatory=$true)][string]$towerToken,
      [parameter(Mandatory=$true)][string]$towerTemplateProjectId,
      [parameter(Mandatory=$true)][string]$towerTemplateName,
      [parameter(Mandatory=$true)][string]$towerTemplateDescription,
      [parameter(Mandatory=$true)][string]$towerTemplatePlaybook,
      [parameter(Mandatory=$true)]$towerTemplateExtraVars
  )

  $headers = @{
    "Authorization" = "Bearer $towerToken"
    "Content-Type"  = "application/json"
  }
  $body = @{
    "name" = $towerTemplateName
    "description" = $towerTemplateDescription
    "job_type" = "run"
    "inventory" = 1
    "project" = $towerTemplateProjectId
    "playbook" = $towerTemplatePlaybook
    "verbosity" = 0
    "extra_vars" = ($towerTemplateExtraVars | ConvertTo-Yaml)
    "allow_simultaneous" = $True
    "ask_variables_on_launch" = $True
    "ask_credential_on_launch" = $True
  } | ConvertTo-Json
  
  if($towerTemplateTemplateId){
    Invoke-RestMethod -Method PUT -Headers $headers -Body $body -Uri ("https://{0}/api/v2/job_templates/{1}/" -f $towerInstance,$towerTemplateTemplateId)
  }else{
    Invoke-RestMethod -Method POST -Headers $headers -Body $body -Uri ("https://{0}/api/v2/job_templates/" -f $towerInstance)
  }
}

function Add-TowerTemplateRole{
  param(
      [parameter(Mandatory=$true)][string]$towerInstance,
      [parameter(Mandatory=$true)][string]$towerToken,
      [parameter(Mandatory=$true)][int]$towerTemplateRole,
      [parameter(Mandatory=$true)][array]$teams 
  )

  $headers = @{
    "Authorization" = "Bearer $towerToken"
    "Content-Type"  = "application/json"
  }
  $body = @{
    "id" = $towerTemplateRole
  } | ConvertTo-Json

  $teams | Foreach-Object{
    Invoke-RestMethod -Method POST -Headers $headers -Body $body -Uri ("https://{0}/api/v2/teams/{1}/roles/" -f $towerInstance,$_)
  }
}

function AddRemove-TowerTemplateCredential{
  param(
      [parameter(Mandatory=$true)][string]$towerInstance,
      [parameter(Mandatory=$true)][string]$towerToken,
      [parameter(Mandatory=$true)][string]$towerTemplateId,
      [parameter(Mandatory=$true)][int]$credentials,
      [parameter(Mandatory=$true)][bool]$disassociate
  )

  $headers = @{
    "Authorization" = "Bearer $towerToken"
    "Content-Type"  = "application/json"
  }

  if($disassociate){
    $body = @{
      "id" = $_
      "disassociate" = $disassociate
    } | ConvertTo-Json
  }else{
    $body = @{
      "id" = $_
    } | ConvertTo-Json
  }
  Invoke-RestMethod -Method POST -Headers $headers -Body $body -Uri ("https://{0}/api/v2/job_templates/{1}/credentials/" -f $towerInstance,$towerTemplateId)
}

if($sourceBranchName -eq "master"){
  $sourceBranchName = "NONCERTIFIED"
}

$extraVariables = Get-Content -Raw -Path $PSScriptRoot/extraVars.json | ConvertFrom-Json

Write-Host ("Requested for: {0}" -f $requestedFor)
Write-Host ("Requested for email: {0}" -f $requestedForEmail)
Write-Host ("Environment Name: {0}" -f $environmentName)
Write-Host ("Branch Name: {0}" -f $sourceBranchName)
Write-Host ("Repo Name: {0}" -f $repositoryName)

Write-Host "########### Configure Git User Email & Password ###########"
git config --global user.email $requestedForEmail
git config --global user.name $requestedFor

Write-Host "########### Cloning Ansible-Playbooks Repo ###########"
Set-Location ../
git clone https://${uGit}:${pGit}@eysbp.visualstudio.com/EY%20-%20Platform%20Engineering/_git/Ansible-PlayBooks
Set-Location Ansible-PlayBooks
git checkout ("{0}-BuildingBlocks" -f $environmentName)

Write-Host ("########### Create Directory: ./Ansible-Playbooks/{0}/{1}/ ###########" -f $repositoryName,$sourceBranchName)
New-Item -ItemType Directory ("./{0}/{1}/" -f $repositoryName,$sourceBranchName) -ErrorAction Ignore

Write-Host ("########### Copying playbook version {0} ###########" -f $sourceBranchName)
Copy-Item -Path ("../{0}/{1}/Ansible/playbooks/*" -f $repositoryName,$sourceBranchName) -Destination ("./{0}/{1}/" -f $repositoryName,$sourceBranchName ) -Recurse -Force -Confirm:$False

Get-ChildItem -Recurse ../

# Start Workaround to remove quotes, this needs to be removed after moving to submodules
if( Test-Path ("./{0}/{1}/roles/" -f $repositoryName,$sourceBranchName ) ){
  $files = Get-ChildItem ("./{0}/{1}/roles/" -f $repositoryName,$sourceBranchName )
  foreach($file in $files){
    Write-Host ("########### Removing Quotes From File {0} ###########" -f $file)
    $content = Get-Content $file | ForEach-Object { 
      if($_.Contains("body: client_id")){
        $_.Replace('"','') 
      }
      else{
        $_ 
      }
    } 
    $content | Set-Content -Path $file -Encoding UTF8 -Force
  }
}
# End Workaround

Write-Host "########### Commit & Push To Ansible-Playbooks ###########"
git add -A
git commit -m ("Update playbooks for {0} version {1}" -f $repositoryName,$sourceBranchName)
git push

Write-Host "########### Waiting 30 Seconds ###########"
Start-Sleep -Seconds 30

Write-Host "########### Get Tower Token ###########"
$towerToken = Get-TowerToken -towerInstance $towerInstance -towerUserName $uTower -towerUserPassword $pTower

Write-Host "########### Get Tower Project ###########"
$towerProjects = Get-TowerEndpointInfo -towerInstance $towerInstance -towerToken $towerToken.token -towerEndpoint "projects"
$towerProjects = $towerProjects | Where-Object{$_.Name -eq ("Building Blocks ({0})" -f $environmentName)}

Write-Host ("########### Update Tower Project: {0} ###########" -f $towerProjects.id)
Update-TowerProject -towerInstance $towerInstance -towerToken $towerToken.token -towerProjectId $towerProjects.id

Write-Host "########### Get Tower Templates ###########"
$towerTemplates = Get-TowerEndpointInfo -towerInstance $towerInstance -towerToken $towerToken.token -towerEndpoint "job_templates"

Write-Host "########### Create/Update Tower Templates ###########"
foreach($item in "Create","Destroy"){

  if(!$repositoryName.Contains("capsule")){
    $extraVariables.$environmentName | Add-Member -Name 'var_buildingBlockVersion' -MemberType Noteproperty -Value $sourceBranchName -ErrorAction SilentlyContinue
  }

  $template = CreateUpdate-TowerTemplate -towerInstance $towerInstance `
                                         -towerToken $towerToken.token `
                                         -towerTemplateProjectId $towerProjects.id `
                                         -towerTemplateTemplateId ($towerTemplates | Where-Object{$_.name -eq ("{0}-{1}-{2}-{3}-{4}" -f $environmentName.ToLower(),"bb",$item.ToLower(),$repositoryName.ToLower(),$sourceBranchName)}).id `
                                         -towerTemplateName ("{0}-{1}-{2}-{3}-{4}" -f $environmentName.ToLower(),"bb",$item.ToLower(),$repositoryName.ToLower(),$sourceBranchName) `
                                         -towerTemplateDescription ("Automatically generated job template from release pipeline resource: {0}" -f $repositoryName) `
                                         -towerTemplatePlaybook ("{0}/{1}/{2}_{0}.yml" -f $repositoryName,$sourceBranchName,$item) `
                                         -towerTemplateExtraVars $extraVariables.$environmentName

  Write-Host "########### Get Tower Template Roles ###########"
  $roles = Get-TowerEndpointInfo -towerInstance $towerInstance -towerToken $towerToken.token -towerEndpoint ("job_templates/{0}/object_roles" -f $template.id)

  Write-Host "########### Grant Teams Permissions To Execute Template ###########"
  Add-TowerTemplateRole -towerInstance $towerInstance -towerToken $towerToken.token -towerTemplateRole ($roles | Where-Object{$_.name -eq "Execute"}).id -teams $teams

  Write-Host "########### Remove Credentials To Execute Template ###########"
  ($towerTemplates | Where-Object{$_.name -eq ("{0}-{1}-{2}-{3}-{4}" -f $environmentName,"bb",$item,$repositoryName,$sourceBranchName).ToLower()}).summary_fields.credentials.id | ForEach-Object {
    
    try{
        if($_ -ne $null -and $_ -notin $credentials){
            AddRemove-TowerTemplateCredential -towerInstance $towerInstance -towerToken $towerToken.token -towerTemplateId $template.id -credentials $_ -disassociate $True
        }
    }
    catch
    {
      $ErrorMessage = $_.Exception.Message
      Write-host "Error while removing the credential: $ErrorMessage"

    }

  } 

  Write-Host "########### Add Credentials To Execute Template ###########"
  $credentials | ForEach-Object {
    if($_ -notin ($towerTemplates | Where-Object{$_.name -eq ("{0}-{1}-{2}-{3}-{4}" -f $environmentName,"bb",$item,$repositoryName,$sourceBranchName).ToLower()}).summary_fields.credentials.id){
      AddRemove-TowerTemplateCredential -towerInstance $towerInstance -towerToken $towerToken.token -towerTemplateId $template.id -credentials $_ -disassociate $False
    }
  }
}


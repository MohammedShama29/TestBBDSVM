    <#
DESCRIPTION
   This module will execute the QA pipeline CTP_BB_QA_ReleaseAutomation (definitionId=1865).
.INPUT PARAMETERS
    $resourceType - Building Block name to execute
    $suite - This parameter takes the name of the test suite name that will be running.
    $environment - This parameter is used to know in which environment the test will run. Available values: QA, Prod.
    $token - This parameter is used to have the acces to launch the pipeline.
    $branch - This parameter is the branch name where the test cases will run. default value: refs/heads/BB-Dev
#>
param (
    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [string]$resourceType,

    [string]$suite = 'Smoke',

    [ValidateSet("QA", "PROD", "STAGING")]
    [string]$environment = 'QA',

    [Parameter(Mandatory = $True)]
    [ValidateNotNullOrEmpty()]
    [string]$token,
    
    [string]$ansibleProject= "",

    [string]$branch = 'refs/heads/BB-Dev'
)

$baseURL = 'https://dev.azure.com/eysbp/CTP%20-%20QA%20Automation/_apis/build/builds'
$APIVersion = '?api-version=5.0'

$personalToken = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($token)"))
$headers = New-Object 'System.Collections.Generic.Dictionary[[String],[String]]'
$headers.Add('Authorization', 'Basic ' + $personalToken)
$headers.Add('Content-Type', 'application/json') 

$buildBody = (@{
        'definition'    = @{
            'id' = '1865'
        }
        'sourceBranch'  = $branch
        'sourceVersion' = ''
        'reason'        = '1'
        'demands'       = '[]'
        'parameters'    = "{'system.debug':'false','CustomTemplate':'False','environment':'$environment','suiteName':'$suite','componentName':'$resourceType','ansibleProject':'$ansibleProject'}"
    } | ConvertTo-Json)

$callResult = Invoke-RestMethod -Method Post -Uri ($baseURL + $APIVersion) -Headers $headers -Body $buildBody

if (![string]::IsNullOrEmpty($callResult.id)) {
 
    $checkURL = $baseURL + '/' + (($callResult.id).ToString()) + $APIVersion

    while ($runResult.status -ne 'completed') {
        $runResult = Invoke-RestMethod -Method Get -Uri $checkURL -Headers $headers
        Write-host 'Waiting for the build ' $callResult.id ' pipeline to finish'
        Start-Sleep -s 15
    }

    if ($runResult.result -ne 'Succeeded') {
        Write-Host("Build Pipeline Failed, please review the run.")
        $logURL =  $baseURL + '/' + (($callResult.id).ToString()) + '/logs' + $APIVersion
        (Invoke-RestMethod -Method Get -Uri $logURL -Headers $headers).Value | Foreach-Object {
            (Invoke-WebRequest $_.url -Headers $headers -UseBasicParsing).Content
        }
        Write-Host  "##vso[task.LogIssue type=error;]This is the error"
        Exit 1
    }
    else {
        Write-Host("Execution completed successfully.")
        $logURL =  $baseURL + '/' + (($callResult.id).ToString()) + '/logs' + $APIVersion
        (Invoke-RestMethod -Method Get -Uri $logURL -Headers $headers).Value | Foreach-Object {
            (Invoke-WebRequest $_.url -Headers $headers -UseBasicParsing).Content
        }
        Exit 0
    }    
}
else {
    Write-Host("The remote server returned an error: (401) Unauthorized.")
    Write-Host  "##vso[task.LogIssue type=error;]This is the error"
    Exit 1
}
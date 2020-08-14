
param(
  $StorageSASToken = "?sv=2019-02-02&ss=bfqt&srt=sco&sp=rwdlacup&se=2022-03-02T22:39:42Z&st=2020-03-02T14:39:42Z&spr=https&sig=FX8r9Ajo63kx4plRE8xT3P9uTyOQ6DzXN4hd%2FUyRVvk%3D"
)

$here = (Get-Location).Path
function downloadFile($url, $targetFile)
{
    "Downloading $url"
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.set_Timeout(15000) #15 second timeout
    $response = $request.GetResponse()
    $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
    $buffer = new-object byte[] 1000KB
    $count = $responseStream.Read($buffer,0,$buffer.length)
    $downloadedBytes = $count
    while ($count -gt 0)
    {
        write-host "Downloaded $([System.Math]::Floor($downloadedBytes/1024)) KB of  $totalLength KB"
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer,0,$buffer.length)
        $downloadedBytes = $downloadedBytes + $count
    }
    "`nFinished Download"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

If(!(Test-Path "$here\software.json"))
{
  Exit(0)
}

if(!(Test-Path "$here\software"))
{
  New-Item -Path "$here\software" -ItemType Directory | Out-Null
}

$SoftwareList = Get-Content "$here\software.json" -Raw | ConvertFrom-Json
$webClient = New-Object System.Net.WebClient
$webClient

ForEach($Software In $SoftwareList)
{
  $DestinationFolder = "$here/software/{0}" -f $Software.Platform
  $FileName = $Software.Uri.SubString($Software.Uri.LastIndexOf('/')+1)
  $CurrentHash = $null

  if(!(Test-Path $DestinationFolder))
  {
    New-Item -Path $DestinationFolder -ItemType Directory | Out-Null
  }

  Write-Host ("Working on {0}" -f $Software.Name)
  Write-Host ("Verifying if it's already downloaded")
  if(Test-Path "$DestinationFolder/$FileName")
  {
    $CurrentHash = Get-FileHash -Path "$DestinationFolder/$FileName" -Algorithm $Software.HashType
  }
  
  If($CurrentHash.Hash -ne $Software.Hash)
  {
    Write-Host "Downloading File..."
    downloadFile -url "$($Software.Uri)$StorageSASToken" -targetFile "$DestinationFolder/$FileName"
    Write-Host "Complete!"
  }
  else
  {
    Write-Host "File is already downloaded"
  }
}
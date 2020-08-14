param(
  [string]$BranchName  
)

$here = (Get-Location).Path

$artifactNameTmp = (git remote -v) | Select-Object -First 1
$artifactName = $artifactNameTmp.remove(0, $artifactNameTmp.lastindexof("/") + 1).split(" ")[0]
$artifactSubfolder = "Artifacts"
$ansibleSubfolder = "Ansible"
$softwareSubfolder = "Software"
$readMeSubfolder = "ReadMe"
$scratchSubfolder = "scratch"
Write-Host "Cleaning Up Output folder"
if (Test-Path "$here\output") { Get-ChildItem "$here\output" -Recurse | Remove-Item -Force -Recurse }

Write-Host "Creating Output Directory"
if (!(Test-Path "$here\output")) { New-Item -Path "$here\output" -ItemType Directory | Out-Null }

$version = if($BranchName -eq "master") { "NONCERTIFIED" } else { $BranchName }
$version = $version.replace("version/", "") 
$version = $version.replace("feature/", "")
$version = $version.replace("bugfix/", "")

$base_path = "$here\output\$version\"

$artifactFolder = $base_path + $artifactSubfolder
$ansibleFolder = $base_path + $ansibleSubfolder
$softwareFolder = $base_path + $softwareSubfolder
$scratchFolder = $base_path + $scratchSubfolder
$readMeFolder = $here + "\output\"  + $readMeSubfolder + "\" + $artifactName + "\" + $version

if (!(Test-Path $base_path)) { New-Item $base_path -ItemType Directory }

if (!(Test-Path $artifactFolder)) {
  New-Item -Path $artifactFolder -ItemType Directory | Out-Null
}

if (!(Test-Path $ansibleFolder)) {
  New-Item -Path $ansibleFolder -ItemType Directory | Out-Null
}

if (!(Test-Path $softwareFolder)) {
  New-Item -Path $softwareFolder -ItemType Directory | Out-Null
}

Write-Host "ReadMe directory: $readMeFolder"

if (!(Test-Path $readMeFolder)) {
  New-Item -Path $readMeFolder -ItemType Directory | Out-Null
}

Write-Host "Copying azuredeploy*.json"
Copy-Item -Path "$here\azuredeploy*.json" -Destination "$artifactFolder"

Write-Host "Copying README.md File"
Copy-Item -Path "$here\README.md" -Destination "$readMeFolder"

if (Test-Path "$here\nested") {
  Write-Host "Copying nested JSON files"
  Copy-Item -Path "$here\nested\*.json" -Destination "$artifactFolder" -Recurse
}

if (Test-Path "$here\playbooks") {
  Write-Host "Copying Ansible Playbooks"
  Copy-Item -Path "$here\playbooks\" -Filter "*.yml" -Destination "$ansibleFolder" -Recurse
}

if (Test-Path "$here\software\$artifactName") {
  $softwareList = Get-Content -Path $here\software.json | ConvertFrom-Json
  New-Item -Path $softwareFolder -Name $artifactName -Type Directory | Out-Null
  Write-Host "Copying software files for the building block"
  $softwareList | ForEach-Object {
    $fileName = $_.uri.Remove(0, $_.uri.LastIndexOf("/") + 1)
    Write-Output "$here\software\$artifactName\$fileName"
    Copy-Item -Path "$here\software\$artifactName\$fileName" -Destination "$softwareFolder\$artifactName" -Recurse
  }
}

if (Test-Path "$here\scripts") {
  if (Test-Path $scratchFolder) {
    Remove-Item $scratchFolder -Recurse -Force
  }

  Write-Host "Creating Scratch folder"
  New-Item -Path $scratchFolder -ItemType Directory | Out-Null

  Write-Host "Preparing scripts"
  Get-childitem "$here\scripts" -Directory | Where-Object { $_.Name -ne 'QA' -and $_.Name -ne 'Modules' } | ForEach-Object {
    $scratchPath = "{0}\{1}" -f $scratchFolder, $_.Name

    Write-Host $("[{0}] Copying to scratch folder" -f $_.Name)
    Copy-Item -Path $_.FullName -Destination $scratchPath -Recurse | Out-Null

    $ReferencedModules = Get-ChildItem -Path $_.FullName -Filter *.ps1 | Select-Object -First 1 | Get-Content | Where-Object -FilterScript { $_ -ilike '*Import-DSCResource*' } | ForEach-Object -Process { $_.SubString($_.LastIndexOf(' ') + 1).Replace("'", "") }

    ForEach ($ReferencedModule In $ReferencedModules) {
      Write-Host $("[{0}] Verifying Module: {1}" -f $_.Name, $ReferencedModule)

      if (!(Test-Path ("{0}\{1}" -f $scratchPath, $ReferencedModule))) {
        if (Test-Path "$here\scripts\Modules\$ReferencedModule") {
          Write-Host $("[{0}] Copying Module {1} from shared location" -f $_.Name, $ReferencedModule)
          Copy-Item -Path "$here\scripts\Modules\$ReferencedModule" -Destination "$scratchPath\$ReferencedModule" -Recurse
        }
        else {
          throw ("Missing Modules {0} for {1}" -f $ReferencedModule, $_.Name)
        }
      }
    }

    Write-Host $("[{0}] Compressing...." -f $_.Name)
    Compress-Archive "$scratchPath\*" -DestinationPath ("$artifactFolder\{0}.zip" -f $_.Name)
  }

  Remove-Item -Path $scratchFolder -Recurse -Force
}
Get-ChildItem "$here\scripts" -File | Where-Object { $_.Name -ne ".gitkeep" } | Copy-Item -Destination "$artifactFolder"

Write-Host "Done!"
$WorkingFolder = Get-Location
Function Test-Json {
  Param(
    [string]
    $FilePath
  )

  Context "JSON Structure" {
    It "Converts from JSON and has the expected properties" {
      $expectedProperties = '$schema',
      'contentVersion',
      'parameters',
      'variables',
      'resources',
      'outputs' | Sort-Object

      $templateProperties = (get-content "$FilePath" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | ForEach-Object -Process { $_.Name } | Sort-Object
      $templateProperties | Should -Be $expectedProperties
    }
  }

  $jsonMainTemplate = Get-Content "$FilePath"
  $objMainTemplate = $jsonMainTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue

  $parametersUsage = [System.Text.RegularExpressions.RegEx]::Matches($jsonMainTemplate, "parameters(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique
  Context "Parameters Usage $parameterUsage" {
    ForEach ($parameterUsage In $parametersUsage) {
      $parameterUsage = $parameterUsage.SubString($parameterUsage.IndexOf("'") + 1).Replace("')", "")
    
      It "should have a parameter called $parameterUsage" {
        $objMainTemplate.parameters.$parameterUsage | Should -Not -Be $null
      }
    }
  }

  $variablesUsage = [System.Text.RegularExpressions.RegEx]::Matches($jsonMainTemplate, "variables(\(\'\w*\'\))") | Select-Object -ExpandProperty Value -Unique
  Context "Variables Usage" {
    ForEach ($variableUsage In $variablesUsage) {
      $variableUsage = $variableUsage.SubString($variableUsage.IndexOf("'") + 1).Replace("')", "")
      
      It "should have a variable called $variableUsage" {
        if ($null -eq $objMainTemplate.variables.$variableUsage -and $null -eq ($objMainTemplate.variables.copy | Where-Object { $_.name -eq $variableUsage })) {
          throw "$variableUsage is not defined"
        }
      }
    }
  }
  Context "Variables Debug" {
    $debug = $objMainTemplate.variables.debug
    If ($debug) {
      $debugproperties = $debug | Get-Member | Where-Object membertype -eq Noteproperty | Select-Object -ExpandProperty name
      foreach ($property in $debugproperties) {
        It "Debug Property $property Should be True" {
          $debug.$property | Should -be $true
        }
      }
    }
  }
  $nestedTemplates = $objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments"
  
  if ($nestedTemplates -ne $null) {
    ForEach ($nestedTemplate In $nestedTemplates) {
      If (($nestedTemplate.properties.templateLink.uri -ne $null) -and ($nestedTemplate.properties.templateLink.uri.Contains("https://"))) {
        $nestedTemplateFileName = [System.Text.RegularExpressions.RegEx]::Matches($nestedTemplate.properties.templateLink.uri, "\'\w*\.json\??\'").Value
        $nestedTemplateFileName = $nestedTemplateFileName.SubString($nestedTemplateFileName.IndexOf("'") + 1).Replace("'", "").Replace('?', '')

        Context "Nested Template: $nestedTemplateFileName" {
          It "should exist the nested template at $WorkingFolder\nested\$nestedTemplateFileName" {
            "$WorkingFolder\nested\$nestedTemplateFileName" | Should -Exist
          }

          if (Test-Path "$WorkingFolder\nested\$nestedTemplateFileName") {
            $nestedParameters = (Get-Content "$WorkingFolder\nested\$nestedTemplateFileName" | ConvertFrom-Json).parameters
            $requiredNestedParameters = $nestedParameters | Get-Member -MemberType NoteProperty | Where-Object -FilterScript { $nestedParameters.$($_.Name).defaultValue -eq $null } | ForEach-Object -Process { $_.Name }

            
            ForEach ($requiredNestedParameter In $requiredNestedParameters) {
              It "should set a value for $requiredNestedParameter" {
                $nestedTemplate.properties.parameters.$requiredNestedParameter | Should -Not -BeNullOrEmpty
              }
            }
          }
        }
      }
    }
  }

  $scriptFolders = [System.Text.RegularExpressions.RegEx]::Matches($jsonMainTemplate, "\w+\.(gz|tar|tar\.gz|zip)")
  ForEach ($scriptFolder In $scriptFolders) {
    $CompressedFileName = ($scriptFolder.Value).Replace(".tar.gz", "").Replace(".tar", "").Replace(".gz", "").Replace(".zip", "")

    Context "Script Folder: $CompressedFileName" {
      It "should exists in the scripting folder" {
        "$WorkingFolder\scripts\$CompressedFileName" | Should -Exist
      }

      It "shouldn't be empty" {
        (Get-ChildItem -Path "$WorkingFolder\scripts\$CompressedFileName" -Recurse).Length | Should -BeGreaterThan 0
      }
    }
  }

  $scriptFiles = [System.Text.RegularExpressions.RegEx]::Matches($jsonMainTemplate, "\w+\.(ps1|sh|py)")
  ForEach ($scriptFile In $scriptFiles) {
    Context ("Script File: {0}" -f $scriptFile.Value) {
      $scriptType = $scriptFile.Value.SubString($scriptFile.Value.LastIndexOf('.'))
      $script = Get-ChildItem -Path "$WorkingFolder\scripts" -Filter $scriptFile.Value -Recurse | Select-Object -First 1

      if ($script) {

        It "should exist in the scripts folder" {
          $script | Should -Not -BeNullOrEmpty
        }
  
        if ($scriptType -ieq ".ps1") {
          # It "is a valid Powershell Code"{
          #     $psFile = Get-Content -Path $script.FullName -ErrorAction Stop
          #     $errors = $null
          #     $null = [System.Management.Automation.PSParser]::Tokenize($psFile, [ref]$errors)
          #     $errors.Count | Should -Be 0
          # }

          $ReferencedModules = Get-Content $script.FullName | Where-Object -FilterScript { $_ -ilike '*Import-DSCResource*' } | ForEach-Object -Process { $_.SubString($_.LastIndexOf(' ') + 1).Replace("'", "") }

          ForEach ($Module In $ReferencedModules) {
            $ModulePath = Join-Path -Path $script.DirectoryName -ChildPath $Module
            $ModuleSharedPath = Join-Path -Path "$WorkingFolder\scripts\Modules" -ChildPath $Module

            It "has a Module folder for: $Module" {
              $result = (Test-Path $ModulePath) -or (Test-Path $ModuleSharedPath)
              
              $result | Should -Be $true
            }

            It "has content in $Module folder" {
              If (Test-Path $ModulePath) {
                $result = Get-ChildItem -Path $ModulePath -Recurse | Measure-Object -Sum -Property Length | Select-Object -ExpandProperty Sum  
              }
              else {
                $result = Get-ChildItem -Path $ModuleSharedPath -Recurse | Measure-Object -Sum -Property Length | Select-Object -ExpandProperty Sum  
              }
              
              $result | Should BeGreaterThan 0
            }

            It "has the definition file ($Module.psd1)" {
              if (Test-Path $ModulePath) {
                $result = Get-ChildItem -Path $ModulePath -Filter "$Module.psd1" -Recurse
              }
              else {
                $result = Get-ChildItem -Path $ModuleSharedPath -Filter "$Module.psd1" -Recurse
              }
              
              $result | Should -Not -BeNullOrEmpty
            }
          }
        }
        elseif ($scriptType -ieq ".sh") {

        }
        elseif ($scriptType -ieq ".py") {

        }
      }
    }
  }
}

Describe "Test Object Variables"{
    if(Test-Path "$WorkingFolder\azureDeploy.json"){
      $AzureDeployVars = @()
      $Filecontent= get-content "$WorkingFolder\azureDeploy.json"
      $Json = $Filecontent | ConvertFrom-Json
      if($json.variables){
        $vars =$json.variables | get-member |where membertype -eq noteproperty |Select-Object -ExpandProperty definition
        foreach ($vara in $vars){
          if ($vara -like "*PSCustomObject*"){
            $PSCustomVariable= $vara.split(" ",2)[1]
            foreach ($CustomVariable in $PSCustomVariable){
              $Name=$CustomVariable.split("=")[0]
              $PropertyString =  $CustomVariable.split("=",2)[1]
              $CustomObjectProperties = $PropertyString.Split(";")
              foreach ($Property in $CustomObjectProperties){
                  $AzureDeployVars +="$Name.$($property.Split("=",2)[0].trim("@").trim("{").trim())"
              }
            }
          }
        } 
      }
    }

    $Files = get-childitem $WorkingFolder\nested -Exclude *.yaml,*.gitkeep | select -ExpandProperty fullname

    foreach ($file in $files){
        Context "Check the Properties of the objects from $file"{
            $content= get-content $file
            $json = $content | ConvertFrom-Json
            $obj = $json.variables | gm |where membertype -eq noteproperty |select name,definition
            If($obj){
                $vars = $obj.definition | % {$_.split(" ",2)[1]} 
            
        $tolookFor = @()
        foreach ($var in $vars) {
          if ($var -like "*parameters(*).*") {
            $Object = $var.split("'")[1]
            $Property = $var.split(".", 2)[1].trim("]").trim(")")
            $obj = "$Object.$Property"
            $tolookFor += $obj
          }

        } 
                
        foreach ($prop in $tolookFor) {
          it "should exist $prop" {
            $AzureDeployVars -contains $prop
          }
        }
      }
    }
  }
}

Describe "Solution Standard" {
  Context "Folder & File Structure" {
    ForEach ($Folder In @('docs', 'nested', 'playbooks', 'scripts')) {
      It "should have a '$Folder' folder" {
        "$WorkingFolder\$Folder" | Should -Exist
      }
    }

    It "should have at least 1 (one) playbook" {
      (Get-ChildItem -Path "$WorkingFolder\playbooks" -Filter "*.yml").Length | Should -BeGreaterThan 0
    }
  }

  Context "Documentation" {
    It "should have a README.md file" {
      "$WorkingFolder\README.md" | Should -Exist
    }

    It "should have an Introduction section" {
      "$WorkingFolder\README.md" | Should -FileContentMatch "# Introduction"
    }

    It "should document the project" {
      (Get-FileHash -Path "$WorkingFolder\README.md" -Algorithm SHA256).Hash | Should -Not -Be "CA0DBCC51DF149421A05A71595964BAE965A4FA7755F73A52EE730132505BF4E"
      "$WorkingFolder\README.md" | Should -Not -FileContentMatch "TODO: Give a short introduction of your project."
      "$WorkingFolder\README.md" | Should -Not -FileContentMatch "TODO: Guide users through getting your code up and running on their own system."
      "$WorkingFolder\README.md" | Should -Not -FileContentMatch "TODO: Describe and show how to build your code and run the tests."
      "$WorkingFolder\README.md" | Should -Not -FileContentMatch "TODO: Explain how other users and developers can contribute to make your code better."
    }
  }

  $playbooks = Get-ChildItem -Path "$WorkingFolder\playbooks" -Filter "*.yml"
  $script:armTemplates = @()

  ForEach ($playbook In $playbooks) {
    Context ("Ansible Playbook: {0}" -f $playbook.Name) {
      $ymlPlaybook = Get-Content -Path $playbook.FullName -Raw
      $objPlaybook = ConvertFrom-Yaml -Yaml $ymlPlaybook -ErrorAction SilentlyContinue
      $jsonFiles = [System.Text.RegularExpressions.RegEx]::Matches($ymlPlaybook, "template_link:.+\w+\.json(\?)?.*\""")

      It "should have an underscore (_) on its name" {
        $playbook.Name.Contains('_') | Should -Be $true
      }

      It "should use an approved verb (Add, Create, Destroy, Remove)" {
        $playbook.Name.SubString(0, $playbook.Name.IndexOf('_')) | Should -BeIn @('Add', 'Create', 'Destroy', 'Remove')
      }

      It "is a valid YAML File" {
        $objPlaybook | Should -Not -BeNullOrEmpty
      }

      ForEach ($section In @('tasks', 'hosts', 'gather_facts')) {
        it "defines a $section section" {
          $objPlaybook.$section | Should -Not -BeNullOrEmpty
        }
      }

      ForEach ($var In $objPlaybook.vars.Keys) {
        It "shouldn't have local variables with all upper cases ($var)" {
          $var -ceq $var.ToUpper() | Should -Not -Be $true
        }
      }

      ForEach ($jsonFile In $jsonFiles) {
        $armTemplate = [System.Text.RegularExpressions.RegEx]::Match($jsonFile.Value, "\w+\.json")

        if ($armTemplate) {
          It ("references {0} which should exist" -f $armTemplate.Value) {
            if ($armTemplate.Value -eq "azureDeploy.json") {
              $script:armTemplates += "$WorkingFolder\{0}" -f $armTemplate.Value
              "$WorkingFolder\{0}" -f $armTemplate.Value | Should -Exist
            }
            else {
              $script:armTemplates += "$WorkingFolder\nested\{0}" -f $armTemplate.Value
              "$WorkingFolder\nested\{0}" -f $armTemplate.Value | Should -Exist
            }
          }
        }
      }

    }
  }
}

Describe "Ansible Roles" {
  Context "API Interactions" {
    if ( Test-Path -Path ".\playbooks\roles" ) {
      foreach ($file in $(Get-ChildItem -Path .\playbooks\roles).FullName) {
      
        $roleContent = Get-Content -Path $file -Raw | ConvertFrom-Yaml
      
        It "URI moudle that invokes login.microsoftonline.com should not include: `" character in body" {
          ($roleContent.uri | Where-Object { $_.url -eq "{{ var_mnfTokenUri }}" -or $_.url -eq "{{ var_ipamTokenUri }}" }).body | Should -Not -BeLike "*`"*"
        }
      }
    }
  }
}

ForEach ($armTemplate In $armTemplates) {
  Describe $armTemplate {
    Test-Json -FilePath $armTemplate
  }
  $jsonMainTemplate = Get-Content $armTemplate
  $objMainTemplate = $jsonMainTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue
  $mainNestedTemplates = $null

  If ($objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments") {
    $mainNestedTemplates = [System.Text.RegularExpressions.RegEx]::Matches($($objMainTemplate.resources | Where-Object -Property Type -IEQ -Value "Microsoft.Resources/deployments" | ForEach-Object -Process { $_.properties.templateLink.uri }), "\'\w*\.json\??\'") | Select-Object -ExpandProperty Value -Unique
  }

  ForEach ($nestedTemplate In $mainNestedTemplates) {
    $nestedTemplate = $nestedTemplate.SubString($nestedTemplate.IndexOf("'") + 1).Replace("'", "").Replace('?', '')
    
    Describe "Nested: $WorkingFolder\nested\$nestedTemplate" {
      It "Should exist" {
        "$WorkingFolder\nested\$nestedTemplate" | Should -Exist
      }

      if (Test-Path $WorkingFolder\nested\$nestedTemplate) {
        Test-Json -FilePath $WorkingFolder\nested\$nestedTemplate
      }
    }
  }
}

if ((Test-Path "$WorkingFolder\software.json") -and $null -ne (Get-Content "$WorkingFolder\software.json")) {
  Describe "Software" {
    Context "File Syntax" {
      It "Converts from JSON and has the expected properties" {
        $expectedProperties = 'Hash',
        'HashType',
        'Name',
        'Platform',
        'Uri' | Sort-Object
  
        $templateProperties = (get-content "$WorkingFolder\software.json" -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue) | Get-Member -MemberType NoteProperty | ForEach-Object -Process { $_.Name } | Sort-Object
        $templateProperties | Should -Be $expectedProperties
      }
    }

    $SoftwareList = Get-Content "$WorkingFolder\software.json" -Raw | ConvertFrom-Json

    ForEach ($Software In $SoftwareList) {
      $DestinationFolder = "$WorkingFolder\software\{0}" -f $Software.Platform
      $FileName = $Software.Uri.SubString($Software.Uri.LastIndexOf('/') + 1)

      Context ("Software: {0}" -f $Software.Name) {
        It "should have a Name property" {
          $Software.Name | Should -Not -BeNullOrEmpty
        }

        It "should have a Hash property" {
          $Software.Hash | Should -Not -BeNullOrEmpty
        }

        It "should have a HashType property" {
          $Software.HashType | Should -Not -BeNullOrEmpty
        }

        It "should have a Platform property" {
          $Software.Platform | Should -Not -BeNullOrEmpty
        }

        It "should have a Uri property" {
          $Software.Uri | Should -Not -BeNullOrEmpty
        }

        It ("should exists at software/{0}/{1}" -f $Software.Platform, $FileName) {
          "$DestinationFolder/$FileName" | Should -Exist
        }

        It "should match the hash value" {
          (Get-FileHash -Path "$DestinationFolder\$FileName" -Algorithm $Software.HashType).Hash | Should -Be $Software.Hash
        }
      }
    }
  }
}

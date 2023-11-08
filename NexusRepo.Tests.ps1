[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Suppress false positives in Pester code blocks')]
param ()

BeforeAll {
    $Separator = [System.IO.Path]::DirectorySeparatorChar
    Import-Module "$PSScriptRoot$Separator`PoshNexusRepo.psm1" -Force
    $SaveDir = "$env:APPDATA$Separator`PoshNexusRepo"
    $AuthXmlPath = "$SaveDir$Separator`Auth.xml"

    [uri]$BaseUrl = "https://nexus.cityntl.com"

    if (-not (Test-Path -Path $AuthXmlPath))
    {
        Connect-NexusRepo -BaseUrl $BaseUrl -APIVersion v1 | Out-Null
    }
    $Settings = Import-Clixml -Path $AuthXmlPath
    $Settings | Connect-NexusRepo -MaxPages 1 | Out-Null # We only need a single result
}

Describe "Connect-NexusRepo or Save-NexusRepoLogin" {
    BeforeEach {
        if (Test-Path $AuthXmlPath) { Remove-Item $SaveDir -Recurse }
    }
    It "Saves their profile info" {
        $Result = Connect-NexusRepo -Credential $Settings.Credential -BaseUrl $Settings.BaseUrl -APIVersion $Settings.APIVersion
        $AuthXmlPath | Should -Exist
        $Result.Credential | Should -Not -BeNullOrEmpty
        $Result.Credential.UserName | Should -Be $Settings.Credential.UserName
        $Result.APIVersion | Should -Be $Settings.APIVersion
        $Result.MaxPages | Should -BeOfType [uint]
        $Result | Should -HaveCount 1
    }
    It "Saves their profile info by passing a credential from the pipeline" {
        $Result = $Settings | Connect-NexusRepo -BaseUrl $Settings.BaseUrl -APIVersion $Settings.APIVersion -MaxPages 100
        $AuthXmlPath | Should -Exist
        $Result.Credential | Should -Not -BeNullOrEmpty
        $Result.Credential.UserName | Should -Be $Settings.Credential.UserName
        $Result.APIVersion | Should -Be $Settings.APIVersion
        $Result.MaxPages | Should -BeOfType [uint]
        $Result.MaxPages | Should -Be 100
    }

    AfterEach {
        if (-not (Test-Path $SaveDir))
        {
            New-Item -Path $SaveDir -ItemType Directory | Out-Null
        }
        $Settings | Export-Clixml -Path $AuthXmlPath
    }    
}

Describe "Disconnect-NexusRepo or Remove-NexusRepoLogin" {
    It "Removes their login information from disk" {
        Disconnect-NexusRepo
        $AuthXmlPath | Should -Not -Exist
    }

    AfterEach {
        if (-not (Test-Path $SaveDir))
        {
            New-Item -Path $SaveDir -ItemType Directory | Out-Null
        }
        $Settings | Export-Clixml -Path $AuthXmlPath
    }    
}

Describe "Get-NexusRepoSettings" {
    It "Returns their profile info" {
        $Settings | Should -Not -BeNullOrEmpty
        $Settings.APIVersion.ToString() | Should -Be "v1"
        $Settings.BaseUrl | Should -Be $BaseUrl
        $Settings.Credential | Should -BeOfType PSCredential
        $Settings.MaxPages | Should -BeOfType [uint]
    }
}

Describe "Get-NexusRepoRepository" {
    It "Retrieves all repos without a name parameter" {
        $Result = Get-NexusRepoRepository | Select-Object -First 5
        $Result | Should -Not -BeNullOrEmpty
    }
    It "Retrieves a repo using wildcard" {
        $Result = Get-NexusRepoRepository -Name "Test-*"
        $Result[0].name | Should -BeLike "Test-*"
    }
    It "Retrieves a repo using the pipeline" {
        $Result = "Test-nuget-hosted","Test-nuget-hosted-prod" | Get-NexusRepoRepository
        $Result | Should -HaveCount 2
        $Result[0].name | Should -Be "Test-nuget-hosted"
        $Result[1].name | Should -Be "Test-nuget-hosted-prod"
    }
}

Describe "Get-NexusRepoAsset" {
    BeforeAll {
        $Settings = Get-NexusRepoSettings
    }
    Context "Repository parameter" {
        BeforeAll {
            $Settings | Connect-NexusRepo -MaxPages 2 | Out-Null
        }
        It "Returns some assets given a repository name" {
            $Result = Get-NexusRepoAsset -Repository "Test-raw-hosted"
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -HaveCount 20
        }
        AfterAll {
            $Settings | Connect-NexusRepo -MaxPages 1 | Out-Null
        }
    }
    Context "Id parameter" {
        BeforeAll {
            if ((Get-NexusRepoSettings).MaxPages -ne 1)
            {
                $Settings | Connect-NexusRepo -MaxPages 1 | Out-Null # We only need a single result
            }
        }
        It "Retrieves an asset" {
            $Assets = Get-NexusRepoAsset -Repository "Test-raw-hosted"
            $Assets | Should -Not -BeNullOrEmpty
            $Result = Get-NexusRepoAsset -Id $Assets[0].Id
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -HaveCount 1
            $Result.id | Should -Be $Assets[0].Id
            $Result.format | Should -Be "raw"
        }
        It "Retrieves an asset using the pipeline" {
            $Assets = Get-NexusRepoAsset -Repository "Test-raw-hosted"
            $Assets | Should -Not -BeNullOrEmpty
            $Result = $Assets[0] | Get-NexusRepoAsset
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -HaveCount 1
            $Result.id | Should -Be $Assets[0].Id
            $Result.format | Should -Be "raw"
        }
    }
    AfterAll {
        $Settings | Connect-NexusRepo | Out-Null
    }
}

Describe "Find-NexusRepoAsset" {
    It "Searches for and returns some based on a format" {
        $Result = Find-NexusRepoAsset -Repository "Test-raw-hosted" -Format raw
        $Result | Should -Not -BeNullOrEmpty
        $Result[0].format | Should -Be "raw"
    }
    It "Searches for and returns some based on a some NuGet properties" {
        $Assets = Get-NexusRepoAsset -Repository "Test-nuget-hosted"
        $Splat = @{
            Repository = "Test-nuget-hosted"
            Version    = $Assets[0].nuget.version
            NuGetId    = $Assets[0].nuget.id
        }
        $Result = Find-NexusRepoAsset @Splat
        $Result | Should -Not -BeNullOrEmpty
        $Result | Should -HaveCount 1
        $Result.nuget.id | Should -Be $Assets[0].nuget.id
        $Result.repository | Should -Be $Assets[0].repository
        $Result.nuget.version | Should -Be $Assets[0].nuget.version
    }
}

Describe "Remove-NexusRepoAsset" -Skip {
    BeforeAll {
        $Assets = Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository="Test-raw-hosted" } |
        Select-Object -First 2
    }
    It "Removes the specified assets" {
        # $Assets[0],$Assets[1] | Remove-NexusRepoAsset -WhatIf
        $Result = Find-NexusRepoAsset -Repository "Test-nuget-hosted" -Sha1 $Assets[0].checksum.sha1
        $Result | Should -BeNullOrEmpty
        $Result = Find-NexusRepoAsset -Repository "Test-nuget-hosted" -Sha1 $Assets[1].checksum.sha1
        $Result | Should -BeNullOrEmpty
    }
}

Describe "Request-NexusRepoAsset" {
    Context "Raw artifact" {
        BeforeAll {
            $Asset = Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository="shared-nuget-hosted" } | Select-Object -First 1
        }

        It "Downloads the artifact to the specified directory" {
            # Make sure that it actually returned something before running the tests
            $Asset | Should -Not -BeNullOrEmpty
            $Asset.downloadUrl | Should -Not -BeNullOrEmpty
            $UriPath = [uri]($Asset.downloadUrl) | Select-Object -Expand LocalPath

            # Run the tests
            $Asset | Request-NexusRepoAsset -OutFolder "TestDrive:" | Out-Null
            "TestDrive:/$([System.IO.Path]::GetFileName($Asset.downloadUrl))" | Should -Exist
        }
    }
    Context "NuGet artifact" {
        BeforeAll {
            $Asset = Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository="shared-nuget-hosted" } | Select-Object -First 1
        }
        It "Downloads the package to the specified directory" {
            $Asset | Should -Not -BeNullOrEmpty
            $UriPath = [uri]($Asset.downloadUrl) | Select-Object -Expand LocalPath

            $Asset | Request-NexusRepoAsset -OutFolder "TestDrive:" | Out-Null
            "TestDrive:/$([System.IO.Path]::GetFileName($Asset.downloadUrl)).nupkg" | Should -Exist
        }
    }
    Context "maven artifact" {
        BeforeAll {
            $Asset = Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository="shared-maven-hosted" } | Select-Object -First 1
        }
        It "Downloads the package to the specified directory" {
            $Asset | Should -Not -BeNullOrEmpty
            $UriPath = [uri]($Asset.downloadUrl) | Select-Object -Expand LocalPath

            $Asset | Request-NexusRepoAsset -OutFolder "TestDrive:" | Out-Null
            "TestDrive:/$([System.IO.Path]::GetFileName($Asset.downloadUrl))" | Should -Exist
        }
    }
    Context "npm artifact" {
        BeforeAll {
            $Asset = Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository="shared-npm-hosted" } | Select-Object -First 1
        }
        It "Downloads the package to the specified directory" {
            $Asset | Should -Not -BeNullOrEmpty
            $UriPath = [uri]($Asset.downloadUrl) | Select-Object -Expand LocalPath

            $Asset | Request-NexusRepoAsset -OutFolder "TestDrive:" | Out-Null
            "TestDrive:/$([System.IO.Path]::GetFileName($Asset.downloadUrl))" | Should -Exist
        }
    }
    Context "pypi artifact" {
        BeforeAll {
            $Asset = Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository="shared-pypi-hosted" } | Select-Object -First 1
        }
        It "Downloads the package to the specified directory" {
            $Asset | Should -Not -BeNullOrEmpty
            $UriPath = [uri]($Asset.downloadUrl) | Select-Object -Expand LocalPath

            $Asset | Request-NexusRepoAsset -OutFolder "TestDrive:" | Out-Null
            "TestDrive:/$([System.IO.Path]::GetFileName($Asset.downloadUrl))" | Should -Exist
        }
    }
}

Describe "Get-NexusRepoComponent" {
    Context "Repo Name parameter" {
        It "Retrieves some components" {
            $Results = Get-NexusRepoComponent -RepositoryName "Test-nuget-hosted"
            $Results | Should -Not -BeNullOrEmpty
        }
    }
    Context "Component Id parameter" {
        BeforeAll {
            $Component = Invoke-NexusRepoAPI -Path "components" -Parameters @{ repository="Test-nuget-hosted" } |
            Select-Object -First 1
        }
        It "Retrieves some components" {
            $Result = $Component | Get-NexusRepoComponent
            $Result | Should -HaveCount 1
            $Result.id | Should -Be $Component.id
        }
    }
}

Describe "Remove-NexusRepoComponent" {
    It "Calls the endpoint" {
        { Remove-NexusRepoComponent -Id "Q05SV00tcmF3LWhvc3RlZC1kZXY6MGFiODBhNzQzOTIxZTQyNmRlNzBkZDE1NjgyZTI4ZG1" -WhatIf } |
        Should -Not -Throw
    }
}

AfterAll {
    $Settings | Connect-NexusRepo | Out-Null
}

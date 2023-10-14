[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification='Suppress false positives in Pester code blocks')]
param ()

BeforeAll {
    $Separator = [System.IO.Path]::DirectorySeparatorChar
    Import-Module "$PSScriptRoot$Separator`NexusRepo.psd1" -Force
    $SaveDir = "$env:APPDATA$Separator`NexusRepo"
    $AuthXmlPath = "$SaveDir$Separator`Auth.xml"

    [uri]$BaseUrl = "https://nexus.mycompany.com"

    if (-not (Test-Path -Path $AuthXmlPath))
    {
        Connect-NexusRepo -BaseUrl $BaseUrl -APIVersion v2 | Out-Null
    }
    $Settings = Import-Clixml -Path $AuthXmlPath
    $Settings | Connect-NexusRepo -MaxPages 2 | Out-Null
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
        $Result.MaxPages | Should -BeOfType [ushort]
        $Result | Should -HaveCount 1
    }
    It "Saves their profile info by passing a credential from the pipeline" {
        $Result = $Settings | Connect-NexusRepo -BaseUrl $Settings.BaseUrl -APIVersion $Settings.APIVersion -MaxPages 100
        $AuthXmlPath | Should -Exist
        $Result.Credential | Should -Not -BeNullOrEmpty
        $Result.Credential.UserName | Should -Be $Settings.Credential.UserName
        $Result.APIVersion | Should -Be $Settings.APIVersion
        $Result.MaxPages | Should -BeOfType [ushort]
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
        $Settings.MaxPages | Should -BeOfType [ushort]
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
        $Result = "Test-nuget-hosted-dev","Test-nuget-hosted-prod" | Get-NexusRepoRepository
        $Result | Should -HaveCount 2
        $Result[0].name | Should -Be "Test-nuget-hosted-dev"
        $Result[1].name | Should -Be "Test-nuget-hosted-prod"
    }
}

Describe "Get-NexusRepoAsset" {
    BeforeAll {
        $Settings = Get-NexusRepoSettings
    }
    Context "Name parameter" {
        BeforeAll {
            $Settings | Connect-NexusRepo -MaxPages 2 | Out-Null
        }
        It "Returns some assets given a repository name" {
            $Result = Get-NexusRepoAsset -Name "Test-raw-hosted-dev"
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -HaveCount 20
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
            $Assets = Get-NexusRepoAsset -Name "Test-raw-hosted-dev"
            $Assets | Should -Not -BeNullOrEmpty
            $Result = Get-NexusRepoAsset -Id $Assets[0].Id
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -HaveCount 1
            $Result.id | Should -Be $Assets[0].Id
            $Result.format | Should -Be "raw"
        }
        It "Retrieves an asset using the pipeline" {
            $Assets = Get-NexusRepoAsset -Name "Test-raw-hosted-dev"
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
    BeforeAll {
        if ((Get-NexusRepoSettings).MaxPages -ne 1)
        {
            $Settings | Connect-NexusRepo -MaxPages 1 | Out-Null # We only need a single result
        }
    }
    It "Searches for and returns some based on a format" {
        $Result = Find-NexusRepoAsset -Repository "Test-raw-hosted-dev" -Format raw
        $Result | Should -Not -BeNullOrEmpty
        $Result[0].format | Should -Be "raw"
    }
    It "Searches for and returns some based on a some NuGet properties" {
        $Assets = Get-NexusRepoAsset -Name "Test-nuget-hosted-dev"
        $Splat = @{
            Repository = "Test-nuget-hosted-dev"
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
        if ((Get-NexusRepoSettings).MaxPages -ne 1)
        {
            $Settings | Connect-NexusRepo -MaxPages 1 | Out-Null # We only need a single result
        }
        $Assets = Get-NexusRepoAsset -Name "Test-raw-hosted-dev"
    }
    It "Removes the specified assets" {
        $Assets[0],$Assets[1] | Remove-NexusRepoAsset -WhatIf
        $Result = Find-NexusRepoAsset -Repository "Test-nuget-hosted-dev" -Sha1 $Assets[0].checksum.sha1
        $Result | Should -BeNullOrEmpty
        $Result = Find-NexusRepoAsset -Repository "Test-nuget-hosted-dev" -Sha1 $Assets[1].checksum.sha1
        $Result | Should -BeNullOrEmpty
    }
}

AfterAll {
    $Settings | Connect-NexusRepo | Out-Null
}

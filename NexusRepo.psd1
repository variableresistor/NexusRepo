@{
RootModule = 'NexusRepo'
ModuleVersion = '1.0.0'
CompatiblePSEditions = @('Core','Desktop')
GUID = '80f0fa8a-9493-4d53-8b41-f29eead645cd'
Author = 'Neil White'
CompanyName = ''
Copyright = ''
Description = 'Module acts as a wrapper for the Nexus Repository REST API'
PowerShellVersion = '5.1.0'
# RequiredModules = @()
# RequiredAssemblies = @()
# TypesToProcess = @()
# FormatsToProcess = @()
# NestedModules = @()
FunctionsToExport = @(
    "Connect-NexusRepo"
    "Disconnect-NexusRepo"
    "Get-NexusRepoSettings"
    "Get-NexusRepoRepository"
    "Find-NexusRepoAsset"
    "Get-NexusRepoAsset"
    "Test-NexusRepoStatus"
    "Remove-NexusRepoAsset"
)
CmdletsToExport = @()
# VariablesToExport = '*'
AliasesToExport = @(
    "Login-NexusRepo"
    "Logout-NexusRepo"
    "Save-NexusRepoLogin"
    "Remove-NexusRepoLogin"
)
# ModuleList = @()
PrivateData = @{
    PSData = @{
        Tags = 'Repository','Nexus'
        # LicenseUri = ''
        ProjectUri = 'https://github.com/citynationalbank/CNRWM_PoshNexusRepo'
        # IconUri = ''
        # ReleaseNotes = ''
        # Prerelease = ''
        # ExternalModuleDependencies = @()
    }
}
# HelpInfoURI = ''
}


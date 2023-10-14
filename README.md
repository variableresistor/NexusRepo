# Nexus Repository PowerShell Module 
PowerShell module to interact with the Nexus Repository REST API. Essentially a wrapper for built-in Nexus Repository REST API functionality. Documentation for the REST API can be found [here](https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api).

## Using The Module
```powershell
Connect-NexusRepo -Credential (Get-Credential -Message "Enter your user code and passcode generated from Nexus Repo") -BaseUrl https://nexusiq.mycompany.com
```

## Installation
Run the following command in PowerShell session to install the module from the PowerShell Gallery. If following the instructions above, the below command should not require elevation

```powershell
Install-Module -Name NexusRepo -Scope CurrentUser
```

## Update
If you already have the module installed, run the following command to update the module from the PowerShell Gallery to the latest version.

```powershell
Update-Module -Name NexusRepo
```
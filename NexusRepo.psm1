"Import Microsoft.PowerShell.Commands.WebRequestMethod" | Out-Null
$Separator = [System.IO.Path]::DirectorySeparatorChar

<#
.SYNOPSIS
    Saves the user's Nexus Repository token using a saved PSCredential object stored as a CliXml file with an XML extension.
    Only works on a per-machine, per-user basis.
.PARAMETER Credential
    PSCredential where the username is the UserCode and the password is the PassCode. This will be passed to Nexus Repository when calling the
    API. PowerShell 7+ automatically formats the username and password properly using Base-64 encoding and Basic authentication.
.PARAMETER BaseUrl
    The URL of the Nexus Repository website
.PARAMETER MaxPages
    Limit the number of pages to return
.EXAMPLE
    Connect-NexusRepo -BaseUrl https://nexus.mycompany.com
.EXAMPLE
    # Reuse an existing profile's base URL and change the credentials
    $Settings = Get-NexusRepoSettings
    $Settings | Connect-NexusRepo -Credential (Get-Credential)
#>
filter Connect-NexusRepo
{
    [CmdletBinding()]
    [Alias("Login-NexusRepo","Save-NexusRepoLogin")]
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [string]$BaseUrl,

        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,

        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [NexusRepoAPIVersion]$APIVersion = "v1",

        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]
        [uint]$MaxPages = 0
    )
    if (-not (Test-Path ([NexusRepoSettings]::SaveDir))) { New-Item -Type Directory -Path ([NexusRepoSettings]::SaveDir) | Out-Null }
    else { Write-Verbose "Profile folder already existed" }

    $Settings = [NexusRepoSettings]::new($Credential,$BaseUrl,$APIVersion,$MaxPages)
    $Settings | Export-CliXml -Path ([NexusRepoSettings]::SavePath) -Encoding 'utf8' -Force
    $Settings
}

<#
.SYNOPSIS
    Removes the user's login profile
.EXAMPLE
    Disconnect-NexusRepo
#>
filter Disconnect-NexusRepo
{
    [CmdletBinding()]
    [Alias("Logout-NexusRepo","Remove-NexusRepoLogin")]
    param ()
    Remove-Item ([NexusRepoSettings]::SaveDir) -Recurse
}

<#
.SYNOPSIS
    Retrieves the saved profile information of the current user, including BaseUrl and the userCode and passCode they are using. No parameters required.
#>
filter Get-NexusRepoSettings
{
    [CmdletBinding()]
    [OutputType([NexusRepoSettings])]
    param ()
    if (Test-Path -Path ([NexusRepoSettings]::SavePath))
    {
        $XML = Import-Clixml -Path ([NexusRepoSettings]::SavePath)
        [NexusRepoSettings]::new($XML.Credential,$XML.BaseUrl,$XML.APIVersion,$XML.MaxPages)
    }
    else
    {
        throw "Use Connect-NexusRepo to create a login profile"
    }
}

filter Invoke-NexusRepoAPI
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$Path,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = "Get",
        [Hashtable]$Parameters,
        [string]$OutFile,
        [ValidateSet("REST","Download")]
        [string]$RequestType = "REST",
        [string]$ContentType
    )
    $Settings = Get-NexusRepoSettings
    $StringBuilder = [System.Text.StringBuilder]::new($Settings.BaseUrl)
    switch ($RequestType)
    {
        "REST" {
            $StringBuilder.Append("service/rest/$($Settings.APIVersion)/$Path") | Out-Null
        }
        "Download" {
            $StringBuilder.Append($Path) | Out-Null
        }
    }

    if ($Parameters)
    {
        $Separator = "?"
        $Parameters.Keys | ForEach-Object {
            $StringBuilder.Append(("{0}{1}={2}" -f $Separator,$_,[System.Web.HttpUtility]::UrlEncode($Parameters."$_".ToString()))) | Out-Null
            $Separator = "&"
        }
    }
    $Uri = $StringBuilder.ToString()
    Write-Verbose "Invoking Url $Uri"

    $Splat = @{
        Uri           = $Uri
        Method        = $Method
    }
    if ($PSEdition -eq "Core")
    {
        $Splat.Add("Authentication","Basic")
        $Splat.Add("Credential",$Settings.Credential)
    }
    else
    {
        $Splat.Add("Headers",(Format-AuthHeaders -Credential $Settings.Credential))
    }
    if ($OutFile) { $Splat.Add("OutFile",$OutFile) }
    if ($ContentType) { $Splat.Add("ContentType",$ContentType) }

    $Response = Invoke-RestMethod @Splat
    if ($Response | Get-Member -Name continuationToken -ErrorAction Ignore)
    {
        Write-Verbose "Paginated response. Keep requesting until the max count is reached or until the end of results."
        $Response.items
        $OriginalUrl = $Splat.Uri
        for ($i=1;$null -ne $Response.continuationToken -and ($Settings.MaxPages -eq 0 -or $i -lt $Settings.MaxPages); $i++)
        {
            $Splat.Uri = "$OriginalUrl&continuationToken=$($Response.continuationToken)"
            $Response = Invoke-RestMethod @Splat
            $Response.items
        }
    }
    else { $Response }
}

<#
.SYNOPSIS
    Used for Windows PowerShell to construct and return the authentication header
#>
filter Format-AuthHeaders
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscredential]$Credential
    )
    $Pair = "$($Credential.Username):$($Credential.GetNetworkCredential().Password)"
    $EncodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($Pair))
    @{ Authorization = "Basic $EncodedCreds" }
}

class NexusRepoSettings
{
    static [String]$SaveDir = "$env:APPDATA$Separator`PoshNexusRepo"
    static [String]$SavePath = "$([NexusRepoSettings]::SaveDir)$Separator`Auth.xml"

    # Parameters
    [String]$BaseUrl
    [PSCredential]$Credential
    [NexusRepoAPIVersion]$APIVersion
    [uint]$MaxPages

    NexusRepoSettings([PSCredential]$Credential,[uri]$BaseUrl,[NexusRepoAPIVersion]$APIVersion,[uint]$MaxPages)
    {
        $this.BaseUrl = $BaseUrl
        $this.Credential = $Credential
        $this.APIVersion = $APIVersion
        $this.MaxPages = $MaxPages
    }
}

enum NexusRepoAPIVersion
{
    v1
}

<#
.SYNOPSIS
    Iterates through a listing of repositories a user has browse access to.
.PARAMETER Name
    The name of the repository (optional)
.LINK
    https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api/repositories-api
#>
function Get-NexusRepoRepository
{
    [CmdletBinding()]
    param (
        [SupportsWildcards()]
        [Parameter(ValueFromPipeline)]
        [string[]]$Name
    )
    begin
    {
        $Script:Repos = Invoke-NexusRepoAPI -Path "repositories"
    }
    process
    {
        if ($Name)
        {
            foreach ($RepoName in $Name)
            {
                $Repos | Where-Object -Property name -Like $RepoName
            }
        }
        else { $Repos }
    }
}

<#
.SYNOPSIS
    Iterates through a listing of assets contained in a given repository or allows us to get the details of an individual asset.
.PARAMETER Name
    Name of the repository
.PARAMETER Id
    Id of the asset. This can be retrieved from Get-NexusRepoAsset with the name parameter
.LINK
    https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api/assets-api
#>
filter Get-NexusRepoAsset
{
    [CmdletBinding(DefaultParameterSetName="Id")]
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName,ParameterSetName="Name")]
        [Alias("Name")]
        [string[]]$Repository,

        [Parameter(Mandatory,ValueFromPipelineByPropertyName,ParameterSetName="Id")]
        [string[]]$Id
    )
    if ($Repository)
    {
        foreach ($RepoName in $Repository)
        {
            Invoke-NexusRepoAPI -Path "assets" -Parameters @{ repository=$RepoName }
        }
    }
    elseif ($Id)
    {
        foreach ($AssetId in $Id)
        {
            Invoke-NexusRepoAPI -Path "assets/$AssetId"
        }
    }
}

<#
.SYNOPSIS
    Search assets. Also doubles to provide larger results sets that Get-NexusRepoAsset.
.PARAMETER Query
    Query by keyword.
.PARAMETER Repository
    Repository name.
.PARAMETER Format
    Query by format. Probably the format of the asset and/or repository.
.PARAMETER Group
    Component Group. Basically the folder containing the artifact.
.PARAMETER Name
    Component name.
.PARAMETER Version
    Component version
.PARAMETER NuGetId
    NuGet id
.PARAMETER Sha1
    Specific SHA-1 hash of component's asset
.LINK
    https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api/search-api
#>
filter Find-NexusRepoAsset
{
    [CmdletBinding()]
    param (
        [string]$Query,
        [Alias("RepositoryName")]
        [string]$Repository,
        [ValidateSet("raw","nuget","docker","maven2","npm","pypi")]
        [string]$Format,
        [string]$Group,
        [string]$Name,
        [version]$Version,
        [string]$NuGetId,
        [string]$Sha1
    )
    $Splat = @{ Path = "search/assets"  }
    $Parameters = @{}
    if ($Query) { $Parameters.Add("q",$Query) }
    if ($Repository) { $Parameters.Add("repository",$Repository) }
    if ($Format) { $Parameters.Add("format",$Format) }
    if ($Group) { $Parameters.Add("group",$Group) }
    if ($Name) { $Parameters.Add("name",$Name) }
    if ($Version -gt [version]::new()) { $Parameters.Add("version",$Version.ToString()) }
    if ($NuGetId) { $Parameters.Add("nuget.id",$NuGetId) }
    if ($Sha1) { $Parameters.Add("sha1",$Sha1) }
    if ($Parameters.Count) { $Splat.Add("Parameters",$Parameters) }

    Invoke-NexusRepoAPI @Splat
}

<#
.SYNOPSIS
    Delete a single asset
.PARAMETER Id
    Id of the asset to delete
.LINK
    https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api/assets-api#AssetsAPI-DeleteAsset
#>
filter Remove-NexusRepoAsset
{
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [uint[]]$Id
    )
    foreach ($AssetId in $Id)
    {
        if ($PSCmdlet.ShouldProcess($AssetId))
        {
            Invoke-NexusRepoAPI -Path "assets/$AssetId" -Method Delete
        }
    }
}

<#
.SYNOPSIS
    Search for one asset and then redirect the request to the downloadUrl of that asset, then downloads the asset.
.PARAMETER downloadUrl
    A property of the Raw artifact type.
.LINK
    https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api/search-api
.EXAMPLE
    Request-NexusRepoAsset -Name 
#>
filter Request-NexusRepoAsset
{
    [CmdletBinding()]
    [OutputType("System.IO.FileInfo")]
    param (
        [Parameter(ValueFromPipelineByPropertyName,Mandatory)]
        [string]$downloadUrl,

        [Parameter(ValueFromPipelineByPropertyName,Mandatory)]
        [ValidateSet("raw","nuget","maven2","npm","pypi")]
        [string]$Format,

        [Parameter(Mandatory)]
        [string]$OutFolder
    )
    $UriPath = ([uri]($downloadUrl)).LocalPath.Remove(0,1)
    $FullPath = $(
        switch ($Format)
        {
            "nuget" { "$OutFolder$Separator$([System.IO.Path]::GetFileName($downloadUrl)).nupkg" }
            default { "$OutFolder$Separator$([System.IO.Path]::GetFileName($downloadUrl))" }
        }
    )
    Invoke-NexusRepoAPI -Path $UriPath -OutFile $FullPath -RequestType Download
    if (Test-Path $FullPath)
    {
        Get-ItemProperty $FullPath
    }
}

<#
.SYNOPSIS
    Iterates through a listing of components contained in a given repository or allows us to get the details of an individual asset.
.PARAMETER Name
    Name of the repository
.PARAMETER Id
    Id of the component. This can be retrieved from Get-NexusRepoComponent with the name parameter.
.LINK
    https://help.sonatype.com/repomanager3/integrations/rest-and-integration-api/components-api#ComponentsAPI-ListComponents
#>
filter Get-NexusRepoComponent
{
    [CmdletBinding(DefaultParameterSetName="Id")]
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName,ParameterSetName="RepoName")]
        [Alias("RepositoryName")]
        [string[]]$Repository,

        [Parameter(Mandatory,ValueFromPipelineByPropertyName,ParameterSetName="Id")]
        [string[]]$Id
    )
    if ($Repository)
    {
        foreach ($RepoName in $Repository)
        {
            Invoke-NexusRepoAPI -Path "components" -Parameters @{ repository=$RepoName }
        }
    }
    elseif ($Id)
    {
        foreach ($ComponentId in $Id)
        {
            Invoke-NexusRepoAPI -Path "components/$ComponentId"
        }
    }
}

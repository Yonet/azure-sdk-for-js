# Common Changelog Operations
. "${PSScriptRoot}\logging.ps1"
. "${PSScriptRoot}\SemVer.ps1"

$RELEASE_TITLE_REGEX = "(?<releaseNoteTitle>^\#+.*(?<version>\b\d+\.\d+\.\d+([^0-9\s][^\s:]+)?)(\s+(?<releaseStatus>\(.*\)))?)"
$CHANGELOG_UNRELEASED_STATUS = "(Unreleased)"
$CHANGELOG_DATE_FORMAT = "yyyy-MM-dd"

# Returns a Collection of changeLogEntry object containing changelog info for all version present in the gived CHANGELOG
function Get-ChangeLogEntries {
  param (
    [Parameter(Mandatory = $true)]
    [String]$ChangeLogLocation
  )

  $changeLogEntries = [Ordered]@{}
  if (!(Test-Path $ChangeLogLocation)) {
    LogError "ChangeLog[${ChangeLogLocation}] does not exist"
    return $null
  }

  try {
    $contents = Get-Content $ChangeLogLocation
    # walk the document, finding where the version specifiers are and creating lists
    $changeLogEntry = $null
    foreach ($line in $contents) {
      if ($line -match $RELEASE_TITLE_REGEX) {
        $changeLogEntry = [pscustomobject]@{ 
          ReleaseVersion = $matches["version"]
          ReleaseStatus  =  $matches["releaseStatus"]
          ReleaseTitle   = "## {0} {1}" -f $matches["version"], $matches["releaseStatus"]
          ReleaseContent = @()
        }
        $changeLogEntries[$changeLogEntry.ReleaseVersion] = $changeLogEntry
      }
      else {
        if ($changeLogEntry) {
          $changeLogEntry.ReleaseContent += $line
        }
      }
    }
  }
  catch {
    Write-Host "Error parsing $ChangeLogLocation."
    Write-Host $_.Exception.Message
  }
  return $changeLogEntries
}

# Returns single changeLogEntry object containing the ChangeLog for a particular version
function Get-ChangeLogEntry {
  param (
    [Parameter(Mandatory = $true)]
    [String]$ChangeLogLocation,
    [Parameter(Mandatory = $true)]
    [String]$VersionString
  )
  $changeLogEntries = Get-ChangeLogEntries -ChangeLogLocation $ChangeLogLocation

  if ($changeLogEntries -and $changeLogEntries.ContainsKey($VersionString)) {
    return $changeLogEntries[$VersionString]
  }
  return $null
}

#Returns the changelog for a particular version as string
function Get-ChangeLogEntryAsString {
  param (
    [Parameter(Mandatory = $true)]
    [String]$ChangeLogLocation,
    [Parameter(Mandatory = $true)]
    [String]$VersionString
  )

  $changeLogEntry = Get-ChangeLogEntry -ChangeLogLocation $ChangeLogLocation -VersionString $VersionString
  return ChangeLogEntryAsString $changeLogEntry
}


function ChangeLogEntryAsString($changeLogEntry) {
  if (!$changeLogEntry) {
    return "[Missing change log entry]"
  }
  [string]$releaseTitle = $changeLogEntry.ReleaseTitle
  [string]$releaseContent = $changeLogEntry.ReleaseContent -Join [Environment]::NewLine
  return $releaseTitle, $releaseContent -Join [Environment]::NewLine
}

function Confirm-ChangeLogEntry {
  param (
    [Parameter(Mandatory = $true)]
    [String]$ChangeLogLocation,
    [Parameter(Mandatory = $true)]
    [String]$VersionString,
    [boolean]$ForRelease = $false
  )

  $changeLogEntry = Get-ChangeLogEntry -ChangeLogLocation $ChangeLogLocation -VersionString $VersionString

  if (!$changeLogEntry) {
    LogError "ChangeLog[${ChangeLogLocation}] does not have an entry for version ${VersionString}."
    return $false
  }

  Write-Host "Found the following change log entry for version '${VersionString}' in [${ChangeLogLocation}]."
  Write-Host "-----"
  Write-Host (ChangeLogEntryAsString $changeLogEntry)
  Write-Host "-----"

  if ([System.String]::IsNullOrEmpty($changeLogEntry.ReleaseStatus)) {
    LogError "Entry does not have a correct release status. Please ensure the status is set to a date '($CHANGELOG_DATE_FORMAT)' or '$CHANGELOG_UNRELEASED_STATUS' if not yet released."
    return $false
  }

  if ($ForRelease -eq $True) {
    if ($changeLogEntry.ReleaseStatus -eq $CHANGELOG_UNRELEASED_STATUS) {
      LogError "Entry has no release date set. Please ensure to set a release date with format '$CHANGELOG_DATE_FORMAT'."
      return $false
    }
    else {
      $status = $changeLogEntry.ReleaseStatus.Trim().Trim("()")
      try {
        [DateTime]$status
      }
      catch {
          LogError "Invalid date [ $status ] passed as status for Version [$($changeLogEntry.ReleaseVersion)]."
          return $false
      }
    }

    if ([System.String]::IsNullOrWhiteSpace($changeLogEntry.ReleaseContent)) {
      LogError "Entry has no content. Please ensure to provide some content of what changed in this version."
      return $false
    }
  }
  return $true
}

function New-ChangeLogEntry {
  param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]$Version,
    [String]$Status=$CHANGELOG_UNRELEASED_STATUS,
    [String[]]$Content
  )

  # Validate RelaseStatus
  $Status = $Status.Trim().Trim("()")
  if ($Status -ne "Unreleased") {
    try {
      $Status = ([DateTime]$Status).ToString($CHANGELOG_DATE_FORMAT)
    }
    catch {
        LogWarning "Invalid date [ $Status ] passed as status for Version [$Version]. Please use a valid date in the format '$CHANGELOG_DATE_FORMAT' or use '$CHANGELOG_UNRELEASED_STATUS'"
        return $null
    }
  }
  $Status = "($Status)"

  # Validate Version
  try {
    $Version = ([AzureEngSemanticVersion]::ParseVersionString($Version)).ToString()
  }
  catch {
    LogWarning "Invalid version [ $Version ]."
    return $null
  }

  if (!$Content) { $Content = @() }

  $newChangeLogEntry = [pscustomobject]@{ 
    ReleaseVersion = $Version
    ReleaseStatus  = $Status
    ReleaseTitle   = "## $Version $Status"
    ReleaseContent = $Content
  }

  return $newChangeLogEntry
}

function Set-ChangeLogContent {
  param (
    [Parameter(Mandatory = $true)]
    [String]$ChangeLogLocation,
    [Parameter(Mandatory = $true)]
    $ChangeLogEntries
  )

  $changeLogContent = @()
  $changeLogContent += "# Release History"
  $changeLogContent += ""

  foreach ($version in $ChangeLogEntries.Keys) {
    $changeLogEntry = $ChangeLogEntries[$version]
    $changeLogContent += $changeLogEntry.ReleaseTitle
    if ($changeLogEntry.ReleaseContent.Count -eq 0) {
      $changeLogContent += @("","")
    }
    else {
      $changeLogContent += $changeLogEntry.ReleaseContent
    }
  }

  Set-Content -Path $ChangeLogLocation -Value $changeLogContent
}

function Add-ChangelogEntry {
  param (
    [Parameter(Mandatory = $true)]
    $ChangeLogEntries,
    [Parameter(Mandatory = $true)]
    $NewChangeLogEntry,
    [Parameter(Mandatory = $true)]
    $Version
  )

  $results = [Ordered]@{}
  $results.Add($Version, $NewChangeLogEntry)

  foreach ($entryVersion in $ChangeLogEntries.Keys) {
    $results.Add($entryVersion, $ChangeLogEntries[$entryVersion])
  }

  return $results
}
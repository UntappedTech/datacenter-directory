param(
    [Parameter(Mandatory = $false)]
    [string]$GroupCsvPath = "group_membership.csv",

    [switch]$DryRun
)

#
# Path resolution helper — resolves absolute paths directly,
# and resolves relative paths relative to the loader (caller).
#
function Resolve-InputPath {
    param([string]$Path)

    $trimmed = $Path.Trim('"')

    if ([System.IO.Path]::IsPathRooted($trimmed)) {
        return $trimmed
    }

    # Resolve relative to the caller (loader)
    $callerRoot = Split-Path -Parent $MyInvocation.PSCommandPath
    $combined = Join-Path $callerRoot $trimmed

    # If it doesn't exist yet, return the combined path anyway
    if (-not (Test-Path $combined)) {
        return $combined
    }

    return (Resolve-Path $combined).Path
}

$GroupCsvPath = Resolve-InputPath $GroupCsvPath

#
# Membership CSV may not exist — create it if missing
#
if (-not (Test-Path $GroupCsvPath)) {
    Write-Warning "Group membership CSV not found. Creating new file at: $GroupCsvPath"

    @(
        [PSCustomObject]@{
            Group   = ""
            Members = ""
        }
    ) | Export-Csv -Path $GroupCsvPath -NoTypeInformation
}

Write-Host "Using membership CSV: $GroupCsvPath" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE ENABLED" -ForegroundColor Yellow }

#
# Load Graph modules
#
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.DirectoryObjects

Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All" -UseDeviceCode

$csv = Import-Csv $GroupCsvPath

foreach ($row in $csv) {

    $groupName = $row.Group
    $desiredMembers = @()

    if ($row.Members -and $row.Members.Trim() -ne "") {
        $desiredMembers = $row.Members.Split(";") | ForEach-Object { $_.Trim() }
    }

    Write-Host "Processing group: $groupName"

    #
    # Resolve group
    #
    $groupObj = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
    if (-not $groupObj) {
        Write-Host "  ! Group not found: $groupName"
        continue
    }

    #
    # Resolve desired member ObjectIds
    #
    $desiredObjectIds = @()
    foreach ($member in $desiredMembers) {
        $u = Get-MgUser -Filter "userPrincipalName eq '$member'" -ErrorAction SilentlyContinue
        if ($u) {
            $desiredObjectIds += $u.Id
        }
        else {
            Write-Host "  ! User not found: $member"
        }
    }

    #
    # Get current members
    #
    $currentMembers = Get-MgGroupMember -GroupId $groupObj.Id -ErrorAction SilentlyContinue
    $currentObjectIds = @($currentMembers.Id)

    #
    # Drift detection
    #
    $toAdd = $desiredObjectIds | Where-Object { $currentObjectIds -notcontains $_ }
    $toRemove = $currentObjectIds | Where-Object { $desiredObjectIds -notcontains $_ }

    #
    # Dry-run output
    #
    foreach ($id in $toAdd) {
        $u = Get-MgUser -UserId $id
        Write-Host ("  + Would add member: {0}" -f $u.UserPrincipalName)
    }

    foreach ($id in $toRemove) {
        $u = Get-MgUser -UserId $id
        Write-Host ("  - Would remove member: {0}" -f $u.UserPrincipalName)
    }

    if ($DryRun) { continue }

    #
    # Apply changes
    #
    foreach ($id in $toAdd) {
        New-MgGroupMember -GroupId $groupObj.Id -DirectoryObjectId $id -ErrorAction SilentlyContinue
        $u = Get-MgUser -UserId $id
        Write-Host ("  + Added member: {0}" -f $u.UserPrincipalName)
    }

    foreach ($id in $toRemove) {
        Remove-MgGroupMember -GroupId $groupObj.Id -DirectoryObjectId $id -ErrorAction SilentlyContinue
        $u = Get-MgUser -UserId $id
        Write-Host ("  - Removed member: {0}" -f $u.UserPrincipalName)
    }
}

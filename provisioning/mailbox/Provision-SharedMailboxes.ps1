param(
    [Parameter(Mandatory = $true)]
    [string]$MailboxesCsvPath,

    [Parameter(Mandatory = $false)]
    [string]$MembershipCsvPath = "group_membership.csv",

    [Parameter(Mandatory = $false)]
    [string]$RenameLogPath = "rename_log.txt",

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

$MailboxesCsvPath = Resolve-InputPath $MailboxesCsvPath
$MembershipCsvPath = Resolve-InputPath $MembershipCsvPath
$RenameLog = Resolve-InputPath $RenameLogPath

#
# Validate mailbox CSV
#
if (-not (Test-Path $MailboxesCsvPath)) {
    Write-Error "Mailbox CSV not found at: $MailboxesCsvPath"
    exit 1
}

#
# Membership CSV may not exist — create a fully populated skeleton
#
if (-not (Test-Path $MembershipCsvPath)) {
    Write-Warning "Membership CSV not found. Creating new file at: $MembershipCsvPath"

    $mailboxesForSkeleton = Import-Csv $MailboxesCsvPath

    $skeleton = foreach ($mb in $mailboxesForSkeleton) {
        $name = $mb.Name

        [PSCustomObject]@{
            Group   = "SG_${name}_FullAccess"
            Members = ""
        }

        [PSCustomObject]@{
            Group   = "SG_${name}_SendAs"
            Members = ""
        }
    }

    $skeleton | Export-Csv -Path $MembershipCsvPath -NoTypeInformation
}

Write-Host "Using mailbox CSV: $MailboxesCsvPath" -ForegroundColor Cyan
Write-Host "Using membership CSV: $MembershipCsvPath" -ForegroundColor Cyan
Write-Host "Using rename log: $RenameLog" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE ENABLED" -ForegroundColor Yellow }

#
# Load Graph modules
#
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups

Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All" -UseDeviceCode
Connect-ExchangeOnline -ShowBanner:$false

$mailboxes = Import-Csv $MailboxesCsvPath
$membership = Import-Csv $MembershipCsvPath

foreach ($mb in $mailboxes) {

    $name = $mb.Name
    $primary = $mb.PrimarySmtp
    $aliases = $mb.Aliases -split ';'
    $folders = $mb.Folders -split ';'

    Write-Host "Processing mailbox: $primary"

    $existing = Get-Mailbox -Identity $primary -ErrorAction SilentlyContinue

    #
    # Create mailbox if missing
    #
    if (-not $existing) {
        if ($DryRun) {
            Write-Host ("  + Would create mailbox: {0}" -f $primary)
            continue
        }

        Write-Host "Creating shared mailbox..."
        New-Mailbox -Shared -Name $name -PrimarySmtpAddress $primary
        $existing = Get-Mailbox -Identity $primary
    }

    #
    # Detect mailbox rename
    #
    if ($existing.DisplayName -ne $name) {
        $oldName = $existing.DisplayName

        if ($DryRun) {
            Write-Host ("  ~ Would rename mailbox: '{0}' → '{1}'" -f $oldName, $name)
        }
        else {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Add-Content -Path $RenameLog -Value "$timestamp - Renamed mailbox '$oldName' → '$name'"
            Set-Mailbox -Identity $primary -DisplayName $name
        }

        #
        # Atomic rewrite of membership CSV
        #
        $renameMap = @{
            "SG_${oldName}_FullAccess" = "SG_${name}_FullAccess"
            "SG_${oldName}_SendAs"     = "SG_${name}_SendAs"
        }

        $updatedMembership = foreach ($row in $membership) {
            $newGroup = $row.Group
            if ($renameMap.ContainsKey($row.Group)) {
                $newGroup = $renameMap[$row.Group]
                if ($DryRun) {
                    Write-Host ("  ~ Would rewrite group name in CSV: {0} → {1}" -f $row.Group, $newGroup)
                }
            }

            [PSCustomObject]@{
                Group   = $newGroup
                Members = $row.Members
            }
        }

        if (-not $DryRun) {
            $tempPath = "$MembershipCsvPath.tmp"
            $updatedMembership | Export-Csv -Path $tempPath -NoTypeInformation
            Move-Item -Path $tempPath -Destination $MembershipCsvPath -Force
        }
    }

    #
    # Metadata drift detection
    #
    $mailboxMeta = @{
        HiddenFromAddressListsEnabled = ([bool]$mb.HideFromGAL)
        CustomAttribute1              = $mb.Description
    }

    $userMeta = @{
        Department = $mb.Department
    }

    #
    # Apply mailbox metadata
    #
    foreach ($key in $mailboxMeta.Keys) {
        $current = (Get-Mailbox -Identity $primary).$key
        $desired = $mailboxMeta[$key]

        if ($current -ne $desired) {
            if ($DryRun) {
                Write-Host ("  ~ Would update mailbox {0}: '{1}' → '{2}'" -f $key, $current, $desired)
            }
            else {
                Set-Mailbox -Identity $primary `
                    -HiddenFromAddressListsEnabled $mailboxMeta.HiddenFromAddressListsEnabled `
                    -CustomAttribute1 $mailboxMeta.CustomAttribute1
            }
        }
    }

    #
    # Apply AAD user metadata
    #
    foreach ($key in $userMeta.Keys) {
        $current = (Get-MgUser -UserId $primary).$key
        $desired = $userMeta[$key]

        if ($current -ne $desired) {
            if ($DryRun) {
                Write-Host ("  ~ Would update user {0}: '{1}' → '{2}'" -f $key, $current, $desired)
            }
            else {
                Update-MgUser -UserId $primary -Department $desired
            }
        }
    }

    #
    # Alias drift detection
    #
    $currentAliases = (Get-Mailbox -Identity $primary).EmailAddresses

    foreach ($alias in $aliases) {
        if ($alias -and ($currentAliases -notcontains $alias)) {
            if ($DryRun) {
                Write-Host ("  + Would add alias: {0}" -f $alias)
            }
            else {
                Set-Mailbox -Identity $primary -EmailAddresses @{add = $alias }
            }
        }
    }

    #
    # Folder drift detection
    #
    foreach ($folder in $folders) {
        if (-not $folder) { continue }

        $folderPath = "${primary}:\Inbox\$folder"
        $existsFolder = Get-MailboxFolder -Identity $folderPath -ErrorAction SilentlyContinue

        if (-not $existsFolder) {
            if ($DryRun) {
                Write-Host ("  + Would create folder: {0}" -f $folder)
            }
            else {
                New-MailboxFolder -Parent "${primary}:\Inbox" -Name $folder -ErrorAction SilentlyContinue
            }
        }
    }

    #
    # Group rename + creation
    #
    $faGroupOld = "SG_${existing.DisplayName}_FullAccess"
    $saGroupOld = "SG_${existing.DisplayName}_SendAs"

    $faGroupNew = "SG_${name}_FullAccess"
    $saGroupNew = "SG_${name}_SendAs"

    foreach ($pair in @(
            @{Old = $faGroupOld; New = $faGroupNew },
            @{Old = $saGroupOld; New = $saGroupNew }
        )) {
        $old = $pair.Old
        $new = $pair.New

        $groupObj = Get-MgGroup -Filter "displayName eq '$old'" -ErrorAction SilentlyContinue

        if ($groupObj) {
            if ($DryRun) {
                Write-Host ("  ~ Would rename group: {0} → {1}" -f $old, $new)
            }
            else {
                $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                Add-Content -Path $RenameLog -Value "$timestamp - Renamed group '$old' → '$new'"
                Update-MgGroup -GroupId $groupObj.Id -DisplayName $new -Description $mb.GroupDescription
            }
        }
    }

    foreach ($g in @($faGroupNew, $saGroupNew)) {
        $existingGroup = Get-MgGroup -Filter "displayName eq '$g'" -ErrorAction SilentlyContinue

        if (-not $existingGroup) {
            if ($DryRun) {
                Write-Host ("  + Would create group: {0}" -f $g)
            }
            else {
                $mailNick = $g.ToLower().Replace(" ", "").Replace("_", "").Replace("-", "")

                New-MgGroup `
                    -DisplayName $g `
                    -MailEnabled:$false `
                    -SecurityEnabled:$true `
                    -MailNickname $mailNick `
                    -Description $mb.GroupDescription
            }
        }
    }

    #
    # Permission drift detection
    #
    $faGroup = $faGroupNew
    $saGroup = $saGroupNew

    $faPerm = Get-MailboxPermission -Identity $primary -User $faGroup -ErrorAction SilentlyContinue
    if (-not $faPerm) {
        if ($DryRun) {
            Write-Host ("  + Would assign FullAccess to: {0}" -f $faGroup)
        }
        else {
            Add-MailboxPermission -Identity $primary -User $faGroup -AccessRights FullAccess -AutoMapping $true -Confirm:$false
        }
    }

    $saPerm = Get-RecipientPermission -Identity $primary -Trustee $saGroup -ErrorAction SilentlyContinue
    if (-not $saPerm) {
        if ($DryRun) {
            Write-Host ("  + Would assign SendAs to: {0}" -f $saGroup)
        }
        else {
            Add-RecipientPermission -Identity $primary -Trustee $saGroup -AccessRights SendAs -Confirm:$false
        }
    }
}

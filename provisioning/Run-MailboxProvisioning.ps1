param(
    [string]$MailboxesCsvPath = "shared_mailboxes.csv",
    [string]$MembershipCsvPath = "group_membership.csv",
    [switch]$DryRun
)

Write-Host "`n=== Mailbox Provisioning Loader ===`n" -ForegroundColor Cyan

# Determine repo root (directory containing this loader)
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve CSV paths relative to the loader location unless absolute
function Resolve-CsvPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path $Path).Path
    }

    $combined = Join-Path $RepoRoot $Path
    return (Resolve-Path $combined).Path
}

$MailboxesCsvPath = Resolve-CsvPath $MailboxesCsvPath
$MembershipCsvPath = Resolve-CsvPath $MembershipCsvPath

Write-Host "Mailboxes CSV: $MailboxesCsvPath" -ForegroundColor Cyan
Write-Host "Membership CSV: $MembershipCsvPath" -ForegroundColor Cyan
if ($DryRun) { Write-Host "DRY RUN MODE ENABLED" -ForegroundColor Yellow }

# Provisioning script directories
$ProvisioningRoot = Join-Path $RepoRoot "provisioning"

# Load all provisioning scripts
Write-Host "`n--- Importing provisioning scripts ---`n" -ForegroundColor Yellow

Get-ChildItem -Path $ProvisioningRoot -Recurse -Filter *.ps1 |
ForEach-Object {
    Write-Host "Loading: $($_.Name)" -ForegroundColor DarkGray
    . $_.FullName
}

# Step 1: Provision mailboxes + groups
Write-Host "`n--- Step 1: Provisioning mailboxes and groups ---`n" -ForegroundColor Yellow

$provisionArgs = @{
    MailboxesCsvPath  = $MailboxesCsvPath
    MembershipCsvPath = $MembershipCsvPath
}
if ($DryRun) { $provisionArgs["DryRun"] = $true }

Provision-SharedMailboxes @provisionArgs

# Step 2: Enforce strict group membership
Write-Host "`n--- Step 2: Enforcing strict group membership ---`n" -ForegroundColor Yellow

$membershipArgs = @{
    GroupCsvPath = $MembershipCsvPath
}
if ($DryRun) { $membershipArgs["DryRun"] = $true }

Apply-GroupMembership @membershipArgs

Write-Host "`n=== Loader execution complete ===`n" -ForegroundColor Cyan

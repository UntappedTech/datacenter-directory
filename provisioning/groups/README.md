# Group Membership Enforcement

This directory contains:

- `Apply-GroupMembership.ps1`

## CSV Inputs

### **group_membership.csv**

The script reads the **base/empty** CSV from the parent directory.

If the file is empty or missing, the provisioning script will have already generated a complete skeleton.

### **group_membership_example.csv**

A fictional example is provided in the parent directory for reference.

## Responsibilities

- Resolve groups by display name
- Resolve desired members from CSV
- Compare desired vs. actual membership
- Add missing members
- Remove drifted members
- Support DryRun mode

## Usage

Normally invoked via the wrapper:

```powershell
pwsh ../Run-MailboxProvisioning.ps1
```

Or directly:

```powershell
pwsh ./Apply-GroupMembership.ps1 -GroupCsvPath ../../group_membership.csv
```

## Notes

- Automatically creates a blank CSV if missing
- Uses Microsoft Graph for all membership operations
- Idempotent and safe to re-run

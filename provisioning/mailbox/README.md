# Mailbox Provisioning

This directory contains the mailbox provisioning engine:

- `Provision-SharedMailboxes.ps1`

## CSV Inputs

### **shared_mailboxes.csv**

The provisioning script reads the **base/empty** CSV from the parent directory.  
Users populate this file with real mailbox definitions.

### **shared_mailboxes_example.csv**

A fictional example is provided in the parent directory for reference.

### **group_membership.csv**

If this file does not exist, the provisioning script will **auto-generate a complete membership CSV** containing:

```
SG_<MailboxName>_FullAccess,
SG_<MailboxName>_SendAs,
```

This ensures the group membership enforcement script has a valid baseline.

## Responsibilities

- Create shared mailboxes
- Detect mailbox renames
- Update mailbox metadata
- Update AAD user metadata
- Enforce alias drift correction
- Create mailbox folders
- Create/rename FullAccess and SendAs groups
- Assign mailbox permissions
- Generate membership CSV if missing

## Usage

Normally invoked through the wrapper:

```powershell
pwsh ../Run-MailboxProvisioning.ps1
```

But it can be run directly:

```powershell
pwsh ./Provision-SharedMailboxes.ps1 -MailboxesCsvPath ../../shared_mailboxes.csv
```

## Notes

- All paths are resolved relative to the loader
- Safe to re-run (idempotent)
- Supports DryRun mode for previewing changes

# Provisioning Engine

This directory contains the top-level provisioning workflow for shared mailboxes and directory groups. It includes:

- `Run-MailboxProvisioning.ps1` — the orchestration wrapper
- `shared_mailboxes.csv` — base/empty desired-state definition for mailboxes
- `shared_mailboxes_example.csv` — fictional example mailbox definitions
- `group_membership.csv` — base/empty desired-state definition for group membership (auto-generated if missing)
- `group_membership_example.csv` — fictional example group membership definitions

---

## Run-MailboxProvisioning.ps1

This wrapper:

1. Resolves CSV paths
2. Imports all provisioning scripts from subdirectories
3. Provisions mailboxes and groups
4. Enforces strict group membership
5. Supports DryRun mode

It ensures all provisioning logic runs in a predictable, idempotent order.

### Example

```powershell
pwsh ./Run-MailboxProvisioning.ps1 -MailboxesCsvPath ./shared_mailboxes.csv -DryRun
```

---

# CSV Files

## shared_mailboxes.csv (base/empty)

This is the **real CSV** used by the provisioning engine.  
It ships empty:

```
Name,PrimarySmtp,Aliases,Folders,Description,Department,HideFromGAL,GroupDescription
```

Users populate this file with their actual mailbox definitions.

This file drives:

- mailbox creation
- mailbox rename detection
- metadata drift correction
- alias enforcement
- folder creation
- group naming conventions

---

## shared_mailboxes_example.csv (fictional)

A fully fictional example demonstrating the correct schema, naming conventions, and metadata fields.

This file is provided only as a reference and is safe for public repositories.

---

## group_membership.csv (base/empty)

This file ships empty:

```
Group,Members
```

If empty or missing, the provisioning script will **auto-generate a complete membership skeleton** based on the mailboxes defined in `shared_mailboxes.csv`.

Groups follow the naming convention:

- `SG_<MailboxName>_FullAccess`
- `SG_<MailboxName>_SendAs`

Members are semicolon-separated UPNs.

---

## group_membership_example.csv (fictional)

A fictional example showing how group membership should be structured, including semicolon-separated UPNs and realistic (but non-identifying) group names.

This file is provided only as a reference and is safe for public repositories.

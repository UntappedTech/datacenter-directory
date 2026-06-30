# datacenter-directory

Infrastructure-as-code tooling for identity, directory, and mailbox provisioning automation across hybrid and cloud environments.

This repository defines desired state for shared mailboxes, directory metadata, security groups, and group membership using CSV files. Provisioning scripts apply and enforce that desired state using Microsoft Graph and Exchange Online.

## CSV Files

Two CSV types exist in this repository:

### **1. Base (empty) CSVs**

These are the real, functional CSVs used by the provisioning engine:

- `provisioning/shared_mailboxes.csv` — empty schema
- `provisioning/group_membership.csv` — empty schema

The provisioning script will **auto-generate** a complete membership CSV if it does not exist.

### **2. Example CSVs**

These demonstrate the schema using **fictional** mailboxes and groups:

- `provisioning/shared_mailboxes_example.csv`
- `provisioning/group_membership_example.csv`

These are safe for public repos and help users understand how to structure their own data.

## Repository Structure

```
datacenter-directory/
│
├── provisioning/
│   ├── Run-MailboxProvisioning.ps1
│   ├── shared_mailboxes.csv
│   ├── shared_mailboxes_example.csv
│   ├── group_membership.csv
│   ├── group_membership_example.csv
│   │
│   ├── mailbox/
│   │   └── Provision-SharedMailboxes.ps1
│   │
│   └── groups/
│       └── Apply-GroupMembership.ps1
│
└── README.md
```

## Usage

Run the provisioning workflow:

```powershell
pwsh ./provisioning/Run-MailboxProvisioning.ps1
```

Preview changes:

```powershell
pwsh ./provisioning/Run-MailboxProvisioning.ps1 -DryRun
```

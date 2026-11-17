# Record & Replay

Record a business procedure, turn it into reviewed execution instructions,
and replay the approved process against uploaded data using a Windows 365
computer-use agent.

This guide describes the **Marketplace package 1.9.14 behavior**. Confirm the
version of the offer installed in your environment; older releases have different
identity inputs and activation checks. These instructions do not imply that
1.9.14 has been published to a Marketplace plan.

## Documentation

1. [Identity and Windows 365 prerequisites](IDENTITY-SETUP.md) - for tenant,
   identity and endpoint administrators.
2. [Deployment and acceptance](DEPLOYMENT.md) - for Azure deployment owners.
3. [Using Record & Replay](#using-record--replay) - for process owners and operators.
4. [Troubleshooting](#troubleshooting) - distinguish sign-in, federation, tool
   permissions, capacity and application-access failures.

## What runs where

```text
Operator browser
    |
    v
UI / API on Azure Container Apps
    |-- Recording --> Foundry hosted video planner
    |-- Instructions --> Foundry hosted Compliance / blueprint planner
    |
    +-- Execution request --> Azure queues
                                  |
                                  v
                         Durable Functions executor
                                  |
                                  v
                         Agent 365 computer-use MCP
                                  |
                                  v
                         Windows 365 agent Cloud PC
                                  |
                                  v
                         Approved business application
```

Storage and Cosmos DB hold uploaded artifacts and execution state; telemetry
supports operational investigation.

**Durable Functions is not hosted inside a Foundry hosted agent.** Foundry
planners generate instructions and grounding. The Functions executor performs
the durable execution workflow. Deployments can also use a separate Foundry
coordinator, but coordinator health alone does not establish worker readiness.

## Before using the offering

- Complete [identity and Windows 365 setup](IDENTITY-SETUP.md).
- Require the [installation acceptance checks](DEPLOYMENT.md#5-acceptance-checklist),
  not just an Azure deployment marked **Succeeded**.
- Obtain the application URL and an authorized product role from your
  administrator. Entra sign-in alone does not grant product permissions.
- Start with a nonproduction target and a small, approved test dataset.
- Ensure that using recordings, uploaded data and AI services complies with your
  organization's information-handling policies.

## Using Record & Replay

### 1. Prepare the procedure recording

Record one clear, representative procedure in the intended business application.
Show the starting page, required fields, navigation, save/submit action and
visible confirmation of success.

- Use the intended target organization, especially when production and UAT have
  similar URLs.
- Use synthetic or approved demonstration data.
- Do not record passwords, tokens, secrets or unnecessary personal information.
- Document any application setup or sign-in required before the procedure.
- Use a recording format accepted by the application's upload control.

A recording is input for planning, not approval to perform unrestricted actions.

### 2. Open the workbench and upload the inputs

1. Sign in to the deployed application and select the intended environment.
2. Open the data-entry workbench.
3. Upload the procedure recording, or select a previously saved recording.
4. Wait for extraction to finish. Review the generated instructions for missing
   steps, incorrect URLs and unintended actions.
5. Upload the dataset using a supported format, or select a previous upload.
6. Review the bounded data preview, column names and intended field mappings.

Do not assume that extraction success proves the target application is ready or
that every dataset row is safe to submit.

### 3. Generate and review the execution blueprint

Use **Generate Trusted Execution Blueprint** after reviewing the instructions
and data selection.

Validate:

- The exact target hostname and approved business operation.
- Required fields, column mappings and lookup behavior.
- Which actions create or update records.
- How success is recognized and how uncertain outcomes should be handled.
- Applicable approval and access requirements.

Do not start execution if the blueprint is incomplete or targets the wrong
environment. Changing instructions or selected inputs may require regenerating
and reviewing the blueprint.

### 4. Save the process

Use the workbench's process-saving controls to retain the selected upload,
recording, instructions and related blueprint/run references. Reopen saved
processes from the process list rather than reconstructing them from memory.

Recheck the environment, target URL, data and blueprint before reusing a process.
Saving a process does not grant permissions or authorize a new business run.

### 5. Start with a small controlled run

After required approvals and activation checks pass:

1. Start execution with a small approved dataset.
2. Monitor run and row/batch progress.
3. Verify the resulting records in the target application.
4. Investigate failures or uncertain commits before retrying.
5. Increase volume only after process-owner acceptance and capacity review.

Execution uses real Cloud PCs and can create or modify real business records.
Readiness checks do not certify every business process or dataset.

### 6. Monitor, stop and reconcile safely

- Use the application's run controls and operational views.
- Keep the run ID and sanitized failure/correlation identifiers for support.
- If stopping is required, use the product's authorized cancellation path.
  Stopping a Foundry coordinator or closing the browser is not a workflow-safe
  cancellation of a Durable Functions run.
- Do not clear capacity reservations or manually release a device until ownership
  and outstanding work have been reconciled.
- Do not blindly replay a row whose save outcome is uncertain; check for an
  existing target record first.

Optional screen sharing requires its own setup and permissions. A working
computer-use session does not automatically mean the viewer is authorized.

## Troubleshooting

| Symptom | Check first |
|---|---|
| Azure deployment succeeded, but execution is disabled | Installer receipts and retained readiness gates; provisioning success is not activation |
| Browser sign-in loops or fails | Exact Web callback URI, tenant, ID-token configuration and enterprise-app assignment |
| Signed in but product returns 403 | Product role/group assignment; do not grant subscription Owner to solve UI authorization |
| Managed-identity or blueprint exchange fails | Correct attached UAMI selection and Blueprint FIC issuer/subject/audience |
| `AADSTS65001` | Requested resource audience and its effective delegated consent/inheritance; successful FIC authentication does not grant resource access |
| MCP works but no Cloud PC is available | Windows 365 billing, agent assignment, pool provisioning and free session capacity |
| Browser opens sign-in or access denied | Agent User access, SSO, Conditional Access and target-application permissions |
| Screen sharing fails while automation works | Separate ARI consent and the SDK environment matching the returned remoting service |
| Model throttling | Model deployment, regional quota and shared capacity; additional Cloud PCs do not increase model quota |
| Interrupted cleanup or uncertain commit | Reconcile the session/lease or target record before retrying |

For package 1.9.14, activation **does not request a Dataverse API token or verify
CRM privileges**. It still checks real MCP identity, model/data access, browser
access, session cleanup and telemetry. A runtime operation that uses Dataverse
APIs may still require separate API consent and CRM security roles.

Never attach access tokens, passwords, complete configuration dumps, recordings
or customer datasets to public issues. Share sanitized error codes, installation
version, run/probe ID, time window and approved correlation identifiers.

## Costs and security boundaries

Azure hosting, networking, data services, models, telemetry and Windows 365 usage
can incur charges, including during readiness checks and when no business run
is active. Review retention and cost controls before onboarding production data.

Human sign-in, product authorization, Azure RBAC, Blueprint federation,
delegated tool permissions and target-application permissions are separate
controls. Passing one does not satisfy the others.

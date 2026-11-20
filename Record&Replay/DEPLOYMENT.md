# Deployment and acceptance

[Back to Record & Replay](README.md) |
[Identity prerequisites](IDENTITY-SETUP.md)

This is a customer installation checklist for the **MCP-browser
activation profile**, not a source-build or Marketplace publishing guide.
Obtain the approved offer/version and any release verification utilities
from the offering owner.

## 1. Azure prerequisites

- An approved Azure subscription, deployment region and resource group strategy.
- Permission to create the offering's resources and scoped role assignments.
  Verify managed-application restrictions and Azure Policy compatibility with
  the deployment owner.
- Permission to attach the supplied UAMI, such as Managed Identity Operator at
  that identity's scope.
- Availability and quota for the selected Foundry models and hosting services.
  Model quota is separate from Windows 365 session capacity.
- A nonoverlapping private IPv4 `/16` for the offering's new VNet.
- Approval for the offering's endpoint exposure, outbound connectivity, data
  retention and operating costs.
- Completed [identity, consent and Windows 365 setup](IDENTITY-SETUP.md).

The current deployment uses separate delegated subnets for Container Apps and
the optional Functions executor, with shared NAT egress. UI/API HTTPS and
authenticated Functions endpoints remain publicly reachable. This profile
does not add private endpoints, a firewall, VPN or network peering.

Customers requiring a different isolation topology should obtain an approved
deployment design rather than assuming this offer creates it.

### Installation identities and Azure permissions

Keep the following identities separate. Azure RBAC does not replace the
Blueprint federation, MCP consent or Windows 365 prerequisites in
[identity setup](IDENTITY-SETUP.md).

| Identity | Installation responsibility | Required preparation |
|---|---|---|
| Installing human or deployment account | Creates the Managed Application and selects existing identities | Approved resource-deployment and role-assignment permissions at the installation scopes; **Managed Identity Operator** on each supplied UAMI to attach it |
| Shared runtime/activation UAMI | Runs UI/API, the Functions executor and the readiness-gated activation installer | Create it before installation and configure its Blueprint FIC; supply its full resource ID in **Existing shared runtime and activation managed identity resource ID** |
| Dedicated existing-Foundry deployment UAMI | Authorizes linked-resource deployments and scoped grants outside the managed resource group | Required only when reusing Foundry with a package exposing **Existing Foundry deployment managed identity resource ID**; pre-authorize it as described below |
| Managed Applications On Behalf Application | Azure platform service principal performing Managed Application deployment operations | Ensure effective permission to read and attach supplied external UAMIs; see the separate on-behalf-of guidance below |
| Generated `video-copy-*` and `image-push-*` UAMIs | Agent/package installation and application-image installation | Created and granted scoped access by the offering; do not enter these generated identities in the customer UAMI fields |

Use the full UAMI Azure resource ID, not its client ID or principal/object ID:

```text
/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<identity-name>
```

The shared runtime UAMI is required for both new and existing Foundry, even
when automatic activation is disabled. The dedicated Foundry deployment UAMI
is a different security boundary; do not give the runtime UAMI broad deployment
or RBAC-administration privileges.

#### Shared runtime/activation UAMI

The offering creates scoped Azure assignments for the shared identity during
installation. These include runtime access to Storage, Cosmos DB, ACR, Foundry
and telemetry, plus the following assignments when activation is selected:

| Role | Scope / purpose |
|---|---|
| Container Apps Contributor | Deployed UI/API Container App, for activation configuration |
| Website Contributor | Deployed executor Function App, for activation configuration |
| Log Analytics Reader | Installation Log Analytics workspace, for ingestion verification |
| Foundry User (`53ca6127-db72-4b80-b1b0-d745d6d5456d`) | Selected Foundry project, for readiness probes |
| Storage Blob Data Contributor | Installation receipt container |
| Reader | Installer container groups whose completion must be verified |

These are installer-created scoped grants, not a request to assign Contributor
or Owner to the runtime identity across the subscription. Its privileges are
shared by runtime and activation because they use the same UAMI. The runtime
UAMI needs no Microsoft Graph provisioning permissions or Blueprint ownership
for this activation profile; an authorized identity administrator configures
the Blueprint FIC separately before activation.

#### Dedicated deployment UAMI when reusing Foundry

When reusing Foundry, supply a separate, pre-authorized UAMI in
**Existing Foundry deployment managed identity resource ID**.

Before installation, an Azure administrator must grant the dedicated UAMI:

| Role / permission | Scope |
|---|---|
| Contributor, or a narrower approved role permitting `Microsoft.Resources/deployments/*`, resource-group read and the necessary Foundry reads | **Existing Foundry resource group**, not merely the identity's resource group |
| Role Based Access Control Administrator, preferably with approved delegation conditions | **Existing Foundry account**; child-project grants inherit this scope |
| Managed Identity Operator, if this identity is the effective deployment caller attaching the separately supplied runtime UAMI | The **shared runtime UAMI resource**, when not already covered by approved access |

Contributor alone cannot create role assignments. Delegation must permit the
template to assign Cognitive Services User
(`a97b65f3-24c7-4388-baec-2e87135dc908`) to the generated agent installer and
shared runtime UAMI; assign the installer a constrained Role Based Access
Control Administrator role
(`f58310d9-a9f6-439a-9e8d-f62e7b41a168`); and, when activation is enabled,
assign Foundry User to the runtime UAMI at the project.

The installer's constrained delegation permits only Cognitive Services User
role-assignment creation and prohibits deletion. Permission to assign the
RBAC Administrator role is itself privileged: have the security owner constrain
allowed roles and recipient principals where practical, rather than granting
subscription-wide Owner or unrestricted delegation.

The package attaches the dedicated UAMI to the Managed Application through
the special `managedIdentity` form output. It does not create that UAMI or
grant its prerequisite permissions. Confirm effective assignments and any
required PIM activation before installation.

#### Managed Applications On Behalf Application

This is the Azure platform enterprise application, **not** the runtime UAMI,
Agent Identity Blueprint, Agent Identity or human UI sign-in application.
Identify the caller from the actual authorization error and verify its service
principal in the installation tenant before assigning any roles. The previously
observed application/client ID was
`35cbcc06-defd-44d2-ace4-bc2bf2466970`; its service-principal object ID is
tenant-specific and must not be copied from another installation.

For externally supplied identities, an administrator should verify the
following narrowly scoped access for the effective on-behalf-of caller:

| Permission | Recommended built-in role and scope |
|---|---|
| Read an existing UAMI and attach it to a deployed resource (`Microsoft.ManagedIdentity/userAssignedIdentities/read` and `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action`) | **Managed Identity Operator** on the exact shared runtime UAMI and, when selected, the dedicated Foundry deployment UAMI |
| Create resources and scoped role assignments inside the managed resource group | Provided through the approved Managed Application deployment authorization; verify the offer configuration rather than manually granting subscription-wide Owner |

Granting the installing user Managed Identity Operator does not grant that
permission to the platform service principal. Likewise, a role granted to a
UAMI controls what that UAMI can do; it does not authorize another principal
to attach it. Use the caller object ID and scope in an `AuthorizationFailed`
error to distinguish these cases.

If the on-behalf-of caller lacks `Microsoft.Resources/deployments/write` in
the **existing Foundry resource group**, first verify that the approved preview
package includes linked-resource identity support, the selected dedicated UAMI
is attached to the Managed Application, and its Contributor/custom-role and
RBAC delegation assignments are effective. Do not routinely grant the shared
platform principal Contributor, Owner or RBAC Administrator over the
subscription or existing Foundry resource group as a workaround. Escalate
unexpected caller/scope behavior to the deployment owner.

References:
[Managed Identity Operator permissions](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/identity#managed-identity-operator),
[Managed Applications linked-resource identity](https://learn.microsoft.com/azure/azure-resource-manager/managed-applications/publish-managed-identity#linking-existing-azure-resources),
and [constrained RBAC delegation](https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-overview).

### Optional permission setup script

Download [Set-InstallationPermissions.ps1](Set-InstallationPermissions.ps1)
and review it with your Azure administrator. It requires PowerShell 7, Azure
CLI and `az login` to the intended customer tenant. Run it as a principal
authorized to read the resources and create the requested scoped assignments.
Any required PIM privileges must already be active.

The script does not create managed identities, deploy the application, configure
Blueprint federation, change Graph consent or grant runtime data-plane roles.
It previews by default. It checks existing/inherited assignments for the same
principal and role, skips matching grants, and refuses conflicting conditions.
It does not evaluate all effective permissions or remove broader existing
access. It does not change the active Azure CLI subscription.

For **new Foundry**, preview identity-attachment permissions:

```powershell
$permissions = @{
    SubscriptionId = '<installation-subscription-id>'
    RuntimeIdentityResourceId = '/subscriptions/<subscription-id>/resourceGroups/<identity-rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<runtime-mi>'
    OnBehalfPrincipalObjectId = '<verified-platform-service-principal-object-id>'
}
.\Set-InstallationPermissions.ps1 @permissions
```

For interactive Azure CLI login, the installer defaults to the signed-in user.
The script uses `az ad signed-in-user show` to read that user's tenant-local
object ID and prints the selected principal, type and source before applying
permissions. This is a read-only Microsoft Graph lookup; it does not change
directory permissions or consent. The active CLI user and tenant must match
the installation subscription login. A context mismatch or lookup failure
stops the script rather than guessing an identity.

If the permissions administrator is not the person who will install the offer,
override the installer explicitly:

```powershell
$permissions.InstallerPrincipalObjectId = '<actual-installer-object-id>'
$permissions.InstallerPrincipalType = 'User'
```

For service-principal or managed-identity Azure CLI login, both installer
parameters must be supplied explicitly. Use `ServicePrincipal` for an automation
installer or `Group` for an approved installer group. Explicit overrides skip
the signed-in-user lookup.

Supply tenant-local **object IDs**, not application/client IDs, for installer
overrides and `OnBehalfPrincipalObjectId`. Verify the on-behalf-of enterprise
application with the identity administrator; the script does not discover that
principal through Graph.

For **existing Foundry**, additionally supply the separate deployment UAMI,
account resource ID and a local UTF-8 text file containing the security owner's
approved Azure RBAC delegation condition expression:

```powershell
$permissions.DeploymentIdentityResourceId = '/subscriptions/<subscription-id>/resourceGroups/<identity-rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<deployment-mi>'
$permissions.FoundryAccountResourceId = '/subscriptions/<installation-subscription-id>/resourceGroups/<foundry-rg>/providers/Microsoft.CognitiveServices/accounts/<account-name>'
$permissions.DelegationConditionFile = '.\approved-foundry-delegation-condition.txt'
.\Set-InstallationPermissions.ps1 @permissions
```

The Foundry account must be in the installation subscription. The condition
must authorize the grants described above without opening unintended role
delegation. The script requires a nonempty condition and uses condition version
`2.0`; it cannot certify that an expression is safe or sufficient. In particular,
permitting RBAC Administrator delegation without appropriate recipient controls
can enable privilege escalation. Azure validates the expression when applied.
Do not substitute a generic "allow all" expression merely to pass this check.

Review the preview's principal IDs, exact scopes and condition, then apply:

```powershell
.\Set-InstallationPermissions.ps1 @permissions -Apply -Confirm
```

Existing Foundry adds Contributor on its resource group, condition-restricted
RBAC Administrator on its account, and Managed Identity Operator for the
deployment identity on the runtime UAMI. Both installer and platform caller
receive Managed Identity Operator only on the supplied identity resources.
There is no subscription-wide Owner or platform-principal Foundry Contributor
grant.

The script prints each assignment's role, principal and scope, with
`CREATED`, `ALREADY PRESENT - skipped`, or `NOT APPLIED`. Matching existing
assignments are successful and are never recreated. The final summary shows
the number created, already present and still missing. For example, a rerun
after all required grants exist prints:

```text
PASS: All 7 required role assignments match. Created: 0; already present: 7.
```

`PREVIEW ONLY` means no changes were made and missing permissions still need
to be applied. `INCOMPLETE` means some assignments were declined. CLI errors
and conflicting delegation conditions stop the script with an error; an
existing assignment with different conditions requires administrator review,
not automatic replacement.

Azure role assignments are not transactional. A failed later create does not
roll back earlier assignments; the script reports errors and can be rerun to
skip matching grants. Allow RBAC propagation before installing. Successful
assignment creation is not proof of effective authorization, working federation
or completed application installation.

## 2. Prepare deployment inputs

Use the form tooltips and an approved customer handover worksheet.
Never put tokens or credentials into these fields.

| Input | What to provide |
|---|---|
| Existing shared UAMI resource ID | Customer-owned identity for API, executor and installer |
| Existing Foundry deployment UAMI resource ID | Separate pre-authorized linked-resource identity; required only when reusing Foundry |
| Blueprint client ID | Existing verified Agent Identity Blueprint |
| Agent Identity ID | Enabled instance linked to that Blueprint |
| Agent User object ID | Linked Agent User's actual object ID |
| Agent User UPN | UPN verified to identify that same Agent User |
| UI application client ID | Separate single-tenant Easy Auth application |
| Initial administrator object ID | Intended human product Administrator |
| Dataverse URL | Exact HTTPS origin for the intended production/UAT organization |
| Additional approved targets | Optional exact hostnames; Dataverse hostname is included automatically |
| Application VNet prefix | Approved nonoverlapping private `/16` |
| Install CUA executor | Required for this profile's local Durable Functions execution |
| Automatic CUA activation | Select when prerequisites are ready; retained checks must pass before enablement |
| Optional screen-sharing environment | Disabled, Production or PPE, matching the remoting service |
| Foundry/model settings | Supported deployments and approved capacity for this installation |

Tenant, runtime UAMI client/principal IDs, MCP endpoint and supported tools
resource are derived by the offering. The current form does not ask for a
Blueprint Principal object ID or a CRM privilege list.

## 3. Deploy the approved offering

1. Select the approved offer/version and deployment region.
2. Review resource topology, access and cost implications.
3. Enter the verified customer inputs.
4. Select executor installation and readiness-gated activation when appropriate.
5. Submit and monitor the deployment and installer results.
6. Retain the application URL, callback URL, installation/probe identifiers and
   verification outputs in an approved customer location.
7. Register the callback and test human sign-in as described in
   [identity setup](IDENTITY-SETUP.md#8-prepare-human-ui-sign-in).

For a managed application plan, have the publisher confirm **Incremental**
deployment mode in its Technical configuration. Nested template modes do not
override an outer Complete-mode deployment. Complete-mode cleanup can conflict
with Azure Policy-created resources; do not detach policy-created network
controls just to make cleanup finish.

## 4. Understand automatic activation

Resources and guards begin with execution/new-run admission disabled.
Automatic activation is not an unconditional enable switch.

The installer must verify:

1. Installed runtime payloads and the API's actual MCP identity exchange.
2. The executor's independent identity exchange.
3. Model acknowledgement and required data-plane access.
4. Real Windows 365 session acquisition and browser access to the configured
   target.
5. Confirmed session release and durable cleanup.
6. Logs, traces and metrics ingested from API, executor, video and Compliance
   hosts.
7. The exact approved execution/cleanup Function allowlist and loaded executor
   configuration before API new-run admission opens.

The deployment-time Dataverse API-token/CRM privilege checks are not performed.
Profiled receipts explicitly report:

```json
{
  "readinessProfile": "McpBrowser",
  "dataverseApiPreflightPerformed": false,
  "crmPrivilegesVerified": false
}
```

These are illustrative profile fields, **not a complete activation receipt**.
The two `false` values mean "not checked"; they do not prove access or constitute
a failure of a CRM check. Retained positive proofs must still be present.
Do not fabricate or edit receipts to force acceptance.

An activation failure is intended to restore disabled guards. Unverified
rollback or ambiguous session cleanup requires administrator investigation
and reconciliation before retrying. Do not enable every Function manually.

Readiness can incur model, Cloud PC and telemetry charges. It does not submit
a business dataset or prove every approved process will succeed.

## 5. Acceptance checklist

- [ ] Confirm the installed package version and intended target organization.
- [ ] Identity administrator verifies Blueprint, Principal, Agent Identity and
  Agent User linkage.
- [ ] Shared UAMI is attached and selected correctly by both runtime hosts.
- [ ] Blueprint FIC has the correct tenant issuer, UAMI principal-ID subject and
  token-exchange audience.
- [ ] MCP consent/inheritance and Windows 365 assignment are effective.
- [ ] Image and hosted-planner installation completed successfully.
- [ ] Real retained activation checks pass and a matching receipt is available.
- [ ] Use the approved external verifier and require `InstallationVerified`
  before accepting the installation.
- [ ] Human sign-in and explicit product authorization both work.
- [ ] Optional screen sharing is tested separately if enabled.
- [ ] Process owner reviews the recording-derived instructions, data mappings
  and generated blueprint.
- [ ] A small approved end-to-end business run is checked in the target system.
- [ ] Session cleanup, monitoring, retention, support ownership and cost controls
  are accepted.

**Azure deployment Succeeded is not InstallationVerified.** A healthy UI,
coordinator, visible desktop or individual token exchange is not an end-to-end
acceptance result.

If automatic activation was not selected, keep business execution disabled
until an approved setup/activation procedure establishes the required proofs.

## 6. Operational handover

Record these without embedding secrets or customer data:

- Installed offer version and installation time.
- Application URL, environment and approved target hostnames.
- Owners for Azure resources, Entra/Agent ID, Windows 365 and the business process.
- Approved identity worksheet and permission evidence in a restricted location.
- Pool/capacity references, model capacity and retention/cost ownership.
- Activation/installation verification results and any unresolved limitations.
- Support procedure for failed rows, uncertain commits, interrupted sessions
  and safe cancellation.

Return to [Using Record & Replay](README.md#using-record--replay) for the operator
workflow.

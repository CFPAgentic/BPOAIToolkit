# Identity and Windows 365 prerequisites

[Back to Record & Replay](README.md)

Applies to the **1.9.14 shared customer-managed identity / MCP-browser activation
profile**. Perform setup using customer-owned identities and tenant-approved
administrative workflows. Do not copy IDs or configuration from another tenant
or installation.

## 1. Understand the identities

| Identity | Purpose | Prepared by |
|---|---|---|
| UI/API Entra application registration | Human sign-in through platform Easy Auth | Customer Entra administrator |
| Initial product Administrator | Human user authorized inside the product | Customer application owner |
| User-assigned managed identity (UAMI) | Azure identity shared by UI/API, executor and activation installer | Customer Azure administrator |
| Agent Identity Blueprint application | Parent application holding runtime federation trust | Customer Agent ID administrator |
| Blueprint Principal | Blueprint's service principal in the customer tenant | Customer Agent ID administrator |
| Agent Identity | Agent instance linked to the Blueprint | Customer Agent ID administrator |
| Agent User | User identity linked to the Agent Identity for supported delegated access | Customer Agent ID administrator |

The UI sign-in application is separate from the Agent Identity Blueprint.
The human operator is not the Agent User.

```text
Customer UAMI attached to API + executor + activation installer
    |
    | Federated Identity Credential on the Blueprint application
    v
Agent Identity Blueprint --> Blueprint Principal
    |
    v
Agent Identity
    |
    v
Linked Agent User --> approved MCP tools --> Windows 365 agent pool
```

## 2. Prepare the Agent ID objects

Use the supported [Agent 365 registration workflow](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/registration)
and current tenant onboarding requirements.

1. Create the Agent Identity Blueprint with required sponsors and governance.
2. Verify its identifier URI includes `api://<blueprint-client-id>`.
3. Explicitly create and enable its Blueprint Principal. Creating the Blueprint
   application alone is not sufficient.
4. Create and enable an Agent Identity under that Blueprint.
5. Create and enable the linked Agent User.
6. Verify the Agent Identity's `agentIdentityBlueprintId` matches the Blueprint
   client ID and the Agent User's `identityParentId` matches the Agent Identity.
7. Record the verified Agent User object ID and UPN; confirm they refer to the
   same linked user.

An ordinary app registration or human account is not a substitute for these
typed Agent ID objects. The installer does not discover or create the directory
relationships for you.

Use an explicitly scoped, authorized Graph administrator session or approved
provisioning application. Do not assume a generic Azure CLI Graph token can call
typed Agent ID APIs.

## 3. Prepare the shared UAMI and Blueprint federation

Create or select an existing customer-owned user-assigned managed identity.
The offering attaches the same UAMI to the API, optional executor and activation
installer. Its Azure privileges are shared; this is not a separate installer
security boundary.

An authorized administrator must create or verify this FIC **on the Blueprint
application**, before automatic activation:

| Property | Required value |
|---|---|
| Issuer | `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| Subject | Shared UAMI **principal/object ID** |
| Audience | `api://AzureADTokenExchange` |
| Location | Blueprint application credentials |

Important distinctions:

- The FIC subject is **not the UAMI client ID**.
- The FIC is not created on the Agent Identity or on the UAMI resource.
- Agent Identities do not hold their own client secrets/certificates.
- Do not overwrite or delete unrelated Blueprint credentials.
- If using an offering-provided FIC setup helper, obtain the approved helper
  from the release owner. This documentation repository does not bundle it.

The 1.9.14 activation installer performs no Graph reads/writes. The runtime
UAMI does not need directory provisioning permissions or Blueprint ownership
merely to activate CUA. Administrative credential setup is a separate operation.

### Identifier worksheet

Keep actual values in an approved customer handover, not in this repository.

| Identifier | Correct meaning |
|---|---|
| Tenant ID | Customer Entra tenant |
| UAMI Azure resource ID | Full resource ID used by the deployment |
| UAMI client ID | Selects the attached managed identity at runtime |
| UAMI principal ID | Object ID used as the FIC subject |
| Blueprint client ID | Blueprint application `appId` |
| Blueprint application object ID | Application `id`, used for administrator credential operations |
| Blueprint Principal object ID | Blueprint service principal `id` |
| Agent Identity ID | Linked Agent Identity identifier accepted by this offering |
| Agent User object ID | Linked user object `id`, not Agent Identity ID |
| Agent User UPN | Verified `userPrincipalName` of that same user |

The Blueprint application object ID and Blueprint Principal object ID are useful
for administrator verification; they are not current Marketplace form inputs.

## 4. Approve MCP tool access

Federation authenticates the runtime; it does not grant resource permissions.

1. Register/enable `mcp_W365ComputerUse` using supported Agent 365 tooling setup.
2. Approve the required tool permissions and consent for the integration.
3. Verify the supported Blueprint-to-agent permission inheritance/instance
   authorization path.
4. Confirm the intended Agent Identity / Agent User can initialize MCP, list
   permitted tools and invoke approved lifecycle/browser tools.

The offering's supported shared Agent Tools resource application ID is:

```text
ea9ffc3e-8a23-4a7d-836d-234d7c7565c1
```

The tenant-specific MCP endpoint has this shape:

```text
https://agent365.svc.cloud.microsoft/agents/tenants/<tenant-id>/servers/mcp_W365ComputerUse
```

Discovery permission is not invocation permission. Resource application IDs
are not tenant-local resource service principal object IDs. Review the
[Agent 365 tooling guidance](https://learn.microsoft.com/en-us/microsoft-agent-365/developer/tooling)
and the supported integration's permission setup; do not add arbitrary grants
or use the screen-sharing resource as the MCP audience.

Azure RBAC assignments on the UAMI do not replace delegated tool consent.
An `AADSTS65001` after successful federation should be investigated at the
requested resource's consent/scope path, not assumed to be a missing FIC.

### Runtime flow

```text
Attached UAMI
  -> managed-identity assertion for AzureADTokenExchange
  -> Blueprint token selecting the Agent Identity with fmi_path
  -> Agent Identity token
  -> user_fic exchange for the Agent User and requested resource
  -> resource-specific delegated Agent User token
```

The application selects the configured UAMI client ID. The API and executor
must prove their exchanges independently. A working API exchange does not
prove the executor has the correct identity attached.

MCP uses the configured Agent User UPN; screen sharing uses the Agent User
object ID. Supply both correctly. Neither should be replaced with the
Agent Identity ID.

Do not persist tokens in application settings, scripts, screenshots or tickets.

## 5. Provision Windows 365 for Agents

Confirm current licensing, tenant availability, preview/onboarding requirements
and supported regions with your Microsoft administrator. The offering does not
establish Windows 365 entitlements or a billing policy.

1. Complete Windows 365 for Agents billing and tenant onboarding.
2. Create the agent provisioning policy/pool using the supported Intune workflow.
3. Assign the intended registered agent through that workflow.
4. Confirm that the assignment resolves to the same linked Agent User supplied
   to this offering, not only to a human tester.
5. Provision sufficient free session capacity in the intended geography.
6. Prepare the image, browser, applications, device policies and target-network
   access required by the process.
7. Configure SSO and target-application access for the Agent User.
8. Verify actual session checkout, readiness, permitted browser navigation and
   release.

Useful Microsoft references:

- [Windows 365 for Agents](https://learn.microsoft.com/en-us/windows-365/agents/)
- [Provisioning policy / pool setup](https://learn.microsoft.com/en-us/windows-365/agents/create-provisioning-policy-agents)
- [Billing setup](https://learn.microsoft.com/en-us/windows-365/agents/billing-w365a)
- [Agent authentication model](https://learn.microsoft.com/en-us/windows-365/agents/agent-authentication-model)

Do not disable tenant-wide MFA, Conditional Access or device controls to make
a probe succeed. Have the security owner approve a supported agent access model.

## 6. Optional screen sharing

Screen sharing is a separate resource/consent path:

| Item | Value |
|---|---|
| Resource | Windows 365 Agents Runtime Interface (ARI) |
| Resource application ID | `90ecec28-f5a6-42b3-9bde-dae1ca98f8b5` |
| View permission | `Computer.See` |
| Optional takeover permission | `Computer.Control`, only if approved |

Follow the [Windows 365 integration guidance](https://github.com/microsoft/windows-365-for-agents/blob/main/docs/getting-started.md)
for resource declarations, consent and inherited permissions. Do not blindly
duplicate grants on agent instances when the supported path uses inheritance.

Select `Disabled`, `Production` or `PPE` in the deployment. Match the environment
of the **returned remoting service**, not merely the MCP gateway hostname.
Enabling the viewer setting does not grant consent or authorize human takeover.

## 7. Dataverse and target-application access

Supply the real target Dataverse HTTPS origin. Production and UAT are distinct
organizations even when their names are similar.

For 1.9.14:

- Activation verifies browser navigation/access to the configured target.
- It does not request a Dataverse API token, call `WhoAmI`, read CRM privilege
  metadata or collect a required CRM privilege list.
- Successful activation does not claim CRM API consent or roles were verified.
- The Agent User still needs SSO, licensing and application permissions required
  by the approved workload.
- A workload that calls Dataverse APIs may separately require Dynamics CRM
  delegated authorization, such as the supported `user_impersonation` path,
  and the correct CRM security roles.

API consent does not assign CRM roles; CRM roles do not grant API consent.
An approved hostname does not grant either.

## 8. Prepare human UI sign-in

1. Supply a separate, existing single-tenant Entra application client ID.
2. Supply the intended initial human product Administrator's Entra object ID.
3. After deployment, register the exact generated `authenticationCallbackUrl`
   as a **Web** redirect URI on that application.
4. For this release's secretless Easy Auth profile, enable **ID tokens** under
   implicit grant/hybrid flow settings. No client secret or implicit access-token
   setting is required by this profile.
5. Apply enterprise-application assignment if tenant policy requires it.
6. Test sign-in and product authorization separately.

This release uses an ID-token implicit flow tradeoff. Microsoft recommends
avoiding implicit flow where more secure alternatives are viable; confirm
acceptability with your tenant security owner. Do not work around a tenant policy
by weakening it without approval.

See [Container Apps Entra authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication-entra#enable-microsoft-entra-id-in-your-container-app).

## Ready for deployment

Proceed to [Deployment and acceptance](DEPLOYMENT.md) after the customer identity,
Windows 365 and application owners have signed off these prerequisites.

# Deployment and acceptance

[Back to Record & Replay](README.md) |
[Identity prerequisites](IDENTITY-SETUP.md)

This is a customer installation checklist for the **1.9.14 MCP-browser
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

## 2. Prepare deployment inputs

Use the form tooltips and an approved customer handover worksheet.
Never put tokens or credentials into these fields.

| Input | What to provide |
|---|---|
| Existing shared UAMI resource ID | Customer-owned identity for API, executor and installer |
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

For 1.9.14, the installer must verify:

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

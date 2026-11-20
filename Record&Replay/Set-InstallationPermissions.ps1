#Requires -Version 7.0
<#
.SYNOPSIS
Previews or creates scoped Azure RBAC prerequisites for Record & Replay.
.DESCRIPTION
Requires Azure CLI login and existing identities. Does not create identities,
change Graph permissions, configure Blueprint federation or deploy resources.
Existing Foundry uses account-scoped RBAC Administrator without a condition.
Creating that privileged assignment requires explicit administrator opt-in.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [guid]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$RuntimeIdentityResourceId,

    [guid]$InstallerPrincipalObjectId,

    [ValidateSet('User', 'Group', 'ServicePrincipal')]
    [string]$InstallerPrincipalType = 'User',

    [Parameter(Mandatory)]
    [guid]$OnBehalfPrincipalObjectId,

    [string]$DeploymentIdentityResourceId,
    [string]$FoundryAccountResourceId,
    [switch]$AllowUnrestrictedFoundryRbac,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$null = Get-Command az -ErrorAction Stop

function Invoke-AzJson {
    param([string[]]$Arguments)
    $result = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments[0..1] -join ' '). See the CLI error above."
    }
    if ([string]::IsNullOrWhiteSpace(($result -join "`n"))) {
        throw 'Azure CLI returned no JSON response.'
    }
    return ($result -join "`n") | ConvertFrom-Json
}

function Get-ResourceSubscription {
    param([string]$ResourceId)
    return $ResourceId.Split('/')[2]
}

function Get-Identity {
    param([string]$ResourceId)
    if ($ResourceId -notmatch '^/subscriptions/[0-9a-f-]{36}/resourceGroups/[^/]+/providers/Microsoft\.ManagedIdentity/userAssignedIdentities/[^/]+$') {
        throw "Expected a full user-assigned managed identity resource ID: $ResourceId"
    }
    $identity = Invoke-AzJson -Arguments @(
        'identity', 'show', '--ids', $ResourceId,
        '--subscription', (Get-ResourceSubscription $ResourceId)
    )
    if ([string]::IsNullOrWhiteSpace($identity.principalId) -or $identity.tenantId -ne $account.tenantId) {
        throw 'The identity must have a principal ID and belong to the selected subscription tenant.'
    }
    return $identity
}

function New-Grant {
    param(
        [string]$PrincipalId, [string]$PrincipalType, [string]$Role,
        [string]$RoleId, [string]$Scope
    )
    [pscustomobject]@{
        PrincipalId = $PrincipalId
        PrincipalType = $PrincipalType
        Role = $Role
        RoleId = $RoleId
        Scope = $Scope
        Condition = ''
        Existing = $false
    }
}

$RuntimeIdentityResourceId = $RuntimeIdentityResourceId.Trim().TrimEnd('/')
$hasFoundryInputs = -not [string]::IsNullOrWhiteSpace($DeploymentIdentityResourceId) -or
    -not [string]::IsNullOrWhiteSpace($FoundryAccountResourceId)
if ($hasFoundryInputs -and (
    [string]::IsNullOrWhiteSpace($DeploymentIdentityResourceId) -or
    [string]::IsNullOrWhiteSpace($FoundryAccountResourceId))) {
    throw 'Existing Foundry requires DeploymentIdentityResourceId and FoundryAccountResourceId together.'
}
if ($OnBehalfPrincipalObjectId -eq [guid]::Empty -or
    ($PSBoundParameters.ContainsKey('InstallerPrincipalObjectId') -and $InstallerPrincipalObjectId -eq [guid]::Empty)) {
    throw 'Principal object IDs must not be empty GUIDs.'
}
if (-not $PSBoundParameters.ContainsKey('InstallerPrincipalObjectId') -and $InstallerPrincipalType -ne 'User') {
    throw 'InstallerPrincipalObjectId is required when InstallerPrincipalType is not User.'
}

if ($hasFoundryInputs) {
    $DeploymentIdentityResourceId = $DeploymentIdentityResourceId.Trim().TrimEnd('/')
    $FoundryAccountResourceId = $FoundryAccountResourceId.Trim().TrimEnd('/')
    if ($RuntimeIdentityResourceId -eq $DeploymentIdentityResourceId) {
        throw 'Use separate runtime and Foundry deployment identities.'
    }
    if ($FoundryAccountResourceId -notmatch "^/subscriptions/$SubscriptionId/resourceGroups/[^/]+/providers/Microsoft\.CognitiveServices/accounts/[^/]+$") {
        throw 'FoundryAccountResourceId must identify an account in the installation subscription.'
    }
    Write-Warning "Existing Foundry uses RBAC Administrator WITHOUT a delegation condition at $FoundryAccountResourceId. This permits unrestricted role-assignment management at that account and its children. Obtain security approval before applying."
}

$account = Invoke-AzJson -Arguments @('account', 'show', '--subscription', "$SubscriptionId")
if ($account.state -ne 'Enabled') { throw 'The selected subscription is not enabled.' }
if ($account.user.type -ne 'user' -and (
    -not $PSBoundParameters.ContainsKey('InstallerPrincipalObjectId') -or
    -not $PSBoundParameters.ContainsKey('InstallerPrincipalType'))) {
    throw 'Non-user Azure CLI login: supply InstallerPrincipalObjectId and InstallerPrincipalType explicitly for the intended installer.'
}
$installerSource = 'explicit override'
if (-not $PSBoundParameters.ContainsKey('InstallerPrincipalObjectId')) {
    $activeAccount = Invoke-AzJson -Arguments @('account', 'show')
    if ($activeAccount.tenantId -ne $account.tenantId -or
        $activeAccount.user.type -ne 'user' -or
        $activeAccount.user.name -ne $account.user.name) {
        throw 'The active Azure CLI user/tenant does not match the installation subscription login. Select the intended CLI context or supply InstallerPrincipalObjectId explicitly.'
    }
    $signedInUser = Invoke-AzJson -Arguments @('ad', 'signed-in-user', 'show')
    $resolvedObjectId = [guid]::Empty
    if (-not [guid]::TryParse("$($signedInUser.id)", [ref]$resolvedObjectId) -or $resolvedObjectId -eq [guid]::Empty) {
        throw 'Azure CLI did not return a valid signed-in user object ID. Supply InstallerPrincipalObjectId explicitly.'
    }
    $InstallerPrincipalObjectId = $resolvedObjectId
    $installerSource = 'signed-in Azure CLI user'
}
Write-Information "Installer: $InstallerPrincipalObjectId | Type: $InstallerPrincipalType | Source: $installerSource" -InformationAction Continue
$runtime = Get-Identity $RuntimeIdentityResourceId
$identities = @($runtime)
$deployment = $null
if ($hasFoundryInputs) {
    $deployment = Get-Identity $DeploymentIdentityResourceId
    if ($runtime.principalId -eq $deployment.principalId) {
        throw 'Use separate runtime and Foundry deployment principals.'
    }
    $null = Invoke-AzJson -Arguments @(
        'resource', 'show', '--ids', $FoundryAccountResourceId,
        '--api-version', '2025-06-01', '--subscription', "$SubscriptionId"
    )
    $identities += $deployment
}
foreach ($identity in $identities) {
    if ("$InstallerPrincipalObjectId" -eq $identity.principalId -or
        "$OnBehalfPrincipalObjectId" -eq $identity.principalId) {
        throw 'Installer and on-behalf-of principals must be separate from the supplied UAMIs.'
    }
}
if ($InstallerPrincipalObjectId -eq $OnBehalfPrincipalObjectId) {
    throw 'Installer and on-behalf-of principals must be distinct.'
}

$operatorRole = 'f1a07417-d97a-45cb-824c-7a7467783830'
$grants = @(
    foreach ($identity in $identities) {
        New-Grant "$InstallerPrincipalObjectId" $InstallerPrincipalType 'Managed Identity Operator' $operatorRole $identity.id
        New-Grant "$OnBehalfPrincipalObjectId" 'ServicePrincipal' 'Managed Identity Operator' $operatorRole $identity.id
    }
)
if ($hasFoundryInputs) {
    $foundryResourceGroup = ($FoundryAccountResourceId.Split('/')[0..4] -join '/')
    $grants += New-Grant $deployment.principalId 'ServicePrincipal' 'Contributor' 'b24988ac-6180-42a0-ab88-20f7382dd24c' $foundryResourceGroup
    $grants += New-Grant $deployment.principalId 'ServicePrincipal' 'Role Based Access Control Administrator' 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' $FoundryAccountResourceId
    $grants += New-Grant $deployment.principalId 'ServicePrincipal' 'Managed Identity Operator' $operatorRole $runtime.id
}

# Preflight every assignment before creating any, so conflicts cause no writes.
foreach ($grant in $grants) {
    $assignments = @(Invoke-AzJson -Arguments @(
        'role', 'assignment', 'list', '--scope', $grant.Scope, '--include-inherited',
        '--fill-principal-name', 'false', '--fill-role-definition-name', 'false',
        '--subscription', (Get-ResourceSubscription $grant.Scope)
    ))
    $matching = @($assignments | Where-Object {
        $_.principalId -eq $grant.PrincipalId -and
        ($_.roleDefinitionId.Split('/')[-1]) -eq $grant.RoleId
    })
    foreach ($assignment in $matching) {
        if (-not [string]::IsNullOrWhiteSpace("$($assignment.condition)")) {
            throw "Existing $($grant.Role) assignment has different delegation conditions at $($assignment.scope). Review it manually; no assignments have been changed."
        }
    }
    $grant.Existing = $matching.Count -gt 0
}

$missingPrivilegedGrant = @($grants | Where-Object {
    $_.RoleId -eq 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' -and -not $_.Existing
})
if ($Apply -and -not $WhatIfPreference -and $missingPrivilegedGrant.Count -gt 0 -and
    -not $AllowUnrestrictedFoundryRbac) {
    throw 'Creating account-scoped RBAC Administrator without a condition requires -AllowUnrestrictedFoundryRbac after security approval. No assignments have been changed.'
}

Write-Information "Tenant: $($account.tenantId); installation subscription: $SubscriptionId" -InformationAction Continue
if (-not $Apply) {
    Write-Information 'PREVIEW ONLY. No assignments will be created. Review scopes, principals and privileged access before rerunning with -Apply.' -InformationAction Continue
}
else {
    Write-Warning 'Role assignments are not transactional. If a later create fails, earlier successful creates remain. Resolve the error and rerun; existing matching grants are skipped.'
}

$counts = @{ Created = 0; AlreadyPresent = 0; Planned = 0 }
foreach ($grant in $grants) {
    $status = if ($grant.Existing) { 'AlreadyPresent' } else { 'Planned' }
    if ($Apply -and -not $grant.Existing -and
        $PSCmdlet.ShouldProcess("$($grant.PrincipalId) at $($grant.Scope)", "Assign $($grant.Role)")) {
        $arguments = @(
            'role', 'assignment', 'create',
            '--assignee-object-id', $grant.PrincipalId,
            '--assignee-principal-type', $grant.PrincipalType,
            '--role', $grant.RoleId, '--scope', $grant.Scope,
            '--subscription', (Get-ResourceSubscription $grant.Scope)
        )
        $created = Invoke-AzJson -Arguments $arguments
        if ($created.principalId -ne $grant.PrincipalId -or
            $created.scope -ne $grant.Scope -or
            $created.roleDefinitionId.Split('/')[-1] -ne $grant.RoleId -or
            -not [string]::IsNullOrWhiteSpace("$($created.condition)")) {
            throw 'Azure returned an assignment that does not match the requested grant. Review the assignment before continuing.'
        }
        $status = 'Created'
    }
    $counts[$status]++
    $label = switch ($status) {
        'AlreadyPresent' { 'ALREADY PRESENT - skipped' }
        'Created' { 'CREATED' }
        'Planned' { 'NOT APPLIED' }
    }
    Write-Information "[$label] $($grant.Role) | Principal: $($grant.PrincipalId) | Scope: $($grant.Scope)" -InformationAction Continue
    [pscustomobject]@{
        Status = $status
        PrincipalId = $grant.PrincipalId
        Role = $grant.Role
        Scope = $grant.Scope
        Condition = $grant.Condition
    }
}

if ($counts.Planned -eq 0) {
    Write-Information "PASS: All $($grants.Count) required role assignments match. Created: $($counts.Created); already present: $($counts.AlreadyPresent). Existing matching permissions are not an error." -InformationAction Continue
    Write-Information 'RBAC propagation and end-to-end installation authorization still require verification.' -InformationAction Continue
}
elseif (-not $Apply -or $WhatIfPreference) {
    Write-Information "PREVIEW ONLY: Already present: $($counts.AlreadyPresent); missing: $($counts.Planned). No assignments were created by this run. Use -Apply without -WhatIf after approval." -InformationAction Continue
}
else {
    Write-Warning "INCOMPLETE: Created: $($counts.Created); already present: $($counts.AlreadyPresent); not applied: $($counts.Planned). Some assignments were declined; prerequisites are not complete."
}

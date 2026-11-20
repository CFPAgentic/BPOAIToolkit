#Requires -Version 7.0
<#
.SYNOPSIS
Previews or creates scoped Azure RBAC prerequisites for Record & Replay.
.DESCRIPTION
Requires Azure CLI login and existing identities. Does not create identities,
change Graph permissions, configure Blueprint federation or deploy resources.
For existing Foundry, provide a condition file reviewed by your security owner.
The script does not generate or certify delegation conditions.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [guid]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$RuntimeIdentityResourceId,

    [Parameter(Mandatory)]
    [guid]$InstallerPrincipalObjectId,

    [ValidateSet('User', 'Group', 'ServicePrincipal')]
    [string]$InstallerPrincipalType = 'User',

    [Parameter(Mandatory)]
    [guid]$OnBehalfPrincipalObjectId,

    [string]$DeploymentIdentityResourceId,
    [string]$FoundryAccountResourceId,
    [string]$DelegationConditionFile,
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
        [string]$RoleId, [string]$Scope, [string]$Condition = ''
    )
    [pscustomobject]@{
        PrincipalId = $PrincipalId
        PrincipalType = $PrincipalType
        Role = $Role
        RoleId = $RoleId
        Scope = $Scope
        Condition = $Condition
        Existing = $false
    }
}

$RuntimeIdentityResourceId = $RuntimeIdentityResourceId.Trim().TrimEnd('/')
$hasFoundryInputs = -not [string]::IsNullOrWhiteSpace($DeploymentIdentityResourceId) -or
    -not [string]::IsNullOrWhiteSpace($FoundryAccountResourceId) -or
    -not [string]::IsNullOrWhiteSpace($DelegationConditionFile)
if ($hasFoundryInputs -and (
    [string]::IsNullOrWhiteSpace($DeploymentIdentityResourceId) -or
    [string]::IsNullOrWhiteSpace($FoundryAccountResourceId) -or
    [string]::IsNullOrWhiteSpace($DelegationConditionFile))) {
    throw 'Existing Foundry requires DeploymentIdentityResourceId, FoundryAccountResourceId and DelegationConditionFile together.'
}
foreach ($principal in @($InstallerPrincipalObjectId, $OnBehalfPrincipalObjectId)) {
    if ($principal -eq [guid]::Empty) { throw 'Principal object IDs must not be empty GUIDs.' }
}

$condition = ''
if ($hasFoundryInputs) {
    $DeploymentIdentityResourceId = $DeploymentIdentityResourceId.Trim().TrimEnd('/')
    $FoundryAccountResourceId = $FoundryAccountResourceId.Trim().TrimEnd('/')
    if ($RuntimeIdentityResourceId -eq $DeploymentIdentityResourceId) {
        throw 'Use separate runtime and Foundry deployment identities.'
    }
    if ($FoundryAccountResourceId -notmatch "^/subscriptions/$SubscriptionId/resourceGroups/[^/]+/providers/Microsoft\.CognitiveServices/accounts/[^/]+$") {
        throw 'FoundryAccountResourceId must identify an account in the installation subscription.'
    }
    $condition = (Get-Content -LiteralPath $DelegationConditionFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($condition)) {
        throw 'The administrator-approved delegation condition file must not be empty.'
    }
}

$account = Invoke-AzJson -Arguments @('account', 'show', '--subscription', "$SubscriptionId")
if ($account.state -ne 'Enabled') { throw 'The selected subscription is not enabled.' }
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
    $grants += New-Grant $deployment.principalId 'ServicePrincipal' 'Role Based Access Control Administrator' 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' $FoundryAccountResourceId $condition
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
        if ("$($assignment.condition)".Trim() -cne $grant.Condition -or
            ($grant.Condition -and $assignment.conditionVersion -ne '2.0')) {
            throw "Existing $($grant.Role) assignment has different delegation conditions at $($assignment.scope). Review it manually; no assignments have been changed."
        }
    }
    $grant.Existing = $matching.Count -gt 0
}

Write-Information "Tenant: $($account.tenantId); installation subscription: $SubscriptionId" -InformationAction Continue
if (-not $Apply) {
    Write-Information 'PREVIEW ONLY. No assignments will be created. Review scopes, principals and the condition before rerunning with -Apply.' -InformationAction Continue
}
else {
    Write-Warning 'Role assignments are not transactional. If a later create fails, earlier successful creates remain. Resolve the error and rerun; existing matching grants are skipped.'
}

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
        if ($grant.Condition) {
            $arguments += @('--condition', $grant.Condition, '--condition-version', '2.0')
        }
        $created = Invoke-AzJson -Arguments $arguments
        if ($created.principalId -ne $grant.PrincipalId -or
            $created.scope -ne $grant.Scope -or
            $created.roleDefinitionId.Split('/')[-1] -ne $grant.RoleId -or
            "$($created.condition)".Trim() -cne $grant.Condition -or
            ($grant.Condition -and $created.conditionVersion -ne '2.0')) {
            throw 'Azure returned an assignment that does not match the requested grant. Review the assignment before continuing.'
        }
        $status = 'Created'
    }
    [pscustomobject]@{
        Status = $status
        PrincipalId = $grant.PrincipalId
        Role = $grant.Role
        Scope = $grant.Scope
        Condition = $grant.Condition
    }
}

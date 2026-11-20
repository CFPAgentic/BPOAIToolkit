#Requires -Version 7.0
param(
    [string]$ScriptPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Set-InstallationPermissions.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$subscription = '11111111-2222-3333-4444-555555555555'
$tenant = '22222222-3333-4444-5555-666666666666'
$runtimeId = "/subscriptions/$subscription/resourceGroups/identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/runtime-mi"
$deploymentId = "/subscriptions/$subscription/resourceGroups/identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/deployment-mi"
$foundryId = "/subscriptions/$subscription/resourceGroups/foundry/providers/Microsoft.CognitiveServices/accounts/customer-foundry"
$runtimePrincipal = '33333333-4444-5555-6666-777777777777'
$deploymentPrincipal = '44444444-5555-6666-7777-888888888888'
$fixture = @{
    Creates = [Collections.Generic.List[object]]::new()
    Assignments = [Collections.Generic.List[object]]::new()
    FailCreateAt = 0
    ReadFailure = $false
    LoginType = 'user'
    SignedInUserId = '77777777-8888-9999-aaaa-bbbbbbbbbbbb'
    SignedInUserReads = 0
    SignedInUserFailure = $false
    ActiveTenantId = $tenant
}
$previousExitCode = Get-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-Option {
    param([string[]]$Arguments, [string]$Name)
    $index = [Array]::IndexOf($Arguments, $Name)
    if ($index -lt 0) { return '' }
    return $Arguments[$index + 1]
}

function az {
    $arguments = @($args)
    $global:LASTEXITCODE = 0
    if ($fixture.ReadFailure) {
        $global:LASTEXITCODE = 1
        return
    }
    switch ($arguments[0..1] -join ' ') {
        'account show' {
            $accountTenant = if (Get-Option $arguments '--subscription') { $tenant } else { $fixture.ActiveTenantId }
            return @{tenantId=$accountTenant;state='Enabled';user=@{type=$fixture.LoginType;name='installer@example.invalid'}} | ConvertTo-Json
        }
        'ad signed-in-user' {
            Assert-True (-not ($arguments -contains '--subscription')) 'The directory command must not receive unsupported subscription arguments.'
            $fixture.SignedInUserReads++
            if ($fixture.SignedInUserFailure) { $global:LASTEXITCODE = 1; return }
            return @{id=$fixture.SignedInUserId} | ConvertTo-Json
        }
        'identity show' {
            $id = Get-Option $arguments '--ids'
            $principal = if ($id -eq $runtimeId) { $runtimePrincipal } else { $deploymentPrincipal }
            return @{id=$id;principalId=$principal;tenantId=$tenant} | ConvertTo-Json
        }
        'resource show' { return @{id=$foundryId} | ConvertTo-Json }
        'role assignment' {
            if ($arguments[2] -eq 'list') {
                Assert-True ((Get-Option $arguments '--fill-principal-name') -eq 'false') 'Assignment discovery must not resolve principals through Graph.'
                return ConvertTo-Json -InputObject @($fixture.Assignments.ToArray()) -Depth 5
            }
            if ($arguments[2] -ne 'create') { throw 'Unexpected role operation.' }
            $fixture.Creates.Add($arguments)
            if ($fixture.FailCreateAt -eq $fixture.Creates.Count) {
                $global:LASTEXITCODE = 1
                return
            }
            $scope = Get-Option $arguments '--scope'
            $assignment = [pscustomobject]@{
                principalId = Get-Option $arguments '--assignee-object-id'
                scope = $scope
                roleDefinitionId = "/subscriptions/$subscription/providers/Microsoft.Authorization/roleDefinitions/$(Get-Option $arguments '--role')"
            }
            $fixture.Assignments.Add($assignment)
            return $assignment | ConvertTo-Json
        }
        default { throw "Unexpected Azure CLI call: $($arguments -join ' ')" }
    }
}

$parameters = @{
    SubscriptionId = $subscription
    RuntimeIdentityResourceId = $runtimeId
    InstallerPrincipalObjectId = '55555555-6666-7777-8888-999999999999'
    OnBehalfPrincipalObjectId = '66666666-7777-8888-9999-aaaaaaaaaaaa'
}
try {
    $automaticParameters = $parameters.Clone()
    $automaticParameters.Remove('InstallerPrincipalObjectId')
    $automaticPreview = @(& $ScriptPath @automaticParameters -InformationVariable installerMessages)
    Assert-True ($automaticPreview[0].PrincipalId -eq $fixture.SignedInUserId -and $fixture.SignedInUserReads -eq 1) 'Interactive login must default to the signed-in user object ID.'
    Assert-True (($installerMessages.MessageData -join "`n") -match "Installer: $($fixture.SignedInUserId).*signed-in Azure CLI user") 'The resolved installer must be displayed before any changes.'
    $fixture.SignedInUserFailure = $true
    try { & $ScriptPath @automaticParameters; throw 'Expected signed-in-user lookup failure.' }
    catch { if ($_.Exception.Message -notlike '*Azure CLI failed*') { throw } }
    $fixture.SignedInUserFailure = $false
    $userReads = $fixture.SignedInUserReads
    $fixture.ActiveTenantId = '88888888-9999-aaaa-bbbb-cccccccccccc'
    try { & $ScriptPath @automaticParameters; throw 'Expected mismatched tenant rejection.' }
    catch { if ($_.Exception.Message -notlike '*active Azure CLI user/tenant does not match*') { throw } }
    Assert-True ($fixture.SignedInUserReads -eq $userReads) 'Mismatched tenant must be rejected before the Graph lookup.'
    $fixture.ActiveTenantId = $tenant
    $fixture.LoginType = 'servicePrincipal'
    try { & $ScriptPath @automaticParameters; throw 'Expected non-user login rejection.' }
    catch { if ($_.Exception.Message -notlike '*Non-user Azure CLI login*') { throw } }
    $explicitParameters = $parameters.Clone()
    $explicitParameters.InstallerPrincipalType = 'ServicePrincipal'
    $explicitPreview = @(& $ScriptPath @explicitParameters)
    Assert-True ($explicitPreview[0].PrincipalId -eq $parameters.InstallerPrincipalObjectId -and $fixture.SignedInUserReads -eq $userReads) 'Explicit automation installer must not require a Graph lookup.'
    Assert-True ($fixture.Creates.Count -eq 0) 'Installer resolution and failures must cause no writes in preview.'
    $fixture.LoginType = 'user'
    $preview = @(& $ScriptPath @parameters -InformationVariable previewMessages)
    Assert-True ($fixture.SignedInUserReads -eq $userReads) 'An explicit human installer override must skip signed-in-user discovery.'
    Assert-True ($preview.Count -eq 2 -and $fixture.Creates.Count -eq 0) 'New Foundry preview must plan two grants without writes.'
    Assert-True (($previewMessages.MessageData -join "`n") -match 'PREVIEW ONLY: Already present: 0; missing: 2') 'Preview must report missing grants without claiming success.'
    Assert-True (@($preview | Where-Object { $_.Scope -ne $runtimeId -or $_.Role -ne 'Managed Identity Operator' }).Count -eq 0) 'Attachment grants must stay on the supplied identity.'

    $existingParameters = $parameters.Clone()
    $existingParameters.DeploymentIdentityResourceId = $deploymentId
    $existingParameters.FoundryAccountResourceId = $foundryId
    $preview = @(& $ScriptPath @existingParameters)
    Assert-True ($preview.Count -eq 7 -and $fixture.Creates.Count -eq 0) 'Existing Foundry preview must plan seven scoped grants without writes.'
    $delegation = @($preview | Where-Object Role -eq 'Role Based Access Control Administrator')
    Assert-True ($delegation.Count -eq 1 -and $delegation[0].Scope -eq $foundryId -and $delegation[0].Condition -eq '') 'Unconditioned delegation must stay at the Foundry account scope.'
    $contributor = @($preview | Where-Object Role -eq 'Contributor')
    Assert-True ($contributor.Count -eq 1 -and $contributor[0].Scope -eq "/subscriptions/$subscription/resourceGroups/foundry") 'Contributor must be scoped to the Foundry resource group.'

    $invalidParameters = $existingParameters.Clone()
    $invalidParameters.Remove('DeploymentIdentityResourceId')
    try { & $ScriptPath @invalidParameters; throw 'Expected missing deployment identity rejection.' }
    catch { if ($_.Exception.Message -notlike '*requires*together*') { throw } }
    $invalidParameters = $existingParameters.Clone()
    $invalidParameters.DeploymentIdentityResourceId = $runtimeId
    try { & $ScriptPath @invalidParameters; throw 'Expected shared-identity rejection.' }
    catch { if ($_.Exception.Message -notlike '*separate runtime*') { throw } }
    Assert-True ($fixture.Creates.Count -eq 0) 'Invalid inputs must cause no writes.'
    try { & $ScriptPath @existingParameters -Apply -Confirm:$false; throw 'Expected privileged opt-in rejection.' }
    catch { if ($_.Exception.Message -notlike '*requires -AllowUnrestrictedFoundryRbac*') { throw } }
    Assert-True ($fixture.Creates.Count -eq 0) 'Missing privileged opt-in must abort before any assignment is created.'

    $null = & $ScriptPath @existingParameters -Apply -WhatIf -InformationVariable whatIfMessages
    Assert-True ($fixture.Creates.Count -eq 0) 'WhatIf must never create assignments.'
    Assert-True (($whatIfMessages.MessageData -join "`n") -match 'PREVIEW ONLY: Already present: 0; missing: 7') 'WhatIf must not report unapplied grants as passed.'
    $applied = @(& $ScriptPath @existingParameters -Apply -AllowUnrestrictedFoundryRbac -Confirm:$false -InformationVariable applyMessages)
    Assert-True ($fixture.Creates.Count -eq 7 -and @($applied | Where-Object Status -ne 'Created').Count -eq 0) 'Apply must create and verify seven grants.'
    Assert-True (($applyMessages.MessageData -join "`n") -match 'PASS: All 7 required role assignments match. Created: 7; already present: 0') 'Apply must report a clear passing count.'
    $delegationCall = @($fixture.Creates | Where-Object { (Get-Option $_ '--role') -eq 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' })
    Assert-True (-not ($delegationCall[0] -contains '--condition') -and -not ($delegationCall[0] -contains '--condition-version')) 'RBAC Administrator creation must not require or submit a condition.'
    $repeated = @(& $ScriptPath @existingParameters -Apply -Confirm:$false -InformationVariable repeatMessages)
    Assert-True ($fixture.Creates.Count -eq 7 -and @($repeated | Where-Object Status -ne 'AlreadyPresent').Count -eq 0) 'A repeated apply must skip matching assignments.'
    Assert-True (($repeatMessages.MessageData -join "`n") -match 'PASS: All 7 required role assignments match. Created: 0; already present: 7') 'Existing matching permissions must pass, not fail.'

    foreach ($assignment in $fixture.Assignments) {
        $assignment | Add-Member -NotePropertyName condition -NotePropertyValue $null
    }
    $fixture.Assignments[0].condition = ''
    $withOptionalConditions = @(& $ScriptPath @existingParameters -Apply -Confirm:$false)
    Assert-True ($fixture.Creates.Count -eq 7 -and @($withOptionalConditions | Where-Object Status -ne 'AlreadyPresent').Count -eq 0) 'Null and empty optional conditions must also pass as existing unconditional grants.'
    ($fixture.Assignments | Where-Object { $_.roleDefinitionId -like '*f58310d9-a9f6-439a-9e8d-f62e7b41a168' }).condition = 'EXISTING-ADMIN-APPROVED-CONDITION'
    try { & $ScriptPath @existingParameters -Apply -Confirm:$false; throw 'Expected condition conflict.' }
    catch { if ($_.Exception.Message -notlike '*different delegation conditions*') { throw } }
    Assert-True ($fixture.Creates.Count -eq 7) 'Condition conflicts must abort preflight without writes.'

    $fixture.Assignments.Clear()
    $fixture.Creates.Clear()
    $fixture.FailCreateAt = 2
    try { & $ScriptPath @parameters -Apply -Confirm:$false; throw 'Expected CLI create failure.' }
    catch { if ($_.Exception.Message -notlike '*Azure CLI failed*') { throw } }
    Assert-True ($fixture.Assignments.Count -eq 1) 'Create failures must surface without hiding earlier successful grants.'
    $fixture.ReadFailure = $true
    try { & $ScriptPath @parameters; throw 'Expected CLI read failure.' }
    catch { if ($_.Exception.Message -notlike '*Azure CLI failed*') { throw } }
    Write-Output 'PASS: installer resolution/context guards, preview, bounded scopes, privileged opt-in, condition-free apply, identity separation, WhatIf, rerun, conflict and CLI failure handling. All Azure CLI calls were mocked.'
}
finally {
    if ($null -ne $previousExitCode) { $global:LASTEXITCODE = $previousExitCode.Value }
    else { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
}

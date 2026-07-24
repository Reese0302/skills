param(
    [Parameter(Position = 0)]
    [string]$TaskFile,

    [string]$TaskText,

    [string[]]$AddDir = @(),

    [string]$Name = "delegate",

    [ValidateSet("implement", "review", "rescue")]
    [string]$TaskMode = "implement",

    [string]$WorkflowId = "",

    [string]$TaskId = "",

    [string]$Role = "implementer",

    [ValidateSet("default", "skill-mechanic-readonly", "claude-html-write-one-file", "reflect-readonly-scout")]
    [string]$PermissionProfile = "default",

    [string[]]$WorkflowLearningCase = @(),

    [string]$ManagedSandboxPath = "",

    [string]$ClaudePath = "",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "claude-cli-discovery.ps1")

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description does not exist: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-TaskText {
    param(
        [string]$Path,
        [string]$InlineText
    )

    if ($Path) {
        $resolvedTaskFile = Resolve-ExistingPath -Path $Path -Description "Task file"
        return @{
            Text = Get-Content -LiteralPath $resolvedTaskFile -Encoding UTF8 -Raw
            Source = $resolvedTaskFile
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($InlineText)) {
        return @{
            Text = $InlineText
            Source = "parameter"
        }
    }

    $stdinText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($stdinText)) {
        throw "Provide task text through -TaskFile, -TaskText, or stdin."
    }

    return @{
        Text = $stdinText
        Source = "stdin"
    }
}
function Assert-TaskContract {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskText,

        [Parameter(Mandatory = $true)]
        [string]$TaskSource
    )

    $requiredSections = @(
        'Goal',
        'Allowed Scope',
        'Forbidden Actions',
        'Acceptance Criteria',
        'Verification',
        'Report Requirements'
    )

    $missingSections = @()
    foreach ($sectionName in $requiredSections) {
        $pattern = '(?m)^\s*##\s+' + [regex]::Escape($sectionName) + '\s*$'
        if (-not [regex]::IsMatch($TaskText, $pattern)) {
            $missingSections += $sectionName
        }
    }

    if ($missingSections.Count -gt 0) {
        $missingList = $missingSections -join ', '
        throw "Task is missing required sections: $missingList. Required sections are: Goal, Allowed Scope, Forbidden Actions, Acceptance Criteria, Verification, Report Requirements. Source: $TaskSource"
    }
}

function Get-StrictUtf8Text {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description is missing: $Path"
    }

    try {
        $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString([System.IO.File]::ReadAllBytes($Path))
    }
    catch {
        throw "$Description is not readable as strict UTF-8: $Path"
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "$Description is empty: $Path"
    }

    return $text
}

function Get-ManagedConstraints {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [ValidateSet("task", "guidance")]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $matches = [regex]::Matches($Text, '(?ms)^\s*##\s+Managed Constraints\s*$\s*^```json\s*$\s*(?<json>\{.*?\})\s*^```\s*$')
    if ($matches.Count -ne 1) {
        throw "$Kind managed constraints must contain exactly one ## Managed Constraints JSON block. Source: $Source"
    }

    try {
        $constraints = $matches[0].Groups['json'].Value | ConvertFrom-Json
    }
    catch {
        throw "$Kind managed constraints JSON is invalid. Source: $Source"
    }

    if ($null -eq $constraints.PSObject.Properties['schema_version'] -or [int]$constraints.schema_version -ne 1) {
        throw "$Kind managed constraints must declare schema_version 1. Source: $Source"
    }

    $fields = if ($Kind -eq 'task') {
        @('requested_paths', 'requested_tools', 'requested_acceptance_criteria', 'required_permissions')
    }
    else {
        @('forbidden_paths', 'forbidden_tools', 'forbidden_acceptance_criteria', 'required_permissions')
    }

    $normalized = [ordered]@{ schema_version = 1 }
    foreach ($field in $fields) {
        $property = $constraints.PSObject.Properties[$field]
        if ($null -eq $property) {
            throw "$Kind managed constraints is missing $field. Source: $Source"
        }

        if ($property.Value -is [string] -or $property.Value -isnot [System.Collections.IEnumerable]) {
            throw "$Kind managed constraints $field must be an array. Source: $Source"
        }

        $values = @($property.Value)
        foreach ($value in $values) {
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
                throw "$Kind managed constraints $field must contain only non-empty strings. Source: $Source"
            }
        }

        $normalized[$field] = @($values)
    }

    if ($Kind -eq 'guidance') {
        $reportRule = $constraints.PSObject.Properties['report_rule']
        if ($null -eq $reportRule -or $reportRule.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($reportRule.Value)) {
            throw "Guidance managed constraints must contain a non-empty report_rule. Source: $Source"
        }

        $normalized['report_rule'] = $reportRule.Value
    }
    else {
        $interpretations = $constraints.PSObject.Properties['stricter_interpretations']
        if ($null -eq $interpretations -or $interpretations.Value -is [string] -or $interpretations.Value -isnot [System.Collections.IEnumerable]) {
            throw "Task managed constraints stricter_interpretations must be an array. Source: $Source"
        }

        $normalizedInterpretations = @()
        foreach ($interpretation in @($interpretations.Value)) {
            $sourceProperty = $interpretation.PSObject.Properties['source']
            $valueProperty = $interpretation.PSObject.Properties['interpretation']
            if ($null -eq $sourceProperty -or $null -eq $valueProperty -or $sourceProperty.Value -notin @('CLAUDE.md', 'PROGRESS.md') -or $valueProperty.Value -isnot [string] -or [string]::IsNullOrWhiteSpace($valueProperty.Value)) {
                throw "Task managed constraints stricter_interpretations entries must name a guidance source and non-empty interpretation. Source: $Source"
            }

            if ($normalizedInterpretations.source -contains $sourceProperty.Value) {
                throw "Task managed constraints has duplicate stricter interpretation source: $($sourceProperty.Value). Source: $Source"
            }

            $normalizedInterpretations += [PSCustomObject]@{
                source = $sourceProperty.Value
                interpretation = $valueProperty.Value
            }
        }

        $normalized['stricter_interpretations'] = @($normalizedInterpretations)
    }

    return [PSCustomObject]$normalized
}

function Resolve-ManagedGuidance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SandboxPath
    )

    $root = Resolve-ExistingPath -Path $SandboxPath -Description "Managed sandbox"
    $entries = @()
    foreach ($definition in @(
        @{ Role = 'stable'; FileName = 'CLAUDE.md' },
        @{ Role = 'progress'; FileName = 'PROGRESS.md' }
    )) {
        $path = Join-Path $root $definition.FileName
        $text = Get-StrictUtf8Text -Path $path -Description "Managed guidance $($definition.FileName)"
        if (-not [regex]::IsMatch($text, '(?m)^\s*##\s+Guidance\s*$')) {
            throw "Managed guidance $($definition.FileName) is missing ## Guidance: $path"
        }

        $constraints = Get-ManagedConstraints -Text $text -Kind guidance -Source $path
        if ($definition.Role -eq 'progress' -and $constraints.required_permissions.Count -gt 0) {
            throw "Managed guidance PROGRESS.md cannot require permissions: $path"
        }

        $entries += [PSCustomObject]@{
            role        = $definition.Role
            source      = $definition.FileName
            path        = $path
            sha256      = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            constraints = $constraints
        }
    }

    return [PSCustomObject]@{
        version = 1
        root    = $root
        entries = @($entries)
    }
}

function Assert-ManagedTaskCompatibility {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskConstraints,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$GuidanceManifest
    )

    $fieldPairs = @(
        @{ Requested = 'requested_paths'; Forbidden = 'forbidden_paths' },
        @{ Requested = 'requested_tools'; Forbidden = 'forbidden_tools' },
        @{ Requested = 'requested_acceptance_criteria'; Forbidden = 'forbidden_acceptance_criteria' }
    )
    foreach ($pair in $fieldPairs) {
        $forbidden = @($GuidanceManifest.entries | ForEach-Object { $_.constraints.($pair.Forbidden) })
        foreach ($requestedValue in $TaskConstraints.($pair.Requested)) {
            if ($forbidden -contains $requestedValue) {
                throw "BLOCKED: local-guidance-conflict: task $($pair.Requested) value is forbidden: $requestedValue"
            }
        }
    }

    $requiredPermissions = @($GuidanceManifest.entries | ForEach-Object { $_.constraints.required_permissions })
    foreach ($permission in $requiredPermissions) {
        if ($TaskConstraints.required_permissions -notcontains $permission) {
            throw "BLOCKED: local-guidance-conflict: task is missing required permission: $permission"
        }
    }
}

function Assert-ManagedGuidanceUnchanged {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$GuidanceManifest
    )

    foreach ($entry in $GuidanceManifest.entries) {
        $currentHash = (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash
        if ($currentHash -ne $entry.sha256) {
            throw "BLOCKED: local-guidance-invalid: managed guidance checksum changed: $($entry.path)"
        }
    }
}

function Add-ManagedGuidanceMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Metadata,

        [PSCustomObject]$GuidanceManifest = $null
    )

    if ($null -eq $GuidanceManifest) {
        return
    }

    $Metadata['managedSandboxPath'] = $GuidanceManifest.root
    $Metadata['localGuidanceManifest'] = $GuidanceManifest
}

function Test-ManagedConstraintReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResultText,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$GuidanceManifest,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TaskConstraints
    )

    $sectionMatch = [regex]::Match($ResultText, '(?ms)^\s*##\s+Applied Constraints\s*$\s*(?<table>.*?)(?=^\s*##\s+|\z)')
    if (-not $sectionMatch.Success) {
        return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = 'Applied Constraints section is missing.' }
    }

    $tableLines = @($sectionMatch.Groups['table'].Value -split "`r?`n" | Where-Object { $_.Trim().StartsWith('|') })
    if ($tableLines.Count -lt 3) {
        return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = 'Applied Constraints table is incomplete.' }
    }

    $header = @($tableLines[0].Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
    $expectedHeader = @('Source', 'SHA-256', 'Rule', 'Application in This Task', 'Stricter Interpretation')
    if (($header -join '|') -ne ($expectedHeader -join '|')) {
        return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = 'Applied Constraints table header is invalid.' }
    }

    $rows = @()
    foreach ($tableLine in $tableLines[2..($tableLines.Count - 1)]) {
        $cells = @($tableLine.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -ne $expectedHeader.Count) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = 'Applied Constraints table row is invalid.' }
        }

        $rows += ,$cells
    }

    foreach ($entry in $GuidanceManifest.entries) {
        $matchingRows = @($rows | Where-Object { $_[0] -eq $entry.source })
        if ($matchingRows.Count -ne 1) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = "Applied Constraints must contain one row for $($entry.source)." }
        }

        $row = $matchingRows[0]
        if ($row[1] -ne $entry.sha256) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = "Applied Constraints checksum does not match $($entry.source)." }
        }

        if ($row[2] -ne $entry.constraints.report_rule) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = "Applied Constraints rule does not match $($entry.source)." }
        }

        if ([string]::IsNullOrWhiteSpace($row[3]) -or [string]::IsNullOrWhiteSpace($row[4])) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = "Applied Constraints row is incomplete for $($entry.source)." }
        }

        if ($row[3].Trim().ToLowerInvariant() -in @('none', 'n/a', 'not applicable', 'tbd', 'unknown')) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = "Applied Constraints application is not concrete for $($entry.source)." }
        }

        $matchingInterpretations = @($TaskConstraints.stricter_interpretations | Where-Object { $_.source -eq $entry.source })
        $expectedInterpretation = if ($matchingInterpretations.Count -eq 1) { $matchingInterpretations[0].interpretation } else { 'None identified' }
        if ($row[4] -ne $expectedInterpretation) {
            return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-report'; Reason = "Applied Constraints stricter interpretation does not match $($entry.source)." }
        }
    }

    return [PSCustomObject]@{ Accepted = $true; Status = 'accepted-candidate'; Reason = '' }
}

function Test-NativeWebProjectionAcceptance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$JsonText,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$GuidanceManifest
    )

    $progressEntry = @($GuidanceManifest.entries | Where-Object { $_.source -eq 'PROGRESS.md' })
    if ($progressEntry.Count -ne 1 -or -not (Test-Path -LiteralPath $progressEntry[0].path -PathType Leaf)) {
        return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-native-web-evidence'; Reason = 'Projected progress guidance is unavailable.' }
    }

    $progressText = Get-Content -LiteralPath $progressEntry[0].path -Encoding UTF8 -Raw
    if ($progressText -notmatch 'native-web-zero-cannot-complete') {
        return [PSCustomObject]@{ Accepted = $true; Status = 'accepted-candidate'; Reason = '' }
    }

    try {
        $output = $JsonText | ConvertFrom-Json
        $usage = $output.usage.server_tool_use
        if ($null -eq $usage -or
            $null -eq $usage.PSObject.Properties['web_search_requests'] -or
            $null -eq $usage.PSObject.Properties['web_fetch_requests']) {
            throw 'Native web telemetry fields are missing.'
        }

        $searchCount = $usage.web_search_requests
        $fetchCount = $usage.web_fetch_requests
        if (($searchCount -isnot [System.Int32] -and $searchCount -isnot [System.Int64]) -or
            ($fetchCount -isnot [System.Int32] -and $fetchCount -isnot [System.Int64]) -or
            $searchCount -lt 0 -or $fetchCount -lt 0) {
            throw 'Native web telemetry counts must be non-negative integers.'
        }
    }
    catch {
        return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-native-web-evidence'; Reason = 'Native web telemetry is missing or invalid.' }
    }

    if ($searchCount -eq 0 -and $fetchCount -eq 0) {
        return [PSCustomObject]@{ Accepted = $false; Status = 'unaccepted-native-web-evidence'; Reason = 'Native web request counts are zero.' }
    }

    return [PSCustomObject]@{ Accepted = $true; Status = 'accepted-candidate'; Reason = '' }
}

function ConvertTo-SafeName {
    param([string]$Value)

    $safe = $Value -replace '[^A-Za-z0-9._-]+', '-'
    $safe = $safe.Trim("-._")

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "delegate"
    }

    return $safe.ToLowerInvariant()
}

function New-DelegateBrief {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskText,

        [PSCustomObject]$GuidanceManifest = $null
    )

    $localGuidance = ""
    if ($null -ne $GuidanceManifest) {
        $manifestJson = $GuidanceManifest | Select-Object version, entries | ConvertTo-Json -Depth 10
        $localGuidance = @(
            '',
            '## Local Guidance',
            '',
            'Read the guidance manifest below before acting. Its files are required task inputs.',
            'Your final report must include one row for each source in the following table. State a concrete application and either the stricter interpretation used or `None identified`.',
            '',
            '| Source | SHA-256 | Rule | Application in This Task | Stricter Interpretation |',
            '|---|---|---|---|---|',
            '',
            '```json',
            $manifestJson,
            '```',
            ''
        ) -join [Environment]::NewLine
    }

    return @"
You are Claude Code running as a controlled external executor for Codex.

Role boundaries:
- Execute only the task below.
- Prefer small, direct edits over broad refactors.
- Do not revert unrelated user changes.
- Do not claim final verification authority; Codex will review diffs and run final checks.
- If blocked, stop and report the blocker clearly instead of guessing.
- In your final response, list files changed and any checks you ran.

Delegated task:

$localGuidance

$TaskText
"@
}

function Get-PermissionProfileConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Profile
    )

    $permissionMode = "acceptEdits"
    $allowedTools = @()

    switch ($Profile) {
        "skill-mechanic-readonly" {
            $allowedTools = @("Bash", "Glob")
        }
        "reflect-readonly-scout" {
            $allowedTools = @("Read", "Bash", "Glob")
        }
        default {
            $allowedTools = @()
        }
    }

    $arguments = @(
        "-p",
        "--output-format", "json",
        "--permission-mode", $permissionMode
    )

    if ($allowedTools.Count -gt 0) {
        $arguments += @("--allowedTools", ($allowedTools -join ","))
    }

    return @{
        PermissionMode = $permissionMode
        AllowedTools = $allowedTools
        Arguments = $arguments
    }
}

function Get-ResultText {
    param([string]$JsonText)

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return ""
    }

    try {
        $parsed = $JsonText | ConvertFrom-Json
        foreach ($propertyName in @("result", "content", "message", "summary")) {
            if ($null -ne $parsed.PSObject.Properties[$propertyName]) {
                $value = $parsed.$propertyName
                if ($value -is [string]) {
                    return $value
                }

                return ($value | ConvertTo-Json -Depth 20)
            }
        }
    }
    catch {
        return $JsonText
    }

    return $JsonText
}

function ConvertTo-NativeArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-ClaudePrint {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClaudeExe,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$StandardInputText,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$StandardOutputPath,

        [Parameter(Mandatory = $true)]
        [string]$StandardErrorPath
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ClaudeExe
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $psi.Arguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join " "

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()

    $process.StandardInput.Write($StandardInputText)
    $process.StandardInput.Close()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    Set-Content -LiteralPath $StandardOutputPath -Value $stdout -Encoding UTF8
    Set-Content -LiteralPath $StandardErrorPath -Value $stderr -Encoding UTF8

    return @{
        ExitCode = $process.ExitCode
        Stdout = $stdout
    }
}

$task = Get-TaskText -Path $TaskFile -InlineText $TaskText
Assert-TaskContract -TaskText $task.Text -TaskSource $task.Source
$managedGuidance = $null
$managedTaskConstraints = $null
if (-not [string]::IsNullOrWhiteSpace($ManagedSandboxPath)) {
    try {
        $managedGuidance = Resolve-ManagedGuidance -SandboxPath $ManagedSandboxPath
        $managedTaskConstraints = Get-ManagedConstraints -Text $task.Text -Kind task -Source $task.Source
        Assert-ManagedTaskCompatibility -TaskConstraints $managedTaskConstraints -GuidanceManifest $managedGuidance
    }
    catch {
        if ($_.Exception.Message -match '^BLOCKED: local-guidance-conflict:') {
            throw $_
        }

        throw "BLOCKED: local-guidance-invalid: $($_.Exception.Message)"
    }
}
$brief = New-DelegateBrief -TaskText $task.Text -GuidanceManifest $managedGuidance
$claudeResolution = Resolve-ClaudeCliPath -PreferredPath $ClaudePath
$claudeExe = $claudeResolution.Path
$safeName = ConvertTo-SafeName -Value $Name
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$workflowIdValue = if ([string]::IsNullOrWhiteSpace($WorkflowId)) { "workflow-$timestamp-$safeName" } else { $WorkflowId }
$taskIdValue = if ([string]::IsNullOrWhiteSpace($TaskId)) { $safeName } else { $TaskId }
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$runDir = Join-Path $repoRoot ".delegate-runs\$timestamp-$safeName"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null

$briefPath = Join-Path $runDir "brief.md"
$commandPath = Join-Path $runDir "command.json"
$outputPath = Join-Path $runDir "claude-output.json"
$resultPath = Join-Path $runDir "result.md"
$metadataPath = Join-Path $runDir "metadata.json"
$stderrPath = Join-Path $runDir "claude-stderr.txt"

$resolvedAddDirs = @()
foreach ($dir in $AddDir) {
    $resolvedAddDirs += Resolve-ExistingPath -Path $dir -Description "Allowed directory"
}

Set-Content -LiteralPath $briefPath -Value $brief -Encoding UTF8

$permissionProfileConfig = Get-PermissionProfileConfig -Profile $PermissionProfile
$arguments = @($permissionProfileConfig.Arguments)

foreach ($dir in $resolvedAddDirs) {
    $arguments += @("--add-dir", $dir)
}

$command = [ordered]@{
    executable = $claudeExe
    executableSource = $claudeResolution.Source
    arguments = $arguments
    input = "stdin:brief.md"
    workingDirectory = $repoRoot
    permissionProfile = $PermissionProfile
    workflowLearningCases = $WorkflowLearningCase
    permissionMode = $permissionProfileConfig.PermissionMode
    allowedTools = $permissionProfileConfig.AllowedTools
}
Add-ManagedGuidanceMetadata -Metadata $command -GuidanceManifest $managedGuidance

$command | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $commandPath -Encoding UTF8

if ($DryRun) {
    $metadata = [ordered]@{
        name           = $safeName
        taskMode       = $TaskMode
        workflowId     = $workflowIdValue
        taskId         = $taskIdValue
        role           = $Role
        taskSource     = $task.Source
        addDirs        = $resolvedAddDirs
        claudePath     = $claudeExe
        claudePathSource = $claudeResolution.Source
        permissionProfile = $PermissionProfile
        workflowLearningCases = $WorkflowLearningCase
        permissionMode = $permissionProfileConfig.PermissionMode
        allowedTools   = $permissionProfileConfig.AllowedTools
        outputFormat   = "json"
        runDir         = $runDir
        briefPath      = $briefPath
        commandPath    = $commandPath
        dryRun         = $true
        invokedClaude  = $false
        startedAt      = (Get-Date).ToString("o")
    }
    Add-ManagedGuidanceMetadata -Metadata $metadata -GuidanceManifest $managedGuidance

    $metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

    Write-Output "claude-delegate dry-run: $runDir"
    exit 0
}

$startedAt = (Get-Date).ToString("o")
if ($null -ne $managedGuidance) {
    Assert-ManagedGuidanceUnchanged -GuidanceManifest $managedGuidance
}
$invokeResult = Invoke-ClaudePrint `
    -ClaudeExe $claudeExe `
    -Arguments $arguments `
    -StandardInputText $brief `
    -WorkingDirectory $repoRoot `
    -StandardOutputPath $outputPath `
    -StandardErrorPath $stderrPath
$exitCode = $invokeResult.ExitCode
$finishedAt = (Get-Date).ToString("o")

$stdoutText = $invokeResult.Stdout
$resultText = Get-ResultText -JsonText $stdoutText
Set-Content -LiteralPath $resultPath -Value $resultText -Encoding UTF8
$managedAcceptance = $null
$reportAcceptance = $null
$nativeWebAcceptance = $null
if ($null -ne $managedGuidance) {
    $reportAcceptance = Test-ManagedConstraintReport -ResultText $resultText -GuidanceManifest $managedGuidance -TaskConstraints $managedTaskConstraints
    $nativeWebAcceptance = Test-NativeWebProjectionAcceptance -JsonText $stdoutText -GuidanceManifest $managedGuidance
    $managedAcceptance = $reportAcceptance
    if ($reportAcceptance.Accepted -and -not $nativeWebAcceptance.Accepted) {
        $managedAcceptance = $nativeWebAcceptance
    }
}

$metadata = [ordered]@{
    name           = $safeName
    taskMode       = $TaskMode
    workflowId     = $workflowIdValue
    taskId         = $taskIdValue
    role           = $Role
    taskSource     = $task.Source
    addDirs        = $resolvedAddDirs
    claudePath     = $claudeExe
    claudePathSource = $claudeResolution.Source
    permissionProfile = $PermissionProfile
    workflowLearningCases = $WorkflowLearningCase
    permissionMode = $permissionProfileConfig.PermissionMode
    allowedTools   = $permissionProfileConfig.AllowedTools
    outputFormat   = "json"
    dryRun         = $false
    invokedClaude  = $true
    runDir         = $runDir
    briefPath      = $briefPath
    commandPath    = $commandPath
    outputPath     = $outputPath
    resultPath     = $resultPath
    stderrPath     = $stderrPath
    startedAt      = $startedAt
    finishedAt     = $finishedAt
    exitCode       = $exitCode
    acceptedCandidate = if ($null -ne $managedAcceptance) { $exitCode -eq 0 -and $managedAcceptance.Accepted } else { $null }
    acceptanceStatus = if ($null -ne $managedAcceptance) { $managedAcceptance.Status } else { $null }
    acceptanceReason = if ($null -ne $managedAcceptance) { $managedAcceptance.Reason } else { $null }
    reportAcceptance = if ($null -ne $reportAcceptance) { [ordered]@{ accepted = $reportAcceptance.Accepted; status = $reportAcceptance.Status; reason = $reportAcceptance.Reason } } else { $null }
    nativeWebAcceptance = if ($null -ne $nativeWebAcceptance) { [ordered]@{ accepted = $nativeWebAcceptance.Accepted; status = $nativeWebAcceptance.Status; reason = $nativeWebAcceptance.Reason } } else { $null }
}
Add-ManagedGuidanceMetadata -Metadata $metadata -GuidanceManifest $managedGuidance

$metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

Write-Output "claude-delegate run: $runDir"
Write-Output "exitCode: $exitCode"
Write-Output "result: $resultPath"

exit $exitCode

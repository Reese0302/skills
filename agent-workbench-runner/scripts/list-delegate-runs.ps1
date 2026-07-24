param(
    [int]$Latest = 20,

    [string]$WorkflowId = "",

    [string]$RunRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RunRoot)) {
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $RunRoot = Join-Path $repoRoot ".delegate-runs"
}

if (-not (Test-Path -LiteralPath $RunRoot)) {
    return
}

$runs = foreach ($runDir in Get-ChildItem -LiteralPath $RunRoot -Directory) {
    $metadataPath = Join-Path $runDir.FullName "metadata.json"
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        continue
    }

    try {
        $metadata = Get-Content -LiteralPath $metadataPath -Encoding UTF8 -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Skipping invalid metadata: $metadataPath"
        continue
    }

    if (-not [string]::IsNullOrWhiteSpace($WorkflowId) -and $metadata.workflowId -ne $WorkflowId) {
        continue
    }

    [PSCustomObject]@{
        Name          = $metadata.name
        TaskMode      = $metadata.taskMode
        WorkflowId    = $metadata.workflowId
        TaskId        = $metadata.taskId
        Role          = $metadata.role
        StartedAt     = $metadata.startedAt
        FinishedAt    = $metadata.finishedAt
        ExitCode      = $metadata.exitCode
        DryRun        = $metadata.dryRun
        InvokedClaude = $metadata.invokedClaude
        RunDir        = $runDir.FullName
    }
}

$runs |
    Sort-Object -Property StartedAt, RunDir -Descending |
    Select-Object -First $Latest

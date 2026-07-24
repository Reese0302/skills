param(
    [Parameter(Position = 0)]
    [string]$TaskFile,

    [string]$TaskText,

    [ValidateSet("auto", "scan", "plan", "review", "delegate")]
    [string]$Mode = "auto",

    [string[]]$AddDir = @(),

    [string]$Name = "route",

    [string]$CodexPath = "codex",

    [string]$DelegateScript = "",

    [ValidateSet("implement", "review", "rescue")]
    [string]$DelegateTaskMode = "implement",

    [string]$DelegateRole = "implementer",

    [string]$WorkflowId = "",

    [string]$TaskId = "",

    [switch]$Run
)

$ErrorActionPreference = "Stop"

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

function Get-TaskPayload {
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

function Get-RoutedMode {
    param([string]$TaskText)

    $planOverridePattern = '不是\s*(review|审查|验收)|not\s+(a\s+)?(review|validation|audit)|不是.*已有\s*diff|不是.*现有\s*diff|not.*existing\s+diff'
    $reviewPattern = 'review|验收|回归|边界|regression|edge case|acceptance|final review|verify|validation|validate|audit'
    $delegatePattern = '按既定方案|按方案|冻结方案|确定性修改|确定性实现|直接改|直接执行|批量修改|implement the approved plan|apply the planned change|follow the plan|execute the decided change|deterministic|apply the approved change'
    $scanPattern = '总结|定位|查找|扫描|看看|概览|where|locate|summari[sz]e|scan|inspect|overview|find'

    if ($TaskText -match $planOverridePattern) {
        return @{
            Mode = "plan"
            Reason = "命中非 review / 非已有 diff 的计划意图，按 workflow case routing/research-plan-vs-review 走 plan。"
        }
    }

    if ($TaskText -match $reviewPattern) {
        return @{
            Mode = "review"
            Reason = "命中 review / 验收类关键词，优先走深度审查通道。"
        }
    }

    if ($TaskText -match $delegatePattern) {
        return @{
            Mode = "delegate"
            Reason = "命中确定性执行类关键词，优先推荐走 delegate 通道。"
        }
    }

    if ($TaskText -match $scanPattern) {
        return @{
            Mode = "scan"
            Reason = "命中扫描 / 总结类关键词，优先走快速侦察通道。"
        }
    }

    return @{
        Mode = "plan"
        Reason = "未命中更窄的模式，默认走主规划通道。"
    }
}

function New-CodexInvocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$SelectedMode
    )

    switch ($SelectedMode) {
        "scan" {
            return @{
                Executable = $Executable
                Arguments = @(
                    "exec",
                    "-m", "gpt-5.4-mini",
                    "-c", 'model_reasoning_effort="low"',
                    "-C", $WorkingDirectory
                )
                Reason = "快速侦察通道：便宜、快，适合读文件和定位。"
            }
        }
        "review" {
            return @{
                Executable = $Executable
                Arguments = @(
                    "exec",
                    "-m", "gpt-5.5",
                    "-c", 'model_reasoning_effort="high"',
                    "-C", $WorkingDirectory
                )
                Reason = "深度审查通道：更适合验收、回归和风险检查。"
            }
        }
        default {
            return @{
                Executable = $Executable
                Arguments = @(
                    "exec",
                    "-m", "gpt-5.5",
                    "-c", 'model_reasoning_effort="medium"',
                    "-C", $WorkingDirectory
                )
                Reason = "主规划通道：默认平衡速度与推理深度。"
            }
        }
    }
}

function Invoke-CodexRoute {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$TaskText
    )

    $TaskText | & $Executable @Arguments - | Out-Host
    return $LASTEXITCODE
}

function Write-RouteDecisionLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$Record
    )

    $logDir = Join-Path $RepoRoot '.delegate-runs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $logPath = Join-Path $logDir 'route-decisions.jsonl'
    ($Record | ConvertTo-Json -Compress -Depth 10) | Add-Content -LiteralPath $logPath -Encoding UTF8

    return $logPath
}

function New-RouteLogRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SelectedMode,

        [Parameter(Mandatory = $true)]
        [string]$Reason,

        [Parameter(Mandatory = $true)]
        [bool]$DidRun,

        [Parameter(Mandatory = $true)]
        [string]$TaskSource,

        [Parameter(Mandatory = $true)]
        [string]$Executable,

        [string]$LaneNote = '',

        [int]$ExecutionExitCode = -2147483648
    )

    $record = [ordered]@{
        ts = (Get-Date).ToString('o')
        selectedMode = $SelectedMode
        reason = $Reason
        run = $DidRun
        taskSource = $TaskSource
        command = [ordered]@{
            executable = $Executable
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($LaneNote)) {
        $record.laneNote = $LaneNote
    }

    if ($ExecutionExitCode -ne -2147483648) {
        $record.executionExitCode = $ExecutionExitCode
    }

    return $record
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$delegatePath = if ([string]::IsNullOrWhiteSpace($DelegateScript)) {
    Join-Path $PSScriptRoot "claude-delegate.ps1"
} else {
    Resolve-ExistingPath -Path $DelegateScript -Description "Delegate script"
}

$task = Get-TaskPayload -Path $TaskFile -InlineText $TaskText
$route = if ($Mode -eq "auto") { Get-RoutedMode -TaskText $task.Text } else { @{ Mode = $Mode; Reason = "显式指定模式：$Mode" } }
$selectedMode = $route.Mode

if ($selectedMode -eq "delegate" -and $AddDir.Count -eq 0) {
    $AddDir = @($repoRoot)
}

if ($selectedMode -eq "delegate") {
    $delegateArgs = @()
    $delegateParams = @{
        Name = $Name
        TaskMode = $DelegateTaskMode
        Role = $DelegateRole
    }

    if ($TaskFile) {
        $resolvedTaskFile = Resolve-ExistingPath -Path $TaskFile -Description "Task file"
        $delegateArgs += @("-TaskFile", $resolvedTaskFile)
        $delegateParams.TaskFile = $resolvedTaskFile
    } else {
        $delegateArgs += @("-TaskText", $task.Text)
        $delegateParams.TaskText = $task.Text
    }

    $delegateArgs += @("-Name", $Name, "-TaskMode", $DelegateTaskMode, "-Role", $DelegateRole)

    if (-not [string]::IsNullOrWhiteSpace($WorkflowId)) {
        $delegateArgs += @("-WorkflowId", $WorkflowId)
        $delegateParams.WorkflowId = $WorkflowId
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskId)) {
        $delegateArgs += @("-TaskId", $TaskId)
        $delegateParams.TaskId = $TaskId
    }

    foreach ($dir in $AddDir) {
        $delegateArgs += @("-AddDir", $dir)
    }
    if ($AddDir.Count -gt 0) {
        $delegateParams.AddDir = $AddDir
    }

    $preview = [ordered]@{
        selectedMode = $selectedMode
        reason = $route.Reason
        laneNote = "受控执行通道：自动转给 claude-delegate，并显式传入委派模式与角色。"
        taskSource = $task.Source
        run = [bool]$Run
        delegate = [ordered]@{
            taskMode = $DelegateTaskMode
            role = $DelegateRole
            workflowId = if ([string]::IsNullOrWhiteSpace($WorkflowId)) { $null } else { $WorkflowId }
            taskId = if ([string]::IsNullOrWhiteSpace($TaskId)) { $null } else { $TaskId }
            workflowIdSource = if ([string]::IsNullOrWhiteSpace($WorkflowId)) { "delegate-default" } else { "route-parameter" }
            taskIdSource = if ([string]::IsNullOrWhiteSpace($TaskId)) { "delegate-default" } else { "route-parameter" }
        }
        command = [ordered]@{
            executable = $delegatePath
            arguments = $delegateArgs
            workingDirectory = $repoRoot
        }
    }

    $preview | ConvertTo-Json -Depth 8

    if (-not $Run) {
        $null = Write-RouteDecisionLog -RepoRoot $repoRoot -Record (New-RouteLogRecord -SelectedMode $selectedMode -Reason $route.Reason -DidRun $false -TaskSource $task.Source -Executable $delegatePath -LaneNote $preview.laneNote)
        exit 0
    }

    & $delegatePath @delegateParams
    $exitCode = $LASTEXITCODE
    $null = Write-RouteDecisionLog -RepoRoot $repoRoot -Record (New-RouteLogRecord -SelectedMode $selectedMode -Reason $route.Reason -DidRun $true -TaskSource $task.Source -Executable $delegatePath -LaneNote $preview.laneNote -ExecutionExitCode $exitCode)
    exit $exitCode
}

$codexInvocation = New-CodexInvocation -Executable $CodexPath -WorkingDirectory $repoRoot -SelectedMode $selectedMode
$preview = [ordered]@{
    selectedMode = $selectedMode
    reason = $route.Reason
    laneNote = $codexInvocation.Reason
    taskSource = $task.Source
    run = [bool]$Run
    command = [ordered]@{
        executable = $codexInvocation.Executable
        arguments = $codexInvocation.Arguments
        workingDirectory = $repoRoot
        promptInput = "stdin"
    }
}

$preview | ConvertTo-Json -Depth 8

if (-not $Run) {
    $null = Write-RouteDecisionLog -RepoRoot $repoRoot -Record (New-RouteLogRecord -SelectedMode $selectedMode -Reason $route.Reason -DidRun $false -TaskSource $task.Source -Executable $codexInvocation.Executable -LaneNote $codexInvocation.Reason)
    exit 0
}

$exitCode = Invoke-CodexRoute -Executable $codexInvocation.Executable -Arguments $codexInvocation.Arguments -TaskText $task.Text
$null = Write-RouteDecisionLog -RepoRoot $repoRoot -Record (New-RouteLogRecord -SelectedMode $selectedMode -Reason $route.Reason -DidRun $true -TaskSource $task.Source -Executable $codexInvocation.Executable -LaneNote $codexInvocation.Reason -ExecutionExitCode $exitCode)
exit $exitCode


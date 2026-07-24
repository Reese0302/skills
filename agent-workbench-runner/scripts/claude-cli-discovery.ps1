$script:ClaudeCodeExtensionPattern = 'anthropic.claude-code-*'

function Resolve-ClaudeCliLeafPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Claude CLI path from $Source is empty."
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Claude CLI path from $Source does not exist or is not a file: $Path"
    }

    return [PSCustomObject]@{
        Path   = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        Source = $Source
    }
}

function Get-ClaudeCodeExtensionRoots {
    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $roots += (Join-Path $env:USERPROFILE '.vscode\extensions')
        $roots += (Join-Path $env:USERPROFILE '.vscode-insiders\extensions')
        $roots += (Join-Path $env:USERPROFILE '.cursor\extensions')
        $roots += (Join-Path $env:USERPROFILE '.windsurf\extensions')
    }

    return @($roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-ClaudeCodeExtensionCandidates {
    param([string[]]$ExtensionRoots)

    $candidates = @()
    foreach ($root in $ExtensionRoots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        $extensions = Get-ChildItem -LiteralPath $root -Directory -Filter $script:ClaudeCodeExtensionPattern -ErrorAction SilentlyContinue
        foreach ($extension in $extensions) {
            $nativePath = Join-Path $extension.FullName 'resources\native-binary\claude.exe'
            if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) {
                continue
            }

            $versionText = $extension.Name -replace '^anthropic\.claude-code-', '' -replace '-win32-x64$', ''
            $parsedVersion = $null
            [void][Version]::TryParse($versionText, [ref]$parsedVersion)

            $candidates += [PSCustomObject]@{
                Path          = $nativePath
                Source        = ('vscode-extension:{0}' -f $extension.Name)
                Version       = $parsedVersion
                LastWriteTime = $extension.LastWriteTimeUtc
            }
        }
    }

    return @($candidates | Sort-Object -Property @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true })
}

function Resolve-ClaudeCliPath {
    param(
        [string]$PreferredPath = '',
        [string[]]$ExtensionRoots = @(),
        [switch]$SkipPathLookup
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        return Resolve-ClaudeCliLeafPath -Path $PreferredPath -Source 'parameter'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CLI_PATH)) {
        return Resolve-ClaudeCliLeafPath -Path $env:CLAUDE_CLI_PATH -Source 'env:CLAUDE_CLI_PATH'
    }

    $roots = @($ExtensionRoots)
    if ($roots.Count -eq 0) {
        $roots = @(Get-ClaudeCodeExtensionRoots)
    }

    $extensionCandidate = @(Get-ClaudeCodeExtensionCandidates -ExtensionRoots $roots | Select-Object -First 1)
    if ($extensionCandidate.Count -gt 0) {
        return Resolve-ClaudeCliLeafPath -Path $extensionCandidate[0].Path -Source $extensionCandidate[0].Source
    }

    if (-not $SkipPathLookup) {
        foreach ($commandName in @('claude.exe', 'claude.cmd', 'claude.bat')) {
            $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
                return Resolve-ClaudeCliLeafPath -Path $command.Source -Source ('PATH:{0}' -f $commandName)
            }
        }
    }

    throw 'Claude CLI path was not provided and auto-discovery failed. Pass -ClaudePath, set CLAUDE_CLI_PATH, install the Claude Code extension, or put claude.exe/claude.cmd on PATH.'
}

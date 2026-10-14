#!/usr/bin/env pwsh
<#
Inventory what GitHub Copilot CLI would load for a repository, and flag likely problems.
PowerShell 7+.

  scripts/audit.ps1 [REPO_PATH]      default: current directory

Read-only. Checks personal config in $env:COPILOT_HOME (or ~/.copilot) plus ~/.claude and
~/.agents skill directories, and the repo's instruction, skill, agent, and hook files.

Word counts are a rough proxy for context cost (~1.3 tokens per word for English prose).
#>
param([string]$RepoPath = '.')

$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$userHome = [Environment]::GetFolderPath('UserProfile')
$ch = if ($env:COPILOT_HOME) { $env:COPILOT_HOME } else { Join-Path $userHome '.copilot' }
$budgetPersonal = 300
$budgetRepo = 500
$warnings = [System.Collections.Generic.List[string]]::new()
function Add-Warning([string]$msg) { $warnings.Add($msg) }

function Get-WordCount([string]$path) {
    $text = Get-Content -LiteralPath $path -Raw
    if (-not $text) { return 0 }
    return ($text -split '\s+' | Where-Object { $_ }).Count
}

# Top-level frontmatter value. Handles single-line values and folded/literal blocks.
function Get-Frontmatter([string]$path, [string]$key) {
    $lines = Get-Content -LiteralPath $path
    if (-not $lines -or $lines[0] -ne '---') { return '' }
    $collecting = $false; $val = ''
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -eq '---') { break }
        if ($collecting) {
            if ($line -match '^[ \t]+') { $val = ($val + ' ' + $line.Trim()).Trim(); continue }
            return $val
        }
        if ($line.StartsWith("${key}:")) {
            $v = $line.Substring($key.Length + 1).Trim()
            if ($v -in '>', '|', '>-', '|-') { $collecting = $true; continue }
            return ($v -replace '^["'']|["'']$', '')
        }
    }
    return $val
}

function Format-Rel([string]$path) {
    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($path.StartsWith($repo + $sep)) { return $path.Substring($repo.Length + 1) }
    if ($path.StartsWith($userHome + $sep)) { return '~/' + $path.Substring($userHome.Length + 1) }
    return $path
}

function Get-Files([string]$dir, [string]$filter) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $filter | Sort-Object FullName)
}

Write-Output 'Copilot CLI config audit'
Write-Output "  repo:         $repo"
Write-Output "  copilot home: $(Format-Rel $ch)"
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Always-on instructions =='
$personalTotal = 0; $repoTotal = 0; $rootFiles = 0

$personal = Join-Path $ch 'copilot-instructions.md'
if (Test-Path -LiteralPath $personal) {
    $w = Get-WordCount $personal; $personalTotal += $w
    Write-Output ('  {0,6} words  {1}  (personal)' -f $w, (Format-Rel $personal))
}

foreach ($f in '.github/copilot-instructions.md', 'AGENTS.md', 'CLAUDE.md', '.claude/CLAUDE.md', 'GEMINI.md') {
    $path = Join-Path $repo $f
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $w = Get-WordCount $path; $repoTotal += $w; $rootFiles++
    Write-Output ('  {0,6} words  {1}' -f $w, $f)
    $inc = @(Select-String -LiteralPath $path -Pattern '(^|\s)@[./A-Za-z0-9_-]+\.[A-Za-z0-9]+' | Select-Object -First 5)
    if ($inc.Count -gt 0) {
        Write-Output '             includes (@):'
        $inc | ForEach-Object { Write-Output ("               {0}:{1}" -f $_.LineNumber, $_.Line) }
        Add-Warning "$f pulls in other files with @. Their contents are always-on too; check their size."
    }
}

# Path-scoped files with applyTo "**" are effectively always-on.
$instructionDirs = @((Join-Path $ch 'instructions'), (Join-Path $repo '.github/instructions'))
foreach ($dir in $instructionDirs) {
    foreach ($file in Get-Files $dir '*.instructions.md') {
        $at = Get-Frontmatter $file.FullName 'applyTo'
        if ($at -in '**', '**/*') {
            $w = Get-WordCount $file.FullName
            if ($file.FullName.StartsWith($ch)) { $personalTotal += $w } else { $repoTotal += $w }
            Write-Output ('  {0,6} words  {1}  (applyTo "{2}")' -f $w, (Format-Rel $file.FullName), $at)
            Add-Warning "$(Format-Rel $file.FullName) has applyTo `"$at`", so it's always-on. Move it to the root file or narrow the glob."
        }
    }
}

if ($env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS) {
    Write-Output '  COPILOT_CUSTOM_INSTRUCTIONS_DIRS is set:'
    foreach ($d in $env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS -split '[,;:](?![\\/])') {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { Write-Output "    (missing) $d"; continue }
        Get-ChildItem -LiteralPath $d -Recurse -File | Where-Object { $_.Name -eq 'AGENTS.md' -or $_.Name -like '*.instructions.md' } |
            Sort-Object FullName | ForEach-Object {
                Write-Output ('  {0,6} words  {1}  (custom dir; scope varies by version)' -f (Get-WordCount $_.FullName), (Format-Rel $_.FullName))
            }
    }
    Add-Warning 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS is set. Its global/path scoping changed after v1.0.65; prefer ~/.copilot/copilot-instructions.md for always-on rules.'
}

Write-Output '  -----'
Write-Output "  personal: $personalTotal / $budgetPersonal words    repo: $repoTotal / $budgetRepo words"
if ($personalTotal -gt $budgetPersonal) { Add-Warning "Personal always-on instructions are over budget ($personalTotal > $budgetPersonal words)." }
if ($repoTotal -gt $budgetRepo) { Add-Warning "Repo always-on instructions are over budget ($repoTotal > $budgetRepo words)." }
if ($rootFiles -gt 1) { Add-Warning "$rootFiles root-level instruction files are combined. Overlapping or conflicting rules across them are a common cause of erratic behavior. Consolidate into one." }
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Path-scoped instructions (loaded when applyTo matches) =='
$found = $false
foreach ($dir in $instructionDirs) {
    foreach ($file in Get-Files $dir '*.instructions.md') {
        $at = Get-Frontmatter $file.FullName 'applyTo'
        if ($at -in '**', '**/*') { continue }
        $found = $true
        Write-Output ('  {0,6} words  {1}  applyTo: {2}' -f (Get-WordCount $file.FullName), (Format-Rel $file.FullName), ($at ? $at : '<none>'))
        if (-not $at) { Add-Warning "$(Format-Rel $file.FullName) has no applyTo." }
    }
}
if (-not $found) { Write-Output '  (none)' }
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Nested agent instruction files (below repo root) =='
$prune = '[\\/](\.git|node_modules|\.terraform|vendor|\.venv)[\\/]'
$nested = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in 'AGENTS.md', 'CLAUDE.md', 'GEMINI.md' } |
    Where-Object { $_.FullName -notmatch $prune } |
    Where-Object { $_.DirectoryName -ne $repo } |
    Where-Object { $_.FullName -ne (Join-Path $repo '.claude/CLAUDE.md') } |
    Sort-Object FullName)
if ($nested.Count -gt 0) {
    $nested | ForEach-Object { Write-Output ('  {0,6} words  {1}' -f (Get-WordCount $_.FullName), (Format-Rel $_.FullName)) }
    Add-Warning 'Nested AGENTS.md/CLAUDE.md files add instructions when working in those directories. Make sure they don''t contradict the root.'
} else {
    Write-Output '  (none)'
}
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Skills (descriptions are always visible; bodies load on demand) =='
$skillCount = 0; $descTotal = 0; $names = [System.Collections.Generic.List[string]]::new()
$skillDirs = @(
    (Join-Path $repo '.github/skills'), (Join-Path $repo '.claude/skills'), (Join-Path $repo '.agents/skills'),
    (Join-Path $ch 'skills'), (Join-Path $userHome '.claude/skills'), (Join-Path $userHome '.agents/skills')
)
foreach ($dir in $skillDirs) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($sub in Get-ChildItem -LiteralPath $dir -Directory | Sort-Object Name) {
        $f = Join-Path $sub.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $skillCount++
        $name = Get-Frontmatter $f 'name'; $desc = Get-Frontmatter $f 'description'
        $dw = @($desc -split '\s+' | Where-Object { $_ }).Count; $descTotal += $dw
        $extra = @(Get-ChildItem -LiteralPath $sub.FullName -Recurse -File | Where-Object Name -ne 'SKILL.md').Count
        Write-Output ('  {0,-28} desc {1,3}w  body {2,5}w  +{3} files  {4}' -f ($name ? $name : '<no name>'), $dw, (Get-WordCount $f), $extra, (Format-Rel $sub.FullName))
        if (-not $name) { Add-Warning "$(Format-Rel $f) has no name in frontmatter." }
        if (-not $desc) { Add-Warning "$(Format-Rel $f) has no description; the model can't tell when to use it." }
        if ($name -and $name -ne $sub.Name) { Add-Warning "Skill name '$name' doesn't match its directory '$($sub.Name)'." }
        $names.Add(($name ? $name : $sub.Name))
    }
}
if ($skillCount -eq 0) { Write-Output '  (none)' }
Write-Output '  -----'
Write-Output "  $skillCount skills, $descTotal words of descriptions"
$dups = @($names | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
if ($dups.Count -gt 0) { Add-Warning "Duplicate skill names (same skill in more than one location): $($dups -join ' ')" }
if ($skillCount -gt 15) { Add-Warning "$skillCount skills is a lot to choose between. Check for overlapping descriptions." }
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Custom agents =='
$found = $false
foreach ($dir in (Join-Path $repo '.github/agents'), (Join-Path $ch 'agents')) {
    foreach ($file in Get-Files $dir '*.agent.md') {
        $found = $true
        Write-Output ('  {0,-28} {1,5}w  tools: {2}  {3}' -f (Get-Frontmatter $file.FullName 'name'), (Get-WordCount $file.FullName), (Get-Frontmatter $file.FullName 'tools'), (Format-Rel $file.FullName))
    }
}
if (-not $found) { Write-Output '  (none)' }
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Hooks =='
$found = $false
foreach ($dir in (Join-Path $repo '.github/hooks'), (Join-Path $ch 'hooks')) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $dir -File -Filter '*.json' | Sort-Object Name) {
        $found = $true
        try {
            $h = (Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable).hooks
            $events = if ($h -and $h.Count) { ($h.Keys | ForEach-Object { "$_ x$(@($h[$_]).Count)" }) -join ', ' } else { '(no hooks)' }
        } catch {
            $events = "INVALID JSON: $($_.Exception.Message)"
            Add-Warning "$(Format-Rel $file.FullName) is not valid JSON; its hooks won't load."
        }
        Write-Output "  $(Format-Rel $file.FullName): $events"
    }
}
if (-not $found) { Write-Output '  (none)' }
if (Test-Path -LiteralPath (Join-Path $repo '.github/hooks')) {
    Write-Output '  Note: repo hooks only load in folders Copilot trusts.'
}
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== MCP servers (tool definitions add to context) =='
$mcp = Join-Path $ch 'mcp-config.json'
if (Test-Path -LiteralPath $mcp) {
    try {
        $s = (Get-Content -LiteralPath $mcp -Raw | ConvertFrom-Json -AsHashtable).mcpServers
        $keys = if ($s) { @($s.Keys) } else { @() }
        Write-Output "  $($keys.Count) configured: $(if ($keys.Count) { $keys -join ', ' } else { '(none)' })"
    } catch {
        Write-Output "  INVALID JSON: $($_.Exception.Message)"
    }
} else {
    Write-Output "  (no $(Format-Rel $mcp))"
}
Write-Output '  Note: the GitHub MCP server and any --additional-mcp-config flags aren''t shown here.'
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Saved tool approvals and cop profile =='
$perm = Join-Path $ch 'permissions-config.json'
if (Test-Path -LiteralPath $perm) {
    $raw = Get-Content -LiteralPath $perm -Raw
    $data = $null
    try { $data = $raw | ConvertFrom-Json -AsHashtable } catch { }
    if ($data -and $data.Count) {
        Write-Output "  $(Format-Rel $perm):"
        ($data | ConvertTo-Json -Depth 20) -split "`n" | Select-Object -First 40 | ForEach-Object { Write-Output "    $_" }
        Add-Warning "$(Format-Rel $perm) holds saved approvals, which persist across sessions. Remove any that cover write tools."
    } else {
        Write-Output "  $(Format-Rel $perm): empty"
    }
} else {
    Write-Output '  no saved approvals'
}
if (Test-Path -LiteralPath (Join-Path $ch 'cop.psd1')) {
    Write-Output '  cop.psd1: present'
} else {
    Write-Output '  cop.psd1: absent (cop will prompt for MCP and custom CLI reads)'
}
Write-Output ''

# ---------------------------------------------------------------------------
Write-Output '== Findings =='
if ($warnings.Count -gt 0) { $warnings | ForEach-Object { Write-Output "  ! $_" } } else { Write-Output '  No issues flagged.' }
Write-Output ''
Write-Output 'Next: start a fresh session in this repo and run /context to see the real starting load.'

<#
Stand-in MCP server for the permission smoke test (tests/smoke.ps1).

Speaks MCP over stdio (newline-delimited JSON-RPC) with two tools:
  getIssue     a read
  createIssue  a write
Every tools/call is appended to the log file named by the first argument. That log is the
ground truth for which tools actually ran.

    pwsh -NoProfile -File fake_mcp.ps1 /path/to/calls.log
#>

$log = $args[0]
$utf8 = [System.Text.UTF8Encoding]::new($false)
$stdin = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), $utf8)
$stdout = [System.IO.StreamWriter]::new([Console]::OpenStandardOutput(), $utf8)
$stdout.AutoFlush = $true

$tools = @(
    [ordered]@{
        name        = 'getIssue'
        description = 'Read an issue by key. Read-only.'
        inputSchema = [ordered]@{ type = 'object'; properties = @{ key = @{ type = 'string' } }; required = @('key') }
    },
    [ordered]@{
        name        = 'createIssue'
        description = 'Create a new issue with the given title.'
        inputSchema = [ordered]@{ type = 'object'; properties = @{ title = @{ type = 'string' } }; required = @('title') }
    }
)

function Send-Reply($id, $result, $err) {
    $msg = [ordered]@{ jsonrpc = '2.0'; id = $id }
    if ($null -ne $err) { $msg.error = $err } else { $msg.result = $result }
    $stdout.WriteLine(($msg | ConvertTo-Json -Depth 20 -Compress))
}

while ($null -ne ($line = $stdin.ReadLine())) {
    if (-not $line.Trim()) { continue }
    $msg = $line | ConvertFrom-Json -AsHashtable
    if (-not $msg.ContainsKey('id')) { continue }   # notification, e.g. notifications/initialized
    $id = $msg.id
    $params = if ($msg.params) { $msg.params } else { @{} }
    switch ($msg.method) {
        'initialize' {
            $version = if ($params.protocolVersion) { $params.protocolVersion } else { '2025-06-18' }
            Send-Reply $id ([ordered]@{
                    protocolVersion = $version
                    capabilities    = @{ tools = @{} }
                    serverInfo      = @{ name = 'fakejira'; version = '0.1' }
                })
        }
        'tools/list' { Send-Reply $id @{ tools = $tools } }
        'tools/call' {
            $argsJson = if ($params.arguments) { $params.arguments | ConvertTo-Json -Compress } else { '{}' }
            Add-Content -LiteralPath $log -Value "$($params.name) $argsJson"
            Send-Reply $id @{ content = @(@{ type = 'text'; text = "$($params.name) ok: $argsJson" }) }
        }
        'ping' { Send-Reply $id @{} }
        default { Send-Reply $id $null @{ code = -32601; message = "method not found: $($msg.method)" } }
    }
}

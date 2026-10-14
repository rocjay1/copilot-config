# cop.psd1 for tests/smoke.ps1: the fake MCP server and fake CLI, in place of a real site.
@{
    ReadTools    = @('fakejira(getIssue)', 'shell(fakedt-read)')
    ResearchDeny = @('fakejira(createIssue)')
}

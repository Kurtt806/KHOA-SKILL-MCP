# Install skills from KHOA-SKILL-MCP into current project.
# Usage:
#   irm https://raw.githubusercontent.com/Kurtt806/KHOA-SKILL-MCP/main/install.ps1 | iex
param([switch]$All)

$ErrorActionPreference = "Stop"
$repo = "https://github.com/Kurtt806/KHOA-SKILL-MCP.git"
$tmp = Join-Path $env:TEMP ("khoa-skills-" + (Get-Random))

git clone --depth 1 $repo $tmp | Out-Null

function Install-To($dest) {
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item -Recurse -Force (Join-Path $tmp "devops") (Join-Path $dest "devops")
  Write-Host "installed -> $dest\devops"
}

Install-To ".opencode\skills"
if ($All) {
  Install-To ".claude\skills"
  Install-To ".agents\skills"
}

Remove-Item -Recurse -Force $tmp
Write-Host "done. verify: Get-Content .opencode\skills\devops\SKILL.md -TotalCount 5"

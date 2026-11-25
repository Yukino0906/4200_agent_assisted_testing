<#
.SYNOPSIS
    Add a user folder and regenerate every user's Claude Code permission settings.

.DESCRIPTION
    users\<name>\.claude\settings.json blocks Claude's edit tools (Edit/Write) on:
      - the shared kit: src, config, tests, examples, docs, data and the root files,
        users\README.md, users\_TEMPLATE, this script;
      - every OTHER user's folder;
      - the user's own data\raw (raw data is append-only) and own .claude folder.
    The list of other users changes whenever someone is added, so the file is
    regenerated for everyone. These rules guard Claude's file tools (and shell
    commands Claude Code recognises); they are not an operating-system permission.

    The file also sets autoMemoryDirectory to users\<name>\.claude-memory. Claude
    Code keys its auto memory by git repository, so without it every user folder
    inside this repository would share one memory. Claude Code honours it once the
    user has trusted the folder (asked on the first session there).

    With -NewUser, the folder is first created from users\_TEMPLATE and the
    placeholders <name> and <Full Name> in README.md, CLAUDE.md and NOTES.md are
    filled in.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File users\sync_users.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File users\sync_users.ps1 -NewUser jane_doe -FullName "Jane Doe"
#>
param(
    [string]$NewUser  = '',
    [string]$FullName = ''
)
$ErrorActionPreference = 'Stop'
$usersDir = $PSScriptRoot
$kit      = Split-Path $usersDir -Parent
$utf8     = New-Object System.Text.UTF8Encoding($false)

function ConvertTo-RulePath([string]$p) {
    # Claude Code matches Windows paths in POSIX form: C:\a\b -> //c/a/b
    $p = $p -replace '\\', '/'
    if ($p -match '^([A-Za-z]):/(.*)$') { return '//' + $Matches[1].ToLower() + '/' + $Matches[2] }
    return $p
}

if ($NewUser) {
    if ($NewUser -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
        throw "User name '$NewUser' must start with a letter and use only letters, digits or _."
    }
    if (-not $FullName) { throw '-FullName is required with -NewUser.' }
    $dst = Join-Path $usersDir $NewUser
    if (Test-Path $dst) { throw "users\$NewUser already exists." }
    Copy-Item -Recurse (Join-Path $usersDir '_TEMPLATE') $dst
    foreach ($f in 'README.md', 'CLAUDE.md', 'NOTES.md') {
        $path = Join-Path $dst $f
        if (Test-Path $path) {
            $t = [IO.File]::ReadAllText($path)
            $t = $t.Replace('<Full Name>', $FullName).Replace('<name>', $NewUser)
            [IO.File]::WriteAllText($path, $t, $utf8)
        }
    }
    Write-Output "created users\$NewUser"
}

$users = @(Get-ChildItem $usersDir -Directory |
    Where-Object { $_.Name -ne '_TEMPLATE' -and $_.Name -match '^[A-Za-z][A-Za-z0-9_]*$' } |
    Select-Object -ExpandProperty Name)

$k = ConvertTo-RulePath $kit
$shared = @('src/**', 'config/**', 'tests/**', 'examples/**', 'docs/**', 'data/**',
            'AGENTS.md', 'HANDOFF.md', 'CLAUDE.md', 'README.md', 'setup_paths.m',
            'check_setup.m', '.gitignore', 'users/README.md', 'users/_TEMPLATE/**',
            'users/sync_users.ps1')

foreach ($u in $users) {
    $deny = New-Object System.Collections.Generic.List[string]
    foreach ($s in $shared) { $deny.Add("Edit($k/$s)") }
    foreach ($o in $users) { if ($o -ne $u) { $deny.Add("Edit($k/users/$o/**)") } }
    $deny.Add("Edit($k/users/$u/data/raw/**)")
    $deny.Add("Edit($k/users/$u/.claude/**)")

    $memory   = (Join-Path (Join-Path $usersDir $u) '.claude-memory') -replace '\\', '/'
    $settings = [ordered]@{
        autoMemoryDirectory = $memory
        permissions         = [ordered]@{ deny = $deny.ToArray() }
    }
    $dir = Join-Path (Join-Path $usersDir $u) '.claude'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    [IO.File]::WriteAllText((Join-Path $dir 'settings.json'), ($settings | ConvertTo-Json -Depth 5), $utf8)
    Write-Output ("settings: users\{0}\.claude\settings.json ({1} deny rules)" -f $u, $deny.Count)
}

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
$ghExecutable = if ($ghCommand) { $ghCommand.Source } else { 'C:\Program Files\GitHub CLI\gh.exe' }
if (-not (Test-Path -LiteralPath $ghExecutable)) {
    throw 'Install GitHub CLI first: winget install --id GitHub.cli --exact'
}

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "Git command failed: git $args" }
}

& $ghExecutable auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
    & $ghExecutable auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { throw 'GitHub authentication failed.' }
}
& $ghExecutable auth setup-git --hostname github.com
if ($LASTEXITCODE -ne 0) { throw 'Could not configure GitHub authentication for Git.' }

$repoJson = & $ghExecutable api repos/leo100410/Flightracker
if ($LASTEXITCODE -ne 0) { throw 'Could not access leo100410/Flightracker.' }
$repository = $repoJson | ConvertFrom-Json
if (-not $repository.permissions.push) { throw 'The signed-in account needs write access to leo100410/Flightracker.' }

$profileJson = & $ghExecutable api user
if ($LASTEXITCODE -ne 0) { throw 'Could not read the signed-in GitHub account.' }
$profile = $profileJson | ConvertFrom-Json

if (-not (Test-Path -LiteralPath '.git')) { Invoke-Git init -b main }
$remotes = Invoke-Git remote
if ($remotes -contains 'origin') {
    $origin = Invoke-Git remote get-url origin
    if ($origin -notin @('https://github.com/leo100410/Flightracker.git', 'https://github.com/leo100410/Flightracker', 'git@github.com:leo100410/Flightracker.git')) {
        throw "Origin points to another repository: $origin"
    }
} else {
    Invoke-Git remote add origin https://github.com/leo100410/Flightracker.git
}

Invoke-Git add .
& git diff --cached --quiet
$diffResult = $LASTEXITCODE
if ($diffResult -eq 1) {
    $authorName = if ($profile.name) { $profile.name } else { $profile.login }
    $authorEmail = "$($profile.id)+$($profile.login)@users.noreply.github.com"
    Invoke-Git -c "user.name=$authorName" -c "user.email=$authorEmail" commit -m 'Add SkyNear flight tracker'
} elseif ($diffResult -ne 0) {
    throw 'Could not inspect staged files.'
}

# A normal push preserves any commits added to GitHub in the meantime.
Invoke-Git push --set-upstream origin HEAD:main
Write-Host 'Uploaded SkyNear to https://github.com/leo100410/Flightracker'

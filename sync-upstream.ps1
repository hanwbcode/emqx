[CmdletBinding()]
param (
    [switch]$BuildDocker,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "    EMQX 5.8 Upstream Sync Tool                           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check current branch
$currentBranch = (git branch --show-current).Trim()
if ($currentBranch -ne "release-58") {
    Write-Host "[!] Switching to branch [release-58]..." -ForegroundColor Yellow
    git checkout release-58
}

# 2. Ensure upstream remote exists
$remotes = git remote
if ($remotes -notcontains "upstream") {
    Write-Host "[*] Adding upstream remote https://github.com/emqx/emqx.git..." -ForegroundColor Green
    git remote add upstream https://github.com/emqx/emqx.git
}

# 3. Fetch upstream release-58
Write-Host "`n[*] Fetching upstream/release-58..." -ForegroundColor Green
git fetch upstream release-58

# 4. Check for new commits
$newCommits = git log HEAD..upstream/release-58 --oneline
if (-not $newCommits) {
    Write-Host "`n[OK] Already up to date! Upstream has no new commits." -ForegroundColor Green
    Write-Host "No sync needed." -ForegroundColor Gray
    exit 0
}

Write-Host "`n[*] Detected new upstream commits:" -ForegroundColor Yellow
$commitCount = ($newCommits | Measure-Object -Line).Lines
Write-Host "Total $commitCount new commits:" -ForegroundColor Yellow
$newCommits | Select-Object -First 10 | ForEach-Object { Write-Host "  -> $_" -ForegroundColor DarkGray }
if ($commitCount -gt 10) {
    Write-Host "  -> ... and $($commitCount - 10) more commits" -ForegroundColor DarkGray
}

# 5. Merge upstream
Write-Host "`n[*] Merging upstream updates into local branch..." -ForegroundColor Green
try {
    git merge upstream/release-58 --no-edit
} catch {
    Write-Host "[!] Handled potential merge conflict..." -ForegroundColor Yellow
}

# 6. Prune upstream workflows, keep only community build
Write-Host "[*] Pruning upstream workflows (keeping only build-community-58.yaml)..." -ForegroundColor Green
$unwantedWorkflows = Get-ChildItem -Path ".github/workflows" -Filter "*.yaml" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "build-community-58.yaml" }
if ($unwantedWorkflows) {
    foreach ($wf in $unwantedWorkflows) {
        git rm -f $wf.FullName 2>$null
    }
}

# 7. Commit if any cleanup changes
$status = git status --porcelain
if ($status) {
    git add .
    git commit -m "chore: prune upstream QA workflows after sync"
}

# 8. Determine whether to trigger build
$shouldTriggerBuild = $false
if ($BuildDocker) {
    $shouldTriggerBuild = $true
} elseif ($NoBuild) {
    $shouldTriggerBuild = $false
} else {
    Write-Host "`n----------------------------------------------------------" -ForegroundColor Cyan
    $answer = Read-Host "Trigger GitHub Actions to build Docker image? (Y/N, default Y)"
    if ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim().ToUpper() -eq "Y") {
        $shouldTriggerBuild = $true
    }
}

if ($shouldTriggerBuild) {
    $dateStr = Get-Date -Format "yyyyMMdd"
    Write-Host "[*] Adding trigger commit (pushdocker)..." -ForegroundColor Green
    git commit --allow-empty -m "pushdocker: sync upstream update ($dateStr)"
}

# 9. Push to origin
Write-Host "`n[*] Pushing to origin/release-58..." -ForegroundColor Green
git push origin release-58

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host " [OK] Sync and push completed successfully!" -ForegroundColor Green
if ($shouldTriggerBuild) {
    Write-Host " Triggered GitHub Actions build. Images will be pushed to:" -ForegroundColor Cyan
    Write-Host "   ghcr.io/hanwbcode/emqx:5.8-latest" -ForegroundColor Yellow
    Write-Host "   ghcr.io/hanwbcode/emqx:5.8-$(Get-Date -Format 'yyyyMMdd')" -ForegroundColor Yellow
}
Write-Host "==========================================================" -ForegroundColor Green

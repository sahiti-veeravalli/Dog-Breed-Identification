<#
PowerShell script to:
 - Track a large model file with Git LFS
 - Migrate repository history to LFS for that file
 - Commit and force-push to remote `origin` branch `main`
 - Create a GitHub release and upload the model as a release asset

USAGE (recommended):
  Set environment variable GITHUB_TOKEN to a Personal Access Token with `repo` scope, then run:
    pwsh -ExecutionPolicy Bypass -File .\scripts\push_and_release.ps1 -RepoUrl "https://github.com/sahiti-veeravalli/Dog-Breed-Identification.git"

Or pass token directly (less secure):
    pwsh -ExecutionPolicy Bypass -File .\scripts\push_and_release.ps1 -Pat "ghp_xxx" -RepoUrl "https://github.com/owner/repo.git"
#>

param(
    [string]$RepoUrl = '',
    [string]$Pat = $env:GITHUB_TOKEN,
    [string]$AssetPath = 'model/hybrid_dog_breed_classifier.keras',
    [string]$Tag = "v1.0.0-$(Get-Date -Format yyyyMMddHHmm)",
    [string]$ReleaseName = 'IOMP updated course work',
    [string]$ReleaseBody = 'Automated release created by script.'
)

function Run-Command {
    param([string]$Cmd)
    Write-Host "-> $Cmd"
    $proc = Start-Process -FilePath pwsh -ArgumentList "-NoProfile","-Command","$Cmd" -NoNewWindow -PassThru -Wait -RedirectStandardOutput tmp_out.txt -RedirectStandardError tmp_err.txt
    $stdout = Get-Content tmp_out.txt -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content tmp_err.txt -Raw -ErrorAction SilentlyContinue
    Remove-Item tmp_out.txt,tmp_err.txt -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) {
        Write-Error "Command failed: $Cmd`nSTDERR:`n$stderr"
        throw "Command failed"
    }
    return $stdout
}

# Validate PAT
if (-not $Pat) {
    Write-Host 'ERROR: No GitHub token provided. Set GITHUB_TOKEN env var or provide -Pat parameter.' -ForegroundColor Red
    exit 1
}

Write-Host 'Step 1: Ensure inside a git repo'
if (-not (Test-Path .git)) {
    git init
}

# Determine repo URL
if (-not $RepoUrl) {
    $RepoUrl = git config --get remote.origin.url 2>$null
    if (-not $RepoUrl) {
        Write-Host 'No remote origin found and no -RepoUrl provided. Please provide -RepoUrl.' -ForegroundColor Red
        exit 1
    }
}

# Parse owner/repo from URL
if ($RepoUrl -match 'github.com[:/]+([^/]+)/([^/.]+)') {
    $Owner = $Matches[1]
    $Repo = $Matches[2]
} else {
    Write-Host "Cannot parse owner/repo from $RepoUrl" -ForegroundColor Red
    exit 1
}

Write-Host "Target repository: $Owner/$Repo"

Write-Host 'Step 2: Track asset with Git LFS'
git lfs track "$AssetPath" || Write-Host 'git lfs track returned non-zero (continuing)'
if (Test-Path .gitattributes) { git add .gitattributes }

# Commit tracking file if needed
try {
    git commit -m "Track large model with Git LFS" -- .gitattributes 2>$null | Out-Null
} catch {
    Write-Host 'No .gitattributes changes to commit.'
}

# Migrate history to move the file into LFS
Write-Host 'Step 3: Migrate history to Git LFS for the asset (this may take a while)'
git lfs migrate import --include="$AssetPath" --include-ref=refs/heads/main --yes

# Commit remaining changes and push
Write-Host 'Step 4: Commit and push to remote (force)'
try {
    git add -A
    git commit -m "IOMP updated course work" || Write-Host 'Nothing to commit.'
} catch {
    Write-Host 'Commit step failed or nothing to commit.'
}

# Ensure remote exists
$remote = git remote get-url origin 2>$null
if (-not $remote) {
    git remote add origin $RepoUrl
}

# Ensure branch name main
git branch -M main

Write-Host 'Pushing to remote origin/main (force)'
git push -u origin main --force

# Create GitHub release via API
Write-Host 'Step 5: Create GitHub release and upload asset'
$releaseApi = "https://api.github.com/repos/$Owner/$Repo/releases"
$body = @{ tag_name = $Tag; name = $ReleaseName; body = $ReleaseBody; draft = $false; prerelease = $false } | ConvertTo-Json
$headers = @{ Authorization = "token $Pat"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'pwsh-script' }

$release = Invoke-RestMethod -Method Post -Uri $releaseApi -Headers $headers -Body $body -ContentType 'application/json'
Write-Host "Created release id: $($release.id) tag: $($release.tag_name)"

# Upload asset
if (-not (Test-Path $AssetPath)) {
    Write-Host "Asset $AssetPath not found; skipping upload." -ForegroundColor Yellow
    exit 0
}

$uploadUrl = $release.upload_url -replace '\{.*',''
$fileName = [System.IO.Path]::GetFileName($AssetPath)
$uploadUri = "$uploadUrl?name=$fileName"
Write-Host "Uploading asset to $uploadUri"

# Use Invoke-WebRequest for binary upload
Invoke-WebRequest -Uri $uploadUri -Method Post -InFile $AssetPath -Headers $headers -ContentType 'application/octet-stream'
Write-Host 'Asset upload completed.'

Write-Host 'All done.'

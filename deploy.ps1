# deploy.ps1 — EQ Cards web build + Netlify deploy
#
# Set these Windows user environment variables once (they persist across
# sessions and are never stored in source control):
#
#   [System.Environment]::SetEnvironmentVariable("EQ_CARDS_SUPABASE_URL",       "https://jvknxcmbtrfnxfrwfimn.supabase.co", "User")
#   [System.Environment]::SetEnvironmentVariable("EQ_CARDS_SUPABASE_ANON_KEY",  "<key from Supabase dashboard>",             "User")
#   [System.Environment]::SetEnvironmentVariable("EQ_CARDS_POSTHOG_API_KEY",    "<key>",                                     "User")
#   [System.Environment]::SetEnvironmentVariable("EQ_CARDS_POSTHOG_HOST",       "https://eu.i.posthog.com",                  "User")
#   [System.Environment]::SetEnvironmentVariable("EQ_CARDS_SENTRY_DSN",         "<dsn or empty>",                            "User")
#
# Usage:
#   .\deploy.ps1            # full build + deploy
#   .\deploy.ps1 -SkipBuild # skip flutter build (re-deploy last build)

param(
    [switch]$SkipBuild
)

Set-Location $PSScriptRoot

# ── Read keys from environment ────────────────────────────────────────────────
$SupabaseUrl      = $env:EQ_CARDS_SUPABASE_URL
$SupabaseAnonKey  = $env:EQ_CARDS_SUPABASE_ANON_KEY
$PosthogKey       = $env:EQ_CARDS_POSTHOG_API_KEY
$PosthogHost      = $env:EQ_CARDS_POSTHOG_HOST
$SentryDsn        = if ($env:EQ_CARDS_SENTRY_DSN) { $env:EQ_CARDS_SENTRY_DSN } else { "" }
# SENTRY_AUTH_TOKEN: set via [System.Environment]::SetEnvironmentVariable("EQ_CARDS_SENTRY_AUTH_TOKEN", "<token>", "User")
$SentryAuthToken  = $env:EQ_CARDS_SENTRY_AUTH_TOKEN

if (-not $SupabaseUrl -or -not $SupabaseAnonKey) {
    Write-Error "EQ_CARDS_SUPABASE_URL and EQ_CARDS_SUPABASE_ANON_KEY must be set as user environment variables."
    Write-Host  "Run: [System.Environment]::SetEnvironmentVariable('EQ_CARDS_SUPABASE_ANON_KEY', '<key>', 'User')"
    exit 1
}

# ── Flutter build ─────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Host "`n==> Building Flutter web (release)..." -ForegroundColor Cyan
    flutter build web --release --no-web-resources-cdn --source-maps `
        "--dart-define=SUPABASE_URL=$SupabaseUrl" `
        "--dart-define=SUPABASE_ANON_KEY=$SupabaseAnonKey" `
        "--dart-define=SENTRY_DSN=$SentryDsn" `
        "--dart-define=POSTHOG_API_KEY=$PosthogKey" `
        "--dart-define=POSTHOG_HOST=$PosthogHost"

    if ($LASTEXITCODE -ne 0) {
        Write-Error "flutter build failed - deploy aborted."
        exit 1
    }

    # ── Upload source maps to Sentry ──────────────────────────────────────────
    # Requires sentry-cli installed and EQ_CARDS_SENTRY_AUTH_TOKEN set.
    # Skipped silently if token is absent.
    if ($SentryAuthToken -and (Get-Command sentry-cli -ErrorAction SilentlyContinue)) {
        Write-Host "`n==> Uploading source maps to Sentry..." -ForegroundColor Cyan
        $env:SENTRY_AUTH_TOKEN = $SentryAuthToken
        sentry-cli sourcemaps upload `
            --org eq-solutions `
            --project eq-cards `
            build/web
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Sentry source map upload failed — continuing deploy anyway."
        }
    } else {
        Write-Host "`n(skipping Sentry source map upload — sentry-cli or EQ_CARDS_SENTRY_AUTH_TOKEN not found)" -ForegroundColor DarkGray
    }
}

# ── Netlify deploy ────────────────────────────────────────────────────────────
Write-Host "`n==> Deploying to Netlify (cards.eq.solutions)..." -ForegroundColor Cyan
netlify deploy --prod --no-build --dir=build/web --site=c1bf4b4d-3131-4dd6-977f-2c0dd5cc4d72

if ($LASTEXITCODE -ne 0) {
    Write-Error "Netlify deploy failed."
    exit 1
}

Write-Host "`nDeployed to https://cards.eq.solutions" -ForegroundColor Green

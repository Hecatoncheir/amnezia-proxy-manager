param([string]$Compiler = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("amnezia-update-check-" + [guid]::NewGuid())
$installation = Join-Path $testRoot 'installed'
$baseline = Join-Path $testRoot 'baseline'
$journal = Join-Path $testRoot 'journal.json'
$testId = 'AmneziaProxyManager.UpdateTest.' + [guid]::NewGuid()
New-Item -ItemType Directory -Path $testRoot | Out-Null
Write-Output "Журналы проверки: $testRoot"
if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "WINDOWS_UPDATE_LOG_DIR=$testRoot" }

function Build-App([string]$Target) {
    Push-Location (Join-Path $root 'apps/desktop')
    try {
        flutter build windows --release --target $Target
        if ($LASTEXITCODE -ne 0) { throw 'Ошибка сборки Flutter' }
    } finally { Pop-Location }
}

function Build-Setup([string]$Bundle, [string]$Name, [string]$Version) {
    & $Compiler "/DAppId=$testId" "/DAppBundle=$Bundle" "/DAppVersion=$Version" "/DAppNumericVersion=$Version" "/O$testRoot" "/F$Name" (Join-Path $PSScriptRoot 'windows.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Ошибка компиляции Setup' }
}

function Installed-Processes {
    Get-Process amnezia_proxy_manager -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq (Join-Path $installation 'amnezia_proxy_manager.exe') }
}

try {
    Build-App 'tool/window_placement_probe.dart'
    $bundle = Join-Path $root 'apps/desktop/build/windows/x64/runner/Release'
    $probe = Join-Path $bundle 'amnezia_proxy_manager.exe'
    foreach ($mode in @('write', 'read')) {
        $report = Join-Path $testRoot "window-$mode.json"
        $process = Start-Process -FilePath $probe -ArgumentList @($mode, "`"$report`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot "window-$mode.stdout.log") -RedirectStandardError (Join-Path $testRoot "window-$mode.stderr.log")
        if (!$process.WaitForExit(30000)) {
            Stop-Process -Id $process.Id
            throw 'Проверка положения окна зависла'
        }
        if ($process.ExitCode -ne 0) { throw 'Ошибка проверки положения окна' }
    }
    if ((Get-Content (Join-Path $testRoot 'window-write.json') -Raw) -ne
        (Get-Content (Join-Path $testRoot 'window-read.json') -Raw)) {
        throw 'Геометрия окна изменилась после перезапуска'
    }
    Write-Output 'Геометрия окна восстановлена после настоящего перезапуска.'
    Build-App 'tool/update_install_probe.dart'
    Copy-Item -LiteralPath $bundle -Destination $baseline -Recurse
    Build-Setup $baseline 'baseline' '0.0.1'
    Build-App 'lib/main.dart'
    $versionLine = Select-String -Path (Join-Path $root 'apps/desktop/pubspec.yaml') -Pattern '^version: (\d+\.\d+\.\d+)'
    $candidateVersion = $versionLine.Matches[0].Groups[1].Value
    Build-Setup $bundle 'candidate' $candidateVersion
    $setup = Start-Process -FilePath (Join-Path $testRoot 'baseline.exe') -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', "/DIR=`"$installation`"", "/LOG=`"$testRoot/baseline.log`"") -WindowStyle Hidden -Wait -PassThru
    if ($setup.ExitCode -ne 0) { throw "Ошибка начальной установки: $($setup.ExitCode)" }
    $sentinel = Join-Path $installation 'user-data-sentinel.txt'
    Set-Content -LiteralPath $sentinel -Value 'preserve'
    $executable = Join-Path $installation 'amnezia_proxy_manager.exe'
    Start-Process -FilePath $executable -ArgumentList @("`"$testRoot/candidate.exe`"", "`"$journal`"") -WindowStyle Hidden | Out-Null
    $expected = (Get-FileHash (Join-Path $bundle 'amnezia_proxy_manager.exe')).Hash
    $expectedCode = (Get-FileHash (Join-Path $bundle 'data/app.so')).Hash
    $deadline = (Get-Date).AddSeconds(90)
    $passed = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (!(Test-Path -LiteralPath $journal)) { continue }
        $phase = (Get-Content -LiteralPath $journal -Raw | ConvertFrom-Json).phase
        if ($phase -eq 'failed') { throw 'Контроллер отклонил установку' }
        if ($phase -ne 'exit') { continue }
        if ((Get-FileHash -LiteralPath $executable).Hash -ne $expected) { continue }
        if ((Get-FileHash -LiteralPath (Join-Path $installation 'data/app.so')).Hash -ne $expectedCode) { continue }
        if (!(Installed-Processes)) { continue }
        if ((Get-Content -LiteralPath $sentinel).Trim() -ne 'preserve') { throw 'Потеря данных' }
        $passed = $true
        break
    }
    if (!$passed) { throw 'Обновление или перезапуск не завершились за 90 секунд' }
    Write-Output 'Проверено: установленная копия вызвала контроллер, Setup заменил файлы, приложение перезапущено, посторонний файл сохранён.'
} finally {
    Installed-Processes | Stop-Process -Force
    $uninstaller = Join-Path $installation 'unins000.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -WindowStyle Hidden -Wait
    }
    # Каталог с журналами остаётся для разбора; проверка использует отдельный AppId.
}

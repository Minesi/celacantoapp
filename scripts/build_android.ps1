Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

flutter clean
flutter pub get
flutter build apk --release --target-platform android-arm64
flutter build appbundle --release

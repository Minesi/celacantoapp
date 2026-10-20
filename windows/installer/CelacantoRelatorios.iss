; Instalador do Celacanto Relatorios.
; Compile com o Inno Setup Compiler (ISCC.exe) depois de executar flutter build windows --release.
#define AppName "Celacanto Relatorios"
#define AppVersion "1.0.0"
#define AppPublisher "Celacanto"
#define AppExeName "celacantoapp.exe"

[Setup]
AppId={{B9E0B2E8-2C40-4A90-9D77-CEB0B7D9A001}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\Celacanto Relatorios
DefaultGroupName={#AppName}
OutputDir=..\..\build\windows\installer
OutputBaseFilename=CelacantoRelatorios-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent

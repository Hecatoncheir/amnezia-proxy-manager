#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef AppNumericVersion
  #define AppNumericVersion AppVersion
#endif
#ifndef AppId
  #define AppId "{{8C41D684-5599-4538-B607-19EE8EE417F4}"
#endif
#ifndef AppBundle
  #define AppBundle "..\apps\desktop\build\windows\x64\runner\Release"
#endif
[Setup]
AppId={#AppId}
AppName=Amnezia Proxy Manager
AppVersion={#AppVersion}
VersionInfoVersion={#AppNumericVersion}
AppPublisher=Hecatoncheir
AppPublisherURL=https://github.com/Hecatoncheir/amnezia-proxy-manager
DefaultDirName={localappdata}\Programs\AmneziaProxyManager
DefaultGroupName=AmneziaProxyManager
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=AmneziaProxyManager-Setup-windows-x64
SetupIconFile=..\apps\desktop\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\amnezia_proxy_manager.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
[Files]
Source: "{#AppBundle}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\AmneziaProxyManager"; Filename: "{app}\amnezia_proxy_manager.exe"
Name: "{autodesktop}\AmneziaProxyManager"; Filename: "{app}\amnezia_proxy_manager.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\amnezia_proxy_manager.exe"; Description: "{cm:LaunchProgram,AmneziaProxyManager}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\amnezia_proxy_manager.exe"; Flags: nowait; Check: ShouldRelaunch

[Code]
function ShouldRelaunch: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/RELAUNCH') = 0 then
      Result := True;
end;

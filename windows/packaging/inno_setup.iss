#ifndef AppVersion
  #define AppVersion "0.0.1"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{8E9B7B2A-61D4-47F2-9C7A-7E2A5C4D1001}
AppName=Koneko
AppVersion={#AppVersion}
AppPublisher=Koneko
DefaultDirName={autopf}\Koneko
DefaultGroupName=Koneko
AllowNoIcons=yes
OutputDir={#OutputDir}
OutputBaseFilename=Koneko-{#AppVersion}-windows-x64-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Koneko.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Koneko"; Filename: "{app}\Koneko.exe"
Name: "{autodesktop}\Koneko"; Filename: "{app}\Koneko.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Koneko.exe"; Description: "{cm:LaunchProgram,Koneko}"; Flags: nowait postinstall skipifsilent

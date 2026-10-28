; Inno Setup script for the BookIt Windows installer (built in CI).
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{6F1B7C3E-8D2A-4B9E-A7C1-B00C1E7A0001}
AppName=BookIt
AppVersion={#AppVersion}
AppPublisher=BookIt contributors
AppPublisherURL=https://github.com/MohammedAnasAsif/BookIt
DefaultDirName={autopf}\BookIt
DefaultGroupName=BookIt
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=BookIt-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#SourceDir}\..\..\..\..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bookit.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BookIt"; Filename: "{app}\bookit.exe"
Name: "{autodesktop}\BookIt"; Filename: "{app}\bookit.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\bookit.exe"; Description: "{cm:LaunchProgram,BookIt}"; Flags: nowait postinstall skipifsilent

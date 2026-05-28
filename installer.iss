[Setup]
AppName=ChronosTv
AppVersion=1.0
DefaultDirName={commonpf}\ChronosTv
DefaultGroupName=ChronosTv
OutputDir=.
OutputBaseFilename=ChronosTv
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=assets\icons\babu.ico
WizardStyle=modern

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\ChronosTv"; Filename: "{app}\ChronosTv.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\ChronosTv"; Filename: "{app}\ChronosTv.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\ChronosTv.exe"; Description: "Lancer ChronosTv"; Flags: nowait postinstall skipifsilent

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

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\ChronosTv.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\ChronosTv"; Filename: "{app}\ChronosTv.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\ChronosTv"; Filename: "{app}\ChronosTv.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\ChronosTv.exe"; Description: "Lancer ChronosTv"; Flags: nowait postinstall skipifsilent

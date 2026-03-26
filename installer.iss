[Setup]
AppName=C-MAPENDO
AppVersion=1.0
DefaultDirName={commonpf}\C-MAPENDO
DefaultGroupName=C-MAPENDO
OutputDir=.
OutputBaseFilename=C-MAPENDO
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-MAPENDO.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\C-MAPENDO"; Filename: "{app}\C-MAPENDO.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\C-MAPENDO"; Filename: "{app}\C-MAPENDO.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\C-MAPENDO.exe"; Description: "Lancer C-MAPENDO"; Flags: nowait postinstall skipifsilent

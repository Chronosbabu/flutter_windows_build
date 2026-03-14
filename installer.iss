[Setup]
AppName=C-TCC_MAPENDO
AppVersion=1.0
DefaultDirName={commonpf}\C-TCC_MAPENDO
DefaultGroupName=C-TCC_MAPENDO
OutputDir=.
OutputBaseFilename=C-TCC_MAPENDO
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-TCC_MAPENDO.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\C-TCC_MAPENDO"; Filename: "{app}\C-TCC_MAPENDO.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\C-TCC_MAPENDO"; Filename: "{app}\C-TCC_MAPENDO.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\C-TCC_MAPENDO.exe"; Description: "Lancer C-TCC_MAPENDO"; Flags: nowait postinstall skipifsilent

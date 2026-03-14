[Setup]
AppName=C-Secondaire
AppVersion=1.0
DefaultDirName={commonpf}\C-Secondaire
DefaultGroupName=C-Secondaire
OutputDir=.
OutputBaseFilename=C-Secondaire
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-Secondaire.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\C-Secondaire"; Filename: "{app}\C-Secondaire.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\C-Secondaire"; Filename: "{app}\C-Secondaire.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\C-Secondaire.exe"; Description: "Lancer C-Secondaire"; Flags: nowait postinstall skipifsilent

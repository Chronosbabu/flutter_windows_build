[Setup]
AppName=C-SECONDAIRE
AppVersion=1.0
DefaultDirName={commonpf}\C-SECONDAIRE
DefaultGroupName=C-SECONDAIRE
OutputDir=.
OutputBaseFilename=C-SECONDAIRE
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-SECONDAIRE.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\C-SECONDAIRE"; Filename: "{app}\C-SECONDAIRE.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\C-SECONDAIRE"; Filename: "{app}\C-SECONDAIRE.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\C-SECONDAIRE.exe"; Description: "Lancer C-SECONDAIRE"; Flags: nowait postinstall skipifsilent

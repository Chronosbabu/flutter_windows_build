[Setup]
AppName=C-Primaire-maternelle
AppVersion=1.0
DefaultDirName={commonpf}\C-Primaire-maternelle
DefaultGroupName=C-Primaire-maternelle
OutputDir=.
OutputBaseFilename=C-Primaire-maternelle
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-Primaire-maternelle.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\C-Primaire-maternelle"; Filename: "{app}\C-Primaire-maternelle.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\C-Primaire-maternelle"; Filename: "{app}\C-Primaire-maternelle.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\C-Primaire-maternelle.exe"; Description: "Lancer C-Primaire-maternelle"; Flags: nowait postinstall skipifsilent

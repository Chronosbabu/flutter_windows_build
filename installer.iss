[Setup]
AppName=C-SchoolApp
AppVersion=1.0
DefaultDirName={commonpf}\C-SchoolApp
DefaultGroupName=C-SchoolApp
OutputDir=.
OutputBaseFilename=C-SchoolApp
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-SchoolApp.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\C-SchoolApp"; Filename: "{app}\C-SchoolApp.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\C-SchoolApp"; Filename: "{app}\C-SchoolApp.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\C-SchoolApp.exe"; Description: "Lancer C-SchoolApp"; Flags: nowait postinstall skipifsilent


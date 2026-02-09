[Setup]
AppName=Gestion de Finance
AppVersion=1.0
DefaultDirName={commonpf}\Gestion de Finance
DefaultGroupName=Gestion de Finance
OutputDir=.
OutputBaseFilename=Gestion-de-Finance-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

; Icône du setup ET de l’application
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\gestion_de_finance.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "babu.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Raccourci bureau avec icône personnalisée
Name: "{commondesktop}\Gestion de Finance"; Filename: "{app}\gestion_de_finance.exe"; IconFilename: "{app}\babu.ico"

; Raccourci menu démarrer avec icône
Name: "{group}\Gestion de Finance"; Filename: "{app}\gestion_de_finance.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\gestion_de_finance.exe"; Description: "Lancer Gestion de Finance"; Flags: nowait postinstall skipifsilent


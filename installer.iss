[Setup]
AppName=EDUPAY-DRC Accès
AppVersion=1.0
DefaultDirName={commonpf}\EDUPAY-DRC Accès
DefaultGroupName=EDUPAY-DRC Accès
OutputDir=.
OutputBaseFilename=EDUPAY-DRC-Acces
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=assets\icons\babu.ico
WizardStyle=modern

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\EDUPAY-DRC Accès"; Filename: "{app}\EDUPAY-DRC-Acces.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\EDUPAY-DRC Accès"; Filename: "{app}\EDUPAY-DRC-Acces.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\EDUPAY-DRC-Acces.exe"; Description: "Lancer EDUPAY-DRC Accès"; Flags: nowait postinstall skipifsilent
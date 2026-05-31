[Setup]
AppName=PayScol
AppVersion=1.0
DefaultDirName={commonpf}\PayScol
DefaultGroupName=PayScol
OutputDir=.
OutputBaseFilename=PayScol
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=assets\icons\babu.ico
WizardStyle=modern

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\PayScol"; Filename: "{app}\PayScol.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\PayScol"; Filename: "{app}\PayScol.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\PayScol.exe"; Description: "Lancer PayScol"; Flags: nowait postinstall skipifsilent
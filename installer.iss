[Setup]
AppName=payscolclient
AppVersion=1.0
DefaultDirName={commonpf}\payscolclient
DefaultGroupName=payscolclient
OutputDir=.
OutputBaseFilename=payscolclient
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=assets\icons\babu.ico
WizardStyle=modern

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\payscolclient"; Filename: "{app}\payscolclient.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\payscolclient"; Filename: "{app}\payscolclient.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\payscolclient.exe"; Description: "Lancer payscolclient"; Flags: nowait postinstall skipifsilent
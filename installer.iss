[Setup]
AppName=EDUPAY-DRC
AppVersion=1.0.0
AppPublisher=EDUPAY-DRC
DefaultDirName={autopf}\EDUPAY-DRC
DefaultGroupName=EDUPAY-DRC
OutputDir=.
OutputBaseFilename=EDUPAY-DRC-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
SetupIconFile=assets\icons\babu.ico
UninstallDisplayIcon={app}\babu.ico

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\EDUPAY-DRC"; Filename: "{app}\EDUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\EDUPAY-DRC"; Filename: "{app}\EDUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\EDUPAY-DRC.exe"; Description: "Lancer EDUPAY-DRC"; Flags: nowait postinstall skipifsilent
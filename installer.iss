```ini
[Setup]
AppName=EDUPAY-DRC
AppVersion=1.0
DefaultDirName={commonpf}\EDUPAY-DRC
DefaultGroupName=EDUPAY-DRC
OutputDir=.
OutputBaseFilename=EDUPAY-DRC
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=assets\icons\babu.ico
WizardStyle=modern

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\EDUPAY-DRC"; Filename: "{app}\EDUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\EDUPAY-DRC"; Filename: "{app}\EDUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"

[Run]
Filename: "{app}\EDUPAY-DRC.exe"; Description: "Lancer EDUPAY-DRC"; Flags: nowait postinstall skipifsilent
```

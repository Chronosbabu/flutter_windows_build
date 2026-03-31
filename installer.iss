[Setup]
AppName=C-MAPENDO
AppVersion=1.0
DefaultDirName={commonpf}\C-MAPENDO
DefaultGroupName=C-MAPENDO
OutputDir=.
OutputBaseFilename=C-MAPENDO
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=babu.ico

[Files]
Source: "build\windows\x64\runner\Release\C-MAPENDO.exe"; DestDir: "{app}"
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs

[Icons]
Name: "{commondesktop}\C-MAPENDO"; Filename: "{app}\C-MAPENDO.exe"
Name: "{group}\C-MAPENDO"; Filename: "{app}\C-MAPENDO.exe"

[Run]
Filename: "{app}\C-MAPENDO.exe"; Description: "Lancer C-MAPENDO"; Flags: nowait postinstall skipifsilent

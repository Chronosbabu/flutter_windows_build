[Setup]
AppName=C-SchoolApp
AppVersion=1.0
DefaultDirName={commonpf}\C-SchoolApp
DefaultGroupName=C-SchoolApp
OutputDir=.
OutputBaseFilename=C-SchoolApp-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\c_schollapp.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{commondesktop}\C-SchoolApp"; Filename: "{app}\c_schollapp.exe"
Name: "{group}\C-SchoolApp"; Filename: "{app}\c_schollapp.exe"

[Run]
Filename: "{app}\c_schollapp.exe"; Description: "Lancer C-SchoolApp"; Flags: nowait postinstall skipifsilent

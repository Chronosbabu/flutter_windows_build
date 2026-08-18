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
; ⚡ NOUVEAU — empêche l'installation sur un Windows trop ancien pour
; Flutter (Windows 7/8 ne sont plus supportés par Flutter Windows). Sans
; ça, l'installateur se lance "avec succès" sur un vieux PC mais
; l'application plante ensuite à l'ouverture, ce qui est bien plus
; déroutant pour l'utilisateur qu'un message clair au moment de
; l'installation.
MinVersion=10.0.17763
; ⚡ NOUVEAU — message clair si le setup n'arrive vraiment pas à
; s'installer sur cette machine, au lieu d'un échec silencieux.
DisableWelcomePage=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion
; ⚡ NOUVEAU — le Visual C++ Redistributable (2015-2022, x64), téléchargé
; automatiquement par le workflow GitHub Actions avant la compilation de
; l'installateur (voir windows-build.yml). C'est LA cause n°1 des
; applications Flutter Windows qui "ne s'ouvrent pas" ou affichent une
; erreur du type "VCRUNTIME140.dll est introuvable" sur un PC qui n'a
; jamais eu Visual Studio, un jeu, ou un autre logiciel l'ayant déjà
; installé. On l'embarque directement dans le setup pour ne JAMAIS
; dépendre d'une connexion internet au moment de l'installation chez le
; client (contrairement à une simple redirection web).
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{commondesktop}\EDUPAY-DRC"; Filename: "{app}\EDUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\EDUPAY-DRC"; Filename: "{app}\EDUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"

[Run]
; ⚡ NOUVEAU — installe le VC++ Redistributable AVANT de lancer
; l'application, mais UNIQUEMENT s'il n'est pas déjà présent sur la
; machine (voir VCRedistNeedsInstall dans [Code] plus bas). /install
; /quiet /norestart = totalement silencieux, aucune fenêtre ni question
; posée à l'utilisateur, et on ne force jamais un redémarrage
; automatique du PC.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installation des composants requis (Visual C++)..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated
Filename: "{app}\EDUPAY-DRC.exe"; Description: "Lancer EDUPAY-DRC"; Flags: nowait postinstall skipifsilent

[Code]
// ==========================================================================
// ⚡ NOUVEAU — Vérifie si le Visual C++ Redistributable 2015-2022 (x64) est
// déjà installé sur cette machine, en lisant la clé de registre officielle
// que Microsoft écrit lui-même lors de son installation. Si la clé existe
// et que "Installed" = 1, on ne réinstalle rien (gain de temps, pas de
// popup inutile). Sinon, on l'installe silencieusement.
// ==========================================================================
function VCRedistNeedsInstall(): Boolean;
var
  Installed: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', Installed) then
  begin
    if Installed = 1 then
      Result := False;
  end;
end;
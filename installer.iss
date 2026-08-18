[Setup]
AppName=EDUPAY-DRC-Acces
AppVersion=1.0.0
AppPublisher=EDUPAY-DRC-Acces
DefaultDirName={autopf}\EDUPAY-DRC-Acces
DefaultGroupName=EDUPAY-DRC-Acces
OutputDir=.
OutputBaseFilename=EDUPAY-DRC-Acces-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
SetupIconFile=assets\icons\babu.ico
UninstallDisplayIcon={app}\babu.ico
; empêche l'installation sur un Windows trop ancien pour Flutter
; (Windows 7/8 ne sont plus supportés par Flutter Windows). Sans ça,
; l'installateur se lance "avec succès" sur un vieux PC mais l'application
; plante ensuite à l'ouverture, ce qui est bien plus déroutant pour
; l'utilisateur qu'un message clair au moment de l'installation.
MinVersion=10.0.17763
DisableWelcomePage=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "assets\icons\babu.ico"; DestDir: "{app}"; DestName: "babu.ico"; Flags: ignoreversion
; Visual C++ Redistributable (2015-2022, x64), téléchargé automatiquement
; par le workflow GitHub Actions avant la compilation de l'installateur
; (voir windows-build.yml). C'est LA cause n°1 des applications Flutter
; Windows qui "ne s'ouvrent" pas ou affichent "VCRUNTIME140.dll est
; introuvable" sur un PC qui n'a jamais eu Visual Studio, un jeu, ou un
; autre logiciel l'ayant déjà installé. On l'embarque directement dans le
; setup pour ne JAMAIS dépendre d'une connexion internet à l'installation
; chez le client.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{commondesktop}\EDUPAY-DRC-Acces"; Filename: "{app}\EDUPAY-DRC-Acces.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\EDUPAY-DRC-Acces"; Filename: "{app}\EDUPAY-DRC-Acces.exe"; IconFilename: "{app}\babu.ico"

[Run]
; Installe le VC++ Redistributable AVANT de terminer l'installation, mais
; UNIQUEMENT s'il n'est pas déjà présent (voir VCRedistNeedsInstall dans
; [Code] plus bas). /install /quiet /norestart = totalement silencieux,
; aucune fenêtre ni question posée à l'utilisateur, et on ne force jamais
; un redémarrage automatique du PC.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installation des composants requis (Visual C++)..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated

; ⚡⚡⚡ CORRIGÉ — L'ANCIENNE ligne qui lançait directement l'app ici
; (Filename: "{app}\EDUPAY-DRC-Acces.exe" ... Flags: postinstall) a été
; SUPPRIMÉE d'ici. Raison : PrivilegesRequired=admin (nécessaire pour
; installer vc_redist en silencieux) fait tourner TOUT l'installateur en
; tant qu'administrateur. Un "Filename:" placé directement dans [Run]
; hérite donc de ces droits admin — l'app se lançait ÉLEVÉE une seule
; fois (juste après l'installation), alors que tous les lancements
; suivants (icône bureau, menu Démarrer) tournent en utilisateur normal.
;
; Ce changement de contexte entre le tout premier lancement et les
; suivants est exactement ce qui causait la perte apparente de session :
; l'utilisateur retombait sur RecoveryScreen au lieu de l'écran principal
; après avoir fermé/rouvert l'application normalement, alors que tout
; fonctionnait parfaitement pendant la session elle-même.
;
; Le lancement automatique en fin d'installation est conservé (voir
; CurStepChanged ci-dessous), mais réalisé CORRECTEMENT via
; ShellExecAsOriginalUser, qui exécute l'app avec les droits de
; l'utilisateur connecté d'origine (non-élevé) — exactement le même
; contexte que tous les lancements suivants depuis l'icône du bureau.
; Plus jamais de contexte mixte élevé/non-élevé entre deux lancements.

[Code]
// ==========================================================================
// Vérifie si le Visual C++ Redistributable 2015-2022 (x64) est déjà
// installé sur cette machine, en lisant la clé de registre officielle que
// Microsoft écrit lui-même lors de son installation. Si la clé existe et
// que "Installed" = 1, on ne réinstalle rien (gain de temps, pas de popup
// inutile). Sinon, on l'installe silencieusement.
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

// ==========================================================================
// ⚡⚡⚡ NOUVEAU — Lance l'application à la toute fin de l'installation,
// mais EN TANT QUE L'UTILISATEUR D'ORIGINE (non-élevé), même si
// l'installateur tourne lui-même en administrateur.
// ShellExecAsOriginalUser est une fonction NATIVE d'Inno Setup, prévue
// précisément pour ce cas très courant : elle évite de recréer le bug de
// contexte élevé/non-élevé décrit ci-dessus, tout en conservant le
// confort d'un lancement automatique juste après l'installation.
// ==========================================================================
procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorCode: Integer;
begin
  if CurStep = ssDone then
  begin
    ShellExecAsOriginalUser('open', ExpandConstant('{app}\EDUPAY-DRC-Acces.exe'),
      '', ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;
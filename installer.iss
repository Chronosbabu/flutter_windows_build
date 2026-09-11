[Setup]
AppName=ADUPAY-DRC
AppVersion=1.0.0
AppPublisher=ADUPAY-DRC
DefaultDirName={autopf}\ADUPAY-DRC
DefaultGroupName=ADUPAY-DRC
OutputDir=.
OutputBaseFilename=ADUPAY-DRC-Setup
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

; ---------------------------------------------------------------------
; Pilote Epson Advanced Printer Driver 6.12 pour la TM-T20III. Le fichier
; est déjà présent dans le projet (pas de téléchargement pendant le
; build) : windows\driver\APD_612_T20III_WM.exe. Copié en {tmp} puisqu'on
; n'en a besoin que le temps de l'installation du pilote.
Source: "windows\driver\APD_612_T20III_WM.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

; Script de configuration de l'imprimante : embarqué dans {app}\scripts
; pour rester disponible en permanence (les tâches planifiées créées plus
; bas le rappellent quand l'Epson est branchée plus tard, sans qu'il soit
; nécessaire de réinstaller ADUPAY-DRC).
Source: "windows\scripts\configure_printer.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]
Name: "{commondesktop}\ADUPAY-DRC"; Filename: "{app}\ADUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"
Name: "{group}\ADUPAY-DRC"; Filename: "{app}\ADUPAY-DRC.exe"; IconFilename: "{app}\babu.ico"

[Run]
; Installe le VC++ Redistributable AVANT de terminer l'installation, mais
; UNIQUEMENT s'il n'est pas déjà présent (voir VCRedistNeedsInstall dans
; [Code] plus bas). /install /quiet /norestart = totalement silencieux,
; aucune fenêtre ni question posée à l'utilisateur, et on ne force jamais
; un redémarrage automatique du PC.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installation des composants requis (Visual C++)..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated

; ---------------------------------------------------------------------
; Pilote Epson TM-T20III (APD 6.12) - installé uniquement s'il n'est pas
; déjà présent, pour ne jamais perturber un PC déjà configuré (voir
; NeedsEpsonDriver dans [Code]).
;
; ATTENTION - À VALIDER SUR UN VRAI POSTE AVANT PRODUCTION :
; "/S /v/qn REBOOT=ReallySuppress" est le motif silencieux le plus
; courant pour les installateurs Epson APD (wrapper InstallShield), mais
; ce n'est PAS garanti pour ce fichier précis. Le cahier des charges est
; explicite là-dessus (§6) : il faut tester réellement
; APD_612_T20III_WM.exe (absence de fenêtre, absence de redémarrage
; forcé, code retour, présence du driver après coup) avant de considérer
; cette ligne comme définitive. Le script configure_printer.ps1 ne fera
; de toute façon jamais semblant : si le driver n'apparaît pas vraiment
; après cette étape, il l'écrit comme une ERREUR dans son log au lieu de
; prétendre que tout est en ordre.
Filename: "{tmp}\APD_612_T20III_WM.exe"; Parameters: "/S /v""/qn REBOOT=ReallySuppress"""; StatusMsg: "Installation du pilote Epson TM-T20III..."; Check: NeedsEpsonDriver; Flags: waituntilterminated runhidden

; Tâche planifiée : relance configure_printer.ps1 quand Windows détecte un
; nouveau périphérique (ex. l'Epson branchée après coup). Recréer cette
; tâche (/F) à chaque installation/mise à jour est sans risque : elle ne
; touche que le déclencheur, jamais la configuration de l'imprimante
; elle-même.
; NOTE : le canal d'évènements "Microsoft-Windows-UserPnp/DeviceInstall"
; doit être vérifié sur les postes cibles - selon la configuration groupe
; de sécurité/GPO, un canal analytique/debug peut nécessiter une
; activation préalable. À confirmer en conditions réelles ; la tâche
; ONLOGON ci-dessous sert de filet de sécurité si ce n'est pas le cas.
Filename: "schtasks.exe"; Parameters: "/Create /F /TN ""ADUPAY-DRC Epson Auto-Config"" /SC ONEVENT /EC ""Microsoft-Windows-UserPnp/DeviceInstall"" /MO ""*[System[EventID=20001]]"" /RL HIGHEST /RU SYSTEM /TR ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""{app}\scripts\configure_printer.ps1\"""""; Flags: runhidden

; Filet de sécurité léger : une seule vérification à chaque ouverture de
; session (le script se termine en quelques secondes si tout est déjà
; correct ou si rien n'est branché - pas de sondage permanent qui
; consommerait des ressources).
Filename: "schtasks.exe"; Parameters: "/Create /F /TN ""ADUPAY-DRC Epson Logon Check"" /SC ONLOGON /RL HIGHEST /RU SYSTEM /TR ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""{app}\scripts\configure_printer.ps1\"""""; Flags: runhidden

; ⚡⚡⚡ CORRIGÉ — L'ANCIENNE ligne qui lançait directement l'app ici
; (Filename: "{app}\ADUPAY-DRC.exe" ... Flags: postinstall) a été
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
// Vérifie si le pilote Epson "EPSON TM-T(203dpi) Receipt6" est déjà
// installé, en interrogeant réellement la liste des pilotes d'impression
// Windows via PowerShell (Get-PrinterDriver). Ceci évite de réinstaller
// inutilement le pilote sur un PC déjà configuré (§16-18 du cahier des
// charges) : on VÉRIFIE avant de MODIFIER, on ne supprime/recrée jamais
// systématiquement.
// ==========================================================================
function EpsonDriverInstalled(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "if (Get-PrinterDriver -Name ''EPSON TM-T(203dpi) Receipt6'' -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function NeedsEpsonDriver(): Boolean;
begin
  Result := not EpsonDriverInstalled();
end;

// ==========================================================================
// ⚡⚡⚡ NOUVEAU — Lance l'application à la toute fin de l'installation,
// mais EN TANT QUE L'UTILISATEUR D'ORIGINE (non-élevé), même si
// l'installateur tourne lui-même en administrateur.
// ShellExecAsOriginalUser est une fonction NATIVE d'Inno Setup, prévue
// précisément pour ce cas très courant : elle évite de recréer le bug de
// contexte élevé/non-élevé décrit ci-dessus, tout en conservant le
// confort d'un lancement automatique juste après l'installation.
//
// En ssPostInstall (juste avant ssDone), on lance aussi
// configure_printer.ps1 et on informe l'utilisateur uniquement si
// l'Epson n'a pas pu être détectée ou si une erreur réelle est survenue -
// jamais un message de succès qui n'aurait pas été vérifié.
// ==========================================================================
procedure CurStepChanged(CurStep: TSetupStep);
var
  ErrorCode: Integer;
  ResultCode: Integer;
  ScriptPath: String;
begin
  if CurStep = ssPostInstall then
  begin
    ScriptPath := ExpandConstant('{app}\scripts\configure_printer.ps1');
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '"',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    if ResultCode = 2 then
      MsgBox('L''imprimante Epson TM-T20III n''a pas été détectée pour le moment.' + #13#10 +
             'Branchez-la et allumez-la : la configuration se fera automatiquement, sans avoir besoin de réinstaller ADUPAY-DRC.',
             mbInformation, MB_OK)
    else if ResultCode <> 0 then
      MsgBox('La configuration automatique de l''imprimante Epson TM-T20III a rencontré un problème.' + #13#10 +
             'Journal : ' + ExpandConstant('{%TEMP}') + '\edupay_printer_setup.log',
             mbError, MB_OK);
  end;

  if CurStep = ssDone then
  begin
    ShellExecAsOriginalUser('open', ExpandConstant('{app}\ADUPAY-DRC.exe'), '', ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;

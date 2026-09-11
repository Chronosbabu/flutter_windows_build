#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configuration automatique et idempotente de l'imprimante Epson TM-T20III.

.DESCRIPTION
    Règle absolue : ce script ne devine JAMAIS un port USB (pas de
    "premier port libre", pas de "USB001" en dur). Il procède ainsi :

      1) vérifie que le pilote "EPSON TM-T(203dpi) Receipt6" est installé ;
      2) détecte le PÉRIPHÉRIQUE Epson réellement branché (PnP) ;
      3) retrouve le port RÉEL déjà associé par Windows à ce périphérique,
         en lisant l'objet imprimante que Windows/le pilote crée
         automatiquement lors du Plug&Play (c'est Windows qui a fait
         l'association matérielle réelle, pas ce script) ;
      4) crée ou corrige UNE SEULE file nommée "Epson TM-T20III" pointant
         sur ce port réel, sans jamais créer de doublon ;
      5) la définit par défaut ;
      6) vérifie réellement le résultat avant d'annoncer un succès.

    Si l'imprimante n'est pas branchée, le script ne fabrique rien : il
    journalise "en attente" et se termine avec le code 2 (pas une erreur).
    Il est prévu pour être rappelé plus tard (tâche planifiée déclenchée
    par le branchement du périphérique, voir installer.iss) sans jamais
    casser une configuration déjà correcte (idempotent).

.NOTES
    Codes de sortie :
      0 = configuration correcte et vérifiée
      1 = erreur réelle (pilote absent, association impossible, échec de
          vérification, etc.)
      2 = imprimante non branchée pour l'instant (état normal, pas une
          erreur)
#>

[CmdletBinding()]
param(
    [string]$PrinterName    = "Epson TM-T20III",
    [string]$DriverName     = "EPSON TM-T(203dpi) Receipt6",
    [string]$LogPath        = (Join-Path $env:TEMP "edupay_printer_setup.log"),
    [string]$ConfigPath     = "C:\ProgramData\ADUPAY-DRC\printer_config.json",
    [int]$MaxAttempts       = 8,
    [int]$DelaySeconds      = 3,
    [bool]$SetAsDefault     = $true
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'ERREUR')][string]$Level = 'INFO'
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch {}
    Write-Host $line
}

function Test-EpsonDriverInstalled {
    return [bool](Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)
}

function Get-EpsonPnpDevices {
    # Cherche le PÉRIPHÉRIQUE, jamais un numéro de port.
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -and (
            $_.FriendlyName -match 'TM-T20III' -or
            ($_.FriendlyName -match 'EPSON' -and $_.FriendlyName -match 'TM-T20')
        )
    }
}

function Get-EpsonPrinterObjects {
    # Windows / le pilote Epson crée automatiquement une file au
    # branchement (imprimante USB Plug&Play "vraie"). On la retrouve par
    # pilote ou par motif de nom - jamais en devinant un port.
    Get-Printer -ErrorAction SilentlyContinue | Where-Object {
        $_.DriverName -eq $DriverName -or $_.Name -match 'TM-T20III'
    }
}

function Set-PrinterDefaultReal {
    param([string]$Name)
    $escaped = $Name -replace "'", "''"
    $cim = Get-CimInstance Win32_Printer -Filter "Name='$escaped'" -ErrorAction SilentlyContinue
    if (-not $cim) { return $false }
    # Méthode privilégiée d'après les tests : Invoke-CimMethod, pas
    # $printer.SetDefaultPrinter() qui a échoué avec l'objet CIM utilisé.
    Invoke-CimMethod -InputObject $cim -MethodName SetDefaultPrinter | Out-Null
    Start-Sleep -Milliseconds 500
    $check = Get-CimInstance Win32_Printer -Filter "Default=True" -ErrorAction SilentlyContinue
    return ($check -and $check.Name -eq $Name)
}

function Write-StableConfig {
    param([string]$Port, [bool]$Configured)
    try {
        $dir = Split-Path $ConfigPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $obj = [ordered]@{
            printer_name = $PrinterName
            driver_name  = $DriverName
            port_name    = $Port        # diagnostic uniquement - Flutter ne doit JAMAIS en dépendre
            configured   = $Configured
            updated_at   = (Get-Date).ToString('o')
        }
        $obj | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
        # Écrit sous ProgramData (pas %APPDATA%) : lisible aussi bien par
        # l'installateur admin que par l'application Flutter lancée par un
        # utilisateur normal - voir §24 du cahier des charges.
        icacls $ConfigPath /grant "*S-1-1-0:(R)" 2>$null | Out-Null
    } catch {
        Write-Log "Impossible d'écrire $ConfigPath : $($_.Exception.Message)" 'ERREUR'
    }
}

# ---------------------------------------------------------------------------
Write-Log "Début configuration Epson TM-T20III"

# 1) Driver -------------------------------------------------------------
if (-not (Test-EpsonDriverInstalled)) {
    Write-Log "Driver Epson absent ('$DriverName')" 'ERREUR'
    exit 1
}
Write-Log "Driver Epson détecté" 'OK'

# 2) Détection réelle du périphérique (avec ré-essais : utile juste après
#    un branchement, le temps que Windows termine l'énumération PnP) ----
$epsonDevice  = $null
$epsonPrinter = $null
for ($i = 1; $i -le $MaxAttempts; $i++) {
    $epsonDevice  = Get-EpsonPnpDevices     | Select-Object -First 1
    $epsonPrinter = Get-EpsonPrinterObjects | Select-Object -First 1
    if ($epsonDevice -or $epsonPrinter) { break }
    Start-Sleep -Seconds $DelaySeconds
}

if (-not $epsonDevice -and -not $epsonPrinter) {
    Write-Log "Epson TM-T20III non détectée" 'INFO'
    Write-Log "Configuration reportée (aucune file créée)" 'INFO'
    Write-StableConfig -Port $null -Configured $false
    exit 2
}

if ($epsonDevice) {
    Write-Log "Périphérique PnP détecté : $($epsonDevice.FriendlyName)" 'OK'
}

# 3) Le périphérique PnP peut être vu un instant avant que le spouleur ne
#    matérialise la file. On patiente, mais on ne fabrique jamais de port. -
if (-not $epsonPrinter) {
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Start-Sleep -Seconds $DelaySeconds
        $epsonPrinter = Get-EpsonPrinterObjects | Select-Object -First 1
        if ($epsonPrinter) { break }
    }
}

if (-not $epsonPrinter) {
    Write-Log "Périphérique vu mais aucune file Windows associée trouvée : impossible de déterminer le port réel, aucune configuration forcée" 'ERREUR'
    Write-StableConfig -Port $null -Configured $false
    exit 1
}

$realPort = $epsonPrinter.PortName
Write-Log "Port USB réel détecté : $realPort (via file existante '$($epsonPrinter.Name)')" 'OK'

# 4) Créer/corriger UNE SEULE file nommée "Epson TM-T20III" -------------
$existingTarget = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue

if ($existingTarget) {
    $needsPortFix   = $existingTarget.PortName   -ne $realPort
    $needsDriverFix = $existingTarget.DriverName -ne $DriverName

    if (-not $needsPortFix -and -not $needsDriverFix) {
        Write-Log "Imprimante '$PrinterName' déjà existante et correcte - rien à modifier" 'OK'
        if ($epsonPrinter.Name -ne $PrinterName) {
            # La file auto-créée par Windows est un doublon du même
            # périphérique : on la retire pour n'en garder qu'une seule.
            Write-Log "Suppression du doublon auto-créé '$($epsonPrinter.Name)'" 'INFO'
            Remove-Printer -Name $epsonPrinter.Name -ErrorAction SilentlyContinue
        }
    } else {
        Write-Log ("Imprimante '$PrinterName' existante mais incorrecte (port ok={0}, driver ok={1}) - correction ciblée uniquement" -f (-not $needsPortFix), (-not $needsDriverFix)) 'INFO'
        if ($needsPortFix)   { Set-Printer -Name $PrinterName -PortName $realPort }
        if ($needsDriverFix) { Set-Printer -Name $PrinterName -DriverName $DriverName }
    }
}
elseif ($epsonPrinter.Name -eq $PrinterName) {
    Write-Log "Imprimante '$PrinterName' déjà créée automatiquement par Windows" 'OK'
}
else {
    # La file auto-créée porte un autre nom (ex. "EPSON TM-T20III") : on la
    # RENOMME - même objet, même port, même pilote, donc aucun doublon.
    Write-Log "Renommage de '$($epsonPrinter.Name)' -> '$PrinterName'" 'INFO'
    Rename-Printer -Name $epsonPrinter.Name -NewName $PrinterName
}

# 5) Imprimante par défaut ------------------------------------------------
if ($SetAsDefault) {
    if (Set-PrinterDefaultReal -Name $PrinterName) {
        Write-Log "Imprimante par défaut : $PrinterName" 'OK'
    } else {
        Write-Log "Échec de la définition par défaut" 'ERREUR'
    }
}

# 6) Vérification finale réelle ------------------------------------------
Start-Sleep -Milliseconds 500
$final      = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
$defaultCim = Get-CimInstance Win32_Printer -Filter "Default=True" -ErrorAction SilentlyContinue

if (-not $final -or $final.DriverName -ne $DriverName) {
    Write-Log "Vérification finale ÉCHOUÉE" 'ERREUR'
    Write-StableConfig -Port $realPort -Configured $false
    exit 1
}

$isDefault = [bool]($defaultCim -and $defaultCim.Name -eq $PrinterName)
Write-Log ("Vérification -> Nom={0} | Driver={1} | Port={2} | Statut={3} | Défaut={4}" -f `
    $final.Name, $final.DriverName, $final.PortName, $final.PrinterStatus, $isDefault) 'OK'

Write-StableConfig -Port $final.PortName -Configured $true
Write-Log "Configuration terminée" 'OK'
exit 0
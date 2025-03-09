# Fonction pour vérifier la version de Windows
function Check-WindowsVersion {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $version = [version]$os.Version
    # Windows 10 version 1809 correspond au build 17763
    if ($version.Major -eq 10 -and $version.Build -ge 17763) {
        Write-Host "Votre version de Windows ($($os.Caption) Build $($version.Build)) supporte l'installation RSAT via les fonctionnalités optionnelles."
        return $true
    }
    else {
        Write-Host "Votre version de Windows ($($os.Caption) Build $($version.Build)) ne supporte pas cette méthode d'installation RSAT."
        Write-Host "Veuillez télécharger manuellement le package RSAT depuis le site de Microsoft."
        return $false
    }
}

# Exécuter la vérification de version
if (Check-WindowsVersion) {
    # Récupère toutes les fonctionnalités RSAT disponibles
    $rsatCapabilities = Get-WindowsCapability -Online | Where-Object { $_.Name -like "RSAT*" }
    
    foreach ($capability in $rsatCapabilities) {
        if ($capability.State -ne "Installed") {
            Write-Host "Installation de $($capability.Name) en cours..."
            Add-WindowsCapability -Online -Name $capability.Name
        }
        else {
            Write-Host "$($capability.Name) est déjà installé."
        }
    }
    
    Write-Host "Installation terminée."
}

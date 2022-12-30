#Get subscription name
Param(
    [Parameter (Mandatory = $true)]
    [string] $Subscription
)
#Check if Az module is installed
if (get-module -ListAvailable -Name "Az.RecoveryServices") {
    write-host 'Reqired module is installed'
}
else {
    Write-host "Install Az module"
    Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
    if (get-module -ListAvailable -Name "Az.RecoveryServices") {
        Write-Host "The module az will be isntalled."
    }
    else {
        write-host "Please verify the installation of module AZ. The script will be stopped." -ForegroundColor Red
        write-host "Try one more time after when the module will be isntalled" -ForegroundColor Green
        exit
    }
}
#Check if account is login
$currentSubscription = Get-AzContext
if ($currentSubscription) {
    write-host "You are in :"$currentSubscription.Subscription.Name " and logined to the Azure."
}
else {
    write-host "The user will be logined to Azure"
    Connect-AzAccount | Out-Null
}
#Check if subscription exists
$AllSubscription = Get-AzSubscription | Where-Object { $_.Name -like $Subscription }
if ($AllSubscription) {
    Write-Host "Name of the subscription is correct one and access to them is available."
}
else {
    Write-Host "Subscription is not correct or access to them is not granted." -BackgroundColor DarkBlue
    exit
}

#Check if the subscription is set, if not the accoutn will be switched between two subscriptions
if ($currentSubscription.Subscription.Name -eq $Subscription) {
    Write-Host "You are in proper subscription"
}
else {
    write-host "Switch to subscription: "$Subscription
    Set-AzContext  -SubscriptionName $Subscription | Out-Null
}

#Check if proper resource group exist with Recovery Site Vault.
$resourceGroup = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*500-ASR" }
if ($resourceGroup) {
    write-host "Resource group is: "$resourceGroup.ResourceGroupName
}
else {
    Write-Host "Subscription: $Subscription doesn't have required resource group."
    exit
}
#Check if proper service vault in the resource group
$resourceRSV = (Get-AzResource -resourceGroupName $resourceGroup.ResourceGroupName | Where-Object { $_.Name -like "*RSV*" }).Name
if ($resourceRSV) {
    Write-Host "Recovery Site Vault for DRP proposal in subscription:$Subscription name is: $resourceRSV."
}
else {
    Write-Host "The Recovery Site Valut service hasn't been created for the subscription."
    Exit
}

#The file is responsible for access to some of the ASR resources
$vault01 = Get-AzRecoveryServicesVault | Where-Object { $_.Name -like "*DRP" }
$credsfilename = Get-AzRecoveryServicesVaultSettingsFile -SiteRecovery -Vault $vault01
Import-AzRecoveryServicesAsrVaultSettingsFile -Path $credsfilename.FilePath

#The file which is used for access ASR is not used any more
Remove-Item -Path $credsfilename.FilePath -Force

#Configuration rest part of the ASR connection
$fabric = Get-AzRecoveryServicesAsrFabric | Where-Object { $_.name -like "*francecentral" }
#Get info about container from the ASR properties
$container = Get-AzRecoveryServicesAsrProtectionContainer -Fabric $fabric

#Get all items from Fabric replication
$items = Get-AzRecoveryServicesAsrReplicationProtectedItem -ProtectionContainer $container

#Number of items in array with replication VMs
$numberItems = $items.Length

#Receive info about ASR dammy network
$drNetwork = Get-AzVirtualNetwork | Where-Object { $_.Name -like "*VNT500-ASR-Isolated" }
$recoveryNetowrk = $drNetwork.Id
#Subnet in recvoery network
$drSubnet = (Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $drNetwork | Where-Object { $_.Name -like "*SNT500-ASR-Isolated" }).Name

#Change the confoguration for all items, if it is necessary
$q = 0
for ($j = 0; $j -lt $numberItems; $j++) {
    $i = $items[$j]
    if (-not($i.SelectedTfoAzureNetworkId.Contains("VNT500-ASR-Isolated"))) {
        $q++
        $asrNicGuid = $i.NicDetailsList.NicId
        $vmnic = Get-AzVM -Name $i.FriendlyName
        $getnic = Get-AzNetworkInterface -ResourceId $vmnic.NetworkProfile.NetworkInterfaces.Id
        $ipConfigs = New-AzRecoveryServicesAsrVMNicIPConfig  -IpConfigName $getNic.IpConfigurations.Name `
            -RecoverySubnetName $drSubnet -TfoSubnetName $drSubnet `
            -RecoveryStaticIPAddress "" -TfoStaticIPAddress ""
        $nicConfig = New-AzRecoveryServicesAsrVMNicConfig -NicId $asrNicGuid `
            -ReplicationProtectedItem $i -RecoveryVMNetworkId $recoveryNetowrk `
            -TfoVMNetworkId $recoveryNetowrk  -IPConfig $ipConfigs
        $friendlyName = $i.FriendlyName
        Write-Host "The Virtual network will be changed in target for:$friendlyName"
        $jobNetwork = Set-AzRecoveryServicesAsrReplicationProtectedItem -ReplicationProtectedItem $i -ASRVMNicConfiguration $nicConfig
    }
    else {
        write-host "The VMnetwork in DR is correct for: "$i.FriendlyName
    }
}
#Check status for the VMNetwork changed
if ($q -gt 0) {
  $k = 0
do {
    $k++
    Start-Sleep -Seconds 60
    $statusNetwork = (Get-AzRecoveryServicesAsrJob -Name $jobNetwork.Name).StateDescription
} while (($statusNetwork -eq "Completed") -or ($k -eq 5))
}

#Check Resource group target and it is necessary, the script will change them automatically. 
for ($j = 0; $j -lt $numberItems; $j++) {
    $i = $items[$j]
    $rsgRecoveryId = (Get-AzResourceGroup -Name $drNetwork.ResourceGroupName).ResourceId 
    $jobResourseGroup = (Set-AzRecoveryServicesAsrReplicationProtectedItem -ReplicationProtectedItem $i -RecoveryResourceGroupId $rsgRecoveryId)
    Get-AzRecoveryServicesAsrJob -Name $jobResourseGroup.Name | Out-Null
}

#Disconnect from current subscription
Disconnect-AzAccount
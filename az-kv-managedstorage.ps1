param(
    [string] [Parameter(Mandatory=$True)] [ValidateSet("Y", "N")] $LoginToAzure
)
$ResourceGroupName = Read-Host "Enter your resourceGroup Name for deployment"
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 3

# Sign in
if ($LoginToAzure -eq "Y")
{
    Write-Host "Logging in to Azure ..."; 
    Connect-AzAccount;
}

# select subscription
$SubscriptionId = Get-AzSubscription | Out-GridView -PassThru -Title "Select Subscription..." | Select-Object -ExpandProperty "SubscriptionId"
Write-Host "Selecting subscription '$SubscriptionId'";
Select-AzSubscription -SubscriptionID $SubscriptionId;

#Create or check for existing resource group
Write-Host "Checking if Resource Group ('$ResourceGroupName') exists ..."
$RG = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if(!$RG)
{

    $RL = "australiaeast";
        
    Write-Host "Resource Group not found. Creating in $RL ...";
    New-AzResourceGroup -Name $ResourceGroupName -Location $RL;
}
else
{
    Write-Host "Resource Group found.";
}
#This section will prompt for storage account and key vault name. Script it will check for existing resource and if not found, the resource will be created with provided name.
$staccname = Read-Host "Enter your Storage account Name for deployment"
$kvname = Read-Host "Enter your Key vault Name for deployment"
#Key Vault is a Microsoft application that's pre-registered in all Azure AD tenants. Key Vault is registered under the same Application ID in each Azure cloud.
$keyVaultSpAppId = "cfa8b339-82a2-471a-a3c9-0fc0be7a4093"
$storageAccountKey = "key1"
$SASDefinitionName = "demostoragesas"
#Verify Storage account and Key vault is available.
#$stacc = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $staccname
#kv = Get-AzKeyVault -VaultName $kvname -ResourceGroupName $ResourceGroupName

#Create or check for existing Storage account
Write-Host "Checking if Storage account ('$staccname') exists ..."
$stacc = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $staccname -ErrorAction SilentlyContinue
if(!$stacc)
{

    $RL = "australiacentral";
        
    Write-Host "Storage Account not found. Creating in $RL ...";
    $stacc= New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $staccname -Location $RL  -SkuName Standard_LRS
}
else
{
    Write-Host "Storage Account found.";
}

#Create or check for existing Key vault
Write-Host "Checking if Key Vault  ('$kvname') exists ..."
$kv = Get-AzKeyVault -VaultName $kvname -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if(!$kv)
{

    $RL = "australiacentral";
        
    Write-Host "Key Vault not found. Creating in $RL ...";
    $kv= new-AzKeyVault -VaultName $kvname -ResourceGroupName $ResourceGroupName -Location $RL
}
else
{
    Write-Host "Key Vault found.";
}
# Give Key Vault permissions on Storage to rotate keys
Write-Output "Give KV permissions on Storage to rotate keys"
New-AzRoleAssignment -ApplicationId $keyVaultSpAppId -RoleDefinitionName 'Storage Account Key Operator Service Role' -Scope $stacc.Id

# Give the current user access to KV storage permissions
Write-Output "Give the current user access to KV storage permissions"
$userId = (Get-AzContext).Account.Id
Set-AzKeyVaultAccessPolicy -VaultName $kvname -UserPrincipalName $userId -PermissionsToStorage get, list, delete, set, update, regeneratekey, getsas, listsas, deletesas, setsas, recover, backup, restore, purge
# Add storage accounts to key vault and retention period
$regenPeriod = [System.Timespan]::FromDays(30)
Write-Output "Sleeping 30 seconds to have role assignments propagate and catch up"
Start-Sleep -Seconds 30
Write-Output "Done sleeping. Add storage accounts to key vault"
Add-AzKeyVaultManagedStorageAccount -VaultName $kvname -AccountName $staccname -AccountResourceId $stacc.Id -ActiveKeyName $storageAccountKey -RegenerationPeriod $regenPeriod
# Onboard storage account with read,write and list permissions only
Write-Output "Onboard storage account with read,write and list permissions only"

$storageContext = New-AzStorageContext -StorageAccountName $staccname -Protocol Https -StorageAccountKey Key1 
$start = [System.DateTime]::Now.AddDays(-1)
$end = [System.DateTime]::Now.AddMonths(1)

$sasToken = New-AzStorageAccountSasToken -Service blob -ResourceType Service,Container,Object -Permission "racwlu" -Protocol HttpsOnly -StartTime $start -ExpiryTime $end -Context $storageContext
Set-AzKeyVaultManagedStorageSasDefinition -AccountName $staccname -VaultName $kvname -Name $SASDefinitionName -TemplateUri $sasToken -SasType 'account' -ValidityPeriod ([System.Timespan]::FromDays(1))

# Getting secrets to verify everything works
 <# Write-Host "Getting secrets to verify things work."
$secret = Get-AzKeyVaultSecret -VaultName "kv-demo-storage01" -Name "azdemostgmanagedkv01-demostoragesas"
$ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
try {
   $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
} finally {
   [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
}
Write-Output $secretValueText
#


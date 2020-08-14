param (
    [string]$customerName
)

# Define Resource groups and other basic information
# TODO: Support for multiple Key Vaults
$managementRgName = 'rg-iac'
$solutionRgName = "rg-Apps"
$gitRepo = "https://github.com/whaakman/Demo-WebApp.git" 
$keyvaultName = 'kv-wh-iac'
$storageAccountName = 'sawhiac'
$tableName = 'Customers'

# Retrieve "Customers" table from table storage and storage the customer data in $customerData
$table = Get-AzTableTable -resourceGroup $managementRgName -TableName $tableName -storageAccountName $storageAccountName
$customerData = Get-AzTableRow -Table $table -PartitionKey $customerName

# Before continuing check if customer exists to prevent deployments with default values
If([string]::IsNullOrEmpty($customerData)){            
    Write-Host "Customer doesn't exist" 
	break          
} 

# Remove white space from customer name, required for App and DB naming
$customerName = $customerName -replace '\s',''

# Determine the customer size (small, medium, large) and set the corresponding SKUs
# Additionally checks if the App Service plan selected isn't overpopulated to
# prevent performance issues
# TODO: Automatically created new App Service Plan with an increment of "1" when all plans are full
$customerSize = $customerData.customerSize

switch ($customerSize)
{
    "Small" { $appServicePlan = 'ASP-Small01'; $sku = 'S1' ; $databaseCapacity = '2' }
    "Medium" { $appServiceplan = 'ASP-Medium01'; $sku = 'S2' ; $databaseCapacity = '4'   }
    "Large" { $appServicePlan = 'ASP-Large01'; $sku = 'P1V2' ; $databaseCapacity = '6'  }
}

$selectedAppServicePlan = Get-AzAppServicePlan -ResourceGroupName $solutionRgName -name $appServicePlan
if ($selectedAppServicePlan.NumberOfSites -gt 9)
{
    Write-Host "App Service Plan $appServicePlan has reached the limit of 10 websites"
    break
}

# Retrieve keys from KeyVault and store all secrets in $keys for later use
$secrets = Get-AzKeyVaultSecret -VaultName $keyvaultName
$keys =@{}
foreach ($secret in $secrets)
    {
        $secretName = $secret.name
        
        $key = (Get-AzKeyVaultSecret -VaultName $keyvaultName -name $secretName).SecretValueText
        $keys.Add("$secretName", "$key")
    }

# Populate the template Parameters. Data comes from Table storage and Key Vault
# SKU is not a requirement, only when provisioning a new App Service Plan
# TODO: Validate whether domain is already in use
$templateParams =@{
    "webAppName" = $customerName
    "appServicePlan" = $appServicePlan
    "sku" = $sku
    "sqlAdministratorLogin" = $keys.sqlAdministratorLogin
    "sqlAdministratorLoginPassword" = $keys.sqlAdministratorLoginPassword
    "databaseCapacity" = $databaseCapacity
    "location" = $customerData.Location
}

# Configuration for Source Control, retrieve code from main branch
$PropertiesObject = @{
    repoUrl = "$gitrepo";
    branch = "main";
    isManualIntegration = "true";
}

# Deploy the ARM Template
# TODO: Use seperate templates for Web Apps and SQL
# TODO: Support for deploying development and training environments
$deployment = New-AzResourceGroupDeployment -ResourceGroupName $solutionRgName -TemplateFile .\azuredeploy.json -TemplateParameterObject $templateParams

# Store the output in variables that make sense
$webAppPortalName = $deployment.Outputs.webAppPortalName.value
$customerData.URI = $deployment.Outputs.webAppPortalUri.value[0].value

# Configure Source Control
# Doing this through the ARM Template itself is a bit wonky and results in unpredictable behavior
$PropertiesObject = @{
    repoUrl = "$gitrepo";
    branch = "main";
    isManualIntegration = "true";
}

$sc = Set-AzResource -Properties $PropertiesObject -ResourceGroupName $solutionRgName -ResourceType Microsoft.Web/sites/sourcecontrols -ResourceName $webAppPortalName/web -ApiVersion 2015-08-01 -Force

# Store the URI in table storage
$tableUpdate = $customerData |Update-AzTableRow $table
$customerData
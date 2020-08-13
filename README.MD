# Automatically deploy Web Apps for additional customers
The script and ARM Template will create a scenario where additional Web Apps and databases will deployed based on the configuration stored in table stored. This works across regions. Scenario is fit for software companies deploying new Apps for new customers. Can be used for demo purposes or as a starting point for your own scripting. 

## Requirements
1. Create a resource group for management purposes
2. Deploy Storage Account (Table Storage)
3. Create customers in Table storage
4. Deploy Key Vault
5. Populate Key Vault with required secrets
6. Create a resource group to house the Apps
7. Deploy using deployment.ps1 with the -customerName parameter. Note that the customerName must match the name of the customer in Table storage. 
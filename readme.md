# Start-AzureVMMigration
<p>Start-AzureVMMigration is a script which duplicates a VM in a different subscription, within the same Azure tenant. It does so non-destructively by creating a parallel VM in the new subscription and shutting down the old VM before starting the new one. Because of this, it should also avoid AD name collision issues. (AD collision has yet to be fully tested.)</p>

## Usage
<p>There are many functions contained in this script but there are really only two which you need to run.</p>

<p>Install-RequisiteModules checks to make sure you have the Az.Resources, Az.Network, Az.Compute and Az.Accounts modules installed. You can choose to run this function or leave it if you know you have your preferred versions of those modules installed.</p>

<p>Start-AzureVMMigration is the function which calls the other functions and controls the error state of the script. It is also responsible for logging general script runtime information and using try-catch blocks to log errors if they occour.</p>

## Roadmap
<p>This script is a bit of a "quick and dirty" fix for a current requirement. With that in mind, it is still in active development. Here are some features I'm looking to fix and add.</p>

<ol>
<li>The script currently throws an error when I call Update-AzVM, near line 518. This means you'll have to manually reattach drives to the VM once the new VM is created.</li>
<li>Ideally, I'd like to create a function or a robust try-catch block to handle unmanaged disk cloning and migration. The current task does not require I work with unmanaged disks but I may revisit this task later.</li>
<li>Need to decide on a method for dealing with cases where the VM's name in the portal and the name in the OS profile are inconsistent. Currently, I prefer the name provided by the OSProfile.</li>
<li>Write a loop counter in Install-RequisiteModules so it doesn't infinitely loop. That's the cost of recursion I suppose. </li>
</ol>

## Contributing
<p>Pull requests are welcome and I will address them as I have time. Please feel free to email me at mcherneski@alvarezandmarsal.com if you submitted a pull request and have not heard from me in a timely manner.</p>

# Functions Overview
<p>This script was created to migrate Azure VMs from one subscription to another, within the same tenant. The functions accomplish the following:</p>

### Write-ToLogFile: 
<p>Creates a log file on the desktop of the user running the script. The file is named Azure-Migrations_Date where date is the deate in the dd-mm-yy format. It also has a Write-Verbose option.</p>

<p>Accepts one argument: </p>
<ul>
<li>$Message: This is a string for which you want to log and optionally, display with Write-Verbose.</li>
</ul>

### Install-RequisiteModules
<p>Checks for the Az.Resources, Az.Compute, Az.Network and Az.Accounts modules. If they are not present, it attempts to install them for the current user. This function uses recursion to retry the checks if one of the modules is not installed and it attempts an install.</p>
<br>
<p>Accepts one argument:</p>
<ul>
<li>$SourceSubsription: SourceSubscription is the subscription ID which contains the VM to be migrated. I know it's not exactly a needed parameter but I figured I'd add it in to add a layer of convinience to the script.</li>
</ul>

### Get-AzureVM
<p>Uses the Get-AzVM cmdlet to retreive information and create a PSCustomObject which we can use to pass to later functions. Most of these fields come from the PSVirtualMachine object, which is returned from Get-AzVM. I chose to create custom objects so I could keep all the method and property calls to a minimum at runtime.Plus I like PSCustomObjects, they feel very cool to write.</p>
<br>
<p>The PSCustomObject contains the following fields: </p>
<ul>
    <li> Id - Virtual Machine's ID</li>
    <li>VMName - THe VM's OSProfile.ComputerName</li>
    <li>AzureName - The VM's name in the Azure portal. Used occasionally for troubleshooting</li>
    <li>Location - The VM's Azure Location (Ex: eastus)</li>
    <li>ResourceGroupName - The VM's ResourceGroupName</li>
    <li>HardwareProfile - The VM's size </li>
    <li>OSProfile - VM's OS information. Returns an array of useful info for debugging purposes. May be cleaned in later version</li>
    <li>OSDisk - VM's OS Disk accourding to StorageProfile.OSDisk. Primary object used when taking snapshots of disk</li>
    <li>DataDisks - Array of VM's data disks from StorageProfile.DataDisks</li>
    <li>Tags - Array of Tags so we can easily move those over. </li>
    <li>LicenseType - This was used when creating the VM. Keeping it in there for debugging, for now.</li>
</ul>
<br>
<p>Accepts two arguments:</p>
<ul>
<li>$VirtualMachineName: Name of the VM for which you would like to retreive the information. This is the name in the Azure Portal, not the OS profile</li>
<li>$SubscriptionID: ID of the subscription for which the VM resides. </li>
</ul>
    
### Start-DestinationChecks
<p>Verifies the existence of the VM, the Target Subnet, the Target VNet and the Target RG for the VMs being moved. Will return a boolean value</p>
<br>
<p>Requires four arguements:</p>
<ul>
<li>$VM: The PSCustomObject which is returned by Get-AzureVM.</li>
<li>$TargetSubnetName: The name of the subnet in which the new VM will reside.</li>
<li>$TargetVNet: The name of the VNet in which the new VM will reside. Must be the VNet for the subnet specified. Doesn't make sense otherwise but it bears stating. :) </li>
<li>$TargetResourceGroup: The ResourceGroupName of the resource group for which you would like to migrate the resources. </li>
</ul>

### New-DiskSnapshots
<p>Takes disk snapshots and saves them into an array of PSCustom objects so we can iterate over them in future functions in a foreach loop. Creates an array for the data disks and the OS disks based on the return value of the New-AzSnapshot or Update-AzSnapshot calls.</p>

<p>The PSCustomObject has the following fields:</p>
<ul>
<li>Id - The DiskSnapshot ID.</li>
<li>SnapshotName - Name of the snapshot.</li>
<li>NewDiskName - What the new disk will be named. Currently, if it's an OS disk it will be named "OS_VMName_DateTime" where DateTime is the date and time in the format MMddyyyyhhmmss. Similarly, it will specify the same format but with a DD_ prefix for data disks. This allows a psuedo serialization for the disks based on snapshot time.</li>
<li>ResourceGroupName - The resourcegroupname of the disk snapshot</li>
<li>SKU - The disk SKU. </li>
<li>DiskSizeGB - Self explainitory and I'm not sure if I use it anymore since Azure has some built in smarts regarding this. </li>
<li>Location - The Azure Region of the disk snapshot. </li>
</ul>
<br>
<p>This function requires the following params: </p>
<ul>
<li>$VM: The PSCustomObject returned from the Get-AzureVM cmdlet. This function will extract the disk information from that object.</li>
</ul>

### New-MigrationDisks
<p>Creates new disks in the existing resource group based on the snapshopts taken by New-DiskSnapshots. Accepts the PSCustomObject we created with New-DiskSnapshots and creates another array of PSCustomObjects for future use.</p> 

<p>The PSCustomObject has the following fields:</p>
<ul>
<li>Name - The newly created disk's name. Same as the snapshot's NewDiskName field.</li>
<li>ResourceGroupName - The resourcegroupname for the newly created disk.</li>
<li>Id - The Id of the newly created disk.</li>
<li>Location - The Azure region/location of the newly created disk.</li>
<li>DiskSizeInGB - The disk size in GB for the newly created disk. I'm not sure if I'll keep this for the reasons stated above. </li>
</ul>
<br>
<p>This function requires the following params:</p>
<ul>
<li>$SnapshotCollection: The array of PSCustomObjects returned by New-DiskSnapshots</li>
</ul>

### Move-NewDisks
<p>Moves the disks created in New-MigrationDisks to the specified target resource group by iterating over the array of PSCustomObjects returned by New-MigrationDisks. Returns true or false.</p> 
<br>
<p>This function requires the following params:</p>
<ul>
<li>$DiskCollection: The array of PSCustomObjects returned by New-MigrationDisks</li>
<li>$DestinationResourceGroupName: The resourcegroupname where you would like to move the disks. This will be the same as your VM's destination RG name.</li>
<li>$DestinationSubscriptionID: The Subscription for which the new VM will live.</li>
</ul>

### Start-AzureVMMigration
<p>This is the function which calls the other functions in order to do the actual migration. It is responsible for error catching the other functions and logging overall progress. <em>Currently, the Update-AzVM cmdlet around line 511 throws an error which needs addressing</em>.</p>
<p>So basically, here's a breakdown of how this function works:</p>
<ol>
<li>Writes a line in the logfile to create a clear seperation between migration attemtps.</li>
<li>Runs Get-AzureVM to create the PSCustomObject which will be passed down through multiple functions.</li>
<li>Runs Start-DestinationChecks to make sure our targets are valid.</li>
<li>If DestinationChecks are valid, takes disk snapshots by running New-DiskSnapshots. Will return the array of PSCustomObjects which contain the snapshot details.</li>
<li>If there are no thrown errors during snapshots, creates migration disks by running New-MigrationDisks cmdlet. Returns the array of PSCustomObjects which represent the new disks.</li>
<li>Runs Move-NewDisks to migrate the disks stored in the previously returned array to the new subscription.</li>
<li>Creates new Nic using New-AzNetworkInterface. Stores that value.</li>
<li>Creates the AzVM config using the new disk information and the new Nic we created.</li>
<li>Shuts down the old VM in the previous subscription. </li>
<li>Creates the VM in the new ResourceGroup, using the config we created above.</li>
<li>Attaches the data disks by searching the array created by New-Migration disks, creating an array of objects with the name like DD_* and running that array through a foreach loop with the Add-AzVMDataDisk cmdlet.</li>

<li>***Broken*** Runs Update-AzVM on the new VM to complete the data disk attachment.</li>
<li>Returns status of $true or throws an error.</li>
</ol>
<br>
<p>Function will return true or false. It requires the following params:</p>
<ul>
<li>$AzureVMName: Name of the VM in Azure for which you want to migrate to a new subscription. Used mostly by Get-AzureVM cmdlet to create the initial PSCustomObject which is passed down to other functions.</li>
<li>$CurrentSubscriptionID: ID of the current subscription. We use Set-AzContext often so this is a good thing to have in our pocket. </li>
<li>$TargetSubscriptionID: ID of the subscription for which the new VM will live.</li>
<li>$TargetSubnetName: Name of the subnet which you want to move the VM into.</li>
<li>$TargetVNetName: Name of the target VNet. Must be within the subnet specified above.</li>
<li>$TargetResourceGroup: Name of the resource group which will be used to stage migrated resources and eventually where the new VM will reside</li>
</ul>
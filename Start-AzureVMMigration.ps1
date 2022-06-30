Function Write-ToLogFile
{
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]
        $Message
    )
    $Date = (Get-Date -Format "dd-MM-yy").ToString()
    $DateTime = (Get-Date -Format "dd-MM-yy_hh:mm:ss").ToString()

    $FullPath = "$($Env:USERPROFILE)\Desktop\Azure-Migrations_$($Date).log"
    if (!(Test-Path $FullPath))
    {
        try {
            New-Item -Path $FullPath -ItemType File
        }catch{
            Write-Verbose "Error Creating Log file at $($FullPath)"
            throw $Error[0].Exception
        }
    }

    $Message = "$($Message) - $($DateTime)"

    Add-Content -Path $FullPath -Value $Message -Force -ErrorAction SilentlyContinue
    Write-Verbose -Message $Message
}

Function Install-RequisiteModules
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $SourceSubscription
    )

    $Resources = $false
    $Compute = $false
    $Network = $false
    $Accounts = $false
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Register-PSRepository -Default -ErrorAction SilentlyContinue

    try {
        if (Get-Module -ListAvailable -Name Az.Compute)
        {
            Write-ToLogFile -Message "Az.Compute Module Installed!"
            $Compute = $true
        } else {
            Write-ToLogFile "Az.Compute module was not installed. Attempting install..." -Verbose
            try {
                Find-Module -Name Az.Compute | Install-Module -Scope CurrentUser -Force
            } catch [System.Management.Automation.ParameterBindingException] {
                Write-ToLogFile -Message "Az.Compute is already installed. Upgrading module." -Verbose
                Get-InstalledModule -Name "Az.Compute" | Update-Module -Force
            } catch {
                Write-ToLogFile -Message "Failed to install Az.Compute." -Verbose
                throw "Requisite Module Az.Compute could not be installed!"
            }
        }

        if (Get-Module -ListAvailable -Name Az.Network)
        {
            Write-ToLogFile "Az.Network Module Installed!"
            $Network = $true
        } else {
            Write-ToLogFile "Az.Network module was not installed. Attempting install..." -Verbose
            try {
                Find-Module -Name Az.Network| Install-Module -Scope CurrentUser -MinimumVersion "5.2.0" -Force
            } catch [System.Management.Automation.ParameterBindingException] {
                Write-ToLogFile -Message "Az.Network is already installed. Upgrading module." -Verbose
                Get-InstalledModule -Name "Az.Network" | Update-Module -Force
            } catch {
                Write-ToLogFile -Message "Failed to install Az.Network." -Verbose
                throw "Requisite Module Az.Network could not be installed!"
            }
        }

        if (Get-Module -ListAvailable -Name Az.Resources)
        {
            Write-ToLogFile "Az.Resources Module Installed!"
            $Resources = $true
        } else {
            Write-ToLogFile "Az.Resources module was not installed. Attempting install..." -Verbose
            try {
                Find-Module -Name Az.Resources | Install-Module -Scope CurrentUser -Force
            } catch [System.Management.Automation.ParameterBindingException] {
                Write-ToLogFile -Message "Az.Resources is already installed. Upgrading module." -Verbose
                Get-InstalledModule -Name "Az.Resources" | Update-Module -Force
            } catch {
                Write-ToLogFile -Message "Failed to install Az.Resources." -Verbose
                throw "Requisite Module Az.Resources could not be installed!"
            }
        }

        if (Get-Module -ListAvailable -Name Az.Accounts)
        {
            Write-ToLogFile "Az.Accounts Module Installed!"
            $Accounts = $true
        } else {
            Write-ToLogFile "Az.Accounts module was not installed. Attempting install..." -Verbose
            try {
                Find-Module -Name Az.Accounts | Install-Module -Scope CurrentUser -MinimumVersion "5.2.0" -Force
            } catch [System.Management.Automation.ParameterBindingException] {
                Write-ToLogFile -Message "Az.Accounts is already installed. Upgrading module." -Verbose
                Get-InstalledModule -Name "Az.Accounts" | Update-Module -Force
            } catch {
                Write-ToLogFile -Message "Failed to install Az.Accounts." -Verbose
                throw "Requisite Module Az.Accounts could not be installed!"
            }
        }
    }
    catch {
        Write-ToLogFile "Error getting pre-reqs:  $Error" -Verbose
    }

    if (($Resources -eq $true) -and ($Compute -eq $true) -and ($Network -eq $true) -and ($Accounts -eq $true))
    {
        try {
            Connect-AzAccount -Subscription $SourceSubscription | Out-Null
        }
        catch {
            throw "Failed to Connect Azure Account. Please check credentials."
        }
        return $true | Out-Null
    }
    else
    {
# TODO: Add loop with counter so we don't have infinite loop issues.
        Write-ToLogFile "Resources: $resources, Compute: $Compute, Network: $Network, Accounts: $Accounts"
        Write-ToLogFile "Attempting retry..." -Verbose
        Install-RequisiteModules
    }
}
Function Get-AzureVM
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $VirtualMachineName,
        [Parameter(Mandatory = $true)]
        [string]
        $SubscriptionID
    )

    try {
        Set-AzContext -Subscription $SubscriptionID | Out-Null
        $VM = Get-AzVM -Name $VirtualMachineName
        if ($null -ne $VM)
        {
            $TargetVirtualMachine = [PSCustomObject]@{
                Id = $VM.Id
                VMName = $VM.OSProfile.ComputerName
                AzureName = $VM.Name
                Location = $VM.Location
                ResourceGroupName = $VM.ResourceGroupName
                HardwareProfile = $VM.HardwareProfile
                OSProfile = $VM.OSProfile
                OSDisk = $VM.StorageProfile.OSDisk
                DataDisks = $VM.StorageProfile.DataDisks
                Tags = $VM.Tags
                LicenseType = $VM.LicenseType
            }
        }

        return $TargetVirtualMachine;
    } catch {
        Write-ToLogFile $Error[0]
        throw $Error
    }
}
Function Start-DestinationChecks
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]
        $VM,
        [Parameter(Mandatory = $true)]
        [string]
        $TargetSubnetName,
        [Parameter(Mandatory = $true)]
        [string]
        $TargetVNet,
        [Parameter(Mandatory = $true)]
        [string]
        $TargetResourceGroup
    )

    $validSubnet = $false;
    $validVNet = $false;
    $validResourceGroup = $false;
    Write-ToLogFile "Start destination pre-reqs."
    Set-AzContext -Subscription $TargetSubscriptionID | Out-Null
    Write-ToLogFile "Setting subscription to $TargetSubscriptionId" -Verbose
    try {
        Write-ToLogFile "Checking for Azure VNET: $TargetVNet"
        $VNet = Get-AzVirtualNetwork -Name $TargetVNet
        if ($null -ne $VNet)
        {
            $validVNet = $true
            Write-ToLogFile "VNet is valid! Checking for subnet: $TargetSubnet"
            if ($VNet.Subnets.Name -contains $TargetSubnetName)
            {
                $validSubnet = $true
                Write-ToLogFile "Subnet is valid!"
            }
        } else {
            Write-ToLogFile "Error! $($Error)"
            throw $Error
        }
        Write-ToLogFile "Checking target resource group: $TargetResourceGroup"
        if (Get-AzResourceGroup -Name $TargetResourceGroup)
        {
            Write-ToLogFile "ResourceGroup is valid."
            $validResourceGroup = $true;
        }

        if (($validSubnet -eq $true) -and ($validVNet -eq $true) -and ($validResourceGroup -eq $true))
        {
            Write-ToLogFile "Migration prechecks confirmed!"
            return $true;
        }

    } catch {
        Write-ToLogFile $Error[0].Exception
        return $false;
    }
    Write-ToLogFile "Start-DestinationChecks Complete!"
}
Function New-DiskSnapshots
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [PSObject]
        $VM
    )
    Set-AzContext -Subscription $CurrentSubscriptionId | Out-Null
    $DiskSnapshots = @();
    Write-ToLogFile "Starting Disk Snapshots..."
    $DateTime = Get-Date -Format 'MMddyyyyhhmmss'

    if ($null -ne $VM)
    {
        if ($null -eq $VM.OSDisk.ManagedDisk)
        {
            # TODO Create process for capturing unmanaged disk.
            # MS ADDED BELOW #
            ##Write-ToLogFile "$($VM.OSDisk.Name) is an unmanaged disk! Unable to do snapshot right now... sorry..."
            ##throw "OS Disk is an unmanaged disk. This is currently unsupported."
            New-AzVmSnapshot -vmName $VM.Name
            # MS ADDED ABOVE #
        } else {
            foreach ($Disk in $VM.OSDisk.ManagedDisk){
                try{
                    $SnapshotConfigDetails = New-AzSnapshotConfig -SourceUri $VM.OSDisk.ManagedDisk.Id -Location $VM.Location -CreateOption Copy
                    $SnapshotName = "$($VM.VMName)_OSMigSnap_$($DateTime)"
                    try{
                        $Snapshot = New-AzSnapshot -Snapshot $SnapshotConfigDetails -SnapshotName $SnapshotName -ResourceGroupName $VM.ResourceGroupName
                    } catch [System.Exception] {
                        Write-ToLogFile "Disk snapshot may already exist with that name. Using update-snapshot cmdlet." -Verbose
                        $Snapshot = Update-AzSnapshot -Snapshot $SnapshotConfigDetails -ResourceGroupName $VM.ResourceGroupName -SnapshotName $SnapshotName
                    } catch {
                        Write-ToLogFile $Error[0] -Verbose
                    }

                    if ($Snapshot.ProvisioningState -eq "Succeeded")
                    {
                        $NewName = "OS_$($VM.VMName)_$($DateTime)"

                        $DiskSnapshot = [PSCustomObject]@{
                            Id = $Snapshot.Id
                            SnapshotName = $Snapshot.Name
                            NewDiskName = $NewName
                            ResourceGroupName = $Snapshot.ResourceGroupName
                            SKU = $Snapshot.Sku.Name
                            DiskSizeGB = $Snpashot.DiskSizeGB
                            Location = $Snapshot.Location
                        }

                        $DiskSnapshots += $DiskSnapshot

                    } else {
                        Write-ToLogFile "$SnapshotName Failed!" -Verbose
                    }
                }
                catch {
                    Write-ToLogFile $Error[0] -Verbose
                    return $Error
                }
            }
        }

        if (($VM.DataDisks).count -gt 0)
        {
            $DiskNumber = 0;
            foreach ($Disk in $VM.DataDisks)
            {
                try {
                    $DiskURI = (Get-AzDisk -ResourceGroupName $VM.ResourceGroupName -DiskName $Disk.Name | Select-Object Id).Id
                    $SnapshotConfigDetails = New-AzSnapshotConfig -SourceUri $DiskURI -Location $VM.Location -CreateOption Copy
                    $SnapshotName = "$($Disk.Name)_DDMigSnap_$($DateTime)"

                    try{
                        $Snapshot = New-AzSnapshot -Snapshot $SnapshotConfigDetails -SnapshotName $SnapshotName -ResourceGroupName $VM.ResourceGroupName
                    } catch [System.Exception] {
                        Write-ToLogFile "Disk snapshot may already exist with that name. Using update-snapshot cmdlet."
                        $Snapshot = Update-AzSnapshot -ResourceGroupName $VM.ResourceGroupName -Snapshot $SnapshotConfigDetails -SnapshotName $SnapshotName
                    } catch {
                        Write-ToLogFile $Error[0].Exception
                    }

                    if ($Snapshot.ProvisioningState -eq "Succeeded")
                    {
                        $NewName = "DD_$($DiskNumber)_$($VM.VMname)_$($DateTime)"

                        $DiskSnapshot = [PSCustomObject]@{
                            Id = $Snapshot.Id
                            SnapshotName = $Snapshot.Name
                            NewDiskName = $NewName
                            ResourceGroupName = $Snapshot.ResourceGroupName
                            SKU = $Snapshot.Sku.Name
                            Location = $Snapshot.Location
                        }
                        $DiskSnapshots += $DiskSnapshot
                        $DiskNumber ++
                    }

                } catch {
                    Write-ToLogFile $Error[0].Exception
                }
            }
        }
    }
    else {
        # throw "Error finding OS Disk!" LOOK INTO THIS
    }
    Write-ToLogFile "Snapshots Complete!"

    return $DiskSnapshots
}
Function New-MigrationDisks
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]
        $SnapshotCollection
    )
    Write-ToLogFile -Message "Creating new disks for migration..."
    Set-AzContext -Subscription $CurrentSubscriptionId -Force -Verbose | Out-Null
    $NewDisks = @();

    foreach ($Snapshot in $SnapshotCollection)
    {
        Write-ToLogFile "Working on $($Snapshot.Name) right now."
        $DiskConfig = New-AzDiskConfig -SkuName $Snapshot.Sku -Location $Snapshot.Location -CreateOption Copy -SourceResourceId $Snapshot.Id
        Write-ToLogFile -Message ($Snapshot | Format-Table | Out-String) -Verbose
        try {
            Write-ToLogFile -Message "Creating disk for snapshot with name $($Snapshot.SnapshotName)."
            $NewDisk = New-AzDisk $DiskConfig -ResourceGroupName $Snapshot.ResourceGroupName -DiskName $Snapshot.NewDiskName

            if ($NewDisk.ProvisioningState -eq "Succeeded")
            {
                $NewDisk = [PSCustomObject]@{
                    Name = $NewDisk.Name
                    ResourceGroupName = $NewDisk.ResourceGroupName
                    Id = $NewDisk.Id
                    Location = $NewDisk.Location
                    DiskSizeInGB = $NewDisk.DiskSizeGB
                }
                $NewDisks += $NewDisk
            }
        }catch{
            Write-ToLogFile $Error
        }
    }
    return $NewDisks
}

Function Move-NewDisks
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]
        $DiskCollection,
        [Parameter(Mandatory = $true)]
        [string]
        $DestinationResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string]
        $DestinationSubscriptionId
    )

    if ($DiskCollection.Count -gt 0)
    {
        Write-ToLogFile -Message "Starting disk moves..." -Verbose

        foreach ($Disk in $DiskCollection)
        {
            Write-ToLogFile -Message ($Disk | Format-Table | Out-String) -Verbose
            try {
                Write-ToLogFile -Message "Migrating $($Disk.Name) to $($DestinationResourceGroupName)"
                Move-AzResource -ResourceId $Disk.Id -DestinationResourceGroupName $DestinationResourceGroupName -DestinationSubscriptionId $DestinationSubscriptionId -Force
            } catch {
                Write-ToLogFile -Message $Error[0]
                throw $Error[0]
            }
        }
        return $true | Out-Null
    }
}
Function Start-AzureVMMigration
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $AzureVMName,
        [Parameter(Mandatory = $true, Position = 1)]
        [string]
        $CurrentSubscriptionID,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]
        $TargetSubscriptionID,
        [Parameter(Mandatory = $true, Position = 3)]
        [string]
        $TargetSubnetName,
        [Parameter(Mandatory = $true, Position = 4)]
        [string]
        $TargetVNetName,
        [Parameter(Mandatory = $true, Position = 5)]
        [string]
        $TargetResourceGroup
    )
    Write-ToLogFile -Message "-------------------- Starting New Migration! --------------------"
    $VirtualMachine = Get-AzureVM -VirtualMachineName $AzureVMName -SubscriptionID $CurrentSubscriptionID
    Write-ToLogFile "Initialize VM Creation! Target VM is $($VirtualMachine.VMName) in $($VirtualMachine.ResourceGroupName)."
    $PreChecks = Start-DestinationChecks -VM $VirtualMachine -TargetSubnetName $TargetSubnetName -TargetVNet $TargetVNetName -TargetResourceGroup $TargetResourceGroup

    if($PreChecks -eq $true)
    {
        Write-ToLogFile "New VM Settings are valid. Starting disk snapshots."

        try {
            $Snapshots = New-DiskSnapshots -VM $VirtualMachine -Verbose
        } catch {
            Write-ToLogFile $Error[0].Exception -Verbose
        }

        try {
            $MigrationDisks = New-MigrationDisks -SnapshotCollection $Snapshots -Verbose
        } catch {
            Write-ToLogFile $Error[0].Exception -Verbose
        }

        Write-ToLogFile "Disk setups complete. Moving disks to new subscription."

        Move-NewDisks -DiskCollection $MigrationDisks -DestinationResourceGroupName $TargetResourceGroup -DestinationSubscriptionId $TargetSubscriptionID

            $StatusCode = Stop-AzVM -Id $VirtualMachine.Id -Force -NoWait

            Set-AzContext -Subscription $TargetSubscriptionID

            if ($StatusCode.IsSuccessStatusCode -eq $true)
            {
                $NicName = $VirtualMachine.VMName + "_NIC"
                $VNet = Get-AzVirtualNetwork -Name $TargetVNetName

                $Subnet = ($VNet.Subnets | Where-Object {$_.Name -eq $TargetSubnetName}).Id

                Write-ToLogFile -Message "Subnet ID is $Subnet" -Verbose

                $NIC = New-AzNetworkInterface -Name $NicName -ResourceGroupName $TargetResourceGroup -Location $VirtualMachine.Location -SubnetId $Subnet

                if ($NIC.ProvisioningState -eq "Succeeded")
                {
                    $NewVM = New-AzVMConfig -VMName $VirtualMachine.VMName -VMSize $VirtualMachine.HardwareProfile.VmSize -Tags $VirtualMachine.Tags -LicenseType $VirtualMachine.LicenseType
                    $NewVM = Add-AzVMNetworkInterface -VM $NewVM -Id $NIC.Id

                    $OSDiskObj = $MigrationDisks | Where-Object {$_.Name -like "OS_*"}

                    $NewOSDisk = Get-AzDisk -ResourceGroupName $TargetResourceGroup -DiskName $OSDiskObj.Name
                    $OSDiskName = $NewOSDisk.Name;

                    Write-ToLogFile -Message "OSDisk Name is $OSDiskName" -Verbose

                    $NewVM = Set-AzVMOSDisk -VM $NewVM -Name $NewOSDisk.Name -ManagedDiskId $NewOSDisk.Id -CreateOption "Attach" -StorageAccountType StandardSSD_LRS -Windows

                    try{
                        $MigratedVM = New-AzVM -ResourceGroupName $TargetResourceGroup -Location $VirtualMachine.Location -VM $NewVM -Verbose
                        Write-ToLogFile -Message "Migrated VM: $($MigratedVM | Format-Table | Out-String)" -Verbose

                        $CreatedVM = Get-AzVm -Name $VirtualMachine.VMName -ResourceGroupName $TargetResourceGroup

                        Write-ToLogFile -Message "Created VM: $($CreatedVM | Format-Table | Out-String)" -Verbose

                        $DataDisks = $MigrationDisks | Where-Object {$_.Name -like "DD_*"}
                        if ($DataDisks.Count -gt 0)
                        {
                            $lunCount = 0;
                            $NewSub = $CreatedVM.ResourceGroupName
                            Write-Host "$NewSub" -ForegroundColor White -BackgroundColor Blue
                            Foreach ($Disk in $DataDisks)
                            {
                                try {
                                    Write-ToLogFile -Message "Adding Azure Disk $($Disk.Name)"
                                    Add-AzVMDataDisk -VM $CreatedVM -Name $Disk.Name -ManagedDiskId $Disk.Id -Caching 'ReadOnly' -DiskSizeInGB $Disk.DiskSizeGB -CreateOption 'Attach' -lun $lunCount

                                    Update-AzVM -VM $CreatedVM -ResourceGroupName $NewSub -Verbose
                                } catch {
                                    Write-ToLogFile $Error -Verbose
                                }
                                $lunCount ++
                            }
                        }

                    return $true

                    } catch {
                        throw $Error[0]
                    }
                }
            }
    }
}

#region Microsoft-provided sample functions
<#
 Microsoft provides programming examples for illustration only, without warranty either expressed or
 implied, including, but not limited to, the implied warranties of merchantability and/or fitness
 for a particular purpose.

 This sample assumes that you are familiar with the programming language being demonstrated and the
 tools used to create and debug procedures. Microsoft support professionals can help explain the
 functionality of a particular procedure, but they will not modify these examples to provide added
 functionality or construct procedures to meet your specific needs. if you have limited programming
 experience, you may want to contact a Microsoft Certified Partner or the Microsoft fee-based consulting
 line at (800) 936-5200.
#>
# Query, Start, Restart or Stop (deallocate) selected Azure RM VMs in serial or parallel. In serial, VMs are actioned in alphabetical order (Query/Start/Restart) or reverse alphabetical order (Stop).
function Request-AzVmAction
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [String]$ResourceGroupName,
        [Parameter(Mandatory=$true)]
        [ValidateSet("Start","Stop","StopButStayProvisioned","Restart","Query")]
        [String]$Action,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [ValidateSet("Serial","Parallel")]
        [String]$Mode,
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [String]$vmName
    )

    if (!$Mode -and !$vmName)
    {
        Write-Verbose -Message " - 'Mode' not specified so VMs will $Action one-at-a-time. Use -Mode Parallel to $Action VMs in parallel."
        $Mode = "Serial"
    }
    if ($Action -eq "Query")
    {
        #Write-Verbose -Message " - Querying VMs doesn't make much sense in parallel, so resetting the Mode to 'Serial'."
        #$Mode = "Serial"
    }
    $subscriptionName = (Get-AzContext).Subscription.Name
    $vmsToAction = $null
    $colorParameter = @{ForegroundColor = "White"}
    if ($vmName) # Means we have specified a single VM name via parameter
    {
        # Create an object from the $vmName so we can add a Name property
        $vmObject = New-Object -TypeName PSObject -Property @{"Name" = $vmName}
        $vmsSelected += $vmObject
        if ($Mode -eq "Parallel")
        {
            Write-Verbose -Message " - Only one VM selected, so 'Parallel' has no effect here..."
            $Mode = "Serial"
        }
    }
    else # No VM name specified; prompt for values
    {
        # If we have specified a resource name, check its validity and set the ResourceGroupName parameter
        if (![string]::IsNullOrEmpty($ResourceGroupName))
        {
            if (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue -WarningAction Continue)
            {
                Write-Output " - Enumerating all VMs in resource group '$ResourceGroupName'..."
                $resourceGroupNameParameter = @{ResourceGroupName = $ResourceGroupName}
            }
            else
            {
                Write-Warning "Invalid resource group name '$ResourceGroupName' specified."
                $resourceGroupNameParameter = @{}
            }
        }
        else # Just get all VMs at the subscription level
        {
            Write-Output " - Enumerating all VMs in subscription '$subscriptionName'..."
            $resourceGroupNameParameter = @{}
        }
        [array]$allVMs = Get-AzVm @resourceGroupNameParameter -WarningAction SilentlyContinue
        if ($allVMs.Count -gt 1) # Only prompt if there are multiple VMs to select from
        {
            Write-Host -ForegroundColor Cyan " - Prompting for names of VMs to $($Action.ToUpper()) in $Mode..."
            $vmsSelected = Get-AzVm @resourceGroupNameParameter -WarningAction SilentlyContinue | Select-Object Name, ResourceGroupName | Sort-Object Name | Out-GridView -Title "Select one or more Azure VM(s) to $($Action.ToUpper()) in $Mode..." -OutputMode Multiple
        }
        elseif ($allVMs.Count -eq 1)
        {
            Write-Output " - VM '$allVMs[0]' auto-selected since it was the only one found."
            $vmsSelected = $allVMs[0]
        }
        else # No VMs found
        {
            Write-Host -ForegroundColor Yellow " - No VMs found in your subscription."
        }
    }
    if ($vmsSelected.Count -gt 1)
    {
        Write-Output " - Building list of VMs to $($action.ToLower())..."
    }
    foreach ($vmSelected in $vmsSelected)
    {
        [array]$vmsToAction += (Get-AzVM -WarningAction SilentlyContinue | Where-Object {$_.Name -eq $vmSelected.Name})
    }
    $vmsToAction = $vmsToAction | Sort-Object Name
    if ($vmsToAction.Count -lt 1)
    {
        Write-Host -ForegroundColor Yellow " - No VMs selected, or none found in subscription; exiting."
    }
    if ($Action -like "Stop*")
    {
        $colorParameter = @{BackgroundColor = "DarkRed"}
        # Some possible statuses are: "VM starting", "VM running", "VM deallocating", "VM deallocated"
        $desiredStatus = "VM deallocated"
        $vmsToAction = $vmsToAction | Sort-Object Name -Descending # Meaning we will stop our VMs in reverse alphabetical order
        $actionVerb = "Stopping (Deallocating)"
        $actionState = "stopped"
        if ($Action -eq "StopButStayProvisioned")
        {
            Write-Warning -Message "You have requested to stop VM(s) without deprovisioning them; costs will continue to accrue while they are stopped."
            $desiredStatus = "VM stopped"
            $actionVerb = "Stopping"
            $actionState = "stopped (still provisioned)"
            $StayProvisionedSwitch = @{StayProvisioned = $true}
        }
        else
        {
            $StayProvisionedSwitch = @{}
        }
        $actionCommand = "Stop-AzVM -Force -Name `$(`$vmToAction.Name) -ResourceGroupName `$vmToAction.ResourceGroupName @StayProvisionedSwitch | Out-Null"
    }
    elseif ($Action -eq "Start")
    {
        $colorParameter = @{ForegroundColor = "Green"}
        # Some possible statuses are: "VM starting", "VM running", "VM deallocating", "VM deallocated"
        $desiredStatus = "VM running"
        $actionVerb = "Starting"
        $actionState = "started"
        $actionCommand = "Start-AzVM -Name `$(`$vmToAction.Name) -ResourceGroupName `$vmToAction.ResourceGroupName | Out-Null"
    }
    elseif ($Action -eq "Restart")
    {
        $colorParameter = @{ForegroundColor = "Green"}
        # Some possible statuses are: "VM starting", "VM running", "VM deallocating", "VM deallocated"
        $desiredStatus = "VM running"
        $actionVerb = "Restarting"
        $actionState = "started"
        $actionCommand = "Restart-AzVM -Name `$(`$vmToAction.Name) -ResourceGroupName `$vmToAction.ResourceGroupName | Out-Null"
    }
if ($Mode -eq "Parallel")
{
    $actionCommand = $actionCommand +" -AsJob"
}
    # Do things one at a time, or just action the single VM if we've only specified one
    $scriptStartTime = Get-Date
    foreach ($vmToAction in $vmsToAction)
    {
        $outVariableParameter = @{}
        if ($Mode -eq "Parallel")
        {
            $jobName = "job$($vmToAction.Name)"
            $outVariableParameter = @{"OutVariable" = $jobName}
        }
        $vmStatus = (Get-AzVM -Name $vmToAction.Name -ResourceGroupName $vmToAction.ResourceGroupName -Status -WarningAction SilentlyContinue).Statuses[1].DisplayStatus
        Write-Host -BackgroundColor DarkBlue -ForegroundColor White " - $($vmToAction.Name):"
        Write-Output "  - Current status: '$vmStatus'"
        if (($Action -eq "Restart") -and ($vmStatus -ne "VM running"))
        {
            Write-Warning "Requested action was '$Action' but status is '$vmStatus' - use 'Start' instead."
            throw
        }
        if ($Action -ne "Query")
        {
            if (($vmStatus -ne $desiredStatus) -or ($Action -eq "Restart"))
            {
                $vmOperationStartTime = Get-Date
                Write-Output "  - $actionVerb '$($vmToAction.Name)'..."
                Invoke-Expression -Command $actionCommand @outVariableParameter
                Start-Sleep -Seconds 5
                $vmStatus = (Get-AzVM -Name $vmToAction.Name -ResourceGroupName $vmToAction.ResourceGroupName -Status -WarningAction SilentlyContinue).Statuses[1].DisplayStatus
                Write-Host @colorParameter "  - VM '$($vmToAction.Name)' now has status '$vmStatus'."
                $delta,$null = (New-TimeSpan -Start $vmOperationStartTime -End (Get-Date)).ToString() -split "\."
                Write-Output "  - Operation completed in $delta."
            } else
            {
                Write-Host -ForegroundColor DarkGray "  - Already $actionState."
            }
            if ($Mode -eq "Parallel")
            {
                [array]$jobNames += $jobName
            }
        }
    }
    $delta,$null = (New-TimeSpan -Start $scriptStartTime -End (Get-Date)).ToString() -split "\."
    Write-Output " - Action '$action' completed in $delta."
}

function New-AzVmSnapshot
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$false)][ValidateNotNullOrEmpty()]
        [String]$vmName
    )

    if ([string]::IsNullOrEmpty($vmName)) # Prompt for VMs as none specified as a parameter value
    {
        # Prompt for VM(s)
        Write-Host -ForegroundColor Cyan " - Prompting for VM names..."
        $vmsSelected = Get-AzVm -WarningAction SilentlyContinue | Select-Object Name, ResourceGroupName | Sort-Object Name | Out-GridView -Title "Select one or more Azure VM(s) to power down / stop and snapshot..." -OutputMode Multiple
        foreach ($vmSelected in $vmsSelected)
        {
            [array]$vms += Get-AzVM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $vmSelected.Name}
        }
        [array]$vms = $vms | Sort-Object Name -Descending # Meaning we will stop our VMs in reverse alphabetical order
    }
    else
    {
        # Ensure the VM name provided matches an existing VM
        $vm = Get-AzVM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $vmName}
        if ($null -eq $vm)
        {
            throw "VM '$vmName' could not be found!"
        }
        else
        {
            $vms += $vm
        }
    }
    if ($vms.Count -lt 1)
    {
        Write-Host -ForegroundColor Yellow " - No VMs selected; exiting."
    }
    foreach ($vm in $vms)
    {
        # Stop the VM
        Request-AzVmAction -Action Stop -vmName $vm.Name -Mode Serial
        # Check if the OS disk is a managed disk
        $vmOsDiskFileName = $vm.StorageProfile.OsDisk.Name
        Write-Host -ForegroundColor Cyan "  - Creating snapshot of '$vmOsDiskFileName'..."
        $vmOsDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
        if ($null -ne $vmOsDiskId)
        {
            # Managed Disk way
            $osDiskSnapshotName = "$($vm.Name)-OSDisk_snapshot_$(Get-Date -Format yyyy-MM-dd_HH-mm)"
            $vmOsDiskSnapshotConfig = New-AzSnapshotConfig -Location $vm.Location -CreateOption Copy -SourceUri $vmOsDiskId -OsType $vm.StorageProfile.OsDisk.OsType
            Write-Output "   - Creating snapshot: '$osDiskSnapshotName'..."
            New-AzSnapshot -ResourceGroupName $vm.ResourceGroupName -Snapshot $vmOsDiskSnapshotConfig -SnapshotName $osDiskSnapshotName
        }
        else # Non-managed disk
        {
            # Get the OS disk associated with the VM
            $vmOsDiskUri = $vm.StorageProfile.OsDisk.Vhd.Uri
            # Get the OS disk blob filename and other details by getting specific sub-strings in the $vmOsDiskUri
            $vmOsDiskFileName = $vmOsDiskUri -split "/" | Select-Object -Last 1
            # Create a snapshot of the OS disk blob
            # Based on https://blogs.msdn.microsoft.com/cie/2016/05/17/using-blob-snapshots-with-powershell/
            ## Old way
            # Get storage account details
            # Infer the storage account name from the OS disk URI. There's probably a better way.
            $vmOsDiskStorageAccountName = $vmOsDiskUri.Replace('https://','') -split '\.' | Select-Object -First 1
            $vmOsDiskStorageAccount = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $vmOsDiskStorageAccountName}
            $vmOsDiskResourceGroupName = $vmOsDiskStorageAccount.ResourceGroupName
            $vmOsDiskStorageAccountAccessKey = (Get-AzStorageAccountKey -ResourceGroupName $vmOsDiskResourceGroupName -Name $vmOsDiskStorageAccountName)[0].Value
            $vmOsDiskStorageContext = New-AzStorageContext -StorageAccountName $vmOsDiskstorageAccountName -StorageAccountKey $vmOsDiskStorageAccountAccessKey
            $vmOsDiskStorageAccountContainerUri = ($vmOsDiskUri.TrimEnd($vmOsDiskFileName)).TrimEnd("/")
            $vmOsDiskStorageAccountContainerName = $vmOsDiskStorageAccountContainerUri -split "/" | Select-Object -Last 1
            $vmOsDiskFileBlob = Get-AzStorageBlob -Context $vmOsDiskStorageContext -Container $vmOsDiskStorageAccountContainerName -Blob $vmOsDiskFileName
            $vmOsDiskFileBlob.ICloudBlob.CreateSnapshotAsync()
        }
        # Get the data disk(s) attached to the VM
        [array]$vmDataDisks = $vm.StorageProfile.DataDisks
        if ($vmDataDisks.Count -ge 1)
        {
            Write-Host -ForegroundColor Cyan "  - $($vmDataDisks.Count) data disk(s) found."
            # Back up each of the data disks
            foreach ($vmDataDisk in $vmDataDisks)
            {
                $vmDataDiskFileName =$vmDataDisk.Name
                Write-Output -ForegroundColor Cyan "  - Creating snapshot of '$vmDataDiskFileName'..."
                $vmDataDiskId = $vmDataDisk.ManagedDisk.Id
                if ($null -ne $vmDataDiskId)
                {
                    # Managed Disk way
                    $dataDiskSnapshotName = "$($vmDataDisk.Name)_snapshot_$(Get-Date -Format yyyy-MM-dd_HH-mm)"
                    $vmDataDiskSnapshotConfig = New-AzSnapshotConfig -Location $vm.Location -CreateOption Copy -SourceUri $vmDataDiskId -OsType $vm.StorageProfile.OsDisk.OsType
                    Write-Output "   - Creating snapshot: '$dataDiskSnapshotName'..."
                    New-AzSnapshot -ResourceGroupName $vm.ResourceGroupName -Snapshot $vmDataDiskSnapshotConfig -SnapshotName $dataDiskSnapshotName
                }
                else # Non-managed disk
                {
                    $vmDataDiskUri = $vmDataDisk.Vhd.Uri
                    # Get storage account details
                    # Infer the storage account name from the disk URI. There's probably a better way.
                    $vmDataDiskStorageAccountName = $vmDataDiskUri.Replace('https://','') -split '\.' | Select-Object -First 1
                    $vmDataDiskStorageAccount = Get-AzStorageAccount | Where-Object {$_.StorageAccountName -eq $vmDataDiskStorageAccountName}
                    $vmDataDiskResourceGroupName = $vmDataDiskStorageAccount.ResourceGroupName
                    $vmDataDiskStorageAccountAccessKey = (Get-AzStorageAccountKey -ResourceGroupName $vmDataDiskResourceGroupName -Name $vmDataDiskStorageAccountName)[0].Value
                    $vmDataDiskStorageContext = New-AzStorageContext -StorageAccountName $vmDataDiskStorageAccountName -StorageAccountKey $vmDataDiskStorageAccountAccessKey
                    $vmDataDiskStorageAccountContainerUri = ($vmDataDiskUri.TrimEnd($vmDataDiskFileName)).TrimEnd("/")
                    $vmDataDiskStorageAccountContainerName = $vmDataDiskStorageAccountContainerUri -split "/" | Select-Object -Last 1
                    # Create a snapshot of the Data disk blob
                    # Based on https://blogs.msdn.microsoft.com/cie/2016/05/17/using-blob-snapshots-with-powershell/
                    $vmDataDiskFileBlob = Get-AzStorageBlob -Context $vmDataDiskStorageContext -Container $vmDataDiskStorageAccountContainerName -Blob $vmDataDiskFileName
                    $vmDataDiskFileBlob.ICloudBlob.CreateSnapshot()
                }
            }
        }
        Write-Output "  - Done taking snapshots of all disks for VM '$($vm.Name)'."
    }
    Write-Output " - Done."
}
#endregion

# Install-RequisiteModules -SourceSubscription "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# $Migrate = Start-AzureVMMigration -AzureVMName "VMName" -CurrentSubscriptionId "SourceSubscription" -TargetSubscriptionID "TargetSubscription" -TargetSubnetName "Subnet Name" -TargetVNetName "VNet Name" -TargetResourceGroup "ResourceGroupName" -Verbose

# if ($Migrate.ProvisioningState -eq $true)
# {
#     Write-ToLogFile "Migration Complete!" -Verbose
# }
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
            Write-ToLogFile "$($VM.OSDisk.Name) is an unmanaged disk! Unable to do snapshot right now... sorry..." 
            throw "OS Disk is an unmanaged disk. This is currently unsupported."
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



# Install-RequisiteModules -SourceSubscription "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# $Migrate = Start-AzureVMMigration -AzureVMName "VMName" -CurrentSubscriptionId "SourceSubscription" -TargetSubscriptionID "TargetSubscription" -TargetSubnetName "Subnet Name" -TargetVNetName "VNet Name" -TargetResourceGroup "ResourceGroupName" -Verbose

# if ($Migrate.ProvisioningState -eq $true)
# {
#     Write-ToLogFile "Migration Complete!" -Verbose
# }
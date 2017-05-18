<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
$result = ""
$testResult = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if ($isDeployed)
{
	try
	{
		$hs1VIP = $AllVMData.PublicIP
		$hs1vm1sshport = $AllVMData.SSHPort
		$hs1ServiceUrl = $AllVMData.URL
		$hs1vm1Dip = $AllVMData.InternalIP
        
        $vmName = $AllVMData.RoleName
        $rgNameOfVM = $AllVMData.ResourceGroupName
        $storageAccountName =  $xmlConfig.config.Azure.General.ARMStorageAccount
        
        $rgNameOfBlob = Get-AzureRmStorageAccount | where {$_.StorageAccountName -eq $storageAccountName} | Select-Object -ExpandProperty ResourceGroupName
        $storageAcc=Get-AzureRmStorageAccount -ResourceGroupName $rgNameOfBlob -Name $storageAccountName 

        #Pulls the VM info for later 
        $vmdiskadd=Get-AzurermVM -ResourceGroupName $rgNameOfVM -Name $vmName 

        #Sets the URL string for where to store your vhd files
        #Also adds the VM name to the beginning of the file name 
        $DataDiskUri=$storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/" + $vmName 

        #Max data disks are 16 for A4
		if( $currentTestData.TestType -eq "random" )
		{
			LogMsg "Add SCSI disks with random LUNs"
			$length = 16
			$testLUNs = @()
			for( $i = 0; $i -lt $length; $i++ )
			{
				do 
				{
					$random = Get-Random
					$lun = $random % $length
				} while ( $lun -in $testLUNs )
				$testLUNs += $lun
			}
		}
		else
		{
			LogMsg "Add SCSI disks with sequential LUNs"
			$testLUNs= 0..15
			$length = $testLUNs.Length
		}

        foreach ($newLUN in $testLUNs)
        {
            $diskSize = (($newLUN + 1)*10)
            LogMsg "Adding disk ---- LUN: $newLUN   DiskSize: $diskSize"
            Add-AzureRmVMDataDisk -CreateOption empty -DiskSizeInGB $diskSize -Name $vmName-$newLUN -VhdUri $DataDiskUri-Data$newLUN.vhd -VM $vmdiskadd -Caching ReadWrite -lun $newLUN 
        }
        
        #Updates the VM with the disk config - does not require a reboot 
        Update-AzureRmVM -ResourceGroupName $rgNameOfVM -VM $vmdiskadd

		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
		LogMsg "Executing : bash $($currentTestData.testScript) $length"
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "bash $($currentTestData.testScript) $length" -runAsSudo

		RemoteCopy -download -downloadFrom $hs1VIP -files "/root/state.txt, /root/summary.log" -downloadTo $LogDir -port $hs1vm1sshport -username $user -password $password
		$testResultOfAddDisks = Get-Content $LogDir\summary.log
		$testStatus = Get-Content $LogDir\state.txt
		LogMsg "Test result : $testResultOfAddDisks"
        if ($testStatus -eq "TestCompleted")
		{
			LogMsg "Add disks successfully"
            $testResultOfAddDisks = "PASS"
		}
        else
        {
            LogMsg "Add the VHDs failed"
            $testResultOfAddDisks = "FAIL"
        }
        
        $temp = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "camcontrol devlist | wc -l" -runAsSudo
        $temp = $temp.Split(" ")
        $diskNumsBeforRemoveVHD = $temp[$temp.length - 1]
		LogMsg "The sum of disks before removing: $diskNumsBeforRemoveVHD"
		
        #To delete the VHDs 
        $testResultOfRemoveDisks = "PASS"
        foreach ($newLUN in $testLUNs)
        {
            Remove-AzureRmVMDataDisk -VM $vmdiskadd -Name  $vmName-$newLUN
            sleep 10
            Update-AzureRmVM -ResourceGroupName $rgNameOfVM  -VM $vmdiskadd
            
            $temp = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "camcontrol devlist | wc -l" -runAsSudo
			$temp = $temp.Split(" ")
			$currentDiskNums = $temp[$temp.length - 1]
			LogMsg "The current disks: $currentDiskNums"
            $diffNum = [int]( $diskNumsBeforRemoveVHD - $currentDiskNums )
            if( $diffNum -ne 1 )
            {
                $testResultOfRemoveDisks = "FAIL"
                LogMsg "Remove the VHDs failed @LUN is $newLUN"
            }
            $diskNumsBeforRemoveVHD = $diskNumsBeforRemoveVHD - 1
        
        }

        $temp = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "camcontrol devlist | wc -l" -runAsSudo
		$temp = $temp.Split(" ")
		$out = $temp[$temp.length - 1]
		LogMsg "The current disks: $out"
		if( $out -eq 3  -and $testResultOfAddDisks -eq "PASS" -and  $testResultOfRemoveDisks -eq "PASS" )
        {
            $testResult = "PASS"
        }
        else
        {
            LogMsg "Delete the VHDs failed"
            $testResult = "FAIL"
        }
		
	}

	catch
	{
		$ErrorMessage =  $_.Exception.Message
		LogMsg "EXCEPTION : $ErrorMessage"   
	}
	Finally
	{
		$metaData = ""
		if (!$testResult)
		{
			$testResult = "Aborted"
		}
		$resultArr += $testResult
#$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName# if you want to publish all result then give here all test status possibilites. if you want just failed results, then give here just "FAIL". You can use any combination of PASS FAIL ABORTED and corresponding test results will be published!
	}   
}

else
{
	$testResult = "Aborted"
	$resultArr += $testResult
}

$result = GetFinalResultHeader -resultarr $resultArr

#Clean up the setup
DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

#Return the result and summery to the test suite script..
return $result

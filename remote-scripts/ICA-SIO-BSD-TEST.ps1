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

		
		$diskSize = 10
		$newLUN = 1
		$newDiskName = "freebsdTestVHD"
		 LogMsg "Adding disk ---- LUN: $newLUN   DiskSize: $diskSize GB"
		Add-AzureRmVMDataDisk -CreateOption empty -DiskSizeInGB $diskSize -Name $newDiskName -VhdUri $DataDiskUri-Data.vhd -VM $vmdiskadd -Caching ReadWrite -lun $newLUN 
        
 
        Update-AzureRmVM -ResourceGroupName $rgNameOfVM -VM $vmdiskadd

		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
		
		$NumberOfDisksAttached = 1
		LogMsg "Executing : bash $($currentTestData.testScript) $NumberOfDisksAttached"
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "bash $($currentTestData.testScript) $NumberOfDisksAttached" -runAsSudo

		
		# LogMsg "Executing : Install gcc"
		# RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "echo "y" | pkg install gcc" -runAsSudo
		
		# LogMsg "Executing : Install sio"
		# RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf /root/sio.tgz -C /root;cd /root/sio;make freebsd" -runAsSudo
		
		LogMsg "Executing : Install sio"
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf sio.tgz -C /root" -runAsSudo
		
		$sioTestSize = $currentTestData.fileSize
		$sioRunTime = $currentTestData.runTimeSec
		$sioFileName = "/dev/da2"
		
		#Actual Test Starts here..
        foreach ( $blockSize in $currentTestData.blockSizes.split(","))
        {
            foreach ( $numThread in $currentTestData.numThreads.split(","))
            {
				foreach ( $mode in $currentTestData.modes.split(","))
				{
					try 
					{
						$testMode = GetSIOMode $mode   
						if ($testMode -eq "-1 -1")
						{
						  Throw "The mode doesn't support. Check the mode and try again"
						}
												
						$sioOutputFile = "sio-output-${mode}-${blocksize}-${numThread}.log"
						$command = "nohup /root/sio/sio_ntap_freebsd $testMode $blockSize $sioTestSize $sioRunTime $numThread $sioFileName -direct > $sioOutputFile "
						$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command $command -runAsSudo
						WaitFor -seconds 10
						$isSioStarted  = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $sioOutputFile" ) -imatch "Version")
						if ( $isSioStarted )
						{ 
							LogMsg "SIO Test Started successfully for mode : ${mode}, blockSize : $blockSize, numThread : $numThread, FileSize : $sioTestSize and Runtime = $sioRunTime seconds.."
							WaitFor -seconds 60 
						}
						else
						{
							Throw "Failed to start sio tests."
						}
						$isSioFinished = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $sioOutputFile" ) -imatch "Threads")
						while (!($isSioFinished))
						{
							LogMsg "Sio Test is still running. Please wait.."
							$isSioFinished = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $sioOutputFile" ) -imatch "Threads")
							WaitFor -seconds 20
						}
						LogMsg "Great! SIO test is finished now."
						RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "$sioOutputFile" -downloadTo $LogDir -download
						# Rename-Item -Path "$LogDir\SioConsoleOutput.log" -NewName "SIOLOG-${iosize}k-$queDepth.log" -Force | Out-Null
						# LogMsg "Sio Logs saved at :  $LogDir\SIOLOG-${iosize}k-$queDepth.log"
						# LogMsg "Removing all log files from test VM."
						# $out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -rf *.log" -runAsSudo
						$testResult = "PASS"
					}
					catch
					{
						$ErrorMessage =  $_.Exception.Message
						LogMsg "EXCEPTION : $ErrorMessage"   
					}
					finally
					{
						if (!$testResult)
						{
							$testResult = "Aborted"
						}
						$resultArr += $testResult
						$resultSummary +=  CreateResultSummary -testResult $testResult -metaData $metaData -checkValues "PASS,FAIL,ABORTED" -testName $currentTestData.testName
					}				
				}
            }
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

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

		# $diskPath = "/mnt"
		$diskPath = "/dev/da2"
        $fileSize = currentTestData.fileSize
        $ioengine = currentTestData.ioengine
        $runTime = currentTestData.runtimeSeconds
		
        #Actual Test Starts here..
        foreach ( $blockSize in $currentTestData.blockSizes.split(","))
        {
            foreach ( $numThread in $currentTestData.numThreads.split(","))
			{
				foreach ( $iodepth in $currentTestData.iodepths.split(","))
				{
					foreach ( $testMode in $currentTestData.modes.split(","))
					{
						try 
						{
							$fioOutputFile = "fio-output-${testmode}-${blocksize}-${numThread}-${iodepths}.log"
							$fioCommonOptions="--size=${fileSize} --direct=1 --ioengine=${ioengine} --filename=${diskPath} --overwrite=1 --iodepth=$iodepth --runtime=${runTime}"
							$command="fio ${fioCommonOptions} --readwrite=$testmode --bs=$blockSize --numjobs=$numThread --name=fiotest --output=$fioOutputFile"
							$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command $command -runAsSudo
							WaitFor -seconds 10
							$isFioStarted  = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $fioOutputFile" ) -imatch "Starting")
							if ( $isFioStarted )
							{ 
								LogMsg "FIO Test Started successfully for mode : ${testMode}, blockSize : $blockSize, numThread : $numThread, FileSize : $fileSize and Runtime = $runTime seconds.."
								WaitFor -seconds 60 
							}
							else
							{
								Throw "Failed to start FIO tests."
							}
							$isFioFinished = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $fioOutputFile" ) -imatch "Run status group")
							while (!($isFioFinished))
							{
								LogMsg "FIO Test is still running. Please wait.."
								$isFioFinished = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $fioOutputFile" ) -imatch "Run status group")
								WaitFor -seconds 20
							}
							LogMsg "Great! FIO test is finished now."
							RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "$fioOutputFile" -downloadTo $LogDir -download
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

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

		
		$diskSize = 100
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

		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "date >  summary.log;uname -a >>  summary.log" -runAsSudo
		
		# LogMsg "Executing : Install gcc"
		# RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "echo "y" | pkg install gcc" -runAsSudo
		
		# LogMsg "Executing : Install sio"
		# RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf /root/sio.tgz -C /root;cd /root/sio;make freebsd" -runAsSudo
		
		LogMsg "Executing : Install sio"
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf sio.tgz -C /root" -runAsSudo
		
		$testFileSize = $currentTestData.fileSize
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
						
						$blockSizeInKB=$blocksize.split("k")[0].trim()
						$fileSizeInGB=$testFileSize.split("g")[0].trim()
						
						$sioOutputFile = "${blockSizeInKB}-$fileSizeInGB-${numThread}-${mode}-${sioRunTime}-freebsd.sio.log"
						$command = "nohup /root/sio/sio_ntap_freebsd $testMode $blockSize $testFileSize $sioRunTime $numThread $sioFileName -direct > $sioOutputFile "
						$runMaxAllowedTime = [int]$sioRunTime + 180
						$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command $command -runAsSudo -runMaxAllowedTime  $runMaxAllowedTime
						WaitFor -seconds 10
						$isSioStarted  = (( RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cat $sioOutputFile" ) -imatch "Version")
						if ( $isSioStarted )
						{ 
							LogMsg "SIO Test Started successfully for mode : ${mode}, blockSize : $blockSize, numThread : $numThread, FileSize : $testFileSize and Runtime = $sioRunTime seconds.."
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
						
						
						if( $isSioFinished )
						{
							LogMsg "Great! SIO test is finished now."
							$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mkdir /usr/sio" -runAsSudo
							$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp $sioOutputFile  /usr/sio" -runAsSudo
							$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp summary.log /usr" -runAsSudo
				
							RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf report.tgz -C /usr" -runAsSudo
							RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "python /usr/report/sioTestEntry.py" -runAsSudo
							
							RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "result.log" -downloadTo $LogDir -download
							RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "$sioOutputFile" -downloadTo $LogDir -download
							
							LogMsg "Uploading the test results.."
							if( $xmlConfig.config.Azure.database.server )
							{
								$dataSource = $xmlConfig.config.Azure.database.server
								$user = $xmlConfig.config.Azure.database.user
								$password = $xmlConfig.config.Azure.database.password
								$database = $xmlConfig.config.Azure.database.dbname
								$dataTableName = $xmlConfig.config.Azure.database.dbtable
							}
							else
							{
								$dataSource = $env:databaseServer
								$user = $env:databaseUser
								$password = $env:databasePassword
								$database = $env:databaseDbname
								$dataTableName = $env:databaseDbtable
							}
							
							if ($dataSource -And $user -And $password -And $database -And $dataTableName) 
							{
								$connectionString = "Server=$dataSource;uid=$user; pwd=$password;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
								$KernelVersion = ""
								$InstanceSize = ""
								$bandwidth_KBps = 0
								$BlockSize_KB = 0
								$IOs = 0
								$HostType = "MS Azure"
								$FileSize_KB = 0
								$IOPS = 0
								$TestMode = ""
								$GuestOS = "FreeBSD"
								$NumThread = 0
								$RuntimeSec = 0
								$TestCaseName = "sio"
								
								$LogContents = Get-Content -Path "$LogDir\result.log"
								foreach ($line in $LogContents)
								{
									if ( $line -imatch "KernelVersion:" )
									{
										$KernelVersion = $line.Split(":")[1].trim()
									}
									
									if ( $line -imatch "InstanceSize:" )
									{
										$InstanceSize = $line.Split(":")[1].trim()
									}
									
									if ( $line -imatch "bandwidth_KBps:" )
									{
										$bandwidth_KBps = [int]($line.Split(":")[1].trim())
									}	
									
									if ( $line -imatch "BlockSize_KB:" )
									{
										$BlockSize_KB = [int]($line.Split(":")[1].trim())
									}
									
									if ( $line -imatch "IOs:" )
									{
										$IOs = [int]($line.Split(":")[1].trim())
									}
									
									if ( $line -imatch "FileSize_KB:" )
									{
										$FileSize_KB = [int]($line.Split(":")[1].trim())
									}
									
									if ( $line -cmatch "IOPS:" )
									{
										"This line is: $line"
										$IOPS = [float]($line.Split(":")[1].trim())
									}
									
									if ( $line -imatch "TestMode:" )
									{
										$TestMode = $line.Split(":")[1].trim()
									}
									
									if ( $line -imatch "NumThread:" )
									{
										$NumThread = [int]($line.Split(":")[1].trim())
									}
									
									if ( $line -imatch "RuntimeSec:" )
									{
										$RuntimeSec = [int]($line.Split(":")[1].trim())
									}
								}

								
								$SQLQuery  = "INSERT INTO $dataTableName (TestCaseName,TestDate,HostType,InstanceSize,GuestOS,"
								$SQLQuery += "KernelVersion,BlockSize_KB,FileSize_KB,NumThread,TestMode,"
								$SQLQuery += "iops,bandwidth_KBps,RuntimeSec,IOs) VALUES "
									
								$SQLQuery += "('$TestCaseName','$(Get-Date -Format yyyy-MM-dd)','$HostType','$InstanceSize','$GuestOS',"
								$SQLQuery += "'$KernelVersion','$BlockSize_KB','$FileSize_KB','$NumThread',"
								$SQLQuery += "'$TestMode','$iops','$bandwidth_KBps','$RuntimeSec','$IOs')"
			
								LogMsg "SQLQuery:"
								LogMsg  $SQLQuery
								LogMsg  "ItemName                      Value"
								LogMsg  "TestMode                      $TestMode"
								LogMsg  "RuntimeSec                    $RuntimeSec"
								LogMsg  "bandwidth_KBps                $bandwidth_KBps"
								LogMsg  "BlockSize_KB                  $BlockSize_KB"
								LogMsg  "FileSize_KB                   $FileSize_KB"
								LogMsg  "IOPS                          $IOPS"
								LogMsg  "NumThread                     $NumThread"
								LogMsg  "KernelVersion                 $KernelVersion"
								LogMsg  "InstanceSize                  $InstanceSize"
								
								$uploadResults = $true
								#Check the result valid before uploading. TODO 
								
								if ($uploadResults)
								{
									$connection = New-Object System.Data.SqlClient.SqlConnection
									$connection.ConnectionString = $connectionString
									$connection.Open()

									$command = $connection.CreateCommand()
									$command.CommandText = $SQLQuery
									$result = $command.executenonquery()
									$connection.Close()
									LogMsg "Uploading the test results done!!"
									$testResult = "PASS"
								}
								else 
								{
									LogErr "Uploading the test results cancelled due to zero/invalid output for some results!"
									$testResult = "FAIL"
								}								
								
							}
							else
							{
								LogErr "Uploading the test results cancelled due to wrong database configuration"
								$testResult = "FAIL"
							}								
							

							
						}
						else
						{
							$testResult = "FAIL"
						}
						
						
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

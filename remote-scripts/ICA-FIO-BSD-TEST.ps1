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

		
		$diskSize = 200
		$newLUN = 1
		$newDiskName = "freebsdTestVHD"
		LogMsg "Adding disk ---- LUN: $newLUN   DiskSize: $diskSize GB"
		Add-AzureRmVMDataDisk -CreateOption empty -DiskSizeInGB $diskSize -Name $newDiskName -VhdUri $DataDiskUri-Data.vhd -VM $vmdiskadd -Caching ReadWrite -lun $newLUN 
        
 
        Update-AzureRmVM -ResourceGroupName $rgNameOfVM -VM $vmdiskadd

		RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
		
		RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "date >  summary.log;uname -a >>  summary.log" -runAsSudo
		
		$NumberOfDisksAttached = 1
		# LogMsg "Executing : bash $($currentTestData.testScript) $NumberOfDisksAttached"
		# RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "bash $($currentTestData.testScript) $NumberOfDisksAttached" -runAsSudo
		# $diskPath = "/mnt"
		
		$diskPath = "/dev/da2"
        $fileSize = $currentTestData.fileSize        
        $runTime = $currentTestData.runTimeSec
		
		if ($currentTestData.ioengine)
		{
			$ioengine = $currentTestData.ioengine
		}
		else
		{
			$ioengine = "libaio"
		}

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
							$blockSizeInKB=$blocksize.split("k")[0].trim()
							$fileSizeInGB=$fileSize.split("g")[0].trim()							
							$fioOutputFile = "$blockSizeInKB-$iodepth-${ioengine}-$fileSizeInGB-$numThread-$testMode-${runTime}-freebsd.fio.log"
							$fioCommonOptions="--size=${fileSize} --direct=1 --ioengine=${ioengine} --filename=${diskPath} --overwrite=1 --iodepth=$iodepth --runtime=${runTime}"
							$command="fio ${fioCommonOptions} --readwrite=$testmode --bs=$blockSize --numjobs=$numThread --name=fiotest --output=$fioOutputFile"
							$runMaxAllowedTime = [int]$runTime + 180
							$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command $command -runAsSudo -runMaxAllowedTime  $runMaxAllowedTime
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
							
							if( $isFioFinished )
							{
							
								$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mkdir /usr/fio" -runAsSudo
								$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp $fioOutputFile  /usr/fio" -runAsSudo
								$out = RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp summary.log /usr" -runAsSudo
					
								RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf report.tgz -C /usr" -runAsSudo
								RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "python /usr/report/fioTestEntry.py" -runAsSudo
								
								RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "result.log" -downloadTo $LogDir -download
								RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "$fioOutputFile" -downloadTo $LogDir -download
								
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

									$TestCaseName = "fio"
									$avg_iops = 0
									$max_iops = 0
									$TestMode = ""
									$RuntimeSec = 0
									$QDepth = 0
									$bandwidth_KBps = 0
									$avg_iops = 0
									$max_iops = 0
									$TestMode = ""
									$RuntimeSec = 0
									$QDepth = 0
									$bandwidth_KBps = 0
									$stdev_iops = 0
									$QDepth = 0
									$BlockSize_KB = 0
									$FileSize_KB = 0
									$IOPS = 0
									$NumThread = 0
									$min_iops = 0
									$KernelVersion = ""
									$InstanceSize = ""
									$lat_usec = 0
									$TestDate = "2018-04-25"
									$IOEngine = ""
									$GuestOS = "FreeBSD"
									$HostType = "MS Azure"
									$DiskSetup = "Single"
									$DataPath = "No Need"
									
									$LogContents = Get-Content -Path "$LogDir\result.log"
									foreach ($line in $LogContents)
									{
									 
										if ( $line -imatch "bandwidth_KBps:" )
										{
											$bandwidth_KBps = [int]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "avg_iops:" )
										{
											$avg_iops = [float]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "max_iops:" )
										{
											$max_iops = [float]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "TestMode:" )
										{
											$TestMode = $line.Split(":")[1].trim()
										}
										
										if ( $line -imatch "RuntimeSec:" )
										{
											$RuntimeSec = [int]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "QDepth:" )
										{
											$QDepth = [int]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "stdev_iops:" )
										{
											$stdev_iops = [float]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "BlockSize_KB:" )
										{
											$BlockSize_KB = [int]($line.Split(":")[1].trim())
										}

										if ( $line -imatch "FileSize_KB:" )
										{
											$FileSize_KB = [int]($line.Split(":")[1].trim())
										}

										if ( $line -cmatch "IOPS:" )
										{
											$IOPS = [float]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "NumThread:" )
										{
											$NumThread = [int]($line.Split(":")[1].trim())
										}

										if ( $line -imatch "min_iops:" )
										{
											$min_iops = [float]($line.Split(":")[1].trim())
										}

										if ( $line -imatch "KernelVersion:" )
										{
											$KernelVersion = $line.Split(":")[1].trim()
										}

										if ( $line -imatch "InstanceSize:" )
										{
											$InstanceSize = $line.Split(":")[1].trim()
										}
										
										if ( $line -imatch "lat_usec:" )
										{
											$lat_usec = [float]($line.Split(":")[1].trim())
										}
										
										if ( $line -imatch "TestDate:" )
										{
											$TestDate = $line.Split(":")[1].trim()
										}
										
										if ( $line -imatch "IOEngine:" )
										{
											$IOEngine = $line.Split(":")[1].trim()
										}
								    }
								
								    $SQLQuery  = "INSERT INTO $dataTableName (TestCaseName,DataPath,TestDate,HostType,InstanceSize,GuestOS,"
								    $SQLQuery += "KernelVersion,DiskSetup,IOEngine,BlockSize_KB,FileSize_KB,QDepth,NumThread,TestMode,"
								    $SQLQuery += "iops,min_iops,max_iops,avg_iops,stdev_iops,bandwidth_KBps,lat_usec,RuntimeSec) VALUES "
									
									$SQLQuery += "('$TestCaseName','$DataPath','$(Get-Date -Format yyyy-MM-dd)','$HostType','$InstanceSize','$GuestOS',"
									$SQLQuery += "'$KernelVersion','$DiskSetup','$IOEngine','$BlockSize_KB','$FileSize_KB','$QDepth','$NumThread',"
									$SQLQuery += "'$TestMode','$iops','$min_iops','$max_iops','$avg_iops','$stdev_iops','$bandwidth_KBps','$lat_usec','$RuntimeSec')"
			
									
									LogMsg "SQLQuery:"
									LogMsg $SQLQuery
									
									LogMsg  "ItemName                      Value"
									LogMsg  "avg_iops                      $avg_iops"
									LogMsg  "max_iops                      $max_iops"
									LogMsg  "TestMode                      $TestMode"
									LogMsg  "RuntimeSec                    $RuntimeSec"
									LogMsg  "bandwidth_KBps                $bandwidth_KBps"
									LogMsg  "stdev_iops                    $stdev_iops"
									LogMsg  "QDepth                        $QDepth"
									LogMsg  "BlockSize_KB                  $BlockSize_KB"
									LogMsg  "FileSize_KB                   $FileSize_KB"
									LogMsg  "IOPS                          $IOPS"
									LogMsg  "NumThread                     $NumThread"
									LogMsg  "min_iops                      $min_iops"
									LogMsg  "KernelVersion                 $KernelVersion"
									LogMsg  "InstanceSize                  $InstanceSize"
									LogMsg  "lat_usec                      $lat_usec"
									LogMsg  "TestDate                      $TestDate"
									LogMsg  "IOEngine                      $IOEngine"

									$uploadResults = $true
									
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
									}
									else 
									{
										LogErr "Uploading the test results cancelled due to wrong database configuration."
										$testResult = "FAIL"
									}
								
								
									LogMsg "Great! FIO test is finished now."
									$testResult = "PASS"
								}
								else
								{
									LogErr "Uploading the test results cancelled due to zero throughput for some connections!!"
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
		
		if( $testResult -eq "PASS" )
		{
			# RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "summary.log" -downloadTo $LogDir -download
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

#Return the result to the test suite script..
return $result

Import-Module .\TestLibs\RDFELibs.psm1 -Force

$testResult = ""
$result = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
	foreach ($VMdata in $allVMData)
	{
		if ($VMdata.RoleName -imatch $currentTestData.setupType)
		{
			$hs1VIP = $VMdata.PublicIP
			$hs1vm1sshport = $VMdata.SSHPort
			$hs1vm1tcpport = $VMdata.TCPtestPort
			$hs1ServiceUrl = $VMdata.URL
			$clientGroupName = $VMdata.ResourceGroupName
		}
		elseif ($VMdata.RoleName -imatch "DTAP")
		{
			$dtapServerIp = $VMdata.PublicIP
			$dtapServerSshport = $VMdata.SSHPort
			$dtapServerTcpport = $VMdata.TCPtestPort
			$serverGroupName = $VMdata.ResourceGroupName
		}
		
	}
	
	$cmd1="$python_cmd start-kqnetperf-server.py -p $dtapServerTcpport -t2 && mv -f Runtime.log start-server.py.log"
	$cmd2="$python_cmd start-kqnetperf-client.py -c $dtapServerIp -p $dtapServerTcpport -t20"

	$server = CreateIperfNode -nodeIp $dtapServerIp -nodeSshPort $dtapServerSshport -nodeTcpPort $dtapServerTcpport -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir -groupName $serverGroupName
	$client = CreateIperfNode -nodeIp $hs1VIP -nodeSshPort $hs1vm1sshport -nodeTcpPort $hs1vm1tcpport -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir -groupName $clientGroupName

	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "date >  summary.record;uname -a >>  summary.record" -runAsSudo
	
	RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
	
	RemoteCopy -uploadTo $dtapServerIp -port $dtapServerSshport -files $currentTestData.files -username $user -password $password -upload
	RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "chmod +x *" -runAsSudo
	
	LogMsg "Executing : Install qkperf"
	RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf kq_netperf.tgz " -runAsSudo
	RunLinuxCmd -username $user -password $password -ip $dtapServerIp -port $dtapServerSshport -command "tar -xvzf kq_netperf.tgz " -runAsSudo
	
	$resultArr = @()
	$result = "", ""
	$Subtests= $currentTestData.connections
	$connections = $Subtests.Split(",")	
	$runTimeSec= $currentTestData.runTimeSec	
	$threads= $currentTestData.threads
	$connections = $threads.Split(",")
	$dataPath = $currentTestData.DataPath

	foreach ($thread in $threads) 
	{
	    foreach ($connection in $connections) 
		{
			try
			{
				$testResult = $null
				
			    $server.cmd = "$python_cmd start-kqnetperf-server.py -p $dtapServerTcpport -t $thread  && mv -f Runtime.log start-server.py.log"			
				
				LogMsg "Test Started for Parallel Connections $connection"
				$client.cmd = "$python_cmd start-kqnetperf-client.py -4 $dtapServerIp -p $dtapServerTcpport -t $thread -c $connection -l $runTimeSec"
				mkdir $LogDir\$connection -ErrorAction SilentlyContinue | out-null
				$server.logDir = $LogDir + "\$connection"
				$client.logDir = $LogDir + "\$connection"
				$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshport -command "rm -rf kqnetperf-server.txt" -runAsSudo
				$testResult = KQperfClientServerTest $server $client  $runTimeSec
				if( $testResult -eq "PASS" )
				{
					#Rename the client log
					$newFileName = "$connection-$thread-$runTimeSec-freebsd.kq.log"
					Copy-Item "$($client.LogDir)\kqnetperf-client.txt"   "$($client.LogDir)\$newFileName"				
					RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files  "$($client.LogDir)\$newFileName" -username $user -password $password -upload
					RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv summary.record  /usr/summary.log " -runAsSudo
			
					RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mkdir /usr/kqperf" -runAsSudo
					RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "cp $newFileName /usr/kqperf" -runAsSudo
					
					RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "tar -xvzf report.tgz -C /usr" -runAsSudo
					RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "python /usr/report/kqTestEntry.py" -runAsSudo
					
					RemoteCopy -downloadFrom $hs1VIP -port $hs1vm1sshport -username $user -password $password -files "result.log" -downloadTo $LogDir -download
					
					LogMsg "Uploading the test results.."
					if( $xmlConfig.config.Azure.database.server )
					{
						$dataSource = $xmlConfig.config.Azure.database.server
						$databaseUser = $xmlConfig.config.Azure.database.user
						$databasePassword = $xmlConfig.config.Azure.database.password
						$database = $xmlConfig.config.Azure.database.dbname
						$dataTableName = $xmlConfig.config.Azure.database.dbtable
					}
					else
					{
						$dataSource = $env:databaseServer
						$databaseUser = $env:databaseUser
						$databasePassword = $env:databasePassword
						$database = $env:databaseDbname
						$dataTableName = $env:databaseDbtable
					}				

					if( $dataTableName -eq $null )
					{
						$dataTableName = $currentTestData.dataTableName
					}

					if ($dataSource -And $databaseUser -And $databasePassword -And $database -And $dataTableName) 
					{
					
						$connectionString = "Server=$dataSource;uid=$databaseUser; pwd=$databasePassword;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
						$TestCaseName = "kqperf"
						$HostType = "MS Azure"
						$InstanceSize = ""
						$GuestOS = "FreeBSD"
						$KernelVersion = ""
						$RuntimeSec = 0
						$MinBWInMbps = 0
						$MaxBWInMbps = 0
						$Connections = 0
						$NumThread = 0
						
						$LogContents = Get-Content -Path "$LogDir\result.log"
						foreach ($line in $LogContents)
						{
							if ( $line -imatch "InstanceSize:" )
							{
								$InstanceSize = $line.Split(":")[1].trim()
							}
							
							if ( $line -imatch "KernelVersion:" )
							{
								$KernelVersion = $line.Split(":")[1].trim()
							}
							
							if ( $line -imatch "RuntimeSec:" )
							{
								$RuntimeSec = [float]($line.Split(":")[1].trim())
							}
							
							if ( $line -imatch "min_bw_Mbps:" )
							{
								$MinBWInMbps = [float]($line.Split(":")[1].trim())
							}
							
							if ( $line -imatch "max_bw_Mbps:" )
							{
								$MaxBWInMbps = [float]($line.Split(":")[1].trim())
							}
							
							if ( $line -imatch "NumberOfConnections:" )
							{
								$Connections = [int]($line.Split(":")[1].trim())
							}
							
							if ( $line -imatch "NumThread:" )
							{
								$NumThread = [int]($line.Split(":")[1].trim())
							}
							
						}

						
						$SQLQuery  = "INSERT INTO $dataTableName (TestCaseName,TestDate,HostType,InstanceSize,GuestOS,"
						$SQLQuery += "KernelVersion,RuntimeSec,MaxBWInMbps,MinBWInMbps,Connections,NumThread,DataPath) VALUES "
						
						$SQLQuery += "('$TestCaseName','$(Get-Date -Format yyyy-MM-dd)','$HostType','$InstanceSize','$GuestOS',"
						$SQLQuery += "'$KernelVersion','$RuntimeSec','$MaxBWInMbps','$MinBWInMbps','$Connections','$NumThread','$dataPath')"

						LogMsg "SQLQuery:"
						LogMsg $SQLQuery
						"ItemName                      Value"
						"RuntimeSec                    $RuntimeSec"
						"NumThread                     $NumThread"
						"KernelVersion                 $KernelVersion"
						"InstanceSize                  $InstanceSize"
						"MaxBWInMbps                   $MaxBWInMbps"
						"MinBWInMbps                   $MinBWInMbps"
						"Connections                   $Connections"
						"DataPath                      $dataPath"
						
						$uploadResults = $true
						#Check the results validation ? TODO
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
							
							#Delete the previous result
							RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -rf /usr/kqperf" -runAsSudo
							RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -f result.log"   -runAsSudo
							
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
						LogErr "Uploading the test results cancelled due to wrong database configuration!"
						$testResult = "FAIL"
					}
					

				}
				
			}

			catch
			{
				$ErrorMessage =  $_.Exception.Message
				LogMsg "EXCEPTION : $ErrorMessage"
				$testResult = "Aborted"
			}

			Finally
			{
				$metaData = $connection 
				if (!$testResult)
				{
					$testResult = "Aborted"
				}
				$resultArr += $testResult
			}
		}

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




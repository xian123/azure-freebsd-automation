Import-Module .\TestLibs\RDFELibs.psm1 -Force

$testResult = ""
$result = ""
$resultArr = @()
$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig
if($isDeployed)
{
	
	$KQClientIp = $allVMData[0].PublicIP
	$KQClientSshport = $allVMData[0].SSHPort
	$vmName =$allVMData[0].RoleName
    $rgNameOfVM = $allVMData[0].ResourceGroupName
	
	$KQServerIp = $allVMData[1].PublicIP
	$KQServerSshport = $allVMData[1].SSHPort
	$KQServerInterIp = $allVMData[1].InternalIP
	
	$cmd1="$python_cmd start-kqnetperf-server.py    && mv -f Runtime.log start-server.py.log"
	$cmd2="$python_cmd start-kqnetperf-client.py -4 $KQServerInterIp"

	$server = CreateIperfNode -nodeIp $KQServerIp -nodeSshPort $KQServerSshport  -nodeIperfCmd $cmd1 -user $user -password $password -files $currentTestData.files -logDir $LogDir
	$client = CreateIperfNode -nodeIp $KQClientIp -nodeSshPort $KQClientSshport  -nodeIperfCmd $cmd2 -user $user -password $password -files $currentTestData.files -logDir $LogDir 

	$vmInfo = Get-AzureRMVM –Name $vmName  –ResourceGroupName $rgNameOfVM
	$InstanceSize = $vmInfo.HardwareProfile.VmSize
	
	RemoteCopy -uploadTo $KQClientIp -port $KQClientSshport -files $currentTestData.files -username $user -password $password -upload
	RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "chmod +x *" -runAsSudo
	
	LogMsg "Install basic apps/tools."
	InstallPackagesOnFreebsd -username $user -password $password -ip $KQClientIp -port $KQClientSshport
	InstallPackagesOnFreebsd -username $user -password $password -ip $KQServerIp -port $KQServerSshport
	
	RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "bash $($currentTestData.testScript)" -runAsSudo
	RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "cp summary.log  /usr/summary.log " -runAsSudo
	
	RemoteCopy -uploadTo $KQServerIp -port $KQServerSshport -files $currentTestData.files -username $user -password $password -upload
	RunLinuxCmd -username $user -password $password -ip $KQServerIp -port $KQServerSshport -command "chmod +x *" -runAsSudo
	
	LogMsg "Executing : Install qkperf"
	RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "tar -xvzf kq_netperf.tgz " -runAsSudo
	RunLinuxCmd -username $user -password $password -ip $KQServerIp -port $KQServerSshport -command "tar -xvzf kq_netperf.tgz " -runAsSudo
	
	$resultArr = @()
	$connections= $currentTestData.connections.Split(",")
	$runTimeSec= $currentTestData.runTimeSec	
	$dataPath = $currentTestData.DataPath
	
	#The /usr/kqperf directory is used for parsing the KQ result
	RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "mkdir /usr/kqperf" -runAsSudo
	RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "tar -xvzf report.tgz -C /usr" -runAsSudo

	foreach ($connection in $connections) 
	{
		try
		{
			$testResult = $null
			
			$server.cmd = "$python_cmd start-kqnetperf-server.py   && mv -f Runtime.log start-server.py.log"			
			
			LogMsg "Test Started for Parallel Connections $connection"
			$client.cmd = "$python_cmd start-kqnetperf-client.py -4 $KQServerInterIp   -c $connection -l $runTimeSec"
			mkdir $LogDir\$connection -ErrorAction SilentlyContinue | out-null
			$server.logDir = $LogDir + "\$connection"
			$client.logDir = $LogDir + "\$connection"
			$suppressedOut = RunLinuxCmd -username $server.user -password $server.password -ip $server.ip -port $server.sshport -command "rm -rf kqnetperf-server.txt" -runAsSudo
			$testResult = KQperfClientServerTest $server $client  $runTimeSec
			if( $testResult -eq "PASS" )
			{
				#Rename the client log
				$newFileName = "$connection-$runTimeSec-freebsd.kq.log"
				Copy-Item "$($client.LogDir)\kqnetperf-client.txt"   "$($client.LogDir)\$newFileName"				

				RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "cp kqnetperf-client.txt /usr/kqperf/$newFileName" -runAsSudo
				RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "python /usr/report/kqTestEntry.py" -runAsSudo
				RemoteCopy -downloadFrom $KQClientIp -port $KQClientSshport -username $user -password $password -files "result.log" -downloadTo $LogDir -download
				
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
					$TestCaseName = "azure_kq_perf"
					$HostType = "MS Azure"
					$GuestOS = "FreeBSD"
					$KernelVersion = ""
					$GuestDistro = ""
					$RuntimeSec = 0
					$MinBWInMbps = 0
					$MaxBWInMbps = 0
					$BWInMbps = 0
					$Connections = 0
					$NumThread = 0
					$HostBy = $xmlConfig.config.Azure.General.Location
					$HostBy = $HostBy.Replace('"',"")
					
					$LogContents = Get-Content -Path "$LogDir\result.log"
					foreach ($line in $LogContents)
					{
						if ( $line -imatch "GuestDistro:" )
						{
							$GuestDistro = $line.Split(":")[1].trim()
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
						
						if ( $line -imatch "total_bw_Mbps:" )
						{
							$BWInMbps = [float]($line.Split(":")[1].trim())
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

					
					$SQLQuery  = "INSERT INTO $dataTableName (TestCaseName,TestDate,HostType,HostBy,GuestDistro,InstanceSize,GuestOS,"
					$SQLQuery += "KernelVersion,RuntimeSec,BWInMbps,MaxBWInMbps,MinBWInMbps,Connections,NumThread,DataPath) VALUES "
					
					$SQLQuery += "('$TestCaseName','$(Get-Date -Format yyyy-MM-dd)','$HostType','$HostBy','$GuestDistro','$InstanceSize','$GuestOS',"
					$SQLQuery += "'$KernelVersion','$RuntimeSec','$BWInMbps','$MaxBWInMbps','$MinBWInMbps','$Connections','$NumThread','$dataPath')"

					LogMsg  "SQLQuery:"
					LogMsg  $SQLQuery
					LogMsg  "ItemName                      Value"
					LogMsg  "RuntimeSec                    $RuntimeSec"
					LogMsg  "NumThread                     $NumThread"
					LogMsg  "KernelVersion                 $KernelVersion"
					LogMsg  "InstanceSize                  $InstanceSize"
					LogMsg  "BWInMbps                      $BWInMbps"
					LogMsg  "MaxBWInMbps                   $MaxBWInMbps"
					LogMsg  "MinBWInMbps                   $MinBWInMbps"
					LogMsg  "Connections                   $Connections"
					LogMsg  "DataPath                      $dataPath"
					LogMsg  "HostBy                        $HostBy"
					LogMsg  "GuestDistro                   $GuestDistro"
					
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
			
			#Delete the previous result
			RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "rm -rf /usr/kqperf/*.log" -runAsSudo
			RunLinuxCmd -username $user -password $password -ip $KQClientIp -port $KQClientSshport -command "rm -f result.log kqnetperf-client.txt"   -runAsSudo
			
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




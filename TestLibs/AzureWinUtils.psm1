﻿
Import-Module .\TestLibs\RDFELibs.psm1 -Force

#LogMsg ()
# Operation : Prints the messages, warnings, errors
# Parameter : message string

function LogMsg([string]$msg, [Boolean]$WriteHostOnly, [Boolean]$NoLogsPlease, [switch]$LinuxConsoleOuput)
{
    #Masking the password.
    $pass2 = $password.Replace('"','')
    $msg = $msg.Replace($pass2,"$($pass2[0])***$($pass2[($pass2.Length) - 1])")
    foreach ( $line in $msg )
    {
        $now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss : ")
        $tag="INFO : "
        $color = "green"
        if(!$WriteHostOnly -and !$NoLogsPlease)
        {
            if ( $LinuxConsoleOuput )
            {   
                $tag = "LinuxConsole"               
                Write-Host "$tag $now $line" -ForegroundColor Gray
            }
            else
            {
                write-host -f $color "$tag $now $line"
            }
            ($tag+ $now + $line) | out-file -encoding ASCII -append -filePath $logFile 
        }
        elseif ($WriteHostOnly)
        {
            write-host "$tag $now $line"
        }
        elseif ($NoLogsPlease)
        {
            #Nothing to do here.
        }
    }
}

function LogErr([string]$msg)
{
    #Masking the password.
    $pass2 = $password.Replace('"','')
    $msg = $msg.Replace($pass2,"$($pass2[0])***$($pass2[($pass2.Length) - 1])")
	$now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss : ")
	$tag="ERROR : "
	$color = "Red" 
	($tag+ $now + $msg) | out-file -encoding ASCII -append -filePath $logFile
	write-host -f $color "$tag $now $msg"
}

function LogWarn([string]$msg)
{      
    #Masking the password.
    $pass2 = $password.Replace('"','')
    $msg = $msg.Replace($pass2,"$($pass2[0])***$($pass2[($pass2.Length) - 1])")
	$now = [Datetime]::Now.ToUniversalTime().ToString("MM/dd/yyyy HH:mm:ss : ")
    $tag="WARNING : "
	$color = "Yellow" 
	($tag+ $now + $msg) | out-file -encoding ASCII -append -filePath $logFile
	write-host -f $color "$tag $now $msg"
}

function GetTestSummary($testCycle, [DateTime] $StartTime, [string] $xmlFilename, [string] $distro, $testSuiteResultDetails)
{
    <#
	.Synopsis
    	Append the summary text from each VM into a single string.
        
    .Description
        Append the summary text from each VM one long string. The
        string includes line breaks so it can be display on a 
        console or included in an e-mail message.
        
	.Parameter xmlConfig
    	The parsed xml from the $xmlFilename file.
        Type : [System.Xml]

    .Parameter startTime
        The date/time the ICA test run was started
        Type : [DateTime]

    .Parameter xmlFilename
        The name of the xml file for the current test run.
        Type : [String]
        
    .ReturnValue
        A string containing all the summary message from all
        VMs in the current test run.
        
    .Example
        GetTestSummary $testCycle $myStartTime $myXmlTestFile
	
#>
    
	$endTime = [Datetime]::Now.ToUniversalTime()
	$testSuiteRunDuration= $endTime - $StartTime    
	$testSuiteRunDuration=$testSuiteRunDuration.Days.ToString() + ":" +  $testSuiteRunDuration.hours.ToString() + ":" + $testSuiteRunDuration.minutes.ToString()
    $str = "<br />Test Results Summary<br />"
    $str += "ICA test run on " + $startTime
    $str += "<br />Image under test " + $distro
	$str += "<br />Total Executed TestCases " + $testSuiteResultDetails.totalTc + " (" + $testSuiteResultDetails.totalPassTc + " Pass" + ", " + $testSuiteResultDetails.totalFailTc + " Fail" + ", " + $testSuiteResultDetails.totalAbortedTc + " Abort)"
	$str += "<br />Total Execution Time(dd:hh:mm) " + $testSuiteRunDuration.ToString()
    $str += "<br />XML file: $xmlFilename<br /><br />"
	        
    # Add information about the host running ICA to the e-mail summary
    $str += "<pre>"
    $str += $testCycle.emailSummary + "<br />"
    $hostName = hostname
    $str += "<br />Logs can be found at \\${hostname}\TestResults\" + $xmlFilename + "-" + $StartTime.ToString("yyyyMMdd-HHmmss") + "<br /><br />"
    $str += "</pre>"
    $plainTextSummary = $str
    $strHtml =  "<style type='text/css'>" +
			".TFtable{width:800px; border-collapse:collapse; }" +
			".TFtable td{ padding:7px; border:#4e95f4 1px solid;}" +
			".TFtable tr{ background: #b8d1f3;}" +
			".TFtable tr:nth-child(odd){ background: #dbe1e9;}" +
			".TFtable tr:nth-child(even){background: #ffffff;}</style>" +
            "<Html><head><title>Test Results Summary</title></head>" +
            "<body style = 'font-family:sans-serif;font-size:13px;color:#000000;margin:0px;padding:30px'>" +
            "<br/><h1 style='background-color:lightblue;width:800'>Test Results Summary - ${xmlFilename} </h1>"
    $strHtml += "<h2 style='background-color:lightblue;width:800'>ICA test run on - " + $startTime + "</h2><span style='font-size: medium'>"
    $strHtml += "<br /><br/>Image under test - " + $distrHtmlo
    $strHtml += "<br /><br/>Total Executed TestCases - " + $testSuiteResultDetails.totalTc + " (" +
	$testSuiteResultDetails.totalPassTc + " - <span style='background-color:green'>PASS</span>" + ", " +
	$testSuiteResultDetails.totalFailTc + " - <span style='background-color:red'>FAIL</span>" + ", " + 
	$testSuiteResultDetails.totalAbortedTc + " - <span style='background-color:yellow'>ABORTED</span>)"

    $strHtml += "<br /><br/>Total Execution Time(dd:hh:mm) " + $testSuiteRunDuration.ToString()
    $strHtml += "<br /><br/>XML file: $xmlFilename<br /><br /></span>"

    # Add information about the host running ICA to the e-mail summary
    $strHtml += "<table border='0' class='TFtable'>"
    $strHtml += $testCycle.htmlSummary
    $strHtml += "</table>"
    $currentNWPath = (hostname) + "\" + (pwd).Path.Replace(":", "$")
    $strHtml += "<br /><br/> <a href='\\${currentNWPath}\TestResults\" + $xmlFilename + "-" + $StartTime.ToString("yyyyMMdd-HHmmss") + "'>Logs can be found here </a><br /><br />"
    $strHtml += "</body></Html>"

    if (-not (Test-Path(".\temp\CI"))) {
        mkdir ".\temp\CI" | Out-Null 
    }

	Set-Content ".\temp\CI\index.html" $strHtml
	return $plainTextSummary, $strHtml
}

function SendEmail([XML] $xmlConfig, $body)
{
    <#
	.Synopsis
    	Send an e-mail message with test summary information.
        
    .Description
        Collect the test summary information from each testcycle.  Send an
        eMail message with this summary information to emailList defined
        in the xml config file.
        
	.Parameter xmlConfig
    	The parsed XML from the test xml file
        Type : [System.Xml]
        
    .ReturnValue
        none
        
    .Example
        SendEmail $myConfig
	#>

    $to = $xmlConfig.config.global.emailList.split(",")
    $from = $xmlConfig.config.global.emailSender
    $subject = $xmlConfig.config.global.emailSubject + " " + $testStartTime
    $smtpServer = $xmlConfig.config.global.smtpServer
    $fname = [System.IO.Path]::GetFilenameWithoutExtension($xmlConfigFile)
    # Highlight the failed tests 
    $body = $body.Replace("Aborted", '<em style="background:Yellow; color:Red">Aborted</em>')
    $body = $body.Replace("FAIL", '<em style="background:Yellow; color:Red">Failed</em>')
    
	Send-mailMessage -to $to -from $from -subject $subject -body $body -smtpserver $smtpServer -BodyAsHtml
}



####################################################
#Get the sio test mode, such as rand read, rand write and so on
####################################################
Function GetSIOMode($mode)
{
	$result = "-1 -1"
	switch ( $mode )
	{
		"seqw"
		{
			$result = "0 0"
		}
		"seqr"
		{
			$result = "100 0"
		}
		"ranr"
		{
			$result = "100 100"
		}
		"ranw"
		{
			$result = "0 100"
		}
		"seqranrw"
		{
			$result = "50 50"
		}
	}
	
	return $result

}


####################################################
#Install basic apps/tools
####################################################
Function InstallPackagesOnFreebsd( [string] $username,[string] $password,[string] $ip, $port )
{
	$command = "env ASSUME_ALWAYS_YES=yes pkg bootstrap -yf"
	$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command $command -runAsSudo -runMaxAllowedTime  300
	$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command "echo '#!/bin/csh' > updateports.csh" -runAsSudo
	$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command "echo 'echo y | pkg update -f' >> updateports.csh" -runAsSudo
	$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command "/bin/csh updateports.csh > updateports.log" -runAsSudo -runMaxAllowedTime  300
	
	$appsToBeInstalled=@("bash","unix2dos","fio","iperf")  
    foreach( $app in $appsToBeInstalled )
	{
		$command = "pkg install -y $app "
		$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command $command -runAsSudo -runMaxAllowedTime  600
		if(!$?) 
		{
			LogMsg "ERROR: Install $app failed!"
		}
	}
	
	$command = "ln -sf /usr/local/bin/bash  /bin/bash"
	$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command $command -runAsSudo
	
	$command = "uname -r"
	$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command $command -runAsSudo
	if( $out -like  "*10.*"   )
	{
		# Load the aio module for freebsd 10.x, otherwise the fio test will be failed.
		$kldstatus = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command "kldstat" -runAsSudo
		if( !( $kldstatus -like  "*aio.ko*" ) )
		{
			$command = "kldload aio;ls"  # Command with "ls" is a trick to make sure the return value is 0.
			$out = RunLinuxCmd -username $username -password $password -ip $ip -port $port -command $command -runAsSudo
		}
		
	}

}




####################################################
# Check the specified storage account whether exists.
# Create the account if it doesn't exist.
####################################################
Function CheckAndMakesureStorageAccountExists( [string] $resourceGroupNameToBeChecked,[string] $storageAccountNameToBeChecked,[string] $containerNameToBeChecked,[string] $location,[string] $storageType )
{
	$resourceGroupName = $resourceGroupNameToBeChecked
	$storageAccountName = $storageAccountNameToBeChecked
	$containerName = $containerNameToBeChecked
	
	$status = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorVariable notPresent -ErrorAction SilentlyContinue
	if (!$status)
	{
		# Resource group doesn't exist, so create the resource group, storage account and container.
		LogMsg "Create a resource group: $resourceGroupName"	
		New-AzureRmResourceGroup -Name $resourceGroupName -Location  $location
		
		LogMsg "Create a storage account: $storageAccountName"
		New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccountName -Location $location  -SkuName $storageType

		LogMsg "Create a container: $containerName"
		$srcStorageKey = (Get-AzureRmStorageAccountKey  -StorageAccountName $storageAccountName -ResourceGroupName $resourceGroupName).Value[0]
		$ctx = New-AzureStorageContext -StorageAccountName $storageAccountName  -StorageAccountKey  $srcStorageKey
		New-AzureStorageContainer -Name $containerName  -Context $ctx

	}
	else
	{
		# Resource group exist, then check the storage account
		$status = Get-AzureRmStorageAccount -ResourceGroupName  $resourceGroupName  -AccountName  $storageAccountName -ErrorVariable notPresent -ErrorAction SilentlyContinue
		if (!$status)
		{
			# Storage account doesn't exist, so create the storage account and container.
			LogMsg "Create a storage account: $storageAccountName"
			New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -AccountName $storageAccountName -Location $location  -SkuName $storageType

			LogMsg "Create a container: $containerName"
			$srcStorageKey = (Get-AzureRmStorageAccountKey  -StorageAccountName $storageAccountName -ResourceGroupName $resourceGroupName).Value[0]
			$ctx = New-AzureStorageContext -StorageAccountName $storageAccountName  -StorageAccountKey  $srcStorageKey
			New-AzureStorageContainer -Name $containerName  -Context $ctx
		}
		else
		{
			# Storage account exist, then check the container
			$srcStorageKey = (Get-AzureRmStorageAccountKey  -StorageAccountName $storageAccountName -ResourceGroupName $resourceGroupName).Value[0]
			$ctx = New-AzureStorageContext -StorageAccountName $storageAccountName  -StorageAccountKey  $srcStorageKey
			$content = Get-AzureStorageContainer -Context $ctx  
			if( $content -eq $null )
			{
				LogMsg "Create a container: $containerName"
				New-AzureStorageContainer -Name $containerName  -Context $ctx
			}				
		}	
	
	}		

}






####################################################
#SystemStart ()
# Operation : Starts the VHD provisioning Virtual Machine 
# Parameter : Name of the Virtual Machine
######################################################
function SystemStart ($VmObject)
{
    $vmname=$VmObject.vmName
    $hvServer=$VmObject.hvServer    
    LogMsg "VM $vmname is Starting"
    $startVMLog = Start-VM  -Name $vmname -ComputerName $hvServer 3>&1 2>&1
    $isVmStarted = $?
    if($isVmStarted)
    {
        if ($startVMLog -imatch "The virtual machine is already in the specified state.")
        {
            LogMsg "$startVMLog"
        }
        else
        {
            LogMsg "VM started Successfully"
            $VMState=GetVMState $vmname $hvServer
            LogMsg "Current Status : $VMState"
            WaitFor -seconds 10
        }
    }
    else
    {
        LogErr "$startVMLog"
        Throw "Failed to start VM."
    }
}

####################################################
#SystemStop ()
# Operation : Stops the VHD provisioning Virtual Machine
# Parameter : Name of the Virtual Machine
######################################################
function SystemStop ($VmObject)
{
    $vm = $VmObject
    $vmname=$vm.vmName
    $hvServer=$vm.hvServer
    $VMIP=$vm.ipv4
    $passwd=$vm.Password
    LogMsg "Shutting down the VM $vmname.."
    $VMState=GetVMState -VmObject $vm
    if(!($VMState -eq "Off"))
    {
        LogMsg "Issuing shutdown command.."
        $out = echo y|.\bin\plink -pw $passwd root@"$VMIP" "init 0" 3>&1 2>&1
        $isCommandSent = $?
        if(!$isCommandSent)
        {
            LogMsg "Failed to sent shutdown command .. Stopping forcibly."
            ForceShutDownVM -VmObject $vm
        }
        else
        {
            LogMsg "Shutdown command sent."
            WaitFor -seconds 15
            $counter = 1
            $retryAttemts = 10
            $VMState=GetVMState -VmObject $vm
            if($VMState -eq "Off")
            {
                $isSuccess=$true
            }
            while(($counter -le $retryAttemts) -and ($VMState -ne "Off"))
            {
                $isSuccess=$false
                Write-Host "Current Status : $VMState. Retrying $counter/$retryAttemts.."
                WaitFor -seconds 10
                $VMState=GetVMState -VmObject $vm
                if($VMState -eq "Off")
                {
                    $isSuccess=$true
                    break
                }
                $counter += 1
            }
            if ($isSuccess)
            {
                LogMsg "VM stopped successfully."
            }
            else 
            {
                Throw "VM failed to stop."
            }
        }
    }
    else
    {
    LogMsg "VM is already off."
    }
}

function ForceShutDownVM($VmObject)
{
    $vmname=$VmObject.vmName
    $hvServer=$VmObject.hvServer
    LogMsg "Force Shutdown VM : $vmname"
    $VMstopLog = stop-VM  -Name $vmname -ComputerName $hvServer -force 3>&1 2>&1
    $counter = 1
    $retryAttemts = 10
    $VMState=GetVMState -VmObject $vm
    while(($counter -le $retryAttemts) -and ($VMState -ne "Off"))
    {
        $isSuccess=$false
        Write-Host "Current Status : $VMState. Retrying $counter/$retryAttemts.."
        WaitFor -seconds 10
        $VMstopLog = stop-VM  -Name $vmname -ComputerName $hvServer -force 3>&1 2>&1
        $VMState=GetVMState -VmObject $vm
        if($VMState -eq "Off")
        {
            $isSuccess=$true
            break
        }
        $counter += 1
    }

    LogMsg "VM `'$vmname`' is $VMState"
}



#################################################
#GetVMState ()
#Function : Determinig the VM state
#Parameter : VM Name
#Return Value : state of the VM {"Running", "Stopped", "Paused", "Suspended", "Starting","Taking Snapshot", "Saving, "Stopping"}
########################################################

function GetVMState ($VmObject)
{
    $vmname=$vm.vmName
    $hvServer=$vm.hvServer
    $VMIP=$vm.ipv4
    $passwd=$vm.Password
    try
    {
    $VMstatus = Get-VM -Name $vmname -ComputerName $hvServer 3>&1 2>&1
    }
    Catch
    {
    LogErr "Exception Message : $VMstatus"
    Throw "Failed to Get the VM status."
    }
    return $VMstatus.state
}

###############################################################
#TestPort ()
# Function : Checking port 22 of the VM
# parameter : IP address
##############################################################

function TestPort ([string] $IP)
{
    
    $out = .\bin\vmmftest -server $IP -port 22 -timeout=3 3>&1 2>&1 
    if ($out -imatch "$IP is alive")
    {
        $isConnected=$true
    }
    else
    {
        $isConnected=$false
    }
    return $isConnected
}

Function csuploadSetConnetion ([string] $subscription)
{
    if ($subscription -eq $null -or $subscription.Length -eq 0)
    {
        "Error: Subscription is null"
        return $False
    }
    .\tools\CsUpload\csupload.exe Set-Connection $subscription

    if($?)
    {
	    LogMsg "Csupload connection set successfully.."
        return $true
    }
    else
    {
	    LogErr "Error in setting up Csupload connection.."
        return $False
    }

}

function UploadVHD ($xmlConfig)
{
    #CSUpload Parameters
    $SubscriptionID=$xmlConfig.config.Azure.CSUpload.Subscription
    $DestinationURL=$xmlConfig.config.Azure.CSUpload.DestinationURL
    $VHDpath=$xmlConfig.config.Azure.CSUpload.VHDpath
    $VHDname = $xmlConfig.config.Azure.CSUpload.VHDName

    #Set Connection of CSUpload to upload a VHD to cloud

    LogMsg "Connecting to Azure cloud to upload test VHD : $VHDName"
    #LogMsg ".\SetupScripts\csuploadSetConnection.ps1 $SubscriptionID"

    $isConnectinSet= csuploadSetConnetion $SubscriptionID
    if($isConnectinSet)
    {
        #Uploading the test VHD to cloud
        
        LogMsg "Uplaoding the test VHD $VHDName to Azure cloud..."
        $curtime = Get-Date
        $ImageName = "ICA-UPLOADED-" + $Distro + "-" + $curtime.Month + "-" +  $curtime.Day  + "-" + $curtime.Year + "-" + $curtime.Hour + "-" + $curtime.Minute + ".vhd"
        $ImageDestination =  $DestinationURL + "/" + $ImageName
        $ImageLabel = $ImageName
        $ImageLiteralPath =  $VHDpath + "\" + "$VHDName"

        LogMsg "Image Name using        : $ImageName"
        LogMsg "Image Label using       : $ImageLabel"
        LogMsg "Destination place using : $ImageDestination"
        LogMsg "Literal path using      : $ImageLiteralPath"

        $uploadLogs = .\tools\CsUpload\csupload.exe Add-DurableImage -Destination $ImageDestination -Name $ImageName -Label $ImageLabel -LiteralPath $ImageLiteralPath -OS Linux 3>&1 2>&1
        if($uploadLogs -imatch  "is registered successfully")
        {
            LogMsg "VHD uploaded successfully."
            LogMsg "Publishing the image name.."
            SetOSImageToDistro -Distro $Distro -xmlConfig $xmlConfig -ImageName "`"$ImageName`""
            return $true
        }
        else
        {
            LogErr "Failed to upload VHD. Please find the parameters used below."
            LogErr "Image Name used        : $ImageName"
            LogErr "Image Label used       : $ImageLabel"
            LogErr "Destination place used : $ImageDestination"
            LogErr "Literal path used      : $ImageLiteralPath"
            Throw "Failed to upload vhd."
        }
    }
    else
    {
        Throw "Failed to set connection fo csupload."
    }
}

function VHDProvision ($xmlConfig, $uploadflag)
{
	if (!$onCloud)
	{
	    #VM Parameters
	    $vm=$xmlConfig.config.VMs.vm
	    $testVM=$vm.vmName
	    $VMIP=$vm.ipv4
	    $passwd=$vm.Password
	    $VHDName=$xmlConfig.config.Azure.CSUpload.VHDName
	    $hvServer=$vm.hvServer
	    $Platform=$xmlConfig.config.global.platform

	    #LIS Tarball
	    $LISTarball=$xmlConfig.config.VMs.vm.LIS_TARBALL
	  
	    
	    #Start the VM..
	    SystemStart -VmObject $vm

	    #Checking avaialability of port 22

	    CheckSSHConnection -VMIpAddress $VMIP
	    Write-Host "Done"
	    #.\SetupScripts\VHDProvision.ps1 $testVM $VMIP $passwd $LISTarball
	    $isAllPackagesInstalled = InstallPackages -VMSshPort 22 -VMUserName "root" -VMPassword "redhat" -VMIpAddress $VMIP

	        # Collect VHD provision logs
	        #
	    if ($isAllPackagesInstalled)
	    {
	       
	        LogMsg "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	        LogMsg "TestVHD {$VHDName} is provisioned for automation"
	        LogMsg "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	        
	    }
	    else
	    {
	        LogMsg "Error:Failed to pull VHD Provision logfile"
	        return $false
	        
	    }
	    
	    # Stop the VM after VHD preparation
	   
	    SystemStop -VmObject $vm

	    if ($uploadflag)
	    {
	       UploadVHD $xmlConfig
	       if(!$?) 
	       {
	           return $false
	       }
	    }
	   

	}
	else
	{
	    #VHD preparation on clod part here--

	    #Deploy one VM on cloud..
	    $isDeployed = DeployVMs -xmlConfig $xmlConfig -setupType LargeVM -Distro $Distro
	    #$isDeployed =  "ICA-LargeVM-testdistro-7-16-1-41-23"
	    #$isDeployed = $true
	    if ($isDeployed)
	    {   
	           
	            $testServiceData = Get-AzureService -ServiceName $isDeployed

	            #Get VMs deployed in the service..
	            $testVMsinService = $testServiceData | Get-AzureVM

	            $hs1vm1 = $testVMsinService
	            $hs1vm1Endpoints = $hs1vm1 | Get-AzureEndpoint
	            $hs1vm1sshport = GetPort -Endpoints $hs1vm1Endpoints -usage ssh
	            $hs1VIP = $hs1vm1Endpoints[0].Vip
	            $hs1ServiceUrl = $hs1vm1.DNSName
	            $hs1ServiceUrl = $hs1ServiceUrl.Replace("http://","")
	            $hs1ServiceUrl = $hs1ServiceUrl.Replace("/","")
	            $hs1vm1Hostname =  $hs1vm1.Name
	   
	            

	        $isAllPackagesInstalled = InstallPackages -VMIpAddress $hs1VIP -VMSshPort $hs1vm1sshport -VMUserName $user -VMPassword $password
	                                  

	        $capturedImage = CaptureVMImage -ServiceName $isDeployed
	        #$capturedImage = "ICA-CAPTURED-testDistro-7-5-2013-4-37.vhd"
	        LogMsg "Publishing the image name.."
	        SetOSImageToDistro -Distro $Distro -xmlConfig $xmlConfig -ImageName "`"$capturedImage`""
	            

	        Write-Host $xmlConfig
	    }
	    else
	    {
	        $retValue = $false
	        Throw "Deployment Failed."
	    }

	    #InstallPackages run on cloud.

	    #deprovision VM..

	    #Capture Image with generated Name..
	  
	}
}

function Usage()
{
    write-host
    write-host "  Start automation: AzureAutomationManager.ps1 -xmlConfigFile <xmlConfigFile> -runTests -email -Distro <DistroName> -cycleName <TestCycle>"
    write-host
    write-host "         xmlConfigFile : Specifies the configuration for the test environment."
    write-host "         DistroName    : Run tests on the distribution OS image defined in Azure->Deployment->Data->Distro"
    write-host "         -help         : Displays this help message."
    write-host
}

Function CSUploadSetSubscription([string] $subscription)
{
	if ($subscription -eq $null -or $subscription.Length -eq 0)
	{
	    "Error: Subscription is null"
	    return $False
	}
	.\tools\CsUpload\csupload Set-Connection $subscription

	if($?)
	{
		"Csupload connection set successfully.."
	}
	else
	{
		"Error in setting up Csupload connection.."
		Break;
	}
}

Function ImportAzureSDK()
{
	$module = get-module | select-string -pattern azure -quiet
	if (! $module)
	{
		import-module .\tools\AzureSDK\Azure.psd1
	}
}

Function GetCurrentCycleData($xmlConfig, $cycleName)
{
    foreach ($Cycle in $xmlConfig.config.testCycles.Cycle )
    {
        if($cycle.cycleName -eq $cycleName)
        {
        return $cycle
        break
        }
    }
    
}

Function CheckSSHConnection($VMIpAddress)
{
    $retryCount = 1
    $maxRetryCount = 100
    $isConnected= TestPort -IP $VMIpAddress
    if($isConnected)
    {
        $isSuccess = $true
    }
    while (($retryCount -le $maxRetryCount) -and (!$isConnected))
    {
        $isSuccess = $False
        LogMsg "Connecting to ssh network of VM $VMIpAddress. Retry $retryCount/$maxRetryCount.."
        $isConnected= TestPort -IP $VMIpAddress
        if($isConnected)
        {
            $isSuccess = $true
            break
        }
        $retryCount += 1
        WaitFor -seconds 5
    }
    if($isSuccess)
    {
        LogMsg "Connected to $VMIpAddress."
    }
    else
    {
        Throw "Connection failed to $VMIpAddress."
    }
    
}

Function RunAzureCmd ($AzureCmdlet, $maxWaitTimeSeconds = 600, [string]$storageaccount = "")
{
    $timeExceeded = $false
    LogMsg "$AzureCmdlet"
    $jobStartTime = Get-Date 
    $CertThumbprint = $xmlConfig.config.Azure.General.CertificateThumbprint
    $myCert = Get-Item cert:\CurrentUser\My\$CertThumbprint
    if(!$storageaccount)
    {
      $storageaccount = $xmlConfig.config.Azure.General.StorageAccount
    }
    if (IsEnvironmentSupported)
    {
		$environment = $xmlConfig.config.Azure.General.Environment
        $AzureJob = Start-Job -ScriptBlock { $PublicConfiguration = $args[6];$PrivateConfiguration = $args[7];$suppressedOut = Set-AzureSubscription -SubscriptionName $args[1] -Certificate $args[2] -SubscriptionID $args[3] -ServiceEndpoint $args[4] -CurrentStorageAccountName $args[5] -Environment $args[8];$suppressedOut = Select-AzureSubscription -Current $args[1];Invoke-Expression $args[0];} -ArgumentList $AzureCmdlet, $xmlConfig.config.Azure.General.SubscriptionName, $myCert, $xmlConfig.config.Azure.General.SubscriptionID, $xmlConfig.config.Azure.General.ManagementEndpoint, $storageaccount, $PublicConfiguration, $PrivateConfiguration, $environment
    }
    else
    {
        $AzureJob = Start-Job -ScriptBlock { $PublicConfiguration = $args[6];$PrivateConfiguration = $args[7];$suppressedOut = Set-AzureSubscription -SubscriptionName $args[1] -Certificate $args[2] -SubscriptionID $args[3] -ServiceEndpoint $args[4] -CurrentStorageAccountName $args[5];$suppressedOut = Select-AzureSubscription -Current $args[1];Invoke-Expression $args[0];} -ArgumentList $AzureCmdlet, $xmlConfig.config.Azure.General.SubscriptionName, $myCert, $xmlConfig.config.Azure.General.SubscriptionID, $xmlConfig.config.Azure.General.ManagementEndpoint, $storageaccount, $PublicConfiguration, $PrivateConfiguration
    }
    $currentTime = Get-Date
    while (($AzureJob.State -eq "Running") -and !$timeExceeded)
        {
        $currentTime = Get-Date        
        $timeLapsed = (($currentTime - $jobStartTime).TotalSeconds) 
        Write-Progress -Activity $AzureCmdlet -Status $AzureJob.State -PercentComplete (($timeLapsed / $maxWaitTimeSeconds)*100) -Id 142536 -SecondsRemaining ( $maxWaitTimeSeconds - $timeLapsed )
        Write-Host "." -NoNewline
        sleep -Seconds 1
        if ($timeLapsed -gt $maxWaitTimeSeconds)
            {
                $timeExceeded = $true
            }
        }
    Write-Progress -Id 142536 -Activity $AzureCmdlet -Completed
    LogMsg "Time Lapsed : $timeLapsed Seconds."
    $AzureJobOutput = Receive-Job $AzureJob
    $operationCounter = 0
    $operationSuccessCounter = 0
    $operationFailureCounter = 0
    if ($AzureJobOutput -eq $null)
    {
        $operationCounter += 1
    }
    else
    {
        foreach ($operation in $AzureJobOutput)
        {
            $operationCounter += 1 
            if ($operation.OperationStatus -eq "Succeeded")
            {
                $operationSuccessCounter += 1
            }
            else
            {
                $operationFailureCounter += 1
            }
        }
    }
    if($operationCounter -eq $operationSuccessCounter)
    {
        return $AzureJobOutput
    }
    else
    {
        if($timeExceeded)
        {
            LogErr "Azure Cmdlet : Timeout"
        } 
        Throw "Failed to execute Azure command."
    }
}

<#-------------Create Deployment Start------------------#>
Import-Module .\TestLibs\RDFELibs.psm1 -Force
Set-Alias -Name java -Value (Join-Path $env:JAVA_HOME 'bin\java.exe')

Function GetBillableSize ($key, $name, $url)
{
    java -jar $toolpath net.local.test.AccessStorage -k $key -n $name -c false -u $url
    $line = Get-Content .\azure-storage-usage.log | select -Last 1
    $value = $line.Split('')[-3] + " " + $line.Split('')[-2]
    Return "$value"
}

$result = ""
$testResult = ""
$resultArr = @()

$isDeployed = DeployVMS -setupType $currentTestData.setupType -Distro $Distro -xmlConfig $xmlConfig

if($isDeployed)
{
      try
      {
        $hs1VIP = $AllVMData.PublicIP
        $hs1ServiceUrl = $AllVMData.URL
        $hs1vm1IP = $AllVMData.InternalIP
        $hs1vm1Hostname = $AllVMData.RoleName
        $hs1vm1sshport = $AllVMData.SSHPort
        $hs1vm1tcpport = $AllVMData.TCPtestPort
        $hs1vm1udpport = $AllVMData.UDPtestPort
        $resourcegroupname = $AllVMData.ResourceGroupName
        $disksize = $currentTestData.DataDiskSize
        $DistroName = DetectLinuxDistro -VIP $hs1VIP -SSHport $hs1vm1sshport -testVMUser $user -testVMPassword $password
        $diskName = "freebsdtrimtest" + (get-random)
        $toolpath = Join-Path $env:Azure_Storage_Test_Tool 'azure-storage-usage-1.0-SNAPSHOT.jar'

        if($UseAzureResourceManager)
        {
            $name = $xmlConfig.config.Azure.General.ARMStorageAccount
        }
        else
        {
            $name = $xmlConfig.config.Azure.General.StorageAccount 
        }
        $key = GetStorageAccountKey $xmlConfig

        RemoteCopy -uploadTo $hs1VIP -port $hs1vm1sshport -files $currentTestData.files -username $user -password $password -upload
        RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "chmod +x *" -runAsSudo
        
        LogMsg "*************Attach data disk begin*************"
        $osDiskUrl=""
        $dataDiskUrl=""

        if($UseAzureResourceManager)
        {
            $VirtualMachine = Get-AzureRmVM -ResourceGroupName $resourcegroupname  
            $index = $VirtualMachine.StorageProfile.OsDisk.Vhd.Uri.ToString().LastIndexOf('/')
            $diskurl = $VirtualMachine.StorageProfile.OsDisk.vhd.Uri.ToString().substring(0, $index)
            Add-AzureRmVMDataDisk -VM $VirtualMachine -Name $diskName -VhdUri "$diskurl/$diskName.vhd" -LUN 0 -Caching None -DiskSizeinGB $disksize -CreateOption Empty
            
            $AttachDataDisk = Update-AzureRmVM -ResourceGroupName $resourcegroupname -VM $VirtualMachine
        
            if ($AttachDataDisk.IsSuccessStatusCode -eq "True"  -or  $restartVM.StatusCode -eq "OK" )
	        {
              LogMsg "Attach data $diskName.vhd successfully"
              LogMsg "Disk size is $disksize"
            }
        }
        else
        {
            $testServiceData = Get-AzureService -ServiceName $isDeployed
            $testVMsinService = $testServiceData | Get-AzureVM
            
            $index = $testVMsinService.VM.OSVirtualHardDisk.MediaLink.ToString().LastIndexOf('/')
            $diskurl = $testVMsinService.VM.OSVirtualHardDisk.MediaLink.ToString().substring(0, $index)
            $AttachDataDisk = Get-AzureVM  -ServiceName $testServiceData.ServiceName | Add-AzureDataDisk -CreateNew -MediaLocation "$diskurl/$diskName.vhd" -DiskLabel "data0" -LUN 0 -HostCaching None -DiskSizeInGB $disksize | Update-AzureVM
            $dataDiskUrl= "$diskurl/$diskName.vhd"
            $osDiskUrl=$testVMsinService.VM.OSVirtualHardDisk.MediaLink.ToString()
            if($AttachDataDisk.OperationStatus -eq "Succeeded")
            {
              LogMsg "Attach data $diskName.vhd successfully"
              LogMsg "Disk size is $disksize"
            }
        }
        LogMsg "*************Attach data disk end*************"

        LogMsg "*************Initialize data disk begin*************"
        LogMsg "Executing : $($currentTestData.testScript)"
        RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "$python_cmd $($currentTestData.testScript) -f $($currentTestData.FileSystem)" -runAsSudo 
        RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "mv Runtime.log $($currentTestData.testScript).log" -runAsSudo
        LogMsg "*************Initialize data disk end*************"
        
        LogMsg "*************Sleep 2 mins begin*************" 
        sleep 120
        LogMsg "*************Sleep 2 mins end*************"

        LogMsg "*************Before create file, get billable size*************"
        $beforesize =  GetBillableSize $key $name "$diskurl/$diskName.vhd"
        LogMsg "Before create file, the size is: $($beforesize[-1])"

        # after initialize the disk
        if($currentTestData.FileSystem -eq "UFS")
        {
          $location = "/mnt/datadisk"
        }
        else 
        {
          $location = "/Test"  
        }

        LogMsg "*************Create file begin*************"
        RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "dd if=/dev/random of=$location/test_trim  bs=10M count=$($currentTestData.Count)" -runAsSudo -runMaxAllowedTime 3600
        LogMsg "*************Create file end*************"

        LogMsg "*************Sleep 5 mins begin*************" 
        sleep 300
        LogMsg "*************Sleep 5 mins end*************"

        LogMsg "*************After create file, get billable size*************"
        $aftercreatefilesize = GetBillableSize $key $name "$diskurl/$diskName.vhd"
        LogMsg "After create file, the size is: $($aftercreatefilesize[-1])"
        
        LogMsg "*************Delete file begin*************"   
        RunLinuxCmd -username $user -password $password -ip $hs1VIP -port $hs1vm1sshport -command "rm -rf $location/test_trim" -runAsSudo 
        LogMsg "*************Delete file end*************" 

        LogMsg "*************Sleep 5 mins begin*************" 
        sleep 300
        LogMsg "*************Sleep 5 mins end*************"

        LogMsg "*************After delete file, get billable size*************"
        $afterdeletefilesize = GetBillableSize $key $name "$diskurl/$diskName.vhd"
        LogMsg "After delete file, the size is: $($afterdeletefilesize[-1])"

        #RemoteCopy -download -downloadFrom $hs1VIP -files "/home/$user/state.txt, /home/$user/Summary.log, /home/$user/$($currentTestData.testScript).log" -downloadTo $LogDir\$hs1vm1Hostname -port $hs1vm1sshport -username $user -password $password
        
        $testResult = "Pass"
        #Get-Content $LogDir\$hs1vm1Hostname\Summary.log
        $testStatus = "TestCompleted"
        #Get-Content $LogDir\$hs1vm1Hostname\state.txt
        #log azure-storage-usage.txt
        LogMsg "Test result : $testResult"
      }
      catch
      {
        $ErrorMessage =  $_.Exception.Message
        LogMsg "EXCEPTION : $ErrorMessage"  
      }
      Finally
      {
        if (!$testResult)
        {
          $testResult = "Aborted"
        }
        $resultArr += $testResult
      }
  }
  else
  {
      $testResult = "Aborted"
      $resultArr += $testResult
  }

  $result = GetFinalResultHeader -resultarr $resultArr
  if(!$UseAzureResourceManager)
  {
     Remove-AzureVM -Name $hs1vm1Hostname -DeleteVHD -ServiceName $testServiceData.ServiceName 
     Remove-AzureService -ServiceName $testServiceData.ServiceName -Force
  }

  if($UseAzureResourceManager)
  {
        
      DoTestCleanUp -result $result -testName $currentTestData.testName -deployedServices $isDeployed -ResourceGroups $isDeployed

      LogMsg "Delete os disk $osDiskUrl"
      $osDiskContainerName = $osDiskUrl.Split('/')[-2]
      $osDiskStorageAcct = Get-AzureRmStorageAccount | where { $_.StorageAccountName -eq $osDiskUrl.Split('/')[2].Split('.')[0] }
      $osDiskStorageAcct | Remove-AzureStorageBlob -Container $osDiskContainerName -Blob $osDiskUrl.Split('/')[-1] -ea Ignore -Force

      LogMsg "Delete data disk $dataDiskUrl"
      $dataDiskContainerName = $dataDiskUrl.Split('/')[-2]
      $dataDiskStorageAcct = Get-AzureRmStorageAccount | where { $_.StorageAccountName -eq $dataDiskUrl.Split('/')[2].Split('.')[0] }
      $dataDiskStorageAcct | Remove-AzureStorageBlob -Container $dataDiskContainerName -Blob $dataDiskUrl.Split('/')[-1] -ea Ignore -Force
  }

return $result


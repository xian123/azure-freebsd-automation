﻿##############################################################################################
# RunAzureTests.ps1
# Description : This script manages all the setup and test operations in Azure environment.
#               It is an entry script of Azure Automation.
#               It's a package of AzureAutomationManager.ps1.

# Usage

# Example 1:
#        .\RunAzureTests.ps1 -ARMImageName 'MicrosoftOSTC FreeBSD 11.1 11.1.20180112' -testLocation 'eastus2' -DistroIdentifier 'freebsdkqtest'    + 
#          -testCycle 'PERF-KQ' -StorageAccount 'ExistingStorage_Standard'  -ResultDBTable 'Perf_FreeBSD_Azure_KQ' -customSecretsFilePath "C:\Users\Public\secretsFile.xml"

# Example 2:
#        .\RunAzureTests.ps1 -ARMImageName 'MicrosoftOSTC FreeBSD 11.1 11.1.20180112' -testLocation 'eastus2' -DistroIdentifier 'freebsdfiotest'   + 
#         -testCycle 'PERF-SIO-SingleDisk' -StorageAccount 'ExistingStorage_Premium'  -ResultDBTable 'Perf_FreeBSD_Azure_sio' -customSecretsFilePath "C:\Users\Public\secretsFile.xml"
###############################################################################################


Param( $BuildNumber=$env:BUILD_NUMBER,

[Parameter(Mandatory=$true)]
[string] $testLocation,

[Parameter(Mandatory=$true)]
[string] $DistroIdentifier,

[Parameter(Mandatory=$true)]
[string] $testCycle,

[string] $ARMImageName,
[string] $OsVHD,

[string] $OverrideVMSize,

[switch] $EnableAcceleratedNetworking,
[string] $customKernel,
[string] $customLIS,
[string] $customBISBranch,
[switch] $ForceDeleteResources,
[switch] $keepReproInact,
[string] $customSecretsFilePath = "",
[string] $ArchiveLogDirectory = "",
[string] $ResultDBTable = "",
[string] $ResultDBTestTag = "",
[string] $RunSelectedTests="",
[string] $StorageAccount="",
[string] $customParameters="",
[int] $coureCountExceededTimeout,
[int] $testIterations = 1,
[int] $maxDirLength = 32,

[string] $LinuxUsername="",
[string] $LinuxPassword="",

[string] $tipSessionId="",
[string] $tipCluster="",
[switch] $UseManagedDisks,
[string] $destBlobName = "Default",

[switch] $ExitWithZero
)

#---------------------------------------------------------[Initializations]--------------------------------------------------------

Write-Host "-----------$PWD---------"
$maxDirLength = 100
$shortRandomNumber = Get-Random -Maximum 99999 -Minimum 11111
Set-Variable -Name shortRandomNumber -Value $shortRandomNumber -Scope Global
$shortRandomWord = -join ((65..90) | Get-Random -Count 4 | % {[char]$_})
Set-Variable -Name shortRandomWord -Value $shortRandomWord -Scope Global
if ( $pwd.Path.Length -gt $maxDirLength)
{
    $originalWorkingDirectory = $pwd
    Write-Host "Current working directory length is greather than $maxDirLength. Need to change the working directory."
    $tempWorkspace = $env:TEMP
    New-Item -ItemType Directory -Path "$tempWorkspace\az" -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path "$tempWorkspace\az\$shortRandomNumber" -Force -ErrorAction SilentlyContinue | Out-Null
    $finalWorkingDirectory = "$tempWorkspace\az\$shortRandomNumber"
    $tmpSource = '\\?\' + "$originalWorkingDirectory\*"
    Write-Host "Copying current workspace to $finalWorkingDirectory"
    Copy-Item -Path $tmpSource -Destination $finalWorkingDirectory -Recurse -Force -ErrorAction SilentlyContinue| Out-Null
    Set-Location -Path $finalWorkingDirectory | Out-Null
    Write-Host "Wroking directory changed to $finalWorkingDirectory"
}
Remove-Item -Path ".\report\report_$(($TestCycle).Trim()).xml" -Force -ErrorAction SilentlyContinue
Remove-Item -Path ".\report\testSummary.html" -Force -ErrorAction SilentlyContinue
mkdir -Path .\report -Force -ErrorAction SilentlyContinue | Out-Null
Set-Content -Value "No tests ran yet." -Path ".\report\testSummary.html" -Force -ErrorAction SilentlyContinue

# .\Extras\CheckForNewKernelPackages.ps1

New-Item -Name temp -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

if ( $customSecretsFilePath ) {
    $secretsFile = $customSecretsFilePath
    Write-Host "Using user provided secrets file: $($secretsFile | Split-Path -Leaf)"
    Set-Variable -Name "secretsFile" -Value $customSecretsFilePath -Scope Global
}
if ($env:Azure_Secrets_File) {
    $secretsFile = $env:Azure_Secrets_File
    Write-Host "Using predefined secrets file: $($secretsFile | Split-Path -Leaf) in Jenkins Global Environments."
}
if ( $secretsFile -eq $null ) {
    Write-Host "ERROR: Azure Secrets file not found in Jenkins / user not provided -customSecretsFilePath" -ForegroundColor Red -BackgroundColor Black
    exit 1
}


if ( Test-Path $secretsFile) {
    Write-Host "AzureSecrets.xml found."
    .\AddAzureRmAccountFromSecretsFile.ps1 -customSecretsFilePath $secretsFile
    $xmlSecrets = [xml](Get-Content $secretsFile)
    Set-Variable -Name xmlSecrets -Value $xmlSecrets -Scope Global
    Set-Variable -Name AuthenticatedSession -Value $true -Scope Global
}
else {
    Write-Host "AzureSecrets.xml file is not added in Jenkins Global Environments OR it is not bound to 'Azure_Secrets_File' variable." -ForegroundColor Red -BackgroundColor Black
    Write-Host "Aborting." -ForegroundColor Red -BackgroundColor Black
    exit 1
}

if ( $ARMImageName -eq $null -and $OsVHD -eq $null)
{
    Write-Host "MISSING PARAMETER: ARMImage and OsVHD parameters are missing. Please give atleast one."
}

#region Set Jenkins specific variables.
if ($env:BUILD_NUMBER -gt 0)
{
    Write-Host "Detected Jenkins environment."
    $xmlConfigFileFinal = "$PWD\Azure_Config-$shortRandomNumber.xml"
    $xmlConfigFileFinal = $xmlConfigFileFinal.Replace('/','-')
}
else
{
    Write-Host "Detected local environment."
    $xmlConfigFileFinal = "$PWD\Azure_Config-$testCycle-$DistroIdentifier.xml"
}

#region Select Storage Account Type
$regionName = $testLocation.Replace(" ","").Replace('"',"").ToLower()
$regionStorageMapping = [xml](Get-Content .\XML\RegionAndStorageAccounts.xml)
if ( $StorageAccount -imatch "ExistingStorage_Standard" )
{
    $StorageAccountName = $regionStorageMapping.AllRegions.$regionName.StandardStorage
}
elseif ( $StorageAccount -imatch "ExistingStorage_Premium" )
{
    $StorageAccountName = $regionStorageMapping.AllRegions.$regionName.PremiumStorage
}
elseif ( $StorageAccount -imatch "NewStorage_Standard" )
{
    $StorageAccountName = "NewStorage_Standard_LRS"
}
elseif ( $StorageAccount -imatch "NewStorage_Premium" )
{
    $StorageAccountName = "NewStorage_Premium_LRS"
}
elseif ($StorageAccount -eq "")
{
    $StorageAccountName = $regionStorageMapping.AllRegions.$regionName.StandardStorage
    Write-Host "Auto selecting storage account : $StorageAccountName as per your test region."
}
#if ($defaultDestinationStorageAccount -ne $StorageAccountName)
#{
#   $OsVHD = "https://$defaultDestinationStorageAccount.blob.core.windows.net/vhds/$OsVHD"
#}
#endregion

#Write-Host "Getting '$StorageAccountName' storage account details..."
#$testLocation = (Get-AzureRmLocation | Where { $_.Location -eq $((Get-AzureRmResource | Where { $_.Name -eq "$StorageAccountName"}).Location)}).DisplayName

#region Prepare workspace for automation.
Set-Content -Value "<pre>" -Path .\FinalReport.txt -Force
Add-Content -Value "Build process aborted manually. Please check attached logs for more details..." -Path .\FinalReport.txt -Force
Add-Content -Value "</pre>" -Path .\FinalReport.txt -Force
mkdir .\report -Force -ErrorAction SilentlyContinue | Out-Null
Set-Content -Value "" -Path .\report\testSummary.html -Force
Set-Content -Value "" -Path .\report\lastLogDirectory.txt -Force

#Copy-Item J:\Jenkins\userContent\azure-linux-automation\* -Destination . -Recurse -Force -ErrorAction SilentlyContinue
#Copy-Item J:\Jenkins\userContent\CI\* -Destination . -Recurse -Force -ErrorAction SilentlyContinue
#endregion


#region PREPARE XML FILE
Write-Host "Injecting Azure Configuration data in $xmlConfigFileFinal file.."
#region Add custom parameters to XML

if ( $customParameters )
{
    $customParameters = $customParameters.Replace("^","`n")
    $xmlFileString = Get-Content .\Azure_ICA_all.xml
    foreach ($replaceString in $customParameters.Split("`n"))
    {
        $actualContent = $replaceString.Split("=")[0]
        $replacement = $replaceString.Split("=")[1]
        $xmlFileString = $xmlFileString.Replace($actualContent,$replacement)
        Write-Host "Replaced $actualContent --> $replacement in XML file."
    }
    [xml]$xmlFileData = [xml]($xmlFileString)
}
else
{
    [xml]$xmlFileData = [xml](Get-Content .\Azure_ICA_all.xml)
}
#endregion
$xmlFileData.config.Azure.General.SubscriptionID = $xmlSecrets.secrets.SubscriptionID.Trim()
$xmlFileData.config.Azure.General.SubscriptionName = $xmlSecrets.secrets.SubscriptionName.Trim()
$xmlFileData.config.Azure.General.StorageAccount= $StorageAccountName
$xmlFileData.config.Azure.General.ARMStorageAccount = $StorageAccountName
if ($LinuxUsername)
{
    $xmlFileData.config.Azure.Deployment.Data.UserName = $LinuxUsername.Trim()
}
else 
{
    $xmlFileData.config.Azure.Deployment.Data.UserName = $xmlSecrets.secrets.linuxTestUsername.Trim()
}
if ($LinuxPassword)
{
    $xmlFileData.config.Azure.Deployment.Data.Password = '"' + ($LinuxPassword.Trim()) + '"'
}
else 
{
    $xmlFileData.config.Azure.Deployment.Data.Password = '"' + ($xmlSecrets.secrets.linuxTestPassword.Trim()) + '"'
}
$xmlFileData.config.Azure.Deployment.Data.Distro[0].Name = ($DistroIdentifier).Trim()
$xmlFileData.config.Azure.General.AffinityGroup=""
$newNode = $xmlFileData.CreateElement("Location")
$xmlFileData.config.Azure.General.AppendChild($newNode) | Out-Null
$xmlFileData.config.Azure.General.Location='"' + "$testLocation" + '"'
if ( $OsVHD )
{
    Write-Host "Injecting Os VHD Information in $xmlConfigFileFinal ..."
    $xmlFileData.config.Azure.Deployment.Data.Distro[0].OsVHD = ($OsVHD).Trim()
}
else
{
    Write-Host "Injecting ARM Image Information in $xmlConfigFileFinal ..."
    $armPub = [string](($ARMImageName).Split(" ")[0])
    $armOffer = [string](($ARMImageName).Split(" ")[1])
    $armSKU = [string](($ARMImageName).Split(" ")[2])
    $armVersion = [string](($ARMImageName).Split(" ")[3])
    $xmlFileData.config.Azure.Deployment.Data.Distro[0].ARMImage.Publisher = $armPub
    $xmlFileData.config.Azure.Deployment.Data.Distro[0].ARMImage.Offer = $armOffer
    $xmlFileData.config.Azure.Deployment.Data.Distro[0].ARMImage.Sku = $armSKU
    $xmlFileData.config.Azure.Deployment.Data.Distro[0].ARMImage.Version = $armVersion
}
#endregion

#region Inject DB data to XML

    $xmlFileData.config.Azure.database.server = ($xmlSecrets.secrets.DatabaseServer).Trim()
    $xmlFileData.config.Azure.database.user = ($xmlSecrets.secrets.DatabaseUser).Trim()
    $xmlFileData.config.Azure.database.password = ($xmlSecrets.secrets.DatabasePassword).Trim()
    $xmlFileData.config.Azure.database.dbname= ($xmlSecrets.secrets.DatabaseName).Trim()


if( $ResultDBTable )
{
    $xmlFileData.config.Azure.database.dbtable = ($ResultDBTable).Trim()
}

if( $ResultDBTestTag )
{
    $xmlFileData.config.Azure.database.testTag = ($ResultDBTestTag).Trim()
}
else
{
    #Write-Host "No Test Tag provided. If test needs DB support please fill testTag."
}

if( $customBISBranch )
{
    $xmlFileData.config.global.VMEnv.LISBuildBranch = ($customBISBranch).Trim()
}

if( $testCycle -eq "BUILD-KERNEL" )
{
	if ( $destBlobName -eq "Default" ) {
		Write-Host "ERROR: destBlobName is not given." -ForegroundColor Red -BackgroundColor Black
		exit 1
	}

	$target = $xmlFileData.config.testsDefinition.test  | Where {$_.testName -eq "ICA-BUILD-FREEBSD-KERNEL"}
	if( $target )
	{
		$target.destBlobName = ($destBlobName).Trim()
	}
}



$xmlFileData.Save("$xmlConfigFileFinal")
Write-Host "$xmlConfigFileFinal prepared successfully."


if ( $OsVHD )
{
	try
	{
		$dstStorageAccountName  = $StorageAccountName
		$dstStorageAccountInfo = Get-AzureRmStorageAccount -ErrorAction Stop | where-object {$_.StorageAccountName -eq $dstStorageAccountName}
		if($dstStorageAccountInfo)
		{
			# Check the blob whether exists 
			$dstStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $dstStorageAccountInfo.ResourceGroupName -name $dstStorageAccountInfo.StorageAccountName)[0].value
			$destContext = New-AzureStorageContext -StorageAccountName $dstStorageAccountInfo.StorageAccountName -StorageAccountKey $dstStorageKey
			$destContainerName = "vhds"
			$blobName = ($OsVHD).Trim()
			
			$blob = Get-AzureStorageBlob -Blob $blobName -Container $destContainerName -Context $destContext -ErrorAction Ignore
			if (-not $blob)
			{
				Write-Host "$blobName Not Found, so copy it."
				# This storage account name is fixed and the storage places all the xxx.vhd which is from building kernel
				$srcStorageAccountName = "xhxprparevhdstoragev2"  
				$srcContainerName = "vhds"

				$srcStorageAccountInfo = Get-AzureRmStorageAccount -ErrorAction Stop | where-object {$_.StorageAccountName -eq $srcStorageAccountName}
				if(-not $srcStorageAccountInfo )
				{
					Write-Host "ERROR: the storage $srcStorageAccountName doesn't exist." -ForegroundColor Red -BackgroundColor Black
					exit 1
				}
				
				$srcUri =   "https://" + $srcStorageAccountName + ".blob.core.windows.net/" + $srcContainerName + "/" + $blobName
				$srcStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $srcStorageAccountInfo.ResourceGroupName -name $srcStorageAccountInfo.StorageAccountName)[0].value
				$srcContext = New-AzureStorageContext -StorageAccountName $srcStorageAccountInfo.StorageAccountName -StorageAccountKey $srcStorageKey
				
				Write-Host "Begin to copy $blobName from  $srcStorageAccountName to $dstStorageAccountName ..."
				$blob = Start-AzureStorageBlobCopy -SrcUri $srcUri -SrcContext $srcContext -DestContainer $destContainerName -DestBlob $blobName -DestContext $destContext

				Write-Host "Checking Copy Status"
				$status = $blob | Get-AzureStorageBlobCopyState
				while($status.Status -eq "Pending"){
					$status = $blob | Get-AzureStorageBlobCopyState
					Start-Sleep 20
					$BytesCopied = $status.BytesCopied
					$TotalBytes = $status.TotalBytes
					Write-Host "BytesCopied/TotalBytes: $BytesCopied/$TotalBytes"
				}
				
				$status = $blob | Get-AzureStorageBlobCopyState
				if( $status.Status -eq "Success"  )
				{
					Write-Host "Copy $blobName from  $srcStorageAccountName to $dstStorageAccountName successfully."
				}
				else
				{
					Write-Host "ERROR: Copy $blobName from  $srcStorageAccountName to $dstStorageAccountName failed." -ForegroundColor Red -BackgroundColor Black
					exit 1
				}
				
			}
			else
			{
				Write-Host "$blobName Found in $dstStorageAccountName"
			}
		
		}
		else
		{
			Write-Host "ERROR: The storage account $StorageAccountName doesn't exist" -ForegroundColor Red -BackgroundColor Black
			# TODO: create a storage account
			exit 1
		}
	}
	catch 
	{
		$ErrorMessage =  $_.Exception.Message
		Write-Host "EXCEPTION : $ErrorMessage" -ForegroundColor Red -BackgroundColor Black
		exit 1
	}
	
}




$currentDir = $PWD
Write-Host "CURRENT WORKING DIRECTORY - $currentDir"

#region Generate trigger command
Remove-Item -Path ".\report\report_$(($TestCycle).Trim()).xml" -Force -ErrorAction SilentlyContinue

mkdir -Path .\tools -ErrorAction SilentlyContinue | Out-Null

Import-Module BitsTransfer

if (!( Test-Path -Path .\tools\7za.exe ))
{
    Write-Host "Downloading 7za.exe"
    $out = Start-BitsTransfer -Source "https://github.com/iamshital/azure-linux-automation-support-files/raw/master/tools/7za.exe" | Out-Null
}
if (!( Test-Path -Path .\tools\dos2unix.exe ))
{
    Write-Host "Downloading dos2unix.exe"
    $out = Start-BitsTransfer -Source "https://github.com/iamshital/azure-linux-automation-support-files/raw/master/tools/dos2unix.exe" | Out-Null
}
if (!( Test-Path -Path .\tools\plink.exe ))
{
    Write-Host "Downloading plink.exe"
    $out = Start-BitsTransfer -Source "https://github.com/iamshital/azure-linux-automation-support-files/raw/master/tools/plink.exe" | Out-Null
}
if (!( Test-Path -Path .\tools\pscp.exe ))
{
    Write-Host "Downloading pscp.exe"
    $out = Start-BitsTransfer -Source "https://github.com/iamshital/azure-linux-automation-support-files/raw/master/tools/pscp.exe"  | Out-Null
}
Move-Item -Path "*.exe" -Destination .\tools -ErrorAction SilentlyContinue -Force


$cmd = ".\AzureAutomationManager.ps1 -runtests -Distro " + ($DistroIdentifier).Trim() + " -cycleName "+ ($TestCycle).Trim()
$cmd += " -xmlConfigFile $xmlConfigFileFinal"

if ( $OverrideVMSize )
{
    $cmd += " -OverrideVMSize $OverrideVMSize"
}
if ( $EconomyMode -eq "True")
{
    $cmd += " -EconomyMode -keepReproInact"
}
if ( $EnableAcceleratedNetworking )
{
    $cmd += " -EnableAcceleratedNetworking"
}
if ( $ForceDeleteResources )
{
    $cmd += " -ForceDeleteResources"
}
if ( $keepReproInact )
{
    $cmd += " -keepReproInact"
}
if ( $customKernel)
{
    $cmd += " -customKernel '$customKernel'"
}
if ( $customLIS)
{
    $cmd += " -customLIS $customLIS"
}
if ( $RunSelectedTests )
{
    $cmd += " -RunSelectedTests '$RunSelectedTests'"
}
if ( $coureCountExceededTimeout )
{
    $cmd += " -coureCountExceededTimeout $coureCountExceededTimeout"
}
if ( $testIterations -gt 1 )
{
    $cmd += " -testIterations $testIterations"
}
if ( $tipSessionId)
{
    $cmd += " -tipSessionId $tipSessionId"
}
if ( $tipCluster)
{
    $cmd += " -tipCluster $tipCluster"
}
if ($UseManagedDisks)
{
    $cmd += " -UseManagedDisks"
}
# $cmd += " -ImageType Standard"
$cmd += " -UseAzureResourceManager"

Write-Host "Invoking Final Command..."
Write-Host $cmd
Invoke-Expression -Command $cmd


exit 0

#The below is TODO


$LogDir = Get-Content .\report\lastLogDirectory.txt -ErrorAction SilentlyContinue
$ticks = (Get-Date).Ticks
$currentDir = (Get-Location).Path
$out = Remove-Item *.json -Force
$out = Remove-Item *.xml -Force
$zipFile = "$(($TestCycle).Trim())-$ticks-azure-buildlogs.zip"

$out = ZipFiles -zipfilename $zipFile -sourcedir $LogDir

#region Get a downloadble link of logs...
$testLogFolder = "TestCycleLogs"
$testLogStorageAccount = $xmlSecrets.secrets.testLogsStorageAccount
$testLogStorageAccountKey = $xmlSecrets.secrets.testLogsStorageAccountKey
if ($env:BUILD_NUMBER -gt 0 )
{
    $filePrefix = "$env:BUILD_NUMBER"
}
else
{
    $filePrefix = "manual"
}
Rename-Item -Path $zipFile -NewName "$filePrefix-$zipFile" | Out-Null
$compressedFile = .\Extras\UploadFilesToStorageAccount.ps1 -filePaths "$filePrefix-$zipFile" -destinationStorageAccount $testLogStorageAccount -destinationContainer "logs" -destinationFolder "$testLogFolder" -destinationStorageKey $testLogStorageAccountKey
LogMsg $compressedFile
#endregion

if ($ArchiveLogDirectory)
{
    Write-Host "Archive test results to : $ArchiveLogDirectory"
    $now = Get-Date
    $hhmmssC = Get-Date -format "HHMMssfff"
    $hhmmssP = Get-Date -format "yyyyMMdd"
    $destDir = "$testCycle-$hhmmssC"
    Mkdir -Force "$ArchiveLogDirectory\$hhmmssP" -ErrorAction SilentlyContinue | Out-Null
    $FinalDestDir = "$ArchiveLogDirectory\$hhmmssP\$destDir"
    Mkdir -Force $FinalDestDir -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path -Path $FinalDestDir )
    {
        Write-Host "$FinalDestDir - Available."
        Write-Host "Entering $FinalDestDir"
        cd $LogDir
        Write-Host "$LogDir-----------------------"
        Write-Host "Copying all items recursively to $FinalDestDir"
        Copy-Item -Path .\* -Recurse -Destination $FinalDestDir -Force
        Write-Host "Done."
        cd $currentDir
    }
}
$retValue = 1
try
{
    if (Test-Path -Path ".\report\report_$(($TestCycle).Trim()).xml" )
    {
        $resultXML = [xml](Get-Content ".\report\report_$(($TestCycle).Trim()).xml" -ErrorAction SilentlyContinue)
        Copy-Item -Path ".\report\report_$(($TestCycle).Trim()).xml" -Destination ".\report\report_$(($TestCycle).Trim())-$shortRandomNumber-junit.xml" -Force -ErrorAction SilentlyContinue
        Write-Host "Copied : .\report\report_$(($TestCycle).Trim()).xml --> .\report\report_$(($TestCycle).Trim())-$shortRandomNumber-junit.xml"
        Write-Host "Analysing results.."
        Write-Host "PASS  : $($resultXML.testsuites.testsuite.tests - $resultXML.testsuites.testsuite.errors - $resultXML.testsuites.testsuite.failures)"
        Write-Host "FAIL  : $($resultXML.testsuites.testsuite.failures)"
        Write-Host "ABORT : $($resultXML.testsuites.testsuite.errors)"
        if ( ( $resultXML.testsuites.testsuite.failures -eq 0 ) -and ( $resultXML.testsuites.testsuite.errors -eq 0 ) -and ( $resultXML.testsuites.testsuite.tests -gt 0 ))
        {
            $retValue = 0
        }
        else
        {
            $retValue = 1
        }
    }
    else
    {
        Write-Host "Summary file: .\report\report_$(($TestCycle).Trim()).xml does not exist. Exiting with 1."
        $retValue = 1
    }
}
catch
{
    Write-Host "$($_.Exception.GetType().FullName, " : ",$_.Exception.Message)"
    exit 1
}
finally
{
    if ( $finalWorkingDirectory )
    {
        Write-Host "Copying all files to original working directory."
        $tmpDest = '\\?\' + $originalWorkingDirectory
        Move-Item -Path "$finalWorkingDirectory\*" -Destination $tmpDest -Force -ErrorAction SilentlyContinue | Out-Null
        cd ..
        Write-Host "Cleaning $finalWorkingDirectory"
        Remove-Item -Path $finalWorkingDirectory -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "Setting workspace to original location: $originalWorkingDirectory"
        cd $originalWorkingDirectory
    }
    if ( $ExitWithZero -and ($retValue -ne 0) )
    {
        Write-Host "Changed exit code from 1 --> 0. (-ExitWithZero mentioned.)"
        $retValue = 0
    }
    Write-Host "Exiting with code : $retValue"
    exit $retValue
}

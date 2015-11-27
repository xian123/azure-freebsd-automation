#!/usr/bin/python

from azuremodules import *
import os.path

def RunTest(command):
    UpdateState("TestRunning")
    RunLog.info("Checking if swap disk is enable or not..")
    RunLog.info("Executing swapon -s..")
    temp = Run(command)
    output = temp

    if os.path.exists("/etc/lsb-release") and int(Run("cat /etc/lsb-release | grep -i coreos | wc -l")) > 0:
        waagent_conf_file = "/usr/share/oem/waagent.conf"
    else:
        waagent_conf_file = "/etc/waagent.conf"

    RunLog.info("Read ResourceDisk.EnableSwap from " + waagent_conf_file + "..")
    outputlist=open(waagent_conf_file)

    for line in outputlist:
        if(line.find("ResourceDisk.EnableSwap")!=-1):
                break

    valueofconfig=line.strip()[len("ResourceDisk.EnableSwap=")]
    RunLog.info("Value ResourceDisk.EnableSwap in " + waagent_conf_file + ": " + valueofconfig)
    if (("swap" in output) and (valueofconfig == "n")):
        RunLog.error('Swap is enabled. Swap should not be enabled.')
        RunLog.error('%s', output)
        ResultLog.error('FAIL')

    elif ((output.find("swap")==-1) and (valueofconfig == "y")):
        RunLog.error('Swap is disabled. Swap should be enabled.')
        RunLog.error('%s', output)
        RunLog.info("Pleae check value of setting ResourceDisk.SwapSizeMB")
        ResultLog.error('FAIL')
    
    elif(("swap" in output) and (valueofconfig == "y")):
        RunLog.info('swap is enabled.')
        if(IsUbuntu()) :
            mntresource = "/mnt"
        else:
            mntresource = "/mnt/resource"
        swapfile = mntresource + "/swapfile"
        if(swapfile in output):
            RunLog.info("swap is enabled on resource disk")
            ResultLog.info('PASS')
        else:
            RunLog.info("swap is not enabled on resource disk")
            ResultLog.info('FAIL')
    elif((output.find("swap")==-1) and (valueofconfig == "n")):
        RunLog.info('swap is disabled.')
        ResultLog.info('PASS')
    UpdateState("TestCompleted")


if (IsFreeBSD()):
    RunTest("swapinfo | grep /dev")
else:
    RunTest("swapon -s")

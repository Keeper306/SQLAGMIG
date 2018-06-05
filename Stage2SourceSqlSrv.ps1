# don't forget make cd c:\scriptfolder\sqlagmig
$ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
$Config=Import-LocalizedData -FileName Config.PSD1
Import-Module .\SqlMigration.psm1 -Force -DisableNameChecking

#Detach application databases from cluster sql instance. Databases enlisted in config file.
Function Detach-SourceSqlDatabase
{
    #Get instanceID of SQL cluster instance from config file
    $SqlInstanceID=$Config.SourceSqlCluster.ClusterGroups.Group1.InstanceId
    #Get VCO name from SQL cluster role.
    $VCOName=$Config.SourceSqlCluster.ClusterGroups.Group1.VCOName
    #Get database list to detach from config file.
    $Databases=$Config.SourceSqlServer.Databases
    #Call function to detach each database.   
    foreach ($db in $Databases.Keys)
    {
        $db=$Databases.$db.DBName        
        Detach-SqlClusterDatabase -SqlInstanceID $SqlInstanceID -VCODnsName $VCOName -SqlDatabase $db
    }
}
if($Prod){Detach-SourceSqlDatabase}

#Stop SQL cluster role.
Function Stop-SourceSqlClusterRole
{
    $SourceClusterGroup=$Config.SourceSqlCluster.ClusterGroups.Group1.Name
    Write-Log "Trying to stop cluster role $SourceClusterGroup..."
    $ClusterGroup=Stop-ClusterGroup -Name $SourceClusterGroup
    Write-log "Cluster role $($ClusterGroup.name) state is $($ClusterGroup.state) "
}
    if($Prod){Stop-SourceSqlClusterRole}
#Function detach disk from role and cluster.
#Firstly function trying to discover offline disks for cluster role.
#If it find it, then disks GUID will be set to variable and disk will be removed from the cluster.
Function Detach-SourceSqlClusterDBDisk
{
        $SourceClusterGroup=$Config.SourceSqlCluster.ClusterGroups.Group1.Name
        #Get Cluster disk resource which in offline state and in cluster role.
        $ClusterGroupDisks=Get-ClusterResource|Where {$_.OwnerGroup -eq "$SourceClusterGroup" -and $_.ResourceType -eq 'Physical Disk' -and $_.state -eq 'Offline'}
        #If disks discoverered set disk guid to variable and remove disks from cluster.    
        If ($ClusterGroupDisks)
        {
            #Get Guid of disks.
            $Script:ClusterGroupDisksGUID=$ClusterGroupDisks|Get-ClusterParameter|where name -eq 'DiskIdGuid'
            Write-log "Detach-SourceSqlClusterDBDisk found $($ClusterGroupDisks.count) offline disks. Function offer to dismount it."
            #remove disks from cluster.
            $ClusterGroupDisksGUID.value|ForEach-Object {Write-log $_}
            $ClusterGroupDisks|Remove-ClusterResource -Confirm -Verbose|ForEach-Object {Write-log $_}
                                   
        }
        #If disks not discovered, then write message about it.
        Else
        {
            Write-log "Can't find any offline disk for cluster role  $SourceClusterGroup"            
        }

}
if($Prod){Detach-SourceSqlClusterDBDisk}

#Under Development. Need to add foreach loop.
Function Mount-SourceClusterDisk
{   #If $Script:ClusterGroupDisksGUID variable  from Detach-SourceSqlClusterDBDisk doesn't exist, function try to get guid for disk from config file.
    #If $Config file does not contain disk guid value, then it try to ask guid from user.
    #If script can get guid from config file or user, it will assign guid to $DatabaseDiskGUID variable. 
    if (!$Script:ClusterGroupDisksGUID)
    {
        Write-log "There are no objects in ClusterGroupDisksGUID variable. Trying to find GUID of umounted disk in config file"
        $DatabaseDisksGUID=$Config.SourceSqlServer.DatabaseDisk.GUID
        If (!$DatabaseDiskGUID) 
        {
            Write-log "Can't find disk GUID in config file";
            $DatabaseDisksGUID=Read-Host 'Plese enter GUID of disk that you want switch to online state'
            if (!$DatabaseDisksGUID){Write-log 'Function of Mount-SourceClusterDisk cannot be completed withoug disk GUID. Script will exit';pause;exit}            
        }
    }
    #If Script got guid from Detach-SourceSqlClusterDBDisk function it use its guid to attach disk as local.
    #Or
    #If Script got guid variable from config file or user, it attach it as local.
    If ($Script:ClusterGroupDisksGUID -or $DatabaseDisksGUID)
    {
        If($Script:ClusterGroupDisksGUID)
        {    
        $DatabaseDisksGUID=$Script:ClusterGroupDisksGUID
        Write-log "Script has found `$Script:ClusterGroupDisksGUID variable and will try switch disks to online state."    
        }
        Elseif($DatabaseDisksGUID){Write-log "Script has GUID Variable and will try switch disks with guid to online state."}
        #Perform mounting operation algrorithm.
        Foreach ($DatabaseDiskGUID in $DatabaseDisksGUID)
        {            
            #Get disk with required guid.            
            $DatabaseDisk=Get-Disk|where {$_.Guid -like "*$($DatabaseDiskGUID.value)*" -and $_.IsClustered -eq $false}
            $DatabaseDisk
            #If disk with GUID found script will offer to mount it locally..
            if($DatabaseDisk)
            {
                #Confirm disk mounting operation.
                Write-Log "Function will offer to mount disk $($DatabaseDisk.Number)  $($DatabaseDisk.FriendlyName) $($DatabaseDisk.Size/1gb) GB with guid $($DatabaseDiskGUID.value)." 
                $message  = 'Request for disk mount'
                $question = "Are you sure you want to mount disk $($DatabaseDisk.Number)  $($DatabaseDisk.FriendlyName) $($DatabaseDisk.Size/1gb) GB with guid $($DatabaseDiskGUID.value) ?"                
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
                #Mount disk locally if user confirmed this operation.
                if ($decision -eq 0) {
                    Write-Log 'confirmed'
                    #Return disk to online state making it writeable to host.
                    $DatabaseDisk|Set-Disk -IsReadOnly $false
                    $DatabaseDisk|Set-Disk -IsOffline $false
                    Get-Disk -Number $DatabaseDisk.Number|ForEach-Object {Write-log "$($_.Number) $($_.FriendlyName) $($_.OperationalStatus)" }
                }
                #Cancel operation if don't confirm it.
                else {
                    Write-Log 'cancelled'
                }
            }            
        }
    }

}
if($Prod){Mount-SourceClusterDisk}
#>
#Remove SourceSqlServer from cluster.
Function Remove-SourceClusterNode
{
    #Get name of the node and cluster from config file.
    $SourceSqlServer=$Config.SourceSqlServer.Name
    $SourceSqlCluster=$Config.SourceSqlCluster.name
    Write-Log "Remove $SourceSqlServer from cluster $SourceSqlCluster"
    #Remove source node from (n+1 cluster).
    Remove-ClusterNode -Name $SourceSqlServer -Confirm -Verbose|ForEach-Object {Write-log $_}
}
if($Prod){Remove-SourceClusterNode}


#Install StandAlone SQL Instance on SourceNode
Function Install-SqlSourceStandaloneInstance
{
    #Initialize Installation variables.
    #Get location of sql setup folder.
    $SQLSourceFiles=$Config.SqlStanaloneInstallation.MediaFilesPath
    #Get Instance ID for standalone sql instance.
    $SqlInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
    #Get name of service account for mssql installation.
    $SQLServiceAccount=$Config.SqlStanaloneInstallation.SourceServiceAccountName
    #Get intallation path for sql setup.
    $SqlInstancePath=$Config.SqlStanaloneInstallation.SourceInstancePath
    #Get name of server to check it later.
    $SqlServername=$Config.SourceSqlServer.Name
    Write-log "Checking name of Server."
    #Check name of the server with name from config file
    #If name is correct script will ask password sql service account and SA and then call Install-SQLStandaloneInstance from SqlMigration.psm . 
    If($SqlServername -eq "$env:COMPUTERNAME")
    {
        Write-log "Server name check passed."
        $SQLSvcPassword= Read-Host -assecurestring "Please enter password for service account $SQLServiceAccount"
        $SqlSaPassword=Read-Host -assecurestring "Please enter password for SA account"
        Write-log "Call Install-SQLStandaloneInstance function..."
        Install-SQLStandaloneInstance -SqlSourceFilesPath $SQLSourceFiles -SqlInstanceID $SqlInstanceID -SqlServiceAccountName $SQLServiceAccount -SqlSvcPassword $SQLSvcPassword -SqlSAPassword $SqlSaPassword -SqlInstancePath $SqlInstancePath
    }
    #If name of the server is incorrect script will write to log correlated message and exit.
    Else {Write-log "Name of the server from config file ($SqlServername) does not math with name of this computer ($env:COMPUTERNAME)."}

}
if($Prod){Install-SqlSourceStandaloneInstance}
#Call function which configfure standalone sql instance on source sql server. Additional info in Config-SqlServerInstance function im SqlMigration.psm1 file.
Function Config-SourceSqlServerInstance
{
    #Get Servername and instance ID from config file.
    $SourceSqlServerName=$Config.SourceSqlServer.Name
    $SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
    Config-SqlServerInstance -SqlInstanceID $SourceSqlServerInstanceID -ComputerName $SourceSqlServerName
}
if($prod){Config-SourceSqlServerInstance}
#Call function which configfure standalone sql instance on destination sql server. Additional info in Config-SqlServerInstance function im SqlMigration.psm1 file.
Function Config-DestSqlServerInstance
{
    #Get Servername and instance ID from config file.
    $DestSqlServerName=$Config.DestinationSqlServer.Name
    $DestSqlServerInstanceID=$Config.SqlStanaloneInstallation.DestInstanceID
    Config-SqlServerInstance -SqlInstanceID $DestSqlServerInstanceID -ComputerName $DestSqlServerName
}
if($prod){Config-DestSqlServerInstance}
#Add sql logins to standalone sql instance on source sql server.
Function Add-SourceSqlServerLogin
{
    #Get Servername and instance ID from config file.
    $SourceSqlServerName=$Config.SourceSqlServer.Name
    $SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
    #Get list of admins logins (from config file) to add it to standalone instance.
    $UserAdminlist=$Config.SqlUserAdminList
    #Cycle each user in list.
    Foreach ($Element in $UserAdminlist.Keys)
    {
        $Login=$UserAdminlist.$Element
        Write-log "Adding User $Login with admiministratie privileges."
        #Call Add-SqlServerLogin function from SqlMigration.psm1 module. Function will add logins to sql instance and gives them sysAdmin role.
        Add-SqlServerLogin -SqlInstanceID $SourceSqlServerInstanceID -ComputerName $SourceSqlServerName -DomainLogins $Login -AddSysAdminRole
    }
    $Userlist=$Config.SqlUserList
    #Get list of user logins (from config file) to add it to standalone instance.
    Foreach ($Element in $Userlist.Keys)
    {
        $Login=$Userlist.$Element
        Write-log "Adding User $Login."
        #Call Add-SqlServerLogin function from SqlMigration.psm1 module. Function will add logins to sql instance.
        Add-SqlServerLogin -SqlInstanceID $SourceSqlServerInstanceID -ComputerName $SourceSqlServerName -DomainLogins $Login        
    }
}
if($prod){Add-SourceSqlServerLogin}
#Add sql logins to standalone sql instance on destination sql server.
Function Add-DestinationSqlServerLogin
{
    $DestSqlServerName=$Config.DestinationSqlServer.Name
    $SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.DestInstanceID
    #Get list of admins logins (from config file) to add it to standalone instance.
    $UserAdminlist=$Config.SqlUserAdminList
    Foreach ($Element in $UserAdminlist.Keys)
    {
        $Login=$UserAdminlist.$Element
        Write-log "Adding User $Login with admiministratie privileges."
        #Call Add-SqlServerLogin function from SqlMigration.psm1 module. Function will add logins to sql instance and gives them sysAdmin role.
        Add-SqlServerLogin -SqlInstanceID $SourceSqlServerInstanceID -ComputerName $DestSqlServerName -DomainLogins $Login -AddSysAdminRole
    }
    $Userlist=$Config.SqlUserList
    Foreach ($Element in $Userlist.Keys)
    {
        $Login=$Userlist.$Element        
        Write-log "Adding User $Login."
        #Call Add-SqlServerLogin function from SqlMigration.psm1 module. Function will add logins to sql instance.
        Add-SqlServerLogin -SqlInstanceID $SourceSqlServerInstanceID -ComputerName $DestSqlServerName -DomainLogins $Login        
    }
}
if($prod){Add-DestinationSqlServerLogin}

#Import msdb and model database from cluster instance to standalone instance and create additional TempDB.
Function Alter-SourceServerSysDBDatabase
{
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    Import-Module sqlps -DisableNameChecking
    #Initialize Variables for connection to database
    $StandSourceInstanceID=$config.SqlStanaloneInstallation.SourceInstanceID
    #Initialize path to SQL standalone instance default sysdb folder
    $StandSourceInstanceSysDBPath=$Config.SqlStanaloneInstallation.SourceInstancePath+"MSSQL11.$StandSourceInstanceID\MSSQL\DATA"
    #Initialize cluster system databases objects from config variable.
    $ClusInstanceSystemDatabases=$Config.SourceSqlServer.SystemDatabases
    #Start Cycle which alter system database from config file (msdb, model and tempdb) in Standalone Instance  
    #(rename current standalone instance model and msdb database files and get copy of those files from cluster instance).
    #Then cycle increase number of tempdb files in tempdb database (segment database). .
    foreach ($db in $ClusInstanceSystemDatabases.Keys)
    {
        #Condition to ignore master database in cycle, to 
        if ($db -ne 'master' -and $db.DBFileName -ne 'model.mdf' )
        {
            Write-log $db
            #DB file Name Variables.
            $dbFileName=$ClusInstanceSystemDatabases.$db.DBFileName
            #Path to old cluster SysDB data file.
            #$Config.SourceSqlServer.StandaloneInstanceName
            $ClusDBFilePath=$ClusInstanceSystemDatabases.$db.ParentPath+"\"+$ClusInstanceSystemDatabases.$db.DBFileName
            #DB log name Variables.
            $dbLogName=$ClusInstanceSystemDatabases.$db.LogFileName                 
            #Path to old cluster SysDB log         
            $ClusDBLogPath=$ClusInstanceSystemDatabases.$db.ParentPath+"\"+$dbLogName
            #Paths to stanalone SysDB File
            $StandDBFilePath=$StandSourceInstanceSysDBPath+"\"+$dbFileName
            $StandDBLogPath=$StandSourceInstanceSysDBPath+"\"+$dbLogName
            #Start cycle for msdb and model system database
            if ($db -ne 'tempdb')
            {                
                #Get service status of SQL standalone instance.
                $InstanceService=get-service ("MSSQL$"+$StandSourceInstanceID)
                #If Service running then stop it.
                if($InstanceService.Status -eq 'running'){$InstanceService|Stop-Service -Force}
                #Rename msdb and model database files (mdf and ldf log files) in standalone instance sysdb folder (add old prefix).
                if( (test-path $StandSourceInstanceSysDBPath+"\Old"+$dbFileName) -ne $true)
                {
                    Write-log "Renaming $StandDBFilePath to $('Old'+$dbFileName)"
                    Rename-Item -Path $StandDBFilePath -NewName ('Old'+$dbFileName)
                }
                else{write-log "$('Old'+$dbFileName) already exist." }
                if( (test-path $StandSourceInstanceSysDBPath+"\Old"+$dbLogName) -ne $true)
                {
                    Write-Log "Renaming $StandDBLogPath to $('Old'+$dbLogName)"
                    Rename-Item -Path $StandDBLogPath -NewName ('Old'+$dbLogName)
                }
                else{write-log "$('Old'+$dbLogName) already exist." }                
                #Copy sys db files from cluster sysdb folder to standalone instance sysd folder.
                Write-log "Copy file $ClusDBFilePath to $StandSourceInstanceSysDBPath"
                Copy-Item -Path $ClusDBFilePath -Destination $StandSourceInstanceSysDBPath
                Write-log "Copy file $ClusDBLogPath to $StandSourceInstanceSysDBPath"
                Copy-Item -Path $ClusDBLogPath -Destination $StandSourceInstanceSysDBPath
                Remove-Variable InstanceService                
            }               
        }    
    }
    #Get MSSQL service and start it after script completion.
    $InstanceService=get-service ("MSSQL$"+$StandSourceInstanceID)
    if($InstanceService.Status -ne 'running'){$InstanceService|Start-Service} 
    cd c:;cd $ScriptRootPath
}
if($Prod){Alter-SourceServerSysDBDatabases}
Function Alter-SourceServerTempDBDatabases
{
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    Import-Module sqlps -DisableNameChecking
    #Initialize Variables for connection to database
    $StandSourceInstanceID=$config.SqlStanaloneInstallation.SourceInstanceID
    $SrcSqlServerStandaloneInstName=$config.SourceSqlServer.Name+"\"+$config.SqlStanaloneInstallation.SourceInstanceID
    #Initialize path to SQL standalone instance default sysdb folder
    $StandSourceInstanceSysDBPath=$Config.SqlStanaloneInstallation.SourceInstancePath+"MSSQL11.$StandSourceInstanceID\MSSQL\DATA"
    #Initialize cluster system databases objects from config variable.
    $ClusInstanceSystemDatabases=$Config.SourceSqlServer.SystemDatabases
    #Start Cycle which alter system database from config file (msdb, model and tempdb) in Standalone Instance  
    #(rename current standalone instance model and msdb database files and get copy of those files from cluster instance).
    #Then cycle increase number of tempdb files in tempdb database (segment database). .
    foreach ($db in $ClusInstanceSystemDatabases.Keys)
    {
        #Condition to ignore master database in cycle, to 
        if ($db -ne 'master' -and $db.DBFileName -ne 'model.mdf' )
        {
            Write-log $db
            #DB file Name Variables.
            $dbFileName=$ClusInstanceSystemDatabases.$db.DBFileName
            $dbFileLogicalName=$ClusInstanceSystemDatabases.$db.DBLogicalName                                 
            #Start cycle for tempdb additional file creation.  
            if ($db -eq 'tempdb')
            {
                #Get status of sql service
                $InstanceService=get-service ("MSSQL$"+$StandSourceInstanceID)
                if($InstanceService.Status -ne 'running'){$InstanceService|Start-Service}                
                #File size of additio
                $tempdbFileSize='5242880KB'
                $tempdbFileGrowth='131072KB'
                #Increment for loop
                $Increment=2
                Write-log "Adding addittional database files to tempdb database." 
                #Start loop. That add additional tempdb files while $Increment lesser or equal 8.               
                do
                {                
                    #Show current increment value.
                    "Increment is equal $Increment"
                    #Create variable for tempdb file name. It contain standard tempdb file name + current $increment value.
                    $TempdbFileLogicalName=$dbFileLogicalName+$Increment
                    #Create path to the tempdb file.
                    $TempdbFilePath=$StandSourceInstanceSysDBPath+"\"+$db+$Increment+'.ndf'
                    #Check if file already exist. If not, then 
                    if ((Test-Path $TempdbFilePath) -eq $false)
                    {
                        $Query="alter database $db ADD FILE ( NAME = '$TempdbFileLogicalName' , FILENAME = '$TempdbFilePath', SIZE = $tempdbFileSize , FILEGROWTH = $tempdbFileGrowth)"
                        Write-log $Query
                        Invoke-Sqlcmd -ServerInstance $SrcSqlServerStandaloneInstName -Query $Query
                    }
                    #Increase value of $increment variable
                    $Increment++
                }
                While ($Increment -le 8)
                #Remove InstanceService variable to ensure it will not be inherited with another cycle.
                Remove-Variable InstanceService              
            }    
        }    
    }
    #Get MSSQL service and start it after script completion.
    $InstanceService=get-service ("MSSQL$"+$StandSourceInstanceID)
    if($InstanceService.Status -ne 'running'){$InstanceService|Start-Service} 
    cd c:;cd $ScriptRootPath
}
if($Prod){Alter-SourceServerTempDBDatabases}
#Function Attach application databases to standalone instance on source sqlserver
Function Attach-SourceServerDatabase
{
    #Initialize varitables.
    $SrcSqlServerStandaloneInstName=$config.SourceSqlServer.Name+"\"+$config.SqlStanaloneInstallation.SourceInstanceID
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    Import-Module sqlps -DisableNameChecking
    #Create object representing sqlserver.
    $SqlServer=New-Object "Microsoft.SqlServer.Management.Smo.Server" $SrcSqlServerStandaloneInstName
    #Get list of application databases from config file.
    $Databases=$Config.SourceSqlServer.Databases
    #Cycle through each Database to add it to standalone sql instance.
    foreach ($db in $Databases.Keys)
    {
        #Create string collection object.
        $sc = new-object System.Collections.Specialized.StringCollection
        #Get name of current db.
        $DatabaseName=$databases.$db.dbName
        #Get path to mdf and ldf files of db and then add it to $sc string collection.
        $mdffile=$databases.$db.DBFileParentPath+$databases.$db.DBFileName
        $ldffile=$databases.$db.DBLogFilePath+$databases.$db.LogFileName
        $sc.Add($mdffile)
        $sc.Add($ldffile)
        "Attaching $sc for $DatabaseName"
        #Call method which attach database from $sc string collection.
        $SqlServer.AttachDatabase($DatabaseName,$sc)        
    }
    cd c:  ;cd $ScriptRootPath
}
if($Prod){Attach-SourceServerDatabase}
#Add source sql server to destination cluster.
Function Add-SourceSqlServerToDestCluster
{
    #Get name of destination cluster.
    $DestCluster=$Config.DestinationSqlCluster.CNO
    #Get name of source sql server.
    $SourceSqlServer=$Config.SourceSqlServer.Name
    Write-Log "Trying to add $SourceSqlServer to $DestCluster cluster"
    Add-ClusterNode -Cluster $DestCluster -Name $SourceSqlServer -NoStorage
}
if($Prod){Add-SourceSqlServerToDestCluster}
#Enable SQLAlwaysOn on standalone instance of source sql server.
Function Enable-SourceSQLServerAlwaysOn
{
    $SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
    Add-SQLAlwaysOn -SqlInstanceID $SourceSqlServerInstanceID
}
if($Prod){Enable-SourceSQLServerAlwaysOn}

#(Optional function)
#Set each application database recovery mode to full on stanadlone sql instance on source sql server.
Function Change-SourceSqlServerRecoveryModel
{
    $SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
    $Databases=$Config.SourceSqlServer.Databases
    foreach ($db in $Databases.Keys)
    {
        $Databases.$db.DBName
        Change-SqlServerRecoveryModel -SqlInstanceID $SourceSqlServerInstanceID -DatabaseName $Databases.$db.DBName     
    }    
}
if($Prod){Change-SourceSqlServerRecoveryModel}

#Optional Function
#Create SMB Share on source sql server.
Function Create-SourceSqlServerSmbShare
{
    #Initialize variables.
    $ShareName=$Config.BackupShare.Name
    $ShareLocalPath=($config.SourceSqlServer.DatabaseDisk.Label+$ShareName)
    $ShareUncPath=$Config.BackupShare.UncPath      
    Write-log "Test share existence - $ShareUncPath"      
    #Create share if it does not exist.
    If (!(Test-Path $ShareUncPath)){
        Write-log "Share $ShareName does not exist. Trying to create new one"
        #Create backup folder if it does not exist.
        If (!(Test-Path -Path $ShareLocalPath) )
        {
            Write-log "Creating local folder. Path - $ShareLocalPath "
            New-Item -Path $ShareLocalPath  -Type Directory|Out-Null
            #Set Access for SysDB Directory
            $ShareFolder=Get-Item $ShareLocalPath
            $ACL=$ShareFolder.GetAccessControl('Access')
            $Username=$Config.SqlStanaloneInstallation.SourceServiceAccountName
            $AccessRule= New-Object System.Security.AccessControl.FileSystemAccessRule($Username,'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $ACL.SetAccessRule($AccessRule)
            Set-Acl -path $ShareLocalPath -AclObject $Acl
        }
        #Create SMB Share.
        Write-log "Creating new smb Share with $ShareName name. Path - $ShareLocalPath"
        New-SmbShare -Name $ShareName -Path $ShareLocalPath -FullAccess 'Everyone'      
    }
    #Do notning if share already exist.
    Else
    {
        Write-log "Share $ShareUncPath is already exist"
    }
}
if($Prod){Create-SourceSqlServerSmbShare}


#Backupp each database to backup share.
Function Backup-SourceSqlServerDatabases
{
$SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
$Databases=$Config.SourceSqlServer.Databases
$BackupPath=$Config.BackupShare.UncPath
    foreach ($db in $Databases.Keys)
    {
        $Databases.$db.DBName
        Backup-SqlServerDatabase -SqlInstanceID $SourceSqlServerInstanceID -DatabaseName $Databases.$db.DBName -BackupPath $BackupPath     
    }    
}
if($Prod){Backup-SourceSqlServerDatabases}


#Restore each apllication database from backup share with NoRecoveryOption on destination SQL Server
Function Restore-DestinationSqlServerDatabases
{
Import-Module SQLPS -DisableNameChecking
#Get variables from config file.
$DestinationSqlServer=$config.DestinationSqlServer.Name
$DestSqlServerInstanceID=$Config.SqlStanaloneInstallation.DestInstanceID
$Databases=$Config.SourceSqlServer.Databases
$BackupPath=$Config.BackupShare.UncPath
$DatabaseDiskLabel=($config.SourceSqlServer.DatabaseDisk.Label).Substring(0,1)
#Create pssession with Destination server.
$Session=New-PSSession -ComputerName $DestinationSqlServer
#Check existence of database volume on destination server. Function will exit if volume does not exist.
$DestSqlServerVolumeCheck=Invoke-Command -Session $Session -ScriptBlock {param($DatabaseDiskLabel) Get-Volume $DatabaseDiskLabel} -ArgumentList $DatabaseDiskLabel
If (!$DestSqlServerVolumeCheck){Write-log "Volume $DatabaseDiskLabel does not exist on destination server $DestinationSqlServer. Please add required volume to $DestinationSqlServer";return}    
#Check for existence of database data and log folders for sql databases and create it if not exist.
#After script will Call Restore-SqlServerDatabase function from SQL Migration module.     
foreach ($db in $Databases.Keys)
    {
        $Databases.$db.DBName
        $DatabaseFolderPath=$Databases.$db.DBFileParentPath
        $DatabaseLogFolderPath=$Databases.$db.DBLogFilePath
        Invoke-Command -Session $Session -ArgumentList $DatabaseFolderPath,$DatabaseLogFolderPath -ScriptBlock {
            param($DatabaseFolderPath,$DatabaseLogFolderPath)
            Write-log "Trying to discover $DatabaseFolderPath"
            If (!(Test-Path $DatabaseFolderPath))
            {
                Write-log "Folder $DatabaseFolderPath does not exist. Script will try to create it..."                   
                New-Item -Path $DatabaseFolderPath  -Type Directory|Out-Null
            }
                Write-log "Trying to discover $DatabaseLogFolderPath"
                If (!(Test-Path $DatabaseLogFolderPath))
            {
                Write-log "Folder $DatabaseLogFolderPath does not exist. Script will try to create it..."                   
                New-Item -Path $DatabaseLogFolderPath  -Type Directory|Out-Null
            }

        }
                
        Restore-SqlServerDatabase -SqlInstanceID $DestSqlServerInstanceID -DatabaseName $Databases.$db.DBName -BackupPath $BackupPath -computername $DestinationSqlServer    
    }    
}
if($Prod){Restore-DestinationSqlServerDatabases}
#Create database mirroring endpoint on source sql server
Function Create-SourceSqlServerEndpoint
{
    #Initialize variables.
    $SourceSqlServerInstanceID=$Config.SqlStanaloneInstallation.SourceInstanceID
    $SQLServiceAccount=$Config.SqlStanaloneInstallation.SourceServiceAccountName
    #Call function Create-SqlServerEndpoint from sql migration module.
    Create-SqlServerEndpoint -SqlInstanceID $SourceSqlServerInstanceID -SQLServiceAccount $SQLServiceAccount

}
if($Prod){Create-SourceSqlServerEndpoint}
#Create database mirroring endpoint on destination sql server
Function Create-DestinationSqlServerEndpoint
{
    #Initialize variables.
    $DestSqlServerName=$Config.DestinationSqlServer.Name
    $DestSqlServerInstanceID=$Config.SqlStanaloneInstallation.DestInstanceID
    $SQLServiceAccount=$Config.SqlStanaloneInstallation.SourceServiceAccountName
    Create-SqlServerEndpoint -SqlInstanceID $DestSqlServerInstanceID -ComputerName $DestSqlServerName -SQLServiceAccount $SQLServiceAccount
}
if($Prod){Create-DestinationSqlServerEndpoint}
#Create SQL availability group on source SQL server standalone instance.
Function Create-SourceSqlServerAG
{
    #Initialize variables and import modules.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    Import-Module sqlps -DisableNameChecking
    $AGName=$Config.AvaiabilityGroup.Name
    $SrcSqlServerStandaloneInstName=$config.SourceSqlServer.Name+"\"+$config.SqlStanaloneInstallation.SourceInstanceID
    $DestSqlServerStandaloneInstName=$Config.DestinationSqlServer.StandaloneInstanceName
    #Get version of sql for template creation.
    $SQLVersion = (Get-Item ("SQLSERVER:\Sql\"+$SrcSqlServerStandaloneInstName)).version
    #Create FQDN variables.
    $SourceSqlServerFQDN=$Config.SourceSqlServer.Name+"."+$env:USERDNSDOMAIN
    $DestSqlServerFQDN=$Config.DestinationSqlServer.Name+"."+$env:USERDNSDOMAIN
    #Create the primary replica as a template objectS    
    $primaryReplica = New-SqlAvailabilityReplica -Name $SrcSqlServerStandaloneInstName -EndpointUrl (“TCP://"+$SourceSqlServerFQDN+":5022”) -AvailabilityMode “SynchronousCommit” -FailoverMode 'Automatic' -AsTemplate -Version $SQLVersion  
    #Create the secondary replica as a template object
    $secondaryReplica = New-SqlAvailabilityReplica -Name $DestSqlServerStandaloneInstName -EndpointUrl (“TCP://"+$DestSqlServerFQDN+":5022”) -AvailabilityMode “SynchronousCommit” -FailoverMode 'Automatic' -AsTemplate -Version $SQLVersion    
    # Create the availability group
    Write-Log 
    New-SqlAvailabilityGroup -name $AGName -Path ("SQLSERVER:\SQL\"+$SrcSqlServerStandaloneInstName) -AvailabilityReplica ($primaryReplica,$secondaryReplica) -Confirm
    cd c:  ;cd $ScriptRootPath
}
if($Prod){Create-SourceSqlServerAG}
#Join destination server to availability group.
Function Join-DestSqlServerAG
{
    #Initialize variables and import SQLPS module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    Import-Module sqlps -DisableNameChecking
    $AGName=$Config.AvaiabilityGroup.Name
    $DestSqlServerStandaloneInstName=$Config.DestinationSqlServer.StandaloneInstanceName
    #Join destination server standalone instance to availability group.
    Join-SqlAvailabilityGroup -Path ("SQLSERVER:\SQL\"+$DestSqlServerStandaloneInstName) -Name $AGName
    cd c:;cd $ScriptRootPath
}
if($Prod){Join-DestSqlServerAG}
#Add application databases to availability group on source sql server (primary replica)
Function Add-SourceSqlServerAGDatabases
{
    #Initialize variables and import SQLPS module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    $AGName=$Config.AvaiabilityGroup.Name
    $SourceSqlServerStandaloneInstName=$config.SourceSqlServer.Name+"\"+$config.SqlStanaloneInstallation.SourceInstanceID
    $Databases=$Config.SourceSqlServer.Databases
    Import-Module sqlps -DisableNameChecking
    #Add each application database from config file to availability group.
    foreach ($db in $Databases.Keys)
    {
        $Databases.$db.DBName
        "Trying to add "+$Databases.$db.DBName+" database to $AGName availability group on $DestSqlServerStandaloneInstName instance "
        Add-SqlAvailabilityDatabase -Path ("SQLSERVER:\SQL\"+$SourceSqlServerStandaloneInstName+"\AvailabilityGroups\"+$AGName) -Database $Databases.$db.DBName     
    }    
    
    cd c:  ;cd $ScriptRootPath
}
if($Prod){Add-SourceSqlServerAGDatabases}

#Add application databases to availability group on destination sql server (secondary replica)
Function Add-DestinationSqlServerAGDatabases
{
    #Initialize variables and import SQLPS module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    $AGName=$Config.AvaiabilityGroup.Name
    $DestSqlServerStandaloneInstName=$Config.DestinationSqlServer.StandaloneInstanceName
    $Databases=$Config.SourceSqlServer.Databases
    Import-Module sqlps -DisableNameChecking
    #Add each application database from config file to availability group.
    foreach ($db in $Databases.Keys)
    {
        $Databases.$db.DBName
        "Trying to add "+$Databases.$db.DBName+" database to $AGName availability group on $DestSqlServerStandaloneInstName instance "
        Add-SqlAvailabilityDatabase -Path ("SQLSERVER:\SQL\"+$DestSqlServerStandaloneInstName+"\AvailabilityGroups\"+$AGName) -Database $Databases.$db.DBName   
    } 
    cd c:  ;cd $ScriptRootPath
}
if($Prod){Add-DestinationSqlServerAGDatabases}
#Create listener for sql availability group.
Function Create-SourceSqlServerAGListener
{
    #Initialize variables and import SQLPS module.
    $AGName=$Config.AvaiabilityGroup.Name
    $StaticIP=$Config.AvaiabilityGroup.StaticIp
    $SourceSqlServerStandaloneInstName=$config.SourceSqlServer.Name+"\"+$config.SqlStanaloneInstallation.SourceInstanceID
    Import-Module sqlps -DisableNameChecking
    #Create listener.
    New-SqlAvailabilityGroupListener -Name $AGName -staticIP $StaticIP -Port 1433 -Path ("SQLSERVER:\SQL\"+$SourceSqlServerStandaloneInstName+"\AvailabilityGroups\"+$AGName)
}
if($Prod){Create-SourceSqlServerAGListener}
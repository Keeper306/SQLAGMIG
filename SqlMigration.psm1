#Function for logging.
function Write-Log 
{ 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
        ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path="GeneralLog"+(get-date -Format yyMMdd)+".log", 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    { 
        if($ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName){$Path=$ScriptRootPath+'\'+$Path}
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber) { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            $NewLogFile = New-Item $Path -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
                $LevelText = 'INFO:' 
                } 
            } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End 
    { 
    } 
}
#Function check existence of sql instance.
Function Check-SQLInstance
{
    Param(
        # Instance id of sql instance.
        [Parameter(Mandatory=$true)]
        [string]$SQLInstanceID
    )
    #Check wmi instance for list of instances and trying to filter out object with $sqlinstanceid value.
    $SQLInstanceCheck=Get-CimInstance -Namespace root/Microsoft/SqlServer/ComputerManagement11 -ClassName ServerSettings -ErrorAction SilentlyContinue|Where-Object instancename -EQ "$SQLInstanceID"
    if ($SQLInstanceCheck)
    {
        Write-Log "Instance with name $SQLInstanceID is found."
        return $SQLInstanceCheck

    }
    else 
    {
        Write-Log "Instance with name $SQLInstanceID not found"
    }
}
#Function to install SQL standalone instance. Function creates answer file  and call sql setup with parameters for unattended installation.
Function Install-SQLStandaloneInstance
{
    Param
    (
        [Parameter(Mandatory=$false,Position=1)]
        [ValidateSet('Auto','Manual')]
        [string]$DeploymentType='Auto', #Type of installation. Auto=Fully automated. Manual=You can change options before installation start.        
        [Parameter(Mandatory=$true)] 
        [string]$SqlSourceFilesPath, #Path where sql media is located.       
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID, #Sql instance name for installation.
        [Parameter(Mandatory=$True)] 
        [string]$SqlServiceAccountName, #Sql service account for sql service. Format= mydomain\myaccount
        [Parameter(Mandatory=$true)] 
        [SecureString]$SqlSAPassword, #SA Password in securestirng format.
        [Parameter(Mandatory=$true)] 
        [SecureString]$SqlSvcPassword, #Sql service account password.      
        [Parameter(Mandatory=$False)] 
        [string]$SqlInstancePath='C:\Program Files\Microsoft SQL Server' #Setup path for sql instance.
    )
    #Check existence of sql instance.
    Write-log "Check existence of $SqlInstanceID"
    $SqlInstanceCheck=Check-SQLInstance -SQLInstanceID $SqlInstanceID
    If(!$SQLInstanceCheck)
    {
        "Check Passed. Starting next step..."
        #Initialize Create-SqlConfigFile Script.    
        . .\PsScripts\Create-SqlConfigFile.ps1
        Write-log 'Generating answer file for SQL Standalone Instance' 
        #Run function for generation of config file for sql setup.
        $ConfigFile=Create-SqlConfigFile -ConfigFileName $SqlInstanceID -SqlInstanceID $SqlInstanceID -DeploymentType $DeploymentType -SqlServiceAccountName $SqlServiceAccountName -SqlInstancePath $SqlInstancePath
        #Convert Passwords to string before command execution.
        [string]$SQLSvcPassword=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SQLSvcPassword))
        [string]$SqlSaPassword=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlSaPassword))
        #Variable that contain call command for sql setup with required parameters.
        $ExecuteExpression="$SqlSourceFilesPath`setup.exe /SAPWD=`"$SqlSAPassword`" /SQLSVCPASSWORD=`"$SqlSvcPassword`" /AGTSVCPASSWORD=`"$SqlSvcPassword`" /ConfigurationFile=$configFile"
        #Start installation.
        Invoke-Expression $ExecuteExpression
    }
    #Stop function if intance with this name already exist.
    Else {Write-log "Instance with name $SqlInstanceID already exist. Use different name or install it on another server."}
}
#Set default UFPS parameters for sql instance.
Function Config-SqlServerInstance
{
   Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID,
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME
    )  
    #Root path to return after call of SQL module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    $SqlServerInstanceFullName=$ComputerName+"\"+$SqlInstanceID
    #Get current amount of RAM in MB.
    $PhysicalMemory=((Get-CimInstance -ClassName 'Cim_PhysicalMemory' | Measure-Object -Property Capacity -Sum).Sum)/1024/1024
    if ($PhysicalMemory -gt 4096)
    {
    #Configure amount of maximum RAM.
    $SQLServerMemory=$PhysicalMemory-4096
    Write-log "$PhysicalMemory MB is discovered on the system. Script will set maximum server memory for SQL to $SQLServerMemory"
    $MemoryConfigQuery="
    exec sp_configure 'max server memory', $SQLServerMemory"
    }
    #Default sql instance configuration for UFPS instance.
    $InstanceConfigQuery="
       
        exec sp_configure 'show advanced options', 1
        go
        reconfigure
        go
        $MemoryConfigQuery
        go
              reconfigure
        go
        exec sp_configure 'backup compression default', 1
        go
        exec sp_configure 'Database Mail XPs', 1
        go
        exec sp_configure 'fill factor (%)', 100
        go
        exec sp_configure 'xp_cmdshell', 1
        go
        exec sp_configure 'max degree of parallelism', 1
        go
        reconfigure
        go
        dbcc traceon (3042, -1) 
        dbcc traceon (1117, -1)
        dbcc traceon (4136, -1)
        dbcc traceon (4199, -1)
    "
    #Import modules and start configuration.
    Import-Module -Name SQLPS -DisableNameChecking
    Write-Log "Start SQL configuration. Memory will be set to $SQLServerMemory.
    Next command will be executed:
    dbcc traceon (3042, -1) exec sp_configure 'show advanced options', 1
    go
    reconfigure
    $MemoryConfigQuery
    go
    reconfigure
    go
    dbcc traceon (1117, -1) exec sp_configure 'show advanced options', 1
    go
    reconfigure
    exec sp_configure 'backup compression default', 1
    go
    exec sp_configure 'Database Mail XPs', 1
    go
    exec sp_configure 'fill factor (%)', 100
    go
    exec sp_configure 'xp_cmdshell', 1
    go
    exec sp_configure 'max degree of parallelism', 1
    go
    reconfigure
    go
    dbcc traceon (1117, -1)
    dbcc traceon (4136, -1)
    dbcc traceon (4199, -1)"
    Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $InstanceConfigQuery           
    cd c: ;cd $ScriptRootPath
}
#Change recovery model for specified database
Function Change-SqlServerRecoveryModel
{
    Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID,
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME,
        [Parameter(Mandatory=$True)] 
        [string]$DatabaseName
    )

    #Initialize variables and import sqlps module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    $SqlServerInstanceFullName=$ComputerName+"\"+$SqlInstanceID
    Import-Module SQLPS -DisableNameChecking
    #Generate change recovery model query
    Write-log "Start change recovery model opetaion on $DatabaseName in $SqlServerInstanceFullName instance "
    $Query="
        USE master ;  
        ALTER DATABASE $DatabaseName SET RECOVERY FULL ; 
    "
    #Invoke sqlcmd with generated command.
    Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $Query
    cd c:  ;cd $ScriptRootPath

}
#Function to backup specified database
Function Backup-SqlServerDatabase
{
    Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID, #Instance for backup.
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME, #Computername of server for backup.
        [Parameter(Mandatory=$True)] 
        [string]$DatabaseName, #Database name for backup.
        [Parameter(Mandatory=$True)] 
        [string]$BackupPath #Path for backup.
    )
    #Initialize variables and import sqlps module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    $SqlServerInstanceFullName=$ComputerName+"\"+$SqlInstanceID
    $BackupFilePath=($BackupPath+'\'+$DatabaseName+".bak")
    $BackupLogPath=($BackupPath+'\'+$DatabaseName+".log")
    Import-Module SQLPS -DisableNameChecking
    #Start DB backup query with 12 hours timeout.
    Write-log "Start DB File Backup operation on database $DatabaseName in $SqlServerInstanceFullName instance. Destination path is $BackupFilePath"
    $Query="BACKUP DATABASE $DatabaseName TO DISK = N'$BackupFilePath' WITH FORMAT"
    Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $Query -QueryTimeout 43200
    #Start DB log backup query with 3 hours timeout
    $Query="BACKUP log $DatabaseName TO DISK = N'$BackupLogPath' WITH FORMAT"
    Write-log "Start DB log Backup operation on database $DatabaseName in $SqlServerInstanceFullName instance. Destination path is $BackupLogPath"
    Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $Query -QueryTimeout 21600
    cd c:  ;cd $ScriptRootPath
}
#Restore database from specified backup.
Function Restore-SqlServerDatabase
{
    Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID, #Instance for restore operation.
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME,#Computer name for restore operation.
        [Parameter(Mandatory=$True)] 
        [string]$DatabaseName, #Name of database to restore.
        [Parameter(Mandatory=$True)] 
        [string]$BackupPath #Path where DB backup reside.
    )
    #Initialize variables and import sqlps module.
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName    
    $SqlServerInstanceFullName=$ComputerName+"\"+$SqlInstanceID
    $BackupFilePath=($BackupPath+'\'+$DatabaseName+".bak")
    $BackupLogPath=($BackupPath+'\'+$DatabaseName+".log")
    Import-Module SQLPS -DisableNameChecking
    #Start DB restore query with 12 hours timeout.
    Write-log "Start DB File Restore operation on database $DatabaseName in $SqlServerInstanceFullName instance. Destination path is $BackupFilePath"
    $Query="RESTORE DATABASE $DatabaseName FROM DISK = N'$BackupFilePath' WITH NORECOVERY"
    Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $Query -QueryTimeout 43200
    #Start DB log restore query with 3 hours timeout
    $Query="RESTORE LOG $DatabaseName FROM DISK = N'$BackupLogPath' WITH NORECOVERY"
    Write-log "Start DB log Restore operation on database $DatabaseName in $SqlServerInstanceFullName instance. Destination path is $BackupLogPath"
    Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $Query -QueryTimeout 21600
    cd c:  ;cd $ScriptRootPath
}
#Add sql login for domain account.
Function Add-SqlServerLogin
{
    Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID, #SQL instance id.
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME, #Computername of server.
        [Parameter(Mandatory=$true)] 
        $DomainLogins, #Array of domain accounts in domain\username format.
        [Parameter(Mandatory=$false)]
        [switch]$AddSysAdminRole #Switch which allows to grant created logins sysadmin role.
    )
    #Initialize full server instance name.
    $SqlServerInstanceFullName=$ComputerName+"\"+$SqlInstanceID
    #Logins must be in domain\username format
    #Create loging for each user.
    Foreach ($SqlLogin in $DomainLogins)
    {    
        Write-log "Create SQL login for $SqlLogin"
    
        $UserCreateQuery="
            USE [master]
            GO
            CREATE LOGIN [$SqlLogin] FROM WINDOWS WITH DEFAULT_DATABASE=[master], DEFAULT_LANGUAGE=[us_english]
            GO
        "
        Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $UserCreateQuery
        #If $AddSysAdminRole sitch is included, grant sysadmin role to login.
        if ($AddSysAdminRole -eq $True)
        {
            Write-log "Try to add sysadmin role for $SqlLogin"
            $AddSysAdminRoleQuery="
                USE [master]
                GO                
                ALTER SERVER ROLE [sysadmin] ADD MEMBER [$SqlLogin]
                GO
            "
            Invoke-Sqlcmd -ServerInstance $SqlServerInstanceFullName -Query $AddSysAdminRoleQuery
        }
    }
}
#Install failover clustering and MPIO features, start Test-cluster and creating cluster.
Function Create-MigrationCluster
{
    Param
    (
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME, #Server name
        [Parameter(Mandatory=$True)]
        [string]$ClusterNameObject, #CNO object name for cluster.
        [Parameter(Mandatory=$True)]
        [string]$ClusterIPAddress #Ip address for cluster.
    )

    #Create SessionObject
    $Session=New-PSSession -ComputerName $ComputerName 
    Invoke-Command -Session $Session -OutVariable Message -ScriptBlock {
        #Check for existence of features. Setup if not installed.
        Write-Output "Check for installation state of Failover clustering and MPIO features.`n"
        $FailoverCluterRoleCheck=Get-WindowsFeature failover-clustering
        $MpioRoleCheck=Get-WindowsFeature Multipath-IO
        if ($FailoverCluterRoleCheck.InstallState -ne 'Installed') {Write-Output "Installation of Failover Clustering feature... `n";Install-WindowsFeature failover-clustering -IncludeManagementTools}
        Else {Write-Output "Failover clustering test passed. `n"}
        if ($MpioRoleCheck.InstallState -ne 'Installed') {Write-Output "Installation of MPIO feature... `n" ;Install-WindowsFeature Multipath-IO -IncludeManagementTools}
        Else {Write-Output "MPIO test passed. `n"}       
    }
    Write-Log $Message
    #Test Cluster
    Write-Log "Start cluster validation report. You can find result in C:\Windows\Cluster\Reports folder."
    Test-Cluster -Node $ComputerName
    #Pause because there is no logic for automatic test result processing.
    pause
    #Create Cluster
    Write-log "Creating cluster $ClusterNameObject on $ComputerName with static ip $ClusterIPAddress"
    New-Cluster -Name $ClusterNameObject -Node $ComputerName -StaticAddress $ClusterIPAddress -NoStorage

}
#Enable SQL AlwaysOn in SQL instance configuration.
Function Add-SQLAlwaysOn
{
   Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID,
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME
    )
    #Initialize root path.   
    $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
    #Initialize SQL Instance Name and PSPath variables.
    $SqlServerFullInstanceName=$ComputerName+"\"+$SqlInstanceID
    $SqlServerFullInstancePath="SQLSERVER:\sql\$SqlServerFullInstanceName"    
    Import-Module -Name SQLPS -DisableNameChecking
    $SqlInstanceCheck=Check-SQLInstance -SQLInstanceID $SqlInstanceID
    if ($SqlInstanceCheck){Write-Log "SQL instance $SqlInstanceID exist."}
    Else{Write-Log "Can't find SQL instance ID enry in WMI. function will stop";return}
    #Get current state of Always on.
    $SQLAlwaysOnStatusCheck=get-item $SqlServerFullInstancePath | Select-Object IsHadrEnabled
    #If AlwaysOn not enabled, then enable it. 
    #If AlwaysOn enabled, then then script just notifying about it.   
    if ($SQLAlwaysOnStatusCheck.IsHadrEnabled -ne $True) 
    {
        $SQLAlwaysOnStatusCheck
        Write-log 'SQL AlwaysOn is not enabled. Trying to enable it...'
        Enable-SqlAlwaysOn -Path $SqlServerFullInstancePath
        Remove-Variable 'SQLAlwaysOnStatusCheck'
        #Get current state of AlwaysOn.
        $SQLAlwaysOnStatusCheck=get-item $SqlServerFullInstancePath | Select-Object IsHadrEnabled
        if ($SQLAlwaysOnStatusCheck.IsHadrEnabled -eq $True){Write-log 'SQL AlwaysOn is enabled.'}
        else {$SQLAlwaysOnStatusCheck;Write-log 'Looks like status of AlwaysOn not changed. Try to check status of Always on in SQL configuration manager. Also try to check your permissions (UAC).'}
    }
    #Message if Always on already enabled.
    elseif ($SQLAlwaysOnStatusCheck.IsHadrEnabled -eq $True){Write-log 'SQL AlwaysOn is already enabled'}
    #Message for unexpected results of check.
    Else {Write-log 'Something goes wrong. Cannot return status of AlwaysOn. Try to check your computer and instance names and permissions (UAC)'}
    cd c:;cd $ScriptRootPath
}
#Detach database from specified sql cluster instance.
Function Detach-SqlClusterDatabase
{
    Param
        (            
            [Parameter(Mandatory=$True)] 
            [string]$SqlInstanceID,            
            [Parameter(Mandatory=$True)] 
            [string]$VCODnsName,     
            [Parameter(Mandatory=$True)]
            $SqlDatabase            
        )
        #Initialize root path.  
        $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
        #Initialize full instance name.
        $SqlServerFullInstanceName=$VCODnsName+"\"+$SqlInstanceID
        Import-Module -Name SQLPS -DisableNameChecking
        #Initialize SQL instance object
        Write-Log 'Check existence of sql database'
        $SqlServer=New-Object "Microsoft.SqlServer.Management.Smo.Server" $SqlServerFullInstanceName
        $DatabaseCheck=$SqlServer.Databases|where name -eq $SqlDatabase
        #If database found then script will detach it.
        If($DatabaseCheck)
        {
            Write-log "Database $SqlDatabase is found.  Trying to Detach $SqlDatabase from $SqlServerFullInstanceName..."        
            $SqlServer.DetachDatabase($SqlDatabase, $false, $false)
            $SqlServer.Databases.Refresh()
            if(($SqlServer.Databases|where name -EQ $SqlDatabase)){Write-log "Database $SqlDatabase has not been detached." -Level Error}
            elseif(!($SqlServer.Databases|where name -EQ $SqlDatabase)){Write-log "Database $SqlDatabase has been detached." }
        }
        #Else can't find database
        else 
        {
            Write-Log "Can't find $SqlDatabase on server $SqlServerFullInstanceName."
        }
        
        cd c:  ;cd $ScriptRootPath      
}
#Function Adds sql server endpoint to sql instance and call function Add-SqlServerEndpointPermission  give connect permission for specified service account.
Function Create-SqlServerEndpoint
{
    Param
        (
            [Parameter(Mandatory=$True)] 
            [string]$SqlInstanceID, #InstanceID of sql installation.
            [Parameter(Mandatory=$True)] 
            [string]$SQLServiceAccount, #Domain account in Domain\Username format.
            [Parameter(Mandatory=$False)] 
            [string]$ComputerName=$env:COMPUTERNAME #Server Name.
        )   
            #Initialize vatiables and import SQLPS module.
            $ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
            $SqlServerFullInstanceName=$ComputerName+"\"+$SqlInstanceID
            $SqlServerFullInstancePath="SQLSERVER:\sql\$SqlServerFullInstanceName"
            $EndpointName="MainEndpoint"     
            Import-Module -Name SQLPS -DisableNameChecking
            #Create endpoing.
            Write-Log "Creating $EndpointName for $SqlServerFullInstancePath "
            New-SqlHADREndpoint -Path "$SqlServerFullInstancePath" -Name $EndpointName
            #Start endpoint.
            Write-Log "Trying to Start endpoint for $SqlServerFullInstancePath"
            Set-SqlHADREndpoint -Path ($SqlServerFullInstancePath+"\Endpoints\"+($EndpointName)) -State Started
            #Call function Add-SqlServerEndpointPermission to add connect permissions to endpoint for specified account.
            Add-SqlServerEndpointPermission -SqlInstanceID $SqlInstanceID -SQLServiceAccount $SQLServiceAccount -EndpointName $EndpointName -ComputerName $ComputerName     
            cd c:  ;cd $ScriptRootPath
}
#Function add connect permissions to specified Endpoint object for SqlServiceAccount.
Function Add-SqlServerEndpointPermission
{
Param
    (
        [Parameter(Mandatory=$True)] 
        [string]$SqlInstanceID, #InstanceID of sql instance.
        [Parameter(Mandatory=$True)] 
        [string]$SQLServiceAccount, #Domain account in Domain\Username format.
        [Parameter(Mandatory=$False)] 
        [string]$ComputerName=$env:COMPUTERNAME, #Server name.
        [Parameter(Mandatory=$True)]
        $EndpointName #Endpoint name.

    )   
        #Initialize variables.
        $SqlServerFullInstanceName=$ComputerName+"\"+$SqlInstanceID
        #Query to add connect permission to endpoint.
        $Query="GRANT CONNECT ON ENDPOINT::$EndpointName TO [$SQLServiceAccount];"
        #Check permission existence.
        $CheckQuery="select 'true'
        FROM sys.server_permissions p INNER JOIN sys.endpoints e ON p.major_id = e.endpoint_id
        INNER JOIN sys.server_principals s ON p.grantee_principal_id = s.principal_id
        WHERE p.class_desc = 'endpoint'  and s.name = '$SQLServiceAccount' "
        #Start add connect permission query.
        "Adding access for login $SQLServiceAccount to $EndpointName endpoint."
        Invoke-Sqlcmd -Query $Query -ServerInstance $SqlServerFullInstanceName  -Verbose
        #Check existence of added permissions.
        $CheckPermssion=Invoke-Sqlcmd -Query $CheckQuery -ServerInstance $SqlServerFullInstanceName  -Verbose
        if (!$CheckPermssion) 
        {
            Write-Log "Permissions is not added, looks like there is no login for $SQLServiceAccount"
            Write-Log "Trying to add login for $SQLServiceAccount..."
            #Add login for $SQLServiceAccount.
            Add-SqlServerLogin -SqlInstanceID $SqlInstanceID -ComputerName $ComputerName -DomainLogins $SQLServiceAccount
            Write-Log "Script will retry to add permission"
            Write-Log "Adding login $SQLServiceAccount access to $EndpointName endpoint."
            #Try add connect permission again.
            Invoke-Sqlcmd -Query $Query -ServerInstance $SqlServerFullInstanceName|Out-Null
        }
}
# Vatiable for root path detection.
Write-Warning  '
Don''t forget to set exection policy mode to remotesigned and run this module with administrative privileges.'
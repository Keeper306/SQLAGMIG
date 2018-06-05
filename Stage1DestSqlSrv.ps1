# cd \\axpost\VM\GoldImages\SQLAGMig
$ScriptRootPath=(Get-Item -Path ".\" -Verbose).FullName
$Config=Import-LocalizedData -FileName config.PSD1
#Import-module with migration functions.
Import-Module .\SqlMigration.psm1 -Force
#Install Sql Standalone instance on destination server.
Function Install-SqlDestStandaloneInstance
{
    #Get properties for sql installation from config file
    $SQLSourceFiles=$Config.SqlStanaloneInstallation.MediaFilesPath
    $SqlInstanceID=$Config.SqlStanaloneInstallation.DestInstanceID
    $SQLServiceAccount=$Config.SqlStanaloneInstallation.DestServiceAccountName
    $SqlInstancePath=$Config.SqlStanaloneInstallation.DestInstancePath
    $SqlServername=$Config.DestinationSqlServer.Name
   
    Write-log "Checking name of Server."
     #Compare $SqlServername from config file with local server name.
     #If condition is true, then script will start.
    If($SqlServername -eq "$env:COMPUTERNAME")
    {
        Write-log "Server name check passed."
        $SQLSvcPassword= Read-Host -assecurestring "Please enter password for service account $SQLServiceAccount"
        $SqlSaPassword=Read-Host -assecurestring "Please enter password for SA account"
        Write-log "Call Install-SQLStandaloneInstance function..."
        #Call function from SqlMigration.psm1, to install SQL standalone instance.
        Install-SQLStandaloneInstance -SqlSourceFilesPath $SQLSourceFiles -SqlInstanceID $SqlInstanceID -SqlServiceAccountName $SQLServiceAccount -SqlSvcPassword $SQLSvcPassword -SqlSAPassword $SqlSaPassword -SqlInstancePath $SqlInstancePath
    }
    Else 
    {
        Write-log "Name of the server from config file ($SqlServername) does not math with name of this computer ($env:COMPUTERNAME)"
    }
}
if($Prod){Install-SqlDestStandaloneInstance}

#Create cluster on destination server.
Function Create-DestinationCluster
{
    #Get properties for sql installation from config file
    $DestinationSqlServer=$Config.DestinationSqlServer.Name
    $DestinationSqlClusterName=$Config.DestinationSqlCluster.CNO
    $DestinationSqlClusterIP=$config.DestinationSqlCluster.IPAddress
    #Call function from SqlMigration module to create cluster on destination node.
    Create-MigrationCluster -ComputerName $DestinationSqlServer -ClusterNameObject $DestinationSqlClusterName -ClusterIpAddress $DestinationSqlClusterIP
}
if($Prod){Create-DestinationCluster}
#Add witness share to cluster configuration
Function Set-DestinationClusterWitness
{
    #Get variables 
    $DestinationClusterName=$Config.DestinationSqlCluster.CNO
    $DestinationClusterWitnessShare=$Config.DestinationSqlCluster.WitnessShare
    #Test existence of share.
    $ShareCheck=Test-Path $DestinationClusterWitnessShare
    Write-log "Run Set-DestinationClusterWitness function"
    #Add witness resource to destion cluster if share exist
    if ($ShareCheck -eq $true)
    {
        Write-log "Witness share exist. Trying to add it in cluster"
        Set-ClusterQuorum -Cluster $DestinationClusterName -NodeAndFileShareMajority $DestinationClusterWitnessShare
    }
    #Write 
    elseif ($ShareCheck -eq $false) {Write-log "Can't reach smb share from config file. Try to check name of the share"}
}
if($Prod){Set-DestinationClusterWitness}
#Enable AlwaysON on destination instance.
Function Enable-DestSQLServerAlwaysOn
{
    #Get properties for sql installation from config file
    $DestSqlServerName=$Config.DestinationSqlServer.Name
    $DestSqlServerInstanceID=$Config.SqlStanaloneInstallation.DestInstanceID
    #Call function from SqlMigration module to enable sql alwaysOn on destination standalone instance.
    Add-SQLAlwaysOn -SqlInstanceID $DestSqlServerInstanceID -ComputerName $DestSqlServerName
}
if($Prod){Enable-DestSQLServerAlwaysOn}
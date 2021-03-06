#region Initialize

function Initialize
{
    # hosts location
    # Enum for Ensure
    Add-Type -TypeDefinition @"
        public enum EnsureType
        {
            Present,
            Absent
        }
"@ -ErrorAction SilentlyContinue; 
}

. Initialize;

#endregion

#region Message Definition

Data VerboseMessages {
    ConvertFrom-StringData -StringData @"
        CheckKBEntry = Check KB entry is exists.
        CompleteInstallation = Installation complete for KB : {0}.
        CompleteUninstallation = Uninstallation complete for KB : {0}.
        KBEnteryExists = Found a KB entry {0}.
        KBEnteryNotExists = Did not find a KB entry {0}.
        StartInstallation = Start Installation with process '{0}', arguments '{1}'
        VerifyExitCode = Verifying Exit Code.
        VerifyExitCode0 = ExitCode : {0}. Installation success. Installation completed successfully.
        VerifyExitCode1641 = ExitCode : {0}. Installation success. A restart is required to complete the installation. This message indicates success.
        VerifyExitCode3010 = ExitCode : {0}. Installation success. A restart is required to complete the installation. This message indicates success.
"@
}

Data DebugMessages {
    ConvertFrom-StringData -StringData @"
"@
}

Data ErrorMessages {
    ConvertFrom-StringData -StringData @"
        InstallerNotFound = Could not found Installer file {0}.
        VerifyExitCode1602 = Installation failed. The user canceled installation. ExitCode : {0}.
        VerifyExitCode1603 = Installation failed. A fatal error occurred during installation. ExitCode : {0}
        VerifyExitCode5100 = Installation failed. The user's computer does not meet system requirements. ExitCode : {0}
        VerifyExitCode16389 = Installation failed. Installation prevented as previous installation is not completed until reboot. Please redo after reboot. ExitCode : {0}
        VerifyExitCodeOther = Unexpected exit code detected. ExitCode : {0}.
        VerifyInstallationKBFound = Still KB found from Windows Hotfix list. Uninstallation seeems failed. KB : {0}
        VerifyInstallationKBNotFound = Could not find KB from Windows Hotfix list. KB : {0}
"@
}

#endregion

#region *-TargetResource

function Get-TargetResource
{
    [OutputType([System.Collections.Hashtable])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$KB,

        [parameter(Mandatory = $true)]
        [System.String]$Ensure,

        [parameter(Mandatory = $false)]
        [System.String]$InstallerPath = "",

        [parameter(Mandatory = $false)]
        [System.Boolean]$NoRestart = $true,

        [parameter(Mandatory = $false)]
        [System.String]$LogPath = "$env:windir\Temp"
    )

    $Configuration = @{
        KB = $KB
        InstallerPath = $InstallerPath
        NoRestart = $NoRestart
        LogPath = $LogPath
    };

    Write-Verbose $VerboseMessages.CheckKBEntry;

    try
    {
        if ((IsHotfixEntryExists -KB $KB))
        {
            Write-Verbose ($VerboseMessages.KBEnteryExists -f $KB);
            $Configuration.Ensure = [EnsureType]::Present;
        }
        else
        {
            Write-Verbose ($VerboseMessages.KBEnteryNotExists -f $KB);
            $Configuration.Ensure = [EnsureType]::Absent;
        }
    }
    catch
    {
        Write-Error $_;
    }

    return $Configuration;
}


function Set-TargetResource
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$KB,

        [parameter(Mandatory = $true)]
        [System.String]$Ensure,

        [parameter(Mandatory = $false)]
        [System.String]$InstallerPath = "",

        [parameter(Mandatory = $false)]
        [System.Boolean]$NoRestart = $true,

        [parameter(Mandatory = $false)]
        [System.String]$LogPath = "$env:windir\Temp"
    )

    try
    {
        if ($Ensure -eq [EnsureType]::Absent.ToString())
        {
            # Absent
            $exitCode = UninstallDotNet -KB $KB -LogPath $LogPath;
        }
        elseif ($Ensure -eq [EnsureType]::Present.ToString())
        {
            # Present
            # There is a bug which both "OfflineInstaller.exe /q" and "OfflineInstaller.exe /passive" won't work with SYSTEM user.
            # Therefore need to extract OfflineInstaller, then call setup.exe inside.
            # https://social.technet.microsoft.com/Forums/ja-JP/4808233e-1410-4305-a8d1-0e88f3a6fdc8/net-451-install-only-works-when-running-on-a-ui-session?forum=configmanagerapps
            # This bug will never hapen on local, but you'll see with Remote Session.
            $extractPath = ExtractInstaller -InstallerPath $InstallerPath;
            $exitCode = InstallDotNet -ExtractPath $extractPath -LogPath $LogPath;
        }

        # verify result
        VerifyExitCode -ExitCode $exitCode;
        VerifyInstallation -KB $KB -Ensure $Ensure;

        # restart flag for DSC
        if (-not $NoRestart)
        {
            # Restart require after installation
            $global:DSCMachineStatus = 1
        }
    }
    catch
    {
        throw $_
    }    
}


function Test-TargetResource
{
    [OutputType([System.Boolean])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$KB,

        [parameter(Mandatory = $true)]
        [System.String]$Ensure,

        [parameter(Mandatory = $false)]
        [System.String]$InstallerPath = "",

        [parameter(Mandatory = $false)]
        [System.Boolean]$NoRestart = $true,

        [parameter(Mandatory = $false)]
        [System.String]$LogPath = "$env:windir\Temp"
    )

    # skip for NoRestart and LogDirectory. As these parameter doesn't affect to status check
    return (Get-TargetResource -KB $KB -Ensure $Ensure -InstallerPath $InstallerPath).Ensure -eq $Ensure;
}

#endregion

#region Installer Function

function UninstallDotNet
{
    [OutputType([int32])]
    [CmdletBinding()]
    param
    (
        [string]$KB,
        [string]$LogPath
    )

    $path = "$env:windir\System32\wusa.exe";
    $uninstallKb = ValidateKb -KB $KB;
    $arguments = "/uninstall /kb:$uninstallKb /quiet /norestart /log:$LogPath"

    # Validate installer/uninstaller path.
    ValidateInstallerPath -Path $path;

    # execute
    $exitCode = StartProcess -FilePath $path -Arguments $arguments;
    return $exitCode;
}

function InstallDotNet
{
    [OutputType([int32])]
    [CmdletBinding()]
    param
    (
        [string]$ExtractPath,
        [string]$LogPath
    )

    $setupExe = Join-Path $ExtractPath "setup.exe"
    $setupArguments = "/q /x86 /x64 /redist /norestart /log $LogPath"

    # Validate installer/uninstaller path.
    ValidateInstallerPath -Path $setupExe;

    # install
    $exitCode = StartProcess -FilePath $setupExe -Arguments $setupArguments;

    # Remove extract files
    Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue;

    return $exitCode
}

function ExtractInstaller
{
    [OutputType([string])]
    [CmdletBinding()]
    param
    (
        [string]$InstallerPath
    )

    $guid = [Guid]::NewGuid().ToString();
    $extractPath = Join-Path "$env:windir\Temp" "$guid"
    $extractArguments = "/q /x:$extractPath"

    # Validate installer/uninstaller path.
    ValidateInstallerPath -Path $InstallerPath;

    # extract
    $extractExitCode = StartProcess -FilePath $InstallerPath -Arguments $extractArguments;

    # verify result
    VerifyExitCode -ExitCode $extractExitCode;

    return $extractPath;
}

#endregion

#region Helper Function

function IsHotfixEntryExists
{
    [OutputType([System.Boolean])]
    [CmdletBinding()]
    param
    (
        [string]$KB
    )
    return (Get-HotFix | where HotFixId -eq $KB | measure).Count -ne 0;
}

function ValidateInstallerPath
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [string]$Path
    )
    
    if (-not (Test-Path -Path $Path))
    {
        throw New-Object System.IO.FileNotFoundException ($ErrorMessages.InstallerNotFound -f $Path);
    }
}


function ValidateKb
{
    [OutputType([int])]
    [CmdletBinding()]
    param
    (
        [string]$KB
    )

    if ($KB.StartsWith("KB"))
    {
        $newKb =$KB.Replace("KB", "")
    }
    else
    {
        $newKb = $KB;
    }
    return $newKb
}

function StartProcess
{
    [OutputType([int])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$FilePath,

        [parameter(Mandatory = $true)]
        [System.String]$Arguments
    )

    Write-Verbose ($VerboseMessages.StartInstallation -f $FilePath, $Arguments);
    try
    {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.CreateNoWindow = $true 
        $psi.UseShellExecute = $false 
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.FileName = $FilePath
        $psi.Arguments = $Arguments

        $process = New-Object System.Diagnostics.Process 
        $process.StartInfo = $psi
        $process.Start() > $null
        $output = $process.StandardOutput.ReadToEnd().Trim();
        $process.WaitForExit(); 
        
        Write-Debug $output;

        return $process.ExitCode
    }
    catch
    {
        $outputError = $process.StandardError.ReadToEnd()
        throw $_ + $outputError
    }
    finally
    {
        if ($null -ne $psi){ $psi = $null}
        if ($null -ne $process){ $process.Dispose() }
    }
}

function VerifyExitCode
{
    [OutputType([void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    # List of ExitCode and status  from MSDN
    # https://msdn.microsoft.com/en-us/library/ee942965.aspx#return_codes
    Write-Verbose $VerboseMessages.VerifyExitCode
    switch ($exitCode)
    {
        0
        {
            Write-Verbose ($VerboseMessages.VerifyExitCode0 -f $ExitCode);
        }
        1641
        {
            Write-Verbose ($VerboseMessages.VerifyExitCode1641 -f $ExitCode);
        }
        3010
        {
            Write-Verbose ($VerboseMessages.VerifyExitCode3010 -f $ExitCode);
        }
        1602 
        {
            $message = $ErrorMessages.VerifyExitCode1602 -f $ExitCode;
            Write-Verbose $message;
            throw New-Object System.OperationCanceledException ($message);
        }
        1603
        {
            $message = $ErrorMessages.VerifyExitCode1603 -f $ExitCode;
            Write-Verbose $message;
            throw New-Object System.ArgumentException ($message);
        }
        5100
        {
            $message = $ErrorMessages.VerifyExitCode5100 -f $ExitCode;
            Write-Verbose $message;
            throw New-Object System.InvalidOperationException ($message);
        }
        16389
        {
            $message = $ErrorMessages.VerifyExitCode16389 -f $ExitCode;
            Write-Verbose $message;
            throw New-Object System.InvalidOperationException ($message);
        }
        default
        {
            $message = $ErrorMessages.VerifyExitCodeOther -f $ExitCode;
            Write-Verbose $message;
            throw New-Object System.ArgumentException ($message);
        }
    }
}

function VerifyInstallation
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$KB,

        [parameter(Mandatory = $true)]
        [System.String]$Ensure
    )

    $result = (Get-HotFix | where HotFixId -eq $KB | measure).Count
    if ($Ensure -eq [EnsureType]::Absent.ToString())
    {
        # Absent
        if ($result -ne 0) # should be 0 for success uninstallation
        {
            throw New-Object System.ArgumentException ($ErrorMessages.VerifyInstallationKBFound -f $KB);
        }
        Write-Verbose ($VerboseMessages.CompleteUninstallation -f $KB);
    }
    elseif ($Ensure -eq [EnsureType]::Present.ToString())
    {
        #Present
        if ($result -eq 0) # should be 1 for success installation
        {
            throw New-Object System.NullReferenceException ($ErrorMessages.VerifyInstallationKBNotFound -f $KB);
        }
        Write-Verbose ($VerboseMessages.CompleteInstallation -f $KB);
    }
}

#endregion

Export-ModuleMember -Function *-TargetResource

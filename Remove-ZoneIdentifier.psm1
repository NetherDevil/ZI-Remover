<#
    .SYNOPSIS
    Removes the Zone.Identifier alternate data stream from files.

    .DESCRIPTION
    This function recursively scans a specified path (file or directory)
    and removes the 'Zone.Identifier' alternate data stream from files.
    This stream is commonly added by web browsers or network transfers
    to mark files as originating from an untrusted source.

    .PARAMETER Path
    Specifies the path to the file or directory to process.
    This can be a relative or absolute path.

    .PARAMETER Force
    When specified, the function will temporarily clear the 'ReadOnly'
    attribute from files if necessary to strip the stream, and then
    revert the attribute afterwards.

    .PARAMETER NoRecurse
    When specified, the function will only process the files in the
    specified directory and will not recurse into subdirectories.

    .PARAMETER FullyQualifiedPath
    Internal use only. Indicates that the provided Path is already
    fully qualified. Do not use this parameter manually.

    .PARAMETER SuppressSuccess
    When specified, suppresses the green success messages for stripped files.
    Error and warning messages will still be displayed.

   .PARAMETER CommonParameters
   This cmdlet supports the common parameters: -Debug, -ErrorAction, 
   -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, 
   -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and 
   -WarningVariable. For more information, see about_CommonParameters 
   (https://go.microsoft.com/fwlink/?LinkID=113216).

    .EXAMPLE
    Remove-ZoneIdentifier -Path 'C:\Directory'

    .EXAMPLE
    Remove-ZoneIdentifier -Path 'C:\Directory' -WhatIf

    .EXAMPLE
    Remove-ZoneIdentifier -Path 'C:\Directory' -NoRecurse

    .EXAMPLE
    Remove-ZoneIdentifier -Path 'C:\ReadOnlyFile.exe' -Force

    .NOTES
    Author: NetherDevil
    Version: 0.1
    License: MIT
#>
function Remove-ZoneIdentifier {
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
	param ([Parameter(Mandatory=$true, Position=0)][string] $Path, [switch] $Force, [switch] $NoRecurse, [switch] $FullyQualifiedPath, [switch] $SuppressSuccess);
	function InternalGetDisplayName {
		param([string] $FullName);
		if ($FullName.Length -gt 80) {
			return "..." + $FullName.SubString($FullName.Length - 77);
		}
		return $FullName;
	}
	function InternalGetErrorDetail {
		param ([System.Exception] $Exception);
		if ($Exception -is [System.Management.Automation.MethodException]) {
			try {
				return InternalGetErrorDetail -Exception:$Exception.InnerException; # MethodException is often a wrapper; we need to dive deeper.
			}
			catch { } # but if it fails, return the message directly (below)
		}
		return $Exception.Message;
	}
	function InternalHandleFile {
		param([System.IO.FileSystemInfo] $File, [bool] $Force);
		$displayName = InternalGetDisplayName -FullName:$File.FullName;
		if ([System.IO.File]::Exists($File.FullName + ":Zone.Identifier") -and $PSCmdlet.ShouldProcess($displayName, "Strip Zone.Identifier")) {
			$attribOverride = $false;
			$attrib = $File.Attributes;
			try {
				if ($Force -and $File.Attributes.HasFlag([System.IO.FileAttributes]::ReadOnly)) { # read-only attribute will stop us from stripping
					Write-Warning -Message "Temporarily clearing attributes from $displayName"
					$attribOverride = $true; # set this flag first, before altering the attributes
					$File.Attributes = $attrib -band (-bnot [System.IO.FileAttributes]::ReadOnly);
				}
				Write-Verbose "Stripping Zone.Identifier from $displayName"
				[System.IO.File]::Delete($File.FullName + ":Zone.Identifier")
				if (-not $SuppressSuccess) { Write-Host -ForegroundColor Green "Stripped Zone.Identifier from $displayName" } # we are sticking to write-host, as we want a colored output. but we offer an option to turn it off
			}
			catch {
				$detail = InternalGetErrorDetail -Exception:$_.Exception
				Write-Error -Message "Failed to strip Zone.Identifier from ${displayName}: $detail";
			}
			finally {
				if ($attribOverride) {
					try {
						Write-Verbose "Reverting attributes for $displayName"
						$File.Attributes = $attrib;
					}
					catch {
						$detail = InternalGetErrorDetail -Exception:$_.Exception
						Write-Warning -Message "Failed to revert attributes ($attrib) for ${displayName}: $detail";
					}
				}
			}
		}
	}
	if (-not $FullyQualifiedPath) {
		$Path = [System.IO.Path]::Combine((Get-Location), $Path); # Use powershell's internal location to alter the path to get fully-qualified ones (ps core quirks)
	}
	$fileInfo = [System.IO.FileInfo]::new($Path);
	if ($fileInfo.Exists) { # a file is passed
		InternalHandleFile -File:$fileInfo -Force:$Force
		return;
	}
	$pathInfo = [System.IO.DirectoryInfo]::new($Path);
	if (-not $pathInfo.Exists) { 
		$displayName = InternalGetDisplayName -FullName:$Path;
		Write-Error -Message "Could not find ${displayName}.";
		return;
	}
	$items = $null;
	try {
		$items = $pathInfo.GetFileSystemInfos();
	}
	catch {
		$displayName = InternalGetDisplayName -FullName:$Path;
		$detail = InternalGetErrorDetail -Exception:$_.Exception
		Write-Warning -Message "Could not list files in ${displayName}: $detail";
		return;
	}
	foreach ($item in $items) { # items are non-null here
		if ($item.Attributes.HasFlag([System.IO.FileAttributes]::Directory)) {
			$displayName = InternalGetDisplayName -FullName:$item.FullName;
			if (-not $NoRecurse) {
				Write-Verbose "Recurse: Enter directory $displayName"
				Remove-ZoneIdentifier -Path:$item.FullName -Force:$Force -FullyQualifiedPath; # we recurse here, so we recurse, no NoRecurse; we always pass fully-qualified path internally.
				Write-Verbose "Recurse: Leave directory $displayName"
			}
		}
		else {
			InternalHandleFile -File:$item -Force:$Force
		}
	}
}

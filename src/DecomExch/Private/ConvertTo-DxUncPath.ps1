function ConvertTo-DxUncPath {
    <#
    .SYNOPSIS
        Zet een lokaal pad (C:\map) om naar een administratief UNC-pad (\\server\C$\map).
        Zonder ComputerName, of voor de lokale computer, blijft het pad ongewijzigd.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ComputerName
    )

    if (-not $ComputerName -or $ComputerName -eq '.' -or $ComputerName -eq 'localhost' -or
        $ComputerName -eq $env:COMPUTERNAME -or $Path -like '\\*') {
        return $Path
    }

    if ($Path -notmatch '^(?<drive>[A-Za-z]):\\?(?<rest>.*)$') {
        throw "Pad '$Path' is geen lokaal pad met stationsletter."
    }

    $rest = $Matches['rest'].TrimEnd('\')
    $unc = '\\{0}\{1}$' -f $ComputerName, $Matches['drive'].ToUpper()
    if ($rest) { $unc = '{0}\{1}' -f $unc, $rest }
    $unc
}

function Set-VDUplinkState {
#Requires -Modules @{"ModuleName" = "VMware.VimAutomation.Core"; "ModuleVersion" = "11.0.0.10336080"}
    <#
    .SYNOPSIS
        Set the state of an uplink on all port groups on a vDS to active, standby or unused.

    .DESCRIPTION
        Set the state of an uplink on all port groups on a vDS to active, standby or unused.

    .PARAMETER vdSwitch
        Distributed switch object as returned by Get-VDSwitch

    .PARAMETER uplinkName
        Name of uplink to set configuration on.

    .PARAMETER uplinkState
        State to set uplink to, active, standby or unused.

    .INPUTS
        VMware.VimAutomation.Vds.Impl.VDObjectImpl. Virtual distributed switch object as returned by Get-VDSwitch.

    .OUTPUTS
        None.

    .EXAMPLE
        Get-VDSwitch | Set-VDUplinkState -uplinkName dvUplink2 -uplinkState active -Confirm:$false

        Set the state of dvUplink2 to active on all portgroups on all distributed switches. Suppress confirmation prompt.

    .EXAMPLE
        Set-VDUplinkState -vdSwitch $vdSwitch -uplinkName dvUplink2 -uplinkState unused -Verbose

        Set the state of dvUplink2 to unused on $vdSwitch. Will prompt for confirmation on each port group. Verbose output enabled.

    .LINK


    .NOTES
        01           Alistair McNair          Initial version.

    #>

    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="High")]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [VMware.VimAutomation.Vds.Impl.VDObjectImpl]$vdSwitch,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$uplinkName,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [ValidateSet("active","unused","standby")]
        [string]$uplinkState
    )

    begin {

        Write-Verbose ("Function start.")

    } # begin


    process {

        Write-Verbose ("Processing VDS " + $vdSwitch.name)


        ## Check that specified uplink exists on this switch
        if ($vdSwitch.ExtensionData.Config.UplinkPortPolicy.UplinkPortName -contains $uplinkName) {
            Write-Verbose ("Uplink was found on this VD switch.")
        } # if
        else {
            throw ("Invalid uplink specified.")
        } # else


        ## Get all port groups for this switch
        try {
            $vdPorts = Get-VDPortgroup -VDSwitch $vdSwitch -ErrorAction Stop | Where-Object {!$_.IsUplink}
            Write-Verbose ("Got VD ports for this switch.")
        } # try
        catch {
            Write-Debug ("Failed to get VD ports for this switch")
            throw ("Failed to get VD ports for this switch")
        } # catch


        ## Check we have at least 1 port group to work with
        if ($vdPorts.count -lt 1) {

            throw ("No port groups found on this VD switch.")

        } # if
        else {

            Write-Verbose ("Processing " + $vdPorts.count + " port groups.")

            ## Iterate through each port group and query uplink status
            :nextPort foreach ($vdPort in $vdPorts) {


                Write-Verbose ("Processing port group " + $vdPort.name)


                try {
                    $teamingPolicy = Get-VDPortgroup -VDSwitch $vdSwitch -Name $vdPort.name -ErrorAction Stop | Get-VDUplinkTeamingPolicy -ErrorAction Stop
                    Write-Verbose ("Got teaming policy for " + $vdPort.name)
                } # try
                catch {
                    Write-Debug ("Failed to get teaming policy")
                    throw ("Failed to get teaming policy for VD port " + $vdPort.name + ". " + $_.exception.message)
                } # catch


                ## Set active, standby and unused collections
                $ActiveUplinkPorts = $teamingPolicy.ActiveUplinkPort
                $StandbyUplinkPorts = $teamingPolicy.StandbyUplinkPort
                $UnusedUplinkPorts = $teamingPolicy.UnusedUplinkPort


                ## Switch through and update if necessary
                switch ($teamingPolicy) {

                    {$_.ActiveUplinkPort -contains $uplinkName} {
                        Write-Verbose ("Uplink " + $uplinkName + " is active on port group " + $vdPort.name)

                        ## Check if this is the desired configuration
                        if ($uplinkState -eq "active") {

                            Write-Verbose ("Uplink is already set as active, no further action is necessary.")
                            Continue nextPort
                        } # if
                        else {

                            Write-Verbose ("Uplink is set as active and should be " + $uplinkState + ". Configuration will be changed.")

                            ## Remove this uplink from the teaming config .ActiveUplinkPort collection
                            $activeUplinkPorts = $activeUplinkPorts | Where-Object {$_ -ne $uplinkName}

                        } # else

                    } # active

                    {$_.StandbyUplinkPort -contains $uplinkName} {
                        Write-Verbose ("Uplink " + $uplinkName + " is standby on port group " + $vdPort.name)

                        ## Check if this is the desired configuration
                        if ($uplinkState -eq "standby") {

                            Write-Verbose ("Uplink is already set as standby, no further action is necessary.")
                            Continue nextPort
                        } # if
                        else {

                            Write-Verbose ("Uplink is set as standby and should be " + $uplinkState + ". Configuration will be changed.")

                            ## Remove this uplink from the teaming config .standbyUplinkPort collection
                            $StandbyUplinkPorts = $StandbyUplinkPorts | Where-Object {$_ -ne $uplinkName}

                        } # else

                    } # standby

                    {$_.UnusedUplinkPort -contains $uplinkName} {
                        Write-Verbose ("Uplink " + $uplinkName + " is unused on port group " + $vdPort.name)

                        ## Check if this is the desired configuration
                        if ($uplinkState -eq "unused") {

                            Write-Verbose ("Uplink is already set as unused, no further action is necessary.")
                            Continue nextPort
                        } # if
                        else {

                            Write-Verbose ("Uplink is set as unused and should be " + $uplinkState + ". Configuration will be changed.")

                            ## Remove this uplink from the teaming config .UnusedUplinkPort collection
                            $UnusedUplinkPorts = $UnusedUplinkPorts | Where-Object {$_ -ne $uplinkName}

                        } # else

                    } # unused

                    default {
                        throw ("Failed to determine status of uplink.")
                    } # default

                } # switch


                ## Add this to the appropriate uplink port group
                switch ($uplinkState) {

                    "active" {

                        Write-Verbose ("Setting uplink to active.")

                        ## Add this to active
                        $activeUplinkPorts += $uplinkName

                    } # active


                    "standby" {

                        Write-Verbose ("Setting uplink to standby.")
                        $StandbyUplinkPorts += $uplinkName

                    } # standby


                    "unused" {

                        Write-Verbose ("Setting uplink to unused.")
                        $UnusedUplinkPorts += $uplinkName

                    } # unused

                } # switch


                ## Build a cmd string
                $cmdString = "`$teamingPolicy | Set-VDUplinkTeamingPolicy "

                if ($ActiveUplinkPorts) {
                    $cmdString = $cmdString + "-ActiveUplinkPort `$activeUplinkPorts "
                } # if
                if ($StandbyUplinkPorts) {
                    $cmdString = $cmdString + "-StandbyUplinkPort `$StandbyUplinkPorts"
                } # if
                if ($UnusedUplinkPorts) {
                    $cmdString = $cmdString + "-UnusedUplinkPort `$UnusedUplinkPorts"
                } # if


                ## Add tail to cmd
                $cmdString = $cmdString + " -ErrorAction Stop | Out-Null"

                ## Apply new configuration
                try {

                    ## Apply shouldProcess
                    if ($PSCmdlet.ShouldProcess($vdPort.name)) {
                        Invoke-Expression -Command $cmdString -ErrorAction Stop
                    } # if

                    Write-Verbose ("Set new uplink configuration")
                } # try
                catch {
                    Write-Debug ("Failed to set new teaming policy.")
                    throw ("Failed to set new teaming policy. " + $_.exception.message)
                } # catch


            } # foreach

        } # else


        Write-Verbose ("Completed DV switch " + $vdSwitch.name)

    } # process


    end {

        Write-Verbose ("Function complete")

    } # end


} # function
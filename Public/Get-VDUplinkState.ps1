function Get-VDUplinkState {
#Requires -Modules @{"ModuleName" = "VMware.VimAutomation.Core"; "ModuleVersion" = "11.0.0.10336080"}
    <#
    .SYNOPSIS
        Return a table of uplink status for all port groups on a distributed switch.

    .DESCRIPTION
        Return a table of uplink status for all port groups on a distributed switch.

    .PARAMETER vdSwitch
        VD switch object as returned by Get-VDSwitch

    .PARAMETER uplinkName
        Name of uplink to get configuration of.

    .INPUTS
        VMware.VimAutomation.Vds.Impl.VDObjectImpl. Virtual distributed switch object as returned by Get-VDSwitch

    .OUTPUTS
        System.Management.Automation.PSCustomObject. Collection of objects representing port groups and the assignment for the specified uplink.

    .EXAMPLE
        Get-VDUplinkState -vdSwitch $vdSwitch -uplinkName dvUplink1

        Get the uplink assignment for all port groups on the vDS $vdSwitch

    .EXAMPLE
        Get-VDSwitch | Get-VDUplinkState -uplinkName dvUplink1

        Get the uplink assignment for all port groups on the vDS $vdSwitch for all distributed switches returned by Get-VDSwitch


    .LINK


    .NOTES
        01           Alistair McNair          Initial version.

    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [VMware.VimAutomation.Vds.Impl.VDObjectImpl]$vdSwitch,
        [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$uplinkName
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


        ## Set array for return objects
        $uplinkStatuses = @()


        ## Check we have at least 1 port group to work with
        if ($vdPorts.count -lt 1) {

            throw ("No port groups found on this VD switch.")

        } # if
        else {

            Write-Verbose ("Processing " + $vdPorts.count + " port groups.")

            ## Iterate through each port group and query uplink status
            foreach ($vdPort in $vdPorts) {

                try {
                    $teamingPolicy = Get-VDPortgroup -VDSwitch $vdSwitch -Name $vdPort.name -ErrorAction Stop | Get-VDUplinkTeamingPolicy -ErrorAction Stop
                    Write-Verbose ("Got teaming policy for " + $vdPort.name)
                } # try
                catch {
                    Write-Debug ("Failed to get teaming policy")
                    throw ("Failed to get teaming policy for VD port " + $vdPort.name + ". " + $_.exception.message)
                } # catch


                ## Set object for return
                $uplinkStatus = [pscustomobject]@{"portGroup" = $vdPort.name; "uplinkName" = $uplinkName; "isActive" = $false; "isStandby" = $false; "isUnused" = $false}

                ## Check the status of this
                switch ($teamingPolicy) {

                    {$_.ActiveUplinkPort -contains $uplinkName} {
                        Write-Verbose ("Uplink " + $uplinkName + " is active on port group " + $vdPort.name)
                        $uplinkStatus.isActive = $true
                    } # active

                    {$_.StandbyUplinkPort -contains $uplinkName} {
                        Write-Verbose ("Uplink " + $uplinkName + " is standby on port group " + $vdPort.name)
                        $uplinkStatus.isStandby = $true
                    } # standby

                    {$_.UnusedUplinkPort -contains $uplinkName} {
                        Write-Verbose ("Uplink " + $uplinkName + " is unused on port group " + $vdPort.name)
                        $uplinkStatus.isUnused = $true
                    } # unused

                    default {
                        throw ("Failed to determin status of uplink.")
                    } # default

                } # switch

                ## Add this object to the collection to return
                $uplinkStatuses += $uplinkStatus

            } # foreach

        } # else


        Write-Verbose ("Completed DV switch " + $vdSwitch.name)


        ## Return results
        return $uplinkStatuses

    } # process


    end {

        Write-Verbose ("Function complete")

    } # end


} # function
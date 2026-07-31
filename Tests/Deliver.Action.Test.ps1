Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Deliver Action Tests" {
    BeforeAll {
        $actionName = "Deliver"
        $scriptRoot = Join-Path $PSScriptRoot "..\Actions\$actionName" -Resolve
        $scriptName = "$actionName.ps1"
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'scriptPath', Justification = 'False positive.')]
        $scriptPath = Join-Path $scriptRoot $scriptName
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'actionScript', Justification = 'False positive.')]
        $actionScript = GetActionScript -scriptRoot $scriptRoot -scriptName $scriptName
    }

    It 'Compile Action' {
        Invoke-Expression $actionScript
    }

    It 'Test action.yaml matches script' {
        $outputs = [ordered]@{
            "manifestPath" = "Path to the local JSON manifest of the production apps delivered to NuGet (empty for non-NuGet deliveries; apps is empty if no packages were delivered)"
        }
        $outputValues = @{
            "manifestPath" = "`${{ inputs.deliveryTarget == 'NuGet' && steps.deliver.outputs.manifestPath || '' }}"
        }
        $additionalSteps = @(
            '    - name: Publish NuGet delivery manifest'
            "      if: `${{ inputs.deliveryTarget == 'NuGet' }}"
            '      uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1'
            '      with:'
            '        name: ado-delivery-manifest-NuGet-${{ github.run_id }}-${{ github.run_attempt }}'
            '        path: ${{ steps.deliver.outputs.manifestPath }}'
            '        if-no-files-found: error'
        )
        YamlTest -scriptRoot $scriptRoot -actionName $actionName -actionScript $actionScript -outputs $outputs -outputValues $outputValues -additionalSteps $additionalSteps
    }

    # Call action

}

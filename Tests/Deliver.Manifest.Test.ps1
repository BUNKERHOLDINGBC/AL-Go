Get-Module TestActionsHelper | Remove-Module -Force
Import-Module (Join-Path $PSScriptRoot 'TestActionsHelper.psm1')
$errorActionPreference = "Stop"; $ProgressPreference = "SilentlyContinue"; Set-StrictMode -Version 2.0

Describe "Deliver Module - Delivery Manifest Tests" {
    BeforeAll {
        Import-Module (Join-Path $PSScriptRoot "../Actions/Deliver/Deliver.psm1" -Resolve) -DisableNameChecking -Force

        $originalGitHubEnvironment = @{}
        @('GITHUB_REPOSITORY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_SHA') | ForEach-Object {
            $originalGitHubEnvironment[$_] = [Environment]::GetEnvironmentVariable($_)
        }
        $ENV:GITHUB_REPOSITORY = 'microsoft/AL-Go'
        $ENV:GITHUB_RUN_ID = '123456789'
        $ENV:GITHUB_RUN_ATTEMPT = '2'
        $ENV:GITHUB_SHA = '0123456789abcdef0123456789abcdef01234567'

        function New-TestAppJson {
            Param(
                [string] $id = '11111111-1111-1111-1111-111111111111',
                [string] $name = 'My App',
                [string] $publisher = 'Contoso',
                [string] $version = '1.0.0.0'
            )
            return [PSCustomObject]@{
                id        = $id
                name      = $name
                publisher = $publisher
                version   = $version
            }
        }
    }

    AfterAll {
        $originalGitHubEnvironment.Keys | ForEach-Object {
            if ($null -eq $originalGitHubEnvironment[$_]) {
                Remove-Item -Path "Env:$_" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "Env:$_" -Value $originalGitHubEnvironment[$_]
            }
        }
    }

    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'manifestFolder', Justification = 'False positive.')]
        $manifestFolder = (New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.IO.Path]::GetRandomFileName()))).FullName
    }

    It 'adds an entry for a new package pushed from the Apps folder' {
        # A new package: no exact version found on the feed, no latest package to compare with, package was pushed
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $true -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'

        $manifest.Count | Should -Be 1
        $manifest[0].packageName | Should -Be 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'
    }

    It 'adds an entry for a changed package pushed from the Apps folder' {
        # A changed package: Compare-AppFiles found differences, so the package was pushed
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $true -AppJson (New-TestAppJson -version '1.0.0.1') -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'

        $manifest.Count | Should -Be 1
        $manifest[0].version | Should -Be '1.0.0.1'
    }

    It 'does not add an entry for an identical package' {
        # Compare-AppFiles found no meaningful changes, hence no package was pushed
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $false -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'

        $manifest.Count | Should -Be 0
    }

    It 'does not add an entry when the exact version already exists on the feed' {
        # Find-BcNugetPackage found the exact version, hence no package was pushed
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $false -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'

        $manifest.Count | Should -Be 0
    }

    It 'does not add an entry when the push failed' {
        # Push-BcNuGetPackage failed, hence the package was never marked as pushed
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $false -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'

        $manifest.Count | Should -Be 0
    }

    It 'does not add an entry for apps from the TestApps folder' {
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'TestApps' -Pushed $true -AppJson (New-TestAppJson -name 'My App Tests') -Project 'MyProject' -PackageName 'Contoso.MyAppTests.symbols.22222222-2222-2222-2222-222222222222'

        $manifest.Count | Should -Be 0
    }

    It 'does not add an entry for apps from the Dependencies folder' {
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Dependencies' -Pushed $true -AppJson (New-TestAppJson -name 'My Dependency') -Project 'MyProject' -PackageName 'Contoso.MyDependency.symbols.33333333-3333-3333-3333-333333333333'

        $manifest.Count | Should -Be 0
    }

    It 'keeps already collected entries when an entry is skipped' {
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $true -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'
        $manifest = Add-DeliveryManifestEntry -Manifest $manifest -ArtifactType 'TestApps' -Pushed $true -AppJson (New-TestAppJson -name 'My App Tests') -Project 'MyProject' -PackageName 'Contoso.MyAppTests.symbols.22222222-2222-2222-2222-222222222222'
        $manifest = Add-DeliveryManifestEntry -Manifest $manifest -ArtifactType 'Apps' -Pushed $false -AppJson (New-TestAppJson -name 'My Other App') -Project 'MyProject' -PackageName 'Contoso.MyOtherApp.symbols.44444444-4444-4444-4444-444444444444'

        $manifest.Count | Should -Be 1
        $manifest[0].name | Should -Be 'My App'
    }

    It 'writes an empty manifest envelope with matching provenance when nothing was delivered' {
        $path = Join-Path $manifestFolder 'DeliveryManifest-NuGet.json'
        $result = Save-DeliveryManifest -Manifest @() -Path $path

        $result | Should -Be $path
        Test-Path -Path $path | Should -Be $true
        $json = Get-Content -Path $path -Encoding UTF8 -Raw
        $document = $json | ConvertFrom-Json
        @($document.PSObject.Properties.Name) | Should -Be @('schemaVersion', 'repository', 'runId', 'runAttempt', 'headSha', 'deliveryTarget', 'apps')
        $document.schemaVersion | Should -Be 1
        $document.repository | Should -Be 'microsoft/AL-Go'
        $document.runId | Should -Be '123456789'
        $document.runAttempt | Should -Be '2'
        $document.headSha | Should -Be '0123456789abcdef0123456789abcdef01234567'
        $document.deliveryTarget | Should -Be 'NuGet'
        @($document.apps).Count | Should -Be 0
        $json | Should -Match '(?s)"apps"\s*:\s*\[\s*\]'
    }

    It 'writes a manifest with a single entry as an array under apps with all fields' {
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $true -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'
        $path = Join-Path $manifestFolder 'DeliveryManifest-NuGet.json'
        Save-DeliveryManifest -Manifest $manifest -Path $path | Out-Null

        $json = Get-Content -Path $path -Encoding UTF8 -Raw
        $document = $json | ConvertFrom-Json
        $json.TrimStart() | Should -BeLike '{*'
        $json | Should -Match '(?s)"apps"\s*:\s*\['
        $entries = @($document.apps)
        $entries.Count | Should -Be 1
        $entry = $entries[0]
        @($entry.PSObject.Properties.Name) | Should -Be @('id', 'name', 'publisher', 'version', 'project', 'packageName', 'deliveryTarget')
        $entry.id | Should -Be '11111111-1111-1111-1111-111111111111'
        $entry.name | Should -Be 'My App'
        $entry.publisher | Should -Be 'Contoso'
        $entry.version | Should -Be '1.0.0.0'
        $entry.project | Should -Be 'MyProject'
        $entry.packageName | Should -Be 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'
        $entry.deliveryTarget | Should -Be 'NuGet'
    }

    It 'writes a manifest with multiple entries as an array under apps' {
        $manifest = Add-DeliveryManifestEntry -Manifest @() -ArtifactType 'Apps' -Pushed $true -AppJson (New-TestAppJson) -Project 'MyProject' -PackageName 'Contoso.MyApp.symbols.11111111-1111-1111-1111-111111111111'
        $manifest = Add-DeliveryManifestEntry -Manifest $manifest -ArtifactType 'Apps' -Pushed $true -AppJson (New-TestAppJson -id '44444444-4444-4444-4444-444444444444' -name 'My Other App') -Project 'MyOtherProject' -PackageName 'Contoso.MyOtherApp.symbols.44444444-4444-4444-4444-444444444444'
        $path = Join-Path $manifestFolder 'DeliveryManifest-NuGet.json'
        Save-DeliveryManifest -Manifest $manifest -Path $path | Out-Null

        $document = Get-Content -Path $path -Encoding UTF8 -Raw | ConvertFrom-Json
        $entries = @($document.apps)
        $entries.Count | Should -Be 2
        $entries[1].project | Should -Be 'MyOtherProject'
        $entries[1].deliveryTarget | Should -Be 'NuGet'
    }

    It 'creates the manifest folder if it does not exist' {
        $path = Join-Path $manifestFolder 'subfolder/DeliveryManifest-NuGet.json'
        Save-DeliveryManifest -Manifest @() -Path $path | Out-Null

        Test-Path -Path $path | Should -Be $true
    }
}

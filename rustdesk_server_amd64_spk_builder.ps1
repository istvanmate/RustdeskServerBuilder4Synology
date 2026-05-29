# 1. Initialize Paths
$CURRENT_DIR = $PSScriptRoot
$BUILD_DIR = "$CURRENT_DIR\rustdesk-build"
$STAGE_DIR = "$BUILD_DIR\stage"
$version = "1.1.15"
$Url = "https://github.com/rustdesk/rustdesk-server/releases/download/$version/rustdesk-server-linux-amd64.zip"

# 2. Establish Workspaces
New-Item -ItemType Directory -Path "$BUILD_DIR", "$BUILD_DIR\conf", "$STAGE_DIR\bin", "$STAGE_DIR\data", "$BUILD_DIR\scripts" -Force

# 3. Download and extract the downloaded server zip
Invoke-WebRequest -Uri $Url -OutFile "$BUILD_DIR\rustdesk-server-linux-amd64.zip"
$ZipFile = Get-ChildItem "$BUILD_DIR\rustdesk-server-linux-amd64.zip" | Select-Object -First 1 -ExpandProperty FullName
Expand-Archive -Path $ZipFile -DestinationPath "$BUILD_DIR\extracted" -Force

# 4. Move binaries to the staging zone
$ArchDir = Get-ChildItem "$BUILD_DIR\extracted" -Directory | Select-Object -First 1 -ExpandProperty FullName
Move-Item "$ArchDir\hbbs", "$ArchDir\hbbr" -Destination "$STAGE_DIR\bin\" -Force

# 5. Inject your Desktop cryptographic keys
if (Test-Path "$CURRENT_DIR\id_ed25519") { Copy-Item "$CURRENT_DIR\id_ed25519" -Destination "$STAGE_DIR\data\" -Force }
if (Test-Path "$CURRENT_DIR\id_ed25519.pub") { Copy-Item "$CURRENT_DIR\id_ed25519.pub" -Destination "$STAGE_DIR\data\" -Force }

# 6. Transfer Icons if present
if (Test-Path "$CURRENT_DIR\PACKAGE_ICON.PNG") { Copy-Item "$CURRENT_DIR\PACKAGE_ICON.PNG" -Destination "$BUILD_DIR\" -Force }
if (Test-Path "$CURRENT_DIR\PACKAGE_ICON_256.PNG") { Copy-Item "$CURRENT_DIR\PACKAGE_ICON_256.PNG" -Destination "$BUILD_DIR\" -Force }

# 7. Build Configuration Text (INFO)
$InfoContent = @"
package="rustdesk_server"
version="$version"
os_min_ver="7.0-40000"
displayname="RustDesk Server"
description="Self-hosted open-source ID/Rendezvous and Relay server for RustDesk clients."
arch="x86_64"
maintainer="Self"
distributor="RustDesk Community"
startable="yes"
support_center="yes"
"@
Set-Content -Path "$BUILD_DIR\INFO" -Value $InfoContent -NoNewline

# 8. Create DSM 7 Privilege Profile Configuration File inside conf/
$PrivilegeContent = @"
{
  "defaults": {
    "run-as": "package"
  },
  "username": "sc-rustdesk",
  "groupname": "sc-rustdesk"
}
"@
[System.IO.File]::WriteAllText("$BUILD_DIR\conf\privilege", $PrivilegeContent, (New-Object System.Text.UTF8Encoding($false)))

# 9. FIXED LOGIC: Generate Post-installer Hook (postinst) to change permissions AFTER extraction
$PostinstContent = "#!/bin/sh`n" +
"chmod +x /var/packages/rustdesk_server/target/bin/hbbs`n" +
"chmod +x /var/packages/rustdesk_server/target/bin/hbbr`n" +
"chown -R sc-rustdesk:sc-rustdesk /var/packages/rustdesk_server/target/data`n" +
"exit 0"
[System.IO.File]::WriteAllText("$BUILD_DIR\scripts\postinst", $PostinstContent, (New-Object System.Text.UTF8Encoding($false)))

# 10. Generate Management Pipeline Hooks (start-stop-status) with strict LF endings
$ScriptContent = "#!/bin/sh`n" +
"PKG_DIR=`"/var/packages/rustdesk_server/target`"`n" +
"BIN_DIR=`"`${PKG_DIR}/bin`"`n" +
"DATA_DIR=`"`${PKG_DIR}/data`"`n`n" +
"case `"`$1`" in`n" +
"    start)`n" +
"        cd `"`${DATA_DIR}`"`n" +
"        `"`${BIN_DIR}/hbbs`" -r 0.0.0.0 > /dev/null 2>&1 &`n" +
"        `"`${BIN_DIR}/hbbr`" > /dev/null 2>&1 &`n" +
"        exit 0`n" +
"        ;;`n" +
"    stop)`n" +
"        killall hbbs hbbr`n" +
"        exit 0`n" +
"        ;;`n" +
"    status)`n" +
"        if pidof hbbs > /dev/null && pidof hbbr > /dev/null; then exit 0; else exit 3; fi`n" +
"        ;;`n" +
"    *)`n" +
"        exit 1`n" +
"        ;;`n" +
"esac"
[System.IO.File]::WriteAllText("$BUILD_DIR\scripts\start-stop-status", $ScriptContent, (New-Object System.Text.UTF8Encoding($false)))

# 11. Assemble Package
cd $STAGE_DIR
tar -czf "$BUILD_DIR\package.tgz" bin data

cd $BUILD_DIR
if (Test-Path "$BUILD_DIR\PACKAGE_ICON.PNG") {
    tar -cf "$CURRENT_DIR\rustdesk_server.spk" INFO conf package.tgz scripts PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
} else {
    tar -cf "$CURRENT_DIR\rustdesk_server.spk" INFO conf package.tgz scripts
}

# Cleanup temporary build components
cd $HOME
Remove-Item "$BUILD_DIR" -Recurse -Force
Write-Host "Success! Upload your updated $version package to your NAS: rustdesk_server.spk" -ForegroundColor Green

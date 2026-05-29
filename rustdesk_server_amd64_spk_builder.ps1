# 1. Initialize Paths
$CURRENT_DIR = $PSScriptRoot
$BUILD_DIR = "$CURRENT_DIR\rustdesk-build"
$STAGE_DIR = "$BUILD_DIR\stage"
$version = "1.1.15"
$Url = "https://github.com/rustdesk/rustdesk-server/releases/download/$version/rustdesk-server-linux-amd64.zip"

# 2. Establish Workspaces
New-Item -ItemType Directory -Path "$BUILD_DIR", "$BUILD_DIR\conf", "$STAGE_DIR\bin", "$STAGE_DIR\data", "$BUILD_DIR\scripts", "$STAGE_DIR\ui", "$STAGE_DIR\ui\images" -Force

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
dsmuidir="ui"
dsmappname="SYNO.SDS.RustDeskServer"
"@
[System.IO.File]::WriteAllText("$BUILD_DIR\INFO", $InfoContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))


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
[System.IO.File]::WriteAllText("$BUILD_DIR\conf\privilege", $PrivilegeContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

# 9. FIXED LOGIC: Generate Post-installer Hook (postinst) to change permissions AFTER extraction
$PostinstContent = "#!/bin/sh`n" +
"chmod +x /var/packages/rustdesk_server/target/bin/hbbs`n" +
"chmod +x /var/packages/rustdesk_server/target/bin/hbbr`n" +
"chmod +x /var/packages/rustdesk_server/target/ui/index.cgi`n" +
"chown -R sc-rustdesk:sc-rustdesk /var/packages/rustdesk_server/target/data`n" +
"exit 0"
[System.IO.File]::WriteAllText("$BUILD_DIR\scripts\postinst", $PostinstContent, (New-Object System.Text.UTF8Encoding($false)))

# 10. Generate UI
$UiConfig = @'
{
    ".url": {
        "SYNO.SDS.RustDeskServer": {
            "title": "RustDesk Server",
            "desc": "RustDesk Server Administration",
            "icon": "images/icon_72.png",
            "type": "legacy",
            "url": "/webman/3rdparty/rustdesk_server/index.cgi",
            "allUsers": true
        }
    }
}
'@
[System.IO.File]::WriteAllText("$STAGE_DIR\ui\config", $UiConfig.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$CgiContent = @'
#!/bin/sh

echo "Content-Type: text/html"
echo ""

KEY_FILE="/var/packages/rustdesk_server/target/data/id_ed25519.pub"

if [ -f "$KEY_FILE" ]; then
    KEY=$(cat "$KEY_FILE")
else
    KEY="Key not generated yet."
fi

cat <<EOF
<html>
<head>
<meta charset="utf-8">
<title>RustDesk Server</title>

<style>
body {
    font-family: sans-serif;
    margin: 40px;
    background: #f5f5f5;
}

.card {
    background: white;
    border-radius: 12px;
    padding: 20px;
    max-width: 900px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.15);
}

pre {
    background: #efefef;
    padding: 15px;
    border-radius: 8px;
    overflow-x: auto;
}

.status {
    color: green;
    font-weight: bold;
}
</style>
</head>

<body>

<div class="card">
    <h1>RustDesk Server</h1>

    <p class="status">Running</p>

    <h2>Public Key</h2>

    <pre>$KEY</pre>

    <h2>Server Ports</h2>

    <ul>
        <li>21115/TCP</li>
        <li>21116/TCP+UDP</li>
        <li>21117/TCP</li>
        <li>21118/TCP</li>
        <li>21119/TCP</li>
    </ul>
</div>

</body>
</html>
EOF
'@
[System.IO.File]::WriteAllText("$STAGE_DIR\ui\index.cgi", $CgiContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path "$CURRENT_DIR\PACKAGE_ICON.PNG") { Copy-Item "$CURRENT_DIR\PACKAGE_ICON.PNG" -Destination "$STAGE_DIR\ui\images\icon_72.png" -Force}

# 10. Generate Management Pipeline Hooks (start-stop-status) with strict LF endings
$ScriptContent = @'
#!/bin/sh
PKG_DIR="/var/packages/rustdesk_server/target"
BIN_DIR="${PKG_DIR}/bin"
DATA_DIR="${PKG_DIR}/data"

case "$1" in
    start)
        cd "${DATA_DIR}"
        "${BIN_DIR}/hbbs" -r 0.0.0.0 > /dev/null 2>&1 &
        "${BIN_DIR}/hbbr" > /dev/null 2>&1 &
        exit 0
        ;;
    stop)
        killall hbbs hbbr
        exit 0
        ;;
    status)
        if pidof hbbs > /dev/null && pidof hbbr > /dev/null; then exit 0; else exit 3; fi
        ;;
    *)
        exit 1
        ;;
esac
'@
[System.IO.File]::WriteAllText("$BUILD_DIR\scripts\start-stop-status", $ScriptContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

# 11. Assemble Package
cd $STAGE_DIR
tar -czf "$BUILD_DIR\package.tgz" bin data ui

cd $BUILD_DIR
if (Test-Path "$BUILD_DIR\PACKAGE_ICON.PNG") {
    tar -cf "$CURRENT_DIR\rustdesk_server.spk" INFO conf package.tgz scripts PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG
} else {
    tar -cf "$CURRENT_DIR\rustdesk_server.spk" INFO conf package.tgz scripts
}

# Cleanup temporary build components
Remove-Item "$BUILD_DIR" -Recurse -Force
Write-Host "Success! Upload your updated $version package to your NAS: rustdesk_server.spk" -ForegroundColor Green

$CURRENT_DIR = $PSScriptRoot
$BUILD_DIR = Join-Path $CURRENT_DIR "rustdesk-build"
$STAGE_DIR = Join-Path $BUILD_DIR "stage"
$ZIP_DIR = Join-Path $BUILD_DIR "zip"
$RELEASE_DIR = Join-Path $CURRENT_DIR "release"
$version = "1.1.16"
$platforms = @("amd64", "arm64v8", "armv7", "i386")
$arch = @{
    amd64=@("x86_64", "V1000", "Geminilakenk", "Epyc7002", "Broadwellntbap", "V1000nk", "R1000nk", "Geminilake", "R1000", "Denverton", "Apollolake", "Avoton", "Bromolow", "Braswell", "Cedarview", "X86")
    arm64v8=@("rtd1619b", "rtd1296", "armada37xx")
    armv7=@("Armada38x", "Alpine", "Alpine4k", "Monaco", "Armada370", "Armadaxp", "Armada375", "Comcerto2k")
    i386=@("Evansport")
}

New-Item -ItemType Directory -Path $RELEASE_DIR, $BUILD_DIR, $ZIP_DIR, (Join-Path $BUILD_DIR "conf"), (Join-Path $STAGE_DIR "bin"), (Join-Path $STAGE_DIR "data"), (Join-Path $BUILD_DIR "scripts"), (Join-Path $STAGE_DIR "ui"), (Join-Path $STAGE_DIR "ui" "images"), (Join-Path $STAGE_DIR "ui" "texts"), (Join-Path $STAGE_DIR "ui" "texts" "enu") -Force | Out-Null

foreach ($platform in $platforms) {
    $Url = "https://github.com/rustdesk/rustdesk-server/releases/download/$version/rustdesk-server-linux-$platform.zip"
    if (-Not (Test-Path (Join-Path $ZIP_DIR "rustdesk-server-linux-$platform.zip"))) {
        Write-Host "Downloading from $Url ..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $Url -OutFile (Join-Path $ZIP_DIR "rustdesk-server-linux-$platform.zip")
    } else {
        Write-Host "Using cached file for $platform." -ForegroundColor Green
    }
}

foreach ($ZipFile in Get-ChildItem $ZIP_DIR) {
    Expand-Archive -Path $ZipFile -DestinationPath (Join-Path $BUILD_DIR "extracted") -Force
}

#$ArchDir = Get-ChildItem (Join-Path $BUILD_DIR "extracted") -Directory | Select-Object -First 1 -ExpandProperty FullName
#Move-Item (Join-Path $ArchDir "hbbs"), (Join-Path $ArchDir "hbbr") -Destination (Join-Path $STAGE_DIR "bin") -Force

if (Test-Path (Join-Path $CURRENT_DIR "id_ed25519")) { Copy-Item (Join-Path $CURRENT_DIR "id_ed25519") -Destination (Join-Path $STAGE_DIR "data") -Force }
if (Test-Path (Join-Path $CURRENT_DIR "id_ed25519.pub")) { Copy-Item (Join-Path $CURRENT_DIR "id_ed25519.pub") -Destination (Join-Path $STAGE_DIR "data") -Force }

if (Test-Path (Join-Path $CURRENT_DIR "PACKAGE_ICON.PNG")) { Copy-Item (Join-Path $CURRENT_DIR "PACKAGE_ICON.PNG") -Destination $BUILD_DIR -Force }
if (Test-Path (Join-Path $CURRENT_DIR "PACKAGE_ICON_256.PNG")) { Copy-Item (Join-Path $CURRENT_DIR "PACKAGE_ICON_256.PNG") -Destination $BUILD_DIR -Force }

$InfoContent = @"
package="rustdesk_server"
version="$version"
os_min_ver="7.0-40000"
displayname="RustDesk Server"
description="Self-hosted open-source ID/Rendezvous and Relay server for RustDesk clients. This package was built with https://github.com/istvanmate/RustdeskServerBuilder4Synology"
arch="{model}"
maintainer="Self"
distributor="RustDesk Community"
startable="yes"
support_center="yes"
thirdparty="yes"
dsmuidir="ui"
dsmappname="SYNOCOMMUNITY.RustDeskServer.AppInstance"
"@

$PrivilegeContent = @"
{
  "defaults": {
    "run-as": "package"
  },
  "username": "sc-rustdesk",
  "groupname": "sc-rustdesk",
  "join-group": "http"
}
"@
[System.IO.File]::WriteAllText((Join-Path $BUILD_DIR "conf" "privilege"), $PrivilegeContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$PostinstContent = @"
#!/bin/sh
chmod +x /var/packages/rustdesk_server/target/bin/hbbs
chmod +x /var/packages/rustdesk_server/target/bin/hbbr
chmod +x /var/packages/rustdesk_server/target/ui/index.cgi
chown -R sc-rustdesk:sc-rustdesk /var/packages/rustdesk_server/target/data

rm -f /var/packages/rustdesk_server/target/ui/ui
rm -rf /usr/syno/synoman/webman/3rdparty/rustdesk_server
ln -sf /var/packages/rustdesk_server/target/ui /usr/syno/synoman/webman/3rdparty/rustdesk_server
chmod -R 755 /var/packages/rustdesk_server/target/ui
chown -R root:root /var/packages/rustdesk_server/target/ui
exit 0
"@
[System.IO.File]::WriteAllText((Join-Path $BUILD_DIR "scripts" "postinst"), $PostinstContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$UiConfig = @'
{
    "dsm-wrapper.js": {
        "SYNOCOMMUNITY.RustDeskServer.AppInstance": {
            "type": "app",
            "title": "app:app_name",
            "version": "1.0",
            "icon": "images/icon_{0}.png",
            "texts": "texts",
            "allowMultiInstance": false,
            "allUsers": true,
            "appWindow": "SYNOCOMMUNITY.RustDeskServer.AppWindow",
            "depend": ["SYNOCOMMUNITY.RustDeskServer.AppWindow"]
        },
        "SYNOCOMMUNITY.RustDeskServer.AppWindow": {
            "type": "lib",
            "title": "app:app_name",
            "icon": "images/icon_{0}.png",
            "texts": "texts"
        }
    }
}
'@
[System.IO.File]::WriteAllText((Join-Path $STAGE_DIR "ui" "config"), $UiConfig.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$IndexConf = @'
{
    "app": "SYNOCOMMUNITY.RustDeskServer.AppInstance",
    "title": "app:app_name",
    "desc": "app:description",
    "stringset": "texts",
    "keywords": [
        "rustdesk",
        "RustDesk Server"
    ]
}
'@
[System.IO.File]::WriteAllText((Join-Path $STAGE_DIR "ui" "index.conf"), $IndexConf.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$AppJs = @'
Ext.ns("SYNOCOMMUNITY.RustDeskServer");

Ext.define("SYNOCOMMUNITY.RustDeskServer.AppInstance", {
    extend: "SYNO.SDS.AppInstance",
    appWindowName: "SYNOCOMMUNITY.RustDeskServer.AppWindow",
    constructor: function () {
        this.callParent(arguments);
    }
});

Ext.define("SYNOCOMMUNITY.RustDeskServer.AppWindow", {
    extend: "SYNO.SDS.AppWindow",
    constructor: function (config) {
        const appConfig = Ext.apply({
            resizable: true,
            maximizable: true,
            minimizable: true,
            width: 800,
            height: 600,
            minWidth: 600,
            minHeight: 450,
            layout: "fit",
            border: false,
            title: "RustDesk Server",
            items: [{
                xtype: "box",
                itemId: "appframe",
                autoEl: {
                    tag: "iframe",
                    src: "/webman/3rdparty/rustdesk_server/index.cgi",
                    frameborder: "0",
                    style: "width:100%; height:100%; border:none;"
                }
            }]
        }, config);
        this.callParent([appConfig]);
    },
    onOpen: function (config) {
        this.callParent([config]);
    },
    onRequest: function (config) {
        this.onOpen(config);
    }
});
'@
[System.IO.File]::WriteAllText((Join-Path $STAGE_DIR "ui" "dsm-wrapper.js"), $AppJs.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$Strings = @'
[app]
app_name="RustDesk Server"
description="RustDesk Server Administration"
'@
[System.IO.File]::WriteAllText((Join-Path $STAGE_DIR "ui" "texts" "enu" "strings"), $Strings.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$CgiContent = @'
#!/bin/sh
if [ -z "$HTTP_COOKIE" ] || ! echo "$HTTP_COOKIE" | grep -qE '(id=|synoToken=|SESS_)'; then
    echo "Status: 403 Forbidden"
    echo "Content-Type: text/html"
    echo ""
    echo "<html><body style='font-family:sans-serif;padding:40px'><h2>Access denied</h2><p>Please log in to DSM first.</p></body></html>"
    exit 1
fi
echo "Content-Type: text/html"
echo ""
KEY_FILE="/var/packages/rustdesk_server/target/data/id_ed25519.pub"
if [ -f "$KEY_FILE" ]; then KEY=$(cat "$KEY_FILE"); else KEY="Key not generated yet."; fi
if pidof hbbs > /dev/null 2>&1 && pidof hbbr > /dev/null 2>&1; then
    STATUS_TEXT="Running"; STATUS_CLASS="status-running"
else
    STATUS_TEXT="Stopped"; STATUS_CLASS="status-stopped"
fi
cat <<EOF
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>RustDesk Server</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;margin:0px;padding:24px;background:#f0f2f5}
pre{background:#f6f8fa;padding:14px;border-radius:8px;overflow-x:auto;font-size:13px;border:1px solid #e1e4e8}
.status-running{color:#1a7f37;font-weight:600;font-size:16px}
.status-stopped{color:#cf222e;font-weight:600;font-size:16px}
h1{margin-top:0} h2{margin-top:24px} ul{line-height:1.7}
</style></head><body>
<h1>RustDesk Server</h1>
<p class="$STATUS_CLASS">$STATUS_TEXT</p>
<h2>Public Key</h2>
<pre>$KEY</pre>
<h2>Server Ports</h2>
<ul><li>21115 / TCP</li><li>21116 / TCP + UDP</li><li>21117 / TCP</li><li>21118 / TCP</li><li>21119 / TCP</li></ul>
</body></html>
EOF
'@
[System.IO.File]::WriteAllText((Join-Path $STAGE_DIR "ui" "index.cgi"), $CgiContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

foreach ($size in @(16,24,32,48,64,72,256)) {
    #Copy-Item (Join-Path $CURRENT_DIR "icon_$size.png") -Destination (Join-Path $STAGE_DIR "ui" "images" "icon_$size.png") -Force
    [System.IO.File]::WriteAllBytes((Join-Path $STAGE_DIR "ui" "images" "icon_$size.png"), [System.IO.File]::ReadAllBytes((Join-Path $CURRENT_DIR "icon_$size.png")))
}

$ScriptContent = @'
#!/bin/sh
PKG_DIR="/var/packages/rustdesk_server/target"
BIN_DIR="${PKG_DIR}/bin"
DATA_DIR="${PKG_DIR}/data"
case "$1" in
    start) cd "${DATA_DIR}"; "${BIN_DIR}/hbbs" -r 0.0.0.0 > /dev/null 2>&1 & "${BIN_DIR}/hbbr" > /dev/null 2>&1 & exit 0 ;;
    stop) killall hbbs hbbr 2>/dev/null; exit 0 ;;
    status) if pidof hbbs > /dev/null 2>&1 && pidof hbbr > /dev/null 2>&1; then exit 0; else exit 3; fi ;;
    *) exit 1 ;;
esac
'@
[System.IO.File]::WriteAllText((Join-Path $BUILD_DIR "scripts" "start-stop-status"), $ScriptContent.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

$packageCounter = 0

foreach ($platform in $platforms) {
    $ArchDir = Join-Path $BUILD_DIR "extracted" $platform
    Move-Item (Join-Path $ArchDir "hbbs"), (Join-Path $ArchDir "hbbr") -Destination (Join-Path $STAGE_DIR "bin") -Force
    Set-Location $STAGE_DIR
    tar -czf (Join-Path $BUILD_DIR "package.tgz") bin data ui
    Set-Location $BUILD_DIR
    $spkFiles = @("INFO", "conf", "package.tgz", "scripts")
    if (Test-Path (Join-Path $BUILD_DIR "PACKAGE_ICON.PNG")) { $spkFiles += "PACKAGE_ICON.PNG" }
    if (Test-Path (Join-Path $BUILD_DIR "PACKAGE_ICON_256.PNG")) { $spkFiles += "PACKAGE_ICON_256.PNG" }
    foreach ($model in $arch[$platform]) {
        [System.IO.File]::WriteAllText((Join-Path $BUILD_DIR "INFO"), $InfoContent.Replace("{model}", $model).Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
        tar -cf (Join-Path $RELEASE_DIR "rustdesk_server_$model.spk") $spkFiles
        $packageCounter++
        Write-Host "Package for $model created." -ForegroundColor Green
    }
}

Set-Location $CURRENT_DIR
Remove-Item "$BUILD_DIR" -Recurse -Force

Write-Host ""
Write-Host "Success! $packageCounter packages created." -ForegroundColor Green
Write-Host ""

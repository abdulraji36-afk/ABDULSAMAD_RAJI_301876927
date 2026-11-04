param([Parameter(Mandatory)][string]$PostgresBin, [switch]$Json)
$ErrorActionPreference = 'Stop'

$bin = (Resolve-Path -LiteralPath $PostgresBin).Path
$initdb = Join-Path $bin 'initdb.exe'
$ctl = Join-Path $bin 'pg_ctl.exe'
$repo = Split-Path -Parent $PSScriptRoot
$temp = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).Path
$name = 'bilikis-p5-' + [Guid]::NewGuid().ToString('N')
$lab = Join-Path $temp $name
$password = [Guid]::NewGuid().ToString('N')
$passFile = Join-Path $lab 'password'
$clusters = @(
    @{ Name = 'publisher'; Database = 'bilikis_p5_publisher'; Options = '-c wal_level=logical' }
    @{ Name = 'subscriber'; Database = 'bilikis_p5_subscriber'; Options = '' }
)
$oldPrimary = $env:P5_PRIMARY_URL
$oldSubscriber = $env:P5_SUBSCRIBER_URL

function New-Cluster($cluster, $port) {
    $cluster.Data = Join-Path $lab $cluster.Name
    $log = Join-Path $lab ($cluster.Name + '.log')
    & $initdb -D $cluster.Data -U portfolio_lab --auth=scram-sha-256 "--pwfile=$passFile" --locale=C --encoding=UTF8 --no-instructions --no-sync | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "initdb failed for $($cluster.Name)." }

    # Keep postgres from inheriting the PowerShell output pipe.
    $arguments = "start -D `"$($cluster.Data)`" -l `"$log`" -w -t 30 -o `"-h 127.0.0.1 -p $port $($cluster.Options)`""
    $startup = Start-Process -FilePath $ctl -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (!$startup.WaitForExit(40000) -or $startup.ExitCode -ne 0) {
        throw "PostgreSQL failed to start for $($cluster.Name). See $log."
    }

    $url = "postgresql://portfolio_lab:${password}@127.0.0.1:${port}"
    # Use pg to create the disposable database, including on distributions without psql.
    $env:P5_INIT_URL = "$url/postgres"
    $env:P5_INIT_DATABASE = $cluster.Database
    node --input-type=module -e "import pg from 'pg'; const client = new pg.Client({connectionString:process.env.P5_INIT_URL, connectionTimeoutMillis:5000, query_timeout:10000}); await client.connect(); try { await client.query('CREATE DATABASE ' + client.escapeIdentifier(process.env.P5_INIT_DATABASE)); } finally { await client.end(); }" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Could not create $($cluster.Database)." }
    "$url/$($cluster.Database)"
}

New-Item -ItemType Directory -Path $lab | Out-Null
$oldInitUrl = $env:P5_INIT_URL
$oldInitDatabase = $env:P5_INIT_DATABASE
$passed = $false
Push-Location -LiteralPath $repo
try {
    [IO.File]::WriteAllText($passFile, $password + [Environment]::NewLine)
    $ports = @(node --input-type=module -e "import {createServer} from 'node:net'; import {once} from 'node:events'; const servers = [createServer(),createServer()]; await Promise.all(servers.map(s => { s.listen(0,'127.0.0.1'); return once(s,'listening'); })); for (const s of servers) { console.log(s.address().port); s.close(); }")
    if ($LASTEXITCODE -ne 0 -or $ports.Count -ne 2) { throw 'Could not choose two loopback ports.' }
    $env:P5_PRIMARY_URL = New-Cluster $clusters[0] $ports[0]
    $env:P5_SUBSCRIBER_URL = New-Cluster $clusters[1] $ports[1]
    $runnerArgs = @(Join-Path $PSScriptRoot 'run.mjs')
    if ($Json) { $runnerArgs += '--json' }
    node @runnerArgs
    if ($LASTEXITCODE -ne 0) { throw 'Portfolio 5 replication verification failed.' }
    $passed = $true
} finally {
    $env:P5_PRIMARY_URL = $oldPrimary
    $env:P5_SUBSCRIBER_URL = $oldSubscriber
    $env:P5_INIT_URL = $oldInitUrl
    $env:P5_INIT_DATABASE = $oldInitDatabase
    Pop-Location

    $stopped = $true
    foreach ($cluster in @($clusters[1], $clusters[0])) {
        if ($cluster.Data -and (Test-Path -LiteralPath (Join-Path $cluster.Data 'postmaster.pid'))) {
            & $ctl stop -D $cluster.Data -m fast -w -t 30 | Out-Host
            if ($LASTEXITCODE -ne 0) { $stopped = $false }
        }
    }
    Remove-Item -LiteralPath $passFile -ErrorAction SilentlyContinue
    $resolved = (Resolve-Path -LiteralPath $lab).Path
    if ($passed -and $stopped -and $resolved -eq (Join-Path $temp $name)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if (!$stopped) { throw "Could not stop both disposable PostgreSQL instances. Lab files are at $lab." }
    if (!$passed) { Write-Warning "Lab logs are at $lab." }
}

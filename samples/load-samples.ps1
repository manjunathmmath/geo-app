<#
.SYNOPSIS
  Adds sample posts (photos, audio, video and text) around one or more locations, through the API.
  Safe for a real server.

.DESCRIPTION
  - Signs in as the admin you name. The password is asked for here (or read from GEOAPP_ADMIN_PASSWORD), never stored.
  - Creates three sample creators (sample.alice / sample.bob / sample.carol @example.test) with random passwords
    that are thrown away, so nobody can sign in as them. They only own the sample posts.
  - The FIRST location gets the full set: 13 approved posts within 20 m (3 of them text), 8 approved farther away,
    9 pending posts for the moderation queue, 2 rejected posts with reasons, and 2 reports. Every further location
    gets a smaller set (6 + 3 approved, 4 pending, 1 rejected).
  - Skips a location that already has "Corner tea stall" there, so running it twice does not duplicate posts.
  - -TextOnly adds just the text posts (4 approved) to locations that already have the other samples, for servers
    that were filled before text posts existed.

.EXAMPLE
  .\load-samples.ps1 -BaseUrl http://YOUR_VM_IP -AdminEmail you@example.com -Location '12.37602,77.06316','12.9786,77.364'

.EXAMPLE
  .\load-samples.ps1 -BaseUrl http://YOUR_VM_IP -AdminEmail you@example.com -Location '12.37602,77.06316' -TextOnly
#>
param(
  [Parameter(Mandatory)][string]$BaseUrl,
  [Parameter(Mandatory)][string]$AdminEmail,
  [Parameter(Mandatory)][string[]]$Location,   # each as "latitude,longitude"
  [switch]$TextOnly
)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
$b = $BaseUrl.TrimEnd('/')
$img = Join-Path $PSScriptRoot 'images'
$aud = Join-Path $PSScriptRoot 'audio'
$vid = Join-Path $PSScriptRoot 'video'

$places = foreach ($l in $Location) {
  $p = $l -split ','
  if ($p.Count -ne 2) { throw "Location '$l' must look like 12.37602,77.06316" }
  @{ lat = [double]::Parse($p[0].Trim(), $inv); lng = [double]::Parse($p[1].Trim(), $inv) }
}

$pw = $env:GEOAPP_ADMIN_PASSWORD
if (-not $pw) {
  $sec = Read-Host "Admin password for $AdminEmail" -AsSecureString
  $pw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

function Json($o) { $o | ConvertTo-Json -Compress }

# $file = $null makes a text post: $caption is then the text itself.
function NewPost($token, $file, $caption, $where, $metres, $bearing, $accuracy, $authorId) {
  $rad = [math]::PI * $bearing / 180
  $lat = $where.lat + $metres * [math]::Cos($rad) / 111320.0
  $lng = $where.lng + $metres * [math]::Sin($rad) / (111320.0 * [math]::Cos([math]::PI * $where.lat / 180))
  $a = @('-s', '-X', 'POST', "$b/api/posts", '-H', "Authorization: Bearer $token",
    '-F', ('lat=' + $lat.ToString('F6', $inv)),
    '-F', ('lng=' + $lng.ToString('F6', $inv)),
    '-F', "accuracy=$accuracy")
  if ($file) { $a += @('-F', "file=@$file", '-F', "caption=$caption") } else { $a += @('-F', "text=$caption") }
  if ($authorId) { $a += @('-F', "authorId=$authorId") }
  $p = (& curl.exe @a) | ConvertFrom-Json
  if (-not $p.id) { throw "Post failed for '$caption'" }
  $p
}

# 1. Admin sign-in
try {
  $admin = (Invoke-RestMethod -Method Post -Uri "$b/api/auth/login" -ContentType 'application/json' -Body (Json @{ email = $AdminEmail; password = $pw })).accessToken
} catch { throw "Could not sign in as $AdminEmail at $b. Check the address and the password." }
$h = @{ Authorization = "Bearer $admin" }
$pw = $null

# 2. Sample creators with random passwords nobody keeps
function NewCreator($name) {
  $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
  $bytes = New-Object byte[] 24; $rng.GetBytes($bytes)
  $email = "sample.$name@example.test"
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$b/api/auth/register" -ContentType 'application/json' -Body (Json @{ email = $email; password = [Convert]::ToBase64String($bytes) })
    @{ id = $r.user.id; token = $r.accessToken }
  } catch {
    $u = @(curl.exe -s "$b/api/admin/users?limit=100" -H "Authorization: Bearer $admin" | ConvertFrom-Json) | ForEach-Object { $_ } | Where-Object { $_.email -eq $email }
    if (-not $u) { throw "Could not create or find $email" }
    @{ id = $u.id; token = $null }   # left over from an earlier run: its password is unknown, so it cannot post pending items
  }
}
$alice = NewCreator 'alice'; $bob = NewCreator 'bob'; $carol = NewCreator 'carol'
$canPostAsCreators = $alice.token -and $bob.token -and $carol.token
$tok = @($alice.token, $bob.token, $carol.token)

# 3. The sample content: file (or $null for text), caption or text, metres, bearing, accuracy, author
$nearItems = @(
  @("$img\photo-01.png", 'Corner tea stall', 3, 0, 6, $alice.id),
  @("$img\photo-02.png", 'Old banyan tree', 7, 60, 8, $bob.id),
  @("$img\photo-04.png", 'Temple gate', 9, 330, 5, $carol.id),
  @("$aud\doorbell-ding-dong.mp3", 'Shop door bell (sample mp3)', 10, 310, 7, $alice.id),
  @("$aud\chime-arpeggio.wav", 'Temple bells (sample chime)', 11, 130, 7, $carol.id),
  @("$vid\test-pattern-with-sound-5s.mp4", 'Street performance (sample video)', 6, 20, 7, $alice.id),
  @("$vid\color-bars-silent-3s.mp4", 'Colour bars (sample video, no sound)', 13, 160, 7, $bob.id),
  @("$img\photo-03.png", 'Street art on the wall', 14, 200, 9, $alice.id),
  @("$aud\chime-arpeggio.m4a", 'Radio jingle (sample m4a)', 15, 240, 7, $carol.id),
  @("$aud\doorbell-ding-dong.wav", 'Gate bell (sample)', 17, 280, 10, $bob.id),
  @($null, 'The chai here is best after 5 pm. Ask for the cardamom one.', 5, 300, 6, $bob.id),
  @($null, 'Heads up: the lane behind the temple is closed until Saturday for repairs.', 16, 150, 6, $carol.id),
  @($null, 'Lost a blue umbrella near the bus stop yesterday. If you find it, please post here.', 12, 230, 6, $alice.id))
$nearSubset = 0, 3, 5, 6, 8, 10     # a photo, an mp3, two videos, an m4a and a text post
$nearText = 10, 11, 12

$farItems = @(
  @("$img\photo-05.png", 'Bus stop', 35, 20, 7, $alice.id),
  @("$img\photo-06.png", 'Playground', 60, 110, 7, $bob.id),
  @("$vid\mandelbrot-zoom-4s.mp4", 'Light show (sample video)', 80, 90, 7, $carol.id),
  @("$aud\rising-sweep-3s.wav", 'Fountain sound (sample)', 90, 200, 7, $carol.id),
  @($null, 'Free parking on this side of the road after 6 pm.', 120, 20, 7, $bob.id),
  @("$img\photo-07.png", 'Fountain square', 150, 250, 7, $alice.id),
  @("$img\photo-08.png", 'Market entrance', 250, 300, 7, $bob.id),
  @("$img\photo-09.png", 'Lake view', 600, 60, 7, $carol.id))

$pendingItems = @(
  @("$img\photo-10.png", 'New cafe opening'), @("$img\photo-11.png", 'Cat on the wall'),
  @("$img\photo-12.png", 'Sunset from the roof'), @("$img\photo-13.png", 'Pothole near the gate'),
  @($null, 'Is the bakery on the corner still open on Sundays?'),
  @("$img\photo-14.png", 'Fresh flowers stall'), @("$img\photo-15.png", 'Bicycle repair shop'),
  @("$img\photo-16.png", 'Morning mist'), @("$aud\tone-440hz-3s.wav", 'Evening prayer sounds (sample tone)'))

$rejectItems = @(
  @("$img\photo-17.png", 'Blurry photo', 1, 'Image is too blurry to see'),
  @("$img\photo-18.png", 'Someones face', 2, 'Shows an identifiable person without consent'))

# 4. One location at a time
$first = $true
foreach ($where in $places) {
  $label = "{0}, {1}" -f $where.lat.ToString($inv), $where.lng.ToString($inv)
  $q = "lat=$($where.lat.ToString('F6', $inv))&lng=$($where.lng.ToString('F6', $inv))"
  "`n=== $label ==="
  $here = @(Invoke-RestMethod "$b/api/posts/nearby?$q&radius=100")

  if ($TextOnly) {
    if (@($here | Where-Object { $_.type -eq 'TEXT' -and $_.text -like 'The chai here is best*' }).Count -gt 0) {
      'Text samples already exist here, skipped.'; continue
    }
    foreach ($i in $nearText) { $x = $nearItems[$i]; NewPost $admin $x[0] $x[1] $where $x[2] $x[3] $x[4] $x[5] | Out-Null }
    $x = $farItems[4]; NewPost $admin $x[0] $x[1] $where $x[2] $x[3] $x[4] $x[5] | Out-Null
    'added 4 approved text posts (3 within 20 m, 1 farther away)'
    continue
  }

  if (@($here | Where-Object { $_.caption -eq 'Corner tea stall' }).Count -gt 0) {
    'Sample posts already exist here, skipped.'; $first = $false; continue
  }

  $nearList = if ($first) { 0..($nearItems.Count - 1) } else { $nearSubset }
  $farCount = if ($first) { $farItems.Count } else { 3 }
  $pendingCount = if ($first) { $pendingItems.Count } else { 4 }
  $rejectCount = if ($first) { $rejectItems.Count } else { 1 }

  $near = @()
  foreach ($i in $nearList) { $x = $nearItems[$i]; $near += NewPost $admin $x[0] $x[1] $where $x[2] $x[3] $x[4] $x[5] }
  "approved within 20 m: $($near.Count)"

  for ($i = 0; $i -lt $farCount; $i++) { $x = $farItems[$i]; NewPost $admin $x[0] $x[1] $where $x[2] $x[3] $x[4] $x[5] | Out-Null }
  "approved farther away: $farCount"

  if ($canPostAsCreators) {
    for ($i = 0; $i -lt $pendingCount; $i++) {
      NewPost $tok[$i % 3] $pendingItems[$i][0] $pendingItems[$i][1] $where (4 + $i * 3) ($i * 45) (5 + $i % 5) $null | Out-Null
    }
    "pending: $pendingCount"

    for ($k = 0; $k -lt $rejectCount; $k++) {
      $r = $rejectItems[$k]
      $p = NewPost $tok[$r[2]] $r[0] $r[1] $where (8 + $k * 5) (100 + $k * 90) 6 $null
      Invoke-RestMethod -Method Post -Uri "$b/api/admin/posts/$($p.id)/review" -Headers $h -ContentType 'application/json' -Body (Json @{ decision = 'REJECT'; reason = $r[3] }) | Out-Null
    }
    "rejected: $rejectCount"

    if ($first) {
      foreach ($t in @($bob.token, $carol.token)) {
        Invoke-RestMethod -Method Post -Uri "$b/api/posts/$($near[0].id)/report" -Headers @{ Authorization = "Bearer $t" } -ContentType 'application/json' -Body (Json @{ reason = 'Looks like an advertisement' }) | Out-Null
      }
      'reports: 2'
    }
  } else {
    'Pending, rejected and reports skipped (the sample creators already exist from an earlier run).'
  }

  $n = Invoke-RestMethod "$b/api/posts/nearby?$q"
  "Within 20 m now: $($n.Count) post(s), newest first"
  foreach ($p in $n) { '  {0,-6} {1,5:N1} m  {2}' -f $p.type, $p.distanceM, $(if ($p.type -eq 'TEXT') { $p.text } else { $p.caption }) }
  $first = $false
}

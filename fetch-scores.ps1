# WC26 Score Fetcher
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$token  = '5d6ab1203ca84b03a93d2eb9c847ea6c'
$fbBase = 'https://world-cup-score-predictor-default-rtdb.asia-southeast1.firebasedatabase.app'

$teamMap = @{
  'Korea Republic'               = 'South Korea'
  'Czech Republic'               = 'Czechia'
  'United States'                = 'USA'
  'Turkey'                       = 'Türkiye'
  "Cote d'Ivoire"                = 'Ivory Coast'
  "Côte d'Ivoire"                = 'Ivory Coast'
  'IR Iran'                      = 'Iran'
  'Bosnia and Herzegovina'       = 'Bosnia & Herz.'
  'Bosnia-Herzegovina'           = 'Bosnia & Herz.'
  'Cape Verde Islands'           = 'Cape Verde'
  'Democratic Republic of Congo' = 'DR Congo'
  'Congo DR'                     = 'DR Congo'
  'Curacao'                      = 'Curaçao'
}

$fixtures = @(
  @{id='A1';h='Mexico';a='South Africa'},         @{id='A2';h='South Korea';a='Czechia'},
  @{id='A3';h='South Africa';a='Czechia'},         @{id='A4';h='Mexico';a='South Korea'},
  @{id='A5';h='Mexico';a='Czechia'},               @{id='A6';h='South Korea';a='South Africa'},
  @{id='B1';h='Canada';a='Bosnia & Herz.'},        @{id='B2';h='Qatar';a='Switzerland'},
  @{id='B3';h='Switzerland';a='Bosnia & Herz.'},   @{id='B4';h='Canada';a='Qatar'},
  @{id='B5';h='Canada';a='Switzerland'},           @{id='B6';h='Qatar';a='Bosnia & Herz.'},
  @{id='C1';h='Brazil';a='Morocco'},               @{id='C2';h='Haiti';a='Scotland'},
  @{id='C3';h='Scotland';a='Morocco'},             @{id='C4';h='Brazil';a='Haiti'},
  @{id='C5';h='Scotland';a='Brazil'},              @{id='C6';h='Morocco';a='Haiti'},
  @{id='D1';h='USA';a='Paraguay'},                 @{id='D2';h='Australia';a='Türkiye'},
  @{id='D3';h='USA';a='Australia'},               @{id='D4';h='Paraguay';a='Türkiye'},
  @{id='D5';h='USA';a='Türkiye'},                 @{id='D6';h='Paraguay';a='Australia'},
  @{id='E1';h='Germany';a='Curaçao'},             @{id='E2';h='Ivory Coast';a='Ecuador'},
  @{id='E3';h='Germany';a='Ivory Coast'},          @{id='E4';h='Ecuador';a='Curaçao'},
  @{id='E5';h='Ecuador';a='Germany'},              @{id='E6';h='Curaçao';a='Ivory Coast'},
  @{id='F1';h='Netherlands';a='Japan'},            @{id='F2';h='Tunisia';a='Sweden'},
  @{id='F3';h='Netherlands';a='Sweden'},           @{id='F4';h='Tunisia';a='Japan'},
  @{id='F5';h='Tunisia';a='Netherlands'},          @{id='F6';h='Japan';a='Sweden'},
  @{id='G1';h='Belgium';a='Egypt'},                @{id='G2';h='Iran';a='New Zealand'},
  @{id='G3';h='Belgium';a='Iran'},                 @{id='G4';h='New Zealand';a='Egypt'},
  @{id='G5';h='New Zealand';a='Belgium'},          @{id='G6';h='Egypt';a='Iran'},
  @{id='H1';h='Spain';a='Cape Verde'},             @{id='H2';h='Saudi Arabia';a='Uruguay'},
  @{id='H3';h='Spain';a='Saudi Arabia'},           @{id='H4';h='Uruguay';a='Cape Verde'},
  @{id='H5';h='Uruguay';a='Spain'},                @{id='H6';h='Cape Verde';a='Saudi Arabia'},
  @{id='I1';h='France';a='Senegal'},               @{id='I2';h='Norway';a='Iraq'},
  @{id='I3';h='France';a='Iraq'},                  @{id='I4';h='Norway';a='Senegal'},
  @{id='I5';h='Norway';a='France'},                @{id='I6';h='Senegal';a='Iraq'},
  @{id='J1';h='Argentina';a='Algeria'},            @{id='J2';h='Austria';a='Jordan'},
  @{id='J3';h='Argentina';a='Austria'},            @{id='J4';h='Jordan';a='Algeria'},
  @{id='J5';h='Jordan';a='Argentina'},             @{id='J6';h='Algeria';a='Austria'},
  @{id='K1';h='Portugal';a='DR Congo'},            @{id='K2';h='Uzbekistan';a='Colombia'},
  @{id='K3';h='Portugal';a='Uzbekistan'},          @{id='K4';h='Colombia';a='DR Congo'},
  @{id='K5';h='Colombia';a='Portugal'},            @{id='K6';h='Uzbekistan';a='DR Congo'},
  @{id='L1';h='England';a='Croatia'},              @{id='L2';h='Ghana';a='Panama'},
  @{id='L3';h='England';a='Ghana'},                @{id='L4';h='Panama';a='Croatia'},
  @{id='L5';h='Panama';a='England'},               @{id='L6';h='Croatia';a='Ghana'}
)

function Norm($name) {
  $n = $name.Normalize([System.Text.NormalizationForm]::FormC)
  if ($teamMap.ContainsKey($n)) { $n = $teamMap[$n] }
  return $n.Normalize([System.Text.NormalizationForm]::FormC)
}

$lookup = @{}
foreach ($f in $fixtures) {
  $lookup["$(Norm $f.h)|$(Norm $f.a)"] = $f.id
}

function FindFid($h, $a) {
  $nh = Norm $h; $na = Norm $a
  if ($lookup.ContainsKey("$nh|$na")) { return @{id=$lookup["$nh|$na"]; swap=$false} }
  if ($lookup.ContainsKey("$na|$nh")) { return @{id=$lookup["$na|$nh"]; swap=$true} }
  return $null
}

# Knockout stage → ID prefix mapping
$koPrefix = @{
  'ROUND_OF_32'    = @{prefix='R32'; pad=2; singleton=$false}
  'ROUND_OF_16'    = @{prefix='R16'; pad=0; singleton=$false}
  'QUARTER_FINALS' = @{prefix='QF';  pad=0; singleton=$false}
  'SEMI_FINALS'    = @{prefix='SF';  pad=0; singleton=$false}
  'THIRD_PLACE'    = @{prefix='TP';  pad=0; singleton=$true}
  'FINAL'          = @{prefix='FIN'; pad=0; singleton=$true}
}

Write-Host "Fetching WC26 matches..."
$res = Invoke-WebRequest -Uri "https://api.football-data.org/v4/competitions/WC/matches" `
  -Headers @{ 'X-Auth-Token' = $token } -UseBasicParsing
$matches = ($res.Content | ConvertFrom-Json).matches

# ── Group stage scores ─────────────────────────────────────────────────────
$updated = 0
foreach ($m in $matches) {
  if ($m.stage -ne 'GROUP_STAGE') { continue }
  $st = $m.status
  if ($st -notin @('IN_PLAY','PAUSED','LIVE','FINISHED')) { continue }

  $apiH = if ($m.homeTeam.name) { $m.homeTeam.name } else { $m.homeTeam.shortName }
  $apiA = if ($m.awayTeam.name) { $m.awayTeam.name } else { $m.awayTeam.shortName }

  $result = FindFid $apiH $apiA
  if (-not $result) { Write-Warning "No fixture for: $apiH vs $apiA"; continue }
  $fid = $result.id

  $scoreH = $m.score.fullTime.home
  $scoreA = $m.score.fullTime.away
  if ($null -eq $scoreH -or $null -eq $scoreA) { continue }

  if ($result.swap) { $tmp = $scoreH; $scoreH = $scoreA; $scoreA = $tmp }

  $body = "{`"h`":$scoreH,`"a`":$scoreA,`"status`":`"$st`"}"
  Invoke-WebRequest -Uri "$fbBase/scores/$fid.json" -Method Put -Body $body `
    -ContentType 'application/json' -UseBasicParsing | Out-Null
  Write-Host "  $fid : $scoreH-$scoreA [$st]"
  $updated++
}
Write-Host "Group stage: updated $updated scores."

# ── Knockout stage — ESPN API (has teams before football-data.org does) ────
$espnBase2 = 'https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard'

# Stage definitions: UTC date boundaries and ID format
$espnStages = @(
  @{prefix='R32'; pad=2; singleton=$false; start=[datetime]'2026-06-29T00:00:00Z'; end=[datetime]'2026-07-04T12:00:00Z'},
  @{prefix='R16'; pad=0; singleton=$false; start=[datetime]'2026-07-04T12:00:00Z'; end=[datetime]'2026-07-09T00:00:00Z'},
  @{prefix='QF';  pad=0; singleton=$false; start=[datetime]'2026-07-09T00:00:00Z'; end=[datetime]'2026-07-13T00:00:00Z'},
  @{prefix='SF';  pad=0; singleton=$false; start=[datetime]'2026-07-13T00:00:00Z'; end=[datetime]'2026-07-17T12:00:00Z'},
  @{prefix='TP';  pad=0; singleton=$true;  start=[datetime]'2026-07-17T12:00:00Z'; end=[datetime]'2026-07-19T12:00:00Z'},
  @{prefix='FIN'; pad=0; singleton=$true;  start=[datetime]'2026-07-19T12:00:00Z'; end=[datetime]'2026-07-21T00:00:00Z'}
)

# Fetch all ESPN KO events once across the full date range
$espnDates = @('20260629','20260630','20260701','20260702','20260703','20260704',
               '20260705','20260706','20260707','20260708',
               '20260711','20260712','20260715','20260716','20260718','20260719')
$allEspnEvents = [System.Collections.Generic.List[object]]::new()
$seenEventIds  = @{}
foreach ($d in $espnDates) {
  try {
    $er = Invoke-WebRequest -Uri "${espnBase2}?dates=$d" -UseBasicParsing
    $evs = ($er.Content | ConvertFrom-Json).events
    foreach ($ev in $evs) {
      if ($seenEventIds[$ev.id]) { continue }
      $seenEventIds[$ev.id] = $true
      $allEspnEvents.Add($ev)
    }
  } catch { Write-Warning "ESPN fetch failed for $d : $($_.Exception.Message)" }
}

# Sort by UTC date
$espnSorted = $allEspnEvents | Sort-Object { [datetime]$_.date }

$koTeams = 0; $koUpdated = 0
foreach ($stageDef in $espnStages) {
  $stageEvents = $espnSorted | Where-Object {
    $dt = [datetime]$_.date
    $dt -ge $stageDef.start -and $dt -lt $stageDef.end
  }
  $idx = 0
  foreach ($ev in $stageEvents) {
    $comp = $ev.competitions[0]
    $hComp = $comp.competitors | Where-Object { $_.homeAway -eq 'home' }
    $aComp = $comp.competitors | Where-Object { $_.homeAway -eq 'away' }
    $hName = $hComp.team.displayName
    $aName = $aComp.team.displayName

    # Skip placeholder/TBD entries
    if (-not $hName -or -not $aName -or $hName -match 'Winner|TBD|Loser' -or $aName -match 'Winner|TBD|Loser') { continue }

    $fid = if ($stageDef.singleton) { $stageDef.prefix } `
           elseif ($stageDef.pad -gt 0) { "$($stageDef.prefix)-$($($idx+1).ToString().PadLeft($stageDef.pad,'0'))" } `
           else { "$($stageDef.prefix)-$($idx+1)" }
    $idx++

    $normH = Norm $hName; $normA = Norm $aName
    $tb = "{`"h`":`"$normH`",`"a`":`"$normA`"}"
    Invoke-WebRequest -Uri "$fbBase/koTeams/$fid.json" -Method Put -Body $tb `
      -ContentType 'application/json' -UseBasicParsing | Out-Null
    Write-Host "  $fid teams: $normH vs $normA"
    $koTeams++

    # Score (ESPN: STATUS_FINAL = finished, check for ET via period scores)
    $st = $comp.status.type.name
    if ($st -in @('STATUS_FINAL','STATUS_FULL_TIME','STATUS_IN_PROGRESS','STATUS_HALFTIME','STATUS_END_PERIOD')) {
      # Use linescores to detect ET: more than 2 regular periods means ET played
      $periods = $comp.linescores
      $scoreH = [int]$hComp.score; $scoreA = [int]$aComp.score
      $fbSt   = if ($st -eq 'STATUS_FINAL' -or $st -eq 'STATUS_FULL_TIME') { 'FINISHED' } else { 'IN_PLAY' }
      $body   = "{`"h`":$scoreH,`"a`":$scoreA,`"status`":`"$fbSt`"}"
      Invoke-WebRequest -Uri "$fbBase/scores/$fid.json" -Method Put -Body $body `
        -ContentType 'application/json' -UseBasicParsing | Out-Null
      Write-Host "  $fid score: $scoreH-$scoreA [$fbSt]"
      $koUpdated++
    }
  }
}
Write-Host "Knockout: $koTeams team slots set, $koUpdated scores updated."

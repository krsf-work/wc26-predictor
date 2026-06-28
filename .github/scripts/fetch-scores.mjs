// WC26 Predictor — server-side score fetcher
// Runs as a GitHub Actions cron; writes directly to Firebase REST (no auth needed
// for the scores node — rules have ".write": true on scores).

const FDORG_TOKEN = process.env.FDORG_TOKEN;
const FIREBASE_DB = 'https://world-cup-score-predictor-default-rtdb.asia-southeast1.firebasedatabase.app';

if (!FDORG_TOKEN) { console.error('FDORG_TOKEN not set'); process.exit(1); }

// Map football-data.org team names → our fixture shorthand
const TEAM_MAP = {
  'Korea Republic':            'South Korea',
  'Czech Republic':            'Czechia',
  'United States':             'USA',
  'Turkey':                    'Türkiye',
  "Côte d'Ivoire":             'Ivory Coast',
  'IR Iran':                   'Iran',
  'Bosnia and Herzegovina':    'Bosnia & Herz.',
  'Bosnia-Herzegovina':        'Bosnia & Herz.',
  'Cape Verde Islands':        'Cape Verde',
  'Democratic Republic of Congo': 'DR Congo',
  'Congo DR':                  'DR Congo',
  'Curacao':                   'Curaçao',
};

// All 72 group-stage fixtures (home | away → our fixture ID)
const FX = [
  {id:'A1',h:'Mexico',a:'South Africa'},
  {id:'A2',h:'South Korea',a:'Czechia'},
  {id:'B1',h:'Canada',a:'Bosnia & Herz.'},
  {id:'D1',h:'USA',a:'Paraguay'},
  {id:'B2',h:'Qatar',a:'Switzerland'},
  {id:'C1',h:'Brazil',a:'Morocco'},
  {id:'C2',h:'Haiti',a:'Scotland'},
  {id:'D2',h:'Australia',a:'Türkiye'},
  {id:'E1',h:'Germany',a:'Curaçao'},
  {id:'F1',h:'Netherlands',a:'Japan'},
  {id:'E2',h:'Ivory Coast',a:'Ecuador'},
  {id:'F2',h:'Tunisia',a:'Sweden'},
  {id:'H1',h:'Spain',a:'Cape Verde'},
  {id:'G1',h:'Belgium',a:'Egypt'},
  {id:'H2',h:'Saudi Arabia',a:'Uruguay'},
  {id:'G2',h:'Iran',a:'New Zealand'},
  {id:'I1',h:'France',a:'Senegal'},
  {id:'I2',h:'Norway',a:'Iraq'},
  {id:'J1',h:'Argentina',a:'Algeria'},
  {id:'J2',h:'Austria',a:'Jordan'},
  {id:'K1',h:'Portugal',a:'DR Congo'},
  {id:'L1',h:'England',a:'Croatia'},
  {id:'L2',h:'Ghana',a:'Panama'},
  {id:'K2',h:'Uzbekistan',a:'Colombia'},
  {id:'A3',h:'South Africa',a:'Czechia'},
  {id:'B3',h:'Switzerland',a:'Bosnia & Herz.'},
  {id:'B4',h:'Canada',a:'Qatar'},
  {id:'A4',h:'Mexico',a:'South Korea'},
  {id:'D3',h:'USA',a:'Australia'},
  {id:'C3',h:'Scotland',a:'Morocco'},
  {id:'C4',h:'Brazil',a:'Haiti'},
  {id:'D4',h:'Paraguay',a:'Türkiye'},
  {id:'F3',h:'Netherlands',a:'Sweden'},
  {id:'E3',h:'Germany',a:'Ivory Coast'},
  {id:'E4',h:'Ecuador',a:'Curaçao'},
  {id:'F4',h:'Tunisia',a:'Japan'},
  {id:'H3',h:'Spain',a:'Saudi Arabia'},
  {id:'G3',h:'Belgium',a:'Iran'},
  {id:'H4',h:'Uruguay',a:'Cape Verde'},
  {id:'G4',h:'New Zealand',a:'Egypt'},
  {id:'J3',h:'Argentina',a:'Austria'},
  {id:'I3',h:'France',a:'Iraq'},
  {id:'I4',h:'Norway',a:'Senegal'},
  {id:'J4',h:'Jordan',a:'Algeria'},
  {id:'K3',h:'Portugal',a:'Uzbekistan'},
  {id:'L3',h:'England',a:'Ghana'},
  {id:'L4',h:'Panama',a:'Croatia'},
  {id:'K4',h:'Colombia',a:'DR Congo'},
  {id:'B5',h:'Canada',a:'Switzerland'},
  {id:'B6',h:'Qatar',a:'Bosnia & Herz.'},
  {id:'C5',h:'Scotland',a:'Brazil'},
  {id:'C6',h:'Morocco',a:'Haiti'},
  {id:'A5',h:'Mexico',a:'Czechia'},
  {id:'A6',h:'South Korea',a:'South Africa'},
  {id:'E5',h:'Ecuador',a:'Germany'},
  {id:'E6',h:'Curaçao',a:'Ivory Coast'},
  {id:'F5',h:'Tunisia',a:'Netherlands'},
  {id:'F6',h:'Japan',a:'Sweden'},
  {id:'D5',h:'USA',a:'Türkiye'},
  {id:'D6',h:'Paraguay',a:'Australia'},
  {id:'I5',h:'Norway',a:'France'},
  {id:'I6',h:'Senegal',a:'Iraq'},
  {id:'H5',h:'Uruguay',a:'Spain'},
  {id:'H6',h:'Cape Verde',a:'Saudi Arabia'},
  {id:'G5',h:'New Zealand',a:'Belgium'},
  {id:'G6',h:'Egypt',a:'Iran'},
  {id:'L5',h:'Panama',a:'England'},
  {id:'L6',h:'Croatia',a:'Ghana'},
  {id:'K5',h:'Colombia',a:'Portugal'},
  {id:'K6',h:'Uzbekistan',a:'DR Congo'},
  {id:'J5',h:'Jordan',a:'Argentina'},
  {id:'J6',h:'Algeria',a:'Austria'},
];

function norm(name) {
  const mapped = TEAM_MAP[name] || name;
  return mapped.normalize('NFC');
}

const FX_LOOKUP = {};
for (const f of FX) {
  FX_LOOKUP[`${norm(f.h)}|${norm(f.a)}`] = f.id;
}

function findFid(apiHome, apiAway) {
  const h = norm(apiHome), a = norm(apiAway);
  if (FX_LOOKUP[`${h}|${a}`]) return { fid: FX_LOOKUP[`${h}|${a}`], swap: false };
  if (FX_LOOKUP[`${a}|${h}`]) return { fid: FX_LOOKUP[`${a}|${h}`], swap: true };
  return null;
}

// Knockout stage prefix config
const KO_PREFIX = {
  'ROUND_OF_32':    { prefix: 'R32', pad: 2, singleton: false },
  'ROUND_OF_16':    { prefix: 'R16', pad: 0, singleton: false },
  'QUARTER_FINALS': { prefix: 'QF',  pad: 0, singleton: false },
  'SEMI_FINALS':    { prefix: 'SF',  pad: 0, singleton: false },
  'THIRD_PLACE':    { prefix: 'TP',  pad: 0, singleton: true  },
  'FINAL':          { prefix: 'FIN', pad: 0, singleton: true  },
};

async function fbPut(path, body) {
  const r = await fetch(`${FIREBASE_DB}/${path}.json`, {
    method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  if (!r.ok) console.error(`  ✗ Firebase ${path} failed (${r.status})`);
  return r.ok;
}

async function main() {
  console.log('Fetching WC26 matches from football-data.org...');
  const res = await fetch('https://api.football-data.org/v4/competitions/WC/matches', {
    headers: { 'X-Auth-Token': FDORG_TOKEN }
  });

  if (!res.ok) {
    console.error('API error:', res.status, await res.text());
    process.exit(1);
  }

  const { matches } = await res.json();
  let updated = 0, skipped = 0, koTeams = 0, koScores = 0;

  // ── Group stage ────────────────────────────────────────────────────────
  for (const m of matches) {
    if (m.stage !== 'GROUP_STAGE') continue;
    const st = m.status;
    if (!['IN_PLAY', 'PAUSED', 'LIVE', 'FINISHED'].includes(st)) continue;

    const apiHome = m.homeTeam?.name || m.homeTeam?.shortName;
    const apiAway = m.awayTeam?.name || m.awayTeam?.shortName;
    if (!apiHome || !apiAway) continue;

    const found = findFid(apiHome, apiAway);
    if (!found) { console.warn(`  ⚠ No fixture for: "${apiHome}" vs "${apiAway}"`); skipped++; continue; }
    const { fid, swap } = found;

    const apiH = m.score?.fullTime?.home;
    const apiA = m.score?.fullTime?.away;
    if (apiH == null || apiA == null) continue;

    const h = swap ? apiA : apiH;
    const a = swap ? apiH : apiA;
    if (await fbPut(`scores/${fid}`, { h, a, status: st })) {
      console.log(`  ✓ ${fid}: ${apiHome} ${h}-${a} ${apiAway} [${st}]`);
      updated++;
    }
  }
  console.log(`Group stage: ${updated} updated, ${skipped} skipped.`);

  // ── Knockout stage ─────────────────────────────────────────────────────
  const koByStage = {};
  for (const m of matches) {
    const cfg = KO_PREFIX[m.stage];
    if (!cfg) continue;
    if (!koByStage[m.stage]) koByStage[m.stage] = [];
    koByStage[m.stage].push(m);
  }

  for (const [stage, cfg] of Object.entries(KO_PREFIX)) {
    const list = (koByStage[stage] || []).sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate));
    for (let i = 0; i < list.length; i++) {
      const m = list[i];
      const fid = cfg.singleton ? cfg.prefix
        : cfg.pad > 0 ? `${cfg.prefix}-${String(i + 1).padStart(cfg.pad, '0')}`
        : `${cfg.prefix}-${i + 1}`;

      const apiHome = m.homeTeam?.name || m.homeTeam?.shortName || '';
      const apiAway = m.awayTeam?.name || m.awayTeam?.shortName || '';

      // Write team names whenever known (not just when playing)
      if (apiHome && apiAway && apiHome.trim() && apiAway.trim()) {
        const h = norm(apiHome), a = norm(apiAway);
        if (await fbPut(`koTeams/${fid}`, { h, a })) {
          console.log(`  ✓ ${fid} teams: ${h} vs ${a}`);
          koTeams++;
        }
      }

      // Write score when available; use ET score if match went to extra time
      const st = m.status;
      if (['IN_PLAY', 'PAUSED', 'LIVE', 'FINISHED'].includes(st)) {
        const dur = m.score?.duration;
        const useET = dur === 'EXTRA_TIME' || dur === 'PENALTY_SHOOTOUT';
        const h = (useET ? m.score?.extraTime?.home : null) ?? m.score?.fullTime?.home;
        const a = (useET ? m.score?.extraTime?.away : null) ?? m.score?.fullTime?.away;
        if (h != null && a != null) {
          if (await fbPut(`scores/${fid}`, { h, a, status: st })) {
            console.log(`  ✓ ${fid} score: ${h}-${a} [${st}]`);
            koScores++;
          }
        }
      }
    }
  }
  console.log(`Knockout: ${koTeams} team slots, ${koScores} scores updated.`);
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });

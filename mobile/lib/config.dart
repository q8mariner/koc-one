// ONE · connection settings (publishable key; data is protected by Row Level Security).
const supabaseUrl = 'https://jrtpdchuephpkhshdzec.supabase.co';
const supabaseKey = 'sb_publishable_iNYynnynGIp0jmV2kodkLg_zUSI0ozW';

// Add a TURN server for calls through strict corporate NAT.
const iceServers = <Map<String, dynamic>>[
  {
    'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']
  }
];

const ecc160Number = '160';

// KOC ONE · Supabase connection (publishable key — safe for the browser; data is protected by RLS)
window.KOC_CONFIG = {
  SUPABASE_URL: "https://jrtpdchuephpkhshdzec.supabase.co",
  SUPABASE_KEY: "sb_publishable_iNYynnynGIp0jmV2kodkLg_zUSI0ozW",
  // Add a TURN server here for calls across strict corporate NAT / firewalls.
  ICE_SERVERS: [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }],
  MAP_CENTER: [29.0769, 48.0838], // Ahmadi
};

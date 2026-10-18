// End-to-end report encryption (WebCrypto).
// Phone: AES-256-GCM per report, key wrapped with ORT RSA-OAEP(SHA-1) public key.
// Blob format everywhere: base64( iv[12] | ciphertext | tag[16] ).
window.KocCrypto = (() => {
  const enc = new TextEncoder(), dec = new TextDecoder();
  const b64 = (buf) => { let s = ""; const b = new Uint8Array(buf); for (let i = 0; i < b.length; i++) s += String.fromCharCode(b[i]); return btoa(s); };
  const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const RSA = { name: "RSA-OAEP", hash: "SHA-1" };

  async function passKey(pass, salt) {
    const base = await crypto.subtle.importKey("raw", enc.encode(pass), "PBKDF2", false, ["deriveKey"]);
    return crypto.subtle.deriveKey({ name: "PBKDF2", salt, iterations: 210000, hash: "SHA-256" },
      base, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
  }

  // Create the organisation key pair; private key leaves the browser only encrypted with the passphrase.
  async function createOrgKeys(passphrase) {
    const pair = await crypto.subtle.generateKey({ ...RSA, modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]) }, true, ["encrypt", "decrypt"]);
    const pub = await crypto.subtle.exportKey("jwk", pair.publicKey);
    const priv = await crypto.subtle.exportKey("jwk", pair.privateKey);
    const salt = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12));
    const k = await passKey(passphrase, salt);
    const wrapped = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, k, enc.encode(JSON.stringify(priv)));
    return { publicJwk: { kty: pub.kty, n: pub.n, e: pub.e, alg: "RSA-OAEP" }, wrapped: b64(wrapped), salt: b64(salt), iv: b64(iv), privateKey: pair.privateKey };
  }

  async function unlock(row, passphrase) {
    const k = await passKey(passphrase, unb64(row.salt));
    const raw = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(row.iv) }, k, unb64(row.wrapped));
    return crypto.subtle.importKey("jwk", JSON.parse(dec.decode(raw)), RSA, false, ["decrypt"]);
  }

  async function reportKey(privateKey, wrappedKey) {
    const raw = await crypto.subtle.decrypt(RSA, privateKey, unb64(wrappedKey));
    return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["decrypt"]);
  }

  async function openBytes(aesKey, bytes) {
    const iv = bytes.slice(0, 12), body = bytes.slice(12);
    return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, aesKey, body));
  }

  async function decryptReport(privateKey, report) {
    const key = await reportKey(privateKey, report.wrapped_key);
    const json = dec.decode(await openBytes(key, unb64(report.enc_payload)));
    return { key, payload: JSON.parse(json) };
  }

  return { createOrgKeys, unlock, decryptReport, openBytes, b64, unb64 };
})();

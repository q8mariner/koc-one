// Voice call from ORT to an employee: WebRTC audio, signalling over Supabase Realtime broadcast.
// Protocol (shared with the Flutter app), channel "call-<id>":
//   callee → 'ready'   · caller → 'offer' {sdp,type} · callee → 'answer' {sdp,type}
//   both   → 'ice' {candidate,sdpMid,sdpMLineIndex} · either → 'hangup'
// ICE servers (STUN + TURN relay) come from the ice-servers Edge Function so calls work behind carrier NAT.
window.KocCall = function (sb, onState) {
  let pc, channel, stream, callRow, rowSub, timer, pending = [], ended = false;
  // A real <audio> element in the page, played explicitly: detached or autoplay-only elements can stay silent.
  const audio = document.createElement("audio");
  audio.autoplay = true; audio.setAttribute("playsinline", ""); audio.style.display = "none";
  document.body.appendChild(audio);
  const state = (s) => onState && onState(s);

  async function iceServers() {
    try {
      const { data } = await sb.functions.invoke("ice-servers", { body: {} });
      if (data && Array.isArray(data.iceServers)) return data.iceServers;
    } catch (_) {}
    return window.KOC_CONFIG.ICE_SERVERS;
  }

  async function start(calleeId, callerName) {
    stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    const servers = await iceServers();
    const { data, error } = await sb.from("calls").insert({ callee_id: calleeId, caller_name: callerName }).select().single();
    if (error) throw error;
    callRow = data; state("ringing");

    pc = new RTCPeerConnection({ iceServers: servers });
    stream.getTracks().forEach((t) => pc.addTrack(t, stream));
    pc.ontrack = (e) => {
      audio.srcObject = e.streams[0] || new MediaStream([e.track]);
      audio.play().catch(() => {});
    };
    pc.onicecandidate = (e) => e.candidate && send("ice", { candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex });
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "connected") { state("connected"); audio.play().catch(() => {}); }
      if (pc.connectionState === "failed") end("failed");
    };

    channel = sb.channel("call-" + callRow.id, { config: { broadcast: { self: false } } });
    channel
      .on("broadcast", { event: "ready" }, async () => {
        clearTimeout(timer); state("connecting");
        const offer = await pc.createOffer({ offerToReceiveAudio: true });
        await pc.setLocalDescription(offer);
        send("offer", { sdp: offer.sdp, type: offer.type });
        // if media never connects, don't leave the call hanging
        timer = setTimeout(() => { if (pc && pc.connectionState !== "connected") end("failed"); }, 30000);
      })
      .on("broadcast", { event: "answer" }, async ({ payload }) => {
        await pc.setRemoteDescription(payload);
        for (const c of pending.splice(0)) { try { await pc.addIceCandidate(c); } catch (_) {} }
      })
      .on("broadcast", { event: "ice" }, async ({ payload }) => {
        if (!pc.remoteDescription) return pending.push(payload);
        try { await pc.addIceCandidate(payload); } catch (_) {}
      })
      .on("broadcast", { event: "hangup" }, () => end("ended", false))
      .subscribe();

    rowSub = sb.channel("callrow-" + callRow.id)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "calls", filter: "id=eq." + callRow.id },
        ({ new: r }) => { if (r.status === "rejected") end("rejected", false); })
      .subscribe();

    // 60 s to answer: the phone's background service checks for calls every 5 s even when the app is closed
    timer = setTimeout(() => end("missed"), 60000);
  }

  function send(event, payload) { channel && channel.send({ type: "broadcast", event, payload }); }

  async function end(status = "ended", notify = true) {
    if (ended) return; ended = true;
    clearTimeout(timer);
    if (notify) send("hangup", {});
    try { pc && pc.close(); } catch (_) {}
    stream && stream.getTracks().forEach((t) => t.stop());
    try { audio.pause(); audio.srcObject = null; audio.remove(); } catch (_) {}
    if (callRow) await sb.from("calls").update({ status, ended_at: new Date().toISOString() }).eq("id", callRow.id);
    channel && sb.removeChannel(channel); rowSub && sb.removeChannel(rowSub);
    pc = channel = stream = rowSub = null;
    state(status);
  }

  function mute(on) { stream && stream.getAudioTracks().forEach((t) => (t.enabled = !on)); }
  return { start, end, mute };
};

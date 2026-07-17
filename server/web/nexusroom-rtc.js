'use strict';

// NexusRoom browser playback adapter. It keeps the small public surface used by
// player.html while negotiating directly with the embedded NexusRoom media core.
function NexusRoomRtcPlayer() {
    const self = {
        pc: new RTCPeerConnection(),
        stream: new MediaStream(),
    };

    self.pc.ontrack = function (event) {
        if (!self.stream.getTracks().some(function (track) { return track.id === event.track.id; })) {
            self.stream.addTrack(event.track);
        }
    };

    self.play = async function (streamUrl) {
        self.pc.addTransceiver('video', {direction: 'recvonly'});
        const offer = await self.pc.createOffer();
        await self.pc.setLocalDescription(offer);
        await waitForIceGathering(self.pc);

        const response = await fetch('/api/v1/web/rtc/play', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                streamurl: streamUrl,
                sdp: self.pc.localDescription.sdp,
            }),
        });
        const session = await response.json();
        if (!response.ok || session.code) {
            throw new Error(session.message || 'WebRTC playback negotiation failed');
        }
        await self.pc.setRemoteDescription({type: 'answer', sdp: session.sdp});
        return session;
    };

    self.close = function () {
        if (self.pc) {
            self.pc.close();
            self.pc = null;
        }
        self.stream.getTracks().forEach(function (track) { track.stop(); });
    };

    return self;
}

function waitForIceGathering(pc) {
    if (pc.iceGatheringState === 'complete') {
        return Promise.resolve();
    }
    return new Promise(function (resolve) {
        const timeout = setTimeout(finish, 8000);
        function finish() {
            clearTimeout(timeout);
            pc.removeEventListener('icegatheringstatechange', onStateChange);
            resolve();
        }
        function onStateChange() {
            if (pc.iceGatheringState === 'complete') {
                finish();
            }
        }
        pc.addEventListener('icegatheringstatechange', onStateChange);
    });
}

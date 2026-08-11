import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ChangeEvent,
  type FormEvent,
  type KeyboardEvent,
  type ReactElement,
} from 'react';
import type { WsConnectionState } from '../main/ws-client';
import type {
  CachedMessage,
  NexusRoomStorageApi,
} from '../shared/preload-api';
import {
  NexusRoomClient,
  NexusRoomClientError,
  type AuthSession,
  type ChatMessage,
  type RoomDetail,
  type RoomIngress,
  type RoomSummary,
  type VlanSnapshot,
} from './nexusroom-client';
import {
  LivePlayer,
  type LivePlayerSnapshot,
} from './live-player';
import {
  WebRtcVoiceClient,
  type VoiceConnectionState,
  type VoiceMicrophoneState,
  type VoiceParticipant,
  type VoiceSnapshot,
} from './voice-client';

type Theme = 'dark' | 'light';

const DEFAULT_SERVER_URL = 'http://127.0.0.1:8080';

const emptyStorage: NexusRoomStorageApi = {
  getSetting: async () => null,
  setSetting: async () => undefined,
  getSession: async () => null,
  saveSession: async () => undefined,
  removeSession: async () => undefined,
  getMessages: async () => [],
  saveMessages: async () => undefined,
  clearMessages: async () => undefined,
  clearData: async () => undefined,
};

function getRendererStorage(): NexusRoomStorageApi {
  if (typeof window !== 'undefined' && window.nexusroom?.storage) {
    return window.nexusroom.storage;
  }
  return emptyStorage;
}

function createClient(serverUrl: string, storage: NexusRoomStorageApi): NexusRoomClient {
  return new NexusRoomClient({
    serverUrl: serverUrl.trim() || DEFAULT_SERVER_URL,
    storage,
  });
}

function errorMessage(error: unknown): string {
  if (error instanceof NexusRoomClientError) return error.message;
  if (error instanceof Error && error.message.length > 0) return error.message;
  return '操作失败，请稍后重试';
}

function toChatMessage(cached: CachedMessage): ChatMessage {
  return {
    id: cached.id,
    roomId: cached.roomId,
    senderId: cached.senderId,
    type: cached.type,
    content: cached.content,
    createdAt: cached.createdAt,
    ...(cached.senderNickname
      ? {
          sender: {
            id: cached.senderId,
            nickname: cached.senderNickname,
            ...(cached.senderAvatarUrl ? { avatarUrl: cached.senderAvatarUrl } : {}),
          },
        }
      : {}),
    ...(cached.meta === undefined ? {} : { meta: cached.meta }),
  };
}

function mergeMessages(current: readonly ChatMessage[], incoming: readonly ChatMessage[]): ChatMessage[] {
  const next = [...current];
  for (const message of incoming) {
    const existingIndex = next.findIndex(
      (item) => item.id === message.id || (
        message.clientMessageId !== undefined &&
        item.clientMessageId === message.clientMessageId
      ),
    );
    if (existingIndex < 0) next.push(message);
    else next[existingIndex] = message;
  }
  return next.sort((left, right) => {
    const leftTime = Date.parse(left.createdAt);
    const rightTime = Date.parse(right.createdAt);
    if (Number.isFinite(leftTime) && Number.isFinite(rightTime) && leftTime !== rightTime) {
      return leftTime - rightTime;
    }
    return left.id - right.id;
  });
}

function connectionLabel(state: WsConnectionState): string {
  if (state === 'connected') return '已连接';
  if (state === 'connecting') return '连接中';
  return '未连接';
}

function voiceConnectionLabel(state: VoiceConnectionState): string {
  if (state === 'connected') return '语音已连接';
  if (state === 'connecting') return '语音连接中';
  if (state === 'reconnecting') return '语音重连中';
  if (state === 'error') return '语音异常';
  return '语音未加入';
}

function microphoneLabel(state: VoiceMicrophoneState): string {
  if (state === 'enabling') return '开麦中…';
  if (state === 'disabling') return '静音中…';
  return state === 'enabled' ? '静音' : '开麦';
}

function vlanStatusLabel(state: VlanSnapshot['state']): string {
  if (state === 'connecting') return '连接中';
  if (state === 'connected') return '已连接';
  if (state === 'disconnecting') return '断开中';
  if (state === 'unavailable') return '不可用';
  if (state === 'error') return '错误';
  return '关闭';
}

function vlanToggleLabel(state: VlanSnapshot['state']): string {
  if (state === 'connecting') return '连接中…';
  if (state === 'disconnecting') return '断开中…';
  if (state === 'connected') return '关闭 VLAN';
  if (state === 'unavailable') return '重试启用 VLAN';
  return '启用 VLAN';
}

function findVoiceParticipant(
  participants: readonly VoiceParticipant[],
  userId: number,
): VoiceParticipant | undefined {
  return participants.find((participant) => participant.userId === userId);
}

const emptyLiveSnapshot: LivePlayerSnapshot = {
  mode: 'idle',
  protocol: null,
  muted: false,
  sourceHasAudio: null,
  flvRetryCount: 0,
  error: null,
};

const emptyVlanSnapshot: VlanSnapshot = {
  state: 'disabled',
  roomId: null,
  peers: [],
  error: null,
};

function liveStatusLabel(snapshot: LivePlayerSnapshot): string {
  if (snapshot.mode === 'connecting') return '连接中';
  if (snapshot.mode === 'autoplay-blocked') return '等待点击恢复';
  if (snapshot.mode === 'error') return '播放异常';
  if (snapshot.protocol === 'flv') return 'FLV 回退';
  if (snapshot.protocol === 'webrtc') return 'WebRTC';
  if (snapshot.mode === 'closed') return '已关闭';
  return '未播放';
}

interface LivePlaybackPanelProps {
  readonly serverUrl: string;
  readonly ingress: RoomIngress;
  readonly onClose: () => void;
}

function LivePlaybackPanel({
  serverUrl,
  ingress,
  onClose,
}: LivePlaybackPanelProps): ReactElement {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const playerRef = useRef<LivePlayer | null>(null);
  const [snapshot, setSnapshot] = useState<LivePlayerSnapshot>(emptyLiveSnapshot);

  useEffect(() => {
    const video = videoRef.current;
    if (video === null) return undefined;
    const player = new LivePlayer({
      serverUrl,
      streamKey: ingress.streamKey,
      video,
    });
    playerRef.current = player;
    setSnapshot(player.snapshot);
    const unsubscribe = player.onChange(setSnapshot);
    void player.start().catch((error: unknown) => {
      setSnapshot((current) => ({
        ...current,
        mode: 'error',
        error: errorMessage(error),
      }));
    });
    return () => {
      unsubscribe();
      player.dispose();
      if (playerRef.current === player) playerRef.current = null;
    };
  }, [ingress.id, ingress.streamKey, serverUrl]);

  const handleRefresh = (): void => {
    void playerRef.current?.refresh().catch((error: unknown) => {
      setSnapshot((current) => ({ ...current, mode: 'error', error: errorMessage(error) }));
    });
  };

  const handleResume = (): void => {
    void playerRef.current?.resume().catch((error: unknown) => {
      setSnapshot((current) => ({ ...current, mode: 'error', error: errorMessage(error) }));
    });
  };

  const handleToggleMute = (): void => {
    playerRef.current?.toggleMuted();
  };

  return (
    <section className="live-player-panel" aria-label="直播播放器">
      <div className="live-player-panel__header">
        <div>
          <p className="eyebrow">直播播放</p>
          <h3>{ingress.label}</h3>
        </div>
        <span
          className="live-player-panel__status"
          data-live-protocol={snapshot.protocol ?? 'none'}
          aria-live="polite"
        >
          {liveStatusLabel(snapshot)}
        </span>
      </div>
      <div className="live-player-panel__video-wrap">
        <video
          ref={videoRef}
          className="live-player-panel__video"
          aria-label={`${ingress.label} 直播画面`}
          playsInline
          autoPlay
        />
        {snapshot.mode === 'connecting' ? <span className="live-player-panel__overlay">正在连接直播</span> : null}
        {snapshot.mode === 'autoplay-blocked' ? (
          <button className="live-player-panel__overlay live-player-panel__overlay--button" type="button" onClick={handleResume}>
            点击恢复播放
          </button>
        ) : null}
      </div>
      {snapshot.error !== null ? <p className="live-player-panel__error" role="status">{snapshot.error}</p> : null}
      <div className="live-player-panel__controls">
        <span className="muted-copy">协议：{snapshot.protocol === 'flv' ? 'FLV' : snapshot.protocol === 'webrtc' ? 'WebRTC' : '等待中'}</span>
        <button className="voice-button" type="button" onClick={handleToggleMute} aria-pressed={snapshot.muted}>
          {snapshot.muted ? '取消直播静音' : '直播静音'}
        </button>
        <button className="voice-button" type="button" onClick={handleRefresh}>刷新播放</button>
        <button className="text-button" type="button" onClick={onClose}>关闭播放</button>
      </div>
    </section>
  );
}

export function App(): ReactElement {
  const storage = useMemo(getRendererStorage, []);
  const [theme, setTheme] = useState<Theme>('dark');
  const [themeReady, setThemeReady] = useState(false);
  const [serverUrl, setServerUrl] = useState(DEFAULT_SERVER_URL);
  const [serverUrlDraft, setServerUrlDraft] = useState(DEFAULT_SERVER_URL);
  const [client, setClient] = useState(() => createClient(DEFAULT_SERVER_URL, storage));
  const voice = useMemo(
    () => new WebRtcVoiceClient({ signaling: client }),
    [client],
  );
  const [voiceSnapshot, setVoiceSnapshot] = useState<VoiceSnapshot>(() => voice.snapshot);
  const [session, setSession] = useState<AuthSession | null>(null);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [loginBusy, setLoginBusy] = useState(false);
  const [rooms, setRooms] = useState<readonly RoomSummary[]>([]);
  const [selectedRoomId, setSelectedRoomId] = useState<number | null>(null);
  const [roomDetail, setRoomDetail] = useState<RoomDetail | null>(null);
  const [ingresses, setIngresses] = useState<readonly RoomIngress[]>([]);
  const [selectedIngressId, setSelectedIngressId] = useState<number | null>(null);
  const [ingressLabelDraft, setIngressLabelDraft] = useState('');
  const [ingressActionBusy, setIngressActionBusy] = useState(false);
  const [messages, setMessages] = useState<readonly ChatMessage[]>([]);
  const [messageDraft, setMessageDraft] = useState('');
  const [sendingMessage, setSendingMessage] = useState(false);
  const [sendingImage, setSendingImage] = useState(false);
  const [roomNameDraft, setRoomNameDraft] = useState('');
  const [inviteDraft, setInviteDraft] = useState('');
  const [roomActionBusy, setRoomActionBusy] = useState(false);
  const [leavingRoom, setLeavingRoom] = useState(false);
  const [connectionState, setConnectionState] = useState<WsConnectionState>('disconnected');
  const [vlanSnapshot, setVlanSnapshot] = useState<VlanSnapshot>(() => client.vlanSnapshot);
  const [vlanRefreshBusy, setVlanRefreshBusy] = useState(false);
  const [vlanCopyError, setVlanCopyError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [imageSources, setImageSources] = useState<Record<number, string>>({});
  const imageUrls = useRef(new Map<number, string>());
  const selectedRoomIdRef = useRef<number | null>(null);
  const ingressRequestGeneration = useRef(0);

  useEffect(() => {
    selectedRoomIdRef.current = selectedRoomId;
  }, [selectedRoomId]);

  useEffect(() => {
    let active = true;
    void Promise.all([
      storage.getSetting('theme'),
      storage.getSetting('server_url'),
      storage.getSetting('account_id'),
      storage.getSetting('user_display_id'),
    ]).then(async ([savedTheme, savedServerUrl, savedAccountId, savedDisplayId]) => {
      if (!active) return;
      if (savedTheme === 'light' || savedTheme === 'dark') setTheme(savedTheme);
      let savedClient = client;
      if (typeof savedServerUrl === 'string' && savedServerUrl.trim().length > 0) {
        setServerUrlDraft(savedServerUrl);
        try {
          savedClient = createClient(savedServerUrl, storage);
          setServerUrl(savedClient.serverUrl);
          setClient(savedClient);
        } catch {
          setServerUrlDraft(DEFAULT_SERVER_URL);
        }
      }
      const accountId = Number(savedAccountId);
      if (Number.isSafeInteger(accountId) && accountId > 0) {
        const persistedSession = await storage.getSession({
          serverUrl: savedClient.serverUrl,
          accountId,
        });
        if (persistedSession !== null && active) {
          try {
            const restoredSession = savedClient.restoreSession(
              accountId,
              persistedSession.accessToken,
              savedDisplayId ?? undefined,
            );
            setClient(savedClient);
            setSession(restoredSession);
          } catch {
            if (active) setError('保存的登录已失效，请重新登录');
          }
        }
      }
      if (active) setThemeReady(true);
    }).catch(() => {
      if (active) setThemeReady(true);
    });
    return () => {
      active = false;
    };
  }, [storage]);

  useEffect(() => {
    if (themeReady) void storage.setSetting('theme', theme);
  }, [storage, theme, themeReady]);

  useEffect(() => {
    setConnectionState(client.socket.state);
    return client.socket.onStateChange(setConnectionState);
  }, [client]);

  useEffect(() => {
    setVlanSnapshot(client.vlanSnapshot);
    return client.onVlanStateChange((snapshot) => {
      setVlanSnapshot(snapshot);
      if (snapshot.error !== null) setError(snapshot.error);
    });
  }, [client]);

  useEffect(() => {
    return () => {
      client.disconnect();
    };
  }, [client]);

  useEffect(() => {
    setVoiceSnapshot(voice.snapshot);
    return voice.onChange((snapshot) => {
      setVoiceSnapshot(snapshot);
      if (snapshot.error !== null) setError(snapshot.error);
    });
  }, [voice]);

  useEffect(() => {
    return () => {
      void voice.dispose();
    };
  }, [voice]);

  const loadRooms = useCallback(async (targetClient: NexusRoomClient = client): Promise<readonly RoomSummary[]> => {
    const loadedRooms = await targetClient.listRooms();
    setRooms(loadedRooms);
    setSelectedRoomId((current) => {
      if (current !== null && loadedRooms.some((room) => room.id === current)) return current;
      return loadedRooms[0]?.id ?? null;
    });
    return loadedRooms;
  }, [client]);

  const loadIngresses = useCallback(async (roomId: number, targetClient: NexusRoomClient = client): Promise<readonly RoomIngress[]> => {
    const requestGeneration = ++ingressRequestGeneration.current;
    const loadedIngresses = await targetClient.listRoomIngresses(roomId);
    if (requestGeneration !== ingressRequestGeneration.current || selectedRoomIdRef.current !== roomId) {
      return loadedIngresses;
    }
    setIngresses(loadedIngresses);
    setSelectedIngressId((current) => (
      current !== null && loadedIngresses.some((ingress) => ingress.id === current)
        ? current
        : null
    ));
    return loadedIngresses;
  }, [client]);

  const handleLogin = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (loginBusy) return;
    setError(null);
    const targetUrl = serverUrlDraft.trim() || DEFAULT_SERVER_URL;
    let activeClient = client;
    try {
      activeClient = createClient(targetUrl, storage);
    } catch (loginError) {
      setError(errorMessage(loginError));
      return;
    }
    setLoginBusy(true);
    try {
      const nextSession = await activeClient.login(username.trim(), password);
      await storage.setSetting('server_url', activeClient.serverUrl);
      await storage.setSetting('account_id', String(nextSession.userId));
      await storage.setSetting('user_display_id', nextSession.userDisplayId);
      setServerUrl(activeClient.serverUrl);
      setServerUrlDraft(activeClient.serverUrl);
      setClient(activeClient);
      setSession(nextSession);
      setIngresses([]);
      setSelectedIngressId(null);
      setPassword('');
    } catch (loginError) {
      activeClient.disconnect();
      setError(errorMessage(loginError));
    } finally {
      setLoginBusy(false);
    }
  };

  useEffect(() => {
    if (session === null) return undefined;
    let active = true;
    const cleanupVlan = (roomId: number | null): void => {
      if (roomId === null) return;
      void client.leaveVlan(roomId).then(() => {
        const cleanupError = client.vlanSnapshot.error;
        if (active && cleanupError !== null) setError(cleanupError);
      }).catch((vlanError: unknown) => {
        if (active) setError(errorMessage(vlanError));
      });
    };
    const unsubscribeChat = client.onChatMessage((message) => {
      const currentRoomId = selectedRoomIdRef.current;
      if (!active || currentRoomId === null || message.roomId !== currentRoomId) return;
      setMessages((current) => mergeMessages(current, [message]));
    });
    const unsubscribeKicked = client.onKicked((event) => {
      const currentRoomId = selectedRoomIdRef.current;
      if (event.roomId === undefined || event.roomId === currentRoomId) {
        cleanupVlan(currentRoomId);
        setError(event.reason || '你已被移出房间');
        setSelectedRoomId(null);
        setRoomDetail(null);
        setIngresses([]);
        setSelectedIngressId(null);
      }
    });
    const unsubscribeDisbanded = client.onDisbanded((event) => {
      if (event.roomId !== selectedRoomIdRef.current) return;
      cleanupVlan(selectedRoomIdRef.current);
      setError('房间已解散');
      setSelectedRoomId(null);
      setRoomDetail(null);
      setIngresses([]);
      setSelectedIngressId(null);
      void loadRooms().catch(() => undefined);
    });
    const unsubscribeIngress = client.onIngressUpdate((event) => {
      if (!active || event.roomId !== selectedRoomIdRef.current) return;
      void loadIngresses(event.roomId).catch((ingressError) => {
        if (active) setError(errorMessage(ingressError));
      });
    });
    const unsubscribeVlan = client.onVlanPeerUpdate((event) => {
      if (!active || event.roomId !== selectedRoomIdRef.current) return;
      void client.refreshVlanPeers(event.roomId).catch((vlanError) => {
        if (active) setError(errorMessage(vlanError));
      });
    });
    client.connect();
    void loadRooms().catch((loadError) => {
      if (active) setError(errorMessage(loadError));
    });
    return () => {
      active = false;
      unsubscribeChat();
      unsubscribeKicked();
      unsubscribeDisbanded();
      unsubscribeIngress();
      unsubscribeVlan();
    };
  }, [client, loadIngresses, loadRooms, session]);

  useEffect(() => {
    ingressRequestGeneration.current += 1;
    setIngresses([]);
    setSelectedIngressId(null);
    setVlanCopyError(null);
    if (session === null || selectedRoomId === null) {
      void voice.setRoom(null).catch(() => undefined);
      setRoomDetail(null);
      setMessages([]);
      return undefined;
    }
    let active = true;
    const roomId = selectedRoomId;
    setError(null);
    setMessages([]);
    void voice.setRoom(roomId).catch((roomError: unknown) => {
      if (active) setError(errorMessage(roomError));
    });
    client.switchRoom(roomId);
    void Promise.all([
      client.getRoomDetail(roomId),
      client.listRoomIngresses(roomId),
      storage.getMessages(session.scope, roomId),
    ]).then(async ([detail, loadedIngresses, cached]) => {
      if (!active) return;
      setRoomDetail(detail);
      setIngresses(loadedIngresses);
      setMessages(cached.map(toChatMessage));
      const fresh = await client.syncMessages(roomId);
      if (active) setMessages((current) => mergeMessages(current, fresh));
    }).catch((roomError) => {
      if (active) setError(errorMessage(roomError));
    });
    return () => {
      active = false;
    };
  }, [client, selectedRoomId, session, storage, voice]);

  useEffect(() => {
    let active = true;
    const imageMessages = messages.filter((message) => message.type === 'image');
    const imageIds = new Set(imageMessages.map((message) => message.id));
    for (const [id, url] of imageUrls.current) {
      if (!imageIds.has(id)) {
        URL.revokeObjectURL(url);
        imageUrls.current.delete(id);
      }
    }
    setImageSources((current) => {
      const next: Record<number, string> = {};
      for (const [id, url] of imageUrls.current) next[id] = url;
      const same = Object.keys(next).length === Object.keys(current).length &&
        Object.entries(next).every(([id, url]) => current[Number(id)] === url);
      return same ? current : next;
    });
    const loadImages = async (): Promise<void> => {
      if (typeof URL.createObjectURL !== 'function') return;
      for (const message of imageMessages) {
        if (imageUrls.current.has(message.id)) continue;
        try {
          const blob = await client.loadImage(message.content);
          if (!active) return;
          const objectUrl = URL.createObjectURL(blob);
          imageUrls.current.set(message.id, objectUrl);
          setImageSources((current) => ({ ...current, [message.id]: objectUrl }));
        } catch {
          // Keep the message row visible even when an image cannot be loaded.
        }
      }
    };
    void loadImages();
    return () => {
      active = false;
    };
  }, [client, messages]);

  useEffect(() => {
    return () => {
      for (const url of imageUrls.current.values()) URL.revokeObjectURL(url);
      imageUrls.current.clear();
    };
  }, []);

  const handleSend = useCallback(async (): Promise<void> => {
    if (sendingMessage || selectedRoomId === null) return;
    const content = messageDraft.trim();
    if (content.length === 0) return;
    setError(null);
    setSendingMessage(true);
    try {
      await client.sendText(selectedRoomId, content);
      setMessageDraft('');
    } catch (sendError) {
      setError(errorMessage(sendError));
    } finally {
      setSendingMessage(false);
    }
  }, [client, messageDraft, selectedRoomId, sendingMessage]);

  const handleComposerKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>): void => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      void handleSend();
    }
  };

  const handleImageChange = async (event: ChangeEvent<HTMLInputElement>): Promise<void> => {
    const file = event.target.files?.[0];
    event.target.value = '';
    if (file === undefined || selectedRoomId === null || sendingImage) return;
    if (!file.type.startsWith('image/')) {
      setError('只能发送图片文件');
      return;
    }
    setError(null);
    setSendingImage(true);
    try {
      await client.sendImage(selectedRoomId, file, {}, file.name);
    } catch (uploadError) {
      setError(errorMessage(uploadError));
    } finally {
      setSendingImage(false);
    }
  };

  const handleCreateRoom = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (roomActionBusy || roomNameDraft.trim().length === 0) return;
    setRoomActionBusy(true);
    setError(null);
    try {
      const created = await client.createRoom(roomNameDraft.trim());
      setRoomNameDraft('');
      await loadRooms();
      setSelectedRoomId(created.id);
    } catch (roomError) {
      setError(errorMessage(roomError));
    } finally {
      setRoomActionBusy(false);
    }
  };

  const handleJoinRoom = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (roomActionBusy || inviteDraft.trim().length === 0) return;
    setRoomActionBusy(true);
    setError(null);
    try {
      const joined = await client.joinRoom(inviteDraft.trim());
      setInviteDraft('');
      await loadRooms();
      setSelectedRoomId(joined.id);
    } catch (roomError) {
      setError(errorMessage(roomError));
    } finally {
      setRoomActionBusy(false);
    }
  };

  const handleCreateIngress = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    const roomId = selectedRoomId;
    const label = ingressLabelDraft.trim();
    if (roomId === null || ingressActionBusy || label.length === 0) return;
    setIngressActionBusy(true);
    setError(null);
    try {
      await client.createRoomIngress(roomId, label);
      setIngressLabelDraft('');
      await loadIngresses(roomId);
    } catch (ingressError) {
      setError(errorMessage(ingressError));
    } finally {
      setIngressActionBusy(false);
    }
  };

  const handleDeleteIngress = async (ingress: RoomIngress): Promise<void> => {
    const roomId = selectedRoomId;
    if (roomId === null || ingressActionBusy) return;
    setIngressActionBusy(true);
    setError(null);
    try {
      await client.deleteRoomIngress(roomId, ingress.id);
      if (selectedIngressId === ingress.id) setSelectedIngressId(null);
      await loadIngresses(roomId);
    } catch (ingressError) {
      setError(errorMessage(ingressError));
    } finally {
      setIngressActionBusy(false);
    }
  };

  const handleVlanToggle = async (): Promise<void> => {
    const roomId = selectedRoomId;
    if (
      roomId === null ||
      vlanSnapshot.state === 'connecting' ||
      vlanSnapshot.state === 'disconnecting'
    ) {
      return;
    }
    setVlanCopyError(null);
    setError(null);
    try {
      if (vlanSnapshot.state === 'connected' && vlanSnapshot.roomId === roomId) {
        await client.leaveVlan(roomId);
        if (client.vlanSnapshot.error !== null) setError(client.vlanSnapshot.error);
      } else {
        await client.joinVlan(roomId);
      }
    } catch (vlanError) {
      setError(errorMessage(vlanError));
    }
  };

  const handleVlanRefresh = async (): Promise<void> => {
    const roomId = selectedRoomId;
    if (
      roomId === null ||
      vlanSnapshot.state !== 'connected' ||
      vlanSnapshot.roomId !== roomId ||
      vlanRefreshBusy
    ) {
      return;
    }
    setVlanRefreshBusy(true);
    setError(null);
    try {
      await client.refreshVlanPeers(roomId);
    } catch (vlanError) {
      setError(errorMessage(vlanError));
    } finally {
      setVlanRefreshBusy(false);
    }
  };

  const handleCopyVlanIp = async (): Promise<void> => {
    const assignedIp = vlanSnapshot.assignedIp;
    if (assignedIp === undefined) return;
    setVlanCopyError(null);
    try {
      if (typeof navigator === 'undefined' || navigator.clipboard === undefined) {
        throw new Error('clipboard unavailable');
      }
      await navigator.clipboard.writeText(assignedIp);
    } catch {
      setVlanCopyError('复制虚拟 IP 失败，请手动复制');
    }
  };

  const handleLeaveRoom = async (): Promise<void> => {
    const roomId = selectedRoomId;
    if (roomId === null || leavingRoom) return;
    setLeavingRoom(true);
    setError(null);
    try {
      await voice.setRoom(null);
      await client.leaveRoom(roomId);
      setSelectedRoomId(null);
      setRoomDetail(null);
      setIngresses([]);
      setSelectedIngressId(null);
      setMessages([]);
      await loadRooms();
    } catch (leaveError) {
      setError(errorMessage(leaveError));
    } finally {
      setLeavingRoom(false);
    }
  };

  const handleLogout = async (): Promise<void> => {
    if (busy) return;
    setBusy(true);
    try {
      await voice.setRoom(null);
      await client.leaveVlan();
      const vlanCleanupError = client.vlanSnapshot.error;
      if (session !== null) await storage.removeSession(session.scope);
      client.disconnect();
      setSession(null);
      setRooms([]);
      setSelectedRoomId(null);
      setRoomDetail(null);
      setIngresses([]);
      setSelectedIngressId(null);
      setMessages([]);
      setError(vlanCleanupError);
    } catch (logoutError) {
      setError(errorMessage(logoutError));
    } finally {
      setBusy(false);
    }
  };

  const handleClearData = async (): Promise<void> => {
    if (busy) return;
    const confirmed = typeof window === 'undefined' || typeof window.confirm !== 'function'
      ? true
      : window.confirm('清除本地数据后需要重新登录，确定继续吗？');
    if (!confirmed) return;
    setBusy(true);
    try {
      await voice.setRoom(null);
      await client.leaveVlan();
      const vlanCleanupError = client.vlanSnapshot.error;
      await storage.clearData();
      client.disconnect();
      setSession(null);
      setRooms([]);
      setSelectedRoomId(null);
      setRoomDetail(null);
      setIngresses([]);
      setSelectedIngressId(null);
      setMessages([]);
      setError(vlanCleanupError);
    } catch (clearError) {
      setError(errorMessage(clearError));
    } finally {
      setBusy(false);
    }
  };

  const handleVoiceToggle = (): void => {
    if (selectedRoomId === null || voiceSnapshot.microphone === 'enabling' || voiceSnapshot.microphone === 'disabling') {
      return;
    }
    void voice.setMicrophoneEnabled(voiceSnapshot.microphone !== 'enabled').catch(() => undefined);
  };

  const selectedRoom = rooms.find((room) => room.id === selectedRoomId);
  const selectedIngress = ingresses.find((ingress) => ingress.id === selectedIngressId);
  const vlanTransitioningOtherRoom = vlanSnapshot.roomId !== null &&
    vlanSnapshot.roomId !== selectedRoomId &&
    (vlanSnapshot.state === 'connecting' || vlanSnapshot.state === 'disconnecting');
  const visibleVlanSnapshot = vlanSnapshot.roomId === selectedRoomId
    ? vlanSnapshot
    : vlanTransitioningOtherRoom
      ? { ...emptyVlanSnapshot, state: 'disconnecting' as const, roomId: selectedRoomId }
      : emptyVlanSnapshot;
  const vlanConnected = visibleVlanSnapshot.state === 'connected';
  const vlanBusy = visibleVlanSnapshot.state === 'connecting' || visibleVlanSnapshot.state === 'disconnecting';
  const displayName = session?.userDisplayId ?? '未登录';

  return (
    <div className="app-shell" data-theme={theme} data-authenticated={session === null ? 'false' : 'true'}>
      <header className="title-bar">
        <div className="title-bar__identity">
          <span className="brand-mark" aria-hidden="true">NR</span>
          <div>
            <p className="eyebrow">NexusRoom</p>
            <h1>{selectedRoom?.name ?? '桌面客户端'}</h1>
          </div>
        </div>
        <div className="title-bar__actions">
          <span className="connection-status" data-connection={connectionState} aria-live="polite">
            <span className="status-dot" aria-hidden="true" />
            {session === null ? '等待登录' : connectionLabel(connectionState)}
          </span>
          <button
            className="theme-toggle"
            type="button"
            aria-label={theme === 'dark' ? '切换到浅色主题' : '切换到深色主题'}
            onClick={() => setTheme((current) => current === 'dark' ? 'light' : 'dark')}
          >
            {theme === 'dark' ? '浅色' : '深色'}
          </button>
        </div>
      </header>

      <div className="app-body">
        <nav className="sidebar" aria-label="Primary navigation">
          {session === null ? (
            <div className="sidebar__guest">
              <p className="eyebrow">账号</p>
              <p className="muted-copy">登录后管理房间和消息。</p>
            </div>
          ) : (
            <>
              <div className="sidebar__account">
                <span className="avatar avatar--small" aria-hidden="true">{displayName.slice(0, 1).toUpperCase()}</span>
                <div>
                  <strong>{displayName}</strong>
                  <span className="muted-copy">当前账号</span>
                </div>
              </div>
              <div className="sidebar__section-heading">
                <p className="eyebrow">房间</p>
                <span className="room-count">{rooms.length}</span>
              </div>
              <div className="room-list" aria-label="房间列表">
                {rooms.length === 0 ? (
                  <p className="muted-copy room-list__empty">还没有房间</p>
                ) : rooms.map((room) => (
                  <button
                    className={`room-item${selectedRoomId === room.id ? ' room-item--active' : ''}`}
                    type="button"
                    key={room.id}
                    onClick={() => setSelectedRoomId(room.id)}
                    aria-pressed={selectedRoomId === room.id}
                  >
                    <span className="room-item__icon" aria-hidden="true">#</span>
                    <span className="room-item__name">{room.name}</span>
                  </button>
                ))}
              </div>
              <div className="room-actions">
                <form onSubmit={handleCreateRoom}>
                  <label htmlFor="create-room-name">创建房间</label>
                  <div className="inline-form">
                    <input
                      id="create-room-name"
                      value={roomNameDraft}
                      onChange={(event) => setRoomNameDraft(event.target.value)}
                      placeholder="房间名称"
                      maxLength={128}
                    />
                    <button type="submit" disabled={roomActionBusy || roomNameDraft.trim().length === 0}>创建</button>
                  </div>
                </form>
                <form onSubmit={handleJoinRoom}>
                  <label htmlFor="join-room-code">邀请码加入</label>
                  <div className="inline-form">
                    <input
                      id="join-room-code"
                      value={inviteDraft}
                      onChange={(event) => setInviteDraft(event.target.value)}
                      placeholder="六位邀请码"
                      maxLength={6}
                    />
                    <button type="submit" disabled={roomActionBusy || inviteDraft.trim().length === 0}>加入</button>
                  </div>
                </form>
              </div>
              <div className="sidebar__footer">
                <button className="text-button" type="button" onClick={() => void handleLogout()} disabled={busy}>退出当前账号</button>
                <button className="text-button text-button--danger" type="button" onClick={() => void handleClearData()} disabled={busy}>清除本地数据</button>
              </div>
            </>
          )}
        </nav>

        <main className="workspace" aria-label="Workspace">
          {error !== null ? <p className="error-banner" role="alert">{error}</p> : null}
          {session === null ? (
            <section className="login-panel" aria-labelledby="login-title">
              <div className="login-panel__intro">
                <p className="eyebrow">连接到你的服务器</p>
                <h2 id="login-title">登录 NexusRoom</h2>
                <p className="muted-copy">服务器地址和登录会话会保存在本机设置中。</p>
              </div>
              <form className="login-form" onSubmit={handleLogin}>
                <label htmlFor="server-url">服务器地址</label>
                <input
                  id="server-url"
                  type="url"
                  value={serverUrlDraft}
                  onChange={(event) => setServerUrlDraft(event.target.value)}
                  placeholder={DEFAULT_SERVER_URL}
                  autoComplete="url"
                  required
                />
                <label htmlFor="username">账号</label>
                <input
                  id="username"
                  value={username}
                  onChange={(event) => setUsername(event.target.value)}
                  autoComplete="username"
                  required
                />
                <label htmlFor="password">密码</label>
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  autoComplete="current-password"
                  required
                />
                <button className="primary-button" type="submit" disabled={loginBusy}>
                  {loginBusy ? '登录中…' : '登录'}
                </button>
              </form>
            </section>
          ) : (
            <>
              <div className="workspace__header">
                <div>
                  <p className="eyebrow">房间消息</p>
                  <h2>{selectedRoom?.name ?? '选择一个房间'}</h2>
                </div>
                <div className="workspace__header-actions">
                  <span
                    className={`voice-status voice-status--${voiceSnapshot.connection}`}
                    data-voice-state={voiceSnapshot.connection}
                    aria-live="polite"
                  >
                    <span className="voice-status__dot" aria-hidden="true" />
                    {voiceConnectionLabel(voiceSnapshot.connection)}
                  </span>
                  {selectedRoomId !== null ? (
                    <button
                      className="voice-button"
                      type="button"
                      data-microphone-state={voiceSnapshot.microphone}
                      aria-pressed={voiceSnapshot.microphone === 'enabled'}
                      aria-busy={voiceSnapshot.microphone === 'enabling' || voiceSnapshot.microphone === 'disabling'}
                      onClick={handleVoiceToggle}
                      disabled={voiceSnapshot.microphone === 'enabling' || voiceSnapshot.microphone === 'disabling'}
                    >
                      {microphoneLabel(voiceSnapshot.microphone)}
                    </button>
                  ) : null}
                  <span className="status-chip">{connectionLabel(connectionState)}</span>
                </div>
              </div>
              {selectedIngress !== undefined ? (
                <LivePlaybackPanel
                  key={`${selectedIngress.id}-${selectedIngress.streamKey}`}
                  serverUrl={client.serverUrl}
                  ingress={selectedIngress}
                  onClose={() => setSelectedIngressId(null)}
                />
              ) : null}
              <section className="message-panel" aria-label="聊天消息">
                {selectedRoomId === null ? (
                  <div className="empty-state">
                    <span className="empty-state__line" aria-hidden="true" />
                    <h3>选择一个房间开始聊天</h3>
                    <p className="muted-copy">房间消息会显示在这里。</p>
                  </div>
                ) : messages.length === 0 ? (
                  <div className="empty-state">
                    <span className="empty-state__line" aria-hidden="true" />
                    <h3>还没有消息</h3>
                    <p className="muted-copy">发一条消息，开始这个房间的对话。</p>
                  </div>
                ) : (
                  <div className="message-list">
                    {messages.map((message) => {
                      const senderName = message.sender?.nickname ?? (message.senderId === session.userId ? displayName : `用户 ${message.senderId}`);
                      const imageSource = imageSources[message.id];
                      return (
                        <article className="message-row" key={`${message.id}-${message.clientMessageId ?? ''}`}>
                          <span className="avatar" aria-hidden="true">{senderName.slice(0, 1).toUpperCase()}</span>
                          <div className="message-row__body">
                            <div className="message-row__meta"><strong>{senderName}</strong><time dateTime={message.createdAt}>{new Date(message.createdAt).toLocaleString()}</time></div>
                            {message.type === 'image' ? (
                              imageSource ? <img className="message-image" src={imageSource} alt="聊天图片" /> : <span className="image-loading">图片加载中</span>
                            ) : <p>{message.content}</p>}
                          </div>
                        </article>
                      );
                    })}
                  </div>
                )}
              </section>
              <form className="composer" onSubmit={(event) => { event.preventDefault(); void handleSend(); }}>
                <textarea
                  value={messageDraft}
                  onChange={(event) => setMessageDraft(event.target.value)}
                  onKeyDown={handleComposerKeyDown}
                  placeholder="输入消息，Enter 发送，Shift+Enter 换行"
                  rows={3}
                  disabled={selectedRoomId === null || sendingMessage || sendingImage}
                  aria-label="消息内容"
                />
                <div className="composer__actions">
                  <label className="file-button">
                    <span>{sendingImage ? '上传中…' : '选择图片'}</span>
                    <input type="file" accept="image/*" onChange={(event) => void handleImageChange(event)} disabled={selectedRoomId === null || sendingImage || sendingMessage} />
                  </label>
                  <button className="primary-button" type="submit" disabled={selectedRoomId === null || sendingMessage || sendingImage || messageDraft.trim().length === 0}>
                    {sendingMessage ? '发送中…' : '发送'}
                  </button>
                </div>
              </form>
            </>
          )}
        </main>

        <aside className="room-info" aria-label="Room information">
          <div className="room-info__header">
            <p className="eyebrow">房间信息</p>
            <h2>{roomDetail?.name ?? '未选择房间'}</h2>
            {roomDetail?.inviteCode ? <p className="room-code">邀请码：{roomDetail.inviteCode}</p> : null}
            {roomDetail !== null ? (
              <button
                className="text-button room-info__leave"
                type="button"
                onClick={() => void handleLeaveRoom()}
                disabled={leavingRoom}
              >
                {leavingRoom ? '退出中…' : '退出房间'}
              </button>
            ) : null}
          </div>
          {roomDetail === null ? (
            <div className="room-info__empty">
              <span className="room-info__marker" aria-hidden="true" />
              <h3>{session === null ? '登录后查看房间' : '选择房间查看成员'}</h3>
              <p className="muted-copy">成员列表和房间信息会显示在这里。</p>
            </div>
          ) : (
            <div className="member-list" aria-label="房间成员">
              <div className="section-heading"><span>成员</span><span>{roomDetail.members.length}</span></div>
              {roomDetail.members.map((member) => (
                (() => {
                  const participant = findVoiceParticipant(voiceSnapshot.participants, member.userId);
                  const isVoiceOnline = participant !== undefined;
                  const isSpeaking = isVoiceOnline && participant.speaking && !participant.muted;
                  return (
                    <div className="member-row" key={member.userId}>
                  <span
                    className={`member-presence${isVoiceOnline ? ' member-presence--online' : ''}${isSpeaking ? ' member-presence--speaking' : ''}`}
                    data-presence={isVoiceOnline ? (isSpeaking ? 'speaking' : 'online') : 'offline'}
                    role="img"
                    aria-label={isVoiceOnline ? (isSpeaking ? '正在说话' : '语音在线') : '未加入语音'}
                  />
                  <span className="avatar avatar--small" aria-hidden="true">{member.nickname.slice(0, 1).toUpperCase()}</span>
                  <span className="member-name">{member.nickname}</span>
                  {member.role ? <span className="member-role">{member.role}</span> : null}
                </div>
                  );
                })()
              ))}
            </div>
          )}
          {roomDetail !== null ? (
            <section className="vlan-section" aria-label="房间 VLAN">
              <div className="section-heading">
                <span>房间 VLAN</span>
                <span
                  className={`vlan-status vlan-status--${visibleVlanSnapshot.state}`}
                  data-vlan-state={visibleVlanSnapshot.state}
                  aria-live="polite"
                >
                  {vlanStatusLabel(visibleVlanSnapshot.state)}
                </span>
              </div>
              <div className="vlan-controls">
                <button
                  className="vlan-toggle"
                  type="button"
                  onClick={() => void handleVlanToggle()}
                  aria-pressed={vlanConnected}
                  aria-busy={vlanBusy}
                  disabled={vlanBusy}
                >
                  {vlanToggleLabel(visibleVlanSnapshot.state)}
                </button>
                <button
                  className="vlan-refresh"
                  type="button"
                  onClick={() => void handleVlanRefresh()}
                  disabled={!vlanConnected || vlanRefreshBusy}
                  aria-busy={vlanRefreshBusy}
                >
                  {vlanRefreshBusy ? '刷新中…' : '刷新 Peer'}
                </button>
              </div>
              {visibleVlanSnapshot.assignedIp !== undefined ? (
                <div className="vlan-ip-row">
                  <div>
                    <span className="vlan-field-label">虚拟 IPv4</span>
                    <code>{visibleVlanSnapshot.assignedIp}</code>
                  </div>
                  <button
                    className="vlan-copy"
                    type="button"
                    onClick={() => void handleCopyVlanIp()}
                    aria-label="复制虚拟 IPv4"
                  >
                    复制
                  </button>
                </div>
              ) : null}
              {vlanCopyError !== null ? <p className="vlan-error" role="status">{vlanCopyError}</p> : null}
              {visibleVlanSnapshot.error !== null ? <p className="vlan-error" role="alert">{visibleVlanSnapshot.error}</p> : null}
              <div className="vlan-peer-list" aria-label="VLAN Peer 列表">
                <div className="section-heading">
                  <span>Peer</span>
                  <span>{vlanConnected ? visibleVlanSnapshot.peers.length : 0}</span>
                </div>
                {!vlanConnected ? (
                  <p className="muted-copy vlan-empty">连接 VLAN 后查看 Peer。</p>
                ) : visibleVlanSnapshot.peers.length === 0 ? (
                  <p className="muted-copy vlan-empty">暂无其他 Peer。</p>
                ) : visibleVlanSnapshot.peers.map((peer) => (
                  <div className="vlan-peer-row" key={peer.userId}>
                    <span className="vlan-peer-name">{peer.nickname}</span>
                    <code>{peer.assignedIp}</code>
                  </div>
                ))}
              </div>
            </section>
          ) : null}
          {roomDetail !== null ? (
            <section className="stream-section" aria-label="推流入口">
              <div className="section-heading">
                <span>推流入口</span>
                <span>{ingresses.length}</span>
              </div>
              {ingresses.length === 0 ? (
                <p className="muted-copy stream-section__empty">还没有推流入口</p>
              ) : (
                <div className="stream-list">
                  {ingresses.map((ingress) => (
                    <div className={`stream-item${selectedIngressId === ingress.id ? ' stream-item--active' : ''}`} key={ingress.id}>
                      <button
                        className="stream-item__select"
                        type="button"
                        onClick={() => setSelectedIngressId(ingress.id)}
                        aria-pressed={selectedIngressId === ingress.id}
                      >
                        <span className="stream-item__name">{ingress.label}</span>
                        <span className="stream-item__status">{ingress.isActive ? '直播中' : '未推流'}</span>
                      </button>
                      <button
                        className="stream-item__delete"
                        type="button"
                        onClick={() => void handleDeleteIngress(ingress)}
                        disabled={ingressActionBusy || ingress.isActive}
                      >
                        删除
                      </button>
                      {selectedIngressId === ingress.id ? (
                        <div className="stream-item__details">
                          <span>RTMP：{ingress.rtmpUrl}</span>
                          <span>Key：{ingress.streamKey}</span>
                          <span>发布地址：{ingress.publishUrl}</span>
                        </div>
                      ) : null}
                    </div>
                  ))}
                </div>
              )}
              <form className="stream-create-form" onSubmit={handleCreateIngress}>
                <label htmlFor="create-ingress-label">新建入口</label>
                <div className="inline-form">
                  <input
                    id="create-ingress-label"
                    value={ingressLabelDraft}
                    onChange={(event) => setIngressLabelDraft(event.target.value)}
                    placeholder="入口名称"
                    maxLength={64}
                    disabled={ingressActionBusy}
                  />
                  <button type="submit" disabled={ingressActionBusy || ingressLabelDraft.trim().length === 0}>创建</button>
                </div>
              </form>
            </section>
          ) : null}
          <div className="room-info__footer">
            <span className="muted-copy">{serverUrl}</span>
          </div>
        </aside>
      </div>
    </div>
  );
}

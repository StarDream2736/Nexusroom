import type {
  WireGuardAvailability,
  WireGuardKeyPair,
  WireGuardStatus,
  WireGuardTunnelConfig,
} from '../shared/preload-api';

export type VlanState =
  | 'disabled'
  | 'connecting'
  | 'connected'
  | 'disconnecting'
  | 'unavailable'
  | 'error';

export interface VlanJoinPeer {
  readonly userId: number;
  readonly nickname: string;
  readonly publicKey: string;
  readonly allowedIps: string;
}

export interface VlanPeer {
  readonly userId: number;
  readonly nickname: string;
  readonly publicKey: string;
  readonly assignedIp: string;
  readonly lastHandshake?: string;
}

export interface VlanJoinResponse {
  readonly assignedIp: string;
  readonly serverPublicKey: string;
  readonly serverEndpoint: string;
  readonly dns?: string;
  readonly peers: readonly VlanJoinPeer[];
}

export interface VlanPeerInfo {
  readonly userId: number;
  readonly nickname?: string;
  readonly publicKey?: string;
  readonly assignedIp?: string;
}

export interface VlanPeerUpdate {
  readonly roomId: number;
  readonly action: 'join' | 'leave';
  readonly peerInfo: VlanPeerInfo;
}

export interface VlanSnapshot {
  readonly state: VlanState;
  readonly roomId: number | null;
  readonly assignedIp?: string;
  readonly peers: readonly VlanPeer[];
  readonly error: string | null;
}

export type VlanErrorPhase =
  | 'availability'
  | 'key generation'
  | 'join'
  | 'configuration'
  | 'start'
  | 'refresh'
  | 'stop'
  | 'leave';

export interface VlanSessionDriver {
  readonly getAvailability: () => Promise<WireGuardAvailability>;
  readonly generateKeyPair: () => Promise<WireGuardKeyPair>;
  readonly joinServer: (roomId: number, publicKey: string) => Promise<VlanJoinResponse>;
  readonly leaveServer: (roomId: number) => Promise<void>;
  readonly listPeers: (roomId: number) => Promise<readonly VlanPeer[]>;
  readonly startTunnel: (config: WireGuardTunnelConfig) => Promise<WireGuardStatus>;
  readonly stopTunnel: () => Promise<WireGuardStatus | void>;
  readonly toUserError: (error: unknown, phase: VlanErrorPhase) => Error;
  readonly unavailableMessage: (reason: WireGuardAvailability['reason']) => string;
}

export interface VlanSessionOptions {
  readonly onChange?: (snapshot: VlanSnapshot) => void;
}

const emptySnapshot: VlanSnapshot = {
  state: 'disabled',
  roomId: null,
  peers: [],
  error: null,
};

function roomId(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error('房间 ID 无效');
  }
  return value;
}

function toError(value: unknown): Error {
  return value instanceof Error ? value : new Error('VLAN 操作失败');
}

function combineErrors(primary: Error, cleanup: Error | null): Error {
  if (cleanup === null) return primary;
  return new Error(`${primary.message}；${cleanup.message}`);
}

function ipv4ToNumber(value: string): number {
  const parts = value.split('.');
  if (parts.length !== 4) throw new Error('assigned_ip 必须是 IPv4 CIDR');
  const octets = parts.map((part) => {
    if (!/^\d{1,3}$/u.test(part)) throw new Error('assigned_ip 必须是 IPv4 CIDR');
    const octet = Number(part);
    if (!Number.isInteger(octet) || octet < 0 || octet > 255) {
      throw new Error('assigned_ip 必须是 IPv4 CIDR');
    }
    return octet;
  });
  const [first, second, third, fourth] = octets;
  if (first === undefined || second === undefined || third === undefined || fourth === undefined) {
    throw new Error('assigned_ip 必须是 IPv4 CIDR');
  }
  return (((first << 24) >>> 0) |
    (second << 16) |
    (third << 8) |
    fourth) >>> 0;
}

function numberToIpv4(value: number): string {
  return [
    (value >>> 24) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 8) & 0xff,
    value & 0xff,
  ].join('.');
}

export function deriveIPv4Subnet(cidr: string): string {
  if (typeof cidr !== 'string') throw new Error('assigned_ip 必须是 IPv4 CIDR');
  const value = cidr.trim();
  const slash = value.lastIndexOf('/');
  if (slash <= 0 || slash === value.length - 1 || value.indexOf('/') !== slash) {
    throw new Error('assigned_ip 必须是 IPv4 CIDR');
  }
  const address = value.slice(0, slash);
  const prefixText = value.slice(slash + 1);
  if (!/^(?:0|[1-9]\d*)$/u.test(prefixText)) {
    throw new Error('assigned_ip 必须是 IPv4 CIDR');
  }
  const prefix = Number(prefixText);
  if (!Number.isSafeInteger(prefix) || prefix < 0 || prefix > 32) {
    throw new Error('assigned_ip 必须是 IPv4 CIDR');
  }
  const ip = ipv4ToNumber(address);
  const mask = prefix === 0 ? 0 : (0xffffffff << (32 - prefix)) >>> 0;
  return `${numberToIpv4(ip & mask)}/${prefix}`;
}

export function buildVlanTunnelConfig(
  keyPair: WireGuardKeyPair,
  join: VlanJoinResponse,
): WireGuardTunnelConfig {
  if (typeof keyPair.private_key !== 'string' || keyPair.private_key.trim().length === 0) {
    throw new Error('WireGuard 私钥无效');
  }
  if (typeof keyPair.public_key !== 'string' || keyPair.public_key.trim().length === 0) {
    throw new Error('WireGuard 公钥无效');
  }
  const assignedIp = join.assignedIp.trim();
  const serverPublicKey = join.serverPublicKey.trim();
  const serverEndpoint = join.serverEndpoint.trim();
  if (assignedIp.length === 0 || serverPublicKey.length === 0 || serverEndpoint.length === 0) {
    throw new Error('VLAN 服务端配置不完整');
  }
  return {
    interface_name: 'NexusRoom0',
    private_key: keyPair.private_key,
    address: assignedIp,
    peers: [{
      public_key: serverPublicKey,
      endpoint: serverEndpoint,
      allowed_ips: deriveIPv4Subnet(assignedIp),
      persistent_keepalive: 25,
    }],
    ...(join.dns === undefined || join.dns.trim().length === 0
      ? {}
      : { dns: join.dns.trim() }),
  };
}

export class VlanSessionController {
  private snapshotValue: VlanSnapshot = emptySnapshot;
  private readonly listeners = new Set<(snapshot: VlanSnapshot) => void>();
  private lifecyclePromise: Promise<void> = Promise.resolve();
  private generation = 0;
  private registrationRoomId: number | null = null;
  private sessionRoomId: number | null = null;
  private tunnelStarted = false;
  private starting = false;
  private stopRequested = false;
  private stopPromise: Promise<Error | null> | null = null;
  private requestValue: {
    readonly roomId: number;
    readonly promise: Promise<VlanSnapshot>;
  } | null = null;

  constructor(
    private readonly driver: VlanSessionDriver,
    options: VlanSessionOptions = {},
  ) {
    if (options.onChange !== undefined) this.listeners.add(options.onChange);
  }

  get snapshot(): VlanSnapshot {
    return this.snapshotValue;
  }

  onChange(listener: (snapshot: VlanSnapshot) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  join(roomIdValue: number): Promise<VlanSnapshot> {
    const id = roomId(roomIdValue);
    const request = this.requestValue;
    if (
      request !== null &&
      request.roomId === id &&
      (this.snapshotValue.state === 'connecting' || this.snapshotValue.state === 'connected')
    ) {
      return request.promise;
    }
    if (this.sessionRoomId === id && this.snapshotValue.state === 'connected') {
      return Promise.resolve(this.snapshotValue);
    }

    const currentGeneration = ++this.generation;
    this.setSnapshot({ state: 'connecting', roomId: id, peers: [], error: null });
    const operation = this.enqueue(() => this.start(id, currentGeneration));
    this.requestValue = { roomId: id, promise: operation };
    void operation.then(
      () => {
        if (this.requestValue?.promise === operation) this.requestValue = null;
      },
      () => {
        if (this.requestValue?.promise === operation) this.requestValue = null;
      },
    );
    return operation;
  }

  async leave(roomIdValue?: number): Promise<void> {
    const requestedRoomId = roomIdValue === undefined ? undefined : roomId(roomIdValue);
    const activeRoomId = this.registrationRoomId ?? this.sessionRoomId ?? this.requestValue?.roomId ?? this.snapshotValue.roomId;
    if (requestedRoomId !== undefined && activeRoomId !== null && requestedRoomId !== activeRoomId) {
      return;
    }
    const targetRoomId = requestedRoomId ?? activeRoomId;
    const hasWork = targetRoomId !== null || this.starting || this.tunnelStarted || this.requestValue !== null;
    if (!hasWork) return;

    const currentGeneration = ++this.generation;
    this.requestValue = null;
    this.setSnapshot({
      state: 'disconnecting',
      roomId: targetRoomId,
      ...(this.snapshotValue.assignedIp === undefined ? {} : { assignedIp: this.snapshotValue.assignedIp }),
      peers: this.snapshotValue.peers,
      error: null,
    });
    const immediateStop = this.starting || this.tunnelStarted ? this.stopTunnelNow() : null;
    await this.enqueue(async () => {
      if (immediateStop !== null) await immediateStop;
      await this.cleanup(targetRoomId, currentGeneration);
    });
  }

  async refresh(roomIdValue: number): Promise<readonly VlanPeer[]> {
    const id = roomId(roomIdValue);
    if (this.sessionRoomId !== id || this.snapshotValue.state !== 'connected') {
      throw new Error('VLAN 尚未连接');
    }
    const generation = this.generation;
    try {
      const peers = await this.driver.listPeers(id);
      if (generation !== this.generation || this.sessionRoomId !== id || this.snapshotValue.state !== 'connected') {
        return this.snapshotValue.peers;
      }
      this.setSnapshot({ ...this.snapshotValue, peers, error: null });
      return peers;
    } catch (error) {
      const clean = this.cleanError(error, 'refresh');
      if (generation === this.generation && this.sessionRoomId === id) {
        this.setSnapshot({ ...this.snapshotValue, state: 'connected', error: clean.message });
      }
      throw clean;
    }
  }

  async dispose(): Promise<void> {
    await this.leave();
    this.listeners.clear();
  }

  private async start(id: number, currentGeneration: number): Promise<VlanSnapshot> {
    const hasPreviousSession = this.registrationRoomId !== null ||
      this.sessionRoomId !== null ||
      this.starting ||
      this.tunnelStarted;
    if (hasPreviousSession) {
      await this.cleanup(this.registrationRoomId ?? this.sessionRoomId, currentGeneration);
    }
    if (!this.isCurrent(currentGeneration)) return this.snapshotValue;
    this.stopRequested = false;

    let availability: WireGuardAvailability;
    try {
      availability = await this.driver.getAvailability();
    } catch (error) {
      return this.fail(id, currentGeneration, this.cleanError(error, 'availability'));
    }
    if (!availability || availability.available !== true) {
      const message = this.driver.unavailableMessage(availability?.reason);
      const error = new Error(message);
      if (this.isCurrent(currentGeneration)) {
        this.setSnapshot({ state: 'unavailable', roomId: id, peers: [], error: message });
      }
      throw error;
    }

    let keyPair: WireGuardKeyPair;
    try {
      keyPair = await this.driver.generateKeyPair();
    } catch (error) {
      return this.fail(id, currentGeneration, this.cleanError(error, 'key generation'));
    }
    if (!this.isCurrent(currentGeneration)) return this.snapshotValue;

    let join: VlanJoinResponse;
    try {
      join = await this.driver.joinServer(id, keyPair.public_key);
      this.registrationRoomId = id;
    } catch (error) {
      return this.fail(id, currentGeneration, this.cleanError(error, 'join'));
    }
    if (!this.isCurrent(currentGeneration)) {
      await this.cleanup(id, currentGeneration);
      return this.snapshotValue;
    }

    let tunnelConfig: WireGuardTunnelConfig;
    try {
      tunnelConfig = buildVlanTunnelConfig(keyPair, join);
    } catch (error) {
      return this.fail(id, currentGeneration, this.cleanError(error, 'configuration'));
    }
    this.setSnapshot({
      state: 'connecting',
      roomId: id,
      assignedIp: join.assignedIp,
      peers: [],
      error: null,
    });

    this.starting = true;
    try {
      await this.driver.startTunnel(tunnelConfig);
      this.tunnelStarted = true;
    } catch (error) {
      this.starting = false;
      if (!this.isCurrent(currentGeneration)) {
        await this.cleanup(id, currentGeneration);
        return this.snapshotValue;
      }
      const startError = this.cleanError(error, 'start');
      const cleanupError = await this.cleanup(id, currentGeneration);
      const combined = combineErrors(startError, cleanupError);
      this.setSnapshot({ state: 'error', roomId: id, peers: [], error: combined.message });
      throw combined;
    } finally {
      this.starting = false;
    }

    if (!this.isCurrent(currentGeneration)) {
      await this.cleanup(id, currentGeneration, true);
      return this.snapshotValue;
    }
    this.sessionRoomId = id;
    this.setSnapshot({
      state: 'connecting',
      roomId: id,
      assignedIp: join.assignedIp,
      peers: [],
      error: null,
    });
    try {
      const peers = await this.driver.listPeers(id);
      if (!this.isCurrent(currentGeneration)) {
        await this.cleanup(id, currentGeneration);
        return this.snapshotValue;
      }
      this.setSnapshot({
        state: 'connected',
        roomId: id,
        assignedIp: join.assignedIp,
        peers,
        error: null,
      });
      return this.snapshotValue;
    } catch (error) {
      const clean = this.cleanError(error, 'refresh');
      if (!this.isCurrent(currentGeneration)) {
        await this.cleanup(id, currentGeneration);
        return this.snapshotValue;
      }
      this.setSnapshot({
        state: 'connected',
        roomId: id,
        assignedIp: join.assignedIp,
        peers: [],
        error: clean.message,
      });
      throw clean;
    }
  }

  private async fail(
    id: number,
    currentGeneration: number,
    error: Error,
  ): Promise<VlanSnapshot> {
    const cleanupError = await this.cleanup(id, currentGeneration);
    if (!this.isCurrent(currentGeneration)) return this.snapshotValue;
    const combined = combineErrors(error, cleanupError);
    this.setSnapshot({ state: 'error', roomId: id, peers: [], error: combined.message });
    throw combined;
  }

  private async cleanup(
    targetRoomId: number | null,
    currentGeneration: number,
    stopAfterStart = false,
  ): Promise<Error | null> {
    const registeredRoomId = this.registrationRoomId;
    const roomIdValue = registeredRoomId ?? this.sessionRoomId ?? targetRoomId;
    const shouldLeave = registeredRoomId !== null;
    const shouldStop = this.tunnelStarted || this.starting;
    this.registrationRoomId = null;
    this.sessionRoomId = null;
    this.tunnelStarted = false;
    this.starting = false;

    const stopError = shouldStop
      ? stopAfterStart
        ? await this.stopAfterStart()
        : await (this.stopRequested
          ? (this.stopPromise ?? Promise.resolve(null))
          : this.stopTunnelNow())
      : null;
    let leaveError: Error | null = null;
    if (shouldLeave && roomIdValue !== null) {
      try {
        await this.driver.leaveServer(roomIdValue);
      } catch (error) {
        leaveError = this.cleanError(error, 'leave');
      }
    }
    const cleanupError = stopError === null
      ? leaveError
      : leaveError === null
        ? stopError
        : new Error(`${stopError.message}；${leaveError.message}`);
    if (this.generation === currentGeneration) {
      this.setSnapshot({
        state: 'disabled',
        roomId: null,
        peers: [],
        error: cleanupError?.message ?? null,
      });
    }
    return cleanupError;
  }

  private async stopAfterStart(): Promise<Error | null> {
    const earlyStop = this.stopPromise;
    const earlyStopError = earlyStop === null ? null : await earlyStop;
    if (earlyStop !== null && this.stopPromise === earlyStop) this.stopPromise = null;
    const postStartStopError = await this.stopTunnelNow();
    if (earlyStopError === null) return postStartStopError;
    if (postStartStopError === null) return earlyStopError;
    return new Error(`${earlyStopError.message}；${postStartStopError.message}`);
  }

  private stopTunnelNow(): Promise<Error | null> {
    if (this.stopPromise !== null) return this.stopPromise;
    this.stopRequested = true;
    const operation: Promise<Error | null> = Promise.resolve()
      .then(() => this.driver.stopTunnel())
      .then(() => null)
      .catch((error: unknown) => this.cleanError(error, 'stop'));
    this.stopPromise = operation;
    void operation.then(() => {
      if (this.stopPromise === operation) this.stopPromise = null;
    });
    return operation;
  }

  private cleanError(error: unknown, phase: VlanErrorPhase): Error {
    try {
      return toError(this.driver.toUserError(error, phase));
    } catch {
      return new Error(`VLAN ${phase}失败，请稍后重试`);
    }
  }

  private isCurrent(currentGeneration: number): boolean {
    return currentGeneration === this.generation;
  }

  private setSnapshot(snapshot: VlanSnapshot): void {
    this.snapshotValue = snapshot;
    for (const listener of [...this.listeners]) {
      try {
        listener(snapshot);
      } catch {
        // UI listeners must not break the VLAN lifecycle.
      }
    }
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.lifecyclePromise.then(operation, operation);
    this.lifecyclePromise = next.then(() => undefined, () => undefined);
    return next;
  }
}

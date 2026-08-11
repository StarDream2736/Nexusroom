import { describe, expect, it } from 'vitest';
import type {
  WireGuardAvailability,
  WireGuardKeyPair,
  WireGuardStatus,
  WireGuardTunnelConfig,
} from '../src/shared/preload-api';
import {
  VlanSessionController,
  buildVlanTunnelConfig,
  deriveIPv4Subnet,
  type VlanJoinResponse,
  type VlanPeer,
  type VlanSessionDriver,
} from '../src/renderer/vlan-session';

const joinResponse: VlanJoinResponse = {
  assignedIp: '10.0.8.2/24',
  serverPublicKey: 'server-public-key',
  serverEndpoint: 'wg.example.test:51820',
  dns: '10.0.8.1',
  peers: [],
};

const peers: readonly VlanPeer[] = [{
  userId: 2,
  nickname: 'Peer',
  publicKey: 'peer-public-key',
  assignedIp: '10.0.8.3/24',
}];

class Deferred {
  readonly promise: Promise<void>;
  resolve!: () => void;

  constructor() {
    this.promise = new Promise<void>((resolve) => {
      this.resolve = resolve;
    });
  }
}

class FakeDriver implements VlanSessionDriver {
  readonly calls: string[] = [];
  readonly rooms: { join: number[]; leave: number[] } = { join: [], leave: [] };
  readonly configs: WireGuardTunnelConfig[] = [];
  availability: WireGuardAvailability = { available: true };
  failStart = false;
  failRefresh = false;
  startGate: Deferred | null = null;
  readonly startingRooms = new Set<number>();
  readonly runningRooms = new Set<number>();
  readonly postStartStops: number[] = [];
  activeTunnelRoom: number | null = null;

  async getAvailability(): Promise<WireGuardAvailability> {
    this.calls.push('availability');
    return this.availability;
  }

  async generateKeyPair(): Promise<WireGuardKeyPair> {
    this.calls.push('key');
    return { public_key: 'client-public-key', private_key: 'client-private-key' };
  }

  async joinServer(roomId: number): Promise<VlanJoinResponse> {
    this.calls.push('join');
    this.rooms.join.push(roomId);
    return { ...joinResponse, assignedIp: roomId === 2 ? '10.0.9.2/24' : joinResponse.assignedIp };
  }

  async leaveServer(roomId: number): Promise<void> {
    this.calls.push('leave');
    this.rooms.leave.push(roomId);
  }

  async listPeers(): Promise<readonly VlanPeer[]> {
    this.calls.push('peers');
    if (this.failRefresh) throw new Error('peer refresh failed');
    return peers;
  }

  async startTunnel(config: WireGuardTunnelConfig): Promise<WireGuardStatus> {
    this.calls.push('start');
    this.configs.push(config);
    const roomId = this.rooms.join[this.rooms.join.length - 1] ?? 0;
    this.startingRooms.add(roomId);
    if (this.startGate !== null) await this.startGate.promise;
    this.startingRooms.delete(roomId);
    if (this.failStart) throw new Error('start failed');
    this.runningRooms.add(roomId);
    this.activeTunnelRoom = roomId;
    return { available: true, state: 'running', address: config.address };
  }

  async stopTunnel(): Promise<WireGuardStatus> {
    this.calls.push('stop');
    if (this.startingRooms.size > 0) {
      return { available: true, state: 'idle' };
    }
    if (this.activeTunnelRoom !== null) {
      this.postStartStops.push(this.activeTunnelRoom);
      this.runningRooms.delete(this.activeTunnelRoom);
      this.activeTunnelRoom = null;
    }
    return { available: true, state: 'idle' };
  }

  toUserError(error: unknown, phase: string): Error {
    return new Error(`VLAN ${phase}: ${error instanceof Error ? error.message : 'failed'}`);
  }

  unavailableMessage(): string {
    return 'WireGuard Helper 不可用';
  }
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

async function waitUntil(predicate: () => boolean): Promise<void> {
  for (let index = 0; index < 20 && !predicate(); index += 1) await flush();
  expect(predicate()).toBe(true);
}

describe('VlanSessionController', () => {
  it('derives IPv4 subnets for /0, /24, and /32 and rejects non-IPv4 input', () => {
    expect(deriveIPv4Subnet('10.20.30.40/0')).toBe('0.0.0.0/0');
    expect(deriveIPv4Subnet('10.20.30.40/24')).toBe('10.20.30.0/24');
    expect(deriveIPv4Subnet('10.20.30.40/32')).toBe('10.20.30.40/32');
    expect(() => deriveIPv4Subnet('2001:db8::1/64')).toThrow('IPv4 CIDR');
    expect(() => deriveIPv4Subnet('10.20.30.40')).toThrow('IPv4 CIDR');
    expect(() => deriveIPv4Subnet('10.20.30.40/33')).toThrow('IPv4 CIDR');
  });

  it('builds a server peer with the assigned IPv4 subnet and keepalive', () => {
    const config = buildVlanTunnelConfig(
      { public_key: 'client-public-key', private_key: 'client-private-key' },
      joinResponse,
    );
    expect(config.peers).toEqual([{
      public_key: 'server-public-key',
      endpoint: 'wg.example.test:51820',
      allowed_ips: '10.0.8.0/24',
      persistent_keepalive: 25,
    }]);
  });

  it('rolls back a registered peer when local startup fails', async () => {
    const driver = new FakeDriver();
    driver.failStart = true;
    const session = new VlanSessionController(driver);

    await expect(session.join(7)).rejects.toThrow('VLAN start');
    expect(driver.calls).toEqual(['availability', 'key', 'join', 'start', 'leave']);
    expect(session.snapshot.state).toBe('error');
  });

  it('keeps connecting state while deduplicating a same-room enable', async () => {
    const driver = new FakeDriver();
    driver.startGate = new Deferred();
    const states: string[] = [];
    const session = new VlanSessionController(driver, {
      onChange: (snapshot) => states.push(snapshot.state),
    });

    const first = session.join(7);
    const second = session.join(7);
    expect(second).toBe(first);
    expect(states).toEqual(['connecting']);

    driver.startGate.resolve();
    await first;
    expect(driver.calls.filter((call) => call === 'start')).toHaveLength(1);
    expect(states).not.toContain('disabled');
  });

  it('stops before leaving and remains disabled when the leave request fails', async () => {
    const driver = new FakeDriver();
    const session = new VlanSessionController(driver);
    await session.join(7);
    driver.leaveServer = async (roomId: number): Promise<void> => {
      driver.calls.push('leave');
      driver.rooms.leave.push(roomId);
      throw new Error('leave failed');
    };

    await session.leave(7);
    expect(driver.calls.slice(-2)).toEqual(['stop', 'leave']);
    expect(session.snapshot.state).toBe('disabled');
    expect(session.snapshot.roomId).toBeNull();
    expect(session.snapshot.error).toContain('VLAN leave');
  });

  it('cleans room A before room B can start and does not let A overwrite B', async () => {
    const driver = new FakeDriver();
    driver.startGate = new Deferred();
    const session = new VlanSessionController(driver);
    const roomA = session.join(1);
    await waitUntil(() => driver.calls.includes('start'));

    const leaveA = session.leave(1);
    const roomB = session.join(2);
    driver.startGate.resolve();
    await Promise.all([roomA, leaveA, roomB]);

    expect(driver.rooms.join).toEqual([1, 2]);
    expect(driver.rooms.leave).toEqual([1]);
    expect(driver.calls.indexOf('stop')).toBeLessThan(driver.calls.indexOf('leave'));
    expect(driver.postStartStops).toContain(1);
    expect(driver.runningRooms.has(1)).toBe(false);
    expect(driver.runningRooms.has(2)).toBe(true);
    expect(session.snapshot).toMatchObject({
      state: 'connected',
      roomId: 2,
      assignedIp: '10.0.9.2/24',
    });
  });

  it('keeps a running tunnel when the initial Peer refresh fails', async () => {
    const driver = new FakeDriver();
    driver.failRefresh = true;
    const session = new VlanSessionController(driver);

    await expect(session.join(7)).rejects.toThrow('VLAN refresh');
    expect(session.snapshot.state).toBe('connected');
    expect(session.snapshot.roomId).toBe(7);
    expect(driver.calls).not.toContain('stop');
    await session.leave(7);
    expect(driver.calls.slice(-2)).toEqual(['stop', 'leave']);
  });
});

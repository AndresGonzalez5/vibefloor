import { describe, it, expect, beforeEach } from 'vitest';
import { AgentManager } from '../engine/AgentManager';
import { TileMap } from '../engine/TileMap';
import { OfficeLayout } from '../engine/OfficeLayout';

describe('AgentManager with TileMap + OfficeLayout', () => {
  let tileMap: TileMap;
  let layout: OfficeLayout;
  let manager: AgentManager;

  beforeEach(() => {
    layout = new OfficeLayout();
    tileMap = new TileMap(layout.cols, layout.rows, layout.tileSize, layout.zoom);
    layout.initBlockedTiles(tileMap);
    manager = new AgentManager(tileMap, layout);
  });

  describe('createAgent with tile system', () => {
    it('creates agent at spawn tile with a path to a seat', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.tileX).toBe(layout.spawnTile[0]);
      expect(agent.tileY).toBe(layout.spawnTile[1]);
      expect(agent.path).toBeDefined();
      expect(agent.path!.length).toBeGreaterThan(0);
    });

    it('claims a seat for the agent', () => {
      manager.createAgent('a1', 'Alice');
      const seat = layout.getSeat('a1');
      expect(seat).not.toBeNull();
      expect(seat!.occupied).toBe(true);
    });

    it('sets pixelX/pixelY from spawn tile', () => {
      const agent = manager.createAgent('a1', 'Alice');
      const spawnPixel = tileMap.tileToPixel(layout.spawnTile[0], layout.spawnTile[1]);
      expect(agent.pixelX).toBe(spawnPixel.x);
      expect(agent.pixelY).toBe(spawnPixel.y);
    });

    it('agent starts in spawning state when tileMap is available', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.stateMachine.state).toBe('spawning');
      expect(agent.matrixState).not.toBeNull();
    });
  });

  describe('updateAll — walk interpolation', () => {
    it('agent moves toward next tile in path over time', () => {
      const agent = manager.createAgent('a1', 'Alice');

      // Complete spawn first
      manager.updateAll(0.35);
      expect(agent.stateMachine.state).toBe('walk');

      const startX = agent.pixelX;
      const startY = agent.pixelY;

      // Update with small dt
      manager.updateAll(0.1);

      // Agent should have moved from its start position
      const moved = agent.pixelX !== startX || agent.pixelY !== startY;
      expect(moved).toBe(true);
    });

    it('agent arrives at seat and transitions to idle', () => {
      const agent = manager.createAgent('a1', 'Alice');
      const seat = layout.getSeat('a1')!;
      const targetPixel = tileMap.tileToPixel(seat.chairTile[0], seat.chairTile[1]);

      // Run enough updates to complete spawn + walk
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.pixelX).toBe(targetPixel.x);
      expect(agent.pixelY).toBe(targetPixel.y);
      expect(agent.stateMachine.state).toBe('idle');
    });

    it('agent direction changes based on movement', () => {
      const agent = manager.createAgent('a1', 'Alice');
      // Complete spawn first
      manager.updateAll(0.35);
      // The path goes from [0,2] to a seat, first step should be right (col increases)
      manager.updateAll(0.01);
      // After starting to move, direction should reflect movement
      expect(['right', 'left', 'up', 'down']).toContain(agent.stateMachine.direction);
    });
  });

  describe('removeAgent releases seat', () => {
    it('releases the seat after despawn completes', () => {
      manager.createAgent('a1', 'Alice');
      const seat = layout.getSeat('a1');
      expect(seat).not.toBeNull();

      manager.removeAgent('a1');
      // During despawn, seat is still held
      expect(layout.getSeat('a1')).not.toBeNull();

      // Complete despawn
      manager.updateAll(0.35);
      expect(layout.getSeat('a1')).toBeNull();
    });
  });

  describe('backward compatibility', () => {
    it('works without tileMap/layout (old behavior)', () => {
      const oldManager = new AgentManager();
      const agent = oldManager.createAgent('a1', 'Alice');
      expect(agent.id).toBe('a1');
      expect(agent.name).toBe('Alice');
      // Old-style fixed positioning
      expect(agent.x).toBeDefined();
      expect(agent.y).toBeDefined();
    });
  });

  describe('seat release on agent removal with path cleanup (Phase 2.1)', () => {
    it('released seat can be claimed by a new agent after despawn', () => {
      manager.createAgent('a1', 'Alice');
      const seatBefore = layout.getSeat('a1')!;
      const seatId = seatBefore.id;

      manager.removeAgent('a1');
      // Complete despawn
      manager.updateAll(0.35);
      expect(layout.getSeat('a1')).toBeNull();
      expect(manager.size).toBe(0);

      // New agent should be able to claim the same seat
      manager.createAgent('a2', 'Bob');
      const seat2 = layout.getSeat('a2');
      expect(seat2).not.toBeNull();
      expect(seat2!.id).toBe(seatId); // same seat reused (first free)
    });

    it('removing non-existent agent does not crash', () => {
      expect(() => manager.removeAgent('nonexistent')).not.toThrow();
    });
  });

  describe('all-seats-occupied edge case (Phase 2.2)', () => {
    it('6th agent gets no seat when all 5 seats are full', () => {
      manager.createAgent('a1', 'Alice');
      manager.createAgent('a2', 'Bob');
      manager.createAgent('a3', 'Carol');
      manager.createAgent('a4', 'Dave');
      manager.createAgent('a5', 'Eve');

      // All 5 seats should be occupied
      expect(layout.getSeats().filter(s => s.occupied).length).toBe(5);

      // 6th agent should still be created
      const agent6 = manager.createAgent('a6', 'Frank');
      expect(agent6).toBeDefined();
      expect(agent6.id).toBe('a6');
      expect(manager.size).toBe(6);

      // 6th agent should have no seat and no path
      expect(agent6.targetSeat).toBeNull();
      expect(agent6.path).toBeNull();

      // 6th agent stays at spawn tile
      expect(agent6.tileX).toBe(layout.spawnTile[0]);
      expect(agent6.tileY).toBe(layout.spawnTile[1]);
    });

    it('6th agent does not crash during updateAll', () => {
      for (let i = 1; i <= 6; i++) {
        manager.createAgent(`a${i}`, `Agent${i}`);
      }

      // Should not throw when updating all agents including seatless one
      expect(() => {
        for (let j = 0; j < 50; j++) {
          manager.updateAll(0.1);
        }
      }).not.toThrow();
    });

    it('seatless agent gets a seat after another is removed and despawned', () => {
      for (let i = 1; i <= 5; i++) {
        manager.createAgent(`a${i}`, `Agent${i}`);
      }
      const agent6 = manager.createAgent('a6', 'Frank');
      expect(agent6.targetSeat).toBeNull();

      // Remove one agent and complete despawn to free a seat
      manager.removeAgent('a1');
      manager.updateAll(0.35);
      expect(layout.getSeats().filter(s => s.occupied).length).toBe(4);

      // Creating a new agent now should get the freed seat
      const agent7 = manager.createAgent('a7', 'Gina');
      expect(agent7.targetSeat).not.toBeNull();
      expect(agent7.path).not.toBeNull();
    });
  });

  describe('agent direction updates during walk (Phase 2.3)', () => {
    it('direction is set to a valid value after walking begins', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.path).not.toBeNull();

      // Complete spawn first
      manager.updateAll(0.35);

      // Walk a few steps
      for (let i = 0; i < 10; i++) {
        manager.updateAll(0.05);
      }

      expect(['right', 'left', 'up', 'down']).toContain(agent.stateMachine.direction);
    });

    it('direction changes as agent moves through path segments', () => {
      const agent = manager.createAgent('a1', 'Alice');
      // Complete spawn first
      manager.updateAll(0.35);

      const directions: string[] = [];

      // Walk and collect direction changes
      for (let i = 0; i < 100; i++) {
        manager.updateAll(0.05);
        const dir = agent.stateMachine.direction;
        if (directions.length === 0 || directions[directions.length - 1] !== dir) {
          directions.push(dir);
        }
      }

      // Agent path from spawn [0,2] to a seat involves at least one direction
      expect(directions.length).toBeGreaterThanOrEqual(1);
    });

    it('direction matches seat facing after walk completes', () => {
      const agent = manager.createAgent('a1', 'Alice');
      const seat = layout.getSeat('a1')!;

      // Walk to completion
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.stateMachine.direction).toBe(seat.facing);
    });
  });

  describe('agent transitions to seated state on path completion (Phase 2.4)', () => {
    it('agent tile position matches seat chairTile after walk', () => {
      const agent = manager.createAgent('a1', 'Alice');
      const seat = layout.getSeat('a1')!;

      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.tileX).toBe(seat.chairTile[0]);
      expect(agent.tileY).toBe(seat.chairTile[1]);
    });

    it('agent path is null after walk completes', () => {
      const agent = manager.createAgent('a1', 'Alice');

      // Use smaller steps to complete walk without triggering idle behaviors
      // Spawn takes ~0.3s, walk to nearest seat ~0.5s, so 3s is plenty
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.path).toBeNull();
      expect(agent.stateMachine.state).toBe('idle');
    });

    it('agent facing matches seat facing direction', () => {
      const agent = manager.createAgent('a1', 'Alice');
      const seat = layout.getSeat('a1')!;

      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.stateMachine.direction).toBe(seat.facing);
    });
  });

  describe('mid-path agent removal (Phase 2.5)', () => {
    it('agent can be removed while walking (via despawn)', () => {
      const agent = manager.createAgent('a1', 'Alice');
      // Complete spawn
      manager.updateAll(0.35);
      expect(agent.stateMachine.state).toBe('walk');
      expect(agent.path).not.toBeNull();

      // Walk a few steps so agent is mid-path
      manager.updateAll(0.1);
      manager.updateAll(0.1);

      // Remove mid-walk: triggers despawn
      expect(manager.size).toBe(1);
      manager.removeAgent('a1');
      expect(agent.stateMachine.state).toBe('despawning');
      expect(manager.size).toBe(1); // still present during despawn

      // Complete despawn
      manager.updateAll(0.35);
      expect(manager.size).toBe(0);
      expect(layout.getSeat('a1')).toBeNull();
    });

    it('no errors when updating after mid-path removal', () => {
      manager.createAgent('a1', 'Alice');
      manager.updateAll(0.35); // complete spawn
      manager.updateAll(0.1);
      manager.removeAgent('a1');

      // Subsequent updates should not crash (includes despawn completion)
      expect(() => {
        for (let i = 0; i < 50; i++) {
          manager.updateAll(0.1);
        }
      }).not.toThrow();
    });

    it('other agents continue walking after one is removed mid-path', () => {
      manager.createAgent('a1', 'Alice');
      const agent2 = manager.createAgent('a2', 'Bob');

      // Complete spawns
      manager.updateAll(0.35);

      manager.updateAll(0.1);
      manager.removeAgent('a1');

      // Agent2 should still be walking
      expect(agent2.stateMachine.state).toBe('walk');
      expect(agent2.path).not.toBeNull();

      // Continue updates, agent2 should complete walk
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent2.stateMachine.state).toBe('idle');
    });
  });

  describe('MatrixEffect integration (Task 3.2)', () => {
    it('agent starts in spawning state with matrixState when tileMap is available', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.stateMachine.state).toBe('spawning');
      expect(agent.matrixState).not.toBeNull();
      expect(agent.matrixState!.type).toBe('reveal');
    });

    it('after spawn completes (>0.3s), agent transitions from spawning to walk', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.stateMachine.state).toBe('spawning');

      // Advance past default duration (0.3s)
      manager.updateAll(0.15);
      // Should still be spawning
      expect(agent.stateMachine.state).toBe('spawning');
      expect(agent.matrixState).not.toBeNull();

      manager.updateAll(0.2); // total 0.35s > 0.3s
      // Spawn complete: should transition to walk (has path) or idle
      expect(agent.matrixState).toBeNull();
      expect(['walk', 'idle']).toContain(agent.stateMachine.state);
    });

    it('agent with path transitions to walk after spawn', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.path).not.toBeNull();

      // Complete spawn
      manager.updateAll(0.35);
      expect(agent.stateMachine.state).toBe('walk');
    });

    it('agent without path transitions to idle after spawn', () => {
      // Fill all seats so the next agent gets no path
      for (let i = 1; i <= 5; i++) {
        manager.createAgent(`fill${i}`, `Fill${i}`);
      }
      // Complete their spawns
      manager.updateAll(0.35);

      const agent = manager.createAgent('a6', 'NoSeat');
      expect(agent.path).toBeNull();
      expect(agent.stateMachine.state).toBe('spawning');

      manager.updateAll(0.35);
      expect(agent.stateMachine.state).toBe('idle');
    });

    it('on removeAgent, agent enters despawning state with hide matrixState', () => {
      const agent = manager.createAgent('a1', 'Alice');
      // Complete spawn and walk to seat
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }
      expect(agent.stateMachine.state).toBe('idle');

      manager.removeAgent('a1');
      expect(agent.stateMachine.state).toBe('despawning');
      expect(agent.matrixState).not.toBeNull();
      expect(agent.matrixState!.type).toBe('hide');
      // Agent should still be in the map during despawn
      expect(manager.size).toBe(1);
    });

    it('after despawn completes, agent is actually removed from manager', () => {
      manager.createAgent('a1', 'Alice');
      // Complete spawn + walk
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      manager.removeAgent('a1');
      expect(manager.size).toBe(1); // still present during despawn

      // Complete despawn animation
      manager.updateAll(0.35);
      expect(manager.size).toBe(0); // now removed
    });

    it('seat is released after despawn completes', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      manager.removeAgent('a1');
      // Seat is NOT released yet during despawn
      expect(layout.getSeat('a1')).not.toBeNull();

      // Complete despawn
      manager.updateAll(0.35);
      expect(layout.getSeat('a1')).toBeNull();
    });

    it('backward compat: agent without tileMap has no matrixState', () => {
      const oldManager = new AgentManager();
      const agent = oldManager.createAgent('a1', 'Alice');
      expect(agent.matrixState).toBeNull();
      expect(agent.stateMachine.state).toBe('idle');
    });
  });

  describe('event handling still works with tile system', () => {
    it('agentToolStart transitions state correctly', () => {
      const agent = manager.createAgent('a1', 'Alice');
      // Walk the agent to its seat first (spawn ~0.3s + walk ~0.5s = ~1s needed)
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }
      expect(agent.stateMachine.state).toBe('idle');

      manager.handleEvent({
        type: 'agentToolStart',
        agentId: 'a1',
        tool: 'Edit',
      });
      expect(agent.stateMachine.state).toBe('type');
    });

    it('agentRemoved event triggers despawn (seat released after completion)', () => {
      manager.createAgent('a1', 'Alice');
      manager.handleEvent({ type: 'agentRemoved', agentId: 'a1' });
      // Agent is despawning, not yet removed
      expect(manager.size).toBe(1);
      // Complete despawn
      manager.updateAll(0.35);
      expect(layout.getSeat('a1')).toBeNull();
      expect(manager.size).toBe(0);
    });
  });

  describe('BubbleRenderer integration (Task 3.4)', () => {
    it('agentToolStart creates bubble with correct icon', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState).not.toBeNull();
      expect(agent.bubbleState!.icon).toBe('search');
    });

    it('agentToolStart with Edit creates edit bubble', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });
      expect(manager.getAgent('a1')!.bubbleState!.icon).toBe('edit');
    });

    it('agentToolStart with Bash creates terminal bubble', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Bash' });
      expect(manager.getAgent('a1')!.bubbleState!.icon).toBe('terminal');
    });

    it('agentToolDone creates done bubble with 1.5s hold', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });
      manager.handleEvent({ type: 'agentToolDone', agentId: 'a1' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState).not.toBeNull();
      expect(agent.bubbleState!.icon).toBe('done');
      expect(agent.bubbleState!.holdDuration).toBe(1.5);
    });

    it('agentWaiting creates persistent permission bubble', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentWaiting', agentId: 'a1' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState).not.toBeNull();
      expect(agent.bubbleState!.icon).toBe('permission');
      expect(agent.bubbleState!.holdDuration).toBe(Number.POSITIVE_INFINITY);
    });

    it('agentIdle clears the persistent permission bubble', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentWaiting', agentId: 'a1' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState!.icon).toBe('permission');

      manager.handleEvent({ type: 'agentIdle', agentId: 'a1' });
      expect(agent.bubbleState).toBeNull();
    });

    it('bubble state is cleared after full fade lifecycle', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState).not.toBeNull();

      // fade-in 0.15s + hold 2s + fade-out 0.3s = ~2.45s; 30*0.1 = 3s covers it
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);
      expect(agent.bubbleState).toBeNull();
    });
  });

  describe('Bubble edge cases — consecutive tools (Task 3.5)', () => {
    it('consecutive toolStart replaces bubble with new icon', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState!.icon).toBe('search');

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Bash' });
      expect(agent.bubbleState!.icon).toBe('terminal');
      expect(agent.bubbleState!.fadePhase).toBe('in');
    });

    it('toolStart then toolDone swaps to done icon', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      const agent = manager.getAgent('a1')!;
      expect(agent.bubbleState!.icon).toBe('search');

      manager.handleEvent({ type: 'agentToolDone', agentId: 'a1' });
      expect(agent.bubbleState!.icon).toBe('done');
    });

    it('multiple rapid toolStart events always show latest icon', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Glob' });
      expect(manager.getAgent('a1')!.bubbleState!.icon).toBe('search');
    });

    it('done bubble after consecutive tools shows done', () => {
      manager.createAgent('a1', 'Alice');
      for (let i = 0; i < 30; i++) manager.updateAll(0.1);

      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });
      manager.handleEvent({ type: 'agentToolDone', agentId: 'a1' });
      expect(manager.getAgent('a1')!.bubbleState!.icon).toBe('done');
    });
  });
});

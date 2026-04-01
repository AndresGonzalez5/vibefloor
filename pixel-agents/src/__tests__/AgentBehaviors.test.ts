import { describe, it, expect, beforeEach, vi } from 'vitest';
import { AgentManager } from '../engine/AgentManager';
import { TileMap } from '../engine/TileMap';
import { OfficeLayout } from '../engine/OfficeLayout';

/** Helper: walk agent to seat (spawn + walk), with high idle threshold to prevent behaviors. */
function walkToSeat(manager: AgentManager, ids?: string[]): void {
  // Suppress idle behaviors during walk-to-seat
  if (ids) {
    for (const id of ids) {
      const a = manager.getAgent(id);
      if (a) a.idleThreshold = 9999;
    }
  } else {
    // Suppress for all agents
    for (const a of manager.getAgents()) {
      a.idleThreshold = 9999;
    }
  }
  for (let i = 0; i < 30; i++) {
    manager.updateAll(0.1);
  }
}

/** Helper: suppress idle behaviors on all agents. */
function suppressIdle(manager: AgentManager): void {
  for (const a of manager.getAgents()) {
    a.idleThreshold = 9999;
    a.idleTimer = 0;
  }
}

describe('Phase 4: Agent Behaviors', () => {
  let tileMap: TileMap;
  let layout: OfficeLayout;
  let manager: AgentManager;

  beforeEach(() => {
    layout = new OfficeLayout();
    tileMap = new TileMap(layout.cols, layout.rows, layout.tileSize, layout.zoom);
    layout.initBlockedTiles(tileMap);
    manager = new AgentManager(tileMap, layout);
  });

  // ---- Task 4.1: Idle timer and micro-behavior selection ----

  describe('idle timer and micro-behaviors (Task 4.1)', () => {
    it('idle agent triggers micro-behavior after exceeding idleThreshold', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999; // suppress during walk
      walkToSeat(manager);
      expect(agent.stateMachine.state).toBe('idle');

      // Now set a low threshold
      agent.idleThreshold = 0.5;
      agent.idleTimer = 0;

      // Accumulate time past threshold
      manager.updateAll(0.6);

      // After idle threshold is exceeded, one of these should be true:
      const behaviorTriggered =
        agent.idleBehavior !== null ||
        agent.wanderState !== null;
      expect(behaviorTriggered).toBe(true);
    });

    it('toolStart event resets idleTimer to 0', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);

      // Accumulate some idle time
      manager.updateAll(2.0);
      expect(agent.idleTimer).toBeGreaterThan(0);

      // Send tool event
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });
      expect(agent.idleTimer).toBe(0);
    });

    it('idleTimer resets and threshold re-randomizes after behavior completes', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);

      // Force head turn behavior with controlled random
      agent.idleThreshold = 0.1;
      agent.idleTimer = 0;

      const randomSpy = vi.spyOn(Math, 'random');
      randomSpy.mockReturnValue(0.5); // will trigger head turn (0.3-0.65 range)
      manager.updateAll(0.2); // exceed threshold
      randomSpy.mockRestore();

      expect(agent.idleBehavior).toBe('headTurn');
      expect(agent.idleTimer).toBe(0);

      // Wait for behavior to complete (duration = 2 + 0.5 = 2.5s)
      // Suppress further idle triggers during completion
      agent.idleThreshold = 9999;
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.idleBehavior).toBeNull();
    });

    it('head turn changes direction temporarily then restores', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);
      const seatFacing = agent.stateMachine.direction; // 'up' for seat 0

      // Force head turn
      agent.idleThreshold = 0.1;
      agent.idleTimer = 0;
      const randomSpy = vi.spyOn(Math, 'random');
      randomSpy.mockReturnValue(0.4); // head turn range (0.3-0.65)
      manager.updateAll(0.2);
      randomSpy.mockRestore();

      expect(agent.idleBehavior).toBe('headTurn');
      expect(agent.savedDirection).toBe(seatFacing);

      // Complete the behavior (duration = 2 + 0.4 = 2.4s)
      agent.idleThreshold = 9999; // prevent re-trigger
      for (let i = 0; i < 30; i++) {
        manager.updateAll(0.1);
      }

      // Direction should be restored
      expect(agent.stateMachine.direction).toBe(seatFacing);
      expect(agent.idleBehavior).toBeNull();
    });

    it('fidget temporarily transitions to wandering state then back to idle', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);

      // Force fidget
      agent.idleThreshold = 0.1;
      agent.idleTimer = 0;
      const randomSpy = vi.spyOn(Math, 'random');
      randomSpy.mockReturnValue(0.9); // >= 0.65 triggers fidget
      manager.updateAll(0.2);
      randomSpy.mockRestore();

      expect(agent.idleBehavior).toBe('fidget');
      expect(agent.stateMachine.state).toBe('wandering'); // uses walk frames

      // Complete fidget (duration = 1 + 0.9 = 1.9s)
      agent.idleThreshold = 9999; // prevent re-trigger
      for (let i = 0; i < 25; i++) {
        manager.updateAll(0.1);
      }

      expect(agent.idleBehavior).toBeNull();
      expect(agent.stateMachine.state).toBe('idle');
    });
  });

  // ---- Task 4.2: Idle wander ----

  describe('idle wander (Task 4.2)', () => {
    it('wander: agent walks away from seat, pauses, returns', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);
      const seatTile = { x: agent.tileX, y: agent.tileY };
      expect(agent.stateMachine.state).toBe('idle');

      // Force wander
      agent.idleThreshold = 0.1;
      agent.idleTimer = 0;
      const randomSpy = vi.spyOn(Math, 'random');
      randomSpy.mockReturnValue(0.1); // < 0.3 triggers wander
      manager.updateAll(0.2);
      randomSpy.mockRestore();

      // Should be wandering
      expect(agent.wanderState).toBe('going');
      expect(agent.stateMachine.state).toBe('wandering');
      expect(agent.path).not.toBeNull();

      // Suppress idle behaviors to prevent re-triggering after wander completes
      agent.idleThreshold = 9999;

      // Walk to target, pause, and return (wander targets are within 2-4 tiles,
      // pause 2-4s, return path ~same, so ~15s should be enough)
      for (let i = 0; i < 150; i++) {
        manager.updateAll(0.1);
      }

      // After enough time, agent should be back at seat in idle
      expect(agent.wanderState).toBeNull();
      expect(agent.stateMachine.state).toBe('idle');
      expect(agent.tileX).toBe(seatTile.x);
      expect(agent.tileY).toBe(seatTile.y);
    });

    it('wander goes through going -> pausing -> returning phases', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);

      // Force wander
      agent.idleThreshold = 0.1;
      agent.idleTimer = 0;
      const randomSpy = vi.spyOn(Math, 'random');
      randomSpy.mockReturnValue(0.1);
      manager.updateAll(0.2);
      randomSpy.mockRestore();

      expect(agent.wanderState).toBe('going');
      agent.idleThreshold = 9999;

      // Walk and observe phases
      let seenPausing = false;
      let seenReturning = false;
      for (let i = 0; i < 150; i++) {
        manager.updateAll(0.1);
        if (agent.wanderState === 'pausing') seenPausing = true;
        if (agent.wanderState === 'returning') seenReturning = true;
      }

      expect(seenPausing).toBe(true);
      expect(seenReturning).toBe(true);
    });
  });

  // ---- Task 4.3: Per-agent choreography queue and subagent spawn sequence ----

  describe('subagent spawn choreography (Task 4.3)', () => {
    it('parent enters briefing state when subagent is created', () => {
      const parent = manager.createAgent('parent', 'Main');
      walkToSeat(manager);
      expect(parent.stateMachine.state).toBe('idle');

      // Create subagent with parentAgentId
      manager.handleEvent({
        type: 'agentCreated',
        agentId: 'sub1',
        name: 'Sub',
        parentAgentId: 'parent',
      });

      // Parent should be in choreography
      expect(parent.choreographyActive).toBe(true);

      // Run until parent reaches briefing state
      let seenBriefing = false;
      for (let i = 0; i < 50; i++) {
        manager.updateAll(0.1);
        suppressIdle(manager);
        if (parent.stateMachine.state === 'briefing') seenBriefing = true;
      }
      expect(seenBriefing).toBe(true);
    });

    it('both agents end at seats in idle after choreography completes', () => {
      const parent = manager.createAgent('parent', 'Main');
      walkToSeat(manager);

      manager.handleEvent({
        type: 'agentCreated',
        agentId: 'sub1',
        name: 'Sub',
        parentAgentId: 'parent',
      });

      // Run choreography to completion, suppressing idle behaviors
      for (let i = 0; i < 200; i++) {
        manager.updateAll(0.1);
        suppressIdle(manager);
      }

      // Parent should be back at seat, idle, choreography done
      expect(parent.choreographyActive).toBe(false);
      expect(parent.stateMachine.state).toBe('idle');

      // Subagent should exist and be at its seat
      const sub = manager.getAgent('sub1');
      expect(sub).toBeDefined();
      expect(sub!.stateMachine.state).toBe('idle');
    });

    it('subagent is created with parentAgentId set', () => {
      manager.createAgent('parent', 'Main');
      walkToSeat(manager);

      manager.handleEvent({
        type: 'agentCreated',
        agentId: 'sub1',
        name: 'Sub',
        parentAgentId: 'parent',
      });

      // Run until subagent is created
      for (let i = 0; i < 100; i++) {
        manager.updateAll(0.1);
        suppressIdle(manager);
      }

      const sub = manager.getAgent('sub1');
      expect(sub).toBeDefined();
      expect(sub!.parentAgentId).toBe('parent');
    });
  });

  // ---- Task 4.4: Subagent despawn choreography ----

  describe('subagent despawn choreography (Task 4.4)', () => {
    it('subagent enters reporting choreography when removed', () => {
      // Create parent and subagent
      manager.createAgent('parent', 'Main');
      walkToSeat(manager);

      manager.handleEvent({
        type: 'agentCreated',
        agentId: 'sub1',
        name: 'Sub',
        parentAgentId: 'parent',
      });

      // Let choreography complete
      for (let i = 0; i < 200; i++) {
        manager.updateAll(0.1);
        suppressIdle(manager);
      }

      const sub = manager.getAgent('sub1')!;
      expect(sub.stateMachine.state).toBe('idle');

      // Remove subagent
      manager.handleEvent({ type: 'agentRemoved', agentId: 'sub1' });

      // Subagent should be in reporting choreography
      expect(sub.choreographyActive).toBe(true);

      // Run until subagent is fully removed
      let seenReporting = false;
      for (let i = 0; i < 100; i++) {
        manager.updateAll(0.1);
        const s = manager.getAgent('sub1');
        if (s && s.stateMachine.state === 'reporting') seenReporting = true;
      }
      expect(seenReporting).toBe(true);

      // Subagent should be removed after reporting + despawn
      expect(manager.getAgent('sub1')).toBeUndefined();
      // Seat should be released
      expect(layout.getSeat('sub1')).toBeNull();
    });

    it('subagent despawns at current position when parent is already removed', () => {
      manager.createAgent('parent', 'Main');
      walkToSeat(manager);

      manager.handleEvent({
        type: 'agentCreated',
        agentId: 'sub1',
        name: 'Sub',
        parentAgentId: 'parent',
      });

      // Complete choreography
      for (let i = 0; i < 200; i++) {
        manager.updateAll(0.1);
        suppressIdle(manager);
      }

      // Remove parent first
      manager.removeAgent('parent');
      for (let i = 0; i < 10; i++) manager.updateAll(0.1); // complete despawn

      expect(manager.getAgent('parent')).toBeUndefined();

      // Now remove subagent — should despawn without walking
      const sub = manager.getAgent('sub1')!;

      manager.handleEvent({ type: 'agentRemoved', agentId: 'sub1' });

      // Should enter reporting directly (no walk, phase 11)
      expect(sub.choreographyPhase).toBe(11);
      expect(sub.stateMachine.state).toBe('reporting');

      // Complete reporting + despawn
      for (let i = 0; i < 50; i++) {
        manager.updateAll(0.1);
      }

      expect(manager.getAgent('sub1')).toBeUndefined();
    });
  });

  // ---- Task 4.5: Event buffering during non-interruptible states ----

  describe('event buffering (Task 4.5)', () => {
    it('agent in spawning state buffers agentToolStart and replays after spawn', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.stateMachine.state).toBe('spawning');

      // Send tool event during spawn
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });

      // Should be buffered, not applied
      expect(agent.stateMachine.state).toBe('spawning');
      expect(agent.eventBuffer.length).toBe(1);

      // Complete spawn
      manager.updateAll(0.35);

      // After spawn completes, buffered event should be replayed
      expect(agent.eventBuffer.length).toBe(0);
    });

    it('agent in wandering state is interrupted by agentToolStart', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);
      const seatTileX = agent.tileX;
      const seatTileY = agent.tileY;

      // Start wandering
      agent.idleThreshold = 0.1;
      agent.idleTimer = 0;
      const randomSpy = vi.spyOn(Math, 'random');
      randomSpy.mockReturnValue(0.1); // force wander
      manager.updateAll(0.2);
      randomSpy.mockRestore();

      expect(agent.wanderState).toBe('going');
      // Walk a bit so agent leaves its seat
      manager.updateAll(0.1);

      // Send tool event — should interrupt wander
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });

      // Wander should be interrupted
      expect(agent.wanderState).toBeNull();
      // Agent should be snapped back to seat
      expect(agent.tileX).toBe(seatTileX);
      expect(agent.tileY).toBe(seatTileY);
      // Tool state should be applied immediately
      expect(agent.stateMachine.state).toBe('type');
      // No buffered events
      expect(agent.eventBuffer.length).toBe(0);
    });

    it('safety timeout does NOT apply to spawning/despawning/briefing/reporting states', () => {
      const agent = manager.createAgent('a1', 'Alice');
      agent.idleThreshold = 9999;
      walkToSeat(manager);

      // Transition to briefing and set lastEventTime far in the past
      agent.stateMachine.transition('briefing');
      agent.lastEventTime = performance.now() - 60_000; // 60s ago

      manager.updateAll(0.1);

      // Should still be in briefing (not forced to idle by safety timeout)
      expect(agent.stateMachine.state).toBe('briefing');

      // Test spawning
      const agent2 = manager.createAgent('a2', 'Bob');
      agent2.lastEventTime = performance.now() - 60_000;
      manager.updateAll(0.1);
      expect(agent2.stateMachine.state).toBe('spawning');

      // Test reporting
      agent.stateMachine.transition('reporting');
      agent.lastEventTime = performance.now() - 60_000;
      manager.updateAll(0.1);
      expect(agent.stateMachine.state).toBe('reporting');
    });

    it('choreography-active agent buffers tool events and replays after completion', () => {
      const parent = manager.createAgent('parent', 'Main');
      walkToSeat(manager);

      // Start choreography
      manager.handleEvent({
        type: 'agentCreated',
        agentId: 'sub1',
        name: 'Sub',
        parentAgentId: 'parent',
      });
      expect(parent.choreographyActive).toBe(true);

      // Send tool event to parent during choreography
      manager.handleEvent({ type: 'agentToolStart', agentId: 'parent', tool: 'Read' });
      expect(parent.eventBuffer.length).toBe(1);

      // Complete choreography
      for (let i = 0; i < 200; i++) {
        manager.updateAll(0.1);
        suppressIdle(manager);
      }

      // After choreography, buffered event should have been replayed
      expect(parent.eventBuffer.length).toBe(0);
      expect(parent.choreographyActive).toBe(false);
    });

    it('multiple tool events buffer in order during non-interruptible state', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.stateMachine.state).toBe('spawning');

      // Buffer multiple events
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Read' });
      manager.handleEvent({ type: 'agentToolDone', agentId: 'a1' });
      manager.handleEvent({ type: 'agentToolStart', agentId: 'a1', tool: 'Edit' });

      expect(agent.eventBuffer.length).toBe(3);
      expect(agent.eventBuffer[0].type).toBe('agentToolStart');
      expect(agent.eventBuffer[0].tool).toBe('Read');
      expect(agent.eventBuffer[1].type).toBe('agentToolDone');
      expect(agent.eventBuffer[2].tool).toBe('Edit');

      // Complete spawn — events should replay
      manager.updateAll(0.35);
      expect(agent.eventBuffer.length).toBe(0);
      // Last event was agentToolStart Edit -> state should be 'type'
      expect(agent.stateMachine.state).toBe('type');
    });

    it('agentWaiting event is also buffered during non-interruptible states', () => {
      const agent = manager.createAgent('a1', 'Alice');
      expect(agent.stateMachine.state).toBe('spawning');

      manager.handleEvent({ type: 'agentWaiting', agentId: 'a1' });
      expect(agent.eventBuffer.length).toBe(1);
      expect(agent.stateMachine.state).toBe('spawning'); // not wait

      // Complete spawn
      manager.updateAll(0.35);
      expect(agent.eventBuffer.length).toBe(0);
    });
  });
});

import { describe, it, expect } from 'vitest';
import { AgentStateMachine, toolToState } from '../engine/AgentStateMachine';

describe('toolToState', () => {
  it('maps "Edit" to "type"', () => {
    expect(toolToState('Edit')).toBe('type');
  });

  it('maps "Read" to "read"', () => {
    expect(toolToState('Read')).toBe('read');
  });

  it('maps "Bash" to "type"', () => {
    expect(toolToState('Bash')).toBe('type');
  });

  it('maps "Grep" to "read"', () => {
    expect(toolToState('Grep')).toBe('read');
  });

  it('maps "Write" to "type"', () => {
    expect(toolToState('Write')).toBe('type');
  });

  it('maps "Glob" to "read"', () => {
    expect(toolToState('Glob')).toBe('read');
  });

  it('maps "WebFetch" to "read"', () => {
    expect(toolToState('WebFetch')).toBe('read');
  });

  it('maps unknown tools to "type" as default', () => {
    expect(toolToState('UnknownTool')).toBe('type');
  });
});

describe('AgentStateMachine', () => {
  it('starts in idle state', () => {
    const sm = new AgentStateMachine();
    expect(sm.state).toBe('idle');
  });

  it('starts with direction "down"', () => {
    const sm = new AgentStateMachine();
    expect(sm.direction).toBe('down');
  });

  it('getCurrentFrame returns 1 for idle (single-frame anim)', () => {
    const sm = new AgentStateMachine();
    expect(sm.getCurrentFrame()).toBe(1);
  });

  describe('transition', () => {
    it('transitions to "type" state', () => {
      const sm = new AgentStateMachine();
      sm.transition('type');
      expect(sm.state).toBe('type');
    });

    it('transitions to "read" state', () => {
      const sm = new AgentStateMachine();
      sm.transition('read');
      expect(sm.state).toBe('read');
    });

    it('transitions to "walk" state', () => {
      const sm = new AgentStateMachine();
      sm.transition('walk');
      expect(sm.state).toBe('walk');
    });

    it('preserves direction for type and read states (seat facing determines direction)', () => {
      const sm = new AgentStateMachine();
      sm.direction = 'up';
      sm.transition('type');
      expect(sm.direction).toBe('up');

      sm.direction = 'left';
      sm.transition('read');
      expect(sm.direction).toBe('left');
    });

    it('does not change direction for walk state', () => {
      const sm = new AgentStateMachine();
      sm.direction = 'up';
      sm.transition('walk');
      expect(sm.direction).toBe('up');
    });
  });

  describe('frame cycling', () => {
    it('advances frames for "type" state (frames [3,4], duration 0.3)', () => {
      const sm = new AgentStateMachine();
      sm.transition('type');
      expect(sm.getCurrentFrame()).toBe(3); // frameIndex 0 -> frame 3

      sm.update(0.3); // triggers frame advance
      expect(sm.getCurrentFrame()).toBe(4); // frameIndex 1 -> frame 4

      sm.update(0.3); // wraps around
      expect(sm.getCurrentFrame()).toBe(3); // frameIndex 0 -> frame 3
    });

    it('advances frames for "walk" state (frames [0,1,2,1], duration 0.15)', () => {
      const sm = new AgentStateMachine();
      sm.transition('walk');
      expect(sm.getCurrentFrame()).toBe(0); // index 0

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(1); // index 1

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(2); // index 2

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(1); // index 3

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(0); // wraps to index 0
    });

    it('idle state does not advance frames (single frame)', () => {
      const sm = new AgentStateMachine();
      expect(sm.getCurrentFrame()).toBe(1);
      sm.update(5.0); // lots of time passes
      expect(sm.getCurrentFrame()).toBe(1);
    });
  });

  describe('wait state', () => {
    it('transitions to wait state', () => {
      const sm = new AgentStateMachine();
      sm.transition('wait');
      expect(sm.state).toBe('wait');
    });

    it('advances frames for "wait" state (frames [1,1,0,1], duration 0.8)', () => {
      const sm = new AgentStateMachine();
      sm.transition('wait');
      expect(sm.getCurrentFrame()).toBe(1); // index 0

      sm.update(0.8);
      expect(sm.getCurrentFrame()).toBe(1); // index 1

      sm.update(0.8);
      expect(sm.getCurrentFrame()).toBe(0); // index 2

      sm.update(0.8);
      expect(sm.getCurrentFrame()).toBe(1); // index 3

      sm.update(0.8);
      expect(sm.getCurrentFrame()).toBe(1); // wraps to index 0
    });

    it('can transition from wait to type', () => {
      const sm = new AgentStateMachine();
      sm.transition('wait');
      expect(sm.state).toBe('wait');

      sm.transition('type');
      expect(sm.state).toBe('type');
    });
  });

  describe('spawning state', () => {
    it('transitions to spawning state', () => {
      const sm = new AgentStateMachine();
      sm.transition('spawning');
      expect(sm.state).toBe('spawning');
    });

    it('has static frame [1] with 1.0s duration', () => {
      const sm = new AgentStateMachine();
      sm.transition('spawning');
      expect(sm.getCurrentFrame()).toBe(1);
      sm.update(1.0);
      expect(sm.getCurrentFrame()).toBe(1); // single frame, no change
    });

    it('can transition from spawning to walk', () => {
      const sm = new AgentStateMachine();
      sm.transition('spawning');
      sm.transition('walk');
      expect(sm.state).toBe('walk');
    });
  });

  describe('despawning state', () => {
    it('transitions to despawning state', () => {
      const sm = new AgentStateMachine();
      sm.transition('despawning');
      expect(sm.state).toBe('despawning');
    });

    it('has static frame [1] with 1.0s duration', () => {
      const sm = new AgentStateMachine();
      sm.transition('despawning');
      expect(sm.getCurrentFrame()).toBe(1);
      sm.update(2.0);
      expect(sm.getCurrentFrame()).toBe(1);
    });
  });

  describe('wandering state', () => {
    it('transitions to wandering state', () => {
      const sm = new AgentStateMachine();
      sm.transition('wandering');
      expect(sm.state).toBe('wandering');
    });

    it('uses walk frames [0, 1, 2, 1] at 0.15s', () => {
      const sm = new AgentStateMachine();
      sm.transition('wandering');
      expect(sm.getCurrentFrame()).toBe(0);

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(1);

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(2);

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(1);

      sm.update(0.15);
      expect(sm.getCurrentFrame()).toBe(0); // wraps
    });
  });

  describe('briefing state', () => {
    it('transitions to briefing state', () => {
      const sm = new AgentStateMachine();
      sm.transition('briefing');
      expect(sm.state).toBe('briefing');
    });

    it('has static frame [1] with 1.0s duration', () => {
      const sm = new AgentStateMachine();
      sm.transition('briefing');
      expect(sm.getCurrentFrame()).toBe(1);
      sm.update(3.0);
      expect(sm.getCurrentFrame()).toBe(1);
    });

    it('can transition from briefing to idle', () => {
      const sm = new AgentStateMachine();
      sm.transition('briefing');
      sm.transition('idle');
      expect(sm.state).toBe('idle');
    });
  });

  describe('reporting state', () => {
    it('transitions to reporting state', () => {
      const sm = new AgentStateMachine();
      sm.transition('reporting');
      expect(sm.state).toBe('reporting');
    });

    it('has static frame [1] with 1.0s duration', () => {
      const sm = new AgentStateMachine();
      sm.transition('reporting');
      expect(sm.getCurrentFrame()).toBe(1);
      sm.update(3.0);
      expect(sm.getCurrentFrame()).toBe(1);
    });

    it('can transition from reporting to walk', () => {
      const sm = new AgentStateMachine();
      sm.transition('reporting');
      sm.transition('walk');
      expect(sm.state).toBe('walk');
    });
  });
});

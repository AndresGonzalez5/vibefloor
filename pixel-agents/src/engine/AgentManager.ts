// Manages multiple pixel agents and routes events to their state machines.

import type { AgentEvent } from '../types';
import { AgentStateMachine, toolToState } from './AgentStateMachine';
import type { AgentState } from './AgentStateMachine';
import type { Direction } from './SpriteEngine';

export interface Agent {
  id: string;
  name: string;
  palette: number;
  stateMachine: AgentStateMachine;
  x: number;
  y: number;
  lastEventTime: number; // timestamp of last event (performance.now())
}

const AGENT_SPACING = 160;
const BASE_X = 80;
const BASE_Y = 50;
const SAFETY_TIMEOUT_MS = 30_000; // 30 seconds without events → force idle

let nextPalette = 0;

export class AgentManager {
  private agents: Map<string, Agent> = new Map();

  createAgent(id: string, name: string, palette?: number): Agent {
    if (this.agents.has(id)) {
      return this.agents.get(id)!;
    }

    const p = palette ?? nextPalette++ % 6;
    const index = this.agents.size;
    const agent: Agent = {
      id,
      name,
      palette: p,
      stateMachine: new AgentStateMachine(),
      x: BASE_X + index * AGENT_SPACING,
      y: BASE_Y,
      lastEventTime: performance.now(),
    };
    this.agents.set(id, agent);
    return agent;
  }

  removeAgent(id: string): void {
    this.agents.delete(id);
  }

  updateAll(dt: number): void {
    const now = performance.now();
    for (const agent of this.agents.values()) {
      agent.stateMachine.update(dt);
      // Safety timeout: if agent has been non-idle for >30s without events, force idle
      if (
        agent.stateMachine.state !== 'idle' &&
        now - agent.lastEventTime > SAFETY_TIMEOUT_MS
      ) {
        agent.stateMachine.transition('idle');
      }
    }
  }

  getAgents(): Agent[] {
    return Array.from(this.agents.values()).sort((a, b) => a.y - b.y);
  }

  getAgent(id: string): Agent | undefined {
    return this.agents.get(id);
  }

  get size(): number {
    return this.agents.size;
  }

  handleEvent(event: AgentEvent): void {
    switch (event.type) {
      case 'agentCreated': {
        this.createAgent(event.agentId, event.name ?? 'Agent', event.palette);
        break;
      }
      case 'agentRemoved': {
        this.removeAgent(event.agentId);
        break;
      }
      case 'agentToolStart': {
        // Auto-create agent if it doesn't exist yet (hook events may arrive before agentCreated)
        let agent = this.agents.get(event.agentId);
        if (!agent) {
          agent = this.createAgent(event.agentId, event.name ?? event.agentId, event.palette);
        }
        agent.lastEventTime = performance.now();
        if (event.tool) {
          const newState: AgentState = toolToState(event.tool);
          agent.stateMachine.transition(newState);
        }
        break;
      }
      case 'agentToolDone': {
        const agent = this.agents.get(event.agentId);
        if (agent) {
          agent.lastEventTime = performance.now();
          agent.stateMachine.transition('idle');
        }
        break;
      }
      case 'agentIdle': {
        const agent = this.agents.get(event.agentId);
        if (agent) {
          agent.lastEventTime = performance.now();
          agent.stateMachine.transition('idle');
        }
        break;
      }
      case 'agentWaiting': {
        // Auto-create agent if it doesn't exist yet (same pattern as agentToolStart)
        let agent = this.agents.get(event.agentId);
        if (!agent) {
          agent = this.createAgent(event.agentId, event.name ?? event.agentId, event.palette);
        }
        agent.lastEventTime = performance.now();
        agent.stateMachine.transition('wait');
        break;
      }
      case 'agentStatus': {
        // Could be used for walk or other status updates in the future.
        const agent = this.agents.get(event.agentId);
        if (agent && event.status === 'walking') {
          agent.stateMachine.transition('walk');
        }
        break;
      }
      case 'setupProgress': {
        const SETUP_ID = '__setup__';
        if (event.done) {
          const agent = this.agents.get(SETUP_ID);
          if (agent) {
            agent.stateMachine.transition('walk');
            setTimeout(() => this.removeAgent(SETUP_ID), 1500);
          }
        } else {
          if (!this.agents.has(SETUP_ID)) {
            this.createAgent(SETUP_ID, 'Setup', 3);
          }
          const agent = this.agents.get(SETUP_ID)!;
          // Alternate between type and read to look busy
          const state = (event.progress ?? 0) > 0.5 ? 'read' : 'type';
          agent.stateMachine.transition(state);
        }
        break;
      }
    }
  }
}

// Export Direction and AgentState for convenience
export type { Direction, AgentState };

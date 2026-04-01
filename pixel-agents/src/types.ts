// Agent events sent from Swift to JS
export interface AgentEvent {
  type:
    | 'agentCreated'
    | 'agentRemoved'
    | 'agentStatus'
    | 'agentToolStart'
    | 'agentToolDone'
    | 'agentIdle'
    | 'agentWaiting'
    | 'setupProgress';
  agentId: string;
  name?: string;
  palette?: number;
  status?: string;
  tool?: string;
  // setupProgress fields
  step?: string;
  progress?: number;
  done?: boolean;
  // subagent fields
  parentAgentId?: string;
  // error bubble trigger
  error?: boolean;
}

// Window augmentation for the vibefloor bridge
declare global {
  interface Window {
    vibefloor?: {
      postMessage: (msg: unknown) => void;
    };
  }
}

export {};

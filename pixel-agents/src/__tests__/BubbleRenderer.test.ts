import { describe, it, expect } from 'vitest';
import { BubbleRenderer } from '../engine/BubbleRenderer';
import type { BubbleState } from '../engine/BubbleRenderer';

describe('BubbleRenderer', () => {
  describe('show()', () => {
    it('creates state with correct icon', () => {
      const state = BubbleRenderer.show('search');
      expect(state.icon).toBe('search');
    });

    it('starts with opacity 0 and fadePhase "in"', () => {
      const state = BubbleRenderer.show('edit');
      expect(state.opacity).toBe(0);
      expect(state.fadePhase).toBe('in');
      expect(state.timer).toBe(0);
    });

    it('uses default holdDuration of 2s', () => {
      const state = BubbleRenderer.show('terminal');
      expect(state.holdDuration).toBe(2);
    });

    it('accepts custom holdDuration', () => {
      const state = BubbleRenderer.show('done', 1.5);
      expect(state.holdDuration).toBe(1.5);
    });
  });

  describe('iconForTool()', () => {
    it('maps Read to search', () => {
      expect(BubbleRenderer.iconForTool('Read')).toBe('search');
    });

    it('maps Grep to search', () => {
      expect(BubbleRenderer.iconForTool('Grep')).toBe('search');
    });

    it('maps Glob to search', () => {
      expect(BubbleRenderer.iconForTool('Glob')).toBe('search');
    });

    it('maps WebFetch to search', () => {
      expect(BubbleRenderer.iconForTool('WebFetch')).toBe('search');
    });

    it('maps WebSearch to search', () => {
      expect(BubbleRenderer.iconForTool('WebSearch')).toBe('search');
    });

    it('maps Edit to edit', () => {
      expect(BubbleRenderer.iconForTool('Edit')).toBe('edit');
    });

    it('maps Write to edit', () => {
      expect(BubbleRenderer.iconForTool('Write')).toBe('edit');
    });

    it('maps Bash to terminal', () => {
      expect(BubbleRenderer.iconForTool('Bash')).toBe('terminal');
    });

    it('maps NotebookEdit to terminal', () => {
      expect(BubbleRenderer.iconForTool('NotebookEdit')).toBe('terminal');
    });

    it('maps unknown tools to terminal (default)', () => {
      expect(BubbleRenderer.iconForTool('SomeFutureTool')).toBe('terminal');
      expect(BubbleRenderer.iconForTool('')).toBe('terminal');
    });
  });

  describe('update() — fade phases', () => {
    it('increases opacity during fade-in', () => {
      const state = BubbleRenderer.show('search');
      BubbleRenderer.update(state, 0.075); // half of 0.15s fade-in
      expect(state.opacity).toBeCloseTo(0.5, 1);
      expect(state.fadePhase).toBe('in');
    });

    it('transitions to hold after fade-in completes', () => {
      const state = BubbleRenderer.show('search');
      BubbleRenderer.update(state, 0.15);
      expect(state.fadePhase).toBe('hold');
      expect(state.opacity).toBe(1);
      expect(state.timer).toBe(0); // timer resets
    });

    it('stays at opacity 1 during hold', () => {
      const state = BubbleRenderer.show('search', 2);
      BubbleRenderer.update(state, 0.15); // complete fade-in
      BubbleRenderer.update(state, 1.0);  // mid-hold
      expect(state.fadePhase).toBe('hold');
      expect(state.opacity).toBe(1);
    });

    it('transitions to fade-out after hold completes', () => {
      const state = BubbleRenderer.show('search', 1);
      BubbleRenderer.update(state, 0.15); // complete fade-in
      BubbleRenderer.update(state, 1.0);  // complete hold
      expect(state.fadePhase).toBe('out');
      expect(state.timer).toBe(0); // timer resets
    });

    it('decreases opacity during fade-out', () => {
      const state = BubbleRenderer.show('search', 0);
      BubbleRenderer.update(state, 0.15); // complete fade-in
      BubbleRenderer.update(state, 0.01); // complete hold (0s)
      expect(state.fadePhase).toBe('out');
      BubbleRenderer.update(state, 0.15); // half of 0.3s fade-out
      expect(state.opacity).toBeCloseTo(0.5, 1);
    });

    it('returns true while active', () => {
      const state = BubbleRenderer.show('search');
      expect(BubbleRenderer.update(state, 0.01)).toBe(true);
    });

    it('returns false when fade-out completes', () => {
      const state = BubbleRenderer.show('search', 0);
      BubbleRenderer.update(state, 0.15); // fade-in
      BubbleRenderer.update(state, 0.01); // hold (0s)
      const active = BubbleRenderer.update(state, 0.3); // fade-out
      expect(active).toBe(false);
      expect(state.opacity).toBe(0);
    });
  });

  describe('full lifecycle', () => {
    it('goes through in → hold → out → done', () => {
      const state = BubbleRenderer.show('edit', 1);

      // Fade in
      expect(BubbleRenderer.update(state, 0.15)).toBe(true);
      expect(state.fadePhase).toBe('hold');
      expect(state.opacity).toBe(1);

      // Hold
      expect(BubbleRenderer.update(state, 1.0)).toBe(true);
      expect(state.fadePhase).toBe('out');

      // Fade out
      expect(BubbleRenderer.update(state, 0.3)).toBe(false);
      expect(state.opacity).toBe(0);
    });

    it('handles small dt increments correctly', () => {
      const state = BubbleRenderer.show('terminal', 0.5);

      // Many small steps through fade-in (0.15s total)
      for (let i = 0; i < 15; i++) {
        BubbleRenderer.update(state, 0.01);
      }
      expect(state.fadePhase).toBe('hold');
      expect(state.opacity).toBe(1);

      // Small steps through hold (0.5s)
      for (let i = 0; i < 50; i++) {
        BubbleRenderer.update(state, 0.01);
      }
      expect(state.fadePhase).toBe('out');

      // Small steps through fade-out (0.3s)
      let active = true;
      for (let i = 0; i < 30 && active; i++) {
        active = BubbleRenderer.update(state, 0.01);
      }
      expect(active).toBe(false);
    });
  });

  describe('opacity bounds', () => {
    it('opacity never exceeds 1', () => {
      const state = BubbleRenderer.show('search');
      BubbleRenderer.update(state, 10); // way past fade-in
      expect(state.opacity).toBeLessThanOrEqual(1);
    });

    it('opacity never goes below 0', () => {
      const state: BubbleState = {
        icon: 'search',
        opacity: 1,
        fadePhase: 'out',
        timer: 0,
        holdDuration: 0,
      };
      BubbleRenderer.update(state, 10); // way past fade-out
      expect(state.opacity).toBeGreaterThanOrEqual(0);
    });
  });
});

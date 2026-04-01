import { describe, it, expect } from 'vitest';
import { MatrixEffect } from '../engine/MatrixEffect';

describe('MatrixEffect', () => {
  describe('createReveal', () => {
    it('returns state with type=reveal, progress=0, columnsRevealed=0', () => {
      const state = MatrixEffect.createReveal();
      expect(state.type).toBe('reveal');
      expect(state.progress).toBe(0);
      expect(state.columnsRevealed).toBe(0);
    });

    it('defaults duration to 0.3s', () => {
      const state = MatrixEffect.createReveal();
      expect(state.duration).toBe(0.3);
    });

    it('accepts custom duration', () => {
      const state = MatrixEffect.createReveal(0.5);
      expect(state.duration).toBe(0.5);
    });
  });

  describe('createHide', () => {
    it('returns state with type=hide, progress=0, columnsRevealed=16', () => {
      const state = MatrixEffect.createHide();
      expect(state.type).toBe('hide');
      expect(state.progress).toBe(0);
      expect(state.columnsRevealed).toBe(16);
    });

    it('defaults duration to 0.3s', () => {
      const state = MatrixEffect.createHide();
      expect(state.duration).toBe(0.3);
    });

    it('accepts custom duration', () => {
      const state = MatrixEffect.createHide(0.6);
      expect(state.duration).toBe(0.6);
    });
  });

  describe('update', () => {
    it('advances progress on reveal', () => {
      const state = MatrixEffect.createReveal(1.0);
      MatrixEffect.update(state, 0.5);
      expect(state.progress).toBeCloseTo(0.5);
    });

    it('advances progress on hide', () => {
      const state = MatrixEffect.createHide(1.0);
      MatrixEffect.update(state, 0.25);
      expect(state.progress).toBeCloseTo(0.25);
    });

    it('returns true while still active', () => {
      const state = MatrixEffect.createReveal(1.0);
      expect(MatrixEffect.update(state, 0.5)).toBe(true);
    });

    it('returns false when complete', () => {
      const state = MatrixEffect.createReveal(0.3);
      expect(MatrixEffect.update(state, 0.4)).toBe(false);
    });

    it('clamps progress to 1.0', () => {
      const state = MatrixEffect.createReveal(0.3);
      MatrixEffect.update(state, 1.0);
      expect(state.progress).toBe(1.0);
    });

    it('reveal at progress=0.5 has ~8 columns', () => {
      const state = MatrixEffect.createReveal(1.0);
      MatrixEffect.update(state, 0.5);
      expect(state.columnsRevealed).toBe(8);
    });

    it('reveal at progress=1.0 has 16 columns', () => {
      const state = MatrixEffect.createReveal(0.3);
      MatrixEffect.update(state, 0.3);
      expect(state.columnsRevealed).toBe(16);
    });

    it('hide at progress=0.5 has ~8 columns remaining', () => {
      const state = MatrixEffect.createHide(1.0);
      MatrixEffect.update(state, 0.5);
      expect(state.columnsRevealed).toBe(8);
    });

    it('hide at progress=1.0 has 0 columns', () => {
      const state = MatrixEffect.createHide(0.3);
      MatrixEffect.update(state, 0.3);
      expect(state.columnsRevealed).toBe(0);
    });

    it('incremental updates produce correct results', () => {
      const state = MatrixEffect.createReveal(0.3);
      MatrixEffect.update(state, 0.1);
      MatrixEffect.update(state, 0.1);
      MatrixEffect.update(state, 0.1);
      expect(state.progress).toBeCloseTo(1.0);
      expect(state.columnsRevealed).toBe(16);
    });
  });
});

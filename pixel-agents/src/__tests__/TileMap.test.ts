import { describe, it, expect } from 'vitest';
import { TileMap } from '../engine/TileMap';

describe('TileMap', () => {
  describe('constructor', () => {
    it('stores cols, rows, tileSize, zoom', () => {
      const map = new TileMap(14, 5, 16, 3);
      expect(map.cols).toBe(14);
      expect(map.rows).toBe(5);
    });
  });

  describe('tileToPixel / pixelToTile', () => {
    it('converts tile coordinate to pixel position', () => {
      const map = new TileMap(14, 5, 16, 3);
      expect(map.tileToPixel(0, 0)).toEqual({ x: 0, y: 0 });
      expect(map.tileToPixel(1, 0)).toEqual({ x: 48, y: 0 });
      expect(map.tileToPixel(0, 1)).toEqual({ x: 0, y: 48 });
      expect(map.tileToPixel(3, 2)).toEqual({ x: 144, y: 96 });
    });

    it('converts pixel position to tile coordinate', () => {
      const map = new TileMap(14, 5, 16, 3);
      expect(map.pixelToTile(0, 0)).toEqual([0, 0]);
      expect(map.pixelToTile(48, 0)).toEqual([1, 0]);
      expect(map.pixelToTile(50, 50)).toEqual([1, 1]); // fractional rounds down
      expect(map.pixelToTile(144, 96)).toEqual([3, 2]);
    });
  });

  describe('block / unblock / isWalkable', () => {
    it('all tiles are walkable by default', () => {
      const map = new TileMap(14, 5, 16, 3);
      expect(map.isWalkable(0, 0)).toBe(true);
      expect(map.isWalkable(13, 4)).toBe(true);
    });

    it('blocked tiles are not walkable', () => {
      const map = new TileMap(14, 5, 16, 3);
      map.block(3, 2);
      expect(map.isWalkable(3, 2)).toBe(false);
      expect(map.isWalkable(3, 1)).toBe(true); // other tiles unaffected
    });

    it('unblock makes tile walkable again', () => {
      const map = new TileMap(14, 5, 16, 3);
      map.block(3, 2);
      expect(map.isWalkable(3, 2)).toBe(false);
      map.unblock(3, 2);
      expect(map.isWalkable(3, 2)).toBe(true);
    });

    it('out-of-bounds tiles are not walkable', () => {
      const map = new TileMap(14, 5, 16, 3);
      expect(map.isWalkable(-1, 0)).toBe(false);
      expect(map.isWalkable(0, -1)).toBe(false);
      expect(map.isWalkable(14, 0)).toBe(false);
      expect(map.isWalkable(0, 5)).toBe(false);
    });
  });

  describe('findPath (BFS)', () => {
    it('returns path from start to end on open grid', () => {
      const map = new TileMap(5, 5, 16, 3);
      const path = map.findPath([0, 0], [2, 0]);
      expect(path.length).toBeGreaterThan(0);
      expect(path[0]).toEqual([0, 0]);
      expect(path[path.length - 1]).toEqual([2, 0]);
    });

    it('returns empty array when no path exists', () => {
      const map = new TileMap(3, 1, 16, 3);
      map.block(1, 0); // blocks the only path
      const path = map.findPath([0, 0], [2, 0]);
      expect(path).toEqual([]);
    });

    it('returns single-element path when start equals end', () => {
      const map = new TileMap(5, 5, 16, 3);
      const path = map.findPath([2, 2], [2, 2]);
      expect(path).toEqual([[2, 2]]);
    });

    it('finds path around obstacles', () => {
      const map = new TileMap(5, 3, 16, 3);
      // Block a column except bottom row
      map.block(2, 0);
      map.block(2, 1);
      // Path from (0,0) to (4,0) must go through row 2
      const path = map.findPath([0, 0], [4, 0]);
      expect(path.length).toBeGreaterThan(0);
      expect(path[0]).toEqual([0, 0]);
      expect(path[path.length - 1]).toEqual([4, 0]);
      // Verify path doesn't go through blocked tiles
      for (const [col, row] of path) {
        expect(map.isWalkable(col, row)).toBe(true);
      }
    });

    it('returns empty array when start is blocked', () => {
      const map = new TileMap(5, 5, 16, 3);
      map.block(0, 0);
      const path = map.findPath([0, 0], [2, 2]);
      expect(path).toEqual([]);
    });

    it('returns empty array when end is blocked', () => {
      const map = new TileMap(5, 5, 16, 3);
      map.block(2, 2);
      const path = map.findPath([0, 0], [2, 2]);
      expect(path).toEqual([]);
    });

    it('path is contiguous (each step differs by 1 in one axis)', () => {
      const map = new TileMap(5, 5, 16, 3);
      const path = map.findPath([0, 0], [4, 4]);
      for (let i = 1; i < path.length; i++) {
        const dc = Math.abs(path[i][0] - path[i - 1][0]);
        const dr = Math.abs(path[i][1] - path[i - 1][1]);
        expect(dc + dr).toBe(1); // Manhattan distance = 1 per step
      }
    });

    it('returns empty array when start is out of bounds', () => {
      const map = new TileMap(5, 5, 16, 3);
      expect(map.findPath([-1, 0], [2, 2])).toEqual([]);
      expect(map.findPath([0, -1], [2, 2])).toEqual([]);
      expect(map.findPath([5, 0], [2, 2])).toEqual([]);
      expect(map.findPath([0, 5], [2, 2])).toEqual([]);
    });

    it('returns empty array when end is out of bounds', () => {
      const map = new TileMap(5, 5, 16, 3);
      expect(map.findPath([2, 2], [-1, 0])).toEqual([]);
      expect(map.findPath([2, 2], [0, -1])).toEqual([]);
      expect(map.findPath([2, 2], [5, 0])).toEqual([]);
      expect(map.findPath([2, 2], [0, 5])).toEqual([]);
    });

    it('returns empty array when tile is fully enclosed by blocked tiles', () => {
      const map = new TileMap(5, 5, 16, 3);
      // Surround (2,2) with blocked tiles
      map.block(1, 2);
      map.block(3, 2);
      map.block(2, 1);
      map.block(2, 3);
      const path = map.findPath([0, 0], [2, 2]);
      expect(path).toEqual([]);
    });

    it('handles large negative coordinates without crashing', () => {
      const map = new TileMap(5, 5, 16, 3);
      expect(map.findPath([-100, -100], [2, 2])).toEqual([]);
      expect(map.findPath([2, 2], [-100, -100])).toEqual([]);
    });
  });

  describe('pixelToTile round-trip', () => {
    it('round-trips correctly with tileToPixel', () => {
      const map = new TileMap(14, 5, 16, 3);
      for (let col = 0; col < 14; col++) {
        for (let row = 0; row < 5; row++) {
          const pixel = map.tileToPixel(col, row);
          const tile = map.pixelToTile(pixel.x, pixel.y);
          expect(tile).toEqual([col, row]);
        }
      }
    });

    it('round-trips with mid-tile pixel offsets (floor behavior)', () => {
      const map = new TileMap(14, 5, 16, 3);
      // Pixel at center of tile (1,2) => should still map to (1,2)
      const pixel = map.tileToPixel(1, 2);
      const tileFromCenter = map.pixelToTile(pixel.x + 20, pixel.y + 20);
      expect(tileFromCenter).toEqual([1, 2]);
    });
  });

  describe('unblock', () => {
    it('makes a blocked tile walkable again and findPath succeeds', () => {
      const map = new TileMap(3, 1, 16, 3);
      map.block(1, 0);
      expect(map.findPath([0, 0], [2, 0])).toEqual([]);
      map.unblock(1, 0);
      const path = map.findPath([0, 0], [2, 0]);
      expect(path.length).toBe(3);
      expect(path[0]).toEqual([0, 0]);
      expect(path[path.length - 1]).toEqual([2, 0]);
    });
  });
});

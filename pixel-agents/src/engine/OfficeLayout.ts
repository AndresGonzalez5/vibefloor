// Office layout defining seat positions, furniture, and blocked tiles.
// Layout is a 14x5 tile grid representing a compact office scene.

import type { TileMap, TileCoord } from './TileMap';
import type { Direction } from './SpriteEngine';

export interface Seat {
  id: number;
  chairTile: TileCoord;
  deskTile: TileCoord;
  pcTile: TileCoord;
  facing: Direction;
  occupied: boolean;
  agentId: string | null;
}

export interface FurnitureItem {
  type: 'desk' | 'pc' | 'chair' | 'whiteboard' | 'coffee' | 'plant';
  tile: TileCoord;
  spriteKey: string;
  blocksMovement: boolean;
}

export interface WanderTarget {
  tile: TileCoord;
  label: string;
}

// Layout diagram:
//   Col:  0  1  2  3  4  5  6  7  8  9  10 11 12 13
// Row 0: [W] [W] [W] [W] [W] [W] [W] [W] [W] [W] [W] [W] [W] [W]   wall
// Row 1: [.] [D0][ ][.] [D1][ ][.] [D2][ ][.] [D3][ ][.] [WB]   desks (48px = 3 tiles wide) + PCs on desks
// Row 2: [>] [.][C0][.] [.][C1][.] [.][C2][.] [.][C3][.] [.]    chairs centered under desks
// Row 3: [.] [.] [.] [.] [.] [.] [.] [.] [.] [.] [.] [D4][ ][CF]   desk4 + coffee
// Row 4: [.] [.] [.] [.] [.] [.] [.] [.] [.] [.] [.] [.][C4][PL]   chair4 centered + plant
// Note: Desk sprite is 48x32 (3 tiles wide). Chair tile is at desk center (deskTile[0]+1).

const SEATS: Omit<Seat, 'occupied' | 'agentId'>[] = [
  { id: 0, chairTile: [2, 2],  deskTile: [1, 1],  pcTile: [2, 1],  facing: 'up' },
  { id: 1, chairTile: [5, 2],  deskTile: [4, 1],  pcTile: [5, 1],  facing: 'up' },
  { id: 2, chairTile: [8, 2],  deskTile: [7, 1],  pcTile: [8, 1],  facing: 'up' },
  { id: 3, chairTile: [11, 2], deskTile: [10, 1], pcTile: [11, 1], facing: 'up' },
  { id: 4, chairTile: [12, 4], deskTile: [11, 3], pcTile: [12, 3], facing: 'up' },
];

const FURNITURE: FurnitureItem[] = [
  // Desks (block movement)
  { type: 'desk', tile: [1, 1],  spriteKey: 'desk_front', blocksMovement: true },
  { type: 'desk', tile: [4, 1],  spriteKey: 'desk_front', blocksMovement: true },
  { type: 'desk', tile: [7, 1],  spriteKey: 'desk_front', blocksMovement: true },
  { type: 'desk', tile: [10, 1], spriteKey: 'desk_front', blocksMovement: true },
  { type: 'desk', tile: [11, 3], spriteKey: 'desk_front', blocksMovement: true },

  // PCs on desks (block movement)
  { type: 'pc', tile: [2, 1],  spriteKey: 'pc_on', blocksMovement: true },
  { type: 'pc', tile: [5, 1],  spriteKey: 'pc_on', blocksMovement: true },
  { type: 'pc', tile: [8, 1],  spriteKey: 'pc_on', blocksMovement: true },
  { type: 'pc', tile: [11, 1], spriteKey: 'pc_on', blocksMovement: true },
  { type: 'pc', tile: [12, 3], spriteKey: 'pc_on', blocksMovement: true },

  // Whiteboard (blocks movement)
  { type: 'whiteboard', tile: [13, 1], spriteKey: 'whiteboard', blocksMovement: true },

  // Coffee machine (blocks movement)
  { type: 'coffee', tile: [13, 3], spriteKey: 'coffee', blocksMovement: true },

  // Plant (blocks movement)
  { type: 'plant', tile: [13, 4], spriteKey: 'plant', blocksMovement: true },
];

const WANDER_TARGETS: WanderTarget[] = [
  { tile: [13, 2], label: 'whiteboard' },
  { tile: [12, 4], label: 'coffee' },
  { tile: [6, 2],  label: 'hallway' },
  { tile: [6, 3],  label: 'lounge' },
];

export class OfficeLayout {
  readonly cols = 14;
  readonly rows = 5;
  readonly tileSize = 16;
  readonly zoom = 3;
  readonly spawnTile: TileCoord = [0, 2];
  readonly furniture: FurnitureItem[] = FURNITURE;
  readonly wanderTargets: WanderTarget[] = WANDER_TARGETS;

  private seats: Seat[];

  constructor() {
    this.seats = SEATS.map((s) => ({
      ...s,
      occupied: false,
      agentId: null,
    }));
  }

  initBlockedTiles(tileMap: TileMap): void {
    // Block entire wall row
    for (let c = 0; c < this.cols; c++) {
      tileMap.block(c, 0);
    }

    // Block furniture that blocks movement
    for (const item of this.furniture) {
      if (item.blocksMovement) {
        tileMap.block(item.tile[0], item.tile[1]);
      }
    }
  }

  claimSeat(agentId: string): Seat | null {
    const seat = this.seats.find((s) => !s.occupied);
    if (!seat) return null;
    seat.occupied = true;
    seat.agentId = agentId;
    return seat;
  }

  releaseSeat(agentId: string): void {
    const seat = this.seats.find((s) => s.agentId === agentId);
    if (seat) {
      seat.occupied = false;
      seat.agentId = null;
    }
  }

  getSeat(agentId: string): Seat | null {
    return this.seats.find((s) => s.agentId === agentId) ?? null;
  }

  getSeats(): Seat[] {
    return this.seats;
  }

  isSeatOccupied(seatId: number): boolean {
    const seat = this.seats.find((s) => s.id === seatId);
    return seat?.occupied ?? false;
  }

  getSeatForPc(col: number, row: number): Seat | null {
    return this.seats.find((s) => s.pcTile[0] === col && s.pcTile[1] === row) ?? null;
  }
}

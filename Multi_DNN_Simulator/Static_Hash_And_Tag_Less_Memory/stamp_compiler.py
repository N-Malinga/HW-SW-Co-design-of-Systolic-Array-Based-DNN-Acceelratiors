#!/usr/bin/env python3
"""
Stamp-Based Memory Management Compiler for DNN Accelerators

This compiler implements static on-chip memory management for DNN accelerators:
1. Constructs input tiles for each execution phase
2. Maps tiles to on-chip memory statically
3. Determines deltas between consecutive memory stamps
4. Generates metadata for the hardware controller

Key Concepts:
- Phase: A set of input, weight, and output tiles that fit in the systolic array at one time
- Stamp: The layout of phase data in on-chip memory
- Delta: The difference between consecutive stamps (what needs to be loaded/moved)
"""

import numpy as np
from dataclasses import dataclass, field
from typing import List, Dict, Tuple, Set
from enum import Enum
import json


class TileType(Enum):
    INPUT = "input"
    WEIGHT = "weight"
    OUTPUT = "output"
    INTERMEDIATE = "intermediate"


@dataclass
class Tile:
    """Represents a data tile in a DNN computation phase"""
    tile_id: int
    tile_type: TileType
    shape: Tuple[int, ...]  # (C, H, W) for activations, (K, C, Kh, Kw) for weights
    size_bytes: int
    phase_id: int
    reuse_count: int = 1  # How many times this tile is reused
    
    def __hash__(self):
        return hash((self.tile_id, self.tile_type, self.phase_id))
    
    def __eq__(self, other):
        return (self.tile_id == other.tile_id and 
                self.tile_type == other.tile_type and 
                self.phase_id == other.phase_id)


@dataclass
class OnChipLocation:
    """Represents a location in on-chip memory"""
    start_addr: int
    end_addr: int
    tile: Tile
    
    @property
    def size(self):
        return self.end_addr - self.start_addr


@dataclass
class MemoryStamp:
    """Represents the complete on-chip memory layout for one execution phase"""
    phase_id: int
    locations: List[OnChipLocation] = field(default_factory=list)
    total_size: int = 0
    
    def add_tile(self, tile: Tile, start_addr: int):
        """Add a tile to this stamp at the specified address"""
        location = OnChipLocation(
            start_addr=start_addr,
            end_addr=start_addr + tile.size_bytes,
            tile=tile
        )
        self.locations.append(location)
        self.total_size = max(self.total_size, location.end_addr)
    
    def get_tile_address(self, tile: Tile) -> int:
        """Get the on-chip address of a specific tile"""
        for loc in self.locations:
            if loc.tile == tile:
                return loc.start_addr
        return -1
    
    def get_tiles(self) -> Set[Tile]:
        """Get all tiles in this stamp"""
        return {loc.tile for loc in self.locations}


@dataclass
class DeltaOperation:
    """Represents a single operation to transition between stamps"""
    op_type: str  # "load", "move", "keep"
    tile: Tile
    src_addr: int = -1  # For "move": on-chip source address; For "load": -1
    dst_addr: int = -1  # Destination on-chip address
    size: int = 0
    
    def to_dict(self):
        return {
            "op_type": self.op_type,
            "tile_id": self.tile.tile_id,
            "tile_type": self.tile.tile_type.value,
            "src_addr": self.src_addr,
            "dst_addr": self.dst_addr,
            "size": self.size,
            "offset": self.dst_addr - self.src_addr if self.op_type == "move" else 0
        }


@dataclass
class StampDelta:
    """Represents the delta between two consecutive memory stamps"""
    from_phase: int
    to_phase: int
    operations: List[DeltaOperation] = field(default_factory=list)
    
    def add_operation(self, op: DeltaOperation):
        self.operations.append(op)
    
    def get_stats(self):
        """Get statistics about this delta"""
        loads = sum(1 for op in self.operations if op.op_type == "load")
        moves = sum(1 for op in self.operations if op.op_type == "move")
        keeps = sum(1 for op in self.operations if op.op_type == "keep")
        load_bytes = sum(op.size for op in self.operations if op.op_type == "load")
        move_bytes = sum(op.size for op in self.operations if op.op_type == "move")
        
        return {
            "loads": loads,
            "moves": moves,
            "keeps": keeps,
            "load_bytes": load_bytes,
            "move_bytes": move_bytes,
            "total_ops": len(self.operations),
            "bandwidth_saved": move_bytes  # Bytes that don't need off-chip access
        }


class StampCompiler:
    """
    Compiler that generates memory stamps and deltas for DNN execution
    """
    
    def __init__(self, on_chip_size: int, data_width: int = 4):
        """
        Args:
            on_chip_size: Size of on-chip memory in bytes
            data_width: Width of each data element in bytes (default: 4 for fp32)
        """
        self.on_chip_size = on_chip_size
        self.data_width = data_width
        self.phases: List[List[Tile]] = []
        self.stamps: List[MemoryStamp] = []
        self.deltas: List[StampDelta] = []
        
    def create_conv_phases(self, 
                          layer_config: Dict,
                          systolic_array_size: Tuple[int, int],
                          tile_strategy: str = "output_stationary"):
        """
        Create execution phases for a convolutional layer
        
        Args:
            layer_config: Dict with layer parameters
                - input_channels, input_height, input_width
                - output_channels, output_height, output_width
                - kernel_height, kernel_width
                - stride, padding
            systolic_array_size: (height, width) of systolic array
            tile_strategy: "output_stationary", "weight_stationary", or "input_stationary"
        """
        ic = layer_config['input_channels']
        ih = layer_config['input_height']
        iw = layer_config['input_width']
        oc = layer_config['output_channels']
        oh = layer_config['output_height']
        ow = layer_config['output_width']
        kh = layer_config['kernel_height']
        kw = layer_config['kernel_width']
        
        array_h, array_w = systolic_array_size
        
        # Calculate tile sizes based on systolic array and on-chip memory
        # For simplicity, we'll use output-stationary approach
        output_tile_h = min(array_h, oh)
        output_tile_w = min(array_w, ow)
        output_tile_c = min(array_w, oc)
        
        # Input tile size depends on output tile and kernel
        input_tile_h = output_tile_h + kh - 1
        input_tile_w = output_tile_w + kw - 1
        
        phase_id = 0
        
        # Generate phases by tiling the output space
        for oc_start in range(0, oc, output_tile_c):
            oc_end = min(oc_start + output_tile_c, oc)
            oc_tile = oc_end - oc_start
            
            for oh_start in range(0, oh, output_tile_h):
                oh_end = min(oh_start + output_tile_h, oh)
                oh_tile = oh_end - oh_start
                
                for ow_start in range(0, ow, output_tile_w):
                    ow_end = min(ow_start + output_tile_w, ow)
                    ow_tile = ow_end - ow_start
                    
                    phase_tiles = []
                    tile_id_counter = phase_id * 1000  # Unique tile IDs
                    
                    # Input tile (all input channels needed)
                    ih_start = oh_start
                    iw_start = ow_start
                    input_size = ic * input_tile_h * input_tile_w * self.data_width
                    
                    input_tile = Tile(
                        tile_id=tile_id_counter,
                        tile_type=TileType.INPUT,
                        shape=(ic, input_tile_h, input_tile_w),
                        size_bytes=input_size,
                        phase_id=phase_id
                    )
                    phase_tiles.append(input_tile)
                    tile_id_counter += 1
                    
                    # Weight tile
                    weight_size = oc_tile * ic * kh * kw * self.data_width
                    weight_tile = Tile(
                        tile_id=tile_id_counter,
                        tile_type=TileType.WEIGHT,
                        shape=(oc_tile, ic, kh, kw),
                        size_bytes=weight_size,
                        phase_id=phase_id
                    )
                    phase_tiles.append(weight_tile)
                    tile_id_counter += 1
                    
                    # Output tile
                    output_size = oc_tile * oh_tile * ow_tile * self.data_width
                    output_tile = Tile(
                        tile_id=tile_id_counter,
                        tile_type=TileType.OUTPUT,
                        shape=(oc_tile, oh_tile, ow_tile),
                        size_bytes=output_size,
                        phase_id=phase_id
                    )
                    phase_tiles.append(output_tile)
                    
                    self.phases.append(phase_tiles)
                    phase_id += 1
        
        print(f"Created {len(self.phases)} execution phases")
        
    def allocate_stamps(self, allocation_strategy: str = "greedy"):
        """
        Allocate on-chip memory addresses for each phase's tiles
        
        Args:
            allocation_strategy: "greedy" or "optimal"
        """
        for phase_id, phase_tiles in enumerate(self.phases):
            stamp = MemoryStamp(phase_id=phase_id)
            
            if allocation_strategy == "greedy":
                # Simple greedy allocation
                current_addr = 0
                
                # Sort tiles by type for better locality
                sorted_tiles = sorted(phase_tiles, 
                                    key=lambda t: (t.tile_type.value, t.tile_id))
                
                for tile in sorted_tiles:
                    if current_addr + tile.size_bytes > self.on_chip_size:
                        raise ValueError(
                            f"Phase {phase_id} doesn't fit in on-chip memory! "
                            f"Required: {current_addr + tile.size_bytes}, "
                            f"Available: {self.on_chip_size}"
                        )
                    
                    stamp.add_tile(tile, current_addr)
                    current_addr += tile.size_bytes
            
            self.stamps.append(stamp)
        
        print(f"Allocated {len(self.stamps)} memory stamps")
        
    def compute_deltas(self):
        """
        Compute deltas between consecutive stamps to identify:
        1. Tiles that can be kept (same location)
        2. Tiles that can be moved (reused from previous phase)
        3. Tiles that must be loaded from off-chip
        """
        for i in range(len(self.stamps) - 1):
            current_stamp = self.stamps[i]
            next_stamp = self.stamps[i + 1]
            
            delta = StampDelta(from_phase=i, to_phase=i + 1)
            
            current_tiles = {loc.tile: loc.start_addr 
                           for loc in current_stamp.locations}
            next_tiles = {loc.tile: loc.start_addr 
                         for loc in next_stamp.locations}
            
            # Find tiles that exist in both stamps
            for next_tile, next_addr in next_tiles.items():
                found_match = False
                
                # Check if this tile exists in current stamp
                for curr_tile, curr_addr in current_tiles.items():
                    # Check if tiles are the same (can be reused)
                    if self._can_reuse_tile(curr_tile, next_tile):
                        if curr_addr == next_addr:
                            # Tile is in the same location - keep it
                            op = DeltaOperation(
                                op_type="keep",
                                tile=next_tile,
                                src_addr=curr_addr,
                                dst_addr=next_addr,
                                size=next_tile.size_bytes
                            )
                        else:
                            # Tile can be moved from old location to new
                            op = DeltaOperation(
                                op_type="move",
                                tile=next_tile,
                                src_addr=curr_addr,
                                dst_addr=next_addr,
                                size=next_tile.size_bytes
                            )
                        delta.add_operation(op)
                        found_match = True
                        break
                
                # If no match found, must load from off-chip
                if not found_match:
                    op = DeltaOperation(
                        op_type="load",
                        tile=next_tile,
                        dst_addr=next_addr,
                        size=next_tile.size_bytes
                    )
                    delta.add_operation(op)
            
            self.deltas.append(delta)
        
        print(f"Computed {len(self.deltas)} deltas")
        
    def _can_reuse_tile(self, tile1: Tile, tile2: Tile) -> bool:
        """
        Determine if tile2 can reuse data from tile1
        
        This is a simplified heuristic. In reality, you'd check:
        - If tiles overlap in the input/weight space
        - If the data is actually the same
        """
        # For now, check if tiles have the same type and shape
        # In a real implementation, you'd track data dependencies
        if tile1.tile_type != tile2.tile_type:
            return False
        
        # Weights can often be reused across spatial tiles
        if tile1.tile_type == TileType.WEIGHT:
            return tile1.shape == tile2.shape
        
        # Input tiles might overlap
        if tile1.tile_type == TileType.INPUT:
            # Check for spatial overlap (simplified)
            return tile1.shape[0] == tile2.shape[0]  # Same channels
        
        return False
    
    def generate_metadata(self, output_file: str):
        """
        Generate metadata file for the hardware controller
        
        The metadata includes:
        - Phase configurations
        - Memory stamp layouts
        - Delta operations with move offsets
        """
        metadata = {
            "on_chip_size": self.on_chip_size,
            "data_width": self.data_width,
            "num_phases": len(self.phases),
            "stamps": [],
            "deltas": []
        }
        
        # Add stamp information
        for stamp in self.stamps:
            stamp_data = {
                "phase_id": stamp.phase_id,
                "total_size": stamp.total_size,
                "tiles": [
                    {
                        "tile_id": loc.tile.tile_id,
                        "tile_type": loc.tile.tile_type.value,
                        "shape": loc.tile.shape,
                        "start_addr": loc.start_addr,
                        "end_addr": loc.end_addr,
                        "size": loc.tile.size_bytes
                    }
                    for loc in stamp.locations
                ]
            }
            metadata["stamps"].append(stamp_data)
        
        # Add delta information
        for delta in self.deltas:
            delta_data = {
                "from_phase": delta.from_phase,
                "to_phase": delta.to_phase,
                "operations": [op.to_dict() for op in delta.operations],
                "stats": delta.get_stats()
            }
            metadata["deltas"].append(delta_data)
        
        # Write to file
        with open(output_file, 'w') as f:
            json.dump(metadata, f, indent=2)
        
        print(f"Metadata written to {output_file}")
        
    def print_statistics(self):
        """Print statistics about the stamp-based allocation"""
        print("\n" + "="*80)
        print("STAMP-BASED MEMORY MANAGEMENT STATISTICS")
        print("="*80)
        
        print(f"\nOn-chip memory size: {self.on_chip_size:,} bytes")
        print(f"Number of phases: {len(self.phases)}")
        print(f"Number of deltas: {len(self.deltas)}")
        
        # Stamp statistics
        avg_stamp_size = np.mean([s.total_size for s in self.stamps])
        max_stamp_size = max([s.total_size for s in self.stamps])
        utilization = (avg_stamp_size / self.on_chip_size) * 100
        
        print(f"\nStamp Statistics:")
        print(f"  Average stamp size: {avg_stamp_size:,.0f} bytes")
        print(f"  Maximum stamp size: {max_stamp_size:,} bytes")
        print(f"  Average utilization: {utilization:.1f}%")
        
        # Delta statistics
        if self.deltas:
            total_loads = sum(d.get_stats()['loads'] for d in self.deltas)
            total_moves = sum(d.get_stats()['moves'] for d in self.deltas)
            total_keeps = sum(d.get_stats()['keeps'] for d in self.deltas)
            total_load_bytes = sum(d.get_stats()['load_bytes'] for d in self.deltas)
            total_move_bytes = sum(d.get_stats()['move_bytes'] for d in self.deltas)
            total_bandwidth_saved = sum(d.get_stats()['bandwidth_saved'] for d in self.deltas)
            
            print(f"\nDelta Statistics:")
            print(f"  Total load operations: {total_loads}")
            print(f"  Total move operations: {total_moves}")
            print(f"  Total keep operations: {total_keeps}")
            print(f"  Total bytes loaded: {total_load_bytes:,}")
            print(f"  Total bytes moved: {total_move_bytes:,}")
            print(f"  Off-chip bandwidth saved: {total_bandwidth_saved:,} bytes")
            
            if total_load_bytes + total_move_bytes > 0:
                savings_pct = (total_bandwidth_saved / 
                             (total_load_bytes + total_move_bytes)) * 100
                print(f"  Bandwidth savings: {savings_pct:.1f}%")
        
        print("="*80 + "\n")


def main():
    """Example usage of the StampCompiler"""
    
    # Example: Smaller convolution layer that fits in 16KB scratchpad
    layer_config = {
        'input_channels': 16,
        'input_height': 14,
        'input_width': 14,
        'output_channels': 32,
        'output_height': 14,
        'output_width': 14,
        'kernel_height': 3,
        'kernel_width': 3,
        'stride': 1,
        'padding': 1
    }
    
    # On-chip memory: 16 KB scratchpad
    on_chip_size = 16 * 1024
    systolic_array_size = (4, 4)
    
    # Create compiler
    compiler = StampCompiler(on_chip_size=on_chip_size, data_width=4)
    
    # Generate phases
    compiler.create_conv_phases(layer_config, systolic_array_size)
    
    # Allocate stamps
    compiler.allocate_stamps(allocation_strategy="greedy")
    
    # Compute deltas
    compiler.compute_deltas()
    
    # Generate metadata
    compiler.generate_metadata("stamp_metadata.json")
    
    # Print statistics
    compiler.print_statistics()


if __name__ == "__main__":
    main()

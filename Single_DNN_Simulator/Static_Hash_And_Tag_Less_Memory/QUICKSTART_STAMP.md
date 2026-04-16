# Stamp-Based Memory Management: Quick Start Guide

## Overview

This guide shows how to integrate stamp-based memory management into your DNN accelerator in 3 simple steps:

1. **Compile**: Generate stamps and deltas using the Python compiler
2. **Program**: Load metadata into hardware  
3. **Execute**: Run phases with automatic data management

## Step 1: Generate Stamps (Compiler Side)

### Basic Usage

```python
from stamp_compiler import StampCompiler

# Define your layer
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

# Create compiler
compiler = StampCompiler(
    on_chip_size=16*1024,  # 16 KB scratchpad
    data_width=4            # 4 bytes per word
)

# Generate phases and compute deltas
compiler.create_conv_phases(layer_config, systolic_array_size=(4, 4))
compiler.allocate_stamps(allocation_strategy="greedy")
compiler.compute_deltas()

# Save metadata
compiler.generate_metadata("layer1_metadata.json")
compiler.print_statistics()
```

### What You Get

The compiler produces `layer1_metadata.json` containing:
- **Stamps**: Memory layout for each phase
- **Deltas**: Operations to transition between phases
- **Statistics**: Bandwidth savings, reuse patterns

### Example Output

```
Created 128 execution phases
Allocated 128 memory stamps
Computed 127 deltas
Metadata written to layer1_metadata.json

STAMP-BASED MEMORY MANAGEMENT STATISTICS
=========================================
On-chip memory size: 16,384 bytes
Number of phases: 128

Stamp Statistics:
  Average stamp size: 4,804 bytes
  Average utilization: 29.3%

Delta Statistics:
  Total load operations: 127
  Total move operations: 55
  Total keep operations: 199
  Off-chip bandwidth saved: 126,720 bytes
  Bandwidth savings: 83.6%
```

## Step 2: Program Hardware (One-Time Setup)

### Load Metadata into Hardware

```systemverilog
// Read metadata from file (in testbench or boot sequence)
initial begin
    // Load delta operations
    $readmemh("delta_ops.hex", delta_operations);
    
    // Program metadata RAM
    for (int i = 0; i < num_total_ops; i++) begin
        metadata_wr_en = 1'b1;
        metadata_wr_addr = i;
        metadata_wr_data = delta_operations[i];
        @(posedge clk);
    end
    metadata_wr_en = 1'b0;
end
```

### Metadata Format

Each metadata entry (128 bits):
```
[127:120] - op_type (0=keep, 1=move, 2=load)
[119:104] - tile_id
[103:72]  - src_addr
[71:40]   - dst_addr  
[39:8]    - size
[7:0]     - reserved
```

## Step 3: Execute Phases (Runtime)

### Phase Execution Loop

```systemverilog
// For each phase in your network
for (int phase = 0; phase < num_phases; phase++) begin
    
    // 1. Wait for memory controller ready
    wait(phase_ready);
    
    // 2. Configure phase
    phase_id = phase;
    num_delta_ops = phase_op_counts[phase];  // From metadata
    
    // 3. Start delta execution
    phase_start = 1'b1;
    @(posedge clk);
    phase_start = 1'b0;
    
    // 4. Wait for delta completion
    wait(phase_done);
    
    // 5. Start computation
    start = 1'b1;
    @(posedge clk);
    start = 1'b0;
    
    // 6. Wait for compute done
    wait(done);
    
    // 7. Optional: Check statistics
    $display("Phase %0d: Loads=%0d, Moves=%0d, Keeps=%0d",
             phase, mem_stats.total_loads, 
             mem_stats.total_moves, mem_stats.total_keeps);
end
```

### Simplified Version

```systemverilog
// Minimal phase execution
phase_id = current_phase;
num_delta_ops = ops_for_phase[current_phase];
phase_start = 1'b1;
@(posedge clk);
phase_start = 1'b0;
wait(phase_done);  // Delta complete, data ready
start = 1'b1;      // Start compute
wait(done);        // Compute complete
```

## Integration with Existing Accelerator

### Option A: Replace Existing Memory System

If you have a hash-table based system:

```systemverilog
// OLD: Hash table + page table
// systolic_spad_top #(...) spad (
//     .pt_write_en(...),
//     .pt_write_vpn(...),
//     ...
// );

// NEW: Stamp-based controller
systolic_array_stamp_top #(...) stamp_array (
    .metadata_wr_en(metadata_wr_en),
    .metadata_wr_addr(metadata_wr_addr),
    .metadata_wr_data(metadata_wr_data),
    .phase_start(phase_start),
    .phase_id(phase_id),
    .num_delta_ops(num_delta_ops),
    .phase_ready(phase_ready),
    .phase_done(phase_done),
    // ... other ports
);
```

### Option B: Hybrid Approach

Keep both systems and select at compile time:

```systemverilog
generate
    if (USE_STAMP_MEMORY) begin
        stamp_based_memory_controller #(...) mem_ctrl (...);
    end else begin
        hash_table_memory_controller #(...) mem_ctrl (...);
    end
endgenerate
```

## Complete Example: VGG Layer

### 1. Compiler Configuration

```python
# VGG-16 first conv layer: 64 filters, 224x224 input
vgg_conv1 = {
    'input_channels': 3,
    'input_height': 224,
    'input_width': 224,
    'output_channels': 64,
    'output_height': 224,
    'output_width': 224,
    'kernel_height': 3,
    'kernel_width': 3,
    'stride': 1,
    'padding': 1
}

compiler = StampCompiler(on_chip_size=256*1024)  # 256 KB SRAM
compiler.create_conv_phases(vgg_conv1, (16, 16))
compiler.allocate_stamps()
compiler.compute_deltas()
compiler.generate_metadata("vgg_conv1.json")
```

### 2. Hardware Setup

```systemverilog
// At boot/initialization
load_metadata_from_file("vgg_conv1_metadata.hex");

// Configure layer
input_channels   = 3;
input_height     = 224;
input_width      = 224;
output_channels  = 64;
kernel_size      = 3;
```

### 3. Runtime Execution

```systemverilog
// Execute all phases for VGG conv1
for (int p = 0; p < num_vgg_conv1_phases; p++) begin
    execute_phase(p, vgg_conv1_ops[p]);
end

// Proceed to next layer (load new metadata)
load_metadata_from_file("vgg_conv2_metadata.hex");
```

## Performance Tuning

### Overlapping Compute and Memory

```systemverilog
// Pipeline: Load phase N+1 while computing phase N
always_ff @(posedge clk) begin
    if (compute_busy && phase_ready) begin
        // Prefetch next phase
        phase_id <= current_phase + 1;
        phase_start <= 1'b1;
    end
end
```

### Adjusting Tile Sizes

```python
# Increase tile size for better compute efficiency
compiler = StampCompiler(on_chip_size=64*1024)  # Larger SRAM

# Or use smaller tiles if memory constrained
compiler.create_conv_phases(
    layer_config, 
    systolic_array_size=(2, 2)  # Smaller tiles
)
```

### Multiple Layers

```python
# Compile entire network
layers = [conv1_config, conv2_config, pool1_config, ...]

all_metadata = []
for i, layer in enumerate(layers):
    compiler = StampCompiler(on_chip_size=16*1024)
    compiler.create_conv_phases(layer, (4, 4))
    compiler.allocate_stamps()
    compiler.compute_deltas()
    all_metadata.append(compiler.stamps)
    compiler.generate_metadata(f"layer{i}.json")
```

## Debugging

### Check Metadata

```bash
# View metadata
python3 stamp_analyzer.py layer1_metadata.json

# Expected output shows:
# - Stamp sizes
# - Operation breakdown
# - Bandwidth savings
```

### Simulation

```bash
# Run testbench
make -f Makefile_stamp simulate

# View waveforms
gtkwave stamp_memory.vcd
```

### Common Issues

1. **Phase doesn't fit**: Reduce tile size or increase on-chip memory
2. **Poor reuse**: Check layer configuration, may need better tiling
3. **Too many phases**: Normal for large layers, consider prefetching

## Verification Checklist

- [ ] Compiler runs without errors
- [ ] Metadata generated successfully
- [ ] Bandwidth savings > 50% (typical)
- [ ] Testbench passes
- [ ] Hardware synthesizes
- [ ] Performance meets requirements

## Next Steps

1. **Profile your workload**: Run compiler on your actual DNN layers
2. **Optimize tile sizes**: Tune for your memory size and array dimensions
3. **Measure performance**: Compare against baseline hash-table approach
4. **Scale up**: Try larger networks (ResNet, MobileNet, etc.)

## Resources

- **Documentation**: See `STAMP_MEMORY_README.md` for detailed info
- **Compiler**: `stamp_compiler.py` - Generate stamps and deltas
- **Analyzer**: `stamp_analyzer.py` - Analyze metadata and estimate performance
- **Hardware**: `stamp_based_memory_controller.sv` - RTL implementation
- **Testbench**: `stamp_based_memory_tb.sv` - Verification environment

## Support

For questions or issues:
1. Check the detailed README
2. Review example metadata files
3. Run the analyzer for insights
4. Examine testbench for usage patterns

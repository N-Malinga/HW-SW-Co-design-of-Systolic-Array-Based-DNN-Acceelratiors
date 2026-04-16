//=============================================================================
// Module: stamp_based_memory_controller
// Description: Hardware controller for stamp-based on-chip memory management
//
// This controller eliminates hash table lookups and hardware tags by:
// 1. Using compiler-generated static memory layouts (stamps)
// 2. Performing in-place data moves based on compiler metadata
// 3. Streaming data in/out in deterministic order
//
// Key Features:
// - No dynamic hash table lookups
// - No hardware tag matching
// - Compiler-determined memory allocation
// - Efficient data reuse through in-place moves
//=============================================================================

module stamp_based_memory_controller 
    import systolic_array_pkg::*;
#(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int SPAD_DEPTH = 4096,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int MAX_DELTA_OPS = 64,  // Max operations per delta
    parameter int METADATA_DEPTH = 256  // Depth of metadata storage
) (
    input  logic                    clk,
    input  logic                    rst_n,
    
    //=========================================================================
    // Configuration Interface (from compiler)
    //=========================================================================
    // Metadata programming interface
    input  logic                    metadata_wr_en,
    input  logic [$clog2(METADATA_DEPTH)-1:0] metadata_wr_addr,
    input  logic [127:0]            metadata_wr_data,  // {op_type, tile_id, src_addr, dst_addr, size}
    
    // Phase control
    input  logic                    phase_start,
    input  logic [15:0]             phase_id,
    input  logic [15:0]             num_delta_ops,     // Number of operations in this delta
    output logic                    phase_ready,
    output logic                    phase_done,
    
    //=========================================================================
    // Scratchpad Interface
    //=========================================================================
    // Read port (for moves)
    output logic [$clog2(SPAD_DEPTH)-1:0] spad_rd_addr,
    input  logic [DATA_WIDTH-1:0]         spad_rd_data,
    output logic                          spad_rd_en,
    
    // Write port (for moves and loads)
    output logic [$clog2(SPAD_DEPTH)-1:0] spad_wr_addr,
    output logic [DATA_WIDTH-1:0]         spad_wr_data,
    output logic                          spad_wr_en,
    
    //=========================================================================
    // Off-chip Memory Interface (simplified AXI)
    //=========================================================================
    // Read channel (for loads from off-chip)
    output logic [ADDR_WIDTH-1:0]   mem_rd_addr,
    output logic [15:0]             mem_rd_len,    // Burst length
    output logic                    mem_rd_req,
    input  logic                    mem_rd_ready,
    input  logic [DATA_WIDTH-1:0]   mem_rd_data,
    input  logic                    mem_rd_valid,
    output logic                    mem_rd_ready_ack,
    
    //=========================================================================
    // Status and Statistics
    //=========================================================================
    output logic [31:0]             stats_loads,
    output logic [31:0]             stats_moves,
    output logic [31:0]             stats_keeps,
    output logic [31:0]             stats_bytes_loaded,
    output logic [31:0]             stats_bytes_moved,
    output logic                    controller_busy
);

    //=========================================================================
    // Metadata Storage
    //=========================================================================
    typedef struct packed {
        logic [7:0]  op_type;      // 0=keep, 1=move, 2=load
        logic [15:0] tile_id;
        logic [31:0] src_addr;     // Source address (on-chip for move, off-chip for load)
        logic [31:0] dst_addr;     // Destination on-chip address
        logic [31:0] size;         // Size in bytes
    } delta_operation_t;
    
    delta_operation_t metadata_ram [METADATA_DEPTH];
    
    // Write to metadata RAM
    always_ff @(posedge clk) begin
        if (metadata_wr_en) begin
            metadata_ram[metadata_wr_addr] <= metadata_wr_data;
        end
    end
    
    //=========================================================================
    // Controller State Machine
    //=========================================================================
    typedef enum logic [3:0] {
        IDLE,
        FETCH_METADATA,
        PROCESS_KEEP,
        PROCESS_MOVE_SETUP,
        PROCESS_MOVE_EXEC,
        PROCESS_LOAD_SETUP,
        PROCESS_LOAD_EXEC,
        WAIT_LOAD_COMPLETE,
        DELTA_DONE
    } controller_state_t;
    
    controller_state_t state, next_state;
    
    //=========================================================================
    // Control Registers
    //=========================================================================
    logic [15:0] current_op_idx;
    logic [15:0] num_ops;
    delta_operation_t current_op;
    
    // Move/Load tracking
    logic [31:0] bytes_remaining;
    logic [31:0] current_src_addr;
    logic [31:0] current_dst_addr;
    logic [15:0] words_remaining;  // For word-by-word transfers
    
    // Statistics
    logic [31:0] loads_count;
    logic [31:0] moves_count;
    logic [31:0] keeps_count;
    logic [31:0] bytes_loaded_count;
    logic [31:0] bytes_moved_count;
    
    //=========================================================================
    // State Machine
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (phase_start) begin
                    next_state = FETCH_METADATA;
                end
            end
            
            FETCH_METADATA: begin
                if (current_op_idx < num_ops) begin
                    // Decode operation type
                    case (current_op.op_type)
                        8'd0: next_state = PROCESS_KEEP;
                        8'd1: next_state = PROCESS_MOVE_SETUP;
                        8'd2: next_state = PROCESS_LOAD_SETUP;
                        default: next_state = FETCH_METADATA;
                    endcase
                end else begin
                    next_state = DELTA_DONE;
                end
            end
            
            PROCESS_KEEP: begin
                // Keep operations don't require any data movement
                next_state = FETCH_METADATA;
            end
            
            PROCESS_MOVE_SETUP: begin
                next_state = PROCESS_MOVE_EXEC;
            end
            
            PROCESS_MOVE_EXEC: begin
                if (words_remaining == 0) begin
                    next_state = FETCH_METADATA;
                end
            end
            
            PROCESS_LOAD_SETUP: begin
                next_state = PROCESS_LOAD_EXEC;
            end
            
            PROCESS_LOAD_EXEC: begin
                if (mem_rd_ready) begin
                    next_state = WAIT_LOAD_COMPLETE;
                end
            end
            
            WAIT_LOAD_COMPLETE: begin
                if (words_remaining == 0) begin
                    next_state = FETCH_METADATA;
                end
            end
            
            DELTA_DONE: begin
                next_state = IDLE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    //=========================================================================
    // Control Logic
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_op_idx <= 0;
            num_ops <= 0;
            current_op <= '0;
            bytes_remaining <= 0;
            current_src_addr <= 0;
            current_dst_addr <= 0;
            words_remaining <= 0;
            
            loads_count <= 0;
            moves_count <= 0;
            keeps_count <= 0;
            bytes_loaded_count <= 0;
            bytes_moved_count <= 0;
            
        end else begin
            case (state)
                IDLE: begin
                    if (phase_start) begin
                        current_op_idx <= 0;
                        num_ops <= num_delta_ops;
                    end
                end
                
                FETCH_METADATA: begin
                    if (current_op_idx < num_ops) begin
                        current_op <= metadata_ram[current_op_idx];
                        bytes_remaining <= metadata_ram[current_op_idx].size;
                        current_src_addr <= metadata_ram[current_op_idx].src_addr;
                        current_dst_addr <= metadata_ram[current_op_idx].dst_addr;
                        words_remaining <= metadata_ram[current_op_idx].size / (DATA_WIDTH/8);
                    end
                end
                
                PROCESS_KEEP: begin
                    // No data movement needed
                    keeps_count <= keeps_count + 1;
                    current_op_idx <= current_op_idx + 1;
                end
                
                PROCESS_MOVE_SETUP: begin
                    // Setup for move operation
                    moves_count <= moves_count + 1;
                    bytes_moved_count <= bytes_moved_count + current_op.size;
                end
                
                PROCESS_MOVE_EXEC: begin
                    if (words_remaining > 0) begin
                        // Perform one word move per cycle
                        words_remaining <= words_remaining - 1;
                        current_src_addr <= current_src_addr + (DATA_WIDTH/8);
                        current_dst_addr <= current_dst_addr + (DATA_WIDTH/8);
                        
                        if (words_remaining == 1) begin
                            current_op_idx <= current_op_idx + 1;
                        end
                    end
                end
                
                PROCESS_LOAD_SETUP: begin
                    loads_count <= loads_count + 1;
                    bytes_loaded_count <= bytes_loaded_count + current_op.size;
                end
                
                PROCESS_LOAD_EXEC: begin
                    // Wait for memory read to be accepted
                end
                
                WAIT_LOAD_COMPLETE: begin
                    if (mem_rd_valid && mem_rd_ready_ack) begin
                        words_remaining <= words_remaining - 1;
                        current_dst_addr <= current_dst_addr + (DATA_WIDTH/8);
                        
                        if (words_remaining == 1) begin
                            current_op_idx <= current_op_idx + 1;
                        end
                    end
                end
                
                DELTA_DONE: begin
                    // Reset for next phase
                end
                
            endcase
        end
    end
    
    //=========================================================================
    // Scratchpad Control
    //=========================================================================
    always_comb begin
        spad_rd_en = 1'b0;
        spad_rd_addr = '0;
        spad_wr_en = 1'b0;
        spad_wr_addr = '0;
        spad_wr_data = '0;
        
        case (state)
            PROCESS_MOVE_EXEC: begin
                // Read from source
                spad_rd_en = 1'b1;
                spad_rd_addr = current_src_addr[$clog2(SPAD_DEPTH)-1:0];
                
                // Write to destination (1 cycle later)
                spad_wr_en = 1'b1;
                spad_wr_addr = (current_dst_addr - (DATA_WIDTH/8))[$clog2(SPAD_DEPTH)-1:0];
                spad_wr_data = spad_rd_data;
            end
            
            WAIT_LOAD_COMPLETE: begin
                if (mem_rd_valid) begin
                    spad_wr_en = 1'b1;
                    spad_wr_addr = current_dst_addr[$clog2(SPAD_DEPTH)-1:0];
                    spad_wr_data = mem_rd_data;
                end
            end
        endcase
    end
    
    //=========================================================================
    // Off-chip Memory Control
    //=========================================================================
    always_comb begin
        mem_rd_req = 1'b0;
        mem_rd_addr = '0;
        mem_rd_len = '0;
        mem_rd_ready_ack = 1'b0;
        
        case (state)
            PROCESS_LOAD_EXEC: begin
                mem_rd_req = 1'b1;
                mem_rd_addr = current_src_addr;
                mem_rd_len = words_remaining;
            end
            
            WAIT_LOAD_COMPLETE: begin
                mem_rd_ready_ack = 1'b1;
            end
        endcase
    end
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    assign phase_ready = (state == IDLE);
    assign phase_done = (state == DELTA_DONE);
    assign controller_busy = (state != IDLE);
    
    assign stats_loads = loads_count;
    assign stats_moves = moves_count;
    assign stats_keeps = keeps_count;
    assign stats_bytes_loaded = bytes_loaded_count;
    assign stats_bytes_moved = bytes_moved_count;
    
    //=========================================================================
    // Assertions for debugging
    //=========================================================================
    `ifdef FORMAL
    // Ensure metadata index is in range
    assert property (@(posedge clk) disable iff (!rst_n)
        (state == FETCH_METADATA) |-> (current_op_idx < METADATA_DEPTH)
    );
    
    // Ensure scratchpad addresses are in range
    assert property (@(posedge clk) disable iff (!rst_n)
        (spad_rd_en || spad_wr_en) |-> 
        (spad_rd_addr < SPAD_DEPTH && spad_wr_addr < SPAD_DEPTH)
    );
    `endif

endmodule : stamp_based_memory_controller

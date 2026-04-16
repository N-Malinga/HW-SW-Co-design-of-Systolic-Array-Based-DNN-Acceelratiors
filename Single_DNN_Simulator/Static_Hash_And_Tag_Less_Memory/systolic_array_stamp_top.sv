//=============================================================================
// Module: systolic_array_stamp_top
// Description: Systolic array with stamp-based memory management
//
// This module integrates:
// 1. Original systolic array compute engine
// 2. Stamp-based memory controller (replaces hash table)
// 3. Compiler-generated metadata interface
//=============================================================================

module systolic_array_stamp_top
    import systolic_array_pkg::*;
    import stamp_memory_pkg::*;
#(
    parameter int ARRAY_HEIGHT      = 4,
    parameter int ARRAY_WIDTH       = 4,
    parameter int DATA_WIDTH        = 32,
    parameter int ACCUM_WIDTH       = 48,
    parameter int ADDR_WIDTH        = 32,
    parameter int AXI_ID_WIDTH      = 4,
    parameter int AXI_DATA_WIDTH    = 64,
    parameter int SPAD_DEPTH        = 4096,
    parameter int MAX_CHANNELS      = 512,
    parameter int METADATA_DEPTH    = 256
) (
    input  logic                  clk,
    input  logic                  rst_n,

    //=========================================================================
    // Configuration Interface
    //=========================================================================
    input  mem_layout_t           mem_layout,
    input  logic [15:0]           input_channels,
    input  logic [15:0]           input_height,
    input  logic [15:0]           input_width,
    input  logic [15:0]           weight_k,
    input  logic [15:0]           weight_c,
    input  logic [15:0]           weight_kh,
    input  logic [15:0]           weight_kw,
    input  logic [15:0]           output_channels,
    input  logic [15:0]           output_height,
    input  logic [15:0]           output_width,
    input  logic [ADDR_WIDTH-1:0] input_base_addr,
    input  logic [ADDR_WIDTH-1:0] weight_base_addr,
    input  logic [ADDR_WIDTH-1:0] output_base_addr,

    //=========================================================================
    // Neural Network Operation Configuration
    //=========================================================================
    input  nn_operation_config_t  nn_config,
    input  logic                  enable_activation,
    input  logic                  enable_pooling,
    input  logic                  enable_normalization,
    
    //=========================================================================
    // Stamp-based Memory Management Interface
    //=========================================================================
    // Metadata programming
    input  logic                  metadata_wr_en,
    input  logic [$clog2(METADATA_DEPTH)-1:0] metadata_wr_addr,
    input  logic [127:0]          metadata_wr_data,
    
    // Phase execution control
    input  logic                  phase_start,
    input  logic [15:0]           phase_id,
    input  logic [15:0]           num_delta_ops,
    output logic                  phase_ready,
    output logic                  phase_done,
    
    //=========================================================================
    // Normalization Parameters
    //=========================================================================
    input  logic [DATA_WIDTH-1:0] norm_gamma [MAX_CHANNELS],
    input  logic [DATA_WIDTH-1:0] norm_beta  [MAX_CHANNELS],
    input  logic [DATA_WIDTH-1:0] running_mean [MAX_CHANNELS],
    input  logic [DATA_WIDTH-1:0] running_var  [MAX_CHANNELS],
    output logic [DATA_WIDTH-1:0] updated_mean [MAX_CHANNELS],
    output logic [DATA_WIDTH-1:0] updated_var  [MAX_CHANNELS],
    input  logic                  norm_params_valid,
    input  logic                  training_mode,

    //=========================================================================
    // Control Interface
    //=========================================================================
    input  logic                  start,
    input  logic [15:0]           tile_row,
    input  logic [15:0]           tile_col_start,
    input  logic [15:0]           tile_ch_start,
    output logic                  done,
    output logic                  busy,

    //=========================================================================
    // Scratchpad Direct Access (for testing/debugging)
    //=========================================================================
    input  logic [$clog2(SPAD_DEPTH)-1:0]  spad_load_addr,
    input  logic [DATA_WIDTH-1:0]          spad_load_data,
    input  logic                           spad_load_en,

    //=========================================================================
    // Status and Statistics
    //=========================================================================
    output memory_stats_t         mem_stats,
    output logic                  controller_busy,

    //=========================================================================
    // AXI4 Interface
    //=========================================================================
    output logic [AXI_ID_WIDTH-1:0]        m_axi_arid,
    output logic [ADDR_WIDTH-1:0]          m_axi_araddr,
    output logic [7:0]                     m_axi_arlen,
    output logic [2:0]                     m_axi_arsize,
    output logic [1:0]                     m_axi_arburst,
    output logic                           m_axi_arlock,
    output logic [3:0]                     m_axi_arcache,
    output logic [2:0]                     m_axi_arprot,
    output logic                           m_axi_arvalid,
    input  logic                           m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]        m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]      m_axi_rdata,
    input  logic [1:0]                     m_axi_rresp,
    input  logic                           m_axi_rlast,
    input  logic                           m_axi_rvalid,
    output logic                           m_axi_rready,

    output logic [AXI_ID_WIDTH-1:0]        m_axi_awid,
    output logic [ADDR_WIDTH-1:0]          m_axi_awaddr,
    output logic [7:0]                     m_axi_awlen,
    output logic [2:0]                     m_axi_awsize,
    output logic [1:0]                     m_axi_awburst,
    output logic                           m_axi_awlock,
    output logic [3:0]                     m_axi_awcache,
    output logic [2:0]                     m_axi_awprot,
    output logic                           m_axi_awvalid,
    input  logic                           m_axi_awready,

    output logic [AXI_DATA_WIDTH-1:0]      m_axi_wdata,
    output logic [AXI_DATA_WIDTH/8-1:0]    m_axi_wstrb,
    output logic                           m_axi_wlast,
    output logic                           m_axi_wvalid,
    input  logic                           m_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]        m_axi_bid,
    input  logic [1:0]                     m_axi_bresp,
    input  logic                           m_axi_bvalid,
    output logic                           m_axi_bready
);

    //=========================================================================
    // Internal Signals
    //=========================================================================
    
    // Scratchpad interface between controller and compute
    logic [$clog2(SPAD_DEPTH)-1:0] spad_rd_addr_ctrl, spad_rd_addr_compute;
    logic [DATA_WIDTH-1:0]         spad_rd_data;
    logic                          spad_rd_en_ctrl, spad_rd_en_compute;
    
    logic [$clog2(SPAD_DEPTH)-1:0] spad_wr_addr_ctrl, spad_wr_addr_compute;
    logic [DATA_WIDTH-1:0]         spad_wr_data_ctrl, spad_wr_data_compute;
    logic                          spad_wr_en_ctrl, spad_wr_en_compute;
    
    // Memory interface between controller and AXI
    logic [ADDR_WIDTH-1:0]         mem_rd_addr;
    logic [15:0]                   mem_rd_len;
    logic                          mem_rd_req;
    logic                          mem_rd_ready;
    logic [DATA_WIDTH-1:0]         mem_rd_data;
    logic                          mem_rd_valid;
    logic                          mem_rd_ready_ack;
    
    // Compute engine outputs
    logic [DATA_WIDTH-1:0] compute_output_data [ARRAY_HEIGHT][ARRAY_WIDTH];
    logic [ARRAY_HEIGHT-1:0][ARRAY_WIDTH-1:0] compute_output_valid;
    logic compute_done;
    logic compute_busy;
    
    //=========================================================================
    // Scratchpad Memory (Dual-port)
    //=========================================================================
    logic [DATA_WIDTH-1:0] scratchpad [SPAD_DEPTH];
    
    // Port A: Controller or direct load
    always_ff @(posedge clk) begin
        if (spad_load_en) begin
            scratchpad[spad_load_addr] <= spad_load_data;
        end else if (spad_wr_en_ctrl) begin
            scratchpad[spad_wr_addr_ctrl] <= spad_wr_data_ctrl;
        end
    end
    
    always_ff @(posedge clk) begin
        if (spad_rd_en_ctrl || spad_rd_en_compute) begin
            spad_rd_data <= scratchpad[spad_rd_en_ctrl ? spad_rd_addr_ctrl : spad_rd_addr_compute];
        end
    end
    
    // Port B: Compute engine
    always_ff @(posedge clk) begin
        if (spad_wr_en_compute) begin
            scratchpad[spad_wr_addr_compute] <= spad_wr_data_compute;
        end
    end
    
    //=========================================================================
    // Stamp-based Memory Controller
    //=========================================================================
    stamp_based_memory_controller #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .SPAD_DEPTH      (SPAD_DEPTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .METADATA_DEPTH  (METADATA_DEPTH)
    ) memory_controller (
        .clk                (clk),
        .rst_n              (rst_n),
        
        // Metadata programming
        .metadata_wr_en     (metadata_wr_en),
        .metadata_wr_addr   (metadata_wr_addr),
        .metadata_wr_data   (metadata_wr_data),
        
        // Phase control
        .phase_start        (phase_start),
        .phase_id           (phase_id),
        .num_delta_ops      (num_delta_ops),
        .phase_ready        (phase_ready),
        .phase_done         (phase_done),
        
        // Scratchpad interface
        .spad_rd_addr       (spad_rd_addr_ctrl),
        .spad_rd_data       (spad_rd_data),
        .spad_rd_en         (spad_rd_en_ctrl),
        .spad_wr_addr       (spad_wr_addr_ctrl),
        .spad_wr_data       (spad_wr_data_ctrl),
        .spad_wr_en         (spad_wr_en_ctrl),
        
        // Off-chip memory interface
        .mem_rd_addr        (mem_rd_addr),
        .mem_rd_len         (mem_rd_len),
        .mem_rd_req         (mem_rd_req),
        .mem_rd_ready       (mem_rd_ready),
        .mem_rd_data        (mem_rd_data),
        .mem_rd_valid       (mem_rd_valid),
        .mem_rd_ready_ack   (mem_rd_ready_ack),
        
        // Statistics
        .stats_loads        (mem_stats.total_loads),
        .stats_moves        (mem_stats.total_moves),
        .stats_keeps        (mem_stats.total_keeps),
        .stats_bytes_loaded (mem_stats.bytes_loaded),
        .stats_bytes_moved  (mem_stats.bytes_moved),
        .controller_busy    (controller_busy)
    );
    
    //=========================================================================
    // AXI Read Channel Adapter
    // Converts simplified interface to AXI4
    //=========================================================================
    typedef enum logic [1:0] {
        AXI_IDLE,
        AXI_ADDR,
        AXI_DATA
    } axi_state_t;
    
    axi_state_t axi_state;
    logic [15:0] beats_remaining;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_state <= AXI_IDLE;
            beats_remaining <= 0;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    if (mem_rd_req && m_axi_arready) begin
                        axi_state <= AXI_ADDR;
                        beats_remaining <= mem_rd_len;
                    end
                end
                
                AXI_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        axi_state <= AXI_DATA;
                    end
                end
                
                AXI_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        beats_remaining <= beats_remaining - 1;
                        if (beats_remaining == 1 || m_axi_rlast) begin
                            axi_state <= AXI_IDLE;
                        end
                    end
                end
            endcase
        end
    end
    
    assign m_axi_arvalid = (axi_state == AXI_ADDR);
    assign m_axi_araddr  = mem_rd_addr;
    assign m_axi_arlen   = mem_rd_len[7:0];
    assign m_axi_arsize  = 3'b010;  // 4 bytes
    assign m_axi_arburst = 2'b01;   // INCR
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arid    = 4'b0000;
    
    assign m_axi_rready  = mem_rd_ready_ack;
    assign mem_rd_data   = m_axi_rdata[DATA_WIDTH-1:0];
    assign mem_rd_valid  = m_axi_rvalid;
    assign mem_rd_ready  = (axi_state == AXI_IDLE);
    
    // Write channel (unused in this configuration)
    assign m_axi_awvalid = 1'b0;
    assign m_axi_awaddr  = '0;
    assign m_axi_awlen   = '0;
    assign m_axi_awsize  = '0;
    assign m_axi_awburst = '0;
    assign m_axi_awlock  = '0;
    assign m_axi_awcache = '0;
    assign m_axi_awprot  = '0;
    assign m_axi_awid    = '0;
    assign m_axi_wvalid  = 1'b0;
    assign m_axi_wdata   = '0;
    assign m_axi_wstrb   = '0;
    assign m_axi_wlast   = 1'b0;
    assign m_axi_bready  = 1'b1;
    
    //=========================================================================
    // Compute Engine (Simplified - actual systolic array would go here)
    //=========================================================================
    // This is a placeholder - in real implementation, this would be
    // the systolic_array_enhanced_top or similar compute module
    
    logic compute_start;
    logic [15:0] compute_cycles;
    
    assign compute_start = start && phase_ready;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_busy <= 1'b0;
            compute_done <= 1'b0;
            compute_cycles <= 0;
        end else begin
            if (compute_start) begin
                compute_busy <= 1'b1;
                compute_done <= 1'b0;
                compute_cycles <= 100;  // Placeholder - actual compute time
            end else if (compute_busy) begin
                if (compute_cycles > 0) begin
                    compute_cycles <= compute_cycles - 1;
                end else begin
                    compute_busy <= 1'b0;
                    compute_done <= 1'b1;
                end
            end else begin
                compute_done <= 1'b0;
            end
        end
    end
    
    // Placeholder compute logic
    assign spad_rd_en_compute = compute_busy;
    assign spad_rd_addr_compute = compute_cycles[$clog2(SPAD_DEPTH)-1:0];
    assign spad_wr_en_compute = 1'b0;
    assign spad_wr_addr_compute = '0;
    assign spad_wr_data_compute = '0;
    
    //=========================================================================
    // Status Outputs
    //=========================================================================
    assign done = compute_done && phase_done;
    assign busy = compute_busy || controller_busy;
    
    // Statistics
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_stats.cycles_elapsed <= 0;
        end else if (busy) begin
            mem_stats.cycles_elapsed <= mem_stats.cycles_elapsed + 1;
        end
    end

endmodule : systolic_array_stamp_top

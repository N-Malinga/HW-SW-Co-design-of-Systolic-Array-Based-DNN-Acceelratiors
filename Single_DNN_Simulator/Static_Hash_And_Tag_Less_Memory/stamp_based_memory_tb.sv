//=============================================================================
// Module: stamp_based_memory_tb
// Description: Testbench for stamp-based memory management system
//=============================================================================

`timescale 1ns/1ps

module stamp_based_memory_tb
    import systolic_array_pkg::*;
    import stamp_memory_pkg::*;
();

    //=========================================================================
    // Parameters
    //=========================================================================
    localparam int CLK_PERIOD = 10;  // 100 MHz
    localparam int ARRAY_HEIGHT = 4;
    localparam int ARRAY_WIDTH = 4;
    localparam int DATA_WIDTH = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int SPAD_DEPTH = 4096;
    localparam int METADATA_DEPTH = 256;
    
    //=========================================================================
    // Signals
    //=========================================================================
    logic clk;
    logic rst_n;
    
    // Configuration
    mem_layout_t           mem_layout;
    logic [15:0]           input_channels;
    logic [15:0]           input_height;
    logic [15:0]           input_width;
    logic [15:0]           weight_k;
    logic [15:0]           weight_c;
    logic [15:0]           weight_kh;
    logic [15:0]           weight_kw;
    logic [15:0]           output_channels;
    logic [15:0]           output_height;
    logic [15:0]           output_width;
    logic [ADDR_WIDTH-1:0] input_base_addr;
    logic [ADDR_WIDTH-1:0] weight_base_addr;
    logic [ADDR_WIDTH-1:0] output_base_addr;
    
    // Neural network config
    nn_operation_config_t  nn_config;
    logic                  enable_activation;
    logic                  enable_pooling;
    logic                  enable_normalization;
    
    // Stamp-based memory interface
    logic                  metadata_wr_en;
    logic [$clog2(METADATA_DEPTH)-1:0] metadata_wr_addr;
    logic [127:0]          metadata_wr_data;
    logic                  phase_start;
    logic [15:0]           phase_id;
    logic [15:0]           num_delta_ops;
    logic                  phase_ready;
    logic                  phase_done;
    
    // Normalization parameters
    logic [DATA_WIDTH-1:0] norm_gamma [512];
    logic [DATA_WIDTH-1:0] norm_beta [512];
    logic [DATA_WIDTH-1:0] running_mean [512];
    logic [DATA_WIDTH-1:0] running_var [512];
    logic [DATA_WIDTH-1:0] updated_mean [512];
    logic [DATA_WIDTH-1:0] updated_var [512];
    logic                  norm_params_valid;
    logic                  training_mode;
    
    // Control
    logic                  start;
    logic [15:0]           tile_row;
    logic [15:0]           tile_col_start;
    logic [15:0]           tile_ch_start;
    logic                  done;
    logic                  busy;
    
    // Scratchpad direct access
    logic [$clog2(SPAD_DEPTH)-1:0] spad_load_addr;
    logic [DATA_WIDTH-1:0]         spad_load_data;
    logic                          spad_load_en;
    
    // Statistics
    memory_stats_t         mem_stats;
    logic                  controller_busy;
    
    // AXI4 Interface (simplified memory model)
    logic [3:0]            m_axi_arid;
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]            m_axi_arlen;
    logic [2:0]            m_axi_arsize;
    logic [1:0]            m_axi_arburst;
    logic                  m_axi_arlock;
    logic [3:0]            m_axi_arcache;
    logic [2:0]            m_axi_arprot;
    logic                  m_axi_arvalid;
    logic                  m_axi_arready;
    logic [3:0]            m_axi_rid;
    logic [63:0]           m_axi_rdata;
    logic [1:0]            m_axi_rresp;
    logic                  m_axi_rlast;
    logic                  m_axi_rvalid;
    logic                  m_axi_rready;
    logic [3:0]            m_axi_awid;
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]            m_axi_awlen;
    logic [2:0]            m_axi_awsize;
    logic [1:0]            m_axi_awburst;
    logic                  m_axi_awlock;
    logic [3:0]            m_axi_awcache;
    logic [2:0]            m_axi_awprot;
    logic                  m_axi_awvalid;
    logic                  m_axi_awready;
    logic [63:0]           m_axi_wdata;
    logic [7:0]            m_axi_wstrb;
    logic                  m_axi_wlast;
    logic                  m_axi_wvalid;
    logic                  m_axi_wready;
    logic [3:0]            m_axi_bid;
    logic [1:0]            m_axi_bresp;
    logic                  m_axi_bvalid;
    logic                  m_axi_bready;
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    systolic_array_stamp_top #(
        .ARRAY_HEIGHT   (ARRAY_HEIGHT),
        .ARRAY_WIDTH    (ARRAY_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .ADDR_WIDTH     (ADDR_WIDTH),
        .SPAD_DEPTH     (SPAD_DEPTH),
        .METADATA_DEPTH (METADATA_DEPTH)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .mem_layout             (mem_layout),
        .input_channels         (input_channels),
        .input_height           (input_height),
        .input_width            (input_width),
        .weight_k               (weight_k),
        .weight_c               (weight_c),
        .weight_kh              (weight_kh),
        .weight_kw              (weight_kw),
        .output_channels        (output_channels),
        .output_height          (output_height),
        .output_width           (output_width),
        .input_base_addr        (input_base_addr),
        .weight_base_addr       (weight_base_addr),
        .output_base_addr       (output_base_addr),
        .nn_config              (nn_config),
        .enable_activation      (enable_activation),
        .enable_pooling         (enable_pooling),
        .enable_normalization   (enable_normalization),
        .metadata_wr_en         (metadata_wr_en),
        .metadata_wr_addr       (metadata_wr_addr),
        .metadata_wr_data       (metadata_wr_data),
        .phase_start            (phase_start),
        .phase_id               (phase_id),
        .num_delta_ops          (num_delta_ops),
        .phase_ready            (phase_ready),
        .phase_done             (phase_done),
        .norm_gamma             (norm_gamma),
        .norm_beta              (norm_beta),
        .running_mean           (running_mean),
        .running_var            (running_var),
        .updated_mean           (updated_mean),
        .updated_var            (updated_var),
        .norm_params_valid      (norm_params_valid),
        .training_mode          (training_mode),
        .start                  (start),
        .tile_row               (tile_row),
        .tile_col_start         (tile_col_start),
        .tile_ch_start          (tile_ch_start),
        .done                   (done),
        .busy                   (busy),
        .spad_load_addr         (spad_load_addr),
        .spad_load_data         (spad_load_data),
        .spad_load_en           (spad_load_en),
        .mem_stats              (mem_stats),
        .controller_busy        (controller_busy),
        .m_axi_arid             (m_axi_arid),
        .m_axi_araddr           (m_axi_araddr),
        .m_axi_arlen            (m_axi_arlen),
        .m_axi_arsize           (m_axi_arsize),
        .m_axi_arburst          (m_axi_arburst),
        .m_axi_arlock           (m_axi_arlock),
        .m_axi_arcache          (m_axi_arcache),
        .m_axi_arprot           (m_axi_arprot),
        .m_axi_arvalid          (m_axi_arvalid),
        .m_axi_arready          (m_axi_arready),
        .m_axi_rid              (m_axi_rid),
        .m_axi_rdata            (m_axi_rdata),
        .m_axi_rresp            (m_axi_rresp),
        .m_axi_rlast            (m_axi_rlast),
        .m_axi_rvalid           (m_axi_rvalid),
        .m_axi_rready           (m_axi_rready),
        .m_axi_awid             (m_axi_awid),
        .m_axi_awaddr           (m_axi_awaddr),
        .m_axi_awlen            (m_axi_awlen),
        .m_axi_awsize           (m_axi_awsize),
        .m_axi_awburst          (m_axi_awburst),
        .m_axi_awlock           (m_axi_awlock),
        .m_axi_awcache          (m_axi_awcache),
        .m_axi_awprot           (m_axi_awprot),
        .m_axi_awvalid          (m_axi_awvalid),
        .m_axi_awready          (m_axi_awready),
        .m_axi_wdata            (m_axi_wdata),
        .m_axi_wstrb            (m_axi_wstrb),
        .m_axi_wlast            (m_axi_wlast),
        .m_axi_wvalid           (m_axi_wvalid),
        .m_axi_wready           (m_axi_wready),
        .m_axi_bid              (m_axi_bid),
        .m_axi_bresp            (m_axi_bresp),
        .m_axi_bvalid           (m_axi_bvalid),
        .m_axi_bready           (m_axi_bready)
    );
    
    //=========================================================================
    // Simple AXI Memory Model
    //=========================================================================
    logic [DATA_WIDTH-1:0] off_chip_mem [1024];
    logic [7:0] read_counter;
    
    initial begin
        // Initialize off-chip memory with test pattern
        for (int i = 0; i < 1024; i++) begin
            off_chip_mem[i] = i;
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_arready <= 1'b1;
            m_axi_rvalid <= 1'b0;
            m_axi_rlast <= 1'b0;
            read_counter <= 0;
        end else begin
            // Simple read channel response
            if (m_axi_arvalid && m_axi_arready) begin
                read_counter <= m_axi_arlen;
                m_axi_rvalid <= 1'b1;
                m_axi_rdata <= off_chip_mem[m_axi_araddr >> 2];
            end else if (m_axi_rvalid && m_axi_rready) begin
                if (read_counter > 0) begin
                    read_counter <= read_counter - 1;
                    m_axi_rlast <= (read_counter == 1);
                end else begin
                    m_axi_rvalid <= 1'b0;
                    m_axi_rlast <= 1'b0;
                end
            end
        end
    end
    
    assign m_axi_rid = 4'b0;
    assign m_axi_rresp = 2'b00;
    assign m_axi_awready = 1'b1;
    assign m_axi_wready = 1'b1;
    assign m_axi_bvalid = 1'b0;
    assign m_axi_bid = 4'b0;
    assign m_axi_bresp = 2'b00;
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Test Stimulus
    //=========================================================================
    initial begin
        $display("========================================");
        $display("Stamp-Based Memory Management Testbench");
        $display("========================================\n");
        
        // Initialize
        rst_n = 0;
        metadata_wr_en = 0;
        phase_start = 0;
        start = 0;
        spad_load_en = 0;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        //=====================================================================
        // Test 1: Program metadata for 3 phases with different delta patterns
        //=====================================================================
        $display("[%0t] Test 1: Programming metadata for 3 phases", $time);
        
        program_metadata();
        
        //=====================================================================
        // Test 2: Execute Phase 0 (all loads)
        //=====================================================================
        $display("\n[%0t] Test 2: Executing Phase 0 (cold start - all loads)", $time);
        
        execute_phase(0, 3);  // Phase 0 with 3 delta operations
        
        $display("  Loads: %0d, Moves: %0d, Keeps: %0d", 
                 mem_stats.total_loads, mem_stats.total_moves, mem_stats.total_keeps);
        $display("  Bytes loaded: %0d, Bytes moved: %0d", 
                 mem_stats.bytes_loaded, mem_stats.bytes_moved);
        
        //=====================================================================
        // Test 3: Execute Phase 1 (mix of moves and loads)
        //=====================================================================
        $display("\n[%0t] Test 3: Executing Phase 1 (data reuse with moves)", $time);
        
        execute_phase(1, 4);  // Phase 1 with 4 delta operations
        
        $display("  Loads: %0d, Moves: %0d, Keeps: %0d", 
                 mem_stats.total_loads, mem_stats.total_moves, mem_stats.total_keeps);
        $display("  Bytes loaded: %0d, Bytes moved: %0d", 
                 mem_stats.bytes_loaded, mem_stats.bytes_moved);
        
        // Calculate bandwidth savings
        if (mem_stats.bytes_loaded + mem_stats.bytes_moved > 0) begin
            real savings_pct = 100.0 * mem_stats.bytes_moved / 
                              (mem_stats.bytes_loaded + mem_stats.bytes_moved);
            $display("  Bandwidth savings: %0.1f%%", savings_pct);
        end
        
        //=====================================================================
        // Test 4: Execute Phase 2 (maximum reuse)
        //=====================================================================
        $display("\n[%0t] Test 4: Executing Phase 2 (maximum data reuse)", $time);
        
        execute_phase(2, 5);  // Phase 2 with 5 delta operations
        
        $display("  Loads: %0d, Moves: %0d, Keeps: %0d", 
                 mem_stats.total_loads, mem_stats.total_moves, mem_stats.total_keeps);
        $display("  Bytes loaded: %0d, Bytes moved: %0d", 
                 mem_stats.bytes_loaded, mem_stats.bytes_moved);
        
        //=====================================================================
        // Final Statistics
        //=====================================================================
        $display("\n========================================");
        $display("Final Statistics");
        $display("========================================");
        $display("Total loads:        %0d", mem_stats.total_loads);
        $display("Total moves:        %0d", mem_stats.total_moves);
        $display("Total keeps:        %0d", mem_stats.total_keeps);
        $display("Total bytes loaded: %0d", mem_stats.bytes_loaded);
        $display("Total bytes moved:  %0d", mem_stats.bytes_moved);
        $display("Total cycles:       %0d", mem_stats.cycles_elapsed);
        $display("========================================\n");
        
        $display("TEST PASSED!");
        $finish;
    end
    
    //=========================================================================
    // Helper Tasks
    //=========================================================================
    
    task program_metadata();
        // Phase 0->1 Delta: 3 operations (all loads for cold start)
        // Op 0: Load input tile (1024 bytes)
        metadata_wr_en = 1;
        metadata_wr_addr = 0;
        metadata_wr_data = {8'd2, 16'd1, 2'd0, 32'h0000_0000, 32'h0000_0000, 32'd1024, 32'd0};
        @(posedge clk);
        
        // Op 1: Load weight tile (2048 bytes)
        metadata_wr_addr = 1;
        metadata_wr_data = {8'd2, 16'd2, 2'd1, 32'h0000_1000, 32'h0000_0400, 32'd2048, 32'd0};
        @(posedge clk);
        
        // Op 2: Load output tile (512 bytes)
        metadata_wr_addr = 2;
        metadata_wr_data = {8'd2, 16'd3, 2'd2, 32'h0000_2000, 32'h0000_0C00, 32'd512, 32'd0};
        @(posedge clk);
        
        // Phase 1->2 Delta: 4 operations (2 moves, 2 loads)
        // Op 3: Move input tile (reused from previous phase)
        metadata_wr_addr = 3;
        metadata_wr_data = {8'd1, 16'd1, 2'd0, 32'h0000_0000, 32'h0000_0200, 32'd1024, 32'h0000_0200};
        @(posedge clk);
        
        // Op 4: Keep weight tile (same location)
        metadata_wr_addr = 4;
        metadata_wr_data = {8'd0, 16'd2, 2'd1, 32'h0000_0400, 32'h0000_0400, 32'd2048, 32'd0};
        @(posedge clk);
        
        // Op 5: Load new output tile
        metadata_wr_addr = 5;
        metadata_wr_data = {8'd2, 16'd4, 2'd2, 32'h0000_3000, 32'h0000_0C00, 32'd512, 32'd0};
        @(posedge clk);
        
        // Op 6: Load intermediate data
        metadata_wr_addr = 6;
        metadata_wr_data = {8'd2, 16'd5, 2'd3, 32'h0000_4000, 32'h0000_0E00, 32'd256, 32'd0};
        @(posedge clk);
        
        // Phase 2->3 Delta: 5 operations (mostly moves and keeps)
        // Op 7: Keep input
        metadata_wr_addr = 7;
        metadata_wr_data = {8'd0, 16'd1, 2'd0, 32'h0000_0200, 32'h0000_0200, 32'd1024, 32'd0};
        @(posedge clk);
        
        // Op 8: Move weight
        metadata_wr_addr = 8;
        metadata_wr_data = {8'd1, 16'd2, 2'd1, 32'h0000_0400, 32'h0000_0600, 32'd2048, 32'h0000_0200};
        @(posedge clk);
        
        // Op 9: Move output
        metadata_wr_addr = 9;
        metadata_wr_data = {8'd1, 16'd4, 2'd2, 32'h0000_0C00, 32'h0000_0E00, 32'd512, 32'h0000_0200};
        @(posedge clk);
        
        // Op 10: Keep intermediate
        metadata_wr_addr = 10;
        metadata_wr_data = {8'd0, 16'd5, 2'd3, 32'h0000_0E00, 32'h0000_0E00, 32'd256, 32'd0};
        @(posedge clk);
        
        // Op 11: Load new data
        metadata_wr_addr = 11;
        metadata_wr_data = {8'd2, 16'd6, 2'd0, 32'h0000_5000, 32'h0000_1000, 32'd128, 32'd0};
        @(posedge clk);
        
        metadata_wr_en = 0;
        @(posedge clk);
        
        $display("  Metadata programmed for 3 phases");
    endtask
    
    task execute_phase(input int pid, input int num_ops);
        // Wait for controller to be ready
        wait(phase_ready);
        @(posedge clk);
        
        // Start phase
        phase_id = pid;
        num_delta_ops = num_ops;
        phase_start = 1;
        @(posedge clk);
        phase_start = 0;
        
        // Wait for phase to complete
        wait(phase_done);
        @(posedge clk);
        
        $display("  Phase %0d completed", pid);
    endtask
    
    //=========================================================================
    // Waveform Dumping
    //=========================================================================
    initial begin
        $dumpfile("stamp_memory.vcd");
        $dumpvars(0, stamp_based_memory_tb);
    end
    
    //=========================================================================
    // Timeout
    //=========================================================================
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule : stamp_based_memory_tb

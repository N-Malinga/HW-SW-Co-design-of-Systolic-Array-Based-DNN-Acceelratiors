// ============================================================================
// Multi-Scheduler Wrapper  (fixed for Vivado/XSim)
// Allows runtime selection between all scheduling algorithms.
//
// Fix summary
// -----------
// The original always_comb block indexed into generate-block hierarchical
// paths at run-time (e.g. gen_basic_schedulers[scheduler_select].basic_sched.*)
// which is illegal in IEEE 1800 - generate-block indices must be elaboration-
// time constants.  The fix introduces two intermediate signal arrays
// (basic_* and adv_*) that are driven by the generate loops, then the
// always_comb block muxes those arrays with the run-time selector.
// ============================================================================

`timescale 1ns/1ps

module multi_scheduler_wrapper #(
    parameter MAX_TASKS        = 16,
    parameter TASK_ID_WIDTH    = 8,
    parameter BURST_TIME_WIDTH = 16,
    parameter PRIORITY_WIDTH   = 4,
    parameter DEADLINE_WIDTH   = 32,
    parameter TIME_QUANTUM     = 10
)(
    input  logic clk,
    input  logic rst_n,

    // Scheduler selection (run-time configurable)
    // 0-6 : FIFO / LIFO / SJF / RR / Priority / EDF / LRU  (basic)
    // 7   : SRTF   8 : HRRN   9 : MLQ   10 : MLFQ          (advanced)
    input  logic [3:0] scheduler_select,

    // Task arrival interface
    input  logic                          task_valid,
    input  logic [TASK_ID_WIDTH-1:0]      task_id,
    input  logic [BURST_TIME_WIDTH-1:0]   burst_time,
    input  logic [PRIORITY_WIDTH-1:0]     task_priority,
    input  logic [DEADLINE_WIDTH-1:0]     deadline,
    output logic                          task_ready,

    // Scheduler output
    output logic                          scheduled_task_valid,
    output logic [TASK_ID_WIDTH-1:0]      scheduled_task_id,
    output logic [BURST_TIME_WIDTH-1:0]   scheduled_burst_time,
    output logic [PRIORITY_WIDTH-1:0]     scheduled_priority,
    output logic [DEADLINE_WIDTH-1:0]     scheduled_deadline,
    input  logic                          task_tick,
    input  logic                          task_complete,

    // Status
    output logic [$clog2(MAX_TASKS):0]    queue_count,
    output logic                          queue_full,
    output logic                          queue_empty,

    // Statistics
    output logic [31:0] total_tasks_processed,
    output logic [31:0] total_wait_time,
    output logic [31:0] total_turnaround_time
);

    // -------------------------------------------------------------------------
    // Intermediate arrays - one slot per scheduler instance
    // These are driven by the generate blocks and muxed below.
    // -------------------------------------------------------------------------

    // Basic schedulers (indices 0-6)
    logic                          basic_task_ready      [7];
    logic                          basic_sched_valid     [7];
    logic [TASK_ID_WIDTH-1:0]      basic_sched_id        [7];
    logic [BURST_TIME_WIDTH-1:0]   basic_sched_burst     [7];
    logic [PRIORITY_WIDTH-1:0]     basic_sched_priority  [7];
    logic [DEADLINE_WIDTH-1:0]     basic_sched_deadline  [7];
    logic [$clog2(MAX_TASKS):0]    basic_queue_count     [7];
    logic                          basic_queue_full      [7];
    logic                          basic_queue_empty     [7];

    // Advanced schedulers (indices 0-3  →  select offsets 7-10)
    logic                          adv_task_ready        [4];
    logic                          adv_sched_valid       [4];
    logic [TASK_ID_WIDTH-1:0]      adv_sched_id          [4];
    logic [BURST_TIME_WIDTH-1:0]   adv_sched_burst       [4];
    logic [PRIORITY_WIDTH-1:0]     adv_sched_priority    [4];
    logic [$clog2(MAX_TASKS):0]    adv_queue_count       [4];
    logic                          adv_queue_full        [4];
    logic                          adv_queue_empty       [4];

    // -------------------------------------------------------------------------
    // Generate: 7 basic schedulers
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 7; i++) begin : gen_basic_schedulers
            task_scheduler #(
                .MAX_TASKS       (MAX_TASKS),
                .TASK_ID_WIDTH   (TASK_ID_WIDTH),
                .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
                .PRIORITY_WIDTH  (PRIORITY_WIDTH),
                .DEADLINE_WIDTH  (DEADLINE_WIDTH),
                .TIME_QUANTUM    (TIME_QUANTUM),
                .SCHEDULER_TYPE  (i)
            ) u_basic (
                .clk              (clk),
                .rst_n            (rst_n && (scheduler_select == 4'(i))),
                .task_valid       (task_valid  && (scheduler_select == 4'(i))),
                .task_id          (task_id),
                .burst_time       (burst_time),
                .task_priority         (task_priority),
                .deadline         (deadline),
                .task_ready       (basic_task_ready    [i]),
                .scheduled_task_valid  (basic_sched_valid   [i]),
                .scheduled_task_id     (basic_sched_id      [i]),
                .scheduled_burst_time  (basic_sched_burst   [i]),
                .scheduled_priority    (basic_sched_priority[i]),
                .scheduled_deadline    (basic_sched_deadline[i]),
                .task_complete    (task_complete && (scheduler_select == 4'(i))),
                .queue_count      (basic_queue_count [i]),
                .queue_full       (basic_queue_full  [i]),
                .queue_empty      (basic_queue_empty [i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Generate: 4 advanced schedulers
    // -------------------------------------------------------------------------
    genvar j;
    generate
        for (j = 0; j < 4; j++) begin : gen_advanced_schedulers
            advanced_task_scheduler #(
                .MAX_TASKS       (MAX_TASKS),
                .TASK_ID_WIDTH   (TASK_ID_WIDTH),
                .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
                .PRIORITY_WIDTH  (PRIORITY_WIDTH),
                .DEADLINE_WIDTH  (DEADLINE_WIDTH),
                .SCHEDULER_TYPE  (j)
            ) u_adv (
                .clk              (clk),
                .rst_n            (rst_n && (scheduler_select == 4'(7 + j))),
                .task_valid       (task_valid  && (scheduler_select == 4'(7 + j))),
                .task_id          (task_id),
                .burst_time       (burst_time),
                .task_priority         (task_priority),
                .deadline         (deadline),
                .task_ready       (adv_task_ready    [j]),
                .scheduled_task_valid  (adv_sched_valid   [j]),
                .scheduled_task_id     (adv_sched_id      [j]),
                .scheduled_burst_time  (adv_sched_burst   [j]),
                .scheduled_priority    (adv_sched_priority[j]),
                .task_tick        (task_tick    && (scheduler_select == 4'(7 + j))),
                .task_complete    (task_complete && (scheduler_select == 4'(7 + j))),
                .queue_count      (adv_queue_count [j]),
                .queue_full       (adv_queue_full  [j]),
                .queue_empty      (adv_queue_empty [j])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Output mux - indexes the intermediate arrays (always legal)
    // -------------------------------------------------------------------------
    always_comb begin
        // Defaults (invalid / out-of-range selector)
        task_ready           = 1'b0;
        scheduled_task_valid = 1'b0;
        scheduled_task_id    = '0;
        scheduled_burst_time = '0;
        scheduled_priority   = '0;
        scheduled_deadline   = '0;
        queue_count          = '0;
        queue_full           = 1'b1;
        queue_empty          = 1'b1;

        if (scheduler_select < 4'd7) begin
            // ---- Basic schedulers ----
            task_ready           = basic_task_ready    [scheduler_select];
            scheduled_task_valid = basic_sched_valid   [scheduler_select];
            scheduled_task_id    = basic_sched_id      [scheduler_select];
            scheduled_burst_time = basic_sched_burst   [scheduler_select];
            scheduled_priority   = basic_sched_priority[scheduler_select];
            scheduled_deadline   = basic_sched_deadline[scheduler_select];
            queue_count          = basic_queue_count   [scheduler_select];
            queue_full           = basic_queue_full    [scheduler_select];
            queue_empty          = basic_queue_empty   [scheduler_select];

        end else if (scheduler_select >= 4'd7 && scheduler_select < 4'd11) begin
            // ---- Advanced schedulers (offset by 7) ----
            // scheduler_select - 7 maps  7->0, 8->1, 9->2, 10->3
            task_ready           = adv_task_ready    [scheduler_select - 4'd7];
            scheduled_task_valid = adv_sched_valid   [scheduler_select - 4'd7];
            scheduled_task_id    = adv_sched_id      [scheduler_select - 4'd7];
            scheduled_burst_time = adv_sched_burst   [scheduler_select - 4'd7];
            scheduled_priority   = adv_sched_priority[scheduler_select - 4'd7];
            scheduled_deadline   = '0;   // advanced schedulers have no deadline output
            queue_count          = adv_queue_count   [scheduler_select - 4'd7];
            queue_full           = adv_queue_full    [scheduler_select - 4'd7];
            queue_empty          = adv_queue_empty   [scheduler_select - 4'd7];
        end
    end

    // -------------------------------------------------------------------------
    // Statistics collection
    // -------------------------------------------------------------------------
    typedef struct {
        logic [TASK_ID_WIDTH-1:0] id;
        logic [31:0]              arrival_time;
        logic [31:0]              completion_time;
    } task_stats_t;

    task_stats_t task_stats     [255:0];
    logic [7:0]  stats_write_ptr;
    logic [7:0]  stats_read_ptr;
    logic [31:0] current_time;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_tasks_processed <= '0;
            total_wait_time       <= '0;
            total_turnaround_time <= '0;
            stats_write_ptr       <= '0;
            stats_read_ptr        <= '0;
            current_time          <= '0;
            for (int k = 0; k < 256; k++) begin
                task_stats[k].id             <= '0;
                task_stats[k].arrival_time   <= '0;
                task_stats[k].completion_time<= '0;
            end
        end else begin
            current_time <= current_time + 1;

            // Record task arrival
            if (task_valid && task_ready) begin
                task_stats[stats_write_ptr].id           <= task_id;
                task_stats[stats_write_ptr].arrival_time <= current_time;
                stats_write_ptr <= stats_write_ptr + 1;
            end

            // Record task completion
            if (task_complete && scheduled_task_valid) begin
                for (int k = 0; k < 256; k++) begin
                    if (task_stats[k].id == scheduled_task_id) begin
                        automatic logic [31:0] turnaround;
                        automatic logic [31:0] wait_t;
                        task_stats[k].completion_time <= current_time;
                        turnaround = current_time - task_stats[k].arrival_time;
                        wait_t     = (turnaround >= scheduled_burst_time) ?
                                     (turnaround  - scheduled_burst_time) : '0;
                        total_turnaround_time <= total_turnaround_time + turnaround;
                        total_wait_time       <= total_wait_time       + wait_t;
                        total_tasks_processed <= total_tasks_processed + 1;
                        break;
                    end
                end
            end
        end
    end

endmodule
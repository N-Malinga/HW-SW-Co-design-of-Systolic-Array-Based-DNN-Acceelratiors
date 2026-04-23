// ============================================================================
// Multi-Scheduler Wrapper
// Allows runtime selection between different scheduling algorithms
// ============================================================================

`timescale 1ns/1ps

module multi_scheduler_wrapper #(
    parameter MAX_TASKS = 16,
    parameter TASK_ID_WIDTH = 8,
    parameter BURST_TIME_WIDTH = 16,
    parameter PRIORITY_WIDTH = 4,
    parameter DEADLINE_WIDTH = 32,
    parameter TIME_QUANTUM = 10
)(
    input  logic clk,
    input  logic rst_n,
    
    // Scheduler selection (runtime configurable)
    input  logic [3:0] scheduler_select,
    // 0:FIFO, 1:LIFO, 2:SJF, 3:RR, 4:Priority, 5:EDF, 6:LRU
    // 7:SRTF, 8:HRRN, 9:MLQ, 10:MLFQ
    
    // Task arrival interface
    input  logic task_valid,
    input  logic [TASK_ID_WIDTH-1:0] task_id,
    input  logic [BURST_TIME_WIDTH-1:0] burst_time,
    input  logic [PRIORITY_WIDTH-1:0] priority,
    input  logic [DEADLINE_WIDTH-1:0] deadline,
    output logic task_ready,
    
    // Scheduler output
    output logic scheduled_task_valid,
    output logic [TASK_ID_WIDTH-1:0] scheduled_task_id,
    output logic [BURST_TIME_WIDTH-1:0] scheduled_burst_time,
    output logic [PRIORITY_WIDTH-1:0] scheduled_priority,
    output logic [DEADLINE_WIDTH-1:0] scheduled_deadline,
    input  logic task_tick,
    input  logic task_complete,
    
    // Status
    output logic [$clog2(MAX_TASKS):0] queue_count,
    output logic queue_full,
    output logic queue_empty,
    
    // Statistics
    output logic [31:0] total_tasks_processed,
    output logic [31:0] total_wait_time,
    output logic [31:0] total_turnaround_time
);

    // These signals are intermediate wires used to carry outputs from the basic schedulers
    // never used
    logic basic_task_ready;
    logic basic_scheduled_valid;
    logic [TASK_ID_WIDTH-1:0] basic_scheduled_id;
    logic [BURST_TIME_WIDTH-1:0] basic_scheduled_burst;
    logic [PRIORITY_WIDTH-1:0] basic_scheduled_priority;
    logic [DEADLINE_WIDTH-1:0] basic_scheduled_deadline;
    logic [$clog2(MAX_TASKS):0] basic_queue_count;
    logic basic_queue_full;
    logic basic_queue_empty;
    
    // Intermediate signals for advanced schedulers
    logic adv_task_ready;
    logic adv_scheduled_valid;
    logic [TASK_ID_WIDTH-1:0] adv_scheduled_id;
    logic [BURST_TIME_WIDTH-1:0] adv_scheduled_burst;
    logic [PRIORITY_WIDTH-1:0] adv_scheduled_priority;
    logic [$clog2(MAX_TASKS):0] adv_queue_count;
    logic adv_queue_full;
    logic adv_queue_empty;
    
    // Instantiate all basic schedulers
    genvar i;   //genvar is not a runtime , It is used only during compilation (elaboration time) / The loop runs once during synthesis, not during execution
    generate    //generate is a construct used to replicate hardware structures
        for (i = 0; i < 7; i++) begin : gen_basic_schedulers  //This gives a name , That created an array of instances
            task_scheduler #(     //This is a single instance of task_scheduler module
                .MAX_TASKS(MAX_TASKS),            //Configuring the scheduler (parameters)
                .TASK_ID_WIDTH(TASK_ID_WIDTH),
                .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
                .PRIORITY_WIDTH(PRIORITY_WIDTH),
                .DEADLINE_WIDTH(DEADLINE_WIDTH),
                .TIME_QUANTUM(TIME_QUANTUM),
                .SCHEDULER_TYPE(i)
            ) basic_sched (        //instance_name (connections)
                .clk(clk),  //Connecting signals (ports)
                .rst_n(rst_n && (scheduler_select == i)),    //Only active scheduler gets reset
                .task_valid(task_valid && (scheduler_select == i)),
                .task_id(task_id),
                .burst_time(burst_time),
                .priority(priority),
                .deadline(deadline),
                .task_ready(),
                .scheduled_task_valid(),
                .scheduled_task_id(),
                .scheduled_burst_time(),
                .scheduled_priority(),
                .scheduled_deadline(),
                .task_complete(task_complete && (scheduler_select == i)),
                .queue_count(),
                .queue_full(),
                .queue_empty()
            );
        end
    endgenerate
    
    // Instantiate advanced schedulers
    genvar j;
    generate
        for (j = 0; j < 4; j++) begin : gen_advanced_schedulers
            advanced_task_scheduler #(
                .MAX_TASKS(MAX_TASKS),
                .TASK_ID_WIDTH(TASK_ID_WIDTH),
                .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
                .PRIORITY_WIDTH(PRIORITY_WIDTH),
                .DEADLINE_WIDTH(DEADLINE_WIDTH),
                .SCHEDULER_TYPE(j)
            ) adv_sched (
                .clk(clk),
                .rst_n(rst_n && (scheduler_select == (7 + j))),
                .task_valid(task_valid && (scheduler_select == (7 + j))),
                .task_id(task_id),
                .burst_time(burst_time),
                .priority(priority),
                .deadline(deadline),
                .task_ready(),
                .scheduled_task_valid(),
                .scheduled_task_id(),
                .scheduled_burst_time(),
                .scheduled_priority(),
                .task_tick(task_tick && (scheduler_select == (7 + j))),
                .task_complete(task_complete && (scheduler_select == (7 + j))),
                .queue_count(),
                .queue_full(),
                .queue_empty()
            );
        end
    endgenerate
    
    // Output multiplexing based on scheduler selection
    always_comb begin   // Pure combinational logic , Triggered by any change in inputs
        if (scheduler_select < 7) begin
            // Basic schedulers
            task_ready = gen_basic_schedulers[scheduler_select].basic_sched.task_ready;
            scheduled_task_valid = gen_basic_schedulers[scheduler_select].basic_sched.scheduled_task_valid;
            scheduled_task_id = gen_basic_schedulers[scheduler_select].basic_sched.scheduled_task_id;
            scheduled_burst_time = gen_basic_schedulers[scheduler_select].basic_sched.scheduled_burst_time;
            scheduled_priority = gen_basic_schedulers[scheduler_select].basic_sched.scheduled_priority;
            scheduled_deadline = gen_basic_schedulers[scheduler_select].basic_sched.scheduled_deadline;
            queue_count = gen_basic_schedulers[scheduler_select].basic_sched.queue_count;
            queue_full = gen_basic_schedulers[scheduler_select].basic_sched.queue_full;
            queue_empty = gen_basic_schedulers[scheduler_select].basic_sched.queue_empty;
        end else if (scheduler_select >= 7 && scheduler_select < 11) begin
            // Advanced schedulers
            task_ready = gen_advanced_schedulers[scheduler_select - 7].adv_sched.task_ready;
            scheduled_task_valid = gen_advanced_schedulers[scheduler_select - 7].adv_sched.scheduled_task_valid;
            scheduled_task_id = gen_advanced_schedulers[scheduler_select - 7].adv_sched.scheduled_task_id;
            scheduled_burst_time = gen_advanced_schedulers[scheduler_select - 7].adv_sched.scheduled_burst_time;
            scheduled_priority = gen_advanced_schedulers[scheduler_select - 7].adv_sched.scheduled_priority;
            scheduled_deadline = 'x;  // Advanced schedulers don't output deadline (unknown value)
            queue_count = gen_advanced_schedulers[scheduler_select - 7].adv_sched.queue_count;
            queue_full = gen_advanced_schedulers[scheduler_select - 7].adv_sched.queue_full;
            queue_empty = gen_advanced_schedulers[scheduler_select - 7].adv_sched.queue_empty;
        end else begin
            task_ready = 1'b0;
            scheduled_task_valid = 1'b0;
            scheduled_task_id = 'x;
            scheduled_burst_time = 'x;
            scheduled_priority = 'x;
            scheduled_deadline = 'x;
            queue_count = 'x;
            queue_full = 1'b1;
            queue_empty = 1'b1;
        end
    end
    
    // Statistics collection
    //creating a custom data type named task_stats_t
    typedef struct {
        logic [TASK_ID_WIDTH-1:0] id;
        logic [31:0] arrival_time;
        logic [31:0] completion_time;
    } task_stats_t;
    
    task_stats_t task_stats [255:0];  //array of 256 tasks
    logic [7:0] stats_write_ptr;   //Tells where to store the next incoming task’s data in the task_stats array
    logic [7:0] stats_read_ptr;   //Used to read or process stored task statistics
    logic [31:0] current_time;    //This is a global time counter
    
    //It runs on every clock and keeps track of time, task arrivals, and task completions.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_tasks_processed <= '0;
            total_wait_time <= '0;
            total_turnaround_time <= '0;
            stats_write_ptr <= '0;
            stats_read_ptr <= '0;
            current_time <= '0;
        end else begin
            current_time <= current_time + 1;
            
            // Record task arrival
            if (task_valid && task_ready) begin //(A new task is coming && Scheduler can accept it)
                task_stats[stats_write_ptr].id <= task_id;
                task_stats[stats_write_ptr].arrival_time <= current_time;
                stats_write_ptr <= stats_write_ptr + 1;   //move pointer to next slot
            end
            
            // Record task completion
            if (task_complete && scheduled_task_valid) begin
                automatic logic [31:0] turnaround, wait_time;  //Temporary (local) variables for calculation
                
                // Find the task in stats
                for (int k = 0; k < 256; k++) begin
                    if (task_stats[k].id == scheduled_task_id) begin
                        task_stats[k].completion_time <= current_time;
                        turnaround = current_time - task_stats[k].arrival_time;
                        wait_time = turnaround - scheduled_burst_time;
                        
                        total_turnaround_time <= total_turnaround_time + turnaround;
                        total_wait_time <= total_wait_time + wait_time;
                        total_tasks_processed <= total_tasks_processed + 1;
                        break;
                    end
                end
            end
        end
    end

endmodule

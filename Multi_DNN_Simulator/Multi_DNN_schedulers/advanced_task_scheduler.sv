// ============================================================================
// Advanced Task Schedulers
// Includes: SRTF (Shortest Remaining Time First), HRRN, MLQ
// ============================================================================

`timescale 1ns/1ps

module advanced_task_scheduler #(
    parameter MAX_TASKS = 16,
    parameter TASK_ID_WIDTH = 8,        // default bit-width for task IDs
    parameter BURST_TIME_WIDTH = 16,
    parameter PRIORITY_WIDTH = 4,
    parameter DEADLINE_WIDTH = 32,
    parameter NUM_QUEUES = 4,           // For Multi-Level Queue
    parameter SCHEDULER_TYPE = 0        // 0:SRTF, 1:HRRN, 2:MLQ, 3:MLFQ
)(
    input  logic clk,
    input  logic rst_n,
    
    // Task arrival interface
    input  logic task_valid,
    input  logic [TASK_ID_WIDTH-1:0] task_id,
    input  logic [BURST_TIME_WIDTH-1:0] burst_time,
    input  logic [PRIORITY_WIDTH-1:0] task_priority,
    input  logic [DEADLINE_WIDTH-1:0] deadline,
    output logic task_ready,
    
    // Scheduler output
    output logic scheduled_task_valid,
    output logic [TASK_ID_WIDTH-1:0] scheduled_task_id,
    output logic [BURST_TIME_WIDTH-1:0] scheduled_burst_time,
    output logic [PRIORITY_WIDTH-1:0] scheduled_priority,
    input  logic task_tick,        // one time unit has passed for the currently running task
    input  logic task_complete,
    
    // Status
    output logic [$clog2(MAX_TASKS):0] queue_count,
    output logic queue_full,
    output logic queue_empty
);

    // Task structure
    typedef struct packed {
        logic valid;
        logic [TASK_ID_WIDTH-1:0] id;
        logic [BURST_TIME_WIDTH-1:0] burst_time;
        logic [BURST_TIME_WIDTH-1:0] remaining_time;
        logic [PRIORITY_WIDTH-1:0] task_priority;
        logic [DEADLINE_WIDTH-1:0] deadline;
        logic [DEADLINE_WIDTH-1:0] arrival_time;
        logic [DEADLINE_WIDTH-1:0] wait_time;
        logic [$clog2(NUM_QUEUES)-1:0] queue_level;
    } task_t;
    
    // Task queues
    task_t task_queue [MAX_TASKS-1:0];
    logic [$clog2(MAX_TASKS):0] num_tasks;
    logic [DEADLINE_WIDTH-1:0] current_time;
    logic [TASK_ID_WIDTH-1:0] current_task_id;
    logic task_running;
    
    assign queue_count = num_tasks;
    assign queue_full = (num_tasks == MAX_TASKS);
    assign queue_empty = (num_tasks == 0);
    assign task_ready = !queue_full;
    
    // Time counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_time <= '0;
        else
            current_time <= current_time + 1;
    end
    
    // Task management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            num_tasks <= '0;
            for (int i = 0; i < MAX_TASKS; i++) begin
                task_queue[i] <= '0;
            end
            task_running <= 1'b0;
        end else begin
            // Add new task
            if (task_valid && !queue_full) begin
                task_queue[num_tasks].valid <= 1'b1;
                task_queue[num_tasks].id <= task_id;
                task_queue[num_tasks].burst_time <= burst_time;
                task_queue[num_tasks].remaining_time <= burst_time;
                task_queue[num_tasks].task_priority <= task_priority;
                task_queue[num_tasks].deadline <= deadline;
                task_queue[num_tasks].arrival_time <= current_time;
                task_queue[num_tasks].wait_time <= '0;
                task_queue[num_tasks].queue_level <= '0;
                num_tasks <= num_tasks + 1;
            end
            
            // Update remaining time if task is executing
            if (scheduled_task_valid && task_tick) begin
                for (int i = 0; i < MAX_TASKS; i++) begin
                    if (task_queue[i].valid && task_queue[i].id == scheduled_task_id) begin
                        task_queue[i].remaining_time <= task_queue[i].remaining_time - 1;
                    end
                end
            end
            
            // Update wait times for waiting tasks
            for (int i = 0; i < num_tasks; i++) begin
                if (task_queue[i].valid && 
                    (!scheduled_task_valid || task_queue[i].id != scheduled_task_id)) begin
                    task_queue[i].wait_time <= task_queue[i].wait_time + 1;
                end
            end
            
            // Remove completed task
            if (task_complete && scheduled_task_valid) begin
                automatic int remove_idx = -1;
                
                // Find the completed task
                for (int i = 0; i < num_tasks; i++) begin
                    if (task_queue[i].id == scheduled_task_id) begin
                        remove_idx = i;
                        break;
                    end
                end
                
                // Shift queue
                if (remove_idx >= 0) begin
                    for (int i = remove_idx; i < MAX_TASKS-1; i++) begin
                        if (i < num_tasks - 1)
                            task_queue[i] <= task_queue[i+1];
                    end
                    task_queue[num_tasks-1] <= '0;
                    num_tasks <= num_tasks - 1;
                end
                task_running <= 1'b0;
            end
        end
    end
    
    // Scheduling logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scheduled_task_valid <= 1'b0;
            scheduled_task_id <= '0;
            scheduled_burst_time <= '0;
            scheduled_priority <= '0;
            current_task_id <= '0;
        end else begin
            if (!queue_empty) begin
                case (SCHEDULER_TYPE)
                    0: schedule_srtf();
                    1: schedule_hrrn();
                    2: schedule_mlq();
                    3: schedule_mlfq();
                    default: schedule_srtf();
                endcase
            end else begin
                scheduled_task_valid <= 1'b0;
                task_running <= 1'b0;
            end
        end
    end
    
    // SRTF: Shortest Remaining Time First (Preemptive SJF)
    task schedule_srtf();
        automatic int shortest_idx = 0;
        automatic logic [BURST_TIME_WIDTH-1:0] min_time = task_queue[0].remaining_time;
        
        for (int i = 1; i < num_tasks; i++) begin
            if (task_queue[i].remaining_time < min_time) begin
                min_time = task_queue[i].remaining_time;
                shortest_idx = i;
            end
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[shortest_idx].id;
        scheduled_burst_time <= task_queue[shortest_idx].remaining_time;
        scheduled_priority <= task_queue[shortest_idx].task_priority;
        current_task_id <= task_queue[shortest_idx].id;
    endtask
    
    // HRRN: Highest Response Ratio Next
    // Response Ratio = (Wait Time + Burst Time) / Burst Time
    task schedule_hrrn();
        automatic int highest_idx = 0;
        automatic real max_ratio = 0.0;
        automatic real current_ratio;
        
        for (int i = 0; i < num_tasks; i++) begin
            if (task_queue[i].burst_time > 0) begin
                current_ratio = real'(task_queue[i].wait_time + task_queue[i].burst_time) / 
                               real'(task_queue[i].burst_time);
                if (current_ratio > max_ratio) begin
                    max_ratio = current_ratio;
                    highest_idx = i;
                end
            end
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[highest_idx].id;
        scheduled_burst_time <= task_queue[highest_idx].burst_time;
        scheduled_priority <= task_queue[highest_idx].task_priority;
        current_task_id <= task_queue[highest_idx].id;
    endtask
    
    // MLQ: Multi-Level Queue (Static priority queues)
    task schedule_mlq();
        automatic int selected_idx = -1;
        automatic logic [$clog2(NUM_QUEUES)-1:0] highest_queue = NUM_QUEUES - 1;
        
        // Find highest priority queue with tasks
        for (int q = NUM_QUEUES - 1; q >= 0; q--) begin    //q is an integer (32-bit by default)
            for (int i = 0; i < num_tasks; i++) begin
                if (task_queue[i].queue_level == q[$clog2(NUM_QUEUES)-1:0]) begin   //Take only the lower bits of q so it matches the size of queue_level
                    selected_idx = i;
                    break;
                end
            end
            if (selected_idx >= 0) break;
        end
        
        if (selected_idx >= 0) begin
            scheduled_task_valid <= 1'b1;
            scheduled_task_id <= task_queue[selected_idx].id;
            scheduled_burst_time <= task_queue[selected_idx].burst_time;
            scheduled_priority <= task_queue[selected_idx].task_priority;
        end else begin
            scheduled_task_valid <= 1'b0;
        end
    endtask
    
    // MLFQ: Multi-Level Feedback Queue (Dynamic priority adjustment)
    task schedule_mlfq();
        automatic int selected_idx = -1;
        
        // Find highest priority queue with tasks (queue 0 is highest)
        for (int q = 0; q < NUM_QUEUES; q++) begin
            for (int i = 0; i < num_tasks; i++) begin
                if (task_queue[i].queue_level == q[$clog2(NUM_QUEUES)-1:0]) begin
                    selected_idx = i;
                    break;
                end
            end
            if (selected_idx >= 0) break;
        end
        
        if (selected_idx >= 0) begin
            scheduled_task_valid <= 1'b1;
            scheduled_task_id <= task_queue[selected_idx].id;
            scheduled_burst_time <= task_queue[selected_idx].remaining_time;
            scheduled_priority <= task_queue[selected_idx].task_priority;
            
            // Demote task to lower priority queue if it doesn't complete
            if (task_tick && !task_complete) begin
                if (task_queue[selected_idx].queue_level < NUM_QUEUES - 1) begin
                    task_queue[selected_idx].queue_level <= 
                        task_queue[selected_idx].queue_level + 1;
                end
            end
            
            // Promote tasks that have been waiting too long (aging)
            for (int i = 0; i < num_tasks; i++) begin
                if (task_queue[i].wait_time > 100 && task_queue[i].queue_level > 0) begin
                    task_queue[i].queue_level <= task_queue[i].queue_level - 1;
                end
            end
        end else begin
            scheduled_task_valid <= 1'b0;
        end
    endtask

endmodule

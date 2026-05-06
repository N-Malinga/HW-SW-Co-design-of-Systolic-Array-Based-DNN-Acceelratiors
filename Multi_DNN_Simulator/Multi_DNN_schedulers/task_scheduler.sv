// ============================================================================
// Multi-Algorithm Hardware Task Scheduler
// Supports: FIFO, LIFO, SJF, Round Robin, Priority, EDF, LRU
// ============================================================================

`timescale 1ns/1ps

module task_scheduler #(
    parameter MAX_TASKS = 16,           // Maximum number of tasks in queue
    parameter TASK_ID_WIDTH = 8,        // Width of task ID
    parameter BURST_TIME_WIDTH = 16,    // Width of burst time (execution time) field
    parameter PRIORITY_WIDTH = 4,       // Width of priority field
    parameter DEADLINE_WIDTH = 32,      // Width of deadline field
    parameter TIME_QUANTUM = 10,        // Time quantum for Round Robin
    parameter SCHEDULER_TYPE = 0        // 0:FIFO, 1:LIFO, 2:SJF, 3:RR, 4:Priority, 5:EDF, 6:LRU
)(

    //Inputs = pins that receive signals into the chip
    //Outputs = pins that send signals out of the chip
    input  logic clk,
    input  logic rst_n,
    
    // Task arrival interface
    input  logic task_valid,
    input  logic [TASK_ID_WIDTH-1:0] task_id,
    input  logic [BURST_TIME_WIDTH-1:0] burst_time,
    input  logic [PRIORITY_WIDTH-1:0] task_priority,
    input  logic [DEADLINE_WIDTH-1:0] deadline,

    output logic task_ready,  //Scheduler can accept new task
    
    // Scheduler output
    output logic scheduled_task_valid,   //Output task is valid
    output logic [TASK_ID_WIDTH-1:0] scheduled_task_id,
    output logic [BURST_TIME_WIDTH-1:0] scheduled_burst_time,
    output logic [PRIORITY_WIDTH-1:0] scheduled_priority,
    output logic [DEADLINE_WIDTH-1:0] scheduled_deadline,

    input  logic task_complete,   //Current task finished
    
    // Status outputs
    output logic [$clog2(MAX_TASKS):0] queue_count,  //$clog2(How many bits are needed to represent a number)
    output logic queue_full,
    output logic queue_empty
);

    // Task structure
    // custom data type called task_t
    typedef struct packed {    //struct = group of variables, packed = stored as continuous bits
        logic valid;  //is job active
        logic [TASK_ID_WIDTH-1:0] id;
        logic [BURST_TIME_WIDTH-1:0] burst_time;
        logic [BURST_TIME_WIDTH-1:0] remaining_time;
        logic [PRIORITY_WIDTH-1:0] task_priority;
        logic [DEADLINE_WIDTH-1:0] deadline;
        logic [DEADLINE_WIDTH-1:0] arrival_time;
        logic [DEADLINE_WIDTH-1:0] last_access_time;
    } task_t;
    
    // Task queue
    task_t task_queue [MAX_TASKS-1:0];   //Array of tasks (queue) , task_queue[0], task_queue[1], ..., task_queue[MAX_TASKS-1]
    logic [$clog2(MAX_TASKS):0] num_tasks; //Number of tasks currently in queue [4:0]  → 5 bits
    logic [DEADLINE_WIDTH-1:0] current_time; //Global time counter for scheduling decisions
    logic [BURST_TIME_WIDTH-1:0] quantum_counter; //Counter for Round Robin time quantum
    logic task_running; 
    
    // Status signals
    assign queue_count = num_tasks; //Update automatically when num_tasks changes  , num_tasks → internal counter , queue_count → output port
    assign queue_full = (num_tasks == MAX_TASKS);
    assign queue_empty = (num_tasks == 0);
    assign task_ready = !queue_full;
    
    // Current time counter
    always_ff @(posedge clk or negedge rst_n) begin  //sequential logic (flip-flop) , trigger on ising edge or negative edge of reset
        if (!rst_n)
            current_time <= '0;
        else
            current_time <= current_time + 1;
    end
    
    // Task insertion logic
    // Reset + Adding tasks + Removing tasks + Updating LRU
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin  //When reset is active:
            num_tasks <= '0;
            for (int i = 0; i < MAX_TASKS; i++) begin  //Clear entire queue
                task_queue[i] <= '0;
            end
        end else begin
            // Handle new task arrival
            if (task_valid && !queue_full) begin
                task_queue[num_tasks].valid <= 1'b1;  //<size>'<base><value>
                task_queue[num_tasks].id <= task_id;
                task_queue[num_tasks].burst_time <= burst_time;
                task_queue[num_tasks].remaining_time <= burst_time;
                task_queue[num_tasks].task_priority <= task_priority;
                task_queue[num_tasks].deadline <= deadline;
                task_queue[num_tasks].arrival_time <= current_time;
                task_queue[num_tasks].last_access_time <= current_time;
                num_tasks <= num_tasks + 1;
            end
            
            // Handle task completion
            if (task_complete && scheduled_task_valid) begin
                // Remove completed task and shift queue
                for (int i = 0; i < MAX_TASKS-1; i++) begin
                    if (i < num_tasks - 1)
                        task_queue[i] <= task_queue[i+1];
                end
                task_queue[num_tasks-1] <= '0;  //Clear Last Slot
                num_tasks <= num_tasks - 1;
            end
            
            // Update last access time for LRU
            if (scheduled_task_valid && SCHEDULER_TYPE == 6) begin
                task_queue[0].last_access_time <= current_time;
            end
        end
    end
    
    // Scheduling logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scheduled_task_valid <= 1'b0;
            scheduled_task_id <= '0;  //Set ALL bits to 0 , eg: 8'b00000000
            scheduled_burst_time <= '0;
            scheduled_priority <= '0;
            scheduled_deadline <= '0;
            quantum_counter <= '0;
            task_running <= 1'b0;
        end else begin
            if (!queue_empty) begin   //If there are tasks in queue
                case (SCHEDULER_TYPE)
                    0: schedule_fifo();
                    1: schedule_lifo();
                    2: schedule_sjf();
                    3: schedule_round_robin();
                    4: schedule_priority();
                    5: schedule_edf();
                    6: schedule_lru();
                    default: schedule_fifo();
                endcase
            end else begin
                scheduled_task_valid <= 1'b0;
                task_running <= 1'b0;
            end
        end
    end
    
    // FIFO Scheduler (First In First Out)
    task schedule_fifo();
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[0].id;
        scheduled_burst_time <= task_queue[0].burst_time;
        scheduled_priority <= task_queue[0].task_priority;
        scheduled_deadline <= task_queue[0].deadline;
    endtask
    
    // LIFO Scheduler (Last In First Out / Stack)
    task schedule_lifo();
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[num_tasks-1].id;
        scheduled_burst_time <= task_queue[num_tasks-1].burst_time;
        scheduled_priority <= task_queue[num_tasks-1].task_priority;
        scheduled_deadline <= task_queue[num_tasks-1].deadline;
    endtask
    
    // SJF Scheduler (Shortest Job First)
    task schedule_sjf();
        automatic int shortest_idx = 0;  //Create a new fresh variable every time the task/function runs
        automatic logic [BURST_TIME_WIDTH-1:0] min_time = task_queue[0].burst_time;
        
        for (int i = 1; i < num_tasks; i++) begin
            if (task_queue[i].burst_time < min_time) begin
                min_time = task_queue[i].burst_time;
                shortest_idx = i;
            end
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[shortest_idx].id;
        scheduled_burst_time <= task_queue[shortest_idx].burst_time;
        scheduled_priority <= task_queue[shortest_idx].task_priority;
        scheduled_deadline <= task_queue[shortest_idx].deadline;
        
        // Move shortest task to front
        if (shortest_idx != 0) begin
            task_t temp = task_queue[0];
            task_queue[0] = task_queue[shortest_idx];
            task_queue[shortest_idx] = temp;
        end
    endtask
    
    // Round Robin Scheduler
    task schedule_round_robin();
        if (!task_running) begin
            quantum_counter <= TIME_QUANTUM;
            task_running <= 1'b1;
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[0].id;
        scheduled_burst_time <= task_queue[0].burst_time;
        scheduled_priority <= task_queue[0].task_priority;
        scheduled_deadline <= task_queue[0].deadline;
        
        if (quantum_counter > 0) begin
            quantum_counter <= quantum_counter - 1;
        end else begin
            // Time quantum expired, move task to end of queue
            task_t temp = task_queue[0];
            for (int i = 0; i < MAX_TASKS-1; i++) begin
                if (i < num_tasks - 1)
                    task_queue[i] <= task_queue[i+1];
            end
            task_queue[num_tasks-1] <= temp;
            quantum_counter <= TIME_QUANTUM;
        end
    endtask
    
    // Priority Scheduler (Higher priority value = higher priority)
    task schedule_priority();
        automatic int highest_idx = 0;
        automatic logic [PRIORITY_WIDTH-1:0] max_priority = task_queue[0].task_priority;
        
        for (int i = 1; i < num_tasks; i++) begin
            if (task_queue[i].task_priority > max_priority) begin
                max_priority = task_queue[i].task_priority;
                highest_idx = i;
            end
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[highest_idx].id;
        scheduled_burst_time <= task_queue[highest_idx].burst_time;
        scheduled_priority <= task_queue[highest_idx].task_priority;
        scheduled_deadline <= task_queue[highest_idx].deadline;
        
        // Move highest priority task to front
        if (highest_idx != 0) begin
            task_t temp = task_queue[0];
            task_queue[0] = task_queue[highest_idx];
            task_queue[highest_idx] = temp;
        end
    endtask
    
    // EDF Scheduler (Earliest Deadline First)
    task schedule_edf();
        automatic int earliest_idx = 0;
        automatic logic [DEADLINE_WIDTH-1:0] min_deadline = task_queue[0].deadline;
        
        for (int i = 1; i < num_tasks; i++) begin
            if (task_queue[i].deadline < min_deadline) begin
                min_deadline = task_queue[i].deadline;
                earliest_idx = i;
            end
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[earliest_idx].id;
        scheduled_burst_time <= task_queue[earliest_idx].burst_time;
        scheduled_priority <= task_queue[earliest_idx].task_priority;
        scheduled_deadline <= task_queue[earliest_idx].deadline;
        
        // Move earliest deadline task to front
        if (earliest_idx != 0) begin
            task_t temp = task_queue[0];
            task_queue[0] = task_queue[earliest_idx];
            task_queue[earliest_idx] = temp;
        end
    endtask
    
    // LRU Scheduler (Least Recently Used)
    task schedule_lru();
        automatic int lru_idx = 0;
        automatic logic [DEADLINE_WIDTH-1:0] min_access = task_queue[0].last_access_time;
        
        for (int i = 1; i < num_tasks; i++) begin
            if (task_queue[i].last_access_time < min_access) begin
                min_access = task_queue[i].last_access_time;
                lru_idx = i;
            end
        end
        
        scheduled_task_valid <= 1'b1;
        scheduled_task_id <= task_queue[lru_idx].id;
        scheduled_burst_time <= task_queue[lru_idx].burst_time;
        scheduled_priority <= task_queue[lru_idx].task_priority;
        scheduled_deadline <= task_queue[lru_idx].deadline;
        
        // Move LRU task to front
        if (lru_idx != 0) begin
            task_t temp = task_queue[0];
            task_queue[0] = task_queue[lru_idx];
            task_queue[lru_idx] = temp;
        end
    endtask

endmodule


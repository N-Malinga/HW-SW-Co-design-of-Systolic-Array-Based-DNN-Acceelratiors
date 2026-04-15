// ============================================================================
// Task Scheduler Testbench
// Tests all scheduling algorithms with random task arrivals
// ============================================================================

`timescale 1ns/1ps

module task_scheduler_tb;

    // Parameters
    parameter CLK_PERIOD = 10;
    parameter MAX_TASKS = 16;
    parameter TASK_ID_WIDTH = 8;
    parameter BURST_TIME_WIDTH = 16;
    parameter PRIORITY_WIDTH = 4;
    parameter DEADLINE_WIDTH = 32;
    parameter TIME_QUANTUM = 10;
    parameter NUM_TEST_TASKS = 50;
    
    // Clock and reset
    logic clk;
    logic rst_n;
    
    // Task arrival interface
    logic task_valid;
    logic [TASK_ID_WIDTH-1:0] task_id;
    logic [BURST_TIME_WIDTH-1:0] burst_time;
    logic [PRIORITY_WIDTH-1:0] priority;
    logic [DEADLINE_WIDTH-1:0] deadline;
    logic task_ready;
    
    // Scheduler output
    logic scheduled_task_valid;
    logic [TASK_ID_WIDTH-1:0] scheduled_task_id;
    logic [BURST_TIME_WIDTH-1:0] scheduled_burst_time;
    logic [PRIORITY_WIDTH-1:0] scheduled_priority;
    logic [DEADLINE_WIDTH-1:0] scheduled_deadline;
    logic task_complete;
    
    // Status
    logic [$clog2(MAX_TASKS):0] queue_count;
    logic queue_full;
    logic queue_empty;
    
    // Test variables
    int tasks_submitted = 0;
    int tasks_completed = 0;
    int scheduler_type;
    
    // DUT instances for different schedulers
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(0)  // FIFO
    ) dut_fifo (.*);
    
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(1)  // LIFO
    ) dut_lifo (.*);
    
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(2)  // SJF
    ) dut_sjf (.*);
    
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(3)  // Round Robin
    ) dut_rr (.*);
    
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(4)  // Priority
    ) dut_priority (.*);
    
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(5)  // EDF
    ) dut_edf (.*);
    
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(6)  // LRU
    ) dut_lru (.*);
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Main test stimulus
    initial begin
        $display("====================================================");
        $display("Task Scheduler Testbench");
        $display("====================================================");
        $display("MAX_TASKS: %0d", MAX_TASKS);
        $display("TIME_QUANTUM: %0d", TIME_QUANTUM);
        $display("====================================================\n");
        
        // Initialize
        rst_n = 0;
        task_valid = 0;
        task_id = 0;
        burst_time = 0;
        priority = 0;
        deadline = 0;
        task_complete = 0;
        
        // Reset
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        
        // Test each scheduler
        test_scheduler("FIFO", 0);
        test_scheduler("LIFO", 1);
        test_scheduler("SJF", 2);
        test_scheduler("Round Robin", 3);
        test_scheduler("Priority", 4);
        test_scheduler("EDF", 5);
        test_scheduler("LRU", 6);
        
        $display("\n====================================================");
        $display("All tests completed successfully!");
        $display("====================================================");
        $finish;
    end
    
    // Task to test a specific scheduler
    task test_scheduler(string name, int sched_type);
        automatic int local_tasks_submitted = 0;
        automatic int local_tasks_completed = 0;
        
        $display("\n*** Testing %s Scheduler ***", name);
        
        // Reset for this test
        @(posedge clk);
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        
        scheduler_type = sched_type;
        
        // Fork task submission and completion processes
        fork
            // Task submission process (random arrivals)
            begin
                for (int i = 0; i < NUM_TEST_TASKS; i++) begin
                    // Random inter-arrival time
                    repeat($urandom_range(1, 5)) @(posedge clk);
                    
                    // Wait if queue is full
                    while (queue_full) @(posedge clk);
                    
                    // Submit task
                    @(posedge clk);
                    task_valid = 1;
                    task_id = i;
                    burst_time = $urandom_range(5, 50);
                    priority = $urandom_range(0, 15);
                    deadline = $urandom_range(100, 1000);
                    
                    $display("[%0t] Submitting Task %0d: Burst=%0d, Priority=%0d, Deadline=%0d", 
                             $time, task_id, burst_time, priority, deadline);
                    
                    @(posedge clk);
                    task_valid = 0;
                    local_tasks_submitted++;
                end
            end
            
            // Task completion process
            begin
                automatic int exec_cycles = 0;
                automatic logic [BURST_TIME_WIDTH-1:0] current_burst = 0;
                
                while (local_tasks_completed < NUM_TEST_TASKS) begin
                    @(posedge clk);
                    
                    if (scheduled_task_valid) begin
                        if (exec_cycles == 0) begin
                            current_burst = scheduled_burst_time;
                            exec_cycles = current_burst;
                            $display("[%0t] Executing Task %0d (Burst time: %0d cycles)", 
                                     $time, scheduled_task_id, current_burst);
                        end
                        
                        exec_cycles--;
                        
                        if (exec_cycles == 0) begin
                            task_complete = 1;
                            $display("[%0t] Completed Task %0d", $time, scheduled_task_id);
                            local_tasks_completed++;
                            @(posedge clk);
                            task_complete = 0;
                        end
                    end
                end
            end
        join
        
        $display("\n%s Scheduler Results:", name);
        $display("  Tasks Submitted: %0d", local_tasks_submitted);
        $display("  Tasks Completed: %0d", local_tasks_completed);
        $display("  Final Queue Count: %0d", queue_count);
        
        // Wait for queue to drain
        repeat(10) @(posedge clk);
    endtask
    
    // Monitor
    initial begin
        $dumpfile("task_scheduler.vcd");
        $dumpvars(0, task_scheduler_tb);
    end
    
    // Timeout watchdog
    initial begin
        #1000000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule

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
    // The signals used to send a task into your scheduler module.
    logic task_valid;   //Indicates that the sender (testbench) has placed a valid task on the input signals.
    logic [TASK_ID_WIDTH-1:0] task_id;
    logic [BURST_TIME_WIDTH-1:0] burst_time;
    logic [PRIORITY_WIDTH-1:0] task_priority;
    logic [DEADLINE_WIDTH-1:0] deadline;
    logic task_ready;   //Indicates that the receiver (scheduler) is ready to accept a task
    
    // Scheduler output
    logic scheduled_task_valid;
    logic [TASK_ID_WIDTH-1:0] scheduled_task_id;
    logic [BURST_TIME_WIDTH-1:0] scheduled_burst_time;
    logic [PRIORITY_WIDTH-1:0] scheduled_priority;
    logic [DEADLINE_WIDTH-1:0] scheduled_deadline;
    logic task_complete;
    
    // Current state of the scheduler’s task queue
    logic [$clog2(MAX_TASKS):0] queue_count;
    logic queue_full;
    logic queue_empty;
    
    // Test variables used to track progress and control which scheduler is being tested.
    int tasks_submitted = 0;  //(not used)
    int tasks_completed = 0;
    int scheduler_type;
    
    localparam TEST_SCHEDULER_TYPE = 1; // 0:FIFO, 1:LIFO, 2:SJF, etc.
    
    // (Device Under Test) instances for different schedulers
    // This creates a FIFO scheduler hardware instance inside the testbench and connects all matching signals automatically.
    task_scheduler #(
        .MAX_TASKS(MAX_TASKS),
        .TASK_ID_WIDTH(TASK_ID_WIDTH),
        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
        .PRIORITY_WIDTH(PRIORITY_WIDTH),
        .DEADLINE_WIDTH(DEADLINE_WIDTH),
        .TIME_QUANTUM(TIME_QUANTUM),
        .SCHEDULER_TYPE(TEST_SCHEDULER_TYPE)  // FIFO
    ) dut_fifo (.*);    //(.*) - implicit port connection - Connect all signals with matching names automatically
    
//    task_scheduler #(
//        .MAX_TASKS(MAX_TASKS),
//        .TASK_ID_WIDTH(TASK_ID_WIDTH),
//        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
//        .PRIORITY_WIDTH(PRIORITY_WIDTH),
//        .DEADLINE_WIDTH(DEADLINE_WIDTH),
//        .TIME_QUANTUM(TIME_QUANTUM),
//        .SCHEDULER_TYPE(1)  // LIFO
//    ) dut_lifo (.*);
    
//    task_scheduler #(
//        .MAX_TASKS(MAX_TASKS),
//        .TASK_ID_WIDTH(TASK_ID_WIDTH),
//        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
//        .PRIORITY_WIDTH(PRIORITY_WIDTH),
//        .DEADLINE_WIDTH(DEADLINE_WIDTH),
//        .TIME_QUANTUM(TIME_QUANTUM),
//        .SCHEDULER_TYPE(2)  // SJF
//    ) dut_sjf (.*);
    
//    task_scheduler #(
//        .MAX_TASKS(MAX_TASKS),
//        .TASK_ID_WIDTH(TASK_ID_WIDTH),
//        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
//        .PRIORITY_WIDTH(PRIORITY_WIDTH),
//        .DEADLINE_WIDTH(DEADLINE_WIDTH),
//        .TIME_QUANTUM(TIME_QUANTUM),
//        .SCHEDULER_TYPE(3)  // Round Robin
//    ) dut_rr (.*);
    
//    task_scheduler #(
//        .MAX_TASKS(MAX_TASKS),
//        .TASK_ID_WIDTH(TASK_ID_WIDTH),
//        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
//        .PRIORITY_WIDTH(PRIORITY_WIDTH),
//        .DEADLINE_WIDTH(DEADLINE_WIDTH),
//        .TIME_QUANTUM(TIME_QUANTUM),
//        .SCHEDULER_TYPE(4)  // Priority
//    ) dut_priority (.*);
    
//    task_scheduler #(
//        .MAX_TASKS(MAX_TASKS),
//        .TASK_ID_WIDTH(TASK_ID_WIDTH),
//        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
//        .PRIORITY_WIDTH(PRIORITY_WIDTH),
//        .DEADLINE_WIDTH(DEADLINE_WIDTH),
//        .TIME_QUANTUM(TIME_QUANTUM),
//        .SCHEDULER_TYPE(5)  // EDF
//    ) dut_edf (.*);
    
//    task_scheduler #(
//        .MAX_TASKS(MAX_TASKS),
//        .TASK_ID_WIDTH(TASK_ID_WIDTH),
//        .BURST_TIME_WIDTH(BURST_TIME_WIDTH),
//        .PRIORITY_WIDTH(PRIORITY_WIDTH),
//        .DEADLINE_WIDTH(DEADLINE_WIDTH),
//        .TIME_QUANTUM(TIME_QUANTUM),
//        .SCHEDULER_TYPE(6)  // LRU
//    ) dut_lru (.*);
    
    // Clock generation
    initial begin    //Run this block of code once at the start of simulation.  , Executes sequentially , Does not repeat
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Main test stimulus
    // it initializes everything, resets the system, and then runs all scheduler tests one by one.
    initial begin
        $display("====================================================");
        $display("Task Scheduler Testbench");
        $display("====================================================");
        $display("MAX_TASKS: %0d", MAX_TASKS);  //%0d - print as decimal without leading zeros
        $display("TIME_QUANTUM: %0d", TIME_QUANTUM);
        $display("====================================================\n");
        
        // Initialize
        // Avoids undefined (X) states
        rst_n = 0;
        task_valid = 0;
        task_id = 0;
        burst_time = 0;
        task_priority = 0;
        deadline = 0;
        task_complete = 0;
        
        // Reset
        repeat(5) @(posedge clk);  //wait for a rising edge of the clock (this waits for 5 clock cycles)
        rst_n = 1;     //reset released
        repeat(2) @(posedge clk);  //Wait 2 additional clock cycles after reset is released
        
        test_scheduler(get_scheduler_name(TEST_SCHEDULER_TYPE), TEST_SCHEDULER_TYPE);
        
        // Test each scheduler
//        test_scheduler("FIFO", 0);
//        test_scheduler("LIFO", 1);
//        test_scheduler("SJF", 2);
//        test_scheduler("Round Robin", 3);
//        test_scheduler("Priority", 4);
//        test_scheduler("EDF", 5);
//        test_scheduler("LRU", 6);
        
        $display("\n====================================================");
        $display("All tests completed successfully!");
        $display("====================================================");
        $finish;
    end
    
    function string get_scheduler_name(int sched_type);
        case(sched_type)
            0: return "FIFO";
            1: return "LIFO";
            2: return "SJF";
            3: return "Round Robin";
            4: return "Priority";
            5: return "EDF";
            6: return "LRU";
            default: return "Unknown";
        endcase
    endfunction
    
    // Task to test a specific scheduler
    // This simulated a realistic system where (1). task arrive randomly, (2). The schedular picks tasks, (3). Tasks execute and complete
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
        
        scheduler_type = sched_type;  // unused
        
        // Fork task submission and completion processes
        fork   //Run multiple blocks of code in parallel
            // Task submission process (random arrivals)
            begin
                for (int i = 0; i < NUM_TEST_TASKS; i++) begin
                    // Random inter-arrival time
                    repeat($urandom_range(1, 5)) @(posedge clk);  //Wait 1–5 cycles randomly
                    
                    // Wait if queue is full
                    while (queue_full) @(posedge clk);
                    
                    // Submit task
                    @(posedge clk);   //Wait until the next rising edge of the clock, then apply these signals
                    task_valid = 1;
                    task_id = i;
                    burst_time = $urandom_range(5, 50);
                    task_priority = $urandom_range(0, 15);
                    deadline = $urandom_range(100, 1000);
                    
                    $display("[%0t] Submitting Task %0d: Burst=%0d, Priority=%0d, Deadline=%0d", 
                             $time, task_id, burst_time, task_priority, deadline);      //%0t - print time, %0d - print decimal without leading zeros
                    
                    @(posedge clk);  //// 2nd
                    task_valid = 0;
                    local_tasks_submitted++;
                end
            end
            
            // Task completion process
            //This behaves like a CPU that runs tasks selected by the schedule
            begin
                automatic int exec_cycles = 0;   //how many cycles left to finish current task
                automatic logic [BURST_TIME_WIDTH-1:0] current_burst = 0;   //total burst time of current task
                
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
    // tells the simulator to record signal changes so you can view them later in a waveform viewer.
    initial begin
        $dumpfile("task_scheduler.vcd");   // file where waveform data is saved
        $dumpvars(0, task_scheduler_tb);  // 0 - dump all signals in the testbench, task_scheduler_tb - the scope to dump (the entire testbench in this case)
    end
    
    // Timeout watchdog
    // Its job is to stop the simulation if something goes wrong and it runs forever.
    initial begin
        #1000000; // 1,000,000 ns
        $display("ERROR: Simulation timeout!");
        $finish;  // End the simulation
    end

endmodule


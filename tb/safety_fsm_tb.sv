// =============================================================================
// safety_fsm_tb.sv  —  self-checking testbench for safety_fsm
//   Simulate: iverilog -g2012 -o sim.out rtl/safety_fsm.sv tb/safety_fsm_tb.sv
//             vvp sim.out           (prints PASS/FAIL, writes safety_fsm.vcd)
//   Waveforms: gtkwave safety_fsm.vcd
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module safety_fsm_tb;

    logic       clk = 1'b0;
    logic       rst_n;
    logic       btn_auto, btn_estop, btn_resume;
    logic [1:0] ai_cmd;
    logic [1:0] state, motor_cmd;
    logic       emergency;

    // Mirror the DUT encodings for readable checks
    localparam S_STANDBY = 2'd0, S_AUTONOMOUS = 2'd1, S_EMERGENCY = 2'd2;
    localparam AI_GO = 2'd0, AI_SLOW = 2'd1, AI_STOP = 2'd2;
    localparam MOT_STOP = 2'd0, MOT_SLOW = 2'd1, MOT_GO = 2'd2;

    int errors = 0, checks = 0;

    safety_fsm dut (.*);

    always #5 clk = ~clk;          // 100 MHz

    task automatic step(); @(posedge clk); #1; endtask

    task automatic chk(input [1:0] exp_state, input [1:0] exp_motor, input string label);
        checks++;
        if (state !== exp_state || motor_cmd !== exp_motor) begin
            errors++;
            $display("[FAIL ] %-30s state=%0d(exp %0d) motor=%0d(exp %0d) @%0t",
                     label, state, exp_state, motor_cmd, exp_motor, $time);
        end else begin
            $display("[ pass] %-30s state=%0d motor=%0d", label, state, motor_cmd);
        end
    endtask

    initial begin
        $dumpfile("safety_fsm.vcd");
        $dumpvars(0, safety_fsm_tb);

        // --- reset ---
        btn_auto = 0; btn_estop = 0; btn_resume = 0; ai_cmd = AI_STOP;
        rst_n = 0; step(); step();
        rst_n = 1; step();
        chk(S_STANDBY, MOT_STOP, "after reset");

        // --- enter autonomous ---
        btn_auto = 1; step(); btn_auto = 0; step();
        chk(S_AUTONOMOUS, MOT_STOP, "autonomous, ai=STOP");

        // --- AI drives in autonomous ---
        ai_cmd = AI_GO;   step(); chk(S_AUTONOMOUS, MOT_GO,   "autonomous, ai=GO");
        ai_cmd = AI_SLOW; step(); chk(S_AUTONOMOUS, MOT_SLOW, "autonomous, ai=SLOW");

        // --- e-stop overrides the AI (AI says GO, e-stop says NO) ---
        ai_cmd = AI_GO; btn_estop = 1; step();
        chk(S_EMERGENCY, MOT_STOP, "e-stop overrides AI=GO");
        btn_estop = 0; step();

        // --- software/AI cannot leave EMERGENCY ---
        btn_auto = 1; ai_cmd = AI_GO; step(); btn_auto = 0; step();
        chk(S_EMERGENCY, MOT_STOP, "AI+auto cannot clear e-stop");

        // --- only the operator clears it ---
        btn_resume = 1; step(); btn_resume = 0; step();
        chk(S_STANDBY, MOT_STOP, "operator resume -> standby");

        // --- e-stop direct from standby ---
        btn_estop = 1; step();
        chk(S_EMERGENCY, MOT_STOP, "e-stop from standby");
        btn_estop = 0; btn_resume = 1; step(); btn_resume = 0; step();
        chk(S_STANDBY, MOT_STOP, "resume again -> standby");

        $display("\n==== %0d checks, %0d failure(s) ====", checks, errors);
        if (errors == 0) $display(">>> ALL TESTS PASSED <<<");
        else             $display(">>> %0d TEST(S) FAILED <<<", errors);
        $finish;
    end

endmodule

`default_nettype wire

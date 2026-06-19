// =============================================================================
// safety_fsm.sv  —  APEX safety supervisor (Standby / Autonomous / Emergency)
// -----------------------------------------------------------------------------
// Author : Efe Demir
// Origin : Hardware (RTL) re-implementation of the safety state machine I
//          designed in C firmware for APEX — an FPGA-supervised autonomous
//          vehicle with on-chip Edge-AI (SJSU EE277, Embedded SoC Design).
//
// Safety property (the whole point):
//   An emergency stop (btn_estop) PREEMPTS everything — including the AI's
//   drive command — from ANY state, forces the motors to STOP, and LATCHES.
//   Neither the AI nor the "go autonomous" button can leave EMERGENCY; only a
//   human operator (btn_resume, after releasing e-stop) can clear it.
// =============================================================================
`default_nettype none

module safety_fsm (
    input  wire        clk,
    input  wire        rst_n,       // asynchronous, active-low; resets to STANDBY

    // Operator controls. Assumed debounced + synchronized to clk upstream.
    input  wire        btn_auto,    // STANDBY  -> AUTONOMOUS
    input  wire        btn_estop,   // emergency stop (highest priority, any state)
    input  wire        btn_resume,  // operator-only clear of EMERGENCY

    // AI decision from the TinyML brain; only consulted in AUTONOMOUS.
    input  wire [1:0]  ai_cmd,      // AI_GO / AI_SLOW / AI_STOP

    // Outputs
    output logic [1:0] state,       // current mode (see encodings below)
    output logic [1:0] motor_cmd,   // MOT_STOP / MOT_SLOW / MOT_GO
    output logic       emergency    // 1 while latched in EMERGENCY
);

    // ---- State encoding ----
    localparam logic [1:0] S_STANDBY    = 2'd0;
    localparam logic [1:0] S_AUTONOMOUS = 2'd1;
    localparam logic [1:0] S_EMERGENCY  = 2'd2;

    // ---- AI command encoding ----
    localparam logic [1:0] AI_GO   = 2'd0;
    localparam logic [1:0] AI_SLOW = 2'd1;
    localparam logic [1:0] AI_STOP = 2'd2;

    // ---- Motor command encoding ----
    localparam logic [1:0] MOT_STOP = 2'd0;
    localparam logic [1:0] MOT_SLOW = 2'd1;
    localparam logic [1:0] MOT_GO   = 2'd2;

    logic [1:0] next_state;

    // ---- Next-state logic (combinational) ----
    // e-stop is evaluated FIRST so it wins from any state. This priority is the
    // hardware encoding of the safety guarantee.
    always_comb begin
        next_state = state;                       // default: hold
        if (btn_estop) begin
            next_state = S_EMERGENCY;             // priority #1: e-stop, any state
        end else begin
            unique case (state)
                S_STANDBY    : if (btn_auto)   next_state = S_AUTONOMOUS;
                S_AUTONOMOUS : if (btn_resume) next_state = S_STANDBY;     // manual stand-down
                S_EMERGENCY  : if (btn_resume) next_state = S_STANDBY;     // ONLY operator clears
                default      :                 next_state = S_STANDBY;     // illegal-state recovery
            endcase
        end
    end

    // ---- State register (async reset to safe STANDBY) ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_STANDBY;
        else        state <= next_state;
    end

    // ---- Output logic (Moore; AUTONOMOUS additionally passes the AI command) ----
    always_comb begin
        unique case (state)
            S_AUTONOMOUS : begin
                unique case (ai_cmd)
                    AI_GO   : motor_cmd = MOT_GO;
                    AI_SLOW : motor_cmd = MOT_SLOW;
                    default : motor_cmd = MOT_STOP;  // AI_STOP / unknown -> fail-safe STOP
                endcase
            end
            default      : motor_cmd = MOT_STOP;     // STANDBY & EMERGENCY -> motors off
        endcase
    end

    assign emergency = (state == S_EMERGENCY);

endmodule

`default_nettype wire

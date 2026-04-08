FUNCTION_BLOCK "FB_LUB_V_Greaser_V033"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.33
//=============================================================================
// FB_LUB_V_Greaser_V033
// Automatic lubrication function block for LUB-V greaser unit.
// Controls the LUB-V via PIN 3 (command) and reads feedback on PIN 4.
// Version: 0.33  (Fixed — bug corrections applied, see comments below)
//
// Fix 1 — Edge Counting Bug (State 30):
//   ORIGINAL: IF #i_DevicePin4 <> #prevPulseInput THEN
//             Counted BOTH rising and falling edges, doubling the count.
//   FIXED:    IF #i_DevicePin4 AND NOT #prevPulseInput THEN
//             Counts rising edges only, as required by the protocol.
//
// Fix 2 — Timeout Bug (State 20):
//   ORIGINAL: PT := t#20s
//             Shorter than the protocol-specified 30 s response window.
//   FIXED:    PT := t#30s
//             Matches the protocol guarantee of 30 s maximum response time.
//=============================================================================

VAR_INPUT
    i_Enable         : Bool;   // Enable greaser control
    i_Trigger        : Bool;   // Rising edge: start lubrication cycle
    i_Reset          : Bool;   // Rising edge: clear fault latch
    i_DeviceReady    : Bool;   // PIN 2 — LUB-V Ready output
    i_DevicePin4     : Bool;   // PIN 4 — LUB-V Feedback pulse input
END_VAR

VAR_OUTPUT
    o_DevicePin3     : Bool;   // PIN 3 — PLC Control output to LUB-V
    o_LubeOK         : Bool;   // TRUE: last cycle completed without fault
    o_Fault          : Bool;   // TRUE: fault is latched
    o_Busy           : Bool;   // TRUE: cycle is in progress
    o_FaultCode      : Int;    // Fault / response code (0 = no fault)
    o_EdgeCount      : Int;    // Diagnostic: rising edge count from last cycle
END_VAR

VAR
    state            : Int;    // Main state machine
    qState           : Int;    // Ready-qualification sub-state machine
    edgeCount        : Int;    // Accumulated feedback pulse count
    prevPulseInput   : Bool;   // Previous scan value of i_DevicePin4
    deviceQualified  : Bool;   // TRUE when Ready has been stable ≥ 600 ms
    prevTrigger      : Bool;   // For rising-edge detection on i_Trigger
    prevReset        : Bool;   // For rising-edge detection on i_Reset
    tLubeTimeout     : TON;    // Overall response timeout (State 20/30)
    tPulse           : TON;    // Control pulse width timer (State 10)
    tQualify         : TON;    // Ready qualification timer (qState)
    tFeedbackTimeout : TON;    // Silence-detection timer (State 30)
    tGap             : TON;    // Inter-command gap timer (State 50)
END_VAR

//=============================================================================
// BODY
//=============================================================================

// --- Fault latch reset (rising edge on i_Reset) ----------------------------
IF i_Reset AND NOT #prevReset THEN
    o_Fault     := FALSE;
    o_FaultCode := 0;
    o_LubeOK    := FALSE;
END_IF;
#prevReset := i_Reset;

// --- Disable guard ---------------------------------------------------------
IF NOT i_Enable THEN
    o_DevicePin3 := FALSE;
    o_Busy       := FALSE;
    state        := 0;
    qState       := 0;
    deviceQualified := FALSE;
    RETURN;
END_IF;

//=============================================================================
// Ready-Qualification State Machine (qState)
// Requires PIN 2 (i_DeviceReady) to be HIGH for > 500 ms continuously.
//=============================================================================
CASE qState OF

    0:  // Waiting — PIN 2 is not yet HIGH
        deviceQualified := FALSE;
        tQualify(IN := FALSE, PT := t#600ms); // reset timer
        IF i_DeviceReady THEN
            qState := 10;
        END_IF;

    10: // PIN 2 is HIGH — start qualification timer
        tQualify(IN := TRUE, PT := t#600ms);
        IF NOT i_DeviceReady THEN
            qState := 0;  // PIN 2 dropped before timer expired
        ELSIF tQualify.Q THEN
            deviceQualified := TRUE;
            qState := 20;
        END_IF;

    20: // Device is qualified
        deviceQualified := TRUE;
        IF NOT i_DeviceReady THEN
            deviceQualified := FALSE;
            qState := 0;
        END_IF;

END_CASE;

//=============================================================================
// Main State Machine
//=============================================================================
CASE state OF

    // -------------------------------------------------------------------------
    0:  // Idle — wait for trigger
    // -------------------------------------------------------------------------
        o_DevicePin3 := FALSE;
        o_Busy       := FALSE;
        edgeCount    := 0;

        IF i_Trigger AND NOT #prevTrigger AND deviceQualified AND NOT o_Fault THEN
            state := 10;
        END_IF;

    // -------------------------------------------------------------------------
    10: // Assert control pulse on PIN 3
    // -------------------------------------------------------------------------
        o_Busy       := TRUE;
        o_DevicePin3 := TRUE;
        tPulse(IN := TRUE, PT := t#1000ms);  // 1 000 ms trigger pulse

        IF tPulse.Q THEN
            o_DevicePin3 := FALSE;
            tPulse(IN := FALSE, PT := t#1000ms); // reset pulse timer
            state := 20;
        END_IF;

    // -------------------------------------------------------------------------
    20: // PIN 3 now LOW — start overall response timeout and await feedback
    // -------------------------------------------------------------------------
        prevPulseInput := i_DevicePin4; // initialise edge-detection reference
        edgeCount      := 0;

        "TimerReset"(#tLubeTimeout);
        "TimerStart"(timer := #tLubeTimeout,
                     PT := t#30s);       // FIX 2: was t#20s; protocol requires 30 s

        state := 30;

    // -------------------------------------------------------------------------
    30: // Counting feedback pulses from LUB-V (PIN 4)
    // -------------------------------------------------------------------------

        // Silence-detection timer — restarted on every active edge
        tFeedbackTimeout(IN := TRUE, PT := t#500ms);

        // edge detection on PIN 4 (RISING EDGES ONLY)            // FIX 1
        IF #i_DevicePin4 AND NOT #prevPulseInput THEN             // FIX 1
            #edgeCount := #edgeCount + 1;
            tFeedbackTimeout(IN := FALSE, PT := t#500ms); // restart silence timer
        END_IF;
        #prevPulseInput := #i_DevicePin4; // update every scan    // FIX 1

        // End of pulse train: 500 ms of silence after last edge
        IF tFeedbackTimeout.Q THEN
            tFeedbackTimeout(IN := FALSE, PT := t#500ms);
            o_EdgeCount := edgeCount;
            state := 40;
        END_IF;

        // Overall timeout — device failed to respond in time
        IF "TimerDone"(#tLubeTimeout) THEN
            o_Fault     := TRUE;
            o_FaultCode := 99;  // timeout
            state       := 0;
        END_IF;

    // -------------------------------------------------------------------------
    40: // Decode edge count → set status outputs
    // -------------------------------------------------------------------------
        o_LubeOK    := FALSE;
        o_Fault     := FALSE;
        o_FaultCode := 0;

        CASE edgeCount OF
            1:  // Lubrication stroke started
                o_LubeOK    := FALSE;
                o_FaultCode := 0;
            2:  // Past lubrication stroke OK — nominal result
                o_LubeOK    := TRUE;
                o_FaultCode := 0;
            3:  // Low-level warning
                o_LubeOK    := TRUE;
                o_FaultCode := 3;
            4:  // Overpressure (E2) at outlet 1
                o_Fault     := TRUE;
                o_FaultCode := 4;
            5:  // Overpressure (E2) at outlet 2
                o_Fault     := TRUE;
                o_FaultCode := 5;
            6:  // General device fault
                o_Fault     := TRUE;
                o_FaultCode := 6;
            7:  // Device not ready
                o_Fault     := TRUE;
                o_FaultCode := 7;
        ELSE
            o_Fault     := TRUE;
            o_FaultCode := 98;  // unexpected edge count
        END_CASE;

        state := 50;

    // -------------------------------------------------------------------------
    50: // Inter-command gap — wait 600 ms before returning to idle
    // -------------------------------------------------------------------------
        tGap(IN := TRUE, PT := t#600ms);

        IF tGap.Q THEN
            tGap(IN := FALSE, PT := t#600ms);
            state := 0;
        END_IF;

END_CASE;

// Latch trigger edge for next scan
#prevTrigger := i_Trigger;

END_FUNCTION_BLOCK

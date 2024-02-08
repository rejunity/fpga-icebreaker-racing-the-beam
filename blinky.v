module top (
    input  CLK,

    output LED1,
    output LED2,
    output LED3,
    output LED4,
    output LED5,

    input BTN_N,
    input BTN1,
    input BTN2,
    input BTN3
);

    localparam LEDS = 5;
    localparam LOG2DELAY = 22;

    reg [LEDS+LOG2DELAY-1:0] counter = 0;
    reg [LEDS-1:0] outs;

    always @(posedge CLK) begin
        counter <= counter + {!BTN_N, BTN1, BTN2, BTN3, 1'b0} + 1;
    end

    always @(*)
        case (counter[LOG2DELAY+2:LOG2DELAY])
            3'd0: outs = 5'b00001;
            3'd1: outs = 5'b01000;
            3'd2: outs = 5'b00010;
            3'd3: outs = 5'b00100;

            3'd4: outs = 5'b10001;
            3'd5: outs = 5'b11000;
            3'd6: outs = 5'b10010;
            3'd7: outs = 5'b10100;
        endcase

    assign {LED1, LED2, LED3, LED4, LED5} = outs;
endmodule

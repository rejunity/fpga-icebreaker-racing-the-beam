// VGA timing: https://projectf.io/posts/video-timings-vga-720p-1080p/
// PLL setup and sync: https://forum.1bitsquared.com/t/fpga4fun-pong-vga-demo/44
// DVI PMOD 12bpp pcf: https://github.com/icebreaker-fpga/icebreaker-pmod/blob/master/dvi-12bit/icebreaker.pcf or https://github.com/projf/projf-explore/blob/main/graphics/fpga-graphics/ice40/icebreaker.pcf
// DVI PMOD 4bpph pcf: https://github.com/icebreaker-fpga/icebreaker-pmod/blob/master/dvi-4bit/icebreaker.pcf

// Also see: https://projectf.io/posts/fpga-graphics/

// VGA PMOD
// Header J1       Header J2
// Pin Signal  Description Pin Signal  Description Pin Signal  Description Pin Signal  Description
// 1   R0  Red 0   7   B0  Blue 0      1   G0  Green 0 7   HS  Horizontal Sync
// 2   R1  Red 1   8   B1  Blue 1  2   G1  Green 1 8   VS  Vertical Sync
// 3   R2  Red 2   9   B2  Blue 2  3   G2  Green 2 9   NC  Not Connected
// 4   R3  Red 3   10  B3  Blue 3  4   G3  Green 3 10  NC  Not Connected

`define VGA
// `define DVI


module vga_pll(
    input  clk_in,
    output clk_out,
    output locked
);

    // iCE40 PLLs are documented in Lattice TN1251 and ICE Technology Library
    // Given input frequency:        12.000 MHz
    // Requested output frequency:   25.175 MHz
    // Achieved output frequency:    25.125 MHz

    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),         // DIVR =  0
        .DIVF(7'b1000010),      // DIVF = 66
        // .DIVF(7'b0111000),      // DIVF =  ??
        .DIVQ(3'b101),          // DIVQ =  5
        .FILTER_RANGE(3'b001)   // FILTER_RANGE = 1
    ) pll (
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .PACKAGEPIN(clk_in),
        .PLLOUTCORE(clk_out)
    );
endmodule

module vga_sync_generator(
    input clk,
    output h_sync,
    output v_sync,
    output is_display_area,
    output reg[9:0] counter_h,
    output reg[9:0] counter_v
);

    // horizontal timings
    // parameter HA_END = 639;           // end of active pixels
    // parameter HS_STA = HA_END + 16;   // sync starts after front porch
    // parameter HS_END = HS_STA + 96;   // sync ends
    // parameter LINE   = 799;           // last pixel on line (after back porch)

    // // vertical timings
    // parameter VA_END = 479;           // end of active pixels
    // parameter VS_STA = VA_END + 10;   // sync starts after front porch
    // parameter VS_END = VS_STA + 2;    // sync ends
    // parameter SCREEN = 524;           // last line on screen (after back porch)

    // assign h_sync = ~(counter_h >= 639+16 && counter_h < 639+16+96);     // invert: negative polarity
    // assign v_sync = ~(counter_v >= 479+10 && counter_v < 479+10+2);      // invert: negative polarity
    // assign is_display_area = (counter_h <= 639 && counter_v <= 479);

    always @(posedge clk) begin
        h_sync <= (counter_h >= 639+16 && counter_h < 639+16+96);     // invert: negative polarity
        v_sync <= (counter_v >= 479+10 && counter_v < 479+10+2);      // invert: negative polarity
        is_display_area <= (counter_h <= 639 && counter_v <= 479);
    end

    always @(posedge clk)
        if (counter_h == 799) begin
            counter_h <= 0;

            if (counter_v == 525)
                counter_v <= 0;
            else
                counter_v <= counter_v + 1;
        end
        else
            counter_h <= counter_h + 1;


    // wire retrace = (counter_h == 10'd799);//10'h2FF);

    // always @(posedge clk)
    //     if (retrace)
    //         counter_h <= 0;
    //     else
    //         counter_h <= counter_h + 1;

    // always @(posedge clk)
    //     if (retrace)
    //         counter_v <= counter_v + 1;

    // reg vga_HS, vga_VS;
    // always @(posedge clk)
    // begin
    //     // vga_HS <= (counter_h[9:4]==6'h2D); // change this value to move the display horizontally
    //     // vga_VS <= (counter_v==500); // change this value to move the display vertically

    //      vga_HS <= (counter_h[9:4]==0);
    //      vga_VS <= (counter_v==0);
    // end

    // reg is_display_area;
    // always @(posedge clk)
    //     if (is_display_area == 0)
    //         is_display_area <= (retrace) && (counter_v < 480);
    //     else
    //         is_display_area <= !(counter_h == 639);
        
    // assign h_sync = ~vga_HS;
    // assign v_sync = ~vga_VS;

endmodule


module top (
    input  CLK,

    input BTN_N,
    input BTN1,
    input BTN2,
    input BTN3,

    output LED1,
    output LED2,
    output LED3,
    output LED4,
    output LED5,

`ifdef VGA
    output           vga_hsync,
    output           vga_vsync,
    output wire[3:0] vga_r,
    output wire[3:0] vga_g,
    output wire[3:0] vga_b,
`elsif DVI
    output           dvi_clk,
    output           dvi_hsync,
    output           dvi_vsync,
    output           dvi_de,
    output wire[3:0] dvi_r,
    output wire[3:0] dvi_g,
    output wire[3:0] dvi_b
`else
    output wire[7:0] pmod_1a,
    output wire[7:0] pmod_1b
`endif
);
    reg [31:0] counter;
    reg flip;
    always @(posedge clk_pixel) begin
        // if (counter_v == 0 && counter_h == 0)
        counter <= counter + 1;
        if (counter == 60*800*525) begin
            flip <= ~flip;
            counter <= 0;
        end
    end

    assign LED1 = flip;
    assign LED2 = BTN1;
    assign LED3 = BTN2;
    assign LED4 = BTN3;

    reg clk_pixel;
    vga_pll pll(
        .clk_in(CLK),
        .clk_out(clk_pixel),
        .locked()
    );

    reg h_sync, v_sync, is_display_area;
    reg [9:0] counter_h;
    reg [9:0] counter_v;
    vga_sync_generator vga_sync(
        .clk(clk_pixel),
        .h_sync(h_sync),
        .v_sync(v_sync),
        .is_display_area(is_display_area),
        .counter_h(counter_h),
        .counter_v(counter_v)
    );

    wire pixel_r = is_display_area & counter_h[4];
    wire pixel_g = is_display_area & counter_h[2];
    wire pixel_b = is_display_area & counter_h[3];
    // wire [3:0] out = counter_h[5:2] * is_display_area * counter_h[0] * counter_v[3];
    // wire [11:0] pixel_rgb = (counter_h*0 + counter_v) * is_display_area;
    wire [11:0] pixel_rgb = {counter_h[7:4], counter_v[7:4], 4'h4} * is_display_area;
    // wire [11:0] pixel_rgb = {4'hF*(1-BTN1), 4'hF*BTN2, 4'hF*BTN3} * is_display_area;

`ifdef VGA
    // VGA
    assign {vga_r, vga_g, vga_b,
            vga_hsync, vga_vsync} = {pixel_rgb, h_sync, v_sync};
`elsif DVI
    // DVI/HDMI
    assign {dvi_r, dvi_g, dvi_b,
            dvi_hsync, dvi_vsync, dvi_de, dvi_clk} = {pixel_rgb, h_sync, v_sync, is_display_area, clk_pixel};
`else
`endif


endmodule

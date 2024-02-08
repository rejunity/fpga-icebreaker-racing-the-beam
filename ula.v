// https://github.com/voidberg/zx-spectrum-scr-loader
// convert binary to hexadecimal - http://tomeko.net/online_tools/file_to_hex.php?lang=en
// memory layout and attributes - http://www.breakintoprogram.co.uk/hardware/computers/zx-spectrum/screen-memory-layout
// .scr files - https://zxart.ee/eng/graphics/database/pictureType:standard/sortParameter:votes/sortOrder:desc/resultsType:zxitem/

`define VGA
// `define DVI

module vga_pll(
    input  clk_in,
    output clk_out,
    output locked
);

    // Setup VGA 640x480@60Hz pixel clock 25.175 MHz based on iceBreaker's 12MHz master clock.
    // For VGA timings see: https://projectf.io/posts/video-timings-vga-720p-1080p/
    SB_PLL40_PAD #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),         // DIVR =  0
        .DIVF(7'b1000010),      // DIVF = 66
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

// 640x480 VGA sync pulses
module vga_sync_generator(
    input clk,
    output h_sync,
    output v_sync,
    output is_display_area,
    output reg[9:0] counter_h,
    output reg[9:0] counter_v
);
    always @(posedge clk) begin
        // 640x480@60Hz with positive polarity works on all (2) TVs I tried so far ;)
        h_sync <= (counter_h >= 639+16 && counter_h < 639+16+96);     // should be negavtive polarity, but my TV doesn't support it for some reason
        v_sync <= (counter_v >= 479+10 && counter_v < 479+10+2);      // should be negavtive polarity, but my TV doesn't support it for some reason
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

    integer file, status, i, j;
    reg [7:0] screen_memory [0:6911];
    initial begin
        // for (i = 0; i < 192; i = i + 1) begin
        //     for (j = 0; j < 32; j = j + 1) begin
        //         screen_memory[i*32+j] = i[7:0];
        //     end
        // end
        // $readmemh("GlugGlug.scr.memh", screen_memory);
        // $readmemh("MAC_Athena_2016.scr.memh", screen_memory);
        // $readmemh("WonderfulDizzy_2018.scr.memh", screen_memory);
        // $readmemh("MAC_CrystalKingdomDizzy_2017.scr.memh", screen_memory);
        $readmemh("MAC_CauldronII_2016.scr.memh", screen_memory);
    end

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

    // scanline 224 T-states
    // '0' - 2 × 855 = 1710 T-states, '1' - 2 × 1710 = 3420 T-states.  (via https://sinclair.wiki.zxnet.co.uk/wiki/Spectrum_tape_interface)
    // ~11.5 scanlines per bit on average, ~90 scanlines per byte on average
    localparam CLOCKS_PER_HALF_BIT = 1 * 855; // turbo loading speed
    // localparam CLOCKS_PER_HALF_BIT = 7 * 855; // VGA 800 * 2 scanlines / 224 t-states = ~7 - for normal loading speed 


    // The following code emulates ZX Spectrum loading bars on the border 
    reg [17:0] counter;
    reg [2:0] border;
    reg [12:0] loading_addr;
    reg [2:0] loading_addr_bit;
    reg loading_bit;
    always @(posedge clk_pixel) begin
        counter <= counter + 1;

        if (BTN1)
            loading_addr <= 0;          // DEBUG: restart loading
        else if (BTN3)
            loading_addr <= 13'd6912;   // DEBUG: jumpt to completely "loaded" image
        else if (loading_addr >= 13'd6912)
            border = 3'h0;
        else if (loading_bit == 0 && counter < CLOCKS_PER_HALF_BIT  )
            border = 3'h1;
        else if (loading_bit == 0 && counter < CLOCKS_PER_HALF_BIT*2)
            border = 3'h6;
        else if (loading_bit == 1 && counter < CLOCKS_PER_HALF_BIT*3)
            border = 3'h1;
        else if (loading_bit == 1 && counter < CLOCKS_PER_HALF_BIT*4)
            border = 3'h6;
        else begin
            counter <= 0;
            {loading_addr, loading_addr_bit} <= {loading_addr, loading_addr_bit} + 1'b1;
            loading_bit <= loading_block[loading_addr_bit];
        end
    end

    // The following code setups ZX Spectrum 256x192 screen over the VGA signal:
    //  * pixels are twice the size
    //  * 128 horizontal and 96 vertical pixels for the border
    //  - 64 + 256*2 + 64 = 640
    //  - 48 + 192*2 + 48 = 480
    // TODO: implement proper 50Hz PAL support!
    wire [9:0] off_sx = counter_h - 64;
    wire [9:0] off_sy = counter_v - 48;
    wire [7:0] zx_sx  = off_sx[8:1];
    wire [7:0] zx_sy  = off_sy[8:1];
    wire is_zx_screen = (counter_h >= 64 && counter_v >= 48 && counter_h < 256*2+64 && counter_v < 192*2+48);
    wire is_zx_border = !is_zx_screen;

    wire [12:0] pixel_addr = {zx_sy[7:6], zx_sy[2:0], zx_sy[5:3], zx_sx[7:3]};
    wire [12:0] attr_addr  = {3'b110,      zx_sy[7:3],             zx_sx[7:3]}; // 6144 + { zx_sy[7:3], zx_sx[7:3]};

    wire pixel       = pixel_block[3'd7 - zx_sx[2:0]];
    wire bright      = is_zx_screen ? attr_block[6] : 1'b0;
    wire [2:0] ink   = attr_block[2:0];
    wire [2:0] paper = attr_block[5:3];

    reg [7:0] pixel_block;
    reg [7:0] attr_block;
    reg [7:0] loading_block;

    always @(negedge clk_pixel) begin
        pixel_block <= (loading_addr >= pixel_addr) ? screen_memory[pixel_addr] : 8'h00;
        attr_block  <= (loading_addr >=  attr_addr) ? screen_memory[ attr_addr] : {2'b11, 3'h0, 3'h7};
        loading_block <= screen_memory[loading_addr];
    end

    reg [2:0] color;
    always @(posedge clk_pixel)
        color = is_zx_screen ? (pixel ? ink : paper) : border;

    // ZX Secptrum color mapping to 12bpp RGB output
    wire [11:0] pixel_rgb;
    always @(*)
        case ({bright, color})
            4'h0: pixel_rgb = {4'h0, 4'h0, 4'h0};
            4'h1: pixel_rgb = {4'h0, 4'h0, 4'hD};
            4'h2: pixel_rgb = {4'hD, 4'h0, 4'h0};
            4'h3: pixel_rgb = {4'hD, 4'h0, 4'hD};

            4'h4: pixel_rgb = {4'h0, 4'hD, 4'h0};
            4'h5: pixel_rgb = {4'h0, 4'hD, 4'hD};
            4'h6: pixel_rgb = {4'hD, 4'hD, 4'h0};
            4'h7: pixel_rgb = {4'hD, 4'hD, 4'hD};

            4'h8: pixel_rgb = {4'h0, 4'h0, 4'h0};
            4'h9: pixel_rgb = {4'h0, 4'h0, 4'hF};
            4'hA: pixel_rgb = {4'hF, 4'h0, 4'h0};
            4'hB: pixel_rgb = {4'hF, 4'h0, 4'hF};

            4'hC: pixel_rgb = {4'h0, 4'hF, 4'h0};
            4'hD: pixel_rgb = {4'h0, 4'hF, 4'hF};
            4'hE: pixel_rgb = {4'hF, 4'hF, 4'h0};
            4'hF: pixel_rgb = {4'hF, 4'hF, 4'hF};
        endcase

`ifdef VGA
    // VGA
    assign {vga_r, vga_g, vga_b,
            vga_hsync, vga_vsync} = {pixel_rgb * is_display_area, h_sync, v_sync};
`elsif DVI
    // DVI/HDMI
    assign {dvi_r, dvi_g, dvi_b,
            dvi_hsync, dvi_vsync, dvi_de, dvi_clk} = {pixel_rgb * is_display_area, h_sync, v_sync, is_display_area, clk_pixel};
`else
`endif


endmodule

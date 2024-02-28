// -----------------------------------------------------------------------------
// Copyright (c) 2024 David Banks
// -----------------------------------------------------------------------------
//   ____  ____
//  /   /\/   /
// /___/  \  /
// \   \   \/
//  \   \
//  /   /         Filename  : microtan.v
// /___/   /\     Timestamp : 24/02/2024
// \   \  /  \
//  \___\/\___\
//
// Design Name: microtan
// Device: XC6SLX9


//`define USE_T65

module microtan
  (
   input         clk50,
   input         sw1, // press to reset
// input         sw2, // unused
   output [7:0]  led,
   input         ps2_clk,
   input         ps2_data,
   input         dip1,
   output [10:0] trace,
   output reg    vga_vs,
   output reg    vga_hs,
   output reg    vga_r,
   output reg    vga_g,
   output reg    vga_b,
   output [4:0]  kdi,
   output        pwm_audio
 );

   wire        cpu_clk;
   wire        clk0;
   wire [15:0] cpu_AB_next;
   reg [15:0]  cpu_AB;
   wire [7:0]  cpu_DO_next;
   reg [7:0]   cpu_DO;
   wire        cpu_WE_next;
   reg         cpu_WE;
   wire        cpu_SYNC;
	wire        reset_out;

   reg [2:0]   clken_counter = 4'b0;
   reg         cpu_clken = 1'b0;
   reg         cpu_clken1 = 1'b0;

   wire        key_int;
   reg         key_int_last;
   reg         key_int_flag = 1'b0;
   reg [4:0]   key_col = 5'b0;
   wire [6:0]  key_row;
   reg         graphics = 1'b0;
   reg [1:0]   delayed_nmi = 2'b00;

   wire        bfc1_sel = cpu_AB == 16'hBFC1;

   wire        bff0_sel = cpu_AB[15:4] == 12'hBFF && cpu_AB[1:0] == 2'b00;
   wire        bff1_sel = cpu_AB[15:4] == 12'hBFF && cpu_AB[1:0] == 2'b01;
   wire        bff2_sel = cpu_AB[15:4] == 12'hBFF && cpu_AB[1:0] == 2'b10;
   wire        bff3_sel = cpu_AB[15:4] == 12'hBFF && cpu_AB[1:0] == 2'b11;

   wire        sound_sel0 = cpu_AB == 16'hBC00;
   wire        sound_sel1 = cpu_AB == 16'hBC01;
   reg [3:0]   sound_addr_latch;
   wire [7:0]  sound_DO;
   wire [7:0]  sound_PA;
   wire [7:0]  sound_PB;
   wire [9:0]  audio;
   wire [7:0]  joystick_DO;

   // ===============================================================
   // Clock PLL: 50MHz -> 6MHz
   // ===============================================================

   // PLL to generate CPU clock of 50 * DCM_MULT / DCM_DIV MHz
   DCM
     #(
       .CLKFX_MULTIPLY   (3),
       .CLKFX_DIVIDE     (25),
       .CLKDV_DIVIDE     (2.0),
       .CLKIN_PERIOD     (20.000),
       .CLK_FEEDBACK     ("1X")
       )
   DCM1
     (
      .CLKIN            (clk50),
      .CLKFB            (clk0),
      .RST              (1'b0),
      .DSSEN            (1'b0),
      .PSINCDEC         (1'b0),
      .PSEN             (1'b0),
      .PSCLK            (1'b0),
      .CLKFX            (cpu_clk),
      .CLKFX180         (),
      .CLKDV            (vid_clk),
      .CLK2X            (),
      .CLK2X180         (),
      .CLK0             (clk0),
      .CLK90            (),
      .CLK180           (),
      .CLK270           (),
      .LOCKED           (),
      .PSDONE           (),
      .STATUS           ()
      );

   // ===============================================================
   // Reset generation
   // ===============================================================

   reg [9:0] pwr_up_reset_counter = 0; // hold reset low for ~1ms
   wire      pwr_up_reset_n = &pwr_up_reset_counter;
   reg       hard_reset_n;

   always @(posedge cpu_clk)
     begin
        if (!pwr_up_reset_n)
          pwr_up_reset_counter <= pwr_up_reset_counter + 1'b1;
        hard_reset_n <= !sw1 & pwr_up_reset_n;
     end

   wire cpu_reset = !hard_reset_n | reset_out;

   // ===============================================================
   // RAM
   // ===============================================================

   reg [8:0]   ram[0:8191];
   reg [7:0]   ram_DO;
   wire        ram_sel = !cpu_AB[15];

   initial
     $readmemh("../mem/ram.mem", ram);

   always @(posedge cpu_clk)
     if (cpu_clken1) begin
        if (cpu_WE && ram_sel)
          ram[cpu_AB[12:0]] <= { cpu_AB[9] & graphics, cpu_DO};
        ram_DO <= ram[cpu_AB[12:0]][7:0];
     end

   // ===============================================================
   // ROM
   // ===============================================================

   reg [7:0]   rom[0:16383];
   wire        rom_sel   = (cpu_AB[15:14] == 2'b11);
   reg [7:0]   rom_DO;

   initial
     $readmemh("../mem/rom.mem", rom);

   always @(posedge cpu_clk)
     if (cpu_clken1) begin
        rom_DO <= rom[cpu_AB[13:0]];
     end

   // ===============================================================
   // Character ROM
   // ===============================================================

   reg [7:0]   char_rom[0:2047];

   initial
     $readmemh("../mem/char_rom.mem", char_rom);

   // ===============================================================
   // I/O
   // ===============================================================

   reg         keycol4_last = 1'b1;

   always @(posedge cpu_clk) begin
     if (cpu_clken1) begin
        key_int_last <= key_int;
        if (key_int && !key_int_last)
          key_int_flag <= 1'b1;
        if (cpu_WE) begin
           if (bff0_sel)
             key_int_flag <= 1'b0;
           if (bff1_sel)
             delayed_nmi <= 2'b11;
           if (bff2_sel)
             key_col <= cpu_DO[4:0];
           if (bff3_sel)
             graphics <= 1'b0;
        end else begin
           if (bff0_sel)
             graphics <= 1'b1;
        end // else: !if(cpu_WE)
        if ((delayed_nmi > 2'b00) && cpu_SYNC)
          delayed_nmi <= delayed_nmi - 1'b1;
     end
   end

   keypad keypad
     (
      .clk(cpu_clk),
      .reset(cpu_reset),
      .ps2_clk(ps2_clk),
      .ps2_data(ps2_data),
      .keypad_mode(dip1),
      .col(key_col),
      .row(key_row),
      .key_int(key_int),
		.reset_out(reset_out),
      .joystick(joystick_DO)
      );

   // ===============================================================
   // sound
   // ===============================================================

   always @(posedge cpu_clk)
     if (cpu_clken)
       if (cpu_reset)
         sound_addr_latch <= 4'b0000;
       else if (sound_sel0 && cpu_WE && cpu_DO[7:4] == 4'b0000)
         sound_addr_latch <= cpu_DO[3:0];

   jt49 jt49
     (
      .rst_n(!cpu_reset),
      .clk(cpu_clk),
      .clk_en(cpu_clken),
      .addr(sound_addr_latch),
      .cs_n(!sound_sel1),
      .wr_n(!cpu_WE),
      .din(cpu_DO),
      .sel(1'b1), // if sel is low, the clock is divided by 2
      .dout(sound_DO),
      .sound(audio), // combined channel output
      .A(), // linearised channel output
      .B(),
      .C(),
      .sample(),

      .IOA_in(8'h55),
      .IOA_out(sound_PA),
      .IOA_oe(),

      .IOB_in(8'hAA),
      .IOB_out(sound_PB),
      .IOB_oe()
      );

   pwm_dac #(.WIDTH(10)) pwm_dac
     (
      .clk_i(clk50),
      .reset_i(cpu_reset),
      .dac_i(audio),
      .dac_o(pwm_audio)
    );

   // ===============================================================
   // video
   // ===============================================================

   // 640 x 480
   // 800 x 525

   reg [9:0] h_counter = 10'b0;
   reg [3:0] h_counter1 = 4'b0;
   reg [9:0] v_counter = 10'b0;
   reg       h_sync = 1'b0;
   reg       v_sync = 1'b0;

   reg [8:0] video_addr = 9'b0;
   reg [8:0] video_byte;
   reg       video_bit;
   reg       video_out;
   reg [4:0] line_counter;
	reg       gr1;

   always @(posedge vid_clk) begin

      if (h_counter == 799) begin
         h_counter <= 10'b0;
         if (v_counter == 524) begin
            v_counter <= 10'b0;
         end else begin
            v_counter <= v_counter + 1'b1;
         end
      end else begin
         h_counter <= h_counter + 1'b1;
      end

      if (h_counter == 640 + 16) begin
         h_sync <= 1'b1;
      end else if (h_counter == 640 + 16 + 96) begin
         h_sync <= 1'b0;
      end

      if (v_counter == 480 + 10) begin
         v_sync <= 1'b1;
      end else if (v_counter == 480 + 10 + 2) begin
         v_sync <= 1'b0;
      end

      // 32 * 16 = 512 => 64 + 512 + 64 => 640
      // 16 * 28 = 448 => 16 + 448 + 16 => 480
      if (h_counter == 63) begin
         video_addr[4:0] <= 5'b0;
      end else if (h_counter[3:0] == 4'b1111) begin
         video_addr[4:0] <= video_addr[4:0] + 1'b1;
      end

      if (h_counter == 0) begin
         if (v_counter == 16) begin
            line_counter <= 5'b0;
            video_addr[8:5] <= 5'b0;
         end else if (line_counter == 27) begin
            line_counter <= 5'b0;
            video_addr[8:5] <= video_addr[8:5] + 1'b1;
         end else begin
            line_counter <= line_counter + 1'b1;
         end
      end

      video_byte <= ram[{4'b0001, video_addr}];

      h_counter1 <= h_counter[3:0];

      if (video_byte[8]) begin
         // Chunky graphics Mode
         // 0 1 lines 0-6
         // 2 3 lines 7-13
         // 4 5 lines 14-20
         // 6 7 lines 21-27
         if (line_counter < 7)
           video_bit <= h_counter1[3] ? video_byte[1] : video_byte[0];
         else if (line_counter < 14)
           video_bit <= h_counter1[3] ? video_byte[3] : video_byte[2];
         else if (line_counter < 21)
           video_bit <= h_counter1[3] ? video_byte[5] : video_byte[4];
         else
           video_bit <= h_counter1[3] ? video_byte[7] : video_byte[6];
      end else begin
         // Text Mode
         video_bit <= char_rom[{video_byte[6:0], line_counter[4:1]}][h_counter1[3:1] ^ 3'b111];
      end // else: !if(video_byte[8])
      vga_hs <= !h_sync;
      vga_vs <= !v_sync;
      if (v_counter >= 16 && v_counter < 16 + 448 && h_counter >= 64 + 2 && h_counter < 64 + 512 + 2) begin
        vga_r <= video_bit;
        vga_g <= video_bit;
        vga_b <= video_bit;
      end else begin
        vga_r <= 1'b0;
        vga_g <= 1'b0;
        vga_b <= 1'b0;
      end
   end

   // ===============================================================
   // CPU
   // ===============================================================

   wire [7:0]  cpu_DI = ram_sel ? ram_DO :
               rom_sel ? rom_DO :
               bff3_sel ? {key_int_flag, key_row} :
					sound_sel1 ? sound_DO :
               bfc1_sel ? joystick_DO :
               8'hFF;

   wire        cpu_IRQ = key_int_flag;
   wire        cpu_NMI = (delayed_nmi == 2'b01);

`ifdef USE_T65

   T65 cpu
     (
      .mode    ( 2'b00),
      .Abort_n ( 1'b1),
      .SO_n    ( 1'b1),
      .Res_n   ( !cpu_reset),
      .Enable  ( cpu_clken),
      .Clk     ( cpu_clk),
      .Rdy     ( 1'b1),
      .IRQ_n   ( !cpu_IRQ),
      .NMI_n   ( !cpu_NMI),
      .R_W_n   ( cpu_RnW),
      .Sync    ( cpu_SYNC),
      .A       ( cpu_AB),
      .DI      ( cpu_DI),
      .DO      ( cpu_DO),
      .Regs    ( )
      );

   always @(cpu_RnW)
       cpu_WE = !cpu_RnW;

`else
   // Arlet's 65C02 Core
   cpu_65c02 cpu
     (
      .clk(cpu_clk),
      .reset(cpu_reset),
      .AB(cpu_AB_next),
      .DI(cpu_DI),
      .DO(cpu_DO_next),
      .WE(cpu_WE_next),
      .IRQ(cpu_IRQ),
      .NMI(cpu_NMI),
      .RDY(cpu_clken),
      .SYNC(cpu_SYNC)
      );

   always @(posedge cpu_clk) begin
      if (cpu_clken) begin
         cpu_AB <= cpu_AB_next;
         cpu_WE <= cpu_WE_next;
         cpu_DO <= cpu_DO_next;
      end
   end
`endif

   reg         trace_phi2;
   reg         trace_rnw;
   reg         trace_sync;
   reg [7:0]   trace_data;

   always @(posedge cpu_clk) begin
      if (clken_counter == 3'b111)
        cpu_clken <= 1'b1;
      else
        cpu_clken <= 1'b0;
      clken_counter <= clken_counter + 1'b1;
      cpu_clken1 <= cpu_clken;
      if (cpu_clken) begin
         trace_phi2 <= 1'b1;
         trace_sync <= cpu_SYNC;
         if (cpu_WE) begin
            trace_rnw <= 1'b0;
            trace_data <= cpu_DO;
         end else begin
            trace_rnw <= 1'b1;
            trace_data <= cpu_DI;
         end
      end else if (clken_counter == 4) begin
         trace_phi2 <= 1'b0;
      end
   end

   assign trace = {trace_phi2, trace_sync, trace_rnw, trace_data};

//   assign led = {key_row[3:0], key_col[3:0]};
//   assign led = sound_PA;
   assign led = {key_int_flag, key_row};

   assign kdi = {key_col};

endmodule

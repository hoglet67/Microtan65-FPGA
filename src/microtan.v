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
   output        vga_r,
   output        vga_g,
   output        vga_b,
   output        vga_vs,
   output        vga_hs,
   output        composite_sync,
   output        composite_video,
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
      .CLKDV            (vga_clk),
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

   reg [7:0]   ram[0:8191];
   reg [7:0]   ram_DO;
   wire        ram_sel = !cpu_AB[15];

   initial
     $readmemh("../mem/ram.mem", ram);

   always @(posedge cpu_clk)
     if (cpu_clken1) begin
        if (cpu_WE && ram_sel)
          ram[cpu_AB[12:0]] <= cpu_DO;
        ram_DO <= ram[cpu_AB[12:0]];
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
   // VGA Video
   // ===============================================================

   // 800 x 525 with a 640x480 active region and 512x488 centred within that

   lores_video
     #(
       .H_TOTAL         (800),
       .V_TOTAL         (525),
       .H_ACTIVE        (640),
       .V_ACTIVE        (480),
       .H_BORDER         (64),
       .V_BORDER         (16),
       .H_FRONT_PORCH    (16),
       .H_SYNC_WIDTH     (96),
       .V_FRONT_PORCH    (10),
       .V_SYNC_WIDTH      (2),
       .V_LINES_PER_CHAR (28),
       .H_SCALE           (1),
       .V_SCALE           (1)
       )
   vga_video
     (
      .cpu_clk(cpu_clk),
      .cpu_clken(cpu_clken && cpu_AB[15:9] == 7'b0000001),
      .cpu_data({ graphics, cpu_DO}),
      .cpu_addr(cpu_AB[8:0]),
      .cpu_we(cpu_WE),
      .vid_clk(vga_clk),
      .vid_r(vga_r),
      .vid_g(vga_g),
      .vid_b(vga_b),
      .vid_vs(vga_vs),
      .vid_hs(vga_hs),
      .vid_cs()
    );

   // ===============================================================
   // Composite Video
   // ===============================================================

   // 384 x 312 with a 320x288 active region and 256x256 centred within that

   lores_video
     #(
       .H_TOTAL         (384),
       .V_TOTAL         (312),
       .H_ACTIVE        (320),
       .V_ACTIVE        (288),
       .H_BORDER         (32),
       .V_BORDER         (16),
       .H_FRONT_PORCH    (10),
       .H_SYNC_WIDTH     (28),
       .V_FRONT_PORCH     (4),
       .V_SYNC_WIDTH      (2),
       .V_LINES_PER_CHAR (16),
       .H_SCALE           (0),
       .V_SCALE           (0)
       )
   comp_video
     (
      .cpu_clk(cpu_clk),
      .cpu_clken(cpu_clken && cpu_AB[15:9] == 7'b0000001),
      .cpu_data({ graphics, cpu_DO}),
      .cpu_addr(cpu_AB[8:0]),
      .cpu_we(cpu_WE),
      .vid_clk(cpu_clk),
      .vid_r(),
      .vid_g(composite_video),
      .vid_b(),
      .vid_vs(),
      .vid_hs(),
      .vid_cs(composite_sync)
    );

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

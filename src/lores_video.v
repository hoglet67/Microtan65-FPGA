module lores_video
  #(
    parameter H_TOTAL          = 0,
    parameter V_TOTAL          = 0,
    parameter H_ACTIVE         = 0,
    parameter V_ACTIVE         = 0,
    parameter H_BORDER         = 0,
    parameter V_BORDER         = 0,
    parameter H_FRONT_PORCH    = 0,
    parameter H_SYNC_WIDTH     = 0,
    parameter V_FRONT_PORCH    = 0,
    parameter V_SYNC_WIDTH     = 0,
    parameter V_LINES_PER_CHAR = 0,
    parameter H_SCALE          = 0,
    parameter V_SCALE          = 0
    )
   (
    input       cpu_clk,
    input       cpu_clken,
    input [8:0] cpu_data,
    input [8:0] cpu_addr,
    input       cpu_we,
    input       vid_clk,
    output reg  vid_r,
    output reg  vid_g,
    output reg  vid_b,
    output reg  vid_vs,
    output reg  vid_hs,
    output reg  vid_cs
    );

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

   // ===============================================================
   // Video ROM
   // ===============================================================

   reg [8:0] ram[0:511];

   initial
     $readmemh("../mem/vid_ram.mem", char_rom);

   // ===============================================================
   // Character ROM
   // ===============================================================

   reg [7:0]   char_rom[0:2047];

   initial
     $readmemh("../mem/char_rom.mem", char_rom);

   // ===============================================================
   // CPU side
   // ===============================================================

   always @(posedge cpu_clk)
     if (cpu_clken)
       if (cpu_we)
         ram[cpu_addr] <= cpu_data;

   // ===============================================================
   // Video side
   // ===============================================================

   always @(posedge vid_clk) begin

      if (h_counter == H_TOTAL - 1) begin
         h_counter <= 10'b0;
         if (v_counter == V_TOTAL - 1) begin
            v_counter <= 10'b0;
         end else begin
            v_counter <= v_counter + 1'b1;
         end
      end else begin
         h_counter <= h_counter + 1'b1;
      end

      if (h_counter == H_ACTIVE + H_FRONT_PORCH) begin
         h_sync <= 1'b1;
      end else if (h_counter == H_ACTIVE + H_FRONT_PORCH + H_SYNC_WIDTH) begin
         h_sync <= 1'b0;
      end

      if (v_counter == V_ACTIVE + V_FRONT_PORCH) begin
         v_sync <= 1'b1;
      end else if (v_counter == V_ACTIVE + V_FRONT_PORCH + V_SYNC_WIDTH) begin
         v_sync <= 1'b0;
      end

      if (h_counter == H_BORDER - 1) begin
         video_addr[4:0] <= 5'b0;
      end else if (&h_counter[2 + H_SCALE:0]) begin
         video_addr[4:0] <= video_addr[4:0] + 1'b1;
      end

      if (h_counter == 0) begin
         if (v_counter == V_BORDER) begin
            line_counter <= 5'b0;
            video_addr[8:5] <= 5'b0;
         end else if (line_counter == V_LINES_PER_CHAR - 1) begin
            line_counter <= 5'b0;
            video_addr[8:5] <= video_addr[8:5] + 1'b1;
         end else begin
            line_counter <= line_counter + 1'b1;
         end
      end

      video_byte <= ram[video_addr];

      h_counter1 <= h_counter[3:0];

      if (video_byte[8]) begin
         // Chunky graphics Mode
         if (line_counter < V_LINES_PER_CHAR * 1 / 4)
           video_bit <= h_counter1[H_SCALE + 2] ? video_byte[1] : video_byte[0];
         else if (line_counter < V_LINES_PER_CHAR * 2 / 4)
           video_bit <= h_counter1[H_SCALE + 2] ? video_byte[3] : video_byte[2];
         else if (line_counter < V_LINES_PER_CHAR * 3 / 4)
           video_bit <= h_counter1[H_SCALE + 2] ? video_byte[5] : video_byte[4];
         else
           video_bit <= h_counter1[H_SCALE + 2] ? video_byte[7] : video_byte[6];
      end else begin
         // Text Mode
         video_bit <= char_rom[{video_byte[6:0], line_counter[V_SCALE + 3 : V_SCALE]}][h_counter1[H_SCALE + 2 : H_SCALE] ^ 3'b111];
      end
      if (v_counter >= V_BORDER && v_counter < V_ACTIVE - V_BORDER  && h_counter >= H_BORDER + 2 && h_counter < H_ACTIVE - H_BORDER + 2) begin
        vid_r <= video_bit;
        vid_g <= video_bit;
        vid_b <= video_bit;
      end else begin
        vid_r <= 1'b0;
        vid_g <= 1'b0;
        vid_b <= 1'b0;
      end
      vid_hs <= !h_sync;
      vid_vs <= !v_sync;
      vid_cs <= !(h_sync ^ v_sync);
   end

endmodule

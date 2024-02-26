`timescale 1ns / 1ns

module digiac_tb();


   reg clk50 = 0;
   wire [7:0] leds;
   wire       uart_tx;
   wire [10:0] trace;

   always #(10)
     clk50 <= ~clk50;

   digiac digiac
     (
      .clk50(clk50),
      .sw1(1'b0),
      .sw2(1'b0),
      .led(leds),
      .ps2_clk(1'b1),
      .ps2_data(1'b1),
      .uart_rx(1'b1),
      .uart_tx(uart_tx),
      .trace(trace)
      );

   initial begin
      $dumpvars();
      #100
      digiac.ram['h268] = 8'h34;
      digiac.ram['h269] = 8'h12;
      #10000000
      $finish();
   end

   wire trace_phi2 = trace[10];

//   always @(negedge trace_phi2)
//      $display("%04h", {6'b111111, trace[9:0]});

endmodule // digiac_tb

module pwm_dac
  #(
    parameter WIDTH = 0
    )
   (
    input               clk_i,
    input               reset_i, // not currently used
    input [WIDTH - 1:0] dac_i,
    output reg          dac_o
    );

   reg [WIDTH + 1:0] sum;

   always @(posedge clk_i) begin
      sum <= sum + { sum[WIDTH + 1], sum[WIDTH + 1], dac_i };
      dac_o <= sum[WIDTH + 1];
   end
endmodule

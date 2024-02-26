`timescale 1 ns / 1 ns

//  Digiac keypad implementation with interface to PS/2
//
//  Copyright (c) 2024 David Banks
//
//  All rights reserved
//
//  Redistribution and use in source and synthezised forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
//  * Redistributions in synthesized form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
//  * Neither the name of the author nor the names of other contributors may
//    be used to endorse or promote products derived from this software without
//    specific prior written agreement from the author.
//
//  * License is granted for non-commercial use only.  A fee may not be charged
//    for redistributions as source code or in synthesized/hardware form without
//    specific prior written agreement from the author.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
//  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//

module keypad
  (
   input        clk,
   input        reset,
   input        ps2_clk,
   input        ps2_data,
   input [4:0]  col,
   output [7:0] row,
   output       reset_out
   );

   //  Interface to PS/2 block
   wire [7:0]   keyb_data;
   wire         keyb_valid;
   wire         keyb_error;

   //  Internal signals
   reg [19:0]   keys;
   reg          _release_;
   reg          extended;

   ps2_intf PS2
     (
      .CLK       ( clk        ),
      .RESET     ( reset       ),
      .PS2_CLK   ( ps2_clk      ),
      .PS2_DATA  ( ps2_data     ),
      .DATA      ( keyb_data    ),
      .VALID     ( keyb_valid   )
      );

   //  Decode PS/2 data

   always @(posedge clk) begin

      if (reset) begin

         _release_ <= 1'b 0;
         extended <= 1'b 0;
         keys <= 20'h000000;

      end else  begin

         if (keyb_valid === 1'b 1) begin

            //  Decode keyboard input
            if (keyb_data === 8'h e0) begin

               //  Extended key code follows
               extended <= 1'b 1;

            end else if (keyb_data === 8'h f0 ) begin

               //  Release code follows
               _release_ <= 1'b 1;

               //  Cancel extended/release flags for next time

            end else if (extended === 1'b1) begin // Extended keys.

               _release_ <= 1'b 0;
               extended <= 1'b 0;

            end else begin

               _release_ <= 1'b 0;
               extended <= 1'b 0;

               //  Decode scan codes
               case (keyb_data)

                 // Matrix:
                 //           Col
                 //         0   1   2   3
                 //         -------
                 // Rom 4 | Shf LF  CR  Res
                 //     3 | C   D   E   F
                 //     2 | 8   9   A   B
                 //     1 | 4   5   6   7
                 //     0 | 0   1   2   3
                 //

                 8'h 45: keys[ 0] <= ~_release_;    //  0
                 8'h 16: keys[ 1] <= ~_release_;    //  1
                 8'h 1E: keys[ 2] <= ~_release_;    //  2
                 8'h 26: keys[ 3] <= ~_release_;    //  3
                 8'h 25: keys[ 4] <= ~_release_;    //  4
                 8'h 2E: keys[ 5] <= ~_release_;    //  5
                 8'h 36: keys[ 6] <= ~_release_;    //  6
                 8'h 3D: keys[ 7] <= ~_release_;    //  7
                 8'h 3E: keys[ 8] <= ~_release_;    //  8
                 8'h 46: keys[ 9] <= ~_release_;    //  9
                 8'h 1C: keys[10] <= ~_release_;    //  A
                 8'h 32: keys[11] <= ~_release_;    //  B
                 8'h 21: keys[12] <= ~_release_;    //  C
                 8'h 23: keys[13] <= ~_release_;    //  D
                 8'h 24: keys[14] <= ~_release_;    //  E
                 8'h 2B: keys[15] <= ~_release_;    //  F
//                 8'h 12: keys[16] <= ~_release_;    //  Shift (Left Shift)
//                 8'h 59: keys[16] <= ~_release_;    //  Shift (Right Shift)
//                 8'h 72: keys[17] <= ~_release_;    //  LF (Down Arrow)
//                 8'h 5A: keys[18] <= ~_release_;    //  CR (Return)
                 8'h 07: keys[19] <= ~_release_;    //  Reset (F12)

               endcase
            end
         end
      end
   end

   assign row = { 3'b000,
                  (col[0] ? 5'b00000 : {keys[16], keys[12], keys[ 8], keys[ 4], keys [0]}) |
                  (col[1] ? 5'b00000 : {keys[17], keys[13], keys[ 9], keys[ 5], keys [1]}) |
                  (col[2] ? 5'b00000 : {keys[18], keys[14], keys[10], keys[ 6], keys [2]}) |
                  (col[3] ? 5'b00000 : {    1'b0, keys[15], keys[11], keys[ 7], keys [3]})};

   assign reset_out = keys[19];

endmodule

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
   input        keypad_mode,
   input [4:0]  col,
   output [6:0] row,
   output       key_int,
   output       reset_out,
   output [7:0] joystick
   );

   //  Interface to PS/2 block
   wire [7:0]   keyb_data;
   wire         keyb_valid;
   wire         keyb_error;

   //  Internal signals
   reg [19:0]   keys;
   reg          _release_;
   reg          extended;
   reg [6:0]    ascii;

   reg          shift;
   reg          ctrl;
   reg          lock;
   reg          shifted;
   reg          strobe;

   reg          js_left;
   reg          js_right;
   reg          js_up;
   reg          js_down;
   reg          js_btn1;
   reg          js_btn2;

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

         _release_ <= 1'b0;
         extended <= 1'b0;
         keys <= 20'h000000;
         shift <= 1'b0;
         ctrl <= 1'b0;
         shifted <= 1'b0;
         lock <= 1'b0;
			strobe <= 1'b0;
			js_left <= 1'b1;
			js_right <= 1'b1;
			js_up <= 1'b1;
			js_down <= 1'b1;
			js_btn1 <= 1'b1;
			js_btn2 <= 1'b1;

      end else  begin

         shifted <= shift ^ lock;

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

               case (keyb_data)
                 8'h6B: js_left  <= _release_;  // LEFT
                 8'h72: js_down  <= _release_;  // DOWN
                 8'h74: js_right <= _release_;  // RIGHT
                 8'h75: js_up    <= _release_;  // UP
                 8'h14: js_btn2  <= _release_;  // RIGHT CTRL
               endcase

            end else begin

               _release_ <= 1'b 0;
               extended <= 1'b 0;

               case (keyb_data)
                 8'h12: js_btn1  <= _release_;  //  Left SHIFT
                 8'h59: js_btn1  <= _release_;  //  Right SHIFT
                 8'h14: js_btn2  <= _release_;  //  LEFT CTRL
               endcase

               //  Decode scan codes

               if (keypad_mode) begin

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
                    8'h 12: keys[16] <= ~_release_;    //  Shift (Left Shift)
                    8'h 59: keys[16] <= ~_release_;    //  Shift (Right Shift)
                    8'h 72: keys[17] <= ~_release_;    //  LF (Down Arrow)
                    8'h 5A: keys[18] <= ~_release_;    //  CR (Return)
                    8'h 07: keys[19] <= ~_release_;    //  Reset (F12)

                  endcase // case (keyb_data)

               end else begin

                  // Modifiers (these don't send ASCII codes)
                  case (keyb_data)
                    8'h 12: shift <= ~_release_;                 //  Left SHIFT
                    8'h 59: shift <= ~_release_;                 //  Right SHIFT
                    8'h 14: ctrl  <= ~_release_;                 //  LEFT/RIGHT CTRL (CTRL)
                    8'h 58: if (~_release_) lock <= ~lock;      //  CAPS LOCK
                  endcase

                  // Keys (these do sent ASCII codes)
                  if (_release_) begin

                    strobe <= 1'b0;

                  end else begin

                    strobe <= 1'b1;

                    case (keyb_data)
                      8'h 5A: ascii <= 7'h0D;                      //  RETURN
                      8'h 76: ascii <= 7'h1B;                      //  ESCAPE
                      8'h 29: ascii <= 7'h20;                      //  SPACE
                      8'h 45: ascii <= 7'h30;                      //  0
                      8'h 16: ascii <= shifted ? 7'h21 : 7'h31;    //  1 !
                      8'h 1E: ascii <= shifted ? 7'h22 : 7'h32;    //  2 "
                      8'h 26: ascii <= shifted ? 7'h23 : 7'h33;    //  3 #
                      8'h 25: ascii <= shifted ? 7'h24 : 7'h34;    //  4 $
                      8'h 2E: ascii <= shifted ? 7'h25 : 7'h35;    //  5 %
                      8'h 36: ascii <= shifted ? 7'h26 : 7'h36;    //  6 &
                      8'h 3D: ascii <= shifted ? 7'h27 : 7'h37;    //  7 '
                      8'h 3E: ascii <= shifted ? 7'h28 : 7'h38;    //  8 (
                      8'h 46: ascii <= shifted ? 7'h29 : 7'h39;    //  9 )
                      8'h 4C: ascii <= shifted ? 7'h2A : 7'h3A;    //  : *
                      8'h 4E: ascii <= shifted ? 7'h2B : 7'h3B;    //  ; +
                      8'h 41: ascii <= shifted ? 7'h3C : 7'h2C;    //  , <
                      8'h 55: ascii <= shifted ? 7'h3D : 7'h2D;    //  - =
                      8'h 49: ascii <= shifted ? 7'h3E : 7'h2E;    //  . >
                      8'h 4A: ascii <= shifted ? 7'h3F : 7'h2F;    //  / ?
                      8'h 52: ascii <= 7'h60;                      //  '
                      8'h 0E: ascii <= 7'h40;                      //  @
                      8'h 1C: ascii <= ctrl ? 7'h01 : shifted ? 7'h61 : 7'h41;    //  A a
                      8'h 32: ascii <= ctrl ? 7'h02 : shifted ? 7'h62 : 7'h42;    //  B b
                      8'h 21: ascii <= ctrl ? 7'h03 : shifted ? 7'h63 : 7'h43;    //  C c
                      8'h 23: ascii <= ctrl ? 7'h04 : shifted ? 7'h64 : 7'h44;    //  D d
                      8'h 24: ascii <= ctrl ? 7'h05 : shifted ? 7'h65 : 7'h45;    //  E e
                      8'h 2B: ascii <= ctrl ? 7'h06 : shifted ? 7'h66 : 7'h46;    //  F f
                      8'h 34: ascii <= ctrl ? 7'h07 : shifted ? 7'h67 : 7'h47;    //  G g
                      8'h 33: ascii <= ctrl ? 7'h08 : shifted ? 7'h68 : 7'h48;    //  H h
                      8'h 43: ascii <= ctrl ? 7'h09 : shifted ? 7'h69 : 7'h49;    //  I i
                      8'h 3B: ascii <= ctrl ? 7'h0A : shifted ? 7'h6A : 7'h4A;    //  J j
                      8'h 42: ascii <= ctrl ? 7'h0B : shifted ? 7'h6B : 7'h4B;    //  K k
                      8'h 4B: ascii <= ctrl ? 7'h0C : shifted ? 7'h6C : 7'h4C;    //  L l
                      8'h 3A: ascii <= ctrl ? 7'h0D : shifted ? 7'h6D : 7'h4D;    //  M m
                      8'h 31: ascii <= ctrl ? 7'h0E : shifted ? 7'h6E : 7'h4E;    //  N n
                      8'h 44: ascii <= ctrl ? 7'h0F : shifted ? 7'h6F : 7'h4F;    //  O o
                      8'h 4D: ascii <= ctrl ? 7'h10 : shifted ? 7'h70 : 7'h50;    //  P p
                      8'h 15: ascii <= ctrl ? 7'h11 : shifted ? 7'h71 : 7'h51;    //  Q q
                      8'h 2D: ascii <= ctrl ? 7'h12 : shifted ? 7'h72 : 7'h52;    //  R r
                      8'h 1B: ascii <= ctrl ? 7'h13 : shifted ? 7'h73 : 7'h53;    //  S s
                      8'h 2C: ascii <= ctrl ? 7'h14 : shifted ? 7'h74 : 7'h54;    //  T t
                      8'h 3C: ascii <= ctrl ? 7'h15 : shifted ? 7'h75 : 7'h55;    //  U u
                      8'h 2A: ascii <= ctrl ? 7'h16 : shifted ? 7'h76 : 7'h56;    //  V v
                      8'h 1D: ascii <= ctrl ? 7'h17 : shifted ? 7'h77 : 7'h57;    //  W w
                      8'h 22: ascii <= ctrl ? 7'h18 : shifted ? 7'h78 : 7'h58;    //  X x
                      8'h 35: ascii <= ctrl ? 7'h19 : shifted ? 7'h79 : 7'h59;    //  Y y
                      8'h 1A: ascii <= ctrl ? 7'h1A : shifted ? 7'h7A : 7'h5A;    //  Z z
                      8'h 54: ascii <= ctrl ? 7'h1B : shifted ? 7'h7B : 7'h5B;    //  [ {
                      8'h 61: ascii <= ctrl ? 7'h1C : shifted ? 7'h7C : 7'h5C;    //  \ |
                      8'h 5B: ascii <= ctrl ? 7'h1E : shifted ? 7'h7D : 7'h5D;    //  ] }
                      8'h 0E: ascii <= ctrl ? 7'h1E : shifted ? 7'h7E : 7'h5E;    //  ~ ^
                      8'h 66: ascii <= ctrl ? 7'h1F : 7'h7F;                      //  BACKSPACE (DELETE)
                      //8'h 0D: ascii <= shifted ? 7'h60 : 7'h40;    //  TAB
                      //8'h 5D: ascii <= shifted ? 7'h60 : 7'h40;    //  # (_)
                      default : strobe <= 1'b0;
                    endcase
                  end
               end
            end
         end
      end
   end // always @ (posedge clk)

   assign key_int = keypad_mode ? col[4] : strobe;

   assign row = keypad_mode ?
                { 2'b00,
                  (col[0] ? {keys[16], keys[12], keys[ 8], keys[ 4], keys [0]} : 5'b00000) |
                  (col[1] ? {keys[17], keys[13], keys[ 9], keys[ 5], keys [1]} : 5'b00000) |
                  (col[2] ? {keys[18], keys[14], keys[10], keys[ 6], keys [2]} : 5'b00000) |
                  (col[3] ? {    1'b0, keys[15], keys[11], keys[ 7], keys [3]} : 5'b00000)} :

                ascii;

   assign reset_out = keys[19];

   // Standard Joystick Connections connected to Tanex Port A
   assign joystick = { js_down, js_right, js_up, js_left, js_btn2, js_btn1, 2'b11 };

   // Space Invasion Hardware (??)  connected to Tanex Port A
   // assign joystick = { 2'b00, !js_btn2, !js_up, !js_down, !js_right, !js_btn1, !js_left};

endmodule

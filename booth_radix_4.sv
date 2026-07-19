// ============================================================
// FULL modified Booth radix-4 signed 8x8 multiplier -- BASELINE
// Same back end as the full B4G3 design, so the ONLY differences are:
//   - the encoder: 3-bit overlapping window {b_next,b_curr,b_prev}
//     with the full menu {0,+A,+2A,-A,-2A}  (B4G3 trims -2A)
//   - NO carry / prefix network (B4G3 needs one to compensate)
//   - all four units identical (the top window holds B[7], so the
//     sign is handled for free; B4G3 needs a special top dibit)
// Back end is identical: one's-complement PPs, sign vector,
// 3:2 compression tree, final CPA.
// ============================================================

// ---- MODULE 1: Booth R4 encoder (unchanged, yours) ----
module encoder(
  input  logic b_prev, b_curr, b_next,
  output logic negation, two, zero
);
  always_comb begin
    case ({b_next, b_curr, b_prev})
      3'b000: begin zero=1; two=0; negation=0; end
      3'b001: begin zero=0; two=0; negation=0; end
      3'b010: begin zero=0; two=0; negation=0; end
      3'b011: begin zero=0; two=1; negation=0; end
      3'b100: begin zero=0; two=1; negation=1; end
      3'b101: begin zero=0; two=0; negation=1; end
      3'b110: begin zero=0; two=0; negation=1; end
      3'b111: begin zero=1; two=0; negation=0; end
    endcase
  end
endmodule

// ---- MODULE 2: partial-product mux (ONE'S COMPLEMENT form) ----
//   Picks magnitude {0, A, 2A} and INVERTS it when negating.
//   The matching "+1" is carried out as sign_bit and summed later
//   in the sign vector -- never added here.
module mux(
  input  logic        negation, two, zero,
  input  logic signed [7:0] A,
  output logic [8:0]  p_product           // 1's-complement PP bits
);
  logic [8:0] pos_A, pos_2A, mag;
  always_comb begin
    pos_A  = $signed({A[7], A});           //  A  (sign-extend to 9)
    pos_2A = $signed({A, 1'b0});           // 2A  (= A << 1, exactly 9 bits)
    mag    = zero ? 9'b0 : (two ? pos_2A : pos_A);
    p_product = negation ? ~mag : mag;     // invert only; no +1 here
  end
endmodule

// ---- MODULE 3: Booth unit (encoder + mux) ----
//   sign_bit is the one's-complement "+1" correction (= negation).
module booth_unit(
  input  logic signed [7:0] A,
  input  logic b_prev, b_curr, b_next,
  output logic [8:0] p_product,
  output logic sign_bit
);
  logic zero, two, negation;
  encoder enc (
    .b_prev(b_prev), .b_curr(b_curr), .b_next(b_next),
    .zero(zero), .two(two), .negation(negation)
  );
  mux m (
    .zero(zero), .two(two), .negation(negation),
    .A(A), .p_product(p_product)
  );
  assign sign_bit = negation;
endmodule

// ---- MODULE 4: 3:2 carry-save compressor (one tree node) ----
//   x + y + z == s + (c << 1)  (mod 2^16).  Identical to B4G3's.
module csa16(
  input  logic [15:0] x, y, z,
  output logic [15:0] s, c
);
  assign s = x ^ y ^ z;
  assign c = (x & y) | (y & z) | (x & z);
endmodule

// ---- MODULE 5: full multiplier ----
//   NOTE: no prefix_tree here. Windows overlap via b_prev instead.
module booth_multiplier(
  input  logic signed [7:0]  A, B,
  output logic signed [15:0] product
);
  logic [8:0] pp0, pp1, pp2, pp3;        // 1's-complement PP magnitudes
  logic e0, e1, e2, e3;                  // sign-vector correction bits

  // overlapping 3-bit windows; b_prev of the lowest unit is 0
  booth_unit u0 (.A(A), .b_prev(1'b0), .b_curr(B[0]), .b_next(B[1]), .p_product(pp0), .sign_bit(e0));
  booth_unit u1 (.A(A), .b_prev(B[1]), .b_curr(B[2]), .b_next(B[3]), .p_product(pp1), .sign_bit(e1));
  booth_unit u2 (.A(A), .b_prev(B[3]), .b_curr(B[4]), .b_next(B[5]), .p_product(pp2), .sign_bit(e2));
  booth_unit u3 (.A(A), .b_prev(B[5]), .b_curr(B[6]), .b_next(B[7]), .p_product(pp3), .sign_bit(e3));

  // sign-extend each PP to 16 bits and place at weight 4^i (shift 2i)
  logic [15:0] R0, R1, R2, R3;
  assign R0 =  {{7{pp0[8]}}, pp0};
  assign R1 = ({{7{pp1[8]}}, pp1}) << 2;
  assign R2 = ({{7{pp2[8]}}, pp2}) << 4;
  assign R3 = ({{7{pp3[8]}}, pp3}) << 6;

  // sign vector: each "+1" correction sits at bit 2i (cols 0,2,4,6)
  logic [15:0] K;
  assign K = {9'b0, e3, 1'b0, e2, 1'b0, e1, 1'b0, e0};

  // compression tree: reduce {R0,R1,R2,R3,K} (5 rows) to 2 rows
  logic [15:0] sa, ca, sb, cb, sc, cc;
  csa16 z1 (.x(R0), .y(R1),      .z(R2), .s(sa), .c(ca));
  csa16 z2 (.x(sa), .y(ca << 1), .z(R3), .s(sb), .c(cb));
  csa16 z3 (.x(sb), .y(cb << 1), .z(K),  .s(sc), .c(cc));

  // final CPA
  assign product = $signed(sc + (cc << 1));
endmodule
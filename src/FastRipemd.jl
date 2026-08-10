module FastRipemd

# ═══════════════════════════════════════════════════════════════════
# FastRipemd.jl — Implementação RIPEMD-160 (Ultra-Otimizada para Bitcoin)
# Réplica da versão validada em GpuHashing.jl (ripemd160_single_block_gpu),
# adaptada para entrada/saída via ponteiros (Zero-GC).
# ═══════════════════════════════════════════════════════════════════

export ripemd160_32b!, ripemd160_32b_4x!

@inline f1(x::UInt32, y::UInt32, z::UInt32) = x ⊻ y ⊻ z
@inline f2(x::UInt32, y::UInt32, z::UInt32) = (x & y) | (~x & z)
@inline f3(x::UInt32, y::UInt32, z::UInt32) = (x | ~y) ⊻ z
@inline f4(x::UInt32, y::UInt32, z::UInt32) = (x & z) | (y & ~z)
@inline f5(x::UInt32, y::UInt32, z::UInt32) = x ⊻ (y | ~z)

@inline rol(x::UInt32, n::Int) = (x << n) | (x >>> (32 - n))

macro round_ripemd(f_name, A, B, C, D, E, X, K, S)
    esc(quote
        $A = rol($A + $f_name($B, $C, $D) + $X + $K, $S) + $E
        $C = rol($C, 10)
    end)
end

macro rr1(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f1 $A $B $C $D $E $X $K $S)) end
macro rr2(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f2 $A $B $C $D $E $X $K $S)) end
macro rr3(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f3 $A $B $C $D $E $X $K $S)) end
macro rr4(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f4 $A $B $C $D $E $X $K $S)) end
macro rr5(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f5 $A $B $C $D $E $X $K $S)) end

@inline function ripemd160_32b!(in_p::Ptr{UInt8}, out_p::Ptr{UInt8})
    p32 = convert(Ptr{UInt32}, in_p)
    w0 = unsafe_load(p32, 1); w1 = unsafe_load(p32, 2)
    w2 = unsafe_load(p32, 3); w3 = unsafe_load(p32, 4)
    w4 = unsafe_load(p32, 5); w5 = unsafe_load(p32, 6)
    w6 = unsafe_load(p32, 7); w7 = unsafe_load(p32, 8)
    w8 = UInt32(0x00000080); w9 = UInt32(0); w10 = UInt32(0); w11 = UInt32(0)
    w12 = UInt32(0); w13 = UInt32(0); w14 = UInt32(256); w15 = UInt32(0)

    A = 0x67452301; B = 0xefcdab89; C = 0x98badcfe; D = 0x10325476; E = 0xc3d2e1f0
    Ap = 0x67452301; Bp = 0xefcdab89; Cp = 0x98badcfe; Dp = 0x10325476; Ep = 0xc3d2e1f0

    # Chain 1
    @rr1 A B C D E w0  0x00000000 11; @rr1 E A B C D w1  0x00000000 14; @rr1 D E A B C w2  0x00000000 15; @rr1 C D E A B w3  0x00000000 12
    @rr1 B C D E A w4  0x00000000  5; @rr1 A B C D E w5  0x00000000  8; @rr1 E A B C D w6  0x00000000  7; @rr1 D E A B C w7  0x00000000  9
    @rr1 C D E A B w8  0x00000000 11; @rr1 B C D E A w9  0x00000000 13; @rr1 A B C D E w10 0x00000000 14; @rr1 E A B C D w11 0x00000000 15
    @rr1 D E A B C w12 0x00000000  6; @rr1 C D E A B w13 0x00000000  7; @rr1 B C D E A w14 0x00000000  9; @rr1 A B C D E w15 0x00000000  8

    @rr2 E A B C D w7  0x5a827999  7; @rr2 D E A B C w4  0x5a827999  6; @rr2 C D E A B w13 0x5a827999  8; @rr2 B C D E A w1  0x5a827999 13
    @rr2 A B C D E w10 0x5a827999 11; @rr2 E A B C D w6  0x5a827999  9; @rr2 D E A B C w15 0x5a827999  7; @rr2 C D E A B w3  0x5a827999 15
    @rr2 B C D E A w12 0x5a827999  7; @rr2 A B C D E w0  0x5a827999 12; @rr2 E A B C D w9  0x5a827999 15; @rr2 D E A B C w5  0x5a827999  9
    @rr2 C D E A B w2  0x5a827999 11; @rr2 B C D E A w14 0x5a827999  7; @rr2 A B C D E w11 0x5a827999 13; @rr2 E A B C D w8  0x5a827999 12

    @rr3 D E A B C w3  0x6ed9eba1 11; @rr3 C D E A B w10 0x6ed9eba1 13; @rr3 B C D E A w14 0x6ed9eba1  6; @rr3 A B C D E w4  0x6ed9eba1  7
    @rr3 E A B C D w9  0x6ed9eba1 14; @rr3 D E A B C w15 0x6ed9eba1  9; @rr3 C D E A B w8  0x6ed9eba1 13; @rr3 B C D E A w1  0x6ed9eba1 15
    @rr3 A B C D E w2  0x6ed9eba1 14; @rr3 E A B C D w7  0x6ed9eba1  8; @rr3 D E A B C w0  0x6ed9eba1 13; @rr3 C D E A B w6  0x6ed9eba1  6
    @rr3 B C D E A w13 0x6ed9eba1  5; @rr3 A B C D E w11 0x6ed9eba1 12; @rr3 E A B C D w5  0x6ed9eba1  7; @rr3 D E A B C w12 0x6ed9eba1  5

    @rr4 C D E A B w1  0x8f1bbcdc 11; @rr4 B C D E A w9  0x8f1bbcdc 12; @rr4 A B C D E w11 0x8f1bbcdc 14; @rr4 E A B C D w10 0x8f1bbcdc 15
    @rr4 D E A B C w0  0x8f1bbcdc 14; @rr4 C D E A B w8  0x8f1bbcdc 15; @rr4 B C D E A w12 0x8f1bbcdc  9; @rr4 A B C D E w4  0x8f1bbcdc  8
    @rr4 E A B C D w13 0x8f1bbcdc  9; @rr4 D E A B C w3  0x8f1bbcdc 14; @rr4 C D E A B w7  0x8f1bbcdc  5; @rr4 B C D E A w15 0x8f1bbcdc  6
    @rr4 A B C D E w14 0x8f1bbcdc  8; @rr4 E A B C D w5  0x8f1bbcdc  6; @rr4 D E A B C w6  0x8f1bbcdc  5; @rr4 C D E A B w2  0x8f1bbcdc 12

    @rr5 B C D E A w4  0xa953fd4e  9; @rr5 A B C D E w0  0xa953fd4e 15; @rr5 E A B C D w5  0xa953fd4e  5; @rr5 D E A B C w9  0xa953fd4e 11
    @rr5 C D E A B w7  0xa953fd4e  6; @rr5 B C D E A w12 0xa953fd4e  8; @rr5 A B C D E w2  0xa953fd4e 13; @rr5 E A B C D w10 0xa953fd4e 12
    @rr5 D E A B C w14 0xa953fd4e  5; @rr5 C D E A B w1  0xa953fd4e 12; @rr5 B C D E A w3  0xa953fd4e 13; @rr5 A B C D E w8  0xa953fd4e 14
    @rr5 E A B C D w11 0xa953fd4e 11; @rr5 D E A B C w6  0xa953fd4e  8; @rr5 C D E A B w15 0xa953fd4e  5; @rr5 B C D E A w13 0xa953fd4e  6

    # Chain 2
    @rr5 Ap Bp Cp Dp Ep w5  0x50a28be6  8; @rr5 Ep Ap Bp Cp Dp w14 0x50a28be6  9; @rr5 Dp Ep Ap Bp Cp w7  0x50a28be6  9; @rr5 Cp Dp Ep Ap Bp w0  0x50a28be6 11
    @rr5 Bp Cp Dp Ep Ap w9  0x50a28be6 13; @rr5 Ap Bp Cp Dp Ep w2  0x50a28be6 15; @rr5 Ep Ap Bp Cp Dp w11 0x50a28be6 15; @rr5 Dp Ep Ap Bp Cp w4  0x50a28be6  5
    @rr5 Cp Dp Ep Ap Bp w13 0x50a28be6  7; @rr5 Bp Cp Dp Ep Ap w6  0x50a28be6  7; @rr5 Ap Bp Cp Dp Ep w15 0x50a28be6  8; @rr5 Ep Ap Bp Cp Dp w8  0x50a28be6 11
    @rr5 Dp Ep Ap Bp Cp w1  0x50a28be6 14; @rr5 Cp Dp Ep Ap Bp w10 0x50a28be6 14; @rr5 Bp Cp Dp Ep Ap w3  0x50a28be6 12; @rr5 Ap Bp Cp Dp Ep w12 0x50a28be6  6

    @rr4 Ep Ap Bp Cp Dp w6  0x5c4dd124  9; @rr4 Dp Ep Ap Bp Cp w11 0x5c4dd124 13; @rr4 Cp Dp Ep Ap Bp w3  0x5c4dd124 15; @rr4 Bp Cp Dp Ep Ap w7  0x5c4dd124  7
    @rr4 Ap Bp Cp Dp Ep w0  0x5c4dd124 12; @rr4 Ep Ap Bp Cp Dp w13 0x5c4dd124  8; @rr4 Dp Ep Ap Bp Cp w5  0x5c4dd124  9; @rr4 Cp Dp Ep Ap Bp w10 0x5c4dd124 11
    @rr4 Bp Cp Dp Ep Ap w14 0x5c4dd124  7; @rr4 Ap Bp Cp Dp Ep w15 0x5c4dd124  7; @rr4 Ep Ap Bp Cp Dp w8  0x5c4dd124 12; @rr4 Dp Ep Ap Bp Cp w12 0x5c4dd124  7
    @rr4 Cp Dp Ep Ap Bp w4  0x5c4dd124  6; @rr4 Bp Cp Dp Ep Ap w9  0x5c4dd124 15; @rr4 Ap Bp Cp Dp Ep w1  0x5c4dd124 13; @rr4 Ep Ap Bp Cp Dp w2  0x5c4dd124 11

    @rr3 Dp Ep Ap Bp Cp w15 0x6d703ef3  9; @rr3 Cp Dp Ep Ap Bp w5  0x6d703ef3  7; @rr3 Bp Cp Dp Ep Ap w1  0x6d703ef3 15; @rr3 Ap Bp Cp Dp Ep w3  0x6d703ef3 11
    @rr3 Ep Ap Bp Cp Dp w7  0x6d703ef3  8; @rr3 Dp Ep Ap Bp Cp w14 0x6d703ef3  6; @rr3 Cp Dp Ep Ap Bp w6  0x6d703ef3  6; @rr3 Bp Cp Dp Ep Ap w9  0x6d703ef3 14
    @rr3 Ap Bp Cp Dp Ep w11 0x6d703ef3 12; @rr3 Ep Ap Bp Cp Dp w8  0x6d703ef3 13; @rr3 Dp Ep Ap Bp Cp w12 0x6d703ef3  5; @rr3 Cp Dp Ep Ap Bp w2  0x6d703ef3 14
    @rr3 Bp Cp Dp Ep Ap w10 0x6d703ef3 13; @rr3 Ap Bp Cp Dp Ep w0  0x6d703ef3 13; @rr3 Ep Ap Bp Cp Dp w4  0x6d703ef3  7; @rr3 Dp Ep Ap Bp Cp w13 0x6d703ef3  5

    @rr2 Cp Dp Ep Ap Bp w8  0x7a6d76e9 15; @rr2 Bp Cp Dp Ep Ap w6  0x7a6d76e9  5; @rr2 Ap Bp Cp Dp Ep w4  0x7a6d76e9  8; @rr2 Ep Ap Bp Cp Dp w1  0x7a6d76e9 11
    @rr2 Dp Ep Ap Bp Cp w3  0x7a6d76e9 14; @rr2 Cp Dp Ep Ap Bp w11 0x7a6d76e9 14; @rr2 Bp Cp Dp Ep Ap w15 0x7a6d76e9  6; @rr2 Ap Bp Cp Dp Ep w0  0x7a6d76e9 14
    @rr2 Ep Ap Bp Cp Dp w5  0x7a6d76e9  6; @rr2 Dp Ep Ap Bp Cp w12 0x7a6d76e9  9; @rr2 Cp Dp Ep Ap Bp w2  0x7a6d76e9 12; @rr2 Bp Cp Dp Ep Ap w13 0x7a6d76e9  9
    @rr2 Ap Bp Cp Dp Ep w9  0x7a6d76e9 12; @rr2 Ep Ap Bp Cp Dp w7  0x7a6d76e9  5; @rr2 Dp Ep Ap Bp Cp w10 0x7a6d76e9 15; @rr2 Cp Dp Ep Ap Bp w14 0x7a6d76e9  8

    @rr1 Bp Cp Dp Ep Ap w12 0x00000000  8; @rr1 Ap Bp Cp Dp Ep w15 0x00000000  5; @rr1 Ep Ap Bp Cp Dp w10 0x00000000 12; @rr1 Dp Ep Ap Bp Cp w4  0x00000000  9
    @rr1 Cp Dp Ep Ap Bp w1  0x00000000 12; @rr1 Bp Cp Dp Ep Ap w5  0x00000000  5; @rr1 Ap Bp Cp Dp Ep w8  0x00000000 14; @rr1 Ep Ap Bp Cp Dp w7  0x00000000  6
    @rr1 Dp Ep Ap Bp Cp w6  0x00000000  8; @rr1 Cp Dp Ep Ap Bp w2  0x00000000 13; @rr1 Bp Cp Dp Ep Ap w13 0x00000000  6; @rr1 Ap Bp Cp Dp Ep w14 0x00000000  5
    @rr1 Ep Ap Bp Cp Dp w0  0x00000000 15; @rr1 Dp Ep Ap Bp Cp w3  0x00000000 13; @rr1 Cp Dp Ep Ap Bp w9  0x00000000 11; @rr1 Bp Cp Dp Ep Ap w11 0x00000000 11

    # Combine
    h0 = UInt32(0x67452301); h1 = UInt32(0xefcdab89); h2 = UInt32(0x98badcfe)
    h3 = UInt32(0x10325476); h4 = UInt32(0xc3d2e1f0)
    t = h1 + C + Dp; h1 = h2 + D + Ep; h2 = h3 + E + Ap
    h3 = h4 + A + Bp; h4 = h0 + B + Cp; h0 = t

    # Output words little-endian (same byte order as validated GPU kernel)
    p_out = convert(Ptr{UInt32}, out_p)
    @inbounds for (i, word) in enumerate((h0, h1, h2, h3, h4))
        unsafe_store!(p_out, word, i)
    end
end


@inline function ripemd160_32b_4x!(in_p::Ptr{UInt8}, out_p::Ptr{UInt8})
    p32 = convert(Ptr{UInt32}, in_p)
    w0_0 = unsafe_load(p32, 1); w1_0 = unsafe_load(p32, 2); w2_0 = unsafe_load(p32, 3); w3_0 = unsafe_load(p32, 4)
    w4_0 = unsafe_load(p32, 5); w5_0 = unsafe_load(p32, 6); w6_0 = unsafe_load(p32, 7); w7_0 = unsafe_load(p32, 8)
    w8_0 = UInt32(0x00000080); w9_0 = UInt32(0); w10_0 = UInt32(0); w11_0 = UInt32(0)
    w12_0 = UInt32(0); w13_0 = UInt32(0); w14_0 = UInt32(256); w15_0 = UInt32(0)
    w0_1 = unsafe_load(p32, 9); w1_1 = unsafe_load(p32, 10); w2_1 = unsafe_load(p32, 11); w3_1 = unsafe_load(p32, 12)
    w4_1 = unsafe_load(p32, 13); w5_1 = unsafe_load(p32, 14); w6_1 = unsafe_load(p32, 15); w7_1 = unsafe_load(p32, 16)
    w8_1 = UInt32(0x00000080); w9_1 = UInt32(0); w10_1 = UInt32(0); w11_1 = UInt32(0)
    w12_1 = UInt32(0); w13_1 = UInt32(0); w14_1 = UInt32(256); w15_1 = UInt32(0)
    w0_2 = unsafe_load(p32, 17); w1_2 = unsafe_load(p32, 18); w2_2 = unsafe_load(p32, 19); w3_2 = unsafe_load(p32, 20)
    w4_2 = unsafe_load(p32, 21); w5_2 = unsafe_load(p32, 22); w6_2 = unsafe_load(p32, 23); w7_2 = unsafe_load(p32, 24)
    w8_2 = UInt32(0x00000080); w9_2 = UInt32(0); w10_2 = UInt32(0); w11_2 = UInt32(0)
    w12_2 = UInt32(0); w13_2 = UInt32(0); w14_2 = UInt32(256); w15_2 = UInt32(0)
    w0_3 = unsafe_load(p32, 25); w1_3 = unsafe_load(p32, 26); w2_3 = unsafe_load(p32, 27); w3_3 = unsafe_load(p32, 28)
    w4_3 = unsafe_load(p32, 29); w5_3 = unsafe_load(p32, 30); w6_3 = unsafe_load(p32, 31); w7_3 = unsafe_load(p32, 32)
    w8_3 = UInt32(0x00000080); w9_3 = UInt32(0); w10_3 = UInt32(0); w11_3 = UInt32(0)
    w12_3 = UInt32(0); w13_3 = UInt32(0); w14_3 = UInt32(256); w15_3 = UInt32(0)
    A0 = 0x67452301; B0 = 0xefcdab89; C0 = 0x98badcfe; D0 = 0x10325476; E0 = 0xc3d2e1f0
    A1 = 0x67452301; B1 = 0xefcdab89; C1 = 0x98badcfe; D1 = 0x10325476; E1 = 0xc3d2e1f0
    A2 = 0x67452301; B2 = 0xefcdab89; C2 = 0x98badcfe; D2 = 0x10325476; E2 = 0xc3d2e1f0
    A3 = 0x67452301; B3 = 0xefcdab89; C3 = 0x98badcfe; D3 = 0x10325476; E3 = 0xc3d2e1f0
    Ap0 = 0x67452301; Bp0 = 0xefcdab89; Cp0 = 0x98badcfe; Dp0 = 0x10325476; Ep0 = 0xc3d2e1f0
    Ap1 = 0x67452301; Bp1 = 0xefcdab89; Cp1 = 0x98badcfe; Dp1 = 0x10325476; Ep1 = 0xc3d2e1f0
    Ap2 = 0x67452301; Bp2 = 0xefcdab89; Cp2 = 0x98badcfe; Dp2 = 0x10325476; Ep2 = 0xc3d2e1f0
    Ap3 = 0x67452301; Bp3 = 0xefcdab89; Cp3 = 0x98badcfe; Dp3 = 0x10325476; Ep3 = 0xc3d2e1f0
    A0 = rol(A0 + f1(B0, C0, D0) + w0_0 + 0x00000000, 11) + E0
    A1 = rol(A1 + f1(B1, C1, D1) + w0_1 + 0x00000000, 11) + E1
    A2 = rol(A2 + f1(B2, C2, D2) + w0_2 + 0x00000000, 11) + E2
    A3 = rol(A3 + f1(B3, C3, D3) + w0_3 + 0x00000000, 11) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f1(A0, B0, C0) + w1_0 + 0x00000000, 14) + D0
    E1 = rol(E1 + f1(A1, B1, C1) + w1_1 + 0x00000000, 14) + D1
    E2 = rol(E2 + f1(A2, B2, C2) + w1_2 + 0x00000000, 14) + D2
    E3 = rol(E3 + f1(A3, B3, C3) + w1_3 + 0x00000000, 14) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f1(E0, A0, B0) + w2_0 + 0x00000000, 15) + C0
    D1 = rol(D1 + f1(E1, A1, B1) + w2_1 + 0x00000000, 15) + C1
    D2 = rol(D2 + f1(E2, A2, B2) + w2_2 + 0x00000000, 15) + C2
    D3 = rol(D3 + f1(E3, A3, B3) + w2_3 + 0x00000000, 15) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f1(D0, E0, A0) + w3_0 + 0x00000000, 12) + B0
    C1 = rol(C1 + f1(D1, E1, A1) + w3_1 + 0x00000000, 12) + B1
    C2 = rol(C2 + f1(D2, E2, A2) + w3_2 + 0x00000000, 12) + B2
    C3 = rol(C3 + f1(D3, E3, A3) + w3_3 + 0x00000000, 12) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f1(C0, D0, E0) + w4_0 + 0x00000000, 5) + A0
    B1 = rol(B1 + f1(C1, D1, E1) + w4_1 + 0x00000000, 5) + A1
    B2 = rol(B2 + f1(C2, D2, E2) + w4_2 + 0x00000000, 5) + A2
    B3 = rol(B3 + f1(C3, D3, E3) + w4_3 + 0x00000000, 5) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f1(B0, C0, D0) + w5_0 + 0x00000000, 8) + E0
    A1 = rol(A1 + f1(B1, C1, D1) + w5_1 + 0x00000000, 8) + E1
    A2 = rol(A2 + f1(B2, C2, D2) + w5_2 + 0x00000000, 8) + E2
    A3 = rol(A3 + f1(B3, C3, D3) + w5_3 + 0x00000000, 8) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f1(A0, B0, C0) + w6_0 + 0x00000000, 7) + D0
    E1 = rol(E1 + f1(A1, B1, C1) + w6_1 + 0x00000000, 7) + D1
    E2 = rol(E2 + f1(A2, B2, C2) + w6_2 + 0x00000000, 7) + D2
    E3 = rol(E3 + f1(A3, B3, C3) + w6_3 + 0x00000000, 7) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f1(E0, A0, B0) + w7_0 + 0x00000000, 9) + C0
    D1 = rol(D1 + f1(E1, A1, B1) + w7_1 + 0x00000000, 9) + C1
    D2 = rol(D2 + f1(E2, A2, B2) + w7_2 + 0x00000000, 9) + C2
    D3 = rol(D3 + f1(E3, A3, B3) + w7_3 + 0x00000000, 9) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f1(D0, E0, A0) + w8_0 + 0x00000000, 11) + B0
    C1 = rol(C1 + f1(D1, E1, A1) + w8_1 + 0x00000000, 11) + B1
    C2 = rol(C2 + f1(D2, E2, A2) + w8_2 + 0x00000000, 11) + B2
    C3 = rol(C3 + f1(D3, E3, A3) + w8_3 + 0x00000000, 11) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f1(C0, D0, E0) + w9_0 + 0x00000000, 13) + A0
    B1 = rol(B1 + f1(C1, D1, E1) + w9_1 + 0x00000000, 13) + A1
    B2 = rol(B2 + f1(C2, D2, E2) + w9_2 + 0x00000000, 13) + A2
    B3 = rol(B3 + f1(C3, D3, E3) + w9_3 + 0x00000000, 13) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f1(B0, C0, D0) + w10_0 + 0x00000000, 14) + E0
    A1 = rol(A1 + f1(B1, C1, D1) + w10_1 + 0x00000000, 14) + E1
    A2 = rol(A2 + f1(B2, C2, D2) + w10_2 + 0x00000000, 14) + E2
    A3 = rol(A3 + f1(B3, C3, D3) + w10_3 + 0x00000000, 14) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f1(A0, B0, C0) + w11_0 + 0x00000000, 15) + D0
    E1 = rol(E1 + f1(A1, B1, C1) + w11_1 + 0x00000000, 15) + D1
    E2 = rol(E2 + f1(A2, B2, C2) + w11_2 + 0x00000000, 15) + D2
    E3 = rol(E3 + f1(A3, B3, C3) + w11_3 + 0x00000000, 15) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f1(E0, A0, B0) + w12_0 + 0x00000000, 6) + C0
    D1 = rol(D1 + f1(E1, A1, B1) + w12_1 + 0x00000000, 6) + C1
    D2 = rol(D2 + f1(E2, A2, B2) + w12_2 + 0x00000000, 6) + C2
    D3 = rol(D3 + f1(E3, A3, B3) + w12_3 + 0x00000000, 6) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f1(D0, E0, A0) + w13_0 + 0x00000000, 7) + B0
    C1 = rol(C1 + f1(D1, E1, A1) + w13_1 + 0x00000000, 7) + B1
    C2 = rol(C2 + f1(D2, E2, A2) + w13_2 + 0x00000000, 7) + B2
    C3 = rol(C3 + f1(D3, E3, A3) + w13_3 + 0x00000000, 7) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f1(C0, D0, E0) + w14_0 + 0x00000000, 9) + A0
    B1 = rol(B1 + f1(C1, D1, E1) + w14_1 + 0x00000000, 9) + A1
    B2 = rol(B2 + f1(C2, D2, E2) + w14_2 + 0x00000000, 9) + A2
    B3 = rol(B3 + f1(C3, D3, E3) + w14_3 + 0x00000000, 9) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f1(B0, C0, D0) + w15_0 + 0x00000000, 8) + E0
    A1 = rol(A1 + f1(B1, C1, D1) + w15_1 + 0x00000000, 8) + E1
    A2 = rol(A2 + f1(B2, C2, D2) + w15_2 + 0x00000000, 8) + E2
    A3 = rol(A3 + f1(B3, C3, D3) + w15_3 + 0x00000000, 8) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f2(A0, B0, C0) + w7_0 + 0x5a827999, 7) + D0
    E1 = rol(E1 + f2(A1, B1, C1) + w7_1 + 0x5a827999, 7) + D1
    E2 = rol(E2 + f2(A2, B2, C2) + w7_2 + 0x5a827999, 7) + D2
    E3 = rol(E3 + f2(A3, B3, C3) + w7_3 + 0x5a827999, 7) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f2(E0, A0, B0) + w4_0 + 0x5a827999, 6) + C0
    D1 = rol(D1 + f2(E1, A1, B1) + w4_1 + 0x5a827999, 6) + C1
    D2 = rol(D2 + f2(E2, A2, B2) + w4_2 + 0x5a827999, 6) + C2
    D3 = rol(D3 + f2(E3, A3, B3) + w4_3 + 0x5a827999, 6) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f2(D0, E0, A0) + w13_0 + 0x5a827999, 8) + B0
    C1 = rol(C1 + f2(D1, E1, A1) + w13_1 + 0x5a827999, 8) + B1
    C2 = rol(C2 + f2(D2, E2, A2) + w13_2 + 0x5a827999, 8) + B2
    C3 = rol(C3 + f2(D3, E3, A3) + w13_3 + 0x5a827999, 8) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f2(C0, D0, E0) + w1_0 + 0x5a827999, 13) + A0
    B1 = rol(B1 + f2(C1, D1, E1) + w1_1 + 0x5a827999, 13) + A1
    B2 = rol(B2 + f2(C2, D2, E2) + w1_2 + 0x5a827999, 13) + A2
    B3 = rol(B3 + f2(C3, D3, E3) + w1_3 + 0x5a827999, 13) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f2(B0, C0, D0) + w10_0 + 0x5a827999, 11) + E0
    A1 = rol(A1 + f2(B1, C1, D1) + w10_1 + 0x5a827999, 11) + E1
    A2 = rol(A2 + f2(B2, C2, D2) + w10_2 + 0x5a827999, 11) + E2
    A3 = rol(A3 + f2(B3, C3, D3) + w10_3 + 0x5a827999, 11) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f2(A0, B0, C0) + w6_0 + 0x5a827999, 9) + D0
    E1 = rol(E1 + f2(A1, B1, C1) + w6_1 + 0x5a827999, 9) + D1
    E2 = rol(E2 + f2(A2, B2, C2) + w6_2 + 0x5a827999, 9) + D2
    E3 = rol(E3 + f2(A3, B3, C3) + w6_3 + 0x5a827999, 9) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f2(E0, A0, B0) + w15_0 + 0x5a827999, 7) + C0
    D1 = rol(D1 + f2(E1, A1, B1) + w15_1 + 0x5a827999, 7) + C1
    D2 = rol(D2 + f2(E2, A2, B2) + w15_2 + 0x5a827999, 7) + C2
    D3 = rol(D3 + f2(E3, A3, B3) + w15_3 + 0x5a827999, 7) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f2(D0, E0, A0) + w3_0 + 0x5a827999, 15) + B0
    C1 = rol(C1 + f2(D1, E1, A1) + w3_1 + 0x5a827999, 15) + B1
    C2 = rol(C2 + f2(D2, E2, A2) + w3_2 + 0x5a827999, 15) + B2
    C3 = rol(C3 + f2(D3, E3, A3) + w3_3 + 0x5a827999, 15) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f2(C0, D0, E0) + w12_0 + 0x5a827999, 7) + A0
    B1 = rol(B1 + f2(C1, D1, E1) + w12_1 + 0x5a827999, 7) + A1
    B2 = rol(B2 + f2(C2, D2, E2) + w12_2 + 0x5a827999, 7) + A2
    B3 = rol(B3 + f2(C3, D3, E3) + w12_3 + 0x5a827999, 7) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f2(B0, C0, D0) + w0_0 + 0x5a827999, 12) + E0
    A1 = rol(A1 + f2(B1, C1, D1) + w0_1 + 0x5a827999, 12) + E1
    A2 = rol(A2 + f2(B2, C2, D2) + w0_2 + 0x5a827999, 12) + E2
    A3 = rol(A3 + f2(B3, C3, D3) + w0_3 + 0x5a827999, 12) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f2(A0, B0, C0) + w9_0 + 0x5a827999, 15) + D0
    E1 = rol(E1 + f2(A1, B1, C1) + w9_1 + 0x5a827999, 15) + D1
    E2 = rol(E2 + f2(A2, B2, C2) + w9_2 + 0x5a827999, 15) + D2
    E3 = rol(E3 + f2(A3, B3, C3) + w9_3 + 0x5a827999, 15) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f2(E0, A0, B0) + w5_0 + 0x5a827999, 9) + C0
    D1 = rol(D1 + f2(E1, A1, B1) + w5_1 + 0x5a827999, 9) + C1
    D2 = rol(D2 + f2(E2, A2, B2) + w5_2 + 0x5a827999, 9) + C2
    D3 = rol(D3 + f2(E3, A3, B3) + w5_3 + 0x5a827999, 9) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f2(D0, E0, A0) + w2_0 + 0x5a827999, 11) + B0
    C1 = rol(C1 + f2(D1, E1, A1) + w2_1 + 0x5a827999, 11) + B1
    C2 = rol(C2 + f2(D2, E2, A2) + w2_2 + 0x5a827999, 11) + B2
    C3 = rol(C3 + f2(D3, E3, A3) + w2_3 + 0x5a827999, 11) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f2(C0, D0, E0) + w14_0 + 0x5a827999, 7) + A0
    B1 = rol(B1 + f2(C1, D1, E1) + w14_1 + 0x5a827999, 7) + A1
    B2 = rol(B2 + f2(C2, D2, E2) + w14_2 + 0x5a827999, 7) + A2
    B3 = rol(B3 + f2(C3, D3, E3) + w14_3 + 0x5a827999, 7) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f2(B0, C0, D0) + w11_0 + 0x5a827999, 13) + E0
    A1 = rol(A1 + f2(B1, C1, D1) + w11_1 + 0x5a827999, 13) + E1
    A2 = rol(A2 + f2(B2, C2, D2) + w11_2 + 0x5a827999, 13) + E2
    A3 = rol(A3 + f2(B3, C3, D3) + w11_3 + 0x5a827999, 13) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f2(A0, B0, C0) + w8_0 + 0x5a827999, 12) + D0
    E1 = rol(E1 + f2(A1, B1, C1) + w8_1 + 0x5a827999, 12) + D1
    E2 = rol(E2 + f2(A2, B2, C2) + w8_2 + 0x5a827999, 12) + D2
    E3 = rol(E3 + f2(A3, B3, C3) + w8_3 + 0x5a827999, 12) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f3(E0, A0, B0) + w3_0 + 0x6ed9eba1, 11) + C0
    D1 = rol(D1 + f3(E1, A1, B1) + w3_1 + 0x6ed9eba1, 11) + C1
    D2 = rol(D2 + f3(E2, A2, B2) + w3_2 + 0x6ed9eba1, 11) + C2
    D3 = rol(D3 + f3(E3, A3, B3) + w3_3 + 0x6ed9eba1, 11) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f3(D0, E0, A0) + w10_0 + 0x6ed9eba1, 13) + B0
    C1 = rol(C1 + f3(D1, E1, A1) + w10_1 + 0x6ed9eba1, 13) + B1
    C2 = rol(C2 + f3(D2, E2, A2) + w10_2 + 0x6ed9eba1, 13) + B2
    C3 = rol(C3 + f3(D3, E3, A3) + w10_3 + 0x6ed9eba1, 13) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f3(C0, D0, E0) + w14_0 + 0x6ed9eba1, 6) + A0
    B1 = rol(B1 + f3(C1, D1, E1) + w14_1 + 0x6ed9eba1, 6) + A1
    B2 = rol(B2 + f3(C2, D2, E2) + w14_2 + 0x6ed9eba1, 6) + A2
    B3 = rol(B3 + f3(C3, D3, E3) + w14_3 + 0x6ed9eba1, 6) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f3(B0, C0, D0) + w4_0 + 0x6ed9eba1, 7) + E0
    A1 = rol(A1 + f3(B1, C1, D1) + w4_1 + 0x6ed9eba1, 7) + E1
    A2 = rol(A2 + f3(B2, C2, D2) + w4_2 + 0x6ed9eba1, 7) + E2
    A3 = rol(A3 + f3(B3, C3, D3) + w4_3 + 0x6ed9eba1, 7) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f3(A0, B0, C0) + w9_0 + 0x6ed9eba1, 14) + D0
    E1 = rol(E1 + f3(A1, B1, C1) + w9_1 + 0x6ed9eba1, 14) + D1
    E2 = rol(E2 + f3(A2, B2, C2) + w9_2 + 0x6ed9eba1, 14) + D2
    E3 = rol(E3 + f3(A3, B3, C3) + w9_3 + 0x6ed9eba1, 14) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f3(E0, A0, B0) + w15_0 + 0x6ed9eba1, 9) + C0
    D1 = rol(D1 + f3(E1, A1, B1) + w15_1 + 0x6ed9eba1, 9) + C1
    D2 = rol(D2 + f3(E2, A2, B2) + w15_2 + 0x6ed9eba1, 9) + C2
    D3 = rol(D3 + f3(E3, A3, B3) + w15_3 + 0x6ed9eba1, 9) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f3(D0, E0, A0) + w8_0 + 0x6ed9eba1, 13) + B0
    C1 = rol(C1 + f3(D1, E1, A1) + w8_1 + 0x6ed9eba1, 13) + B1
    C2 = rol(C2 + f3(D2, E2, A2) + w8_2 + 0x6ed9eba1, 13) + B2
    C3 = rol(C3 + f3(D3, E3, A3) + w8_3 + 0x6ed9eba1, 13) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f3(C0, D0, E0) + w1_0 + 0x6ed9eba1, 15) + A0
    B1 = rol(B1 + f3(C1, D1, E1) + w1_1 + 0x6ed9eba1, 15) + A1
    B2 = rol(B2 + f3(C2, D2, E2) + w1_2 + 0x6ed9eba1, 15) + A2
    B3 = rol(B3 + f3(C3, D3, E3) + w1_3 + 0x6ed9eba1, 15) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f3(B0, C0, D0) + w2_0 + 0x6ed9eba1, 14) + E0
    A1 = rol(A1 + f3(B1, C1, D1) + w2_1 + 0x6ed9eba1, 14) + E1
    A2 = rol(A2 + f3(B2, C2, D2) + w2_2 + 0x6ed9eba1, 14) + E2
    A3 = rol(A3 + f3(B3, C3, D3) + w2_3 + 0x6ed9eba1, 14) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f3(A0, B0, C0) + w7_0 + 0x6ed9eba1, 8) + D0
    E1 = rol(E1 + f3(A1, B1, C1) + w7_1 + 0x6ed9eba1, 8) + D1
    E2 = rol(E2 + f3(A2, B2, C2) + w7_2 + 0x6ed9eba1, 8) + D2
    E3 = rol(E3 + f3(A3, B3, C3) + w7_3 + 0x6ed9eba1, 8) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f3(E0, A0, B0) + w0_0 + 0x6ed9eba1, 13) + C0
    D1 = rol(D1 + f3(E1, A1, B1) + w0_1 + 0x6ed9eba1, 13) + C1
    D2 = rol(D2 + f3(E2, A2, B2) + w0_2 + 0x6ed9eba1, 13) + C2
    D3 = rol(D3 + f3(E3, A3, B3) + w0_3 + 0x6ed9eba1, 13) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f3(D0, E0, A0) + w6_0 + 0x6ed9eba1, 6) + B0
    C1 = rol(C1 + f3(D1, E1, A1) + w6_1 + 0x6ed9eba1, 6) + B1
    C2 = rol(C2 + f3(D2, E2, A2) + w6_2 + 0x6ed9eba1, 6) + B2
    C3 = rol(C3 + f3(D3, E3, A3) + w6_3 + 0x6ed9eba1, 6) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f3(C0, D0, E0) + w13_0 + 0x6ed9eba1, 5) + A0
    B1 = rol(B1 + f3(C1, D1, E1) + w13_1 + 0x6ed9eba1, 5) + A1
    B2 = rol(B2 + f3(C2, D2, E2) + w13_2 + 0x6ed9eba1, 5) + A2
    B3 = rol(B3 + f3(C3, D3, E3) + w13_3 + 0x6ed9eba1, 5) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f3(B0, C0, D0) + w11_0 + 0x6ed9eba1, 12) + E0
    A1 = rol(A1 + f3(B1, C1, D1) + w11_1 + 0x6ed9eba1, 12) + E1
    A2 = rol(A2 + f3(B2, C2, D2) + w11_2 + 0x6ed9eba1, 12) + E2
    A3 = rol(A3 + f3(B3, C3, D3) + w11_3 + 0x6ed9eba1, 12) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f3(A0, B0, C0) + w5_0 + 0x6ed9eba1, 7) + D0
    E1 = rol(E1 + f3(A1, B1, C1) + w5_1 + 0x6ed9eba1, 7) + D1
    E2 = rol(E2 + f3(A2, B2, C2) + w5_2 + 0x6ed9eba1, 7) + D2
    E3 = rol(E3 + f3(A3, B3, C3) + w5_3 + 0x6ed9eba1, 7) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f3(E0, A0, B0) + w12_0 + 0x6ed9eba1, 5) + C0
    D1 = rol(D1 + f3(E1, A1, B1) + w12_1 + 0x6ed9eba1, 5) + C1
    D2 = rol(D2 + f3(E2, A2, B2) + w12_2 + 0x6ed9eba1, 5) + C2
    D3 = rol(D3 + f3(E3, A3, B3) + w12_3 + 0x6ed9eba1, 5) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f4(D0, E0, A0) + w1_0 + 0x8f1bbcdc, 11) + B0
    C1 = rol(C1 + f4(D1, E1, A1) + w1_1 + 0x8f1bbcdc, 11) + B1
    C2 = rol(C2 + f4(D2, E2, A2) + w1_2 + 0x8f1bbcdc, 11) + B2
    C3 = rol(C3 + f4(D3, E3, A3) + w1_3 + 0x8f1bbcdc, 11) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f4(C0, D0, E0) + w9_0 + 0x8f1bbcdc, 12) + A0
    B1 = rol(B1 + f4(C1, D1, E1) + w9_1 + 0x8f1bbcdc, 12) + A1
    B2 = rol(B2 + f4(C2, D2, E2) + w9_2 + 0x8f1bbcdc, 12) + A2
    B3 = rol(B3 + f4(C3, D3, E3) + w9_3 + 0x8f1bbcdc, 12) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f4(B0, C0, D0) + w11_0 + 0x8f1bbcdc, 14) + E0
    A1 = rol(A1 + f4(B1, C1, D1) + w11_1 + 0x8f1bbcdc, 14) + E1
    A2 = rol(A2 + f4(B2, C2, D2) + w11_2 + 0x8f1bbcdc, 14) + E2
    A3 = rol(A3 + f4(B3, C3, D3) + w11_3 + 0x8f1bbcdc, 14) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f4(A0, B0, C0) + w10_0 + 0x8f1bbcdc, 15) + D0
    E1 = rol(E1 + f4(A1, B1, C1) + w10_1 + 0x8f1bbcdc, 15) + D1
    E2 = rol(E2 + f4(A2, B2, C2) + w10_2 + 0x8f1bbcdc, 15) + D2
    E3 = rol(E3 + f4(A3, B3, C3) + w10_3 + 0x8f1bbcdc, 15) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f4(E0, A0, B0) + w0_0 + 0x8f1bbcdc, 14) + C0
    D1 = rol(D1 + f4(E1, A1, B1) + w0_1 + 0x8f1bbcdc, 14) + C1
    D2 = rol(D2 + f4(E2, A2, B2) + w0_2 + 0x8f1bbcdc, 14) + C2
    D3 = rol(D3 + f4(E3, A3, B3) + w0_3 + 0x8f1bbcdc, 14) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f4(D0, E0, A0) + w8_0 + 0x8f1bbcdc, 15) + B0
    C1 = rol(C1 + f4(D1, E1, A1) + w8_1 + 0x8f1bbcdc, 15) + B1
    C2 = rol(C2 + f4(D2, E2, A2) + w8_2 + 0x8f1bbcdc, 15) + B2
    C3 = rol(C3 + f4(D3, E3, A3) + w8_3 + 0x8f1bbcdc, 15) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f4(C0, D0, E0) + w12_0 + 0x8f1bbcdc, 9) + A0
    B1 = rol(B1 + f4(C1, D1, E1) + w12_1 + 0x8f1bbcdc, 9) + A1
    B2 = rol(B2 + f4(C2, D2, E2) + w12_2 + 0x8f1bbcdc, 9) + A2
    B3 = rol(B3 + f4(C3, D3, E3) + w12_3 + 0x8f1bbcdc, 9) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f4(B0, C0, D0) + w4_0 + 0x8f1bbcdc, 8) + E0
    A1 = rol(A1 + f4(B1, C1, D1) + w4_1 + 0x8f1bbcdc, 8) + E1
    A2 = rol(A2 + f4(B2, C2, D2) + w4_2 + 0x8f1bbcdc, 8) + E2
    A3 = rol(A3 + f4(B3, C3, D3) + w4_3 + 0x8f1bbcdc, 8) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f4(A0, B0, C0) + w13_0 + 0x8f1bbcdc, 9) + D0
    E1 = rol(E1 + f4(A1, B1, C1) + w13_1 + 0x8f1bbcdc, 9) + D1
    E2 = rol(E2 + f4(A2, B2, C2) + w13_2 + 0x8f1bbcdc, 9) + D2
    E3 = rol(E3 + f4(A3, B3, C3) + w13_3 + 0x8f1bbcdc, 9) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f4(E0, A0, B0) + w3_0 + 0x8f1bbcdc, 14) + C0
    D1 = rol(D1 + f4(E1, A1, B1) + w3_1 + 0x8f1bbcdc, 14) + C1
    D2 = rol(D2 + f4(E2, A2, B2) + w3_2 + 0x8f1bbcdc, 14) + C2
    D3 = rol(D3 + f4(E3, A3, B3) + w3_3 + 0x8f1bbcdc, 14) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f4(D0, E0, A0) + w7_0 + 0x8f1bbcdc, 5) + B0
    C1 = rol(C1 + f4(D1, E1, A1) + w7_1 + 0x8f1bbcdc, 5) + B1
    C2 = rol(C2 + f4(D2, E2, A2) + w7_2 + 0x8f1bbcdc, 5) + B2
    C3 = rol(C3 + f4(D3, E3, A3) + w7_3 + 0x8f1bbcdc, 5) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f4(C0, D0, E0) + w15_0 + 0x8f1bbcdc, 6) + A0
    B1 = rol(B1 + f4(C1, D1, E1) + w15_1 + 0x8f1bbcdc, 6) + A1
    B2 = rol(B2 + f4(C2, D2, E2) + w15_2 + 0x8f1bbcdc, 6) + A2
    B3 = rol(B3 + f4(C3, D3, E3) + w15_3 + 0x8f1bbcdc, 6) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f4(B0, C0, D0) + w14_0 + 0x8f1bbcdc, 8) + E0
    A1 = rol(A1 + f4(B1, C1, D1) + w14_1 + 0x8f1bbcdc, 8) + E1
    A2 = rol(A2 + f4(B2, C2, D2) + w14_2 + 0x8f1bbcdc, 8) + E2
    A3 = rol(A3 + f4(B3, C3, D3) + w14_3 + 0x8f1bbcdc, 8) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f4(A0, B0, C0) + w5_0 + 0x8f1bbcdc, 6) + D0
    E1 = rol(E1 + f4(A1, B1, C1) + w5_1 + 0x8f1bbcdc, 6) + D1
    E2 = rol(E2 + f4(A2, B2, C2) + w5_2 + 0x8f1bbcdc, 6) + D2
    E3 = rol(E3 + f4(A3, B3, C3) + w5_3 + 0x8f1bbcdc, 6) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f4(E0, A0, B0) + w6_0 + 0x8f1bbcdc, 5) + C0
    D1 = rol(D1 + f4(E1, A1, B1) + w6_1 + 0x8f1bbcdc, 5) + C1
    D2 = rol(D2 + f4(E2, A2, B2) + w6_2 + 0x8f1bbcdc, 5) + C2
    D3 = rol(D3 + f4(E3, A3, B3) + w6_3 + 0x8f1bbcdc, 5) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f4(D0, E0, A0) + w2_0 + 0x8f1bbcdc, 12) + B0
    C1 = rol(C1 + f4(D1, E1, A1) + w2_1 + 0x8f1bbcdc, 12) + B1
    C2 = rol(C2 + f4(D2, E2, A2) + w2_2 + 0x8f1bbcdc, 12) + B2
    C3 = rol(C3 + f4(D3, E3, A3) + w2_3 + 0x8f1bbcdc, 12) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f5(C0, D0, E0) + w4_0 + 0xa953fd4e, 9) + A0
    B1 = rol(B1 + f5(C1, D1, E1) + w4_1 + 0xa953fd4e, 9) + A1
    B2 = rol(B2 + f5(C2, D2, E2) + w4_2 + 0xa953fd4e, 9) + A2
    B3 = rol(B3 + f5(C3, D3, E3) + w4_3 + 0xa953fd4e, 9) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f5(B0, C0, D0) + w0_0 + 0xa953fd4e, 15) + E0
    A1 = rol(A1 + f5(B1, C1, D1) + w0_1 + 0xa953fd4e, 15) + E1
    A2 = rol(A2 + f5(B2, C2, D2) + w0_2 + 0xa953fd4e, 15) + E2
    A3 = rol(A3 + f5(B3, C3, D3) + w0_3 + 0xa953fd4e, 15) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f5(A0, B0, C0) + w5_0 + 0xa953fd4e, 5) + D0
    E1 = rol(E1 + f5(A1, B1, C1) + w5_1 + 0xa953fd4e, 5) + D1
    E2 = rol(E2 + f5(A2, B2, C2) + w5_2 + 0xa953fd4e, 5) + D2
    E3 = rol(E3 + f5(A3, B3, C3) + w5_3 + 0xa953fd4e, 5) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f5(E0, A0, B0) + w9_0 + 0xa953fd4e, 11) + C0
    D1 = rol(D1 + f5(E1, A1, B1) + w9_1 + 0xa953fd4e, 11) + C1
    D2 = rol(D2 + f5(E2, A2, B2) + w9_2 + 0xa953fd4e, 11) + C2
    D3 = rol(D3 + f5(E3, A3, B3) + w9_3 + 0xa953fd4e, 11) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f5(D0, E0, A0) + w7_0 + 0xa953fd4e, 6) + B0
    C1 = rol(C1 + f5(D1, E1, A1) + w7_1 + 0xa953fd4e, 6) + B1
    C2 = rol(C2 + f5(D2, E2, A2) + w7_2 + 0xa953fd4e, 6) + B2
    C3 = rol(C3 + f5(D3, E3, A3) + w7_3 + 0xa953fd4e, 6) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f5(C0, D0, E0) + w12_0 + 0xa953fd4e, 8) + A0
    B1 = rol(B1 + f5(C1, D1, E1) + w12_1 + 0xa953fd4e, 8) + A1
    B2 = rol(B2 + f5(C2, D2, E2) + w12_2 + 0xa953fd4e, 8) + A2
    B3 = rol(B3 + f5(C3, D3, E3) + w12_3 + 0xa953fd4e, 8) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f5(B0, C0, D0) + w2_0 + 0xa953fd4e, 13) + E0
    A1 = rol(A1 + f5(B1, C1, D1) + w2_1 + 0xa953fd4e, 13) + E1
    A2 = rol(A2 + f5(B2, C2, D2) + w2_2 + 0xa953fd4e, 13) + E2
    A3 = rol(A3 + f5(B3, C3, D3) + w2_3 + 0xa953fd4e, 13) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f5(A0, B0, C0) + w10_0 + 0xa953fd4e, 12) + D0
    E1 = rol(E1 + f5(A1, B1, C1) + w10_1 + 0xa953fd4e, 12) + D1
    E2 = rol(E2 + f5(A2, B2, C2) + w10_2 + 0xa953fd4e, 12) + D2
    E3 = rol(E3 + f5(A3, B3, C3) + w10_3 + 0xa953fd4e, 12) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f5(E0, A0, B0) + w14_0 + 0xa953fd4e, 5) + C0
    D1 = rol(D1 + f5(E1, A1, B1) + w14_1 + 0xa953fd4e, 5) + C1
    D2 = rol(D2 + f5(E2, A2, B2) + w14_2 + 0xa953fd4e, 5) + C2
    D3 = rol(D3 + f5(E3, A3, B3) + w14_3 + 0xa953fd4e, 5) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f5(D0, E0, A0) + w1_0 + 0xa953fd4e, 12) + B0
    C1 = rol(C1 + f5(D1, E1, A1) + w1_1 + 0xa953fd4e, 12) + B1
    C2 = rol(C2 + f5(D2, E2, A2) + w1_2 + 0xa953fd4e, 12) + B2
    C3 = rol(C3 + f5(D3, E3, A3) + w1_3 + 0xa953fd4e, 12) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f5(C0, D0, E0) + w3_0 + 0xa953fd4e, 13) + A0
    B1 = rol(B1 + f5(C1, D1, E1) + w3_1 + 0xa953fd4e, 13) + A1
    B2 = rol(B2 + f5(C2, D2, E2) + w3_2 + 0xa953fd4e, 13) + A2
    B3 = rol(B3 + f5(C3, D3, E3) + w3_3 + 0xa953fd4e, 13) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    A0 = rol(A0 + f5(B0, C0, D0) + w8_0 + 0xa953fd4e, 14) + E0
    A1 = rol(A1 + f5(B1, C1, D1) + w8_1 + 0xa953fd4e, 14) + E1
    A2 = rol(A2 + f5(B2, C2, D2) + w8_2 + 0xa953fd4e, 14) + E2
    A3 = rol(A3 + f5(B3, C3, D3) + w8_3 + 0xa953fd4e, 14) + E3
    C0 = rol(C0, 10)
    C1 = rol(C1, 10)
    C2 = rol(C2, 10)
    C3 = rol(C3, 10)

    E0 = rol(E0 + f5(A0, B0, C0) + w11_0 + 0xa953fd4e, 11) + D0
    E1 = rol(E1 + f5(A1, B1, C1) + w11_1 + 0xa953fd4e, 11) + D1
    E2 = rol(E2 + f5(A2, B2, C2) + w11_2 + 0xa953fd4e, 11) + D2
    E3 = rol(E3 + f5(A3, B3, C3) + w11_3 + 0xa953fd4e, 11) + D3
    B0 = rol(B0, 10)
    B1 = rol(B1, 10)
    B2 = rol(B2, 10)
    B3 = rol(B3, 10)

    D0 = rol(D0 + f5(E0, A0, B0) + w6_0 + 0xa953fd4e, 8) + C0
    D1 = rol(D1 + f5(E1, A1, B1) + w6_1 + 0xa953fd4e, 8) + C1
    D2 = rol(D2 + f5(E2, A2, B2) + w6_2 + 0xa953fd4e, 8) + C2
    D3 = rol(D3 + f5(E3, A3, B3) + w6_3 + 0xa953fd4e, 8) + C3
    A0 = rol(A0, 10)
    A1 = rol(A1, 10)
    A2 = rol(A2, 10)
    A3 = rol(A3, 10)

    C0 = rol(C0 + f5(D0, E0, A0) + w15_0 + 0xa953fd4e, 5) + B0
    C1 = rol(C1 + f5(D1, E1, A1) + w15_1 + 0xa953fd4e, 5) + B1
    C2 = rol(C2 + f5(D2, E2, A2) + w15_2 + 0xa953fd4e, 5) + B2
    C3 = rol(C3 + f5(D3, E3, A3) + w15_3 + 0xa953fd4e, 5) + B3
    E0 = rol(E0, 10)
    E1 = rol(E1, 10)
    E2 = rol(E2, 10)
    E3 = rol(E3, 10)

    B0 = rol(B0 + f5(C0, D0, E0) + w13_0 + 0xa953fd4e, 6) + A0
    B1 = rol(B1 + f5(C1, D1, E1) + w13_1 + 0xa953fd4e, 6) + A1
    B2 = rol(B2 + f5(C2, D2, E2) + w13_2 + 0xa953fd4e, 6) + A2
    B3 = rol(B3 + f5(C3, D3, E3) + w13_3 + 0xa953fd4e, 6) + A3
    D0 = rol(D0, 10)
    D1 = rol(D1, 10)
    D2 = rol(D2, 10)
    D3 = rol(D3, 10)

    Ap0 = rol(Ap0 + f5(Bp0, Cp0, Dp0) + w5_0 + 0x50a28be6, 8) + Ep0
    Ap1 = rol(Ap1 + f5(Bp1, Cp1, Dp1) + w5_1 + 0x50a28be6, 8) + Ep1
    Ap2 = rol(Ap2 + f5(Bp2, Cp2, Dp2) + w5_2 + 0x50a28be6, 8) + Ep2
    Ap3 = rol(Ap3 + f5(Bp3, Cp3, Dp3) + w5_3 + 0x50a28be6, 8) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f5(Ap0, Bp0, Cp0) + w14_0 + 0x50a28be6, 9) + Dp0
    Ep1 = rol(Ep1 + f5(Ap1, Bp1, Cp1) + w14_1 + 0x50a28be6, 9) + Dp1
    Ep2 = rol(Ep2 + f5(Ap2, Bp2, Cp2) + w14_2 + 0x50a28be6, 9) + Dp2
    Ep3 = rol(Ep3 + f5(Ap3, Bp3, Cp3) + w14_3 + 0x50a28be6, 9) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f5(Ep0, Ap0, Bp0) + w7_0 + 0x50a28be6, 9) + Cp0
    Dp1 = rol(Dp1 + f5(Ep1, Ap1, Bp1) + w7_1 + 0x50a28be6, 9) + Cp1
    Dp2 = rol(Dp2 + f5(Ep2, Ap2, Bp2) + w7_2 + 0x50a28be6, 9) + Cp2
    Dp3 = rol(Dp3 + f5(Ep3, Ap3, Bp3) + w7_3 + 0x50a28be6, 9) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f5(Dp0, Ep0, Ap0) + w0_0 + 0x50a28be6, 11) + Bp0
    Cp1 = rol(Cp1 + f5(Dp1, Ep1, Ap1) + w0_1 + 0x50a28be6, 11) + Bp1
    Cp2 = rol(Cp2 + f5(Dp2, Ep2, Ap2) + w0_2 + 0x50a28be6, 11) + Bp2
    Cp3 = rol(Cp3 + f5(Dp3, Ep3, Ap3) + w0_3 + 0x50a28be6, 11) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f5(Cp0, Dp0, Ep0) + w9_0 + 0x50a28be6, 13) + Ap0
    Bp1 = rol(Bp1 + f5(Cp1, Dp1, Ep1) + w9_1 + 0x50a28be6, 13) + Ap1
    Bp2 = rol(Bp2 + f5(Cp2, Dp2, Ep2) + w9_2 + 0x50a28be6, 13) + Ap2
    Bp3 = rol(Bp3 + f5(Cp3, Dp3, Ep3) + w9_3 + 0x50a28be6, 13) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f5(Bp0, Cp0, Dp0) + w2_0 + 0x50a28be6, 15) + Ep0
    Ap1 = rol(Ap1 + f5(Bp1, Cp1, Dp1) + w2_1 + 0x50a28be6, 15) + Ep1
    Ap2 = rol(Ap2 + f5(Bp2, Cp2, Dp2) + w2_2 + 0x50a28be6, 15) + Ep2
    Ap3 = rol(Ap3 + f5(Bp3, Cp3, Dp3) + w2_3 + 0x50a28be6, 15) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f5(Ap0, Bp0, Cp0) + w11_0 + 0x50a28be6, 15) + Dp0
    Ep1 = rol(Ep1 + f5(Ap1, Bp1, Cp1) + w11_1 + 0x50a28be6, 15) + Dp1
    Ep2 = rol(Ep2 + f5(Ap2, Bp2, Cp2) + w11_2 + 0x50a28be6, 15) + Dp2
    Ep3 = rol(Ep3 + f5(Ap3, Bp3, Cp3) + w11_3 + 0x50a28be6, 15) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f5(Ep0, Ap0, Bp0) + w4_0 + 0x50a28be6, 5) + Cp0
    Dp1 = rol(Dp1 + f5(Ep1, Ap1, Bp1) + w4_1 + 0x50a28be6, 5) + Cp1
    Dp2 = rol(Dp2 + f5(Ep2, Ap2, Bp2) + w4_2 + 0x50a28be6, 5) + Cp2
    Dp3 = rol(Dp3 + f5(Ep3, Ap3, Bp3) + w4_3 + 0x50a28be6, 5) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f5(Dp0, Ep0, Ap0) + w13_0 + 0x50a28be6, 7) + Bp0
    Cp1 = rol(Cp1 + f5(Dp1, Ep1, Ap1) + w13_1 + 0x50a28be6, 7) + Bp1
    Cp2 = rol(Cp2 + f5(Dp2, Ep2, Ap2) + w13_2 + 0x50a28be6, 7) + Bp2
    Cp3 = rol(Cp3 + f5(Dp3, Ep3, Ap3) + w13_3 + 0x50a28be6, 7) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f5(Cp0, Dp0, Ep0) + w6_0 + 0x50a28be6, 7) + Ap0
    Bp1 = rol(Bp1 + f5(Cp1, Dp1, Ep1) + w6_1 + 0x50a28be6, 7) + Ap1
    Bp2 = rol(Bp2 + f5(Cp2, Dp2, Ep2) + w6_2 + 0x50a28be6, 7) + Ap2
    Bp3 = rol(Bp3 + f5(Cp3, Dp3, Ep3) + w6_3 + 0x50a28be6, 7) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f5(Bp0, Cp0, Dp0) + w15_0 + 0x50a28be6, 8) + Ep0
    Ap1 = rol(Ap1 + f5(Bp1, Cp1, Dp1) + w15_1 + 0x50a28be6, 8) + Ep1
    Ap2 = rol(Ap2 + f5(Bp2, Cp2, Dp2) + w15_2 + 0x50a28be6, 8) + Ep2
    Ap3 = rol(Ap3 + f5(Bp3, Cp3, Dp3) + w15_3 + 0x50a28be6, 8) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f5(Ap0, Bp0, Cp0) + w8_0 + 0x50a28be6, 11) + Dp0
    Ep1 = rol(Ep1 + f5(Ap1, Bp1, Cp1) + w8_1 + 0x50a28be6, 11) + Dp1
    Ep2 = rol(Ep2 + f5(Ap2, Bp2, Cp2) + w8_2 + 0x50a28be6, 11) + Dp2
    Ep3 = rol(Ep3 + f5(Ap3, Bp3, Cp3) + w8_3 + 0x50a28be6, 11) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f5(Ep0, Ap0, Bp0) + w1_0 + 0x50a28be6, 14) + Cp0
    Dp1 = rol(Dp1 + f5(Ep1, Ap1, Bp1) + w1_1 + 0x50a28be6, 14) + Cp1
    Dp2 = rol(Dp2 + f5(Ep2, Ap2, Bp2) + w1_2 + 0x50a28be6, 14) + Cp2
    Dp3 = rol(Dp3 + f5(Ep3, Ap3, Bp3) + w1_3 + 0x50a28be6, 14) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f5(Dp0, Ep0, Ap0) + w10_0 + 0x50a28be6, 14) + Bp0
    Cp1 = rol(Cp1 + f5(Dp1, Ep1, Ap1) + w10_1 + 0x50a28be6, 14) + Bp1
    Cp2 = rol(Cp2 + f5(Dp2, Ep2, Ap2) + w10_2 + 0x50a28be6, 14) + Bp2
    Cp3 = rol(Cp3 + f5(Dp3, Ep3, Ap3) + w10_3 + 0x50a28be6, 14) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f5(Cp0, Dp0, Ep0) + w3_0 + 0x50a28be6, 12) + Ap0
    Bp1 = rol(Bp1 + f5(Cp1, Dp1, Ep1) + w3_1 + 0x50a28be6, 12) + Ap1
    Bp2 = rol(Bp2 + f5(Cp2, Dp2, Ep2) + w3_2 + 0x50a28be6, 12) + Ap2
    Bp3 = rol(Bp3 + f5(Cp3, Dp3, Ep3) + w3_3 + 0x50a28be6, 12) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f5(Bp0, Cp0, Dp0) + w12_0 + 0x50a28be6, 6) + Ep0
    Ap1 = rol(Ap1 + f5(Bp1, Cp1, Dp1) + w12_1 + 0x50a28be6, 6) + Ep1
    Ap2 = rol(Ap2 + f5(Bp2, Cp2, Dp2) + w12_2 + 0x50a28be6, 6) + Ep2
    Ap3 = rol(Ap3 + f5(Bp3, Cp3, Dp3) + w12_3 + 0x50a28be6, 6) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f4(Ap0, Bp0, Cp0) + w6_0 + 0x5c4dd124, 9) + Dp0
    Ep1 = rol(Ep1 + f4(Ap1, Bp1, Cp1) + w6_1 + 0x5c4dd124, 9) + Dp1
    Ep2 = rol(Ep2 + f4(Ap2, Bp2, Cp2) + w6_2 + 0x5c4dd124, 9) + Dp2
    Ep3 = rol(Ep3 + f4(Ap3, Bp3, Cp3) + w6_3 + 0x5c4dd124, 9) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f4(Ep0, Ap0, Bp0) + w11_0 + 0x5c4dd124, 13) + Cp0
    Dp1 = rol(Dp1 + f4(Ep1, Ap1, Bp1) + w11_1 + 0x5c4dd124, 13) + Cp1
    Dp2 = rol(Dp2 + f4(Ep2, Ap2, Bp2) + w11_2 + 0x5c4dd124, 13) + Cp2
    Dp3 = rol(Dp3 + f4(Ep3, Ap3, Bp3) + w11_3 + 0x5c4dd124, 13) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f4(Dp0, Ep0, Ap0) + w3_0 + 0x5c4dd124, 15) + Bp0
    Cp1 = rol(Cp1 + f4(Dp1, Ep1, Ap1) + w3_1 + 0x5c4dd124, 15) + Bp1
    Cp2 = rol(Cp2 + f4(Dp2, Ep2, Ap2) + w3_2 + 0x5c4dd124, 15) + Bp2
    Cp3 = rol(Cp3 + f4(Dp3, Ep3, Ap3) + w3_3 + 0x5c4dd124, 15) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f4(Cp0, Dp0, Ep0) + w7_0 + 0x5c4dd124, 7) + Ap0
    Bp1 = rol(Bp1 + f4(Cp1, Dp1, Ep1) + w7_1 + 0x5c4dd124, 7) + Ap1
    Bp2 = rol(Bp2 + f4(Cp2, Dp2, Ep2) + w7_2 + 0x5c4dd124, 7) + Ap2
    Bp3 = rol(Bp3 + f4(Cp3, Dp3, Ep3) + w7_3 + 0x5c4dd124, 7) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f4(Bp0, Cp0, Dp0) + w0_0 + 0x5c4dd124, 12) + Ep0
    Ap1 = rol(Ap1 + f4(Bp1, Cp1, Dp1) + w0_1 + 0x5c4dd124, 12) + Ep1
    Ap2 = rol(Ap2 + f4(Bp2, Cp2, Dp2) + w0_2 + 0x5c4dd124, 12) + Ep2
    Ap3 = rol(Ap3 + f4(Bp3, Cp3, Dp3) + w0_3 + 0x5c4dd124, 12) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f4(Ap0, Bp0, Cp0) + w13_0 + 0x5c4dd124, 8) + Dp0
    Ep1 = rol(Ep1 + f4(Ap1, Bp1, Cp1) + w13_1 + 0x5c4dd124, 8) + Dp1
    Ep2 = rol(Ep2 + f4(Ap2, Bp2, Cp2) + w13_2 + 0x5c4dd124, 8) + Dp2
    Ep3 = rol(Ep3 + f4(Ap3, Bp3, Cp3) + w13_3 + 0x5c4dd124, 8) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f4(Ep0, Ap0, Bp0) + w5_0 + 0x5c4dd124, 9) + Cp0
    Dp1 = rol(Dp1 + f4(Ep1, Ap1, Bp1) + w5_1 + 0x5c4dd124, 9) + Cp1
    Dp2 = rol(Dp2 + f4(Ep2, Ap2, Bp2) + w5_2 + 0x5c4dd124, 9) + Cp2
    Dp3 = rol(Dp3 + f4(Ep3, Ap3, Bp3) + w5_3 + 0x5c4dd124, 9) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f4(Dp0, Ep0, Ap0) + w10_0 + 0x5c4dd124, 11) + Bp0
    Cp1 = rol(Cp1 + f4(Dp1, Ep1, Ap1) + w10_1 + 0x5c4dd124, 11) + Bp1
    Cp2 = rol(Cp2 + f4(Dp2, Ep2, Ap2) + w10_2 + 0x5c4dd124, 11) + Bp2
    Cp3 = rol(Cp3 + f4(Dp3, Ep3, Ap3) + w10_3 + 0x5c4dd124, 11) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f4(Cp0, Dp0, Ep0) + w14_0 + 0x5c4dd124, 7) + Ap0
    Bp1 = rol(Bp1 + f4(Cp1, Dp1, Ep1) + w14_1 + 0x5c4dd124, 7) + Ap1
    Bp2 = rol(Bp2 + f4(Cp2, Dp2, Ep2) + w14_2 + 0x5c4dd124, 7) + Ap2
    Bp3 = rol(Bp3 + f4(Cp3, Dp3, Ep3) + w14_3 + 0x5c4dd124, 7) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f4(Bp0, Cp0, Dp0) + w15_0 + 0x5c4dd124, 7) + Ep0
    Ap1 = rol(Ap1 + f4(Bp1, Cp1, Dp1) + w15_1 + 0x5c4dd124, 7) + Ep1
    Ap2 = rol(Ap2 + f4(Bp2, Cp2, Dp2) + w15_2 + 0x5c4dd124, 7) + Ep2
    Ap3 = rol(Ap3 + f4(Bp3, Cp3, Dp3) + w15_3 + 0x5c4dd124, 7) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f4(Ap0, Bp0, Cp0) + w8_0 + 0x5c4dd124, 12) + Dp0
    Ep1 = rol(Ep1 + f4(Ap1, Bp1, Cp1) + w8_1 + 0x5c4dd124, 12) + Dp1
    Ep2 = rol(Ep2 + f4(Ap2, Bp2, Cp2) + w8_2 + 0x5c4dd124, 12) + Dp2
    Ep3 = rol(Ep3 + f4(Ap3, Bp3, Cp3) + w8_3 + 0x5c4dd124, 12) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f4(Ep0, Ap0, Bp0) + w12_0 + 0x5c4dd124, 7) + Cp0
    Dp1 = rol(Dp1 + f4(Ep1, Ap1, Bp1) + w12_1 + 0x5c4dd124, 7) + Cp1
    Dp2 = rol(Dp2 + f4(Ep2, Ap2, Bp2) + w12_2 + 0x5c4dd124, 7) + Cp2
    Dp3 = rol(Dp3 + f4(Ep3, Ap3, Bp3) + w12_3 + 0x5c4dd124, 7) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f4(Dp0, Ep0, Ap0) + w4_0 + 0x5c4dd124, 6) + Bp0
    Cp1 = rol(Cp1 + f4(Dp1, Ep1, Ap1) + w4_1 + 0x5c4dd124, 6) + Bp1
    Cp2 = rol(Cp2 + f4(Dp2, Ep2, Ap2) + w4_2 + 0x5c4dd124, 6) + Bp2
    Cp3 = rol(Cp3 + f4(Dp3, Ep3, Ap3) + w4_3 + 0x5c4dd124, 6) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f4(Cp0, Dp0, Ep0) + w9_0 + 0x5c4dd124, 15) + Ap0
    Bp1 = rol(Bp1 + f4(Cp1, Dp1, Ep1) + w9_1 + 0x5c4dd124, 15) + Ap1
    Bp2 = rol(Bp2 + f4(Cp2, Dp2, Ep2) + w9_2 + 0x5c4dd124, 15) + Ap2
    Bp3 = rol(Bp3 + f4(Cp3, Dp3, Ep3) + w9_3 + 0x5c4dd124, 15) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f4(Bp0, Cp0, Dp0) + w1_0 + 0x5c4dd124, 13) + Ep0
    Ap1 = rol(Ap1 + f4(Bp1, Cp1, Dp1) + w1_1 + 0x5c4dd124, 13) + Ep1
    Ap2 = rol(Ap2 + f4(Bp2, Cp2, Dp2) + w1_2 + 0x5c4dd124, 13) + Ep2
    Ap3 = rol(Ap3 + f4(Bp3, Cp3, Dp3) + w1_3 + 0x5c4dd124, 13) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f4(Ap0, Bp0, Cp0) + w2_0 + 0x5c4dd124, 11) + Dp0
    Ep1 = rol(Ep1 + f4(Ap1, Bp1, Cp1) + w2_1 + 0x5c4dd124, 11) + Dp1
    Ep2 = rol(Ep2 + f4(Ap2, Bp2, Cp2) + w2_2 + 0x5c4dd124, 11) + Dp2
    Ep3 = rol(Ep3 + f4(Ap3, Bp3, Cp3) + w2_3 + 0x5c4dd124, 11) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f3(Ep0, Ap0, Bp0) + w15_0 + 0x6d703ef3, 9) + Cp0
    Dp1 = rol(Dp1 + f3(Ep1, Ap1, Bp1) + w15_1 + 0x6d703ef3, 9) + Cp1
    Dp2 = rol(Dp2 + f3(Ep2, Ap2, Bp2) + w15_2 + 0x6d703ef3, 9) + Cp2
    Dp3 = rol(Dp3 + f3(Ep3, Ap3, Bp3) + w15_3 + 0x6d703ef3, 9) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f3(Dp0, Ep0, Ap0) + w5_0 + 0x6d703ef3, 7) + Bp0
    Cp1 = rol(Cp1 + f3(Dp1, Ep1, Ap1) + w5_1 + 0x6d703ef3, 7) + Bp1
    Cp2 = rol(Cp2 + f3(Dp2, Ep2, Ap2) + w5_2 + 0x6d703ef3, 7) + Bp2
    Cp3 = rol(Cp3 + f3(Dp3, Ep3, Ap3) + w5_3 + 0x6d703ef3, 7) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f3(Cp0, Dp0, Ep0) + w1_0 + 0x6d703ef3, 15) + Ap0
    Bp1 = rol(Bp1 + f3(Cp1, Dp1, Ep1) + w1_1 + 0x6d703ef3, 15) + Ap1
    Bp2 = rol(Bp2 + f3(Cp2, Dp2, Ep2) + w1_2 + 0x6d703ef3, 15) + Ap2
    Bp3 = rol(Bp3 + f3(Cp3, Dp3, Ep3) + w1_3 + 0x6d703ef3, 15) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f3(Bp0, Cp0, Dp0) + w3_0 + 0x6d703ef3, 11) + Ep0
    Ap1 = rol(Ap1 + f3(Bp1, Cp1, Dp1) + w3_1 + 0x6d703ef3, 11) + Ep1
    Ap2 = rol(Ap2 + f3(Bp2, Cp2, Dp2) + w3_2 + 0x6d703ef3, 11) + Ep2
    Ap3 = rol(Ap3 + f3(Bp3, Cp3, Dp3) + w3_3 + 0x6d703ef3, 11) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f3(Ap0, Bp0, Cp0) + w7_0 + 0x6d703ef3, 8) + Dp0
    Ep1 = rol(Ep1 + f3(Ap1, Bp1, Cp1) + w7_1 + 0x6d703ef3, 8) + Dp1
    Ep2 = rol(Ep2 + f3(Ap2, Bp2, Cp2) + w7_2 + 0x6d703ef3, 8) + Dp2
    Ep3 = rol(Ep3 + f3(Ap3, Bp3, Cp3) + w7_3 + 0x6d703ef3, 8) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f3(Ep0, Ap0, Bp0) + w14_0 + 0x6d703ef3, 6) + Cp0
    Dp1 = rol(Dp1 + f3(Ep1, Ap1, Bp1) + w14_1 + 0x6d703ef3, 6) + Cp1
    Dp2 = rol(Dp2 + f3(Ep2, Ap2, Bp2) + w14_2 + 0x6d703ef3, 6) + Cp2
    Dp3 = rol(Dp3 + f3(Ep3, Ap3, Bp3) + w14_3 + 0x6d703ef3, 6) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f3(Dp0, Ep0, Ap0) + w6_0 + 0x6d703ef3, 6) + Bp0
    Cp1 = rol(Cp1 + f3(Dp1, Ep1, Ap1) + w6_1 + 0x6d703ef3, 6) + Bp1
    Cp2 = rol(Cp2 + f3(Dp2, Ep2, Ap2) + w6_2 + 0x6d703ef3, 6) + Bp2
    Cp3 = rol(Cp3 + f3(Dp3, Ep3, Ap3) + w6_3 + 0x6d703ef3, 6) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f3(Cp0, Dp0, Ep0) + w9_0 + 0x6d703ef3, 14) + Ap0
    Bp1 = rol(Bp1 + f3(Cp1, Dp1, Ep1) + w9_1 + 0x6d703ef3, 14) + Ap1
    Bp2 = rol(Bp2 + f3(Cp2, Dp2, Ep2) + w9_2 + 0x6d703ef3, 14) + Ap2
    Bp3 = rol(Bp3 + f3(Cp3, Dp3, Ep3) + w9_3 + 0x6d703ef3, 14) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f3(Bp0, Cp0, Dp0) + w11_0 + 0x6d703ef3, 12) + Ep0
    Ap1 = rol(Ap1 + f3(Bp1, Cp1, Dp1) + w11_1 + 0x6d703ef3, 12) + Ep1
    Ap2 = rol(Ap2 + f3(Bp2, Cp2, Dp2) + w11_2 + 0x6d703ef3, 12) + Ep2
    Ap3 = rol(Ap3 + f3(Bp3, Cp3, Dp3) + w11_3 + 0x6d703ef3, 12) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f3(Ap0, Bp0, Cp0) + w8_0 + 0x6d703ef3, 13) + Dp0
    Ep1 = rol(Ep1 + f3(Ap1, Bp1, Cp1) + w8_1 + 0x6d703ef3, 13) + Dp1
    Ep2 = rol(Ep2 + f3(Ap2, Bp2, Cp2) + w8_2 + 0x6d703ef3, 13) + Dp2
    Ep3 = rol(Ep3 + f3(Ap3, Bp3, Cp3) + w8_3 + 0x6d703ef3, 13) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f3(Ep0, Ap0, Bp0) + w12_0 + 0x6d703ef3, 5) + Cp0
    Dp1 = rol(Dp1 + f3(Ep1, Ap1, Bp1) + w12_1 + 0x6d703ef3, 5) + Cp1
    Dp2 = rol(Dp2 + f3(Ep2, Ap2, Bp2) + w12_2 + 0x6d703ef3, 5) + Cp2
    Dp3 = rol(Dp3 + f3(Ep3, Ap3, Bp3) + w12_3 + 0x6d703ef3, 5) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f3(Dp0, Ep0, Ap0) + w2_0 + 0x6d703ef3, 14) + Bp0
    Cp1 = rol(Cp1 + f3(Dp1, Ep1, Ap1) + w2_1 + 0x6d703ef3, 14) + Bp1
    Cp2 = rol(Cp2 + f3(Dp2, Ep2, Ap2) + w2_2 + 0x6d703ef3, 14) + Bp2
    Cp3 = rol(Cp3 + f3(Dp3, Ep3, Ap3) + w2_3 + 0x6d703ef3, 14) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f3(Cp0, Dp0, Ep0) + w10_0 + 0x6d703ef3, 13) + Ap0
    Bp1 = rol(Bp1 + f3(Cp1, Dp1, Ep1) + w10_1 + 0x6d703ef3, 13) + Ap1
    Bp2 = rol(Bp2 + f3(Cp2, Dp2, Ep2) + w10_2 + 0x6d703ef3, 13) + Ap2
    Bp3 = rol(Bp3 + f3(Cp3, Dp3, Ep3) + w10_3 + 0x6d703ef3, 13) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f3(Bp0, Cp0, Dp0) + w0_0 + 0x6d703ef3, 13) + Ep0
    Ap1 = rol(Ap1 + f3(Bp1, Cp1, Dp1) + w0_1 + 0x6d703ef3, 13) + Ep1
    Ap2 = rol(Ap2 + f3(Bp2, Cp2, Dp2) + w0_2 + 0x6d703ef3, 13) + Ep2
    Ap3 = rol(Ap3 + f3(Bp3, Cp3, Dp3) + w0_3 + 0x6d703ef3, 13) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f3(Ap0, Bp0, Cp0) + w4_0 + 0x6d703ef3, 7) + Dp0
    Ep1 = rol(Ep1 + f3(Ap1, Bp1, Cp1) + w4_1 + 0x6d703ef3, 7) + Dp1
    Ep2 = rol(Ep2 + f3(Ap2, Bp2, Cp2) + w4_2 + 0x6d703ef3, 7) + Dp2
    Ep3 = rol(Ep3 + f3(Ap3, Bp3, Cp3) + w4_3 + 0x6d703ef3, 7) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f3(Ep0, Ap0, Bp0) + w13_0 + 0x6d703ef3, 5) + Cp0
    Dp1 = rol(Dp1 + f3(Ep1, Ap1, Bp1) + w13_1 + 0x6d703ef3, 5) + Cp1
    Dp2 = rol(Dp2 + f3(Ep2, Ap2, Bp2) + w13_2 + 0x6d703ef3, 5) + Cp2
    Dp3 = rol(Dp3 + f3(Ep3, Ap3, Bp3) + w13_3 + 0x6d703ef3, 5) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f2(Dp0, Ep0, Ap0) + w8_0 + 0x7a6d76e9, 15) + Bp0
    Cp1 = rol(Cp1 + f2(Dp1, Ep1, Ap1) + w8_1 + 0x7a6d76e9, 15) + Bp1
    Cp2 = rol(Cp2 + f2(Dp2, Ep2, Ap2) + w8_2 + 0x7a6d76e9, 15) + Bp2
    Cp3 = rol(Cp3 + f2(Dp3, Ep3, Ap3) + w8_3 + 0x7a6d76e9, 15) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f2(Cp0, Dp0, Ep0) + w6_0 + 0x7a6d76e9, 5) + Ap0
    Bp1 = rol(Bp1 + f2(Cp1, Dp1, Ep1) + w6_1 + 0x7a6d76e9, 5) + Ap1
    Bp2 = rol(Bp2 + f2(Cp2, Dp2, Ep2) + w6_2 + 0x7a6d76e9, 5) + Ap2
    Bp3 = rol(Bp3 + f2(Cp3, Dp3, Ep3) + w6_3 + 0x7a6d76e9, 5) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f2(Bp0, Cp0, Dp0) + w4_0 + 0x7a6d76e9, 8) + Ep0
    Ap1 = rol(Ap1 + f2(Bp1, Cp1, Dp1) + w4_1 + 0x7a6d76e9, 8) + Ep1
    Ap2 = rol(Ap2 + f2(Bp2, Cp2, Dp2) + w4_2 + 0x7a6d76e9, 8) + Ep2
    Ap3 = rol(Ap3 + f2(Bp3, Cp3, Dp3) + w4_3 + 0x7a6d76e9, 8) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f2(Ap0, Bp0, Cp0) + w1_0 + 0x7a6d76e9, 11) + Dp0
    Ep1 = rol(Ep1 + f2(Ap1, Bp1, Cp1) + w1_1 + 0x7a6d76e9, 11) + Dp1
    Ep2 = rol(Ep2 + f2(Ap2, Bp2, Cp2) + w1_2 + 0x7a6d76e9, 11) + Dp2
    Ep3 = rol(Ep3 + f2(Ap3, Bp3, Cp3) + w1_3 + 0x7a6d76e9, 11) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f2(Ep0, Ap0, Bp0) + w3_0 + 0x7a6d76e9, 14) + Cp0
    Dp1 = rol(Dp1 + f2(Ep1, Ap1, Bp1) + w3_1 + 0x7a6d76e9, 14) + Cp1
    Dp2 = rol(Dp2 + f2(Ep2, Ap2, Bp2) + w3_2 + 0x7a6d76e9, 14) + Cp2
    Dp3 = rol(Dp3 + f2(Ep3, Ap3, Bp3) + w3_3 + 0x7a6d76e9, 14) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f2(Dp0, Ep0, Ap0) + w11_0 + 0x7a6d76e9, 14) + Bp0
    Cp1 = rol(Cp1 + f2(Dp1, Ep1, Ap1) + w11_1 + 0x7a6d76e9, 14) + Bp1
    Cp2 = rol(Cp2 + f2(Dp2, Ep2, Ap2) + w11_2 + 0x7a6d76e9, 14) + Bp2
    Cp3 = rol(Cp3 + f2(Dp3, Ep3, Ap3) + w11_3 + 0x7a6d76e9, 14) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f2(Cp0, Dp0, Ep0) + w15_0 + 0x7a6d76e9, 6) + Ap0
    Bp1 = rol(Bp1 + f2(Cp1, Dp1, Ep1) + w15_1 + 0x7a6d76e9, 6) + Ap1
    Bp2 = rol(Bp2 + f2(Cp2, Dp2, Ep2) + w15_2 + 0x7a6d76e9, 6) + Ap2
    Bp3 = rol(Bp3 + f2(Cp3, Dp3, Ep3) + w15_3 + 0x7a6d76e9, 6) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f2(Bp0, Cp0, Dp0) + w0_0 + 0x7a6d76e9, 14) + Ep0
    Ap1 = rol(Ap1 + f2(Bp1, Cp1, Dp1) + w0_1 + 0x7a6d76e9, 14) + Ep1
    Ap2 = rol(Ap2 + f2(Bp2, Cp2, Dp2) + w0_2 + 0x7a6d76e9, 14) + Ep2
    Ap3 = rol(Ap3 + f2(Bp3, Cp3, Dp3) + w0_3 + 0x7a6d76e9, 14) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f2(Ap0, Bp0, Cp0) + w5_0 + 0x7a6d76e9, 6) + Dp0
    Ep1 = rol(Ep1 + f2(Ap1, Bp1, Cp1) + w5_1 + 0x7a6d76e9, 6) + Dp1
    Ep2 = rol(Ep2 + f2(Ap2, Bp2, Cp2) + w5_2 + 0x7a6d76e9, 6) + Dp2
    Ep3 = rol(Ep3 + f2(Ap3, Bp3, Cp3) + w5_3 + 0x7a6d76e9, 6) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f2(Ep0, Ap0, Bp0) + w12_0 + 0x7a6d76e9, 9) + Cp0
    Dp1 = rol(Dp1 + f2(Ep1, Ap1, Bp1) + w12_1 + 0x7a6d76e9, 9) + Cp1
    Dp2 = rol(Dp2 + f2(Ep2, Ap2, Bp2) + w12_2 + 0x7a6d76e9, 9) + Cp2
    Dp3 = rol(Dp3 + f2(Ep3, Ap3, Bp3) + w12_3 + 0x7a6d76e9, 9) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f2(Dp0, Ep0, Ap0) + w2_0 + 0x7a6d76e9, 12) + Bp0
    Cp1 = rol(Cp1 + f2(Dp1, Ep1, Ap1) + w2_1 + 0x7a6d76e9, 12) + Bp1
    Cp2 = rol(Cp2 + f2(Dp2, Ep2, Ap2) + w2_2 + 0x7a6d76e9, 12) + Bp2
    Cp3 = rol(Cp3 + f2(Dp3, Ep3, Ap3) + w2_3 + 0x7a6d76e9, 12) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f2(Cp0, Dp0, Ep0) + w13_0 + 0x7a6d76e9, 9) + Ap0
    Bp1 = rol(Bp1 + f2(Cp1, Dp1, Ep1) + w13_1 + 0x7a6d76e9, 9) + Ap1
    Bp2 = rol(Bp2 + f2(Cp2, Dp2, Ep2) + w13_2 + 0x7a6d76e9, 9) + Ap2
    Bp3 = rol(Bp3 + f2(Cp3, Dp3, Ep3) + w13_3 + 0x7a6d76e9, 9) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f2(Bp0, Cp0, Dp0) + w9_0 + 0x7a6d76e9, 12) + Ep0
    Ap1 = rol(Ap1 + f2(Bp1, Cp1, Dp1) + w9_1 + 0x7a6d76e9, 12) + Ep1
    Ap2 = rol(Ap2 + f2(Bp2, Cp2, Dp2) + w9_2 + 0x7a6d76e9, 12) + Ep2
    Ap3 = rol(Ap3 + f2(Bp3, Cp3, Dp3) + w9_3 + 0x7a6d76e9, 12) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f2(Ap0, Bp0, Cp0) + w7_0 + 0x7a6d76e9, 5) + Dp0
    Ep1 = rol(Ep1 + f2(Ap1, Bp1, Cp1) + w7_1 + 0x7a6d76e9, 5) + Dp1
    Ep2 = rol(Ep2 + f2(Ap2, Bp2, Cp2) + w7_2 + 0x7a6d76e9, 5) + Dp2
    Ep3 = rol(Ep3 + f2(Ap3, Bp3, Cp3) + w7_3 + 0x7a6d76e9, 5) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f2(Ep0, Ap0, Bp0) + w10_0 + 0x7a6d76e9, 15) + Cp0
    Dp1 = rol(Dp1 + f2(Ep1, Ap1, Bp1) + w10_1 + 0x7a6d76e9, 15) + Cp1
    Dp2 = rol(Dp2 + f2(Ep2, Ap2, Bp2) + w10_2 + 0x7a6d76e9, 15) + Cp2
    Dp3 = rol(Dp3 + f2(Ep3, Ap3, Bp3) + w10_3 + 0x7a6d76e9, 15) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f2(Dp0, Ep0, Ap0) + w14_0 + 0x7a6d76e9, 8) + Bp0
    Cp1 = rol(Cp1 + f2(Dp1, Ep1, Ap1) + w14_1 + 0x7a6d76e9, 8) + Bp1
    Cp2 = rol(Cp2 + f2(Dp2, Ep2, Ap2) + w14_2 + 0x7a6d76e9, 8) + Bp2
    Cp3 = rol(Cp3 + f2(Dp3, Ep3, Ap3) + w14_3 + 0x7a6d76e9, 8) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f1(Cp0, Dp0, Ep0) + w12_0 + 0x00000000, 8) + Ap0
    Bp1 = rol(Bp1 + f1(Cp1, Dp1, Ep1) + w12_1 + 0x00000000, 8) + Ap1
    Bp2 = rol(Bp2 + f1(Cp2, Dp2, Ep2) + w12_2 + 0x00000000, 8) + Ap2
    Bp3 = rol(Bp3 + f1(Cp3, Dp3, Ep3) + w12_3 + 0x00000000, 8) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f1(Bp0, Cp0, Dp0) + w15_0 + 0x00000000, 5) + Ep0
    Ap1 = rol(Ap1 + f1(Bp1, Cp1, Dp1) + w15_1 + 0x00000000, 5) + Ep1
    Ap2 = rol(Ap2 + f1(Bp2, Cp2, Dp2) + w15_2 + 0x00000000, 5) + Ep2
    Ap3 = rol(Ap3 + f1(Bp3, Cp3, Dp3) + w15_3 + 0x00000000, 5) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f1(Ap0, Bp0, Cp0) + w10_0 + 0x00000000, 12) + Dp0
    Ep1 = rol(Ep1 + f1(Ap1, Bp1, Cp1) + w10_1 + 0x00000000, 12) + Dp1
    Ep2 = rol(Ep2 + f1(Ap2, Bp2, Cp2) + w10_2 + 0x00000000, 12) + Dp2
    Ep3 = rol(Ep3 + f1(Ap3, Bp3, Cp3) + w10_3 + 0x00000000, 12) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f1(Ep0, Ap0, Bp0) + w4_0 + 0x00000000, 9) + Cp0
    Dp1 = rol(Dp1 + f1(Ep1, Ap1, Bp1) + w4_1 + 0x00000000, 9) + Cp1
    Dp2 = rol(Dp2 + f1(Ep2, Ap2, Bp2) + w4_2 + 0x00000000, 9) + Cp2
    Dp3 = rol(Dp3 + f1(Ep3, Ap3, Bp3) + w4_3 + 0x00000000, 9) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f1(Dp0, Ep0, Ap0) + w1_0 + 0x00000000, 12) + Bp0
    Cp1 = rol(Cp1 + f1(Dp1, Ep1, Ap1) + w1_1 + 0x00000000, 12) + Bp1
    Cp2 = rol(Cp2 + f1(Dp2, Ep2, Ap2) + w1_2 + 0x00000000, 12) + Bp2
    Cp3 = rol(Cp3 + f1(Dp3, Ep3, Ap3) + w1_3 + 0x00000000, 12) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f1(Cp0, Dp0, Ep0) + w5_0 + 0x00000000, 5) + Ap0
    Bp1 = rol(Bp1 + f1(Cp1, Dp1, Ep1) + w5_1 + 0x00000000, 5) + Ap1
    Bp2 = rol(Bp2 + f1(Cp2, Dp2, Ep2) + w5_2 + 0x00000000, 5) + Ap2
    Bp3 = rol(Bp3 + f1(Cp3, Dp3, Ep3) + w5_3 + 0x00000000, 5) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f1(Bp0, Cp0, Dp0) + w8_0 + 0x00000000, 14) + Ep0
    Ap1 = rol(Ap1 + f1(Bp1, Cp1, Dp1) + w8_1 + 0x00000000, 14) + Ep1
    Ap2 = rol(Ap2 + f1(Bp2, Cp2, Dp2) + w8_2 + 0x00000000, 14) + Ep2
    Ap3 = rol(Ap3 + f1(Bp3, Cp3, Dp3) + w8_3 + 0x00000000, 14) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f1(Ap0, Bp0, Cp0) + w7_0 + 0x00000000, 6) + Dp0
    Ep1 = rol(Ep1 + f1(Ap1, Bp1, Cp1) + w7_1 + 0x00000000, 6) + Dp1
    Ep2 = rol(Ep2 + f1(Ap2, Bp2, Cp2) + w7_2 + 0x00000000, 6) + Dp2
    Ep3 = rol(Ep3 + f1(Ap3, Bp3, Cp3) + w7_3 + 0x00000000, 6) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f1(Ep0, Ap0, Bp0) + w6_0 + 0x00000000, 8) + Cp0
    Dp1 = rol(Dp1 + f1(Ep1, Ap1, Bp1) + w6_1 + 0x00000000, 8) + Cp1
    Dp2 = rol(Dp2 + f1(Ep2, Ap2, Bp2) + w6_2 + 0x00000000, 8) + Cp2
    Dp3 = rol(Dp3 + f1(Ep3, Ap3, Bp3) + w6_3 + 0x00000000, 8) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f1(Dp0, Ep0, Ap0) + w2_0 + 0x00000000, 13) + Bp0
    Cp1 = rol(Cp1 + f1(Dp1, Ep1, Ap1) + w2_1 + 0x00000000, 13) + Bp1
    Cp2 = rol(Cp2 + f1(Dp2, Ep2, Ap2) + w2_2 + 0x00000000, 13) + Bp2
    Cp3 = rol(Cp3 + f1(Dp3, Ep3, Ap3) + w2_3 + 0x00000000, 13) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f1(Cp0, Dp0, Ep0) + w13_0 + 0x00000000, 6) + Ap0
    Bp1 = rol(Bp1 + f1(Cp1, Dp1, Ep1) + w13_1 + 0x00000000, 6) + Ap1
    Bp2 = rol(Bp2 + f1(Cp2, Dp2, Ep2) + w13_2 + 0x00000000, 6) + Ap2
    Bp3 = rol(Bp3 + f1(Cp3, Dp3, Ep3) + w13_3 + 0x00000000, 6) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    Ap0 = rol(Ap0 + f1(Bp0, Cp0, Dp0) + w14_0 + 0x00000000, 5) + Ep0
    Ap1 = rol(Ap1 + f1(Bp1, Cp1, Dp1) + w14_1 + 0x00000000, 5) + Ep1
    Ap2 = rol(Ap2 + f1(Bp2, Cp2, Dp2) + w14_2 + 0x00000000, 5) + Ep2
    Ap3 = rol(Ap3 + f1(Bp3, Cp3, Dp3) + w14_3 + 0x00000000, 5) + Ep3
    Cp0 = rol(Cp0, 10)
    Cp1 = rol(Cp1, 10)
    Cp2 = rol(Cp2, 10)
    Cp3 = rol(Cp3, 10)

    Ep0 = rol(Ep0 + f1(Ap0, Bp0, Cp0) + w0_0 + 0x00000000, 15) + Dp0
    Ep1 = rol(Ep1 + f1(Ap1, Bp1, Cp1) + w0_1 + 0x00000000, 15) + Dp1
    Ep2 = rol(Ep2 + f1(Ap2, Bp2, Cp2) + w0_2 + 0x00000000, 15) + Dp2
    Ep3 = rol(Ep3 + f1(Ap3, Bp3, Cp3) + w0_3 + 0x00000000, 15) + Dp3
    Bp0 = rol(Bp0, 10)
    Bp1 = rol(Bp1, 10)
    Bp2 = rol(Bp2, 10)
    Bp3 = rol(Bp3, 10)

    Dp0 = rol(Dp0 + f1(Ep0, Ap0, Bp0) + w3_0 + 0x00000000, 13) + Cp0
    Dp1 = rol(Dp1 + f1(Ep1, Ap1, Bp1) + w3_1 + 0x00000000, 13) + Cp1
    Dp2 = rol(Dp2 + f1(Ep2, Ap2, Bp2) + w3_2 + 0x00000000, 13) + Cp2
    Dp3 = rol(Dp3 + f1(Ep3, Ap3, Bp3) + w3_3 + 0x00000000, 13) + Cp3
    Ap0 = rol(Ap0, 10)
    Ap1 = rol(Ap1, 10)
    Ap2 = rol(Ap2, 10)
    Ap3 = rol(Ap3, 10)

    Cp0 = rol(Cp0 + f1(Dp0, Ep0, Ap0) + w9_0 + 0x00000000, 11) + Bp0
    Cp1 = rol(Cp1 + f1(Dp1, Ep1, Ap1) + w9_1 + 0x00000000, 11) + Bp1
    Cp2 = rol(Cp2 + f1(Dp2, Ep2, Ap2) + w9_2 + 0x00000000, 11) + Bp2
    Cp3 = rol(Cp3 + f1(Dp3, Ep3, Ap3) + w9_3 + 0x00000000, 11) + Bp3
    Ep0 = rol(Ep0, 10)
    Ep1 = rol(Ep1, 10)
    Ep2 = rol(Ep2, 10)
    Ep3 = rol(Ep3, 10)

    Bp0 = rol(Bp0 + f1(Cp0, Dp0, Ep0) + w11_0 + 0x00000000, 11) + Ap0
    Bp1 = rol(Bp1 + f1(Cp1, Dp1, Ep1) + w11_1 + 0x00000000, 11) + Ap1
    Bp2 = rol(Bp2 + f1(Cp2, Dp2, Ep2) + w11_2 + 0x00000000, 11) + Ap2
    Bp3 = rol(Bp3 + f1(Cp3, Dp3, Ep3) + w11_3 + 0x00000000, 11) + Ap3
    Dp0 = rol(Dp0, 10)
    Dp1 = rol(Dp1, 10)
    Dp2 = rol(Dp2, 10)
    Dp3 = rol(Dp3, 10)

    h0__0 = UInt32(0x67452301); h1__0 = UInt32(0xefcdab89); h2__0 = UInt32(0x98badcfe); h3__0 = UInt32(0x10325476); h4__0 = UInt32(0xc3d2e1f0)
    h0__1 = UInt32(0x67452301); h1__1 = UInt32(0xefcdab89); h2__1 = UInt32(0x98badcfe); h3__1 = UInt32(0x10325476); h4__1 = UInt32(0xc3d2e1f0)
    h0__2 = UInt32(0x67452301); h1__2 = UInt32(0xefcdab89); h2__2 = UInt32(0x98badcfe); h3__2 = UInt32(0x10325476); h4__2 = UInt32(0xc3d2e1f0)
    h0__3 = UInt32(0x67452301); h1__3 = UInt32(0xefcdab89); h2__3 = UInt32(0x98badcfe); h3__3 = UInt32(0x10325476); h4__3 = UInt32(0xc3d2e1f0)
    t_0 = h1__0 + C0 + Dp0; h1__0 = h2__0 + D0 + Ep0; h2__0 = h3__0 + E0 + Ap0
    h3__0 = h4__0 + A0 + Bp0; h4__0 = h0__0 + B0 + Cp0; h0__0 = t_0
    t_1 = h1__1 + C1 + Dp1; h1__1 = h2__1 + D1 + Ep1; h2__1 = h3__1 + E1 + Ap1
    h3__1 = h4__1 + A1 + Bp1; h4__1 = h0__1 + B1 + Cp1; h0__1 = t_1
    t_2 = h1__2 + C2 + Dp2; h1__2 = h2__2 + D2 + Ep2; h2__2 = h3__2 + E2 + Ap2
    h3__2 = h4__2 + A2 + Bp2; h4__2 = h0__2 + B2 + Cp2; h0__2 = t_2
    t_3 = h1__3 + C3 + Dp3; h1__3 = h2__3 + D3 + Ep3; h2__3 = h3__3 + E3 + Ap3
    h3__3 = h4__3 + A3 + Bp3; h4__3 = h0__3 + B3 + Cp3; h0__3 = t_3
    p_out = convert(Ptr{UInt32}, out_p)
    @inbounds unsafe_store!(p_out, h0__0, 1); unsafe_store!(p_out, h1__0, 2); unsafe_store!(p_out, h2__0, 3)
    unsafe_store!(p_out, h3__0, 4); unsafe_store!(p_out, h4__0, 5)
    @inbounds unsafe_store!(p_out, h0__1, 6); unsafe_store!(p_out, h1__1, 7); unsafe_store!(p_out, h2__1, 8)
    unsafe_store!(p_out, h3__1, 9); unsafe_store!(p_out, h4__1, 10)
    @inbounds unsafe_store!(p_out, h0__2, 11); unsafe_store!(p_out, h1__2, 12); unsafe_store!(p_out, h2__2, 13)
    unsafe_store!(p_out, h3__2, 14); unsafe_store!(p_out, h4__2, 15)
    @inbounds unsafe_store!(p_out, h0__3, 16); unsafe_store!(p_out, h1__3, 17); unsafe_store!(p_out, h2__3, 18)
    unsafe_store!(p_out, h3__3, 19); unsafe_store!(p_out, h4__3, 20)
end

end # module
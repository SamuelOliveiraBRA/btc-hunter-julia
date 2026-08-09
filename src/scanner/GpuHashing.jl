module GpuHashing

if !Sys.isapple()
    using CUDA
end
using ..GpuCrypto

export sha256_single_block_gpu, ripemd160_single_block_gpu, hash160_gpu

# ── SHA-256 ──────────────────────────────────────────────────────────
const K256 = (
    UInt32(0x428a2f98), UInt32(0x71374491), UInt32(0xb5c0fbcf), UInt32(0xe9b5dba5), UInt32(0x3956c25b), UInt32(0x59f111f1), UInt32(0x923f82a4), UInt32(0xab1c5ed5),
    UInt32(0xd807aa98), UInt32(0x12835b01), UInt32(0x243185be), UInt32(0x550c7dc3), UInt32(0x72be5d74), UInt32(0x80deb1fe), UInt32(0x9bdc06a7), UInt32(0xc19bf174),
    UInt32(0xe49b69c1), UInt32(0xefbe4786), UInt32(0x0fc19dc6), UInt32(0x240ca1cc), UInt32(0x2de92c6f), UInt32(0x4a7484aa), UInt32(0x5cb0a9dc), UInt32(0x76f988da),
    UInt32(0x983e5152), UInt32(0xa831c66d), UInt32(0xb00327c8), UInt32(0xbf597fc7), UInt32(0xc6e00bf3), UInt32(0xd5a79147), UInt32(0x06ca6351), UInt32(0x14292967),
    UInt32(0x27b70a85), UInt32(0x2e1b2138), UInt32(0x4d2c6dfc), UInt32(0x53380d13), UInt32(0x650a7354), UInt32(0x766a0abb), UInt32(0x81c2c92e), UInt32(0x92722c85),
    UInt32(0xa2bfe8a1), UInt32(0xa81a664b), UInt32(0xc24b8b70), UInt32(0xc76c51a3), UInt32(0xd192e819), UInt32(0xd6990624), UInt32(0xf40e3585), UInt32(0x106aa070),
    UInt32(0x19a4c116), UInt32(0x1e376c08), UInt32(0x2748774c), UInt32(0x34b0bcb5), UInt32(0x391c0cb3), UInt32(0x4ed8aa4a), UInt32(0x5b9cca4f), UInt32(0x682e6ff3),
    UInt32(0x748f82ee), UInt32(0x78a5636f), UInt32(0x84c87814), UInt32(0x8cc70208), UInt32(0x90befffa), UInt32(0xa4506ceb), UInt32(0xbef9a3f7), UInt32(0xc67178f2)
)

@inline rotr(x::UInt32, n::Int) = (x >>> n) | (x << (32 - n))
@inline sha256_ch(x::UInt32, y::UInt32, z::UInt32) = (x & y) ⊻ (~x & z)
@inline sha256_maj(x::UInt32, y::UInt32, z::UInt32) = (x & y) ⊻ (x & z) ⊻ (y & z)
@inline sha256_sigma0(x::UInt32) = rotr(x, 2) ⊻ rotr(x, 13) ⊻ rotr(x, 22)
@inline sha256_sigma1(x::UInt32) = rotr(x, 6) ⊻ rotr(x, 11) ⊻ rotr(x, 25)
@inline sha256_eps0(x::UInt32) = rotr(x, 7) ⊻ rotr(x, 18) ⊻ (x >>> 3)
@inline sha256_eps1(x::UInt32) = rotr(x, 17) ⊻ rotr(x, 19) ⊻ (x >>> 10)

@inline b_ext(v::UInt64, shift::Int) = UInt32((v >>> shift) & 0xFF)

macro round256(w_val, k_val)
    esc(quote
        t1 = h + sha256_sigma1(e) + sha256_ch(e, f, g) + $k_val + $w_val
        t2 = sha256_sigma0(a) + sha256_maj(a, b, c)
        h = g; g = f; f = e; e = d + t1
        d = c; c = b; b = a; a = t1 + t2
    end)
end

@inline function sha256_single_block_gpu(x::GpuUInt256, prefix::UInt8)::NTuple{8, UInt32}
    w0 = (UInt32(prefix) << 24) | (b_ext(x.v4, 56) << 16) | (b_ext(x.v4, 48) << 8) | b_ext(x.v4, 40)
    w1 = (b_ext(x.v4, 32) << 24) | (b_ext(x.v4, 24) << 16) | (b_ext(x.v4, 16) << 8) | b_ext(x.v4, 8)
    w2 = (b_ext(x.v4, 0) << 24)  | (b_ext(x.v3, 56) << 16) | (b_ext(x.v3, 48) << 8) | b_ext(x.v3, 40)
    w3 = (b_ext(x.v3, 32) << 24) | (b_ext(x.v3, 24) << 16) | (b_ext(x.v3, 16) << 8) | b_ext(x.v3, 8)
    w4 = (b_ext(x.v3, 0) << 24)  | (b_ext(x.v2, 56) << 16) | (b_ext(x.v2, 48) << 8) | b_ext(x.v2, 40)
    w5 = (b_ext(x.v2, 32) << 24) | (b_ext(x.v2, 24) << 16) | (b_ext(x.v2, 16) << 8) | b_ext(x.v2, 8)
    w6 = (b_ext(x.v2, 0) << 24)  | (b_ext(x.v1, 56) << 16) | (b_ext(x.v1, 48) << 8) | b_ext(x.v1, 40)
    w7 = (b_ext(x.v1, 32) << 24) | (b_ext(x.v1, 24) << 16) | (b_ext(x.v1, 16) << 8) | b_ext(x.v1, 8)
    w8 = (b_ext(x.v1, 0) << 24) | UInt32(0x800000)
    w9 = UInt32(0); w10 = UInt32(0); w11 = UInt32(0); w12 = UInt32(0); w13 = UInt32(0); w14 = UInt32(0);
    w15 = UInt32(0x108)  # Length 264 bits
    
    a::UInt32 = 0x6a09e667
    b::UInt32 = 0xbb67ae85
    c::UInt32 = 0x3c6ef372
    d::UInt32 = 0xa54ff53a
    e::UInt32 = 0x510e527f
    f::UInt32 = 0x9b05688c
    g::UInt32 = 0x1f83d9ab
    h::UInt32 = 0x5be0cd19

    @round256 w0 K256[1]; @round256 w1 K256[2]; @round256 w2 K256[3]; @round256 w3 K256[4]
    @round256 w4 K256[5]; @round256 w5 K256[6]; @round256 w6 K256[7]; @round256 w7 K256[8]
    @round256 w8 K256[9]; @round256 w9 K256[10]; @round256 w10 K256[11]; @round256 w11 K256[12]
    @round256 w12 K256[13]; @round256 w13 K256[14]; @round256 w14 K256[15]; @round256 w15 K256[16]

    for i in 17:64
        w_new = sha256_eps1(w14) + w9 + sha256_eps0(w1) + w0
        w0 = w1; w1 = w2; w2 = w3; w3 = w4; w4 = w5; w5 = w6; w6 = w7; w7 = w8;
        w8 = w9; w9 = w10; w10 = w11; w11 = w12; w12 = w13; w13 = w14; w14 = w15; w15 = w_new;
        
        t1 = h + sha256_sigma1(e) + sha256_ch(e, f, g) + K256[i] + w_new
        t2 = sha256_sigma0(a) + sha256_maj(a, b, c)
        h = g; g = f; f = e; e = d + t1
        d = c; c = b; b = a; a = t1 + t2
    end

    return (0x6a09e667 + a, 0xbb67ae85 + b, 0x3c6ef372 + c, 0xa54ff53a + d,
            0x510e527f + e, 0x9b05688c + f, 0x1f83d9ab + g, 0x5be0cd19 + h)
end

# ── RIPEMD-160 ────────────────────────────────────────────────────────
@inline rol(x::UInt32, n::Int) = (x << n) | (x >>> (32 - n))
@inline f1(x::UInt32, y::UInt32, z::UInt32) = x ⊻ y ⊻ z
@inline f2(x::UInt32, y::UInt32, z::UInt32) = (x & y) | (~x & z)
@inline f3(x::UInt32, y::UInt32, z::UInt32) = (x | ~y) ⊻ z
@inline f4(x::UInt32, y::UInt32, z::UInt32) = (x & z) | (y & ~z)
@inline f5(x::UInt32, y::UInt32, z::UInt32) = x ⊻ (y | ~z)

macro round_ripemd(f_name, A, B, C, D, E, X, K, S)
    esc(quote
        $A = rol($A + $f_name($B, $C, $D) + $X + $K, $S) + $E
        $C = rol($C, 10)
    end)
end

# Round helper macros for unrolling
macro rr1(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f1 $A $B $C $D $E $X $K $S)) end
macro rr2(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f2 $A $B $C $D $E $X $K $S)) end
macro rr3(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f3 $A $B $C $D $E $X $K $S)) end
macro rr4(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f4 $A $B $C $D $E $X $K $S)) end
macro rr5(A, B, C, D, E, X, K, S) esc(:(@round_ripemd f5 $A $B $C $D $E $X $K $S)) end

@inline function ripemd160_single_block_gpu(H::NTuple{8, UInt32})::NTuple{5, UInt32}
    w0 = bswap(H[1]); w1 = bswap(H[2]); w2 = bswap(H[3]); w3 = bswap(H[4])
    w4 = bswap(H[5]); w5 = bswap(H[6]); w6 = bswap(H[7]); w7 = bswap(H[8])
    w8 = UInt32(0x00000080); w9 = UInt32(0); w10 = UInt32(0); w11 = UInt32(0)
    w12 = UInt32(0); w13 = UInt32(0); w14 = UInt32(256); w15 = UInt32(0)
    
    A = 0x67452301; B = 0xefcdab89; C = 0x98badcfe; D = 0x10325476; E = 0xc3d2e1f0
    Ap = 0x67452301; Bp = 0xefcdab89; Cp = 0x98badcfe; Dp = 0x10325476; Ep = 0xc3d2e1f0

    # Chain 1 Rounds
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

    # Chain 2 Rounds
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

    # Final Merge
    return (0xefcdab89 + C + Dp, 0x98badcfe + D + Ep, 0x10325476 + E + Ap, 0xc3d2e1f0 + A + Bp, 0x67452301 + B + Cp)
end

@inline function hash160_gpu(x::GpuUInt256, is_even::Bool)::NTuple{5, UInt32}
    prefix = is_even ? UInt8(0x02) : UInt8(0x03)
    h_sha = sha256_single_block_gpu(x, prefix)
    h_rip = ripemd160_single_block_gpu(h_sha)
    return h_rip
end

end # module

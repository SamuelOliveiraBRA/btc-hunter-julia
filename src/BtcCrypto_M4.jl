module BtcCrypto_M4

using Base: llvmcall

export sha256_block_m4!

# Referência de Intrínsecos SHA256 (AArch64)
@inline function sha256_h_intrinsic(abcd, efgh, wk)
    return llvmcall(("""
        declare <4 x i32> @llvm.aarch64.crypto.sha256h(<4 x i32>, <4 x i32>, <4 x i32>)
        define <4 x i32> @entry(<4 x i32> %0, <4 x i32> %1, <4 x i32> %2) {
            %res = call <4 x i32> @llvm.aarch64.crypto.sha256h(<4 x i32> %0, <4 x i32> %1, <4 x i32> %2)
            ret <4 x i32> %res
        }
    """, "entry"), NTuple{4, VecElement{UInt32}}, Tuple{NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}}, abcd, efgh, wk)
end

@inline function sha256_h2_intrinsic(efgh, abcd, wk)
    return llvmcall(("""
        declare <4 x i32> @llvm.aarch64.crypto.sha256h2(<4 x i32>, <4 x i32>, <4 x i32>)
        define <4 x i32> @entry(<4 x i32> %0, <4 x i32> %1, <4 x i32> %2) {
            %res = call <4 x i32> @llvm.aarch64.crypto.sha256h2(<4 x i32> %0, <4 x i32> %1, <4 x i32> %2)
            ret <4 x i32> %res
        }
    """, "entry"), NTuple{4, VecElement{UInt32}}, Tuple{NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}}, efgh, abcd, wk)
end

@inline function sha256_su0_intrinsic(w0_3, w4_7)
    return llvmcall(("""
        declare <4 x i32> @llvm.aarch64.crypto.sha256su0(<4 x i32>, <4 x i32>)
        define <4 x i32> @entry(<4 x i32> %0, <4 x i32> %1) {
            %res = call <4 x i32> @llvm.aarch64.crypto.sha256su0(<4 x i32> %0, <4 x i32> %1)
            ret <4 x i32> %res
        }
    """, "entry"), NTuple{4, VecElement{UInt32}}, Tuple{NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}}, w0_3, w4_7)
end

@inline function sha256_su1_intrinsic(w0_3, w4_7, w8_11)
    return llvmcall(("""
        declare <4 x i32> @llvm.aarch64.crypto.sha256su1(<4 x i32>, <4 x i32>, <4 x i32>)
        define <4 x i32> @entry(<4 x i32> %0, <4 x i32> %1, <4 x i32> %2) {
            %res = call <4 x i32> @llvm.aarch64.crypto.sha256su1(<4 x i32> %0, <4 x i32> %1, <4 x i32> %2)
            ret <4 x i32> %res
        }
    """, "entry"), NTuple{4, VecElement{UInt32}}, Tuple{NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}, NTuple{4, VecElement{UInt32}}}, w0_3, w4_7, w8_11)
end

const K256 = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

const H0_V = 0x6a09e667; const H1_V = 0xbb67ae85; const H2_V = 0x3c6ef372; const H3_V = 0xa54ff53a
const H4_V = 0x510e527f; const H5_V = 0x9b05688c; const H6_V = 0x1f83d9ab; const H7_V = 0x5be0cd19

@inline function sha256_block_m4!(out_hash::Ptr{UInt8}, data::Ptr{UInt8})
    abcd = (VecElement(H0_V), VecElement(H1_V), VecElement(H2_V), VecElement(H3_V))
    efgh = (VecElement(H4_V), VecElement(H5_V), VecElement(H6_V), VecElement(H7_V))

    p32 = convert(Ptr{UInt32}, data)
    w0_3 = (VecElement(bswap(unsafe_load(p32, 1))), VecElement(bswap(unsafe_load(p32, 2))), 
            VecElement(bswap(unsafe_load(p32, 3))), VecElement(bswap(unsafe_load(p32, 4))))
    w4_7 = (VecElement(bswap(unsafe_load(p32, 5))), VecElement(bswap(unsafe_load(p32, 6))), 
            VecElement(bswap(unsafe_load(p32, 7))), VecElement(bswap(unsafe_load(p32, 8))))
    w8_11 = (VecElement(bswap(unsafe_load(p32, 9))), VecElement(bswap(unsafe_load(p32, 10))), 
             VecElement(bswap(unsafe_load(p32, 11))), VecElement(bswap(unsafe_load(p32, 12))))
    w12_15 = (VecElement(bswap(unsafe_load(p32, 13))), VecElement(bswap(unsafe_load(p32, 14))), 
              VecElement(bswap(unsafe_load(p32, 15))), VecElement(bswap(unsafe_load(p32, 16))))

    # --- Rounds 0-15 ---
    # Round 0-3
    abcd_old = abcd
    wk = (VecElement(w0_3[1].value + K256[1]), VecElement(w0_3[2].value + K256[2]), VecElement(w0_3[3].value + K256[3]), VecElement(w0_3[4].value + K256[4]))
    abcd = sha256_h_intrinsic(abcd, efgh, wk); efgh = sha256_h2_intrinsic(efgh, abcd_old, wk)
    # Round 4-7
    abcd_old = abcd
    wk = (VecElement(w4_7[1].value + K256[5]), VecElement(w4_7[2].value + K256[6]), VecElement(w4_7[3].value + K256[7]), VecElement(w4_7[4].value + K256[8]))
    abcd = sha256_h_intrinsic(abcd, efgh, wk); efgh = sha256_h2_intrinsic(efgh, abcd_old, wk)
    # Round 8-11
    abcd_old = abcd
    wk = (VecElement(w8_11[1].value + K256[9]), VecElement(w8_11[2].value + K256[10]), VecElement(w8_11[3].value + K256[11]), VecElement(w8_11[4].value + K256[12]))
    abcd = sha256_h_intrinsic(abcd, efgh, wk); efgh = sha256_h2_intrinsic(efgh, abcd_old, wk)
    # Round 12-15
    abcd_old = abcd
    wk = (VecElement(w12_15[1].value + K256[13]), VecElement(w12_15[2].value + K256[14]), VecElement(w12_15[3].value + K256[15]), VecElement(w12_15[4].value + K256[16]))
    abcd = sha256_h_intrinsic(abcd, efgh, wk); efgh = sha256_h2_intrinsic(efgh, abcd_old, wk)

    # --- Rounds 16-63 (Fully Unrolled) ---
    for k in (17, 21, 25, 29, 33, 37, 41, 45, 49, 53, 57, 61)
        w0_3 = sha256_su0_intrinsic(w0_3, w4_7)
        w0_3 = sha256_su1_intrinsic(w0_3, w8_11, w12_15)
        
        abcd_old = abcd
        wk = (VecElement(w0_3[1].value + K256[k]), VecElement(w0_3[2].value + K256[k+1]), VecElement(w0_3[3].value + K256[k+2]), VecElement(w0_3[4].value + K256[k+3]))
        abcd = sha256_h_intrinsic(abcd, efgh, wk); efgh = sha256_h2_intrinsic(efgh, abcd_old, wk)
        
        w0_3, w4_7, w8_11, w12_15 = w4_7, w8_11, w12_15, w0_3
    end

    r_ptr = convert(Ptr{UInt32}, out_hash)
    unsafe_store!(r_ptr, bswap(abcd[1].value + H0_V), 1)
    unsafe_store!(r_ptr, bswap(abcd[2].value + H1_V), 2)
    unsafe_store!(r_ptr, bswap(abcd[3].value + H2_V), 3)
    unsafe_store!(r_ptr, bswap(abcd[4].value + H3_V), 4)
    unsafe_store!(r_ptr, bswap(efgh[1].value + H4_V), 5)
    unsafe_store!(r_ptr, bswap(efgh[2].value + H5_V), 6)
    unsafe_store!(r_ptr, bswap(efgh[3].value + H6_V), 7)
    unsafe_store!(r_ptr, bswap(efgh[4].value + H7_V), 8)
end

end # module

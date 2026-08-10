module FastRipemd

# ═══════════════════════════════════════════════════════════════════
# FastRipemd.jl — Implementação RIPEMD-160 (Ultra-Otimizada para Bitcoin)
# ═══════════════════════════════════════════════════════════════════

export ripemd160_32b!

@inline f1(x, y, z) = x ⊻ y ⊻ z
@inline f2(x, y, z) = (x & y) | (~x & z)
@inline f3(x, y, z) = (x | ~y) ⊻ z
@inline f4(x, y, z) = (x & z) | (y & ~z)
@inline f5(x, y, z) = x ⊻ (y | ~z)

@inline rot(x, n) = (x << (n % UInt32)) | (x >>> ((32 - n) % UInt32))

@inline function ripemd160_32b!(in_p::Ptr{UInt8}, out_p::Ptr{UInt8})
    # Estado inicial
    h0 = 0x67452301; h1 = 0xefcdab89; h2 = 0x98badcfe; h3 = 0x10325476; h4 = 0xc3d2e1f0
    
    # Carregar 32 bytes (Bitcoin: SHA256 output is Big-Endian)
    # RIPEMD160 espera blocos de 64 bytes em Little-Endian.
    p32 = convert(Ptr{UInt32}, in_p)
    # Bswap necessário porque o SHA256 do BtcCrypto_M4 ja devolve em Big-Endian (ordem Bitcoin)
    w1 = bswap(unsafe_load(p32, 1)); w2 = bswap(unsafe_load(p32, 2))
    w3 = bswap(unsafe_load(p32, 3)); w4 = bswap(unsafe_load(p32, 4))
    w5 = bswap(unsafe_load(p32, 5)); w6 = bswap(unsafe_load(p32, 6))
    w7 = bswap(unsafe_load(p32, 7)); w8 = bswap(unsafe_load(p32, 8))
    
    # Padding fixo para 32 bytes: [32B] + 0x80 + [zeros] + [length 256 bits]
    w9 = 0x00000080; w10=0x00000000; w11=0x00000000; w12=0x00000000
    w13=0x00000000; w14=0x00000000; w15=0x00000100; w16=0x00000000
    
    X = (w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13, w14, w15, w16)

    al, bl, cl, dl, el = h0, h1, h2, h3, h4
    ar, br, cr, dr, er = h0, h1, h2, h3, h4

    # Round 1: f1, K=0
    @inline r1(a,b,c,d,e,k,s) = (a = rot(UInt32(0) + a + f1(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    r1(al,bl,cl,dl,el,0,11); r1(el,al,bl,cl,dl,1,14); r1(dl,el,al,bl,cl,2,15); r1(cl,dl,el,al,bl,3,12)
    r1(bl,cl,dl,el,al,4,5);  r1(al,bl,cl,dl,el,5,8);  r1(el,al,bl,cl,dl,6,7);  r1(dl,el,al,bl,cl,7,9)
    r1(cl,dl,el,al,bl,8,11); r1(bl,cl,dl,el,al,9,13); r1(al,bl,cl,dl,el,10,14); r1(el,al,bl,cl,dl,11,15)
    r1(dl,el,al,bl,cl,12,6); r1(cl,dl,el,al,bl,13,7); r1(bl,cl,dl,el,al,14,9); r1(al,bl,cl,dl,el,15,8)

    # Round 2: f2, K=0x5a827999
    @inline r2(a,b,c,d,e,k,s) = (a = rot(0x5a827999 + a + f2(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    r2(el,al,bl,cl,dl,7,7);  r2(dl,el,al,bl,cl,4,6);  r2(cl,dl,el,al,bl,13,8); r2(bl,cl,dl,el,al,1,13)
    r2(al,bl,cl,dl,el,10,11); r2(el,al,bl,cl,dl,6,9); r2(dl,el,al,bl,cl,15,7); r2(cl,dl,el,al,bl,3,15)
    r2(bl,cl,dl,el,al,12,7); r2(al,bl,cl,dl,el,0,12); r2(el,al,bl,cl,dl,9,15); r2(dl,el,al,bl,cl,5,9)
    r2(cl,dl,el,al,bl,2,11); r2(bl,cl,dl,el,al,14,7); r2(al,bl,cl,dl,el,11,13); r2(el,al,bl,cl,dl,8,12)

    # Round 3: f3, K=0x6ed9eba1
    @inline r3(a,b,c,d,e,k,s) = (a = rot(0x6ed9eba1 + a + f3(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    r3(dl,el,al,bl,cl,3,11); r3(cl,dl,el,al,bl,10,13); r3(bl,cl,dl,el,al,14,6); r3(al,bl,cl,dl,el,4,7)
    r3(el,al,bl,cl,dl,9,14); r3(dl,el,al,bl,cl,15,9); r3(cl,dl,el,al,bl,8,13); r3(bl,cl,dl,el,al,1,15)
    r3(al,bl,cl,dl,el,2,14); r3(el,al,bl,cl,dl,7,8);  r3(dl,el,al,bl,cl,0,13); r3(cl,dl,el,al,bl,6,6)
    r3(bl,cl,dl,el,al,13,5); r3(al,bl,cl,dl,el,11,12); r3(el,al,bl,cl,dl,5,7);  r3(dl,el,al,bl,cl,12,5)

    # Round 4: f4, K=0x8f1bbcdc
    @inline r4(a,b,c,d,e,k,s) = (a = rot(0x8f1bbcdc + a + f4(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    r4(cl,dl,el,al,bl,1,11); r4(bl,cl,dl,el,al,9,12); r4(al,bl,cl,dl,el,11,14); r4(el,al,bl,cl,dl,10,15)
    r4(dl,el,al,bl,cl,0,14); r4(cl,dl,el,al,bl,8,15); r4(bl,cl,dl,el,al,12,9); r4(al,bl,cl,dl,el,4,8)
    r4(el,al,bl,cl,dl,13,9); r4(dl,el,al,bl,cl,3,14); r4(cl,dl,el,al,bl,7,5);  r4(bl,cl,dl,el,al,15,6)
    r4(al,bl,cl,dl,el,14,8); r4(el,al,bl,cl,dl,5,6);  r4(dl,el,al,bl,cl,6,5);  r4(cl,dl,el,al,bl,2,12)

    # Round 5: f5, K=0xa953fd4e
    @inline r5(a,b,c,d,e,k,s) = (a = rot(0xa953fd4e + a + f5(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    r5(bl,cl,dl,el,al,4,9);  r5(al,bl,cl,dl,el,0,15); r5(el,al,bl,cl,dl,5,5);  r5(dl,el,al,bl,cl,9,11)
    r5(cl,dl,el,al,bl,7,6);  r5(bl,cl,dl,el,al,12,8); r5(al,bl,cl,dl,el,2,13); r5(el,al,bl,cl,dl,10,12)
    r5(dl,el,al,bl,cl,14,5); r5(cl,dl,el,al,bl,1,12); r5(bl,cl,dl,el,al,3,13); r5(al,bl,cl,dl,el,8,14)
    r5(el,al,bl,cl,dl,11,11); r5(dl,el,al,bl,cl,6,8); r5(cl,dl,el,al,bl,15,5); r5(bl,cl,dl,el,al,13,6)

    # --- Parallel Round (Direita) ---
    # Round 1: f5, K=0x50a28be6
    @inline pr1(a,b,c,d,e,k,s) = (a = rot(0x50a28be6 + a + f5(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    pr1(ar,br,cr,dr,er,0,11); pr1(er,ar,br,cr,dr,1,14); pr1(dr,er,ar,br,cr,2,15); pr1(cr,dr,er,ar,br,3,12)
    pr1(br,cr,dr,er,ar,4,5);  pr1(ar,br,cr,dr,er,5,8);  pr1(er,ar,br,cr,dr,6,7);  pr1(dr,er,ar,br,cr,7,9)
    pr1(cr,dr,er,ar,br,8,11); pr1(br,cr,dr,er,ar,9,13); pr1(ar,br,cr,dr,er,10,14); pr1(er,ar,br,cr,dr,11,15)
    pr1(dr,er,ar,br,cr,12,6); pr1(cr,dr,er,ar,br,13,7); pr1(br,cr,dr,er,ar,14,9); pr1(ar,br,cr,dr,er,15,8)

    # Round 2: f4, K=0x5c4dd124
    @inline pr2(a,b,c,d,e,k,s) = (a = rot(0x5c4dd124 + a + f4(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    pr2(er,ar,br,cr,dr,7,7);  pr2(dr,er,ar,br,cr,4,6);  pr2(cr,dr,er,ar,br,13,8); pr2(br,cr,dr,er,ar,1,13)
    pr2(ar,br,cr,dr,er,10,11); pr2(er,ar,br,cr,dr,6,9); pr2(dr,er,ar,br,cr,15,7); pr2(cr,dr,er,ar,br,3,15)
    pr2(br,cr,dr,er,ar,12,7); pr2(ar,br,cr,dr,er,0,12); pr2(er,ar,br,cr,dr,9,15); pr2(dr,er,ar,br,cr,5,9)
    pr2(cr,dr,er,ar,br,2,11); pr2(br,cr,dr,er,ar,14,7); pr2(ar,br,cr,dr,er,11,13); pr2(er,ar,br,cr,dr,8,12)

    # Round 3: f3, K=0x6d703ef3
    @inline pr3(a,b,c,d,e,k,s) = (a = rot(0x6d703ef3 + a + f3(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    pr3(dr,er,ar,br,cr,3,11); pr3(cr,dr,er,ar,br,10,13); pr3(br,cr,dr,er,ar,14,6); pr3(ar,br,cr,dr,er,4,7)
    pr3(er,ar,br,cr,dr,9,14); pr3(dr,er,ar,br,cr,15,9); pr3(cr,dr,er,ar,br,8,13); pr3(br,cr,dr,er,ar,1,15)
    pr3(ar,br,cr,dr,er,2,14); pr3(er,ar,br,cr,dr,7,8);  pr3(dr,er,ar,br,cr,0,13); pr3(cr,dr,er,ar,br,6,6)
    pr3(br,cr,dr,er,ar,13,5); pr3(ar,br,cr,dr,er,11,12); pr3(er,ar,br,cr,dr,5,7);  pr3(dr,er,ar,br,cr,12,5)

    # Round 4: f2, K=0x7a6d76e9
    @inline pr4(a,b,c,d,e,k,s) = (a = rot(0x7a6d76e9 + a + f2(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    pr4(cr,dr,er,ar,br,1,11); pr4(br,cr,dr,er,ar,9,12); pr4(ar,br,cr,dr,er,11,14); pr4(er,ar,br,cr,dr,10,15)
    pr4(dr,er,ar,br,cr,0,14); pr4(cr,dr,er,ar,br,8,15); pr4(br,cr,dr,er,ar,12,9); pr4(ar,br,cr,dr,er,4,8)
    pr4(er,ar,br,cr,dr,13,9); pr4(dr,er,ar,br,cr,3,14); pr4(cr,dr,er,ar,br,7,5);  pr4(br,cr,dr,er,ar,15,6)
    pr4(ar,br,cr,dr,er,14,8); pr4(er,ar,br,cr,dr,5,6);  pr4(dr,er,ar,br,cr,6,5);  pr4(cr,dr,er,ar,br,2,12)

    # Round 5: f1, K=0x00000000
    @inline pr5(a,b,c,d,e,k,s) = (a = rot(UInt32(0) + a + f1(b,c,d) + X[k+1], s) + e; c = rot(c, 10))
    pr5(br,cr,dr,er,ar,4,9);  pr5(ar,br,cr,dr,er,0,15); pr5(er,ar,br,cr,dr,5,5);  pr5(dr,er,ar,br,cr,9,11)
    pr5(cr,dr,er,ar,br,7,6);  pr5(br,cr,dr,er,ar,12,8); pr5(ar,br,cr,dr,er,2,13); pr5(er,ar,br,cr,dr,10,12)
    pr5(dr,er,ar,br,cr,14,5); pr5(cr,dr,er,ar,br,1,12); pr5(br,cr,dr,er,ar,3,13); pr5(ar,br,cr,dr,er,8,14)
    pr5(er,ar,br,cr,dr,11,11); pr5(dr,er,ar,br,cr,6,8); pr5(cr,dr,er,ar,br,15,5); pr5(br,cr,dr,er,ar,13,6)

    # Combine results
    t = h1 + cl + dr; h1 = h2 + dl + er; h2 = h3 + el + ar
    h3 = h4 + al + br; h4 = h0 + bl + cr; h0 = t

    # Output as big-endian bytes (Bitcoin standard)
    p_out = convert(Ptr{UInt8}, out_p)
    @inbounds for (i, word) in enumerate((h0, h1, h2, h3, h4))
        w = bswap(word)
        base = (i - 1) * 4
        unsafe_store!(p_out, w & 0xff, base + 1)
        unsafe_store!(p_out, (w >> 8) & 0xff, base + 2)
        unsafe_store!(p_out, (w >> 16) & 0xff, base + 3)
        unsafe_store!(p_out, (w >> 24) & 0xff, base + 4)
    end
end

end

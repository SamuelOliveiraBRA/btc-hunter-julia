                # Motor BitCrackEngine (Multi-target nativo)
                # No modo reverso (2), inicializamos com o passo negativo
                stride_for_engine = mode == 2 ? -BigInt(batch_sz * n_threads) : BigInt(batch_sz * n_threads)
                state = BitCrackEngine.init_engine(curr_base, target_set, batch_sz, Int(stride_for_engine), CFG.both_formats)
                
                local_count = 0
                batch_counter = 0
                local_batch_idx = 0

                while !stop[]
                    res = BitCrackEngine.check_batch(state)
                    idx, h_f = res[1], res[2]
                    
                    if idx > 0
                        # Só agora fazemos a conta pesada de BigInt para registrar o achado
                        found_key[]  = curr_base + BigInt(local_batch_idx * (batch_sz * n_threads)) + BigInt(idx - 1)
                        found_addr[] = address_from_hash(target_set, h_f)
                        atomic_add!(keys_done, local_count)
                        stop[] = true; break
                    end
                    
                    local_count += batch_sz
                    batch_counter += 1
                    
                    # Sincroniza com o global apenas a cada 256 lotes (Reduz contenção no M4)
                    if batch_counter >= 256
                        atomic_add!(keys_done, local_count)
                        local_count = 0
                        batch_counter = 0
                    end

                    if mode == 1 || mode == 2
                        # No modo 1 ou 2, usamos o next_batch! que já tem o stride configurado no state
                        BitCrackEngine.next_batch!(state)
                        local_batch_idx += 1
                        
                        # Verificação de limite simples (BigInt apenas aqui)
                        current_pos = curr_base + BigInt(local_batch_idx * (batch_sz * n_threads))
                        if mode == 1 && current_pos > end_key; break; end
                        if mode == 2 && current_pos < end_key; break; end
                    else
                        # Modo Aleatório: Reinicializa com nova chave (pula bits para evitar repetição próxima)
                        stop[] && break
                        range_size = safe_rng_max > start_key ? safe_rng_max - start_key : BigInt(1)
                        new_base = start_key + BigInt(rand(0:floor(Int64, range_size)))
                        state = BitCrackEngine.init_engine(new_base, target_set, batch_sz, Int(stride_for_engine), CFG.both_formats)
                        local_batch_idx = 0
                    end
                end
                atomic_add!(keys_done, local_count)

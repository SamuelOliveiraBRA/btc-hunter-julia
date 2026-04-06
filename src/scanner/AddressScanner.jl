module AddressScanner

using ..BtcCrypto
using ..PuzzleData
using Distributed
using Printf
using Serialization

export scan_range, SearchMode, ModeSequential, ModeReverse, ModeRandom

@enum SearchMode ModeSequential=1 ModeReverse=2 ModeRandom=3

"""
    scan_range(address::String, start_range::BigInt, end_range::BigInt; mode::SearchMode=ModeSequential, threads::Int=0)
Inicia a busca por chaves privadas no intervalo especificado usando Workers de CPU por padrão.
"""
function scan_range(target_address::String, start_range::BigInt, end_range::BigInt; 
                    mode::SearchMode=ModeSequential, threads::Int=0)
    
    workers_list = workers()
    n_workers = length(workers_list)
    
    # Decodificar endereço alvo para Hash160 (20 bytes)
    target_hash160 = base58_to_hash160(target_address)
    
    println("🚀 Iniciando busca com Workers...")
    println("📍 Alvo: $target_address (Hash160: $(bytes2hex(target_hash160)))")
    println("🔍 Modo: $mode")
    println("⚙️  Processos: $n_workers")
    
    # Canal para sinalizar descoberta
    @sync for w in workers_list
        @async remotecall_wait(w) do 
            worker_task(target_hash160, start_range, end_range, mode, n_workers, myid())
        end
    end
end

"""
    worker_task(...)
Executado em cada worker para escanear uma fatia do range.
"""
function worker_task(target_hash, start_r, end_r, mode, total_workers, wid)
    offset = wid - 1
    curr_key = if mode == ModeSequential
        start_r + (offset - 1)
    elseif mode == ModeReverse
        end_r - (offset - 1)
    else
        BigInt(rand(start_r:end_r))
    end

    step = total_workers
    total_tested = 0
    
    start_time = time()
    last_print = start_time

    while true
        # 2. PrivKey -> Compressed PubKey -> Hash160
        pub_bytes = priv_to_pub_compressed(curr_key)
        current_hash = hash160(pub_bytes)

        # 3. Comparação Direta (BINÁRIA)
        if current_hash == target_hash
            # Converter para Hex 32 bytes com zeros a esquerda APENAS quando achar a chave
            key_hex = string(curr_key, base=16)
            priv_hex = lpad(key_hex, 64, "0")
            pub_hex = bytes2hex(pub_bytes)
            
            println("\n\n" * "="^20 * " FOUND (1) " * "="^20)
            println("Privat key  : $priv_hex")
            println("Public key  : $pub_hex")
            println("="^51)
            
            # Salvar em arquivo
            open("found.txt", "a") do f
                write(f, "Privat key  : $priv_hex\nPublic key  : $pub_hex\n\n")
            end
            exit(0) # Para o processo
        end
        
        total_tested += 1
        
        if mode == ModeSequential
            curr_key += step
            curr_key > end_r && break
        elseif mode == ModeReverse
            curr_key -= step
            curr_key < start_r && break
        else
            curr_key = BigInt(rand(start_r:end_r))
        end

        if total_tested % 100 == 0 && wid == 2
            now = time()
            if now - last_print >= 5.0
                elapsed_total = now - start_time
                hours = floor(Int, elapsed_total / 3600)
                mins = floor(Int, (elapsed_total % 3600) / 60)
                secs = floor(Int, elapsed_total % 60)
                
                # Estimativa baseada no worker * total de workers
                estimated_total = total_tested * total_workers
                speed = estimated_total / elapsed_total
                
                speed_str = speed > 1_000_000 ? @sprintf("%.2f Mkeys/s", speed/1_000_000) :
                            speed > 1_000 ? @sprintf("%.2f Kkeys/s", speed/1_000) : @sprintf("%.2f keys/s", speed)
                
                @printf("[%02d:%02d:%02d] [%016x] [Progresso: %s] [Velocidade: %s]\n", hours, mins, secs, curr_key, estimated_total, speed_str)
                flush(stdout)
                last_print = now
            end
        end
    end
end

end # module

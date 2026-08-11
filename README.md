# 🚀 BTC Hunter Julia - O Manual Mestre v1.5.1

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-Montgomery--Acelerado-orange)](#-motores-de-busca)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)

Este é o manual definitivo para o **BTC Hunter Julia**, um ecossistema de busca de chaves privadas Bitcoin de altíssima performance para resolver a **Bitcoin Puzzle Collection**.

---

## 📋 Sumário
1.  [🌟 Novidades da Versão 1.5.1](#-novidades-da-versão-151)
2.  [🧩 O que são os Bitcoin Puzzles?](#-o-que-são-os-bitcoin-puzzles)
3.  [📦 Guia de Instalação (Windows, Mac, Linux)](#-guia-de-instalação-windows-mac-linux)
4.  [🧠 A Anatomia do Comando (Explicação Linha por Linha)](#-a-anatomia-do-comando-explicação-linha-por-linha)
5.  [⚙️ Motores de Busca: BitCrack vs Julia vs BSGS](#️-motores-de-busca-bitcrack-vs-julia-vs-bsgs)
6.  [💡 Enciclopédia de Exemplos Práticos](#-enciclopédia-de-exemplos-práticos)
7.  [🖥️ Manual do Modo Interativo (Menu)](#️-manual-do-modo-interativo-menu)
8.  [🛡️ Segurança e Checkpoints](#️-segurança-e-checkpoints)
9.  [🏎️ Otimizações Técnicas Avançadas](#️-otimizações-técnicas-avançadas)
10. [🆘 Solução de Problemas](#-solução-de-problemas)

---

## 🌟 Novidades da Versão 1.5.1

A versão 1.5.1 transforma o BTC Hunter em um sistema de nível **NOC (Network Operations Center)**, focado em transparência total e UX refinada.

### 💎 Dashboard Dinâmico
*   **Interface Single-Page**: O terminal agora recarrega de forma limpa a cada navegação, eliminando poluição visual.
*   **Dual-Bar Hardware**: Monitoramento visual em tempo real do uso de **CPUs (com contagem de threads ativo/total)** e **GPU (nível de intensidade)**.
*   **Blocos Estruturados**: Divisores horizontais e títulos dinâmicos para Saldo, Status, Limites de Range e Performance.

### 🌐 Conectividade e Inteligência
*   **Real-Time Balance Check**: Integração nativa com a API `blockchain.info` para validar saldos antes do scan. A consulta é automática se a Internet estiver habilitada nas **Configurações → [2] Internet**. Se estiver desabilitada, a busca inicia direto no modo offline.
*   **Deep Clear Engine**: Novo sistema de limpeza de buffer que impede a duplicação de imagens em transições rápidas.
*   **Créditos de Identidade**: Exibição fixa da versão e autoria no cabeçalho do sistema.

---

## 🧩 O que são os Bitcoin Puzzles?

A **Bitcoin Puzzle Collection** foi lançada em 2015 por um doador anônimo para testar o limite da computação e da curva elíptica Secp256k1.
*   **A Estrutura**: Ele enviou Bitcoins para endereços cujas chaves privadas estão em intervalos crescentes.
*   **O Desafio**: O Puzzle #1 tem 1 bit de dificuldade (fácil). O Puzzle #66 tem 66 bits (extremamente difícil). A cada bit adicionado, o espaço de busca **dobra**.
*   **O Objetivo deste Software**: Varre esses intervalos matemáticos buscando a "chave mestra" que permite o acesso aos fundos da carteira.

---

## 📦 Guia de Instalação (Windows, Mac, Linux)

### 🪟 Windows (Método Rápido)
1.  Abra o PowerShell como Administrador.
2.  Instale o Julia: `winget install Julia.Julia`
3.  Instale o Git: `winget install Git.Git`
4.  Clone este repositório: `git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git`
5.  Entre na pasta: `cd btc-hunter-julia`
6.  Configure o ambiente (MANDATÓRIO): `julia --project=. -e "using Pkg; Pkg.instantiate()"`
    > [!IMPORTANT]
    > Se você ver um erro como `ArgumentError: Package ... not installed`, repita este passo acima. Ele garante que todas as bibliotecas matemáticas e de GPU (CUDA) sejam baixadas corretamente.

### 🍎 macOS / 🐧 Linux
1.  Instale o Julia pelo site oficial ou via `brew install --cask julia`.
2.  Clone e configure como no Windows.

---

## 🧠 A Anatomia do Comando (Explicação Linha por Linha)

Vamos dissecar o comando completo para você entender o que cada palavra faz:

```bash
julia --threads auto main.jl --puzzle 66 --modo 1 --motor bitcrack --gpu:8 --batch 1024
```

### 1. `julia`
O comando `julia` chama o **Runtime (Ambiente de Execução)** da linguagem Julia. É ele quem lê o código, compila as funções matemáticas pesadas e as executa com velocidade de linguagem C.

### 2. `--threads auto` (O MAIS IMPORTANTE)
*   **O que faz**: O Julia é naturalmente capaz de fazer várias coisas ao mesmo tempo (**Multithreading**). Por padrão, ele usa apenas 1 núcleo do seu processador.
*   **O parâmetro `auto`**: Ele detecta automaticamente quantos "núcleos lógicos" (threads) seu processador tem (ex: 8, 12, 16).
*   **Resultado**: Se você tem um Core i7 de 12 núcleos, ao usar `--threads auto`, o sistema rodará **12 vezes mais rápido** do que se não usasse essa flag. Ele ativa o paralelismo real.

### 3. `main.jl`
Este é o **Script Mestre**. Ele contém a lógica de menus, os limites de todos os puzzles e a orquestração de qual motor será usado. É o "cérebro" do projeto.

### 4. `--puzzle 66`
*   **Ação**: Seleciona o alvo #66 da lista oficial.
*   **Bastidores**: Ao definir isso, o programa carrega automaticamente o endereço Bitcoin alvo e os limites (mínimo e máximo) do espaço de busca deste puzzle específico.

### 5. `--modo 1`
Define a estratégia de avanço:
*   **1 (Sequencial)**: Começa do zero e sobe de 1 em 1.
*   **2 (Reverso)**: Começa do valor máximo e desce de 1 em 1.
*   **3 (Aleatório)**: Sorteia números "ao acaso" dentro do intervalo do puzzle.

### 6. `--motor bitcrack`
Escolhe a implementação técnica (veja a seção de Motores para detalhes). O `bitcrack` é a nossa implementação em Julia inspirada no Bitcrack original, focada em velocidade bruta.

### 7. `--gpu:8`
*   **Ação**: Ativa o suporte à placa de vídeo (NVIDIA/CUDA). 
*   **O valor `:8`**: É a **Intensidade**. Define quantas chaves cada núcleo da GPU processa por ciclo. Valores entre 8 e 12 são ideais. Mais do que isso pode travar a interface do Windows.

### 8. `--batch 1024`
*   **Ação**: Define o tamanho do Buffer de chaves. 
*   **Por que importa?**: O processador não testa uma chave por vez e para. Ele testa 1024 chaves, guarda o resultado em um "pacote" e pergunta ao sistema: "Alguma dessas abriu a carteira?". Isso reduz o desperdício de tempo.

---

## ⚙️ Motores de Busca: BitCrack vs Julia vs BSGS

| Motor | Nome Técnico | Características |
| :--- | :--- | :--- |
| **BitCrack** | `bitcrack` | O mais rápido. Matemática de campo finito ultra-otimizada. Uso obrigatório para GPU. |
| **Julia/SecpOpt** | `secp` | Versão estável baseada no SecpOptimized. Excelente para multi-threading em CPUs Intel/AMD. |
| **BSGS** | `bsgs` | Algoritmo de colisão (Baby-Step Giant-Step). Muito rápido em áreas pequenas, mas engole muita memória RAM. |
| **GPU/CUDA** | `gpu` | Aceleração via placa de vídeo NVIDIA. Requer compatibilidade de hardware (veja aviso abaixo). |

> [!WARNING]
> **Compatibilidade do Motor GPU (CUDA)**
>
> O motor GPU requer **CUDA 13.0** ou superior instalado, mas esta versão do CUDA **só suporta placas NVIDIA com Compute Capability 7.0 ou acima** (RTX 20xx, 30xx, 40xx e superiores).
>
> Placas mais antigas como a **GTX 10xx** e **GTX 9xx** **não são compatíveis** com CUDA 13.0 e o motor GPU será desativado automaticamente, fazendo fallback para o motor **SecpOpt (CPU)**.
>
> **Solução para placas antigas:** Instale o **CUDA Toolkit 11.8** (última versão com suporte a CC 6.x):
> ```
> https://developer.nvidia.com/cuda-11-8-0-download-archive
> ```
>
> | Modelo | Compute Capability | CUDA 13.0 | Observação |
> | :--- | :---: | :---: | :--- |
> | GTX 750, 750 Ti | 5.0 | ❌ | Maxwell — sem suporte |
> | GTX 950, 960, 970, 980, 980 Ti | 5.2 | ❌ | Maxwell — sem suporte |
> | GTX 1050, 1050 Ti | 6.1 | ❌ | Pascal — sem suporte |
> | GTX 1060, 1070, 1070 Ti | 6.1 | ❌ | Pascal — sem suporte |
> | GTX 1080, 1080 Ti, Titan X/Xp | 6.1 | ❌ | Pascal — sem suporte |
> | **GTX 1650, 1650 Super** | **7.5** | **✅** | Turing — compatível |
> | **GTX 1660, 1660 Super, 1660 Ti** | **7.5** | **✅** | Turing — compatível |
> | **RTX 2060, 2060 Super** | **7.5** | **✅** | Turing — compatível |
> | **RTX 2070, 2070 Super** | **7.5** | **✅** | Turing — compatível |
> | **RTX 2080, 2080 Super, 2080 Ti** | **7.5** | **✅** | Turing — compatível |
> | **RTX 3050, 3060, 3060 Ti** | **8.6** | **✅** | Ampere — ótimo custo-benefício |
> | **RTX 3070, 3070 Ti** | **8.6** | **✅** | Ampere — alta performance |
> | **RTX 3080, 3080 Ti, 3090, 3090 Ti** | **8.6** | **✅** | Ampere — top de linha |
> | **RTX 4060, 4060 Ti** | **8.9** | **✅** | Ada Lovelace — eficiente |
> | **RTX 4070, 4070 Super, 4070 Ti** | **8.9** | **✅** | Ada Lovelace — recomendado |
> | **RTX 4080, 4080 Super, 4090** | **8.9** | **✅** | Ada Lovelace — máxima performance |
> | **RTX 5070, 5080, 5090** | **10.0** | **✅** | Blackwell — próxima geração |


---

## 💡 Enciclopédia de Exemplos Práticos

### 🎯 Exemplo de Porcentagem (Ideal para dividir trabalho)
```bash
julia --threads auto main.jl --puzzle 71 --modo 1 --porcentagem 50
```
*   **O que faz**: Inicia a busca exatamente no meio do caminho do Puzzle 71 (50% do range). Útil se você tem dois PCs: o PC-1 começa em 0% e o PC-2 começa em 50%.

---

### 🏎️ Exemplo dos Motores de Busca
```bash
# Rodar com o novo motor BitCrack (Recomendado para velocidade)
julia --threads auto main.jl --puzzle 66 --motor bitcrack

# Rodar com o motor tradicional SecpOptimized (Estabilidade)
julia --threads auto main.jl --puzzle 66 --motor secp
```

---

### 🎮 Exemplo de Uso com GPU (Aceleração CUDA)
```bash
julia --threads auto main.jl --puzzle 67 --motor bitcrack --gpu:10
```
*   **O que faz**: Ativa o processamento paralelo na sua placa de vídeo com intensidade 10. Multiplica o KPS (chaves por segundo) drasticamente.

---

### 🔄 Exemplo de Modos de Busca
```bash
# REVERSO: Do fim para o começo
julia --threads auto main.jl --puzzle 66 --modo 2

# ALEATÓRIO: Sorteio puro
julia --threads auto main.jl --puzzle 66 --modo 3

# ALEATÓRIO PARTICIONADO: Sorteia apenas entre 41% e 100%
julia --threads auto main.jl --puzzle 71 --modo 3 --porcentagem 41
```

---

### 🍰 Exemplo de Fatiamento (Range Customizado)
```bash
# BUSCA EM FATIA: Procura apenas no bloco entre 41% e 42%
julia --threads auto main.jl --puzzle 66 --porcentagem 41 --fim 42

# ATALHO (+1%): O comando abaixo também busca a fatia 41% -> 42%
julia --threads auto main.jl --puzzle 66 --porcentagem 41 --fim 41
```
*   **`--fim <%>`**: Define o limite superior da busca. Se for igual à `--porcentagem`, o programa assume um bloco de 1% de largura.

---

## 🖥️ Manual do Modo Interativo (Menu)

O modo interativo foi redesenhado para ser um assistente passo-a-passo:
1.  **Identificação Visual**: O Logo BTC e o Dashboard de Hardware estão sempre visíveis no topo.
2.  **Assistente de Busca (Wizard)**:
    *   **Passo 1 (Varredura)**: Escolha entre Sequencial, Reverso ou Aleatório.
    *   **Passo 2 (Range)**: Definição de range por percentual inicial/final ou hex customizado.
    *   **Saldo**: Consultado automaticamente se **Internet = Ativa** nas Configurações. Sem pergunta extra.
3.  **Configurações de Hardware**: Ajuste dinâmico de CPUs e monitoramento de drivers CUDA sem precisar sair do programa.

---

## 🛡️ Segurança e Checkpoints

### 💾 Checkpoint Automático
O sistema salva seu progresso periodicamente. O arquivo fica em `outputs/checkpoint_puzzle_X.json`.
*   **Padrão**: Salva a cada 30 segundos.
*   **Customizado**: `julia main.jl --puzzle 66 --checkpoint 1800` (salva a cada 30 minutos).
*   **Desativar**: `julia main.jl --puzzle 66 --checkpoint off` (melhora levemente a performance, mas sem backup).
*   **Como retomar**: Ao abrir o programa, ele detecta o arquivo e pergunta: *"Retomar de onde parou?"* Diga sim para não perder trabalho!

### 🔑 Chaves Encontradas
Sempre que uma chave é encontrada, ela é salva instantaneamente em `outputs/encontradas.txt`. 
> [!CAUTION]
> **MUITO IMPORTANTE**: Nunca compartilhe o seu arquivo `encontradas.txt` ou o conteúdo da pasta `outputs/` com ninguém. É ali que sua fortuna estará guardada.

---

## 🏎️ Otimizações Técnicas Avançadas

*   **Montgomery Batch Inversion**: Uma técnica matemática que permite calcular a inversão de centenas de pontos da curva elíptica quase pelo preço de um.
*   **Zero-Allocation Design**: Reduzimos o uso de memória temporária para que o Julia não precise parar o processamento (Garbage Collection), mantendo KPS constante.
*   **Aritmética Jacobiana**: Usamos coordenadas 3D para evitar divisões matemáticas demoradas, convertendo tudo em multiplicações simples.

---

## 🆘 Solução de Problemas

1.  **"Julia not found"**: Adicione a pasta `bin` do Julia às variáveis de ambiente (PATH) do seu Windows ou reinstale via `winget`.
2.  **"CUDA Error"**: Verifique se sua placa é NVIDIA e se os drivers estão na versão 525 ou superior.
3.  **"PC Travando"**: Reduza a intensidade da GPU (ex: de `:12` para `:4`) ou o número de CPUs (`--cpus 2`).
4.  **"ArgumentError: Package ... not installed"**: Isso significa que as dependências não foram instaladas ou estão corrompidas. Rode: `julia --project=. -e "using Pkg; Pkg.instantiate()"` para resolver.
5.  **"Atualizar pacotes"**: Se quiser garantir que está na última versão de tudo, rode: `julia --project=. -e "using Pkg; Pkg.update()"`


---

## 🏆 Hall da Fama (Puzzles Resolvidos)

Estes são os endereços da **Bitcoin Puzzle Collection** que já foram conquistados pela comunidade. Esta lista serve como referência técnica e inspiração para os mineradores. Cada bit de dificuldade adicional dobra o espaço de busca, tornando as conquistas acima do #66 marcos históricos da criptografia.

<details>
<summary>Clique para visualizar a tabela de soluções (#1 até #130)</summary>

| # | Endereço Bitcoin | Chave Privada (Hex) | Chave Pública | Solucionista / Data |
| :--- | :--- | :--- | :--- | :--- |
| **#1** | `1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH` | `1` | `0279be66...f81798` | 2015-01-15 by 1HdtWQ |
| **#2** | `1CUNEBjYrCn2y1SdiUMohaKUi4wpP326Lb` | `3` | `02f9308a...ce036f` | 2015-01-15 by 1aaRgu |
| **#3** | `19ZewH8Kk1PDbSNdJ97FP4EiCjTRaZMZQA` | `7` | `025cbdf0...ac4f9b` | 2015-01-15 by 1aaRgu |
| **#4** | `1EhqbyUMvvs7BfL8goY6qcPbD6YKfPqb7e` | `8` | `022f01e5...e10a2a` | 2015-01-15 by 1aaRgu |
| **#5** | `1E6NuFjCi27W5zoXg8TRdcSRq84zJeBW3k` | `15` | `02352bbf...25be59` | 2015-01-15 by 1aaRgu |
| **#6** | `1PitScNLyp2HCygzadCh7FveTnfmpPbfp8` | `31` | `03f2dac9...7739f5` | 2015-01-15 by 1aaRgu |
| **#7** | `1McVt1vMtCC7yn5b9wgX1833yCcLXzueeC` | `4c` | `0296516a...3300b2` | 2015-01-15 by 1aaRgu |
| **#8** | `1M92tSqNmQLYw33fuBvjmeadirh1ysMBxK` | `e0` | `0308bc89...ce6b51` | 2015-01-15 by 1aaRgu |
| **#9** | `1CQFwcjw1dwhtkVWBttNLDtqL7ivBonGPV` | `1d3` | `0243601d...659d60` | 2015-01-15 by 1aaRgu |
| **#10** | `1LeBZP5QCwwgXRtmVUvTVrraqPUokyLHqe` | `202` | `03a7a4c3...802289` | 2015-01-15 by 18dy6J |
| **#11** | `1PgQVLmst3Z314JrQn5TNiys8Hc38TcXJu` | `483` | `038b05b0...f3ebc6` | 2015-01-15 by 1KEUP6 |
| **#12** | `1DBaumZxUkM4qMQRt2LVWyFJq5kDtSZQot` | `a7b` | `038b00fc...0ce781` | 2015-01-15 by 1LzgnU |
| **#13** | `1Pie8JkxBT6MGPz9Nvi3fsPkr2D8q3GBc1` | `1460` | `03aadaaa...9a4b86` | 2015-01-15 by 112a7w |
| **#14** | `1ErZWg5cFCe4Vw5BzgfzB74VNLaXEiEkhk` | `2930` | `03b4f1de...351e54` | 2015-01-15 by 1EaFXz |
| **#15** | `1QCbW9HWnwQWiQqVo5exhAnmfqKRrCRsvW` | `68f3` | `02fea58f...4dc3df` | 2015-01-15 by 1363mv |
| **#16** | `1BDyrQ6WoF8VN3g9SAS1iKZcPzFfnDVieY` | `c936` | `029d8c5d...2590b7` | 2015-01-15 by 187Jz6 |
| **#17** | `1HduPEXZRdG26SUT5Yk83mLkPyjnZuJ7Bm` | `1764f` | `033f688b...4e128c` | 2015-01-15 by 1NjGUd |
| **#18** | `1GnNTmTVLZiqQfLbAdp9DVdicEnB5GoERE` | `3080d` | `020ce4a3...55cd4a` | 2015-01-15 by 1Hm4wH |
| **#19** | `1NWmZRpHH4XSPwsW6dsS3nrNWfL1yrJj4w` | `5749f` | `0385663c...09408e` | 2015-01-15 by 1DzcaG |
| **#20** | `1HsMJxNiV7TLxmoF6uJNkydxPFDog4NQum` | `d2c55` | `033c4a45...f6454f` | 2015-01-15 by 1JLtZF |
| **#21** | `14oFNXucftsHiUMY8uctg6N487riuyXs4h` | `1ba534` | `031a746c...8d306e` | 2015-01-15 by 1aaRgu |
| **#22** | `1CfZWK1QTQE3eS9qn61dQjV89KDjZzfNcv` | `2de40f` | `023ed96b...917abb` | 2015-01-15 by 12x45A |
| **#23** | `1L2GM8eE7mJWLdo3HZS6su1832NX2txaac` | `556e52` | `03f82710...3cf28d` | 2015-01-15 by 1aaRgu |
| **#24** | `1rSnXMr63jdCuegJFuidJqWxUPV7AtUf7` | `dc2a04` | `036ea839...1c3490` | 2015-01-15 by 12x45A |
| **#25** | `15JhYXn6Mx3oF4Y7PcTAv2wVVAuCFFQNiP` | `1fa5ee5` | `03057fbe...8dd745` | 2015-01-15 by 12x45A |
| **#26** | `1JVnST957hGztonaWK6FougdtjxzHzRMMg` | `340326e` | `024e4f50...b4f384` | 2015-01-15 by 12x45A |
| **#27** | `128z5d7nN7PkCuX5qoA4Ys6pmxUYnEy86k` | `6ac3875` | `031a864b...90f44e` | 2015-01-15 by 12x45A |
| **#28** | `12jbtzBb54r97TCwW3G1gCFoumpckRAPdY` | `d916ce8` | `03e9e661...dd18c0` | 2015-01-15 by 12x45A |
| **#29** | `19EEC52krRUK1RkUAEZmQdjTyHT7Gp1TYT` | `17e2551e` | `026caad6...7e917b` | 2015-01-15 by 12x45A |
| **#30** | `1LHtnpd8nU5VHEMkG2TMYYNUjjLc992bps` | `3d94cd64` | `030d282c...7a2e92` | 2015-01-16 by 18sLsb |
| **#31** | `1LhE6sCTuGae42Axu1L1ZB7L96yi9irEBE` | `7d4fe747` | `0387dc70...13c8fd` | 2015-01-16 by 12x45A |
| **#32** | `1FRoHA9xewq7DjrZ1psWJVeTer8gHRqEvR` | `b862a62e` | `0209c582...159de6` | 2015-01-16 by 12x45A |
| **#33** | `187swFMjz1G54ycVU56B7jZFHFTNVQFDiu` | `1a96ca8d8` | `03a355aa...3bf2ab` | 2015-01-16 by 18sLsb |
| **#34** | `1PWABE7oUahG2AFFQhhvViQovnCr4rEv7Q` | `34a65911d` | `033cdd9d...040827` | 2015-01-17 by 1MLjeM |
| **#35** | `1PWCx5fovoEaoBowAvF5k91m2Xat9bMgwb` | `4aed21170` | `02f6a814...eada13` | 2015-01-17 by 1HtaAw |
| **#36** | `1Be2UF9NLfyLFbtm3TCbmuocc9N1Kduci1` | `9de820a7c` | `02b3e772...5e47b9` | 2015-01-17 by 18H8sy |
| **#37** | `14iXhn8bGajVWegZHJ18vJLHhntcpL4dex` | `1757756a93` | `027d2c03...ad0f12` | 2015-01-18 by 1AQk96 |
| **#38** | `1HBtApAFA9B2YZw3G2YKSMCtb3dVnjuNe2` | `22382facd0` | `03c060e1...bd70c6` | 2015-01-19 by 18sLsb |
| **#39** | `122AJhKLEfkFBaGAd84pLp1kfE7xK3GdT8` | `4b5f8303e9` | `022d77cd...bc0065` | 2015-01-21 by 1LXyBa |
| **#40** | `1EeAxcprB2PpCnr34VfZdFrkUWuxyiNEFv` | `e9ae4933d6` | `03a2efa4...ee53de` | 2015-01-30 by 1ghost |
| **#41** | `1L5sU9qvJeuwQUdt4y1eiLmquFxKjtHr3E` | `153869acc5b` | `03b357e6...b09034` | 2015-01-30 by 1ghost |
| **#42** | `1E32GPWgDyeyQac4aJxm9HVoLrrEYPnM4N` | `2a221c58d8f` | `03eec883...27142c` | 2015-01-30 by 1ghost |
| **#43** | `1PiFuqGpG8yGM5v6rNHWS3TjsG6awgEGA1` | `6bd3b27c591` | `02a631f9...f0bcda` | 2015-01-30 by 1ghost |
| **#44** | `1CkR2uS7LmFwc3T2jV8C1BhWb5mQaoxedF` | `e02b35a358f` | `025e466e...de3573` | 2015-01-30 by 1ghost |
| **#45** | `1NtiLNGegHWE3Mp9g2JPkgx6wUg4TW7bbk` | `122fca143c05` | `026ecabd...f5da71` | 2015-01-30 by 1ghost |
| **#46** | `1F3JRMWudBaj48EhwcHDdpeuy2jwACNxjP` | `2ec18388d544` | `03fd5487...b6dd58` | 2015-01-30 by 1ghost |
| **#47** | `1Pd8VvT49sHKsmqrQiP61RsVwmXCZ6ay7Z` | `6cd610b53cba` | `023a12bd...5a5941` | 2015-09-01 by 15L3Hy |
| **#48** | `1DFYhaB2J9q1LLZJWKTnscPWos9VBqDHzv` | `ade6d7ce3b9b` | `0291bee5...ec12de` | 2015-09-01 by 15L3Hy |
| **#49** | `12CiUhYVTTH33w3SPUBqcpMoqnApAV4WCF` | `174176b015f4d` | `02591d68...589114` | 2015-09-01 by 15L3Hy |
| **#50** | `1MEzite4ReNuWaL5Ds17ePKt2dCxWEofwk` | `22bd43c2e9354` | `03f46f41...3c5a16` | 2015-09-01 by 15L3Hy |
| **#51** | `1NpnQyZ7x24ud82b7WiRNvPm6N8bqGQnaS` | `75070a1a009d4` | `028c6c67...6c3be7` | 2017-04-05 by LBC |
| **#52** | `15z9c9sVpu6fwNiK7dMAFgMYSK4GqsGZim` | `efae164cb9e3c` | `0374c33b...7f6314` | 2017-04-21 by LBC |
| **#53** | `15K1YKJMiJ4fpesTVUcByoz334rHmknxmT` | `180788e47e326c` | `020faaf5...bc6349` | 2017-09-04 by LBC |
| **#54** | `1KYUv7nSvXx4642TKeuC2SNdTk326uUpFy` | `236fb6d5ad1f43` | `034af4b8...ffb225` | 2017-11-16 by LBC |
| **#55** | `1LzhS3k3e9Ub8i2W1V8xQFdB8n2MYCHPCa` | `6abe1f9b67e114` | `0385a30d...33a8f9` | 2018-05-29 by 1AqEgL |
| **#56** | `17aPYR1m6pVAacXg1PTDDU7XafvK1dxvhi` | `9d18b63ac4ffdf` | `033f2db2...863799` | 2018-09-08 by 1AqEgL |
| **#57** | `15c9mPGLku1HuW9LRtBf4jcHVpBUt8txKz` | `1eb25c90795d61c` | `02a521a0...8db07a` | 2018-11-08 by 1AqEgL |
| **#58** | `1Dn8NF8qDyyfHMktmuoQLGyjWmZXgvosXf` | `2c675b852189a21` | `03115694...38875f` | 2018-12-03 by 1DZfjf |
| **#59** | `1HAX2n9Uruu9YDt4cqRgYcvtGvZj1rbUyt` | `7496cbb87cab44f` | `0241267d...802148` | 2019-02-12 by zielar |
| **#60** | `1Kn5h2qpgw9mWE5jKpk8PP4qvvJ1QVy8su` | `fc07a1825367bbe` | `0348e843...eb89a1` | 2019-02-17 by zielar |
| **#61** | `1AVJKwzs9AskraJLGHAZPiaZcrpDr1U6AB` | `13c96a3742f64906` | `0249a438...b26f45` | 2019-05-11 by zielar |
| **#62** | `1Me6EfpwZK5kQziBwBfvLiHjaPGxCKLoJi` | `363d541eb611abee` | `03231a67...ea14fe` | 2019-09-08 by bc1q05 |
| **#63** | `1NpYjtLira16LfGbGwZJ5JbDPh3ai9bjf4` | `7cce5efdaccf6808` | `0365ec29...1a5457` | 2019-07-12 by zielar |
| **#64** | `16jY7qLJnxb7CHZyqBP8qca9d51gAjyXQN` | `f7051f27b09112d4` | `03100611...25d9d4` | 2022-09-10 by 36X5Cc |
| **#65** | `18ZMbwUFLMHoZBbfpCjUJQTCMCbktshgpe` | `1a838b13505b26867` | `0230210c...c0216b` | 2019-06-07 by 3GVSoQ |
| **#66** | `13zb1hQbWVsc2S7ZTZnP2G4undNNpdh5so` | `2832ed74f2b5e35ee` | `024ee2be...dd74cb` | 2024-09-12 by 1Jvv4y |
| **#67** | `1BY8GQbnueYofwSuFAT3USAhGjPrkxDdW9` | `730fc235c1942c1ae` | `0212209f...2b7d46` | 2025-02-21 by Kowala |
| **#68** | `1MVDYgVaSN6iKKEsbzRUAYFrYJadLYZvvZ` | `bebb3940cd0fc1491` | `031fe02f...0a93ba` | 2025-04-06 by Kowala |
| **#69** | `19vkiEajfhuZ8bs8Zu2jgmC6oqZbWqhxhG` | `101d83275fb2bc7e0c` | `024babad...ed03e7` | 2025-04-30 by bc1qlp |
| **#70** | `19YZECXj3SxEZMoUeJ1yiPsw8xANe7M7QR` | `349b84b6431a6c4ef1` | `0290e690...212484` | 2019-06-09 by pikachunakapika |
| **#75** | `1J36UjUByGroXcCvmj13U6uwaVv9caEeAt` | `4c5ce114686a1336e07` | `03726b57...660447` | 2019-06-10 by pikachunakapika |
| **#80** | `1BCf6rHUW6m3iH2ptsvnjgLruAiPQQepLe` | `ea1a5c66dcc11b5ad180` | `037e1238...1c2a19` | 2019-06-11 by pikachunakapika |
| **#85** | `1Kh22PvXERd2xpTQk3ur6pPEqFeckCJfAr` | `11720c4f018d51b8cebba8` | `0329c457...7c83e7` | 2019-06-17 by pikachunakapika |
| **#90** | `1L12FHH2FHjvTviyanuiFVfmzCy46RRATU` | `2ce00bb2136a445c71e85bf` | `035c38bd...1e85bf` | 2019-07-01 by pikachunakapika |
| **#95** | `19eVSDuizydXxhohGh8Ki9WY9KsHdSwoQC` | `527a792b183c7f64a0e8b1f4" | `02967a59...5c88a0` | 2019-07-06 by 1AmDbs |
| **#100** | `1KCgMv8fo2TPBpddVi9jqmMmcne9uSNJ5F` | `af55fc59c335c8ec67ed24826` | `03d2063d...4f8e67` | 2019-07-08 by 125CWt |
| **#105** | `1CMjscKB3QW7SDyQ4c3C3DEUHiHRhiZVib` | `16f14fc2054cd87ee6396b33df3` | `03bcf7ce...5c39d7` | 2019-09-23 by 57fe |
| **#110** | `12JzYkkN76xkwvcPT6AWKZtGX6w2LAgsJg` | `35c0d7234df7deb0f20cf7062444` | `0309976b...16167d` | 2020-05-30 by zielar |
| **#115** | `1NLbHuJebVwUZ1XqDjsAyfTRUPwDQbemfv` | `60f4d11574f5deee49961d9609ac6` | `0248d313...b7cd7f` | 2020-06-16 by zielar |
| **#120** | `17s2b9ksz5y7abUm92cHwG8jEPCzK3dLnT` | `b10f22572c497a836ea187f2e1fc23` | `02ceb6cb...885a26` | 2023-02-27 by RetiredCoder |
| **#125** | `1PXAyUB8ZoH3WD8n5zoAthYjN15yN5CVq5` | `1c533b6bb7f0804e09960225e44877ac` | `0233709e...46f00e` | 2023-07-09 by RetiredCoder |
| **#130** | `1Fo65aKq8s8iquMt6weF1rku1moWVEd5Ua` | `33e7665705359f04f28b88cf897c603c9` | `03633cbe...099378` | -- |

</details>

---
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA) 🚀

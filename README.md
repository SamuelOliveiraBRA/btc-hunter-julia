# 🚀 BTC Key Hunter (Julia Edition) - O Manual Mestre v2.5.0

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-Montgomery--Acelerado-orange)](#-motores-de-busca)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)

Este é o manual definitivo para o **BTC Key Hunter**, um ecossistema de busca de chaves privadas Bitcoin de altíssima performance para resolver a **Bitcoin Puzzle Collection**. Este documento agrupa todo o conhecimento técnico, guias de instalação e exemplos práticos para o uso 100% eficaz da ferramenta.

---

## 📋 Sumário
1.  [🧩 O que são os Bitcoin Puzzles?](#-o-que-são-os-bitcoin-puzzles)
2.  [📦 Guia de Instalação (Windows, Mac, Linux)](#-guia-de-instalação-windows-mac-linux)
3.  [🧠 A Anatomia do Comando (Explicação Linha por Linha)](#-a-anatomia-do-comando-explicação-linha-por-linha)
4.  [⚙️ Motores de Busca: BitCrack vs Julia vs BSGS](#️-motores-de-busca-bitcrack-vs-julia-vs-bsgs)
5.  [💡 Enciclopédia de Exemplos Práticos](#-enciclopédia-de-exemplos-práticos)
6.  [🖥️ Manual do Modo Interativo (Menu)](#️-manual-do-modo-interativo-menu)
7.  [🛡️ Segurança e Checkpoints](#️-segurança-e-checkpoints)
8.  [🏎️ Otimizações Técnicas Avançadas](#️-otimizações-técnicas-avançadas)
9.  [🆘 Solução de Problemas](#-solução-de-problemas)

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
*   **Ação**: Define o tamanho do lote de chaves. 
*   **Por que importa?**: O processador não testa uma chave por vez e para. Ele testa 1024 chaves, guarda o resultado em um "pacote" e pergunta ao sistema: "Alguma dessas abriu a carteira?". Isso reduz o desperdício de tempo.

---

## ⚙️ Motores de Busca: BitCrack vs Julia vs BSGS

| Motor | Nome Técnico | Características |
| :--- | :--- | :--- |
| **BitCrack** | `bitcrack` | O mais rápido. Matemática de campo finito ultra-otimizada. Uso obrigatório para GPU. |
| **Julia/KeyHunter** | `secp` | Versão estável baseada no SecpOptimized. Excelente para multi-threading em CPUs Intel/AMD. |
| **BSGS** | `bsgs` | Algoritmo de colisão (Baby-Step Giant-Step). Muito rápido em áreas pequenas, mas engole muita memória RAM. |

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

Se você apenas rodar `julia main.jl`, verá o menu dinâmico:
1.  **Configurar CPUs**: Você pode escolher usar menos núcleos se precisar trabalhar enquanto o hunter roda.
2.  **Consulta de Saldo**: O sistema checa via API se o endereço alvo ainda tem fundos antes de gastar energia.
3.  **Configurações Avançadas**: Permite trocar o `Batch Size` (Lote) e o formato (Comprimido/Não-comprimido).

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
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA) 🚀

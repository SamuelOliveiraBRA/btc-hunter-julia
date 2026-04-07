# 🚀 BTC Key Hunter (Julia Edition) v2.3.0

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-Montgomery--Acelerado-orange)](#-motores-de-busca)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)

O **BTC Key Hunter** é um ecossistema de busca de chaves privadas Bitcoin de altíssima performance, desenvolvido para resolver a **Bitcoin Puzzle Collection**. Desenvolvido inteiramente em Julia, o sistema utiliza algoritmos matemáticos avançados para maximizar a taxa de chaves testadas por segundo.

---

## 📋 Sumário
- [📦 Guia de Instalação Passo a Passo](#-guia-de-instalação-passo-a-passo)
- [🧩 O que são os Bitcoin Puzzles?](#-o-que-são-os-bitcoin-puzzles)
- [⚙️ Motores de Busca: O Coração do Sistema](#️-motores-de-busca-o-coração-do-sistema)
- [🛠️ Dicionário de Parâmetros (Linha por Linha)](#️-dicionário-de-parâmetros-linha-por-linha)
- [💡 Galeria de Exemplos Ultra-Detalhados](#-galeria-de-exemplos-ultra-detalhados)
- [🖥️ Manual do Modo Interativo (Menu)](#️-manual-do-modo-interativo-menu)
- [🏎️ Otimizações Técnicas](#️-otimizações-técnicas)
- [🆘 Solução de Problemas (Troubleshooting)](#-solução-de-problemas-troubleshooting)

---

## 📦 Guia de Instalação Passo a Passo

### Windows (Via Terminal)
A maneira mais moderna e recomendada é usar o `winget`:
1.  Abra o PowerShell como Administrador.
2.  `winget install Julia.Julia` → Instala a linguagem Julia.
3.  `git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git` → Baixa o projeto.
4.  `cd btc-hunter-julia` → Entra na pasta.
5.  `julia --project=. -e "using Pkg; Pkg.instantiate()"` → Instala todas as bibliotecas necessárias automaticamente.

---

## 🧩 O que são os Bitcoin Puzzles?

Em 2015, um usuário anônimo enviou Bitcoins para diversos endereços com um padrão matemático:
*   **Puzzle #1**: A chave privada está entre 1 e 1 (1 bit).
*   **Puzzle #66**: A chave está num range de $2^{65}$ a $2^{66}-1$.
*   **A Caçada**: O objetivo é varrer esse intervalo específico (Range) para encontrar a chave privada que assina o endereço alvo e permite o saque.

---

## ⚙️ Motores de Busca: O Coração do Sistema

O software possui três "cérebros" (motores) diferentes:

1.  **BitCrack Engine (`bitcrack`)**: Focado em velocidade extrema. Ideal para quem usa GPU.
2.  **SecpOptimized / Julia (`secp`)**: Versão estável baseada na lógica do KeyHunter original. Melhor para buscas simultâneas em vários endereços.
3.  **BSGS Engine (`bsgs`)**: Usa muita memória RAM para "pular" etapas. Muito rápido em fatias pequenas.

---

## 🛠️ Dicionário de Parâmetros (Linha por Linha)

Quando você digita um comando, cada parte tem uma função vital:

*   `julia`: Chama a linguagem de programação.
*   `--threads auto`: Diz ao Julia para usar todos os núcleos (Logical Cores) do seu processador.
*   `main.jl`: O arquivo principal que orquestra toda a busca.
*   `--puzzle 66`: Diz ao sistema qual puzzle você quer atacar (1 a 160).
*   `--modo 1`: Define o comportamento: `1` (Sequencial), `2` (Reverso), `3` (Aleatório).
*   `--motor bitcrack`: Escolhe qual dos três motores explicados acima será usado.
*   `--porcentagem 50`: Define o ponto de partida relativo ao tamanho do range. `50` significa começar exatamente do meio.
*   `--cpus 4`: Limita a busca a apenas 4 núcleos do seu processador.
*   `--gpu:8`: Ativa a placa de vídeo. O número `:8` define a intensidade do kernel (quanto maior, mais KPS, mas o PC pode ficar lento para outras tarefas).
*   `--batch 1024`: Define quantas chaves cada CPU/Thread processa por vez antes de reportar progresso. No Windows/Mac, `1024` ou `2048` costumam ser ideais.

---

## 💡 Galeria de Exemplos Ultra-Detalhados

### 🟢 Exemplo 1: Uso Somente com Porcentagem
*Ideal para dividir o trabalho entre computadores.*
```bash
julia --threads auto main.jl --puzzle 71 --modo 1 --porcentagem 25.5
```
**O que este comando faz linha por linha:**
1. `julia --threads auto`: Inicia o sistema com força máxima de CPU.
2. `main.jl --puzzle 71`: Foca no Puzzle #71.
3. `--modo 1`: Configura para busca Sequencial (do menor para o maior).
4. `--porcentagem 25.5`: Calcula exatamente 25.5% do range total e começa a busca a partir daí.

---

### 🔵 Exemplo 2: Alternando Modos de Busca
*Comparativo entre Sequencial e Aleatório.*
```bash
# Modo Reverso (Do fim para o início)
julia --threads auto main.jl --puzzle 66 --modo 2

# Modo Aleatório (Sorteando chaves)
julia --threads auto main.jl --puzzle 66 --modo 3
```
**O que acontece:**
* No `--modo 2`, o sistema carrega o valor máximo do Puzzle 66 e vai subtraindo 1 a cada tentativa.
* No `--modo 3`, o sistema pula para partes aleatórias do range. Excelente se o sequencial já foi muito explorado pela comunidade.

---

### 🔴 Exemplo 3: Aceleração via GPU
*O "Turbo" do sistema.*
```bash
julia --threads auto main.jl --puzzle 67 --motor bitcrack --gpu:12
```
**O que este comando faz linha por linha:**
1. `--motor bitcrack`: Seleciona o motor mais rápido para kernels de vídeo.
2. `--gpu:12`: Inicializa a placa de vídeo NVIDIA com intensidade 12.
3. O sistema usará os núcleos CUDA para calcular as chaves em paralelo, atingindo milhões de KPS.

---

### 🟡 Exemplo 4: Escolha de Motor (Julia vs BitCrack)
*Diferença entre motores.*
```bash
# Motor Julia (Antigo/Estável)
julia --threads auto main.jl --puzzle 66 --motor secp

# Motor BitCrack (Novo/Rápido)
julia --threads auto main.jl --puzzle 66 --motor bitcrack
```
**Explicação Detalhada:**
* O `--motor secp` usa a biblioteca `SecpOptimized` em Julia puro. É ótimo para quem tem CPUs Intel/AMD modernas.
* O `--motor bitcrack` usa campos finitos e aritmética jacobiana agressiva. Se você quer velocidade bruta, este é o comando.

---

## 🏎️ Otimizações Técnicas

*   **Montgomery Batch Inversion**: Economiza 99% do processamento em divisões modulares.
*   **Jacobian Coordinates**: Transforma geometria plana em espacial para acelerar a curva elíptica.
*   **Checkpoint Automático**: Se você digitar `Ctrl+C` ou a energia cair, o sistema salva o progresso e permite retomar no mesmo comando depois.

---

## 🆘 Solução de Problemas (Troubleshooting)

| Erro | Solução |
| :--- | :--- |
| `julia as a command not found` | Julia não foi instalado ou não está no PATH. Use o instalador winget. |
| `CUDA not available` | Seus drivers da NVIDIA precisam de atualização ou você não tem placa compatível. |
| `Out of memory` | Você tentou usar o `--motor bsgs` com um range muito grande ou pouca RAM. Use `--motor bitcrack`. |

---
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA) 🚀

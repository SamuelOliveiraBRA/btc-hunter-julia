# 🚀 BTC Key Hunter (Julia Edition) v2.2.0

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-Montgomery--Acelerado-orange)](#-motores-de-busca)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)

O **BTC Key Hunter** é um ecossistema de busca de chaves privadas Bitcoin de altíssima performance, desenvolvido para resolver a **Bitcoin Puzzle Collection**. Desenvolvido inteiramente em Julia, o sistema utiliza algoritmos matemáticos avançados de baixo nível para maximizar a taxa de chaves testadas por segundo (Keys per Second - KPS).

---

## 📋 Sumário
- [📦 Instalação](#-instalação)
- [🧩 O que são os Bitcoin Puzzles?](#-o-que-são-os-bitcoin-puzzles)
- [⚙️ Motores de Busca](#️-motores-de-busca)
- [🛠️ Guia Detalhado de Comandos (CLI)](#️-guia-detalhado-de-comandos-cli)
- [🖥️ Modo Interativo (Menu)](#️-modo-interativo-menu)
- [💡 Exemplos Práticos de Uso](#-exemplos-práticos-de-uso)
- [🎯 Estratégias para o Puzzle #71](#-estratégias-para-o-puzzle-71)
- [🏎️ Otimizações Técnicas](#️-otimizações-técnicas)

---

## 📦 Instalação

### 1. Windows (A maneira mais rápida)
Se você usa Windows 10 ou 11, pode instalar tudo via terminal (PowerShell) em segundos:
```bash
# Instalar o Julia via Winget
winget install Julia.Julia

# Reinicie o terminal e clone o projeto
git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git
cd btc-hunter-julia

# Instalar dependências (dentro da pasta do projeto)
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

### 2. macOS / Linux
Utilize o gerenciador de pacotes ou download manual:
```bash
# macOS (Homebrew)
brew install --cask julia

# Linux/macOS Clone & Setup
git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git
cd btc-hunter-julia
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

---

## 🧩 O que são os Bitcoin Puzzles?

A **Bitcoin Puzzle Collection** foi iniciada em 2015 por um anônimo que enviou quantidades crescentes de Bitcoin para endereços cujas chaves privadas seguem um padrão específico de bits.

*   **O Padrão**: As chaves privadas são numeradas. O Puzzle #1 tem uma chave de 1 bit, o #2 de 2 bits, e assim por diante.
*   **O Desafio**: A cada novo nível, o "espaço de busca" dobra. O Puzzle #66, por exemplo, tem um prêmio de 6.6 BTC e requer encontrar uma chave entre `0x2000...` e `0x3fff...`.
*   **Por que o Julia?**: A busca por força bruta exige trilhões de cálculos de curva elíptica (`secp256k1`). O Julia nos permite chegar perto da performance do C++ com a facilidade de prototipagem do Python.

---

## ⚙️ Motores de Busca

Este software inclui múltiplos "motores", cada um com uma filosofia de busca:

### 1. BitCrack Engine (`bitcrack`) ⚡
O motor de "corrida". Ele ignora complexidades e foca em gerar pontos da curva elíptica o mais rápido possível.
*   **Ideal para**: Deixar o computador ligado por dias em um único puzzle grande.
*   **Nota**: Suporta aceleração total via GPU.

### 2. SecpOptimized / KeyHunter (`secp`) 🛠️
Baseado na implementação do famoso software `KeyHunter`, mas refatorado para Julia.
*   **Ideal para**: Usuários que buscam estabilidade e querem testar múltiplos endereços (multi-target) simultaneamente.
*   **Vantagem**: Menor uso de memória que o BSGS.

### 3. BSGS Engine (`bsgs`) 🧠
Utiliza o algoritmo **Baby-Step Giant-Step**. 
*   **Como funciona**: Ele pré-calcula uma tabela na memória RAM para encontrar colisões. 
*   **Vantagem**: Pode ser drasticamente mais rápido para cobrir fatias pequenas de range.
*   **Desvantagem**: Se você tiver pouca RAM, o sistema pode travar.

---

## 🛠️ Guia Detalhado de Comandos (CLI)

Use o comando `julia --threads auto main.jl` seguido de:

| Comando | Descrição Técnica | Por que usar? |
| :--- | :--- | :--- |
| `--puzzle N` | Define o ID do puzzle da lista oficial (1-160). | Para carregar automaticamente o intervalo de busca e o endereço alvo. |
| `--modo 1` | **Sequencial**: Começa do início do range (`min`) e vai subindo. | Melhor para varreduras organizadas e uso de checkpoints. |
| `--modo 2` | **Reverso**: Começa do final do range (`max`) e vai descendo. | Estratégia comum quando se acredita que a chave está no final do bit. |
| `--modo 3` | **Aleatório**: Sorteia números dentro do intervalo. | Útil para "sorte" ou quando o range sequencial já foi muito explorado. |
| `--porcentagem P` | Pula direto para uma posição relativa (ex: `50.0`). | Essencial para dividir o trabalho entre vários computadores. |
| `--batch N` | Quantidade de chaves testadas antes de atualizar a tela. | Valores maiores (1024, 2048) aumentam o KPS, mas diminuem a fluidez da UI. |
| `--gpu` | Ativa o motor CUDA para placas NVIDIA. | Aumenta o desempenho em até 50x comparado a uma CPU comum. |
| `--ambos-formatos` | Testa chaves comprimidas e não-comprimidas. | Alguns puzzles antigos podem usar o formato não-comprimido. |

---

## 🖥️ Modo Interativo (Menu)

Se você apenas digitar `julia main.jl`, o sistema abrirá um **Wizard de Configuração**:

1.  **Dashboard**: Mostra o status atual das CPUs e se a internet está ativa.
2.  **Consulta de Saldo**: Se a internet estiver ativa, o sistema checa o valor em BTC do endereço antes de começar.
3.  **Gerenciador de Checkpoint**: Se você fechar o programa, ele pergunta: *"Deseja retomar do ponto X?"*. Isso evita perder horas de processamento.

---

## 💡 Exemplos Práticos de Uso

### Cenário A: "Quero máxima velocidade na minha GPU"
Para buscar o Puzzle 66 usando sua placa de vídeo:
```bash
julia --threads auto main.jl --puzzle 66 --motor bitcrack --gpu:8
```

### Cenário B: "Vou dividir o range 71 com um amigo"
Você começa do 0% e seu amigo começa do 50%:
*   **Você**: `julia --threads auto main.jl --puzzle 71 --modo 1 --porcentagem 0`
*   **Amigo**: `julia --threads auto main.jl --puzzle 71 --modo 1 --porcentagem 50`

### Cenário C: "Modo Econômico" (Fundo enquanto trabalha)
Usa apenas 2 núcleos da CPU para não travar o PC:
```bash
julia --threads auto main.jl --puzzle 66 --cpus 2 --batch 256
```

---

## 🎯 Estratégias para o Puzzle #71

O Puzzle 71 é massivo ($2^{70}$ a $2^{71}$). Algumas dicas:
1.  **Mantenha o Checkpoint Ativo**: Nunca rode sem ele. Se o PC reiniciar, você continua de onde parou.
2.  **Batch Size**: No 71, use `--batch 2048`. Como o range é enorme, você quer o máximo de eficiência bruta.
3.  **Foco em BitCrack**: Para este nível de dificuldade, o motor BitCrack é o que apresenta as melhores métricas de KPS.

---

## 🏎️ Otimizações Técnicas

Este projeto implementa o estado da técnica em criptografia:
*   **Montgomery Batch Inversion**: Uma técnica que transforma centenas de divisões modulares pesadas em uma única inversão e algumas multiplicações rápidas.
*   **Zero-Allocation Loops**: O código foi escrito para que o Julia não precise acionar o *Garbage Collector*, mantendo a velocidade constante.
*   **Aceleração de Kernel**: Os cálculos de GPU são feitos em kernels otimizados que conversam diretamente com o hardware.

---

> [!CAUTION]
> **Aviso de Aquecimento**: O uso intensivo de CPU/GPU por longos períodos pode gerar calor. Certifique-se de que seu sistema de refrigeração está funcionando corretamente.

---
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA) 🚀

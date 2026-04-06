# 🚀 BTC Key Hunter (Julia Edition)

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-OpenSSL--Acelerado-orange)](https://www.openssl.org)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

O **BTC Key Hunter** é um motor de busca de chaves privadas de alta performance, otimizado para os desafios da **Bitcoin Puzzle Collection**. Agora com suporte a **Aceleração via GPU (NVIDIA/CUDA)**!

---

## 📋 Sumário
*   [🚀 Instalação](#-instalação-do-julia-passo-a-passo)
*   [🛠️ Como Usar (Exemplos)](#-como-usar)
*   [🎮 Aceleração por GPU](#-aceleração-por-gpu)
*   [🏎️ Performance e Otimizações](#️-performance-e-otimizações)
*   [⚠️ Requisitos de Driver](#-requisitos-de-driver-importante)

---

## 🚀 Instalação do Julia (Passo a Passo)

### 1. Sistema Operacional
- **Windows**: `winget install julia -s msstore`
- **Linux/macOS**: `curl -fsSL https://install.julialang.org | sh`

### 2. Configurando o Hunter
```bash
git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git
cd btc-hunter-julia
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

---

## 🛠️ Como Usar

O Hunter aceita diversos parâmetros para otimizar sua busca. Use sempre `-t auto` para máximo aproveitamento de threads.

### Exemplos Práticos:

#### 1. Busca Sequencial Simples (Puzzle #66)
```bash
julia -t auto main.jl --puzzle 66
```

#### 2. Definindo Porcentagem de Início (ex: Começar em 40% do Puzzle #71)
Ótimo para dividir o trabalho entre máquinas:
```bash
julia -t auto main.jl --puzzle 71 --porcentagem 40
```

#### 3. Modos de Busca específicos
- `--modo 1`: Sequencial (Padrão)
- `--modo 2`: Reverso (Do fim para o início)
- `--modo 3`: Randômico (Sorteio de intervalos)

```bash
julia -t auto main.jl --puzzle 66 --modo 3
```

#### 4. Definindo número de CPUs manualmente
```bash
julia -t auto main.jl --puzzle 66 --cpus 4
```

---

## 🎮 Aceleração por GPU

O Hunter agora suporta placas de vídeo NVIDIA para multiplicar sua velocidade de busca.

### Comando com GPU e Intensidade:
Use o parâmetro `--gpu` ou `--gpu:N` (onde N é o nível de intensidade):

```bash
# Busca no Puzzle 71, começando em 40%, usando GPU com intensidade 7
julia -t auto main.jl --puzzle 71 --modo 1 --porcentagem 40 --gpu:7
```

---

## ⚠️ Requisitos de Driver (Importante)

Para utilizar a aceleração por **GPU**, o seu sistema deve atender aos seguintes requisitos:

> [!IMPORTANT]
> **Drivers NVIDIA**: É necessário ter drivers da NVIDIA versão **525 ou superior** (compatíveis com CUDA 12).
> Se o seu driver for antigo (ex: compatível apenas com CUDA 11.6), o programa exibirá um erro de inicialização e entrará em **Modo de Segurança (CPU)** automaticamente para não interromper a busca.

---

## 🏎️ Performance e Otimizações

*   **Aritmética Jacobiana**: Reduz o custo da soma de pontos elípticos.
*   **Montgomery Batch Normalization**: Normaliza centenas de pontos em uma única inversão modular.
*   **Aceleração Nativa**: SHA256 e RIPEMD160 via `libcrypto` (OpenSSL).
*   **GPU Kernels**: Implementação customizada para cálculos de 256-bits em hardware de vídeo.

---

## ⚠️ Atenção
Sempre faça backup de suas descobertas localizadas em `outputs/encontradas.txt`.

---
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA). Se este projeto te ajudou, deixe uma ⭐!

# 🚀 BTC Key Hunter (Julia Edition)

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-OpenSSL--Acelerado-orange)](https://www.openssl.org)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

O **BTC Key Hunter** é um motor de busca de chaves privadas de alta performance, otimizado para resolver os desafios da **Bitcoin Puzzle Collection**. Utilizando aritmética de coordenadas Jacobianas e aceleração nativa via `libcrypto`, ele alcança velocidades competitivas diretamente no seu hardware.

---

## 📋 Sumário
*   [🚀 Instalação do Julia (Passo a Passo)](#-instalação-do-julia-passo-a-passo)
*   [✅ Validação do Ambiente](#-validação-do-ambiente)
*   [🛠️ Como Usar](#-como-usar)
*   [🏎️ Performance e Otimizações](#️-performance-e-otimizações)
*   [📁 Estrutura do Projeto](#-estrutura-do-projeto)

---

## 🚀 Instalação do Julia (Passo a Passo)

### 1. Sistema Operacional
O Hunter roda em Windows, macOS e Linux. Recomendamos a instalação via **juliaup** (o instalador oficial moderno).

*   **Windows**: Abra o Terminal/PowerShell e digite:
    ```powershell
    winget install julia -s msstore
    ```
*   **macOS / Linux**: Abra o Terminal e digite:
    ```bash
    curl -fsSL https://install.julialang.org | sh
    ```

### 2. Configurando o Hunter
Após instalar o Julia, clone este repositório e inicialize as bibliotecas:
```bash
git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git
cd btc-hunter-julia
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

---

## ✅ Validação do Ambiente

Antes de iniciar uma busca pesada, valide se as suas bibliotecas e threads estão funcionando 100%:

```bash
# Este comando verifica Threads, Bibliotecas e Crypto (libcrypto/SHA2)
julia --project=. main.jl --validate
```

> [!TIP]
> No macOS e Linux, a `libcrypto` (OpenSSL) já está incluída. No Windows, instalar o **Git Bash** costuma resolver todas as dependências de criptografia nativa.

---

## 🛠️ Como Usar

O Hunter é modular e aceita diversos parâmetros. Para o melhor desempenho, use o parâmetro `-t auto`:

### Busca Sequencial (Padrão)
Ideal para Puzzles pequenos como o **#25**:
```bash
julia -t auto main.jl --puzzle 25
```

### Busca por Carteira Específica (Legacy)
O motor suporta automaticamente chaves **Uncompressed** (início do desafio):
```bash
julia -t auto main.jl --puzzle 18
```

### Busca Randômica (Deep Search)
Para Puzzles maiores como o **#66**:
```bash
julia -t auto main.jl --puzzle 66 --modo 3
```

---

## 🏎️ Performance e Otimizações

Injetamos diversas técnicas de baixo nível para garantir que você aproveite cada ciclo da sua CPU:

*   **Aritmética Jacobiana**: Reduzimos o custo da soma de pontos elípticos evitando inversões modulares frequentes.
*   **Montgomery Batch Normalization**: Normalizamos centenas de pontos de uma só vez (Operação O(1) amortizada).
*   **OpenSSL Handshake**: As funções `SHA256` e `RIPEMD160` são chamadas via `ccall` diretamente da `libcrypto` nativa, eliminando o overhead do Julia puro.
*   **Multi-Threading Inteligente**: Distribuição de carga Base58 e curvas elípticas paralela.

---

## ⚠️ Atenção
A busca por chaves privadas é um processo estatístico. Este software é fornecido "como está". Sempre faça backup de suas descobertas localizadas em `outputs/encontradas.txt`.

---
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA). Se este projeto te ajudou, deixe uma ⭐!

# 🚀 BTC Key Hunter (Julia Edition) v2.1.0

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-Montgomery--Acelerado-orange)](#-motores-de-busca)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)

O **BTC Key Hunter** é um ecossistema de busca de chaves privadas Bitcoin de altíssima performance, desenvolvido para resolver a **Bitcoin Puzzle Collection**. Desenvolvido inteiramente em Julia, o sistema utiliza algoritmos matemáticos avançados de baixo nível para maximizar a taxa de chaves testadas por segundo (Keys per Second - KPS).

---

## 📋 Sumário
- [📦 Instalação](#-instalação)
- [⚙️ Motores de Busca](#️-motores-de-busca)
- [🛠️ Guia de Comandos (CLI)](#️-guia-de-comandos-cli)
- [🖥️ Modo Interativo (Menu)](#️-modo-interativo-menu)
- [💡 Exemplos de Uso](#-exemplos-de-uso)
- [🎯 Caso Especial: Puzzle #71](#-caso-especial-puzzle-71)
- [🏎️ Otimizações Técnicas](#️-otimizações-técnicas)

---

## 📦 Instalação

### 1. Requisitos do Sistema
*   **Julia 1.10+**: O coração do sistema. [Download oficial](https://julialang.org/downloads/).
*   **Drivers NVIDIA (Opcional)**: Necessário para aceleração via GPU (CUDA).
*   **Git**: Para clonar o repositório.

### 2. Passo a Passo de Instalação

#### No Linux / macOS
```bash
# Clone o repositório
git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git
cd btc-hunter-julia

# Instale as dependências automaticamente
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

#### No Windows
1. Baixe e instale o Julia pelo site oficial.
2. Abra o terminal (PowerShell ou CMD) e execute os comandos acima.

> [!TIP]
> No macOS, você pode instalar o Julia via Homebrew: `brew install --cask julia`.

---

## ⚙️ Motores de Busca

O sistema oferece três motores distintos, selecionáveis via menu ou CLI:

### 1. BitCrack Engine (`bitcrack`) ⚡
O motor de maior performance para buscas sequenciais e em lote.
*   **Tecnologia**: Utiliza as bibliotecas internas `FastField` e `FastSecp`.
*   **Destaque**: Otimizado para CPU e GPU simultaneamente.
*   **Uso Ideal**: Brute-force de longa duração em ranges grandes.

### 2. SecpOptimized / KeyHunter (`secp`) 🛠️
Implementação baseada em `BigInt` com otimizações de curva elíptica.
*   **Tecnologia**: Aritmética Jacobiana customizada.
*   **Destaque**: Extremamente estável e preciso, ideal para validar chaves específicas.
*   **Uso Ideal**: Testes de validação e puzzles de nível inicial a médio.

### 3. BSGS Engine (`bsgs`) 🧠
Algoritmo Baby-Step Giant-Step.
*   **Destaque**: Reduz a complexidade temporal da busca, mas requer uma quantidade significativa de RAM.
*   **Uso Ideal**: Ranges pequenos ou quando você tem muita memória disponível para colisões.

---

## 🛠️ Guia de Comandos (CLI)

Para rodar em modo "Headless" (direto via comando), utilize a seguinte sintaxe:

```bash
julia --threads auto main.jl [argumentos]
```

### Argumentos Disponíveis:

| Argumento | Descrição | Exemplo |
| :--- | :--- | :--- |
| `--puzzle N` | Define o ID do puzzle (ex: 66, 71, 130). | `--puzzle 71` |
| `--modo M` | `1` (Seq), `2` (Rev), `3` (Random). | `--modo 2` |
| `--motor X` | `bitcrack`, `secp` ou `bsgs`. | `--motor bitcrack` |
| `--porcentagem P` | Inicia em X% do range do puzzle. | `--porcentagem 40.5` |
| `--start HEX` | Inicia a partir de uma chave específica (Hex). | `--start 0x3f5b...` |
| `--cpus N` | Define o número de threads da CPU. | `--cpus 8` |
| `--gpu[:I]` | Ativa GPU. `I` é a intensidade (opcional). | `--gpu:8` |
| `--batch N` | Tamanho do lote de chaves (padrão 512). | `--batch 1024` |
| `--sem-checkpoint` | Desativa o salvamento automático de progresso. | `--sem-checkpoint` |
| `--ambos-formatos` | Testa Comprimido + Não-Comprimido (mais lento). | `--ambos-formatos` |

---

## 🖥️ Modo Interativo (Menu)

Basta rodar `julia --threads auto main.jl` sem argumentos para entrar no menu dinâmico:

1.  **Escolher Carteira**: Lista todos os puzzles conhecidos com status (alcançado/pendente).
2.  **Configurar CPUs**: Ajusta dinamicamente quantas threads Julia deve utilizar.
3.  **Configurar Internet**: Ativa/Desativa consulta de saldo via API do Blockchain.info.
4.  **Configurações Avançadas**: Altera o motor de busca, tamanho do lote e sistema de checkpoint.
5.  **Iniciar Busca**: Abre o Dashboard de progresso em tempo real.

---

## 💡 Exemplos de Uso

### 1. Uso via CPU (Máxima Performance)
Utiliza todos os núcleos do processador no modo BitCrack:
```bash
julia --threads auto main.jl --puzzle 66 --modo 1 --motor bitcrack
```

### 2. Uso via GPU (Aceleração CUDA)
Ativa a placa de vídeo com intensidade 8:
```bash
julia --threads auto main.jl --puzzle 67 --gpu:8 --motor bitcrack
```

### 3. Retomada com Checkpoint
Se você parou uma busca, o sistema detecta automaticamente o arquivo em `outputs/` e pergunta se deseja continuar. Para forçar o início sem carregar o anterior, use `--sem-checkpoint`.

---

## 🎯 Caso Especial: Puzzle #71

O Puzzle #71 (Endereço: `16UwLL9Risc3QfPqBUvK3Zwwyc7z2k9D2Q`) é um dos mais famosos. Recomenda-se as seguintes estratégias:

**Estratégia 1: Busca por Porcentagem (Dividir para Conquistar)**
Se você quer começar da metade do range:
```bash
julia --threads auto main.jl --puzzle 71 --modo 1 --motor bitcrack --porcentagem 50
```

**Estratégia 2: Busca Reversa (Do Máximo para o Mínimo)**
Útil se houver suspeita de que a chave está no final do range:
```bash
julia --threads auto main.jl --puzzle 71 --modo 2 --motor bitcrack
```

**Estratégia 3: Modo Headless com Lote Grande**
Para deixar rodando no servidor (VPS) com baixo consumo de interface:
```bash
julia --threads auto main.jl --puzzle 71 --batch 2048 --motor bitcrack
```

---

## 🏎️ Otimizações Técnicas

Este projeto não é apenas um script, é um motor criptográfico otimizado:

1.  **Montgomery Batch Inversion**: Reduz o custo de inversão modular de **O(N)** para **O(1) + 3 multiplicações** por lote.
2.  **Coordenadas Jacobianas**: Evita divisões custosas durante a soma de pontos na curva Secp256k1.
3.  **FastField / FastSecp**: Bibliotecas internas escritas para evitar alocações de memória desnecessárias (Zero-GC).
4.  **Checkpoint Automático**: Salva o progresso a cada 30 segundos, permitindo quedas de energia ou reinicializações sem perda de trabalho.

---

> [!WARNING]
> **SEGURANÇA**: As chaves encontradas são salvas em `outputs/encontradas.txt`. Mantenha este arquivo seguro e faça backups frequentes.

> [!IMPORTANT]
> **MODULARIDADE**: O sistema foi construído de forma modular. Se você desejar adicionar um novo motor ou filtro de endereço (como Bloom Filters), basta adicionar o componente em `src/` e incluí-lo no `main.jl`.

---
Desenvolvido por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA) 🚀

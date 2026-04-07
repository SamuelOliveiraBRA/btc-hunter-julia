# 🚀 BTC Key Hunter (Julia Edition) v2.4.0

[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia&logoColor=white)](https://julialang.org)
[![Performance](https://img.shields.io/badge/Performance-Montgomery--Acelerado-orange)](#-motores-de-busca)
[![GPU](https://img.shields.io/badge/GPU-CUDA--Acelerado-green)](https://developer.nvidia.com/cuda-zone)

O **BTC Key Hunter** é um ecossistema de busca de chaves privadas Bitcoin de alta performance para resolver a **Bitcoin Puzzle Collection**. Este manual detalha cada comando, cada parâmetro e fornece exemplos exaustivos para todos os cenários.

---

## 📋 Sumário
- [📦 Instalação Detalhada](#-instalação-detalhada)
- [🧩 O que são os Bitcoin Puzzles?](#-o-que-são-os-bitcoin-puzzles)
- [⚙️ Comparativo de Motores](#️-comparativo-de-motores)
- [🛠️ Análise Passo a Passo do Comando](#️-análise-passo-a-passo-do-comando)
- [💡 Galeria Completa de Exemplos](#-galeria-completa-de-exemplos)
- [🖥️ Manual do Menu Interativo](#️-manual-do-menu-interativo)
- [🏎️ Otimizações e Performance](#️-otimizações-e-performance)
- [🆘 Dúvidas Frequentes](#-dúvidas-frequentes)

---

## 📦 Instalação Detalhada

### No Windows (Recomendado)
Use o Gerenciador de Pacotes do Windows (`winget`) para instalação limpa:
1.  **Instalar Julia**: `winget install Julia.Julia`
2.  **Baixar Projeto**: `git clone https://github.com/SamuelOliveiraBRA/btc-hunter-julia.git`
3.  **Configurar**: Entre na pasta e execute `julia --project=. -e "using Pkg; Pkg.instantiate()"`

> **O que o comando de configuração faz?**
> *   `--project=.`: Diz ao Julia para usar a pasta atual como ambiente isolado.
> *   `Pkg.instantiate()`: Baixa e instala todas as bibliotecas (HTTP, JSON, CUDA, etc.) necessárias.

---

## 🧩 O que são os Bitcoin Puzzles?

A **Bitcoin Puzzle Collection** é uma série de endereços contendo BTC, onde as chaves privadas seguem uma sequência de bits (Puzzle 1 = 1 bit, Puzzle 66 = 66 bits). 
O software varre o "espaço matemático" (range) de cada puzzle para encontrar o número secreto que abre a carteira.

---

## 🛠️ Análise Passo a Passo do Comando

Vamos decompor o comando mais completo do sistema:
`julia --threads auto main.jl --puzzle 66 --modo 1 --motor bitcrack --gpu:8 --batch 1024`

| Parte do Comando | O que ela faz exatamente? |
| :--- | :--- |
| `julia` | O motor principal que executa o código. |
| `--threads auto` | Ativa o multi-threading. O Julia detecta quantos núcleos seu PC tem e usa todos. |
| `main.jl` | O script mestre que carrega os motores de busca e a interface. |
| `--puzzle 66` | Seleciona o alvo #66. O sistema já sabe os limites (Range) deste puzzle. |
| `--modo 1` | **Modo Sequencial**: Varre de bit em bit, do menor para o maior. |
| `--motor bitcrack` | Seleciona o motor de "velocidade extrema" (BitCrack Julia Engine). |
| `--gpu:8` | Ativa sua placa de vídeo com intensidade nível 8 para cálculos massivos. |
| `--batch 1024` | Processa 1024 chaves de uma vez antes de atualizar o Dashboard. |

---

## 💡 Galeria Completa de Exemplos

### 1. Exemplo de Porcentagem (Range específico)
*Útil para dividir o trabalho com outras pessoas.*
```bash
julia --threads auto main.jl --puzzle 71 --porcentagem 40.5
```
*   **Ação**: O sistema calcula onde fica 40.5% do caminho total do Puzzle 71 e começa a busca a partir de lá.

### 2. Exemplo de Modos de Busca
*Como o sistema se comporta na varredura.*
```bash
# SEQUENCIAL (Modo 1): Do início para o fim
julia --threads auto main.jl --puzzle 66 --modo 1

# REVERSO (Modo 2): Do fim para o início
julia --threads auto main.jl --puzzle 66 --modo 2

# ALEATÓRIO (Modo 3): Sorteio em todo o range
julia --threads auto main.jl --puzzle 66 --modo 3
```

### 3. Exemplo de Motores (Engines)
*Escolha entre velocidade bruta ou estabilidade.*
```bash
# Motor BITCRACK (Máxima performance)
julia --threads auto main.jl --puzzle 66 --motor bitcrack

# Motor JULIA / KEYHUNTER (Estável / Tradicional)
julia --threads auto main.jl --puzzle 66 --motor secp

# Motor BSGS (Baseado em RAM - Colisão)
julia --threads auto main.jl --puzzle 66 --motor bsgs
```

### 4. Exemplo de Aceleração GPU
*Para usuários com placas NVIDIA.*
```bash
# GPU ligada com intensidade 10
julia --threads auto main.jl --puzzle 67 --gpu:10
```

---

## 🖥️ Manual do Menu Interativo

Ao rodar apenas `julia main.jl`, você entra no modo visual:
1.  **Selecionar Puzzle**: Escolha qual nível quer atacar. O sistema mostra se o puzzle já foi resolvido ou não.
2.  **Configurações Avançadas**: Aqui você ajusta o `Batch Size`.
    *   *Batch 512*: Mais atualizações de tela.
    *   *Batch 2048*: Mais velocidade bruta, tela atualiza menos.
3.  **Checkpoint**: O sistema salva automaticamente onde você parou em `outputs/`. Se você abrir o programa de novo, ele perguntará se quer continuar.

---

## 🏎️ Otimizações e Performance

*   **Montgomery Inversion**: Técnica que acelera a matemática da curva elíptica em até 40x por lote.
*   **Zero-Allocation**: O código foi escrito para não "pausar" para limpar memória (Garbage Collection).
*   **Checkpointing**: Salva o progresso a cada 30 segundos.

---

## 🆘 Dúvidas Frequentes

*   **Posso usar no Wi-Fi?** Sim, mas a internet só é usada se você ativar a opção de "Consultar Saldo" no menu. Caso contrário, a busca é 100% offline.
*   **Minha tela travou?** Se você usar um `--batch` muito alto (ex: 10.000), a tela demorará mais para atualizar, mas o cálculo continua ocorrendo.

---
Desenvolvido com dedicação por [SamuelOliveiraBRA](https://github.com/SamuelOliveiraBRA) 🚀

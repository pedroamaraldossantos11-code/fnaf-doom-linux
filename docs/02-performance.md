# 02 — Performance

Metodologia, dados medidos e a análise que levou ao preset final.

Todos os números vêm da máquina descrita abaixo, com o jogo em **E1M1
(Night 0)** — primeira fase jogável, com iluminação de lanterna, dynamic
lights, modelos 3D e o clima de terror do mod.

> **Escopo dos dados:** a tabela abaixo registra apenas configurações
> efetivamente medidas nesta máquina. Onde um ajuste aparece como "medido
> junto" (sem linha própria na tabela), isso está dito no texto.

---

## Máquina

| | |
|---|---|
| CPU | AMD Ryzen 5 5625U (6c/12t, Zen 3) |
| GPU | AMD Radeon integrada — Vega 8, codinome **RENOIR** |
| Memória | 15 GB, **compartilhada com a GPU** |
| SO | CachyOS (Arch), kernel 7.2.8 |
| Gráficos | Mesa 26.2.3, RADV, Vulkan 1.4.354 |
| Sessão | Hyprland / Wayland (jogo via XWayland) |
| Painel | 1920x1080 @ **60 Hz**, `scale=1.5` |
| Wine | 11.18 (prefixo win64) |
| Jogo | FNAF Doom v4.1.1, GZDoom 4.11.1 |

Duas características dessa máquina pesaram na análise:

1. **A GPU usa RAM do sistema** (a Vega 8 não tem VRAM dedicado), então
   largura de banda de memória é escassa e filtros caros — como anisotropia —
   doem mais do que numa GPU dedicada.
2. **O painel é 60 Hz.** Acima disso não há ganho visível; abaixo disso, o
   objetivo é 60 com folga, não o máximo absoluto.

---

## O problema com "benchmark" do GZDoom

A primeira tentativa foi o comando nativo `benchmark`. O mod não deixou:

```
Unknown command "benchmark"
```

O ZScript do FNAF Doom remove a maior parte dos comandos de console —
`help`, `benchmark`, `version`, `demo`, `netdemo` saem todos. Sondando:

```bash
fnaf-doom --log +cvarlist +ccmdlist +stat +version +quit +benchmark +timedemo
grep -oE 'Unknown command "[a-z_0-9]+"' /tmp/fnaf-doom.log | sort -u
```

Restaram `cvarlist`, `stat`, `timedemo`, `quit`, `skill`, `warp` — o suficiente
para instrumentar, mas sem medidor pronto.

---

## Alternativa: log do MangoHud

O MangoHud grava um CSV por frame com FPS, frametime, carga de CPU/GPU, clock e
temperatura. Habilitando o log automático:

```bash
cp ~/.config/MangoHud/MangoHud.conf /tmp/MangoHud.conf.bak
printf '\nautostart_log=1\noutput_folder=/tmp/mh\nlog_interval=200\n' \
    >> ~/.config/MangoHud/MangoHud.conf

fnaf-doom --mangohud --log -- -warp 1
```

`-warp 1` entra direto no E1M1, pulando a intro. Depois de ~30 s de carga,
matar o jogo e analisar.

> **Restaure a config depois** — senão todo jogo Vulkan passa a gravar log:
> `cp /tmp/MangoHud.conf.bak ~/.config/MangoHud/MangoHud.conf`

### Armadilha na leitura do CSV

O arquivo tem **duas linhas de metadados antes do cabeçalho**:

```
os,cpu,gpu,ram,kernel,driver,cpuscheduler
CachyOS,AMD Ryzen 5 5625U...,AMD Radeon Graphics (RADV RENOIR),...,powersave
fps,frametime,cpu_load,...          <- cabeçalho de verdade
59.8343,16.7128,12.9002,...         <- dados
```

`csv.DictReader` usa a linha 1 como cabeçalho e quebra. Resultado: "sem
amostras" — e a conclusão errada de que o log não funcionou.

```python
import statistics as st
raw = open(csv_path).read().splitlines()
hdr = raw[2].split(',')                        # pular as 2 linhas de metadados
data = [dict(zip(hdr, l.split(','))) for l in raw[3:] if l.strip()]
tail = data[len(data)//2:]                    # gameplay, não a intro
fps = [float(r['fps']) for r in tail]
print(f"mediana={st.median(fps):.1f} min={min(fps):.1f} "
      f"1%low={sorted(fps)[len(fps)//20]:.1f}")
```

### Por que descartar a primeira metade

A série completa começa em 60 FPS mesmo com o preset original pesado demais:

```
  t(s)    fps   gpu%   MHz  gpuC   cpu%
   0.2   59.9     3   400    59     8     <- title
  17.0   60.0    28  1800    60    12     <- ainda cena simples
  22.6   60.1    50   200    61    16     <- transicao
  25.4   50.8    66  1800    69    14     <- gameplay real comeca
  28.2   47.4    76  1800    70    14
  36.6   47.1    78  1800    73    14
  45.0   52.0    77  1800    72     8
  61.8   49.7    78  1800    73     9
```

A queda em ~24 s é a entrada na cena de gameplay. Medir a média inteira daria um
número otimista e sem sentido prático. Daí usar só a metade final.

**Cuidado metodológico:** a câmera fica parada (não há input sintético), então
estes números são custo de *renderização*. Com movimentação real podem cair
um pouco por Updates de colisão e streaming de sons.

---

## Resultados medidos

Mediana de FPS no E1M1 (trecho de gameplay), resolução indicada quando
diferente de 720p:

| Configuração | FPS | GPU% | CPU% | Observação |
|---|---:|---:|---:|---|
| 1080p, preset original do mod | **22** | 87–90 | 7–13 | 2x MSAA + SSAO + bloom + aniso 8x |
| 1600x900, efeitos reduzidos | **36** | — | — | nitidez maior |
| 1152x648, SSAO off | **48** | — | — | ver "resolução", abaixo |
| **720p, preset final (vsync off)** | **~50** | ~78 | 8–14 | 60 em cenas simples |
| 720p, **vsync on** | ~52 | — | — | **spread 47–57** (jitter) |
| 720p, **SSAO on** | **44** | — | — | quase o custo do aniso 8x |
| 720p, **aniso 8x** | **44** | — | — | quase o custo do SSAO |
| 720p, **`cl_capfps=true`** | **35** | — | — | pior que não fazer nada |

Ganho líquido: **22 → ~50 FPS**, com temperatura da GPU até 76 °C e clock no
máximo (1800 MHz).

---

## Análise item por item

### Resolução — e onde ela deixa de importar

| resolução | pixels | FPS |
|---|---:|---:|
| 1920x1080 | 2.07 M | 22 |
| 1600x900 | 1.44 M | 36 |
| 1280x720 | 0.92 M | **~50** |
| 1152x648 | 0.75 M | **~48** |

De 1080p para 720p: 2.27x mais FPS. De 720p para 648p (0.81x de pixels):
**praticamente nada** — 48 contra ~50 está dentro da variação do próprio log.

A curva achata porque, abaixo de certo ponto, o custo deixa de ser fill-rate e
vira fixo por frame: o shadowmap (512², independente de resolução), os passes de
bloom, e o overhead de tradução do Wine nas chamadas de API.

**Conclusão: não adianta baixar de 720p.** E 720p é divisível por 60, o que
ajuda o pacing num painel de 60 Hz.

### SSAO — caro demais aqui

Desligar o SSAO fez parte do mesmo conjunto de mudanças que levou de 36 para
~50 FPS a 1600x900/720p. Ligá-lo de volta, a 720p e com o resto já reduzido,
deu **44 FPS**.

É um efeito que pertence à *nitidez* da imagem (oclusão de contato), não à
construção do clima. Fica desligado no preset padrão, disponível com
`--ssao on` para quem preferir a troca.

### Anisotropia — a surpresa

O mod pedia `gl_texture_filter_anisotropic=8`. Esperava custo irrelevante.
Medindo a 720p, com o resto do preset já aplicado:

| configuração | FPS |
|---|---:|
| aniso 4 | **~50** |
| aniso 8 | **44** |

Cerca de 12% de FPS por um filtro que, olhando de longe, é praticamente
indistinguível. Explicação: 8x aniso significa até 8 amostras por fetch de
textura, e numa GPU sem VRAM dedicado cada amostra extra custa bandwidth do
sistema. **4x é o ponto certo** aqui.

### VSync — desligado

O resultado contraintuitivo do tuning. Com a GPU abaixo de 60 FPS, ligar vsync
faz o frame pacing oscilar entre o frame que coube no intervalo de refresh e o
que não coube:

| | mediana | spread |
|---|---:|---|
| vsync off | ~50 | 48–53 |
| vsync on | ~52 | **47–57** |

A mediana até sobe com vsync, mas o spread quase dobra — e é o spread que se
sente. Com vsync ligado o jogo dá uma pulsação rítmica perceptível. Desligado,
varia poucos FPS de forma contínua e o movimento fica uniforme.

> Em um painel de 144 Hz seria o contrário: aí dá para travar 60 com vsync
> ligado e não ter tearing. A regra: **vsync ligado só quando você atinge o
> refresh rate**.

### `cl_capfps=true` — não usar

A ideia é boa em teoria: em vez de gastar CPU girando à espera do próximo
frame, dormir o tempo restante. No GZDoom 4.11 na prática derrubou para
**35 FPS**.

Vale registrar como armadilha: é a "otimização" que parece certa e piora tudo.

### MSAA e reflexo de plano

`gl_multisample=2` (2x MSAA) e `gl_plane_reflection=true` foram desligados junto
com a redução de resolução, então **não há medição isolada dos dois** — só o
efeito combinado. O raciocínio: MSAA multiplica o custo de fragmento em toda a
tela (caro em iGPU) e o FXAA, que já vinha ligado, cobre o antisserrilhado por
uma fração do custo; o reflexo de plano é um passe de cena extra inteiro.

### Throttling térmico — não foi o caso

Hipótese natural para um laptop que esquenta, verificada explicitamente porque
muda a conclusão: se fosse throttling, não haveria ajuste de software que
ajudasse.

- **Clock travado em 1800 MHz** durante o gameplay. As amostras de 400 MHz no
  log são medições ociosas entre rajadas, não o jogo rodando devagar.
- **Correlação FPS × temperatura = -0.19** — praticamente nula.
- A temperatura sobe de 61 para 76 °C, mas o FPS **não** acompanha: cai uma
  vez, em ~24 s (entrada na cena), e depois fica estável entre 47 e 52.

Se fosse térmica, o FPS cairia de forma contínua conforme a temperatura
subisse. Não cai. Os ~50 FPS são o teto de preenchimento real da Vega 8 nessa
cena.

### FPS da CPU no preset original

Um detalhe que mudou a leitura do problema: com o preset original a 1080p, a
GPU estava em 87–90% e a CPU entre 7 e 13%. A CPU **não** era gargalo, então
otimizar ZScript, texturas ou lógica não renderia nada. Todo o ajuste tinha de
ser de GPU — baixar resolução, cortar passes de fragmento. Isso foi o que
orientou a ordem dos testes.

---

## O que ficou ligado, e por quê

Nem tudo podia ser cortado. O critério foi: **cortar o que só melhora a
nitidez, manter o que constrói o clima.**

| cvar | valor | motivo |
|---|---|---|
| bloom (`gl_bloom_amount`) | ligado, 1.4 | o brilho das lanternas **é** a atmosfera |
| `gl_fxaa` | ligado | antisserrilhado barato depois de desligar o MSAA |
| `gl_light_shadowmap` | ligado, 512 | sombras dão profundidade nos corredores |
| `r_dynlights` | ligado | a lanterna é dynamic light; sem ela o jogo fica plano |
| pós-processamento do mod | ligado | efeito próprio do FNAF Doom |

SSAO e MSAA são nitidez. Bloom, sombra e dynamic light são o jogo.

---

## Reproduzindo

```bash
# 1. log do MangoHud
printf '\nautostart_log=1\noutput_folder=/tmp/mh\nlog_interval=200\n' \
    >> ~/.config/MangoHud/MangoHud.conf

# 2. rode e espere carregar
fnaf-doom --mangohud --log -- -warp 1

# 3. depois de ~30 s, em outro terminal
pkill -f gzdoom.exe
python3 - <<'EOF'
import glob, statistics as st
raw = open(sorted(glob.glob('/tmp/mh/*.csv'))[-1]).read().splitlines()
hdr = raw[2].split(',')
data = [dict(zip(hdr, l.split(','))) for l in raw[3:] if l.strip()]
tail = data[len(data)//2:]
fps = [float(r['fps']) for r in tail]
print(f"mediana={st.median(fps):.1f}  1%low={sorted(fps)[len(fps)//20]:.1f}")
EOF

# 4. limpe
cp /tmp/MangoHud.conf.bak ~/.config/MangoHud/MangoHud.conf
```

Para testar um ajuste pontual sem editar o `.ini`:

```bash
fnaf-doom --log +gl_ssao 1 +cvarlist      # e confira o valor no log
```

Para confirmar que o override da linha de comando venceu o `settings.ini`,
olhe a primeira linha do log:

```bash
grep -m1 '^Resolution:' /tmp/fnaf-doom.log
```

Próximo: [03-cvars.md](03-cvars.md).

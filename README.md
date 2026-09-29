# FNAF Doom no Linux (via Wine) — guia completo

Tutorial de ponta a ponta para fazer o **FNAF Doom** (o total conversion de
Five Nights at Freddy's para GZDoom) rodar **liso** no Linux, incluindo o
diagnóstico dos bugs que impediam o jogo de sequer abrir e o ajuste de
performance medido em GPU integrada.

> **Aviso legal:** este repositório contém **apenas scripts e documentação**.
> Nenhum arquivo do jogo é distribuído aqui. Você precisa ter o
> `fivenightsatfreddys1doom-*.zip` comprado/baixado por conta própria, com a
> pasta `game/` extraída.

---

## Índice

1. [O problema](#o-problema)
2. [Requisitos](#requisitos)
3. [Instalação](#instalação)
4. [Os dois bugs que impediam o jogo de abrir](#os-dois-bugs-que-impediam-o-jogo-de-abrir)
5. [Como foram recuperados os argumentos de lançamento](#como-foram-recuperados-os-argumentos-de-lançamento)
6. [Performance: de 22 para ~50 FPS](#performance-de-22-para-50-fps)
7. [Referência de comandos](#referência-de-comandos)
8. [Ajustes de performance para outros hardware](#ajustes-de-performance-para-outro-hardware)
9. [Solução de problemas](#solução-de-problemas)
10. [Documentação detalhada](#documentação-detalhada)

---

## O problema

O FNAF Doom é distribuído como **build Windows**. A pasta `game/` traz:

```
game/
├── gzdoom.exe        <- GZDoom 4.11.1, PE32+ (x86-64 Windows)
├── FNAFDoom.ipk3     <- o IWAD do mod (iwadinfo.txt, mapinfo, textos)
├── FNAF.pk3          <- ~1 GB de assets
├── wads/FD1/         <- FNAF.wad, FNAF.pk3, install.dat
├── wads/Global/      <- JF.pk3
└── settings.ini
```

E na raiz do zip, o `FDLauncher.exe` — um launcher Qt 32-bit que monta a
linha de comando e chama o `gzdoom.exe`. **Esse launcher é o problema**: ele
não roda nativamente, e o jogo não tem script nenhum para Linux.

Além disso, o `settings.ini` que vem no jogo tem um bug que **impede o GZDoom
de encontrar o IWAD**, e o preset gráfico padrão é pesado demais para GPU
integrada (22 FPS em 1080p numa Vega 8).

A solução é rodar o `gzdoom.exe` dentro do Wine e substituir o launcher por um
script que monta o mesmo comando.

---

## Requisitos

- Linux com **Wine 9+** (testado no Wine 11.18)
- Driver **Mesa** com Vulkan (RADV para AMD, ANV para Intel) — o GZDoom 4.11
  usa Vulkan por padrão
- O jogo já extraído em `~/Downloads/game` (ou aponte com `--dir`)

Verifique sua Vulkan antes de começar:

```bash
vulkaninfo --summary | grep -E 'deviceName|driverName'
```

Saída esperada:

```
deviceName   = AMD Radeon Graphics (RADV RENOIR)
driverName   = radv
```

Se aparecer `llvmpipe` ou `lavapipe`, você está em software — o jogo vai rodar,
mas devagar. `radv`, `amdgpu` ou `nouveau` indicam GPU de verdade.

**Não precisa** de `winetricks`, `vcrun`, `dxvk` ou DXVK. O `gzdoom.exe` linka
o CRT do MSVC estaticamente e o Wine 9+ já traz o loader Vulkan embutido:

```bash
objdump -x gzdoom.exe | grep -i 'DLL Name'
# só system32 do Windows + zmusic.dll (que vem junto no jogo)
```

---

## Instalação

```bash
git clone https://github.com/SEU_USUARIO/fnaf-doom-linux.git
cd fnaf-doom-linux
./scripts/install.sh --dir ~/Downloads/game
```

Depois:

```bash
fnaf-doom
```

Ou procure **FNAF Doom** no menu de aplicações.

O instalador é **idempotente** — pode rodar de novo a qualquer momento. Ele:

1. cria um prefixo Wine **dedicado** em
   `~/.local/share/wineprefixes/fnafdoom` (não encosta no seu `~/.wine`);
2. confere se a Vulkan está de pé;
3. faz backup do `settings.ini` para `settings.ini.orig`, corrige o bug do
   IWAD e aplica o perfil de performance;
4. instala o launcher, o atalho `.desktop` e o ícone.

Para desfazer as mudanças no jogo:

```bash
cp ~/Downloads/game/settings.ini.orig ~/Downloads/game/settings.ini
```

### Diagnóstico rápido

```bash
./scripts/diagnose.sh
```

Verifica SO, driver Vulkan, Wine, prefixo, arquivos do jogo, os dois bugs
conhecidos e a instalação do launcher. Não modifica nada — dá para rodar
qualquer hora, antes ou depois de instalar.

```
==> Graficos / Vulkan
  ok   device: AMD Radeon Graphics (RADV RENOIR)
  ok   driver: radv (GPU real)

==> Configuracao
  ok   IWADSearch.Directories = $PROGDIR (bug do IWAD corrigido)
  ok   resolucao interna: 1280x720
  ok   SSAO: 0

Resumo: 27 ok, 0 avisos, 0 falhas
Tudo certo. Rode:  fnaf-doom
```

---

## Os dois bugs que impediam o jogo de abrir

### Bug 1 — `[IWADSearch.Directories]` vazia

O `settings.ini` original vem assim:

```ini
[IWADSearch.Directories]

[FileSearch.Directories]
```

O problema: essa seção **substitui** a lista padrão de diretórios de busca do
GZDoom em vez de adicionar a ela. Como está vazia, o GZDoom fica sem nenhum
caminho para procurar e, mesmo com `-iwad FNAFDoom.ipk3` na linha de comando,
aborta:

```
**** DIED WITH FATAL ERROR:
Cannot find a game IWAD (doom.wad, doom2.wad, heretic.wad, etc.).
```

Isso é confuso porque o `-iwad` *está* na linha de comando — o GZDoom trata um
`-iwad` sem barra como **nome a ser procurado**, não como caminho, então ele
cai na busca vazia.

**Correção:** colocar o diretório do jogo de volta.

```ini
[IWADSearch.Directories]
Path=$PROGDIR
```

### Bug 2 — o launcher é Windows

`FDLauncher.exe` é um executável de 32 bits para Windows. Não há como
executá-lo nativamente, e rodá-lo pelo Wine seria redundante: ele apenas
monta argumentos e chama o `gzdoom.exe` que já está na mesma pasta.

A solução é fazer isso direto em shell — foi o que motivou o
[`scripts/fnaf-doom`](scripts/fnaf-doom).

---

## Como foram recuperados os argumentos de lançamento

Sem acesso ao código-fonte do launcher, os argumentos foram recuperados
**dos próprios binários**, num processo de três passos. Vale registrar porque
é reaproveitável para outros jogos ports via GZDoom/ZDoom.

### 1. Descobrir o que o launcher carrega

`strings` no `FDLauncher.exe` revela a estrutura de arquivos que ele gerencia:

```bash
strings -n 3 FDLauncher.exe | grep -iE 'gzdoom|-iwad|-file|FNAF|install.dat'
```

```
/game/wads/FD1/install.dat
/game/FNAFDoom.ipk3
/game/gzdoom.exe
```

### 2. Achar os switches, com offsets

Dumping com offset mostra os tokens de linha de comando guardados **em sequência
na tabela de strings** — que é exatamente a ordem em que o launcher os concatena:

```bash
strings -n 2 -t d FDLauncher.exe | awk '{o=$1+0} o>=6331050 && o<=6331420'
```

```
6331076 /game/wads/FD
6331092 /install.dat
6331116 version=
6331128 files=
6331140 |MATERIALS
6331152 |LOWPOLY
6331164 -file
6331172 /game/wads/Global/*
6331192 -iwad
6331200 /game/FNAFDoom.ipk3
6331220 -skill
6331232 -config
6331240 -host
6331248 -map
6331256 +map
6331264 -netmode
6331276 -port
6331284 -join
6331292 +sv_cheats
6331304 /game/gzdoom.exe
```

Duas descobertas imediatas:

- o **IWAD é `FNAFDoom.ipk3`**, não `gzdoom.pk3` (que é carregado
  automaticamente por estar na mesma pasta do executável);
- os arquivos do mod vêm de uma lista lida do **`install.dat`**, com flags
  `|LOWPOLY` e `|MATERIALS`.

### 3. Replicar a lógica do `install.dat`

O `wads/FD1/install.dat` é a fonte de verdade sobre *quais* wads usar:

```
version=4.1.1
files=
[
	FNAF.wad,
	FNAF.pk3,
	FNAF_LowPoly.pk3|LOWPOLY,
]
```

O launcher em shell faz exatamente isso: lê o `install.dat`, adiciona os arquivos
sem flag, adiciona os com flag só se a opção correspondente estiver ligada, e
junta `wads/Global/*`:

```bash
while IFS= read -r raw; do
    raw="${raw//[[:space:]]/}"
    [[ -z $raw || $raw == files=* || $raw == "[" || $raw == "]," || $raw == "]" ]] && continue
    [[ $raw == *, ]] && raw="${raw%,}"
    name="${raw%%|*}"; flag="${raw#*|}"; [[ $flag == "$raw" ]] && flag=""
    case "$flag" in
        LOWPOLY)   [[ -n $LOWPOLY ]] && FILES+=("$FDDIR/$name") ;;
        MATERIALS) [[ -n $MATERIALS ]] && FILES+=("$FDDIR/$name") ;;
        *)         FILES+=("$FDDIR/$name") ;;
    esac
done < <(sed -n '/^files=/,/]/p' "$FDDIR/install.dat")
```

Resultado (confirmado no log do jogo):

```
  adding Z:/home/pedro/Downloads/game/gzdoom.pk3, 672 lumps
  adding Z:/home/pedro/Downloads/game/game_support.pk3, 3307 lumps
  adding ./FNAFDoom.ipk3, 93 lumps
  adding Z:/home/pedro/Downloads/game/game_widescreen_gfx.pk3, 214 lumps
  adding wads/FD1/FNAF.wad, 754 lumps
  adding wads/FD1/FNAF.pk3, 957 lumps
  adding wads/Global/JF.pk3, 202 lumps
```

> `game_support.pk3` e `game_widescreen_gfx.pk3` entram sozinhos: o GZDoom
> autolocta os `.pk3` registrados no `gameinfo.txt` do `gzdoom.pk3` que estejam
> na pasta do executável. **Não** é preciso passá-los no `-file`.

Confira o comando gerado a qualquer momento, sem abrir o jogo:

```bash
fnaf-doom --dry-run
```

---

## Performance: de 22 para ~50 FPS

### Ambiente de teste

| | |
|---|---|
| CPU | AMD Ryzen 5 5625U |
| GPU | AMD Radeon integrada (Vega 8, "RENOIR") |
| RAM | 15 GB (GPU usa RAM compartilhada) |
| SO | CachyOS, kernel 7.2, Mesa 26.2.3 |
| Sessão | Hyprland / Wayland (XWayland) |
| Painel | 1920x1080 **@ 60 Hz**, `scale=1.5` |
| Wine | 11.18 |

### Como foi medido

O GZDoom 4.11 removeu os comandos `benchmark` e `help` deste mod (o ZScript
deles apaga os comandos do console), então a medição usou o log do **MangoHud**:

```bash
# habilita log automatico
printf '\nautostart_log=1\noutput_folder=/tmp/mh\nlog_interval=200\n' \
    >> ~/.config/MangoHud/MangoHud.conf

fnaf-doom --mangohud --log -- -warp 1   # -warp 1 entra direto no E1M1
```

Depois de ~30 s para carregar, analisar o CSV separando o trecho de gameplay
(o começo é a cena simples da intro e dá 60 FPS mesmo no preset original):

```python
import statistics as st
raw = open(csv).read().splitlines()
hdr = raw[2].split(',')                       # linha 1 = SO, linha 2 = cabecalho
data = [dict(zip(hdr, l.split(','))) for l in raw[3:] if l.strip()]
tail = data[len(data)//2:]                   # metade final = gameplay
fps = [float(r['fps']) for r in tail]
print(f"mediana={st.median(fps):.1f}  min={min(fps):.1f}  1%low={sorted(fps)[len(fps)//20]:.1f}")
```

> **Armadilha:** `csv.DictReader` não funciona nesse arquivo — as duas primeiras
> linhas são metadados, não cabeçalho. Sem isso você lê "sem amostras" e conclui
> que o log quebrou.

### Resultados

Mediana de FPS no E1M1 (cena de gameplay), 1280x720 salvo indicado:

| Configuração | FPS | 1% low | Observação |
|---|---:|---:|---|
| 1080p, preset original do mod | **22** | 15 | 2x MSAA + SSAO + bloom + aniso 8x |
| 1600x900, efeitos reduzidos | **36** | 34 | |
| 720p, SSAO on, resto reduzido | **44** | 42 | |
| 1152x648, SSAO off | **49** | 47 | **nenhum ganho** vs 720p |
| 720p, aniso 8x (erro meu) | **45** | 41 | aniso é caro aqui |
| 720p, vsync **on** | **52** | — | spread 47–57: *jitter* |
| 720p, `cl_capfps=true` | **35** | 33 | **pior** |
| **720p, vsync off, preset final** | **~50** | **48–49** | spread 48–53, o mais estável |

### O que realmente custava

1. **SSAO** — o item mais caro. Desligar foi o maior ganho.
2. **Anisotropia 8x** — surpresa: numa GPU com RAM compartilhada, 8x aniso
   custa bandwidth e derrubou de 52 para 45 FPS. 4x é indistinguível na prática.
3. **2x MSAA** — o segundo item mais caro; o FXAA (que já vinha ligado) cobre
   o antisserrilhado por uma fração do custo.
4. **Resolução** — 1080p → 720p foi o maior ganho *absoluto*, mas só até certo
   ponto (ver abaixo).

### Duas conclusões contrárias ao instinto

**Não há throttling térmico.** A suspeita natural quando um laptop esquenta
faz sentido, mas os dados desmentem: o clock ficou travado em 1800 MHz a maior
parte do tempo e a correlação entre temperatura e FPS foi de apenas **-0.19**:

```
  t(s)    fps   gpu%   MHz  gpuC   cpu%
  22.6   60.1     50   200    61    16     <- ainda na cena simples
  25.4   50.8     66  1800    69    14     <- gameplay comeca
  28.2   47.4     76  1800    70    14
  36.6   47.1     78  1800    73    14
  45.0   52.0     77  1800    72     8
  61.8   49.7     78  1800    73     9
```

O FPS cai **uma vez**, junto com a entrada na cena de gameplay, e depois fica
estável. A temperatura acompanha, mas não é a causa. Os ~50 FPS são o teto real
de preenchimento da Vega 8 nessa cena.

**Resolução menor não ajuda mais.** Baixar de 720p para 648p (0.81x de pixels)
não mudou nada (49 vs 50 FPS). A partir de certo ponto o custo deixa de ser
fill-rate e vira fixo — shadowmap, passes de bloom e o overhead de tradução do
Wine. Ou seja: **não adianta baixar de 720p**. Mantenha 720p, que é divisível
por 60 e dá o melhor custo-benefício.

### Sobre vsync

Com vsync **ligado** e FPS abaixo de 60, o resultado é pior que sem: o
*frame pacing* oscila (47–57) e você sente uma pulsação rítmica. Com vsync
**desligado** o spread é de 48–53, bem mais estável. Para painel de 60 Hz com
jogo abaixo de 60 FPS, vsync desligado dá a melhor sensação.

`cl_capfps=true` (tentar dormir até o alvo) derruba para 35 FPS no GZDoom 4.11 —
não use.

### O perfil final

```ini
; video
vid_preferbackend=1                  ; 1 = Vulkan, 2 = OpenGL
vid_fullscreen=true
vid_maxfps=60
vid_vsync=false                      ; vsync com <60 fps gera jitter
cl_capfps=false                      ; true derruba para ~35 fps
vid_scalemode=5                      ; 5 = resolucao custom
vid_scale_customwidth=1280
vid_scale_customheight=720

; efeitos — desligar o caro, manter o que define o clima
gl_multisample=0                     ; sem MSAA 2x
gl_fxaa=1                            ; antisserrilhado barato no lugar
gl_ssao=0                            ; item mais caro
gl_texture_filter_anisotropic=4      ; 8x derruba ~15% dos FPS
gl_plane_reflection=false
gl_light_shadowmap=true
gl_shadowmap_quality=512
gl_bloom=true                        ; essencial pro clima de terror

; idioma
language=ptb
```

> **Sobre `vid_scalemode`:** os valores **não** são documentados e a ordem não é
> óbvia. Medidos empiricamente neste build:

  | valor | resolução obtida | significado |
  |---:|---|---|
  | 0 | 1920x1080 | normal (nativa) |
  | 1 | 711x400 | High DPI |
  | 2 | 640x400 | off |
  | 3 | 960x600 | — |
  | 4 | 1280x800 | — |
  | **5** | **1600x900** (= custom) | **custom** |

  Se a sua versão do GZDoom tiver enumeração diferente, descubra com
  `fnaf-doom --res 1920x1080` e conferindo a linha `Resolution:` do log.

---

## Referência de comandos

```
fnaf-doom                     abre o jogo em tela cheia
fnaf-doom --fd 2              usa o FNAF 2 (padrão: 1)
fnaf-doom --lowpoly           liga os arquivos |LOWPOLY do install.dat
fnaf-doom --res 1600x900      resolução interna (default: 1280x720)
fnaf-doom --opengl            usa OpenGL em vez de Vulkan
fnaf-doom --vsync             liga vsync
fnaf-doom --novsync           desliga vsync
fnaf-doom --ssao on           liga SSAO
fnaf-doom --lang en_US        volta pra inglês
fnaf-doom --mangohud          overlay de FPS
fnaf-doom --log               log em /tmp/fnaf-doom.log
fnaf-doom --dry-run           mostra o comando sem abrir o jogo
fnaf-doom --dir PASTA         usa outro lugar do jogo
fnaf-doom -- -warp 1          argumentos extras vão direto ao GZDoom
```

### Ajustes rápidos de qualidade

```bash
fnaf-doom --res 1600x900    # mais nítido, ~36 fps
fnaf-doom --ssao on         # melhor visual, ~44 fps em 720p
fnaf-doom --res 1920x1080  # nativo, ~22 fps (o preset original do mod)
```

---

## Ajustes de performance para outro hardware

Meça antes de mexer. O caminho é o mesmo:

```bash
fnaf-doom --mangohud --log -- -warp 1
```

Depois olhe `/tmp/fnaf-doom.log` para `Resolution:` e para o device de vídeo, e
ajuste:

| Situação | Ajuste |
|---|---|
| GPU dedicada moderna | dá para ligar tudo: `--ssao on`, MSAA de volta no menu, 1080p+ |
| iGPU AMD (Vega / Renoir / RDNA) | o perfil deste repo é 720p + SSAO off + aniso 4 |
| iGPU Intel | comece em `--res 1280x720 --ssao off`; iGPU Intel costuma ser mais fraca em fill-rate |
| 8 GB de RAM | feche o resto; o `FNAF.pk3` descomprimido passa de 1 GB |
| Rodando em VM / sem GPU | `vulkaninfo` vai mostrar `llvmpipe`; espere poucos FPS |

Para trocar permanently, edite `settings.ini` com o editor de texto do GZDoom
(menu → Opções) ou à mão — o launcher lê esse arquivo a cada execução.

---

## Solução de problemas

**`Cannot find a game IWAD`**
O bug 1 voltou, provavelmente porque o `settings.ini` foi sobrescrito. Rode
`./scripts/install.sh` de novo, ou confira se tem:

```ini
[IWADSearch.Directories]
Path=$PROGDIR
```

**Jogo abre mas a tela fica preta**
Quase sempre é Vulkan. Teste com `fnaf-doom --opengl`. Se funcionar, o
problema é o driver — atualize o Mesa.

**Sem som**
O GZDoom usa a `openal32.dll` que já vem na pasta do jogo. Se não houver
áudio, confira se o PulseAudio/PipeWire está rodando e se o prefixo tem
`libsndfile-1.dll` (vem junto).

**FPS muito abaixo do esperado**
Veja qual backend está em uso no log:

```bash
grep -E '^Vulkan device:|GL_RENDERER:' /tmp/fnaf-doom.log
```

Se aparecer `llvmpipe` ou `lavapipe`, você está em renderização por software.

**A tela não sai de 1080p depois de mudar a resolução**
Confira a linha `Resolution:` do log. Se não mudou, o `vid_scalemode` da sua
versão do GZDoom tem outro valor para "custom" — use `fnaf-doom --res WxH`
(que passa os três cvars via linha de comando, sem depender do `settings.ini`).

**Desinstalar**

```bash
rm -f ~/.local/bin/fnaf-doom
rm -f ~/.local/share/applications/fnaf-doom.desktop
rm -f ~/.local/share/icons/hicolor/256x256/apps/fnaf-doom.png
rm -rf ~/.local/share/wineprefixes/fnafdoom
cp ~/Downloads/game/settings.ini.orig ~/Downloads/game/settings.ini
```

---

## Documentação detalhada

| Arquivo | Conteúdo |
|---|---|
| [`docs/01-diagnostico.md`](docs/01-diagnostico.md) | Reverse engineering do `FDLauncher.exe`, descoberta dos CVars, anatomia do bug do IWAD |
| [`docs/02-performance.md`](docs/02-performance.md) | Metodologia de medição, dados brutos, análise de cada ajuste |
| [`docs/03-cvars.md`](docs/03-cvars.md) | Referência dos CVars relevantes e como descobrir outros |
| [`scripts/diagnose.sh`](scripts/diagnose.sh) | Diagnóstico automático do ambiente e da instalação |

---

## Créditos

- **FNAF Doom** — conceito e recursos por *Zeekerss* / Scott Cawthon
- **GZDoom** 4.11.1 — motor
- **FDLauncher** — o launcher original (Windows)
- **Wine** — camada de compatibilidade
- **Mesa/RADV** — drivers gráficos
- **MangoHud** — overlay e log de FPS

Este guia é um projeto pessoal e não tem vínculo oficial com os autores do jogo.
Siga as regras de distribuição do FNAF Doom e do GZDoom.
